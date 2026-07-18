-- ----------------------------------------------------------------
--   pr_carkeys — client/modules/vehicle_lock.lua
-- ----------------------------------------------------------------

local VehicleState = require 'client.modules.vehicle_state'

local VehicleLock = {}

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

local function ensureEngineRunningAfterUnlock(vehicle, plate)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    VehicleState.hasKey = true
    if not GetIsVehicleEngineRunning(vehicle) then
        SetVehicleEngineOn(vehicle, true, false, true)
        local t = 0
        while not GetIsVehicleEngineRunning(vehicle) and t < 1500 do
            Wait(100)
            t = t + 100
        end

        if GetIsVehicleEngineRunning(vehicle) and plate then
            PRCarkeys.OnEngineStarted(vehicle, plate)
        end
    end

    VehicleState.isEngineRunning = GetIsVehicleEngineRunning(vehicle)
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
                local dist = data.distance or Config.Default.UseKeyAnim.DefaultDistance
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

    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    local newState   = (lockStatus == 1) and 2 or 1
    local locking    = (newState == 2)

    SetVehicleDoorsLocked(vehicle, newState)
    SetVehicleDoorsLockedForAllPlayers(vehicle, newState == 2)
    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), newState == 2)
    emitLockChanged(vehicle, plate, newState)
    TriggerServerEvent("pr_carkeys:server:setVehicleLockState",
        NetworkGetNetworkIdFromEntity(vehicle), newState, plate)

    local soundId = keyData and keyData.sound or Config.Sound.soundDefault
    playSound(vehicle, soundId)
    flashLights(vehicle)

    if locking then
        if keyData and keyData.motor then
            SetVehicleEngineOn(vehicle, false, false, true)
            VehicleState.isEngineRunning = false
        end
        PRCarkeys.Notify(Config.Notify.keyLocked)
    else
        SetVehicleUndriveable(vehicle, false)
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)

        if keyData and keyData.motor then
            if Config.Default.RevEngineEffect ~= false then
                CreateThread(function()
                    if not DoesEntityExist(vehicle) then return end
                    local vehicleState = Entity(vehicle).state
                    local hadSkipRevPed = vehicleState and vehicleState.pr_carkeys_skipRevPed == true
                    vehicleState:set('pr_carkeys_revving', true, true)
                    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
                    emitRevEngineState(vehicle, plate, true)
                    SetVehicleDoorsLocked(vehicle, 6)

                    local pedModel = joaat("a_m_y_business_01")
                    local ped = nil
                    RequestModel(pedModel)
                    local t = 0
                    while not HasModelLoaded(pedModel) and t < 2000 do Wait(10); t = t + 10 end
                    if not HasModelLoaded(pedModel) then vehicleState:set('pr_carkeys_revving', nil, true); emitRevEngineState(vehicle, plate, false); return end
                    if not DoesEntityExist(vehicle) then SetModelAsNoLongerNeeded(pedModel); vehicleState:set('pr_carkeys_revving', nil, true); emitRevEngineState(vehicle, plate, false); return end

                    local currentDriver = GetPedInVehicleSeat(vehicle, -1)
                    if currentDriver ~= 0 and currentDriver ~= cache.ped then
                        SetModelAsNoLongerNeeded(pedModel)
                        vehicleState:set('pr_carkeys_revving', nil, true)
                        emitRevEngineState(vehicle, plate, false)
                        return
                    end

                    local vCoords = GetEntityCoords(vehicle)
                    ped = CreatePed(4, pedModel, vCoords.x, vCoords.y, vCoords.z, 0.0, false, true)
                    if not DoesEntityExist(ped) then
                        SetModelAsNoLongerNeeded(pedModel)
                        vehicleState:set('pr_carkeys_revving', nil, true)
                        emitRevEngineState(vehicle, plate, false)
                        return
                    end
                    SetEntityAsMissionEntity(ped, true, true)
                    SetEntityVisible(ped, false, false)
                    SetEntityAlpha(ped, 50, true)
                    SetEntityCollision(ped, false, false)
                    SetPedCanBeTargetted(ped, false)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedRagdollOnCollision(ped, false)

                    local seat = IsVehicleSeatFree(vehicle, -1) and -1 or (IsVehicleSeatFree(vehicle, 0) and 0 or nil)
                    if seat then
                        SetPedIntoVehicle(ped, vehicle, seat)
                    end
                    
                    local isEngineRunning = GetIsVehicleEngineRunning(vehicle)
                    SetVehicleEngineOn(vehicle, not isEngineRunning, false, true)

                    Wait(Config.Default.RevEngineSeatHoldMs or 850)
                    if ped and DoesEntityExist(ped) then
                        ClearPedTasksImmediately(ped)
                        DeletePed(ped)
                        DeleteEntity(ped)
                        SetVehicleDoorsLocked(vehicle, 1)
                        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
                    end
                    SetModelAsNoLongerNeeded(pedModel)

                    if DoesEntityExist(vehicle) then
                        requestVehicleControl(vehicle, 1000)
                        FreezeEntityPosition(vehicle, false)
                        SetVehicleHandbrake(vehicle, false)
                        SetVehicleUndriveable(vehicle, false)
                        SetVehicleDoorsLocked(vehicle, 1)
                        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
                        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
                        vehicleState:set('pr_carkeys_revving', nil, true)
                        if hadSkipRevPed then
                            vehicleState:set('pr_carkeys_skipRevPed', true, true)
                        end
                        emitRevEngineState(vehicle, plate, false)
                    end
                end)
            end


            --  mantém o motor ligado após ter entrado no carro!
            CreateThread(function()
                Debug("INFO", "[VehicleLock] Aguardando entrar no veículo...")            
                while true do
                    Wait(500)            
                    local ped = PlayerPedId()
                    local vehiPlayer = GetVehiclePedIsIn(cache.ped, false)    

                    if vehiPlayer ~= 0 and DoesEntityExist(vehiPlayer) then 
                        local myPlate = Trim(GetVehicleNumberPlateText(vehicle))
                        local playerPlate = Trim(GetVehicleNumberPlateText(vehiPlayer))            
                        Debug("INFO", ("[VehicleLock] Meu: %s | Player: %s"):format(myPlate, playerPlate))            
                        if myPlate ~= playerPlate then

                            SetVehicleEngineOn(vehicle, false, false, false)
                            Debug("INFO", ("[VehicleLock] Veículos diferentes! %s | %s"):format(myPlate, playerPlate))
                            -- preciso fazer uma condicional para bloquear isso!
                            break -- 🔥 para o loop após confirmar
                        end
                        ensureEngineRunningAfterUnlock(vehiPlayer, playerPlate)
                        break -- 🔥 para o loop após confirmar
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

-- Flag para evitar que OnEngineStopped seja chamado logo após OnEngineStarted
local engineJustStarted = false
function toggleEngine()
    local vehicle = VehicleState.currentVehicle
    if not vehicle or vehicle == 0 then return end
    if cache.seat ~= -1 then return end

    local plate = VehicleState.currentPlate
    if not plate then
        PRCarkeys.Notify(Config.Notify.noPermission)
        return
    end

    -- Validação obrigatória no servidor ANTES de ligar/desligar motor.
    -- Mantém o mesmo padrão de segurança do lock/unlock.
    local hasAccess = pr_lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
    if not hasAccess then
        VehicleState:RebuildFromInventory()
        VehicleState.hasKey = false
        SetVehicleEngineOn(vehicle, false, true, true)
        VehicleState.isEngineRunning = false
        PRCarkeys.Notify(Config.Notify.noPermission)
        return
    end

    VehicleState.hasKey = true

    local engineOn = GetIsVehicleEngineRunning(vehicle)

    if engineOn then
        -- Só desliga se não acabou de ligar (evita race condition)
        if engineJustStarted then return end
        SetVehicleEngineOn(vehicle, false, true, true)
        VehicleState.isEngineRunning = false
        CreateThread(function()
            local t = 0
            while GetIsVehicleEngineRunning(vehicle) and t < 3000 do
                Wait(100); t = t + 100
            end
            if not GetIsVehicleEngineRunning(vehicle) then
                PRCarkeys.OnEngineStopped(vehicle, plate)
            end
        end)
    else
        engineJustStarted = true
        
        local isEngineRunning = GetIsVehicleEngineRunning(vehicle)
        SetVehicleEngineOn(vehicle, not isEngineRunning, false, true)
        --SetVehicleEngineOn(vehicle, true, true, false)
        VehicleState.isEngineRunning = true
        CreateThread(function()
            local t = 0
            while not GetIsVehicleEngineRunning(vehicle) and t < 3000 do
                Wait(100); t = t + 100
            end
            if GetIsVehicleEngineRunning(vehicle) then
                PRCarkeys.OnEngineStarted(vehicle, plate)
            end
            -- Libera o flag após 2s para permitir desligar normalmente
            Wait(2000)
            engineJustStarted = false
        end)
    end
end
RegisterCommand("toggleengine", function()
    toggleEngine()
end, false)

RegisterKeyMapping("toggleengine", "Ligar/Desligar Motor", "keyboard",
    Config.Default.EngineKey or "Z")

return VehicleLock
