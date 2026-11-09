-- O PR Carkeys controla apenas ligado/desligado. Nao altera RPM, acelerador,
-- freio, rodas, velocidade ou tarefas de direcao do player.
local LEAVE_ENGINE_ON_PED_FLAG = 241
local DISABLE_AUTO_START_PED_FLAG = 429

local function setPedEngineFlags(blockAutomaticStart)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    -- A saida do veiculo nao usa uma tarefa especial do ped.
    SetPedConfigFlag(ped, LEAVE_ENGINE_ON_PED_FLAG, false)
    -- W nunca pode dar partida. A partida explicita e feita somente pelo Z.
    SetPedConfigFlag(ped, DISABLE_AUTO_START_PED_FLAG, blockAutomaticStart == true)
end

function PRCarkeys.BlockAutomaticEngineStart()
    setPedEngineFlags(true)
end

function PRCarkeys.ResetPedEngineFlags()
    setPedEngineFlags(false)
end

function PRCarkeys.SuspendIgnitionPersistence()
    PRCarkeys.BlockAutomaticEngineStart()
end

function PRCarkeys.MaintainIgnitionEngine(vehicle)
    local ped = PlayerPedId()
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
        or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return false
    end

    PRCarkeys.BlockAutomaticEngineStart()
    return GetIsVehicleEngineRunning(vehicle)
end

-- Executada uma unica vez depois que o cache confirma que o player saiu.
-- Replica a logica simples solicitada: se ainda estava ligado, mantenha ligado.
function PRCarkeys.PreserveRunningEngineAfterExit(vehicle, wasRunning)
    if not Config.KeyInVehicle or Config.KeyInVehicle.keepVehicleEngineOn ~= true then
        print("[PRK-debug] bloqueado: Config.KeyInVehicle.keepVehicleEngineOn nao esta true")
        return false
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        print("[PRK-debug] bloqueado: veiculo invalido/nao existe")
        return false
    end
    if PRCarkeys.manualEngineOffVehicle == vehicle then
        print("[PRK-debug] bloqueado: manualEngineOffVehicle esta setado para este veiculo")
        return false
    end
    if not wasRunning then
        print("[PRK-debug] bloqueado: wasRunning chegou false")
        return false
    end

    if not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local deadline = GetGameTimer() + 500
        while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
            Wait(0)
        end
    end
    if not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then
        print("[PRK-debug] bloqueado: nao conseguiu controle de rede do veiculo")
        return false
    end

    print("[PRK-debug] chegou ate o SetVehicleEngineOn, aplicando...")
    SetVehicleEngineOn(vehicle, true, false, true)
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        PRCarkeys.ResetPedEngineFlags()
    end
end)
