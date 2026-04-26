-- ============================================================
--   pr_carkeys — client/cl_keys.lua
--   Uso do item chave (clique de usar no inventário).
--   Travar/Destrancar com dados do banco (distance, sound, motor).
--   O comando "togglelocks" fica em vehicle_lock.lua.
-- ============================================================

local VehicleState = require 'client.modules.vehicle_state'

-- ----------------------------------------------------------------
-- Uso do item chave — disparado pelo server via RegisterUsableItem
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:useKey", function(data)
    local itemName = data.item
    local keyCfg   = Config.KeyTypes[itemName]
    if not keyCfg then return end

    local metadata = Bridge.inventory.GetSlotMetadata(data.slot)

    if not metadata or not metadata.barcode then
        PRCarkeys.Notify(Config.Notify.vehicleNotFound)
        return
    end

    local plate   = metadata.plate
    local vehicle = plate and PRCarkeys.FindVehicleByPlate(
        plate,
        Config.Default.UseKeyAnim.DefaultDistance
    ) or nil

    if vehicle and PRCarkeys.IsVehicleBlacklisted(vehicle) then
        SetVehicleDoorsLocked(vehicle, 1)
        if Bridge.vehicle_key and Bridge.vehicle_key.GiveKeys then
            Bridge.vehicle_key.GiveKeys(vehicle, plate)
        end
        PRCarkeys.Notify(Config.Notify.keyUsed)
        return
    end

    local netId  = vehicle and PRCarkeys.GetVehicleNetId(vehicle) or nil
    local coords = nil
    if vehicle and DoesEntityExist(vehicle) then
        local c = GetEntityCoords(vehicle)
        coords = { x = c.x, y = c.y, z = c.z }
    else
        local c = GetEntityCoords(PlayerPedId())
        coords = { x = c.x, y = c.y, z = c.z }
    end

    TriggerServerEvent("pr_carkeys:server:useKey", metadata.barcode, netId, coords)
end)

-- ----------------------------------------------------------------
-- Servidor autorizou o uso — executar ação no veículo
-- keyData contém dados DO BANCO: distance, sound, motor, plate
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:executeUseKey", function(keyData)
    PRCarkeys.Debug(("executeUseKey | plate=%s | dist=%s | sound=%s | motor=%s")
        :format(tostring(keyData.plate), tostring(keyData.distance),
                tostring(keyData.sound),  tostring(keyData.motor)))

    -- Atualizar dados do banco no VehicleState para esta chave
    if keyData.plate then
        VehicleState:UpdateKeyDbData(keyData.plate, {
            distance = keyData.distance,
            sound    = keyData.sound,
            motor    = keyData.motor,
        })
    end

    -- Buscar veículo usando a distância DO BANCO
    local dist    = keyData.distance or Config.Default.UseKeyAnim.DefaultDistance
    local vehicle = nil
    if keyData.netId and NetworkDoesNetworkIdExist(keyData.netId) then
        vehicle = NetToVeh(keyData.netId)
    end
    if not vehicle or not DoesEntityExist(vehicle) then
        vehicle = PRCarkeys.FindVehicleByPlate(keyData.plate, dist)
    end

    if not vehicle or not DoesEntityExist(vehicle) then
        PRCarkeys.Notify(Config.Notify.vehicleNotFound)
        return
    end

    -- Animação
    local anim = Config.Default.UseKeyAnim
    RequestAnimDict(anim.dict)
    local t = 0
    while not HasAnimDictLoaded(anim.dict) and t < 2000 do
        Wait(50); t = t + 50
    end
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 8.0, -8.0, anim.time, anim.flag, 0, false, false, false)
    Wait(anim.time)
    ClearPedTasks(PlayerPedId())

    local plate      = PRCarkeys.SanitizePlate(keyData.plate)
    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    local locking    = (lockStatus == 1)   -- se está desbloqueado → vai travar
    local newState   = locking and 2 or 1

    -- Aplicar lock localmente e sincronizar no servidor
    SetVehicleDoorsLocked(vehicle, newState)
    TriggerServerEvent("pr_carkeys:server:setVehicleLockState",
        NetworkGetNetworkIdFromEntity(vehicle), newState, plate)

    -- Som via server (pr_3dsound é server-side)
    if GetResourceState("pr_3dsound"):find("start") then
        local c = GetEntityCoords(vehicle)
        TriggerServerEvent("pr_carkeys:server:playLockSound",
            { x = c.x, y = c.y, z = c.z },
            keyData.sound or Config.Sound.soundDefault
        )
    end

    -- Pisca luzes
    CreateThread(function()
        SetVehicleLights(vehicle, 2); Wait(250)
        SetVehicleLights(vehicle, 1); Wait(200)
        SetVehicleLights(vehicle, 0)
    end)

    if locking then
        PRCarkeys.Notify(Config.Notify.keyLocked)
    else
        -- Desbloqueando
        if keyData.motor then
            SetVehicleEngineOn(vehicle, true, true, false)
            PRCarkeys.Notify(Config.Notify.keyUsedEngine)
        else
            PRCarkeys.Notify(Config.Notify.keyUsed)
        end
    end

    -- single_use (modo cronômetro) não é consumida ao usar.
end)

-- ----------------------------------------------------------------
-- Chave expirada
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyExpired", function()
    PRCarkeys.Notify(Config.Notify.keyExpired)
end)

-- ----------------------------------------------------------------
-- Limpar estado ao descarregar
-- ----------------------------------------------------------------
AddEventHandler("QBCore:Client:OnPlayerUnload", function() VehicleState:Reset() end)
AddEventHandler("esx:onPlayerLogout",           function() VehicleState:Reset() end)
AddEventHandler("ox:playerLogout",              function() VehicleState:Reset() end)
