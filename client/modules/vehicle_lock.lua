-- ----------------------------------------------------------------
--   pr_carkeys — client/modules/vehicle_lock.lua
-- ----------------------------------------------------------------

local VehicleState = assert(
    PRCarkeys.VehicleState,
    "[pr_carkeys] VehicleState deve ser carregado antes do VehicleLock"
)

local VehicleLock = {}

local VehicleStateBags = assert(
    pr_lib and pr_lib.fivem and pr_lib.fivem.vehicleState and pr_lib.fivem.vehicleState.raw,
    "[pr_carkeys] pr_bridge vehicleState indisponivel"
)

local function getVehicleState(vehicle, key)
    return VehicleStateBags.get(vehicle, key)
end

local function setVehicleState(vehicle, key, value)
    local options = { replicated = true, authority = "owner" }
    if value == nil then return VehicleStateBags.remove(vehicle, key, options) end
    return VehicleStateBags.set(vehicle, key, value, options)
end

VehicleStateBags.watchAny("doorslockstate", function(value, _, _, vehicle)
    value = tonumber(value)
    if not value or value < 0 or value > 7 or not DoesEntityExist(vehicle) then return end

    local locked = value ~= 0 and value ~= 1
    SetVehicleDoorsLocked(vehicle, value)
    SetVehicleDoorsLockedForAllPlayers(vehicle, locked)
    if not locked then SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false) end
end)

local function flashLights(vehicle)
    CreateThread(function()
        SetVehicleLights(vehicle, 2); Wait(250)
        SetVehicleLights(vehicle, 1); Wait(200)
        SetVehicleLights(vehicle, 0)
    end)
end

local function Trim(v)
    return v:gsub("^%s*(.-)%s*$", "%1")
end

local function keySnapshot(source)
    local keys = {}
    if type(source) ~= "table" then return keys end

    local lastKey = nil
    while true do
        local ok, key = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        keys[#keys + 1] = key
        lastKey = key
    end

    return keys
end

local function playSound(vehicle, soundId)
    if not GetResourceState("pr_3dsound"):find("start") then return end
    local c = GetEntityCoords(vehicle)
    -- pr_3dsound deve ser chamado no SERVER via exports; aqui delegamos ao server.
    TriggerServerEvent("pr_carkeys:server:playLockSound",
        { x = c.x, y = c.y, z = c.z },
        soundId or Config.Sound.soundDefault
    )
end

local function emitLockChanged(vehicle, plate, lockState)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    TriggerEvent("pr_carkeys:client:vehicleLockChanged", {
        vehicle = vehicle,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        lockState = lockState,
        unlocked = lockState == 1 or lockState == 0
    })
end

local function emitRevEngineState(vehicle, plate, active)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    TriggerEvent("pr_carkeys:client:revEngineState", {
        vehicle = vehicle,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        active = active == true
    })
end

local function requestVehicleControl(vehicle, timeoutMs)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if NetworkHasControlOfEntity(vehicle) then return true end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 and netId ~= 65533 then
        SetNetworkIdCanMigrate(netId, true)
    end

    local deadline = GetGameTimer() + (timeoutMs or 750)
    NetworkRequestControlOfEntity(vehicle)
    while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(vehicle)
        Wait(0)
    end

    return DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle)
end

local function ensureEngineRunningAfterUnlock(vehicle, plate, revision)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if PRCarkeys.engineTransitionVehicle or revision ~= PRCarkeys.engineAccessRevision then return end
    local allowed = pr_lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
    if not allowed or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId()
        or PRCarkeys.engineTransitionVehicle or revision ~= PRCarkeys.engineAccessRevision then return end
    VehicleState.hasKey = true
    PRCarkeys.engineAccessRevision = PRCarkeys.engineAccessRevision + 1
    PRCarkeys.engineTransitionVehicle = vehicle
    local ok, running = pcall(PRCarkeys.StartDriverEngine, vehicle, plate)
    PRCarkeys.engineTransitionVehicle = nil
    VehicleState.isEngineRunning = ok and running == true
    if not ok then Debug("ERROR", tostring(running)) end
