-- All engine writes in pr_carkeys pass here; this never touches RPM or physics.
PRCarkeys.engineAccessRevision = 0
PRCarkeys.engineTransitionVehicle = nil
local traceVehicle, traceGeneration, lastEngineWrite = nil, 0, "none"

function PRCarkeys.SetEngineState(vehicle, enabled, instantly, _disableAutoStart, reason)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    Debug("INFO", ("[Engine] %s | vehicle=%s | requested=%s | before=%s"):format(
        reason or "unspecified", tostring(vehicle), tostring(enabled), tostring(GetIsVehicleEngineRunning(vehicle))))
    if traceVehicle == vehicle then lastEngineWrite = (reason or "unspecified") .. ":" .. tostring(enabled) end
    if enabled then
        if PRCarkeys.manualEngineOffVehicle == vehicle then PRCarkeys.manualEngineOffVehicle = nil end
        PRCarkeys.BlockAutomaticEngineStart()
    else
        PRCarkeys.manualEngineOffVehicle = vehicle
        PRCarkeys.SuspendIgnitionPersistence(vehicle)
    end
    -- A quarta booleana fica sempre true: W nao pode iniciar o motor.
    SetVehicleEngineOn(vehicle, enabled, instantly, true)
    return true
end

-- Native engine flags need not change in the same frame as the start request.
function PRCarkeys.StartDriverEngine(vehicle, plate)
    local revision = PRCarkeys.engineAccessRevision
    if not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return false end
    if not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local controlDeadline = GetGameTimer() + 1000
        while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle)
            and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() and GetGameTimer() < controlDeadline and revision == PRCarkeys.engineAccessRevision do
            Wait(0)
        end
    end
    if revision ~= PRCarkeys.engineAccessRevision or not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle)
        or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return false end

    PRCarkeys.BlockAutomaticEngineStart()
    if not GetIsVehicleEngineRunning(vehicle) then
        PRCarkeys.SetEngineState(vehicle, true, true, false, "authorized_start")
    end
    local deadline = GetGameTimer() + 3000
    while DoesEntityExist(vehicle) and not GetIsVehicleEngineRunning(vehicle)
        and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() and GetGameTimer() < deadline and revision == PRCarkeys.engineAccessRevision do
        Wait(0)
    end
    if revision ~= PRCarkeys.engineAccessRevision or not DoesEntityExist(vehicle) then return false end
    if not GetIsVehicleEngineRunning(vehicle) then
        print(("[pr_carkeys] Partida nao confirmada | plate=%s | fuel=%s | health=%s | driveable=%s"):format(
            tostring(plate), tostring(GetVehicleFuelLevel(vehicle)), tostring(GetVehicleEngineHealth(vehicle)),
            tostring(IsVehicleDriveable(vehicle, false))))
        return false
    end
    if GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return false end
    if PRCarkeys.manualEngineOffVehicle == vehicle then PRCarkeys.manualEngineOffVehicle = nil end
    if not PRCarkeys.OnEngineStarted(vehicle, plate) then
        PRCarkeys.SetEngineState(vehicle, false, true, true, "key_transfer_failed")
        return false
    end
    PRCarkeys.MaintainIgnitionEngine(vehicle)
    return true
end

-- A manual stop never depends on finding the key in the player's inventory:
-- it may already be held in the server ignition record.
function PRCarkeys.StopDriverEngine(vehicle, plate)
    local ped = PlayerPedId()
    if not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    NetworkRequestControlOfEntity(vehicle)
    local deadline = GetGameTimer() + 1000
    while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do Wait(0) end
    if not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle)
        or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end

    -- Bloqueia a partida automatica antes de desligar. Nenhum controle de
    -- aceleracao, RPM, freio ou movimento e aplicado aqui.
    PRCarkeys.BlockAutomaticEngineStart()
    PRCarkeys.SetEngineState(vehicle, false, true, true, "manual_stop")
    Entity(vehicle).state:set("pr_carkeys_ignition", false, true)
    PRCarkeys.VehicleState.isEngineRunning = false
    PRCarkeys.pendingKeyReturnVehicle = vehicle
    if not PRCarkeys.OnEngineStopped(vehicle, plate) then return false end
    PRCarkeys.pendingKeyReturnVehicle = nil

    -- O callback acima cede a execucao ao servidor. GTA ou outro listener pode
    -- tentar a partida automatica nesse intervalo; confirme o desligamento
    -- somente depois que a devolucao da chave terminou.
    if DoesEntityExist(vehicle) then
        PRCarkeys.BlockAutomaticEngineStart()
        PRCarkeys.SetEngineState(vehicle, false, true, true, "manual_stop_confirm")
    end

    local stableOffSince = nil
    deadline = GetGameTimer() + 1500
    while DoesEntityExist(vehicle) and GetGameTimer() < deadline do
        if GetIsVehicleEngineRunning(vehicle) then
            stableOffSince = nil
        else
            stableOffSince = stableOffSince or GetGameTimer()
            if GetGameTimer() - stableOffSince >= 300 then break end
        end
        Wait(0)
    end

    if not DoesEntityExist(vehicle) or GetIsVehicleEngineRunning(vehicle) then
        PRCarkeys.Notify({title = "Motor", type = "error", description = "A chave foi devolvida, mas outro controle manteve o motor ligado."})
        return false
    end

    return true
end

-- Opt-in, read-only capture. Never changes engine, throttle, brake or RPM.
RegisterCommand("pr_engine_trace", function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        print("[pr_carkeys:trace] Entre no veiculo e execute pr_engine_trace antes de sair.")
        return
    end
    traceGeneration = traceGeneration + 1
    local generation, model = traceGeneration, GetEntityModel(vehicle)
    traceVehicle, lastEngineWrite = vehicle, "none"
    print("[pr_carkeys:trace] Captura por 30 segundos. Pare e saia do veiculo para reproduzir.")
    local function read(native, ...)
        if type(native) ~= "function" then return "n/a" end
        local ok, value = pcall(native, ...)
        return ok and tostring(value) or "n/a"
    end
    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        while generation == traceGeneration and DoesEntityExist(vehicle)
            and GetEntityModel(vehicle) == model and GetGameTimer() < deadline do
            print(("[pr_carkeys:trace] driver=%s owner=%s engine=%s rpm=%s throttle=%s speed=%s burnout=%s handbrake=%s frozen=%s lastPRK=%s"):format(
                read(GetPedInVehicleSeat, vehicle, -1), read(NetworkHasControlOfEntity, vehicle),
                read(GetIsVehicleEngineRunning, vehicle), read(GetVehicleCurrentRpm, vehicle),
                read(GetVehicleThrottleOffset, vehicle), read(GetEntitySpeed, vehicle),
                read(IsVehicleInBurnout, vehicle), read(GetVehicleHandbrake, vehicle),
                read(IsEntityPositionFrozen, vehicle), lastEngineWrite))
            Wait(750)
        end
        if generation == traceGeneration then traceVehicle = nil end
    end)
end, false)
