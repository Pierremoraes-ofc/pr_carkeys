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

local function playSound(vehicle, soundId)
    if not GetResourceState("pr_3dsound"):find("start") then return end
    local c = GetEntityCoords(vehicle)
    -- pr_3dsound deve ser chamado no SERVER via exports; aqui delegamos ao server.
    TriggerServerEvent("pr_carkeys:server:playLockSound",
        { x = c.x, y = c.y, z = c.z },
        soundId or Config.Sound.soundDefault
    )
end

function VehicleLock:IsPolice()
    if not Config.Police or not Config.Police.enabled then return false end
    local fw = PRCarkeys.ActiveResource
    if fw == "qb-core" or fw == "qbx-core" then
        local pd = exports["qb-core"]:GetCoreObject().Functions.GetPlayerData()
        local jobName = pd and pd.job and pd.job.name
        for _, job in ipairs(Config.Police.jobs) do
            if jobName == job then return true end
        end
    elseif fw == "es_extended" then
        local xPlayer = exports["es_extended"]:getSharedObject().GetPlayerData()
        local jobName = xPlayer and xPlayer.job and xPlayer.job.name
        for _, job in ipairs(Config.Police.jobs) do
            if jobName == job then return true end
        end
    elseif fw == "ox_core" then
        local groups = exports["ox_core"]:GetPlayerData().groups or {}
        for _, job in ipairs(Config.Police.jobs) do
            if groups[job] then return true end
        end
    end
    return false
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

        for p, data in pairs(VehicleState.permanentKeys) do
            local dist = data.distance or Config.Default.UseKeyAnim.DefaultDistance
            local veh  = PRCarkeys.FindVehicleByPlate(p, dist)
            if veh then
                local d = #(playerPos - GetEntityCoords(veh))
                if d < bestDist then
                    bestDist = d; bestVeh = veh; bestPlate = p; bestData = data
                end
            end
        end

        if not bestVeh then
            for p, _ in pairs(VehicleState.temporaryKeys) do
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
        local hasAccess = lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
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
        if keyData and keyData.motor then

            --  Faz o efeito de motor ligando sozinho 'rev engine'
            --  Pai é brabo demais 
            CreateThread(function()
                local pedModel = joaat("a_m_y_business_01")
                RequestModel(pedModel)
                local t = 0
                while not HasModelLoaded(pedModel) and t < 2000 do Wait(10); t = t + 10 end
                if not HasModelLoaded(pedModel) then return end
                local vCoords = GetEntityCoords(vehicle)
                local ped = CreatePed(4, pedModel, vCoords.x, vCoords.y, vCoords.z, 0.0, false, true)
                if not DoesEntityExist(ped) then SetModelAsNoLongerNeeded(pedModel); return end
                SetEntityVisible(ped, false, false)
                SetEntityCollision(ped, false, false)
                SetPedCanBeTargetted(ped, false)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedRagdollOnCollision(ped, false)
                SetPedIntoVehicle(ped, vehicle, -1)
                
                local isEngineRunning = GetIsVehicleEngineRunning(vehicle)
                SetVehicleEngineOn(vehicle, not isEngineRunning, false, true)

                Wait(2000)
                DeletePed(ped)
            end)

            --  mantém o motor ligado após ter entrado no carro!
            CreateThread(function()
                Debug("INFO", "[VehicleLock] Aguardando entrar no veículo...")            
                while true do
                    Wait(500)            
                    local ped = PlayerPedId()
                    local vehiPlayer = GetVehiclePedIsIn(cache.ped, false)    

                    if vehiPlayer ~= 0 and DoesEntityExist(vehiPlayer) then 
                        toggleEngine()                  
                        VehicleState.isEngineRunning = true
                        local myPlate = Trim(GetVehicleNumberPlateText(vehicle))
                        local playerPlate = Trim(GetVehicleNumberPlateText(vehiPlayer))            
                        Debug("INFO", ("[VehicleLock] Meu: %s | Player: %s"):format(myPlate, playerPlate))            
                        if myPlate ~= playerPlate then

                            SetVehicleEngineOn(vehicle, false, false, false)
                            Debug("INFO", ("[VehicleLock] Veículos diferentes! %s | %s"):format(myPlate, playerPlate))
                            -- preciso fazer uma condicional para bloquear isso!
                            break -- 🔥 para o loop após confirmar
                        end
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
    local hasAccess = lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
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