end

function VehicleLock:StartRemoteEngine(vehicle, plate)
    local ped, frozen, handbrake
    local model = joaat("a_m_y_business_01")
    local ok, err = xpcall(function()
        if not requestVehicleControl(vehicle, 2000) then error("sem controle do veiculo") end
        emitRevEngineState(vehicle, plate, true)
        if GetPedInVehicleSeat(vehicle, -1) ~= 0 or GetEntitySpeed(vehicle) >= 0.5 then return end
        frozen = IsEntityPositionFrozen(vehicle)
        handbrake = type(GetVehicleHandbrake) == "function" and GetVehicleHandbrake(vehicle) or frozen
        FreezeEntityPosition(vehicle, true)
        SetVehicleHandbrake(vehicle, true)
        SetVehicleBrake(vehicle, true)
        RequestModel(model)
        local deadline = GetGameTimer() + 2000
        while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
        if not HasModelLoaded(model) then error("modelo do NPC indisponivel") end
        if not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= 0 then return end
        local coords = GetEntityCoords(vehicle)
        ped = CreatePed(4, model, coords.x, coords.y, coords.z, 0.0, false, true)
        if not DoesEntityExist(ped) then error("falha ao criar NPC") end
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetPedCanBeTargetted(ped, false)
        SetPedCanBeDraggedOut(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedIntoVehicle(ped, vehicle, -1)
        deadline = GetGameTimer() + 1000
        while GetPedInVehicleSeat(vehicle, -1) ~= ped and GetGameTimer() < deadline do Wait(10) end
        if GetPedInVehicleSeat(vehicle, -1) ~= ped then error("NPC nao ocupou o banco") end
        -- Start only after seating; never toggle an already running engine off.
        PRCarkeys.SetEngineState(vehicle, true, false, true, "remote_npc_start")
        local engineDeadline = GetGameTimer() + 3000
        while not GetIsVehicleEngineRunning(vehicle) and GetGameTimer() < engineDeadline do Wait(50) end
        if not GetIsVehicleEngineRunning(vehicle) then error("motor nao iniciou") end
        Wait(Config.Default.RevEngineSeatHoldMs or 1500)
    end, debug.traceback)
    if ped and DoesEntityExist(ped) then
        SetPedKeepTask(ped, false)
        ClearPedTasksImmediately(ped)
        DeletePed(ped)
    end
    SetModelAsNoLongerNeeded(model)
    if DoesEntityExist(vehicle) then
        if frozen ~= nil then
            SetVehicleBrake(vehicle, false)
            SetVehicleHandbrake(vehicle, handbrake == true)
            FreezeEntityPosition(vehicle, frozen)
        end
        setVehicleState(vehicle, 'pr_carkeys_revving', nil)
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
        TriggerServerEvent("pr_carkeys:server:setVehicleLockState", NetworkGetNetworkIdFromEntity(vehicle), 1, plate)
        emitLockChanged(vehicle, plate, 1)
        emitRevEngineState(vehicle, plate, false)
    end
    if not ok then Debug("WARNING", "Partida remota: " .. tostring(err)) end
end

function VehicleLock:IsPolice()
    return Bridge.framework.isPolice() == true
end

function VehicleLock:Toggle()
    local vehicle = nil
    local plate   = nil
    local keyData = nil

    if VehicleState.currentVehicle ~= 0 then
        vehicle = VehicleState.currentVehicle
        plate   = VehicleState.currentPlate
        keyData = plate and VehicleState:GetKeyData(plate)
    else
        -- Fora do carro: busca pela placa mais próxima que o player possui
        local playerPos = GetEntityCoords(cache.ped)
        local bestVeh, bestDist, bestPlate, bestData = nil, math.huge, nil, nil

        local permanentPlates = keySnapshot(VehicleState.permanentKeys)
        for i = 1, #permanentPlates do
            local p = permanentPlates[i]
            local data = VehicleState.permanentKeys[p]
            if data then
                local dist = math.min(tonumber(data.distance) or Config.Default.UseKeyAnim.DefaultDistance, Config.Default.MaxSignalDistance or 50)
                local veh  = PRCarkeys.FindVehicleByPlate(p, dist)
                if veh then
                    local d = #(playerPos - GetEntityCoords(veh))
                    if d < bestDist then
                        bestDist = d; bestVeh = veh; bestPlate = p; bestData = data
                    end
                end
            end
        end

        if not bestVeh then
            local temporaryPlates = keySnapshot(VehicleState.temporaryKeys)
            for i = 1, #temporaryPlates do
                local p = temporaryPlates[i]
                local veh = PRCarkeys.FindVehicleByPlate(p, Config.Default.UseKeyAnim.DefaultDistance)
                if veh then
                    local d = #(playerPos - GetEntityCoords(veh))
                    if d < bestDist then
                        bestDist = d; bestVeh = veh; bestPlate = p; bestData = nil
                    end
                end
            end
        end

        vehicle = bestVeh; plate = bestPlate; keyData = bestData
    end

    if not vehicle or not DoesEntityExist(vehicle) then
        PRCarkeys.Notify(Config.Notify.vehicleNotFound)
        return
    end

    if getVehicleState(vehicle, "pr_carkeys_revving") then return end

    if not plate then
        PRCarkeys.Notify(Config.Notify.noPermission)
        return
    end

    -- Consulta o servidor se realmente tem a chave no inventário AGORA
    -- Bloqueia o toggle até receber resposta (evita cache desatualizado)
    if not self:IsPolice() then
        local hasAccess = pr_lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
        if not hasAccess then
            -- Força rebuild do inventário para corrigir estado local
            VehicleState:RebuildFromInventory()
            PRCarkeys.Notify(Config.Notify.noPermission)
            return
        end
    end

    local isRemote = VehicleState.currentVehicle == 0
    if isRemote then
        local anim = Config.Default.UseKeyAnim
        lib.requestAnimDict(anim.dict)
        TaskPlayAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag, 0, false, false, false)
        Wait(anim.waitTime or 500)
        StopAnimTask(cache.ped, anim.dict, anim.clip, 1.0)
    end

    if PRCarkeys.engineTransitionVehicle then return end
    PRCarkeys.engineAccessRevision = PRCarkeys.engineAccessRevision + 1
    local unlockRevision = PRCarkeys.engineAccessRevision
    local lockStatus = tonumber(getVehicleState(vehicle, "doorslockstate"))
        or GetVehicleDoorLockStatus(vehicle)
    local newState   = (lockStatus == 1) and 2 or 1
    local locking    = (newState == 2)

    local revStart = not locking and keyData and keyData.motor
        and Config.Default.RevEngineEffect ~= false
        and not GetIsVehicleEngineRunning(vehicle)
        and GetPedInVehicleSeat(vehicle, -1) == 0 and GetEntitySpeed(vehicle) < 0.5
    local appliedLock = revStart and 2 or newState
    if revStart then setVehicleState(vehicle, 'pr_carkeys_revving', true) end
    SetVehicleDoorsLocked(vehicle, appliedLock)
    SetVehicleDoorsLockedForAllPlayers(vehicle, appliedLock == 2)
    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), appliedLock == 2)
    emitLockChanged(vehicle, plate, appliedLock)
    TriggerServerEvent("pr_carkeys:server:setVehicleLockState",
        NetworkGetNetworkIdFromEntity(vehicle), appliedLock, plate)

    local soundId = keyData and keyData.sound or Config.Sound.soundDefault
    playSound(vehicle, soundId)
    flashLights(vehicle)

    if locking then
        if keyData and keyData.motor then
            setVehicleState(vehicle, "pr_carkeys_ignition", false)
            PRCarkeys.SetEngineState(vehicle, false, true, true, "remote_lock_stop")
            VehicleState.isEngineRunning = false
        end
        PRCarkeys.Notify(Config.Notify.keyLocked)
    else
        SetVehicleUndriveable(vehicle, false)
        if not revStart then
            SetVehicleDoorsLocked(vehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(vehicle, false)
            SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
        end

        if keyData and keyData.motor then
            if revStart then
                CreateThread(function() VehicleLock:StartRemoteEngine(vehicle, plate) end)
            end


            -- Stop waiting when another vehicle is entered; never switch that engine off.
            CreateThread(function()
                local deadline = GetGameTimer() + 120000
                while DoesEntityExist(vehicle) and GetGameTimer() < deadline and unlockRevision == PRCarkeys.engineAccessRevision do
                    Wait(250)
                    local current = GetVehiclePedIsIn(cache.ped, false)
                    if current ~= 0 then
                        if current == vehicle and GetPedInVehicleSeat(current, -1) == cache.ped then
                            ensureEngineRunningAfterUnlock(current, PRCarkeys.GetVehicleKeyPlate(current), unlockRevision)
                        end
                        return
                    end
                end
            end)
        end
        PRCarkeys.Notify(Config.Notify.keyUsed)
    end

    if isRemote then ClearPedTasks(cache.ped) end
end


RegisterCommand("togglelocks", function()
    VehicleLock:Toggle()
end, false)

RegisterKeyMapping("togglelocks", "Trancar/Destrancar Veículo", "keyboard",
    Config.Default.LockKey or "L")

-- Serialize key presses across the server callback; one press performs one action.
local engineToggleBusy = false
function toggleEngine()
    if engineToggleBusy or PRCarkeys.engineTransitionVehicle then return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return end
    local plate = PRCarkeys.GetVehicleKeyPlate(vehicle)
    if not plate then return end
    -- Capture the requested action at the press, before any callback yields.
    local state = Entity(vehicle).state
    local stopping = GetIsVehicleEngineRunning(vehicle) or PRCarkeys.pendingKeyReturnVehicle == vehicle
        or (state.pr_carkeys_keyInIgnition == true and state.pr_carkeys_ignition == false)
    engineToggleBusy = true
    PRCarkeys.engineAccessRevision = PRCarkeys.engineAccessRevision + 1
    local revision = PRCarkeys.engineAccessRevision
    PRCarkeys.engineTransitionVehicle = vehicle
    local ok, err = xpcall(function()
        if stopping then
            PRCarkeys.StopDriverEngine(vehicle, plate)
            return
        end
        local hasAccess = pr_lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
        if revision ~= PRCarkeys.engineAccessRevision or not DoesEntityExist(vehicle)
            or GetVehiclePedIsIn(PlayerPedId(), false) ~= vehicle
            or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return end
        if not hasAccess then
            VehicleState.hasKey = false
            PRCarkeys.Notify(Config.Notify.noPermission)
            return
        end
        VehicleState.hasKey = true
        VehicleState.isEngineRunning = PRCarkeys.StartDriverEngine(vehicle, plate)
    end, debug.traceback)
    PRCarkeys.engineTransitionVehicle = nil
    engineToggleBusy = false
    if not ok then
        print("[pr_carkeys] Falha no comando de ignicao: " .. tostring(err))
        PRCarkeys.Notify({title = "Motor", description = "Nao foi possivel concluir a operacao da ignicao.", type = "error"})
    end
end

RegisterCommand("pr_carkeys_ignition", function()
    toggleEngine()
end, false)

RegisterKeyMapping("pr_carkeys_ignition", "Ligar/Desligar Motor", "keyboard",
    Config.Default.EngineKey or "Z")

PRCarkeys.VehicleLock = VehicleLock

return VehicleLock

