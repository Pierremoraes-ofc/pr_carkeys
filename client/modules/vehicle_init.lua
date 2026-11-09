-- ============================================================
--   pr_carkeys — client/modules/vehicle_init.lua
--   Inicialização reativa via lib.onCache.
-- ============================================================
local lastKnownEngineState = false
local VehicleState = assert(
    PRCarkeys.VehicleState,
    "[pr_carkeys] VehicleState deve ser carregado antes do VehicleInit"
)
local VehicleLock = assert(
    PRCarkeys.VehicleLock,
    "[pr_carkeys] VehicleLock deve ser carregado antes do VehicleInit"
)
local KeyInVehicle = assert(
    PRCarkeys.KeyInVehicle,
    "[pr_carkeys] KeyInVehicle deve ser carregado antes do VehicleInit"
)

local function snapshotTableValues(source)
    local values = {}
    if type(source) ~= "table" then return values end

    local lastKey = nil
    while true do
        local ok, key, value = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        values[#values + 1] = value
        lastKey = key
    end

    return values
end

local function countTableEntries(source)
    local count = 0
    if type(source) ~= "table" then return count end

    local lastKey = nil
    while true do
        local ok, key = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        count = count + 1
        lastKey = key
    end

    return count
end

local function clearDriverHintUI()
    if VehicleState.showHotwireHint then
        lib.hideTextUI()
        VehicleState.showHotwireHint = false
    end
    VehicleState.textUiMode = nil
end

-- Permite que outros módulos (ex: carjack) fechem o hint de hotwire ao conceder a chave.
RegisterNetEvent("pr_carkeys:client:clearDriverHintUI", function()
    clearDriverHintUI()
end)

-- ----------------------------------------------------------------
-- Busca dados do banco para TODAS as chaves de uma vez (após RebuildFromInventory)
-- Precisa estar no topo pois é chamada em vários lugares
-- ----------------------------------------------------------------
local function fetchAllKeyDbData()
    local barcodes = {}
    local keys = snapshotTableValues(VehicleState.permanentKeys)
    for i = 1, #keys do
        local data = keys[i]
        if data.barcode then
            barcodes[#barcodes+1] = data.barcode
        end
    end
    if #barcodes > 0 then
        TriggerServerEvent("pr_carkeys:server:fetchAllKeyDbData", barcodes)
    end
end

-- Busca chaves dentro das bolsas via callback servidor
-- e adiciona ao permanentKeys (bolsas são stashes, inacessíveis pelo client)
local function fetchKeysInBags()
    if ActiveInventory ~= "ox_inventory" then return end
    -- Pequeno wait para garantir que o servidor registrou o callback
    Wait(500)
    local bagKeys = pr_lib.callback.await("pr_carkeys:server:getKeysInBags", false)
    if not bagKeys then return end
    for _, item in ipairs(bagKeys) do
        local meta = item.metadata or {}
        if meta.plate and meta.barcode then
            local plate = PRCarkeys.SanitizePlate(meta.plate)
            if plate and not VehicleState.temporaryKeys[plate] then
                VehicleState.permanentKeys[plate] = {
                    barcode  = meta.barcode,
                    plate    = plate,
                    itemName = item.name,
                    distance = Config.Default.UseKeyAnim.DefaultDistance,
                    sound    = Config.Sound.soundDefault,
                    motor    = false,
                }
            end
        end
    end
    Debug("INFO", ("[VehicleState] Chaves das bolsas carregadas | total permanentes: %d"):format(
        countTableEntries(VehicleState.permanentKeys)
    ))
end

local driverValidationSequence = 0
local lastDrivenVehicle = nil
local function requestDriverValidation(vehicle, plate)
    driverValidationSequence = driverValidationSequence + 1
    TriggerServerEvent("pr_carkeys:server:validateDriverSeat", NetworkGetNetworkIdFromEntity(vehicle), plate,
        driverValidationSequence, PRCarkeys.engineAccessRevision)
end

-- ----------------------------------------------------------------
-- Ao entrar/sair de veículo
-- ----------------------------------------------------------------
lib.onCache("vehicle", function(vehicle, previousVehicle)
    if vehicle then
        VehicleState.currentVehicle  = vehicle
        local plate = PRCarkeys.GetVehicleKeyPlate(vehicle)
        VehicleState.currentPlate    = plate
        VehicleState.isInDriverSeat  = (GetPedInVehicleSeat(vehicle, -1) == cache.ped)
        VehicleState.hasKey          = VehicleState:HasKey(plate)
        VehicleState.isEngineRunning = GetIsVehicleEngineRunning(vehicle)
        VehicleState.hotwireToken    = nil

        -- Bloqueia a partida pelo W tanto com o motor ligado quanto desligado.
        if VehicleState.isInDriverSeat then
            lastDrivenVehicle = vehicle
            PRCarkeys.MaintainIgnitionEngine(vehicle)
        end

        -- Se entrou no banco do motorista sem chave: verifica se há chave no carro
        if not VehicleState.hasKey and VehicleState.isInDriverSeat then
            TriggerServerEvent("pr_carkeys:server:checkKeyInVehicle",
                NetworkGetNetworkIdFromEntity(vehicle), plate)
        end

        -- Buscar dados do banco (distance, sound, motor) para chaves permanentes
        -- Passa o barcode do metadata para encontrar a chave certa no banco
        if VehicleState.hasKey then
            local keyData = VehicleState:GetKeyData(plate)
            local barcode = keyData and keyData.barcode or nil
            TriggerServerEvent("pr_carkeys:server:fetchKeyDbData", plate, barcode)
        end

        if VehicleState.isInDriverSeat then
            lastKnownEngineState = GetIsVehicleEngineRunning(vehicle)
        end
    else
        -- Saiu do veículo
        local exitedVehicle = previousVehicle or lastDrivenVehicle
        if lastDrivenVehicle and exitedVehicle == lastDrivenVehicle and lastKnownEngineState then
            local vehicleToPreserve = exitedVehicle
            CreateThread(function()
                local deadline = GetGameTimer() + 1000
                while DoesEntityExist(vehicleToPreserve) and GetGameTimer() < deadline do
                    PRCarkeys.PreserveRunningEngineAfterExit(vehicleToPreserve, true)
                    Wait(100)
                end
            end)
        end
        lastDrivenVehicle = nil
        PRCarkeys.ResetPedEngineFlags()
        VehicleState.currentVehicle  = 0
        VehicleState.currentPlate    = nil
        VehicleState.isInDriverSeat  = false
        VehicleState.isEngineRunning = false
        VehicleState.hasKey          = false
        VehicleState.hotwireToken    = nil

        clearDriverHintUI()
    end
end)
CreateThread(function()
    local wasInVehicle = false
    local vehicleRef = nil
    local engineWasOn = false

    while true do
        Wait(200)
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            wasInVehicle = true
            vehicleRef = GetVehiclePedIsIn(ped, false)
            engineWasOn = GetIsVehicleEngineRunning(vehicleRef)
        else
            if wasInVehicle and vehicleRef and DoesEntityExist(vehicleRef) and engineWasOn then
                print(("[teste] motor estava ligado antes de sair, engine running agora = %s"):format(tostring(GetIsVehicleEngineRunning(vehicleRef))))
                if not GetIsVehicleEngineRunning(vehicleRef) then
                    SetVehicleEngineOn(vehicleRef, true, false, true)
                    print("[teste] forcei religar")
                end
            end
            wasInVehicle = false
        end
    end
end)
-- ----------------------------------------------------------------
-- Ao mudar de assento
-- ----------------------------------------------------------------
lib.onCache("seat", function(seat)
    if not cache.vehicle or cache.vehicle == 0 then return end
    VehicleState.isInDriverSeat = (seat == -1)

    if seat ~= -1 then
        PRCarkeys.ResetPedEngineFlags()
        clearDriverHintUI()
        return
    end

    -- Entrou no banco do motorista — delega validação ao servidor
    local vehicle = cache.vehicle
    lastDrivenVehicle = vehicle
    local plate   = PRCarkeys.GetVehicleKeyPlate(vehicle)
    VehicleState.currentPlate = plate
    VehicleState.hasKey       = VehicleState:HasKey(plate)

    PRCarkeys.MaintainIgnitionEngine(vehicle)

    -- Aguarda resposta do servidor antes de desligar motor
    -- Evita desligar motor de quem tem chave mas o cache ainda não sincronizou
    requestDriverValidation(vehicle, plate)
end)

-- ----------------------------------------------------------------
-- Resposta da validação do banco do motorista
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:driverSeatValidation", function(result)
    if not result then return end
    if PRCarkeys.engineTransitionVehicle then return end
    if result.requestId ~= driverValidationSequence or result.revision ~= PRCarkeys.engineAccessRevision then return end
    local plate   = result.plate
    local vehicle = VehicleState.currentVehicle
    if not vehicle or vehicle == 0 then return end
    if cache.seat ~= -1 then return end  -- saiu do banco antes de responder
    if not DoesEntityExist(vehicle) then return end
    if PRCarkeys.SanitizePlate(plate) ~= VehicleState.currentPlate then return end
    if result.netId and result.netId ~= NetworkGetNetworkIdFromEntity(vehicle) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return end


    if result.hasAccess then
        VehicleState.hasKey = true
        VehicleState.hotwireToken = nil
        clearDriverHintUI()

        -- Authorized access must never switch off an already running engine.
        -- The temporary key may arrive after this reply during inventory transfer.
        VehicleState.isEngineRunning = GetIsVehicleEngineRunning(vehicle)
        PRCarkeys.MaintainIgnitionEngine(vehicle)
    elseif result.keyAvailable then
        VehicleState.hotwireToken = nil
        -- Há chave no carro disponível para pegar
        if not VehicleState.showHotwireHint then
            lib.showTextUI(Config.KeyInVehicle and Config.KeyInVehicle.pickupLabel or "Chave no carro...", {
                position = "right-center",
                icon     = "key",
            })
            VehicleState.showHotwireHint = true
            VehicleState.textUiMode = "pickup"
        end
    else
        VehicleState.hotwireToken = result.hotwireToken
        -- Sem chave — mantém motor desligado e mostra hint de hotwire
        PRCarkeys.SetEngineState(vehicle, false, true, true, "driver_access_denied")
        if not VehicleState.showHotwireHint then
            lib.showTextUI(Config.Hotwire and Config.Hotwire.hintText or "[H] Ligação direta", {
                position = "right-center",
                icon     = "bolt",
            })
            VehicleState.showHotwireHint = true
            VehicleState.textUiMode = "hotwire"
        end
    end

    -- No per-reply shutdown loop: the engine watchdog handles unauthorized starts.

end)

-- ----------------------------------------------------------------
-- Gerencia chave no carro baseado no estado do motor
-- Chamado explicitamente pelo toggleengine e pelo destrancar com motor=true
-- NÃO usa polling — evita falsos positivos
-- ----------------------------------------------------------------

--- Chamado quando o motor LIGA (Z ou destrancar com motor=true)
--- Remove chave do inventário se estiver lá (permanente OU carkey_temp)
function PRCarkeys.OnEngineStarted(vehicle, plate)
    if not Config.KeyInVehicle or not Config.KeyInVehicle.enabled then return true end
    if not plate then return false end
    local result = pr_lib.callback.await("pr_carkeys:server:putIgnitionKey", false,
        NetworkGetNetworkIdFromEntity(vehicle), PRCarkeys.SanitizePlate(plate))
    if type(result) == "table" and result.ok then return true end
    local reason = type(result) == "table" and result.reason or "no_response"
    print("[pr_carkeys] OnEngineStarted: " .. tostring(reason))
    PRCarkeys.Notify({title = "Chave", type = "error", description =
        reason == "inventory_full" and "Sem espaco para receber a chave. Ela permanece na ignicao; libere espaco e pressione Z novamente."
        or "Nao foi possivel confirmar a transferencia da chave. Tente novamente."})
    return false
end

function PRCarkeys.OnEngineStopped(vehicle, plate)
    if not Config.KeyInVehicle or not Config.KeyInVehicle.enabled then return true end
    if not plate then return false end
    local result = pr_lib.callback.await("pr_carkeys:server:returnIgnitionKey", false,
        NetworkGetNetworkIdFromEntity(vehicle), PRCarkeys.SanitizePlate(plate))
    if type(result) == "table" and result.ok then return true end
    local reason = type(result) == "table" and result.reason or "no_response"
    print("[pr_carkeys] OnEngineStopped: " .. tostring(reason))
    PRCarkeys.Notify({title = "Chave", type = "error", description =
        reason == "inventory_full" and "Sem espaco para receber a chave. Ela permanece na ignicao; libere espaco e pressione Z novamente."
        or "Nao foi possivel confirmar a transferencia da chave. Tente novamente."})
    return false
end

-- ----------------------------------------------------------------
-- Watchdog de segurança do motor:
-- qualquer transição OFF->ON no banco do motorista exige validação server-side.
-- ----------------------------------------------------------------
CreateThread(function()
    local wasEngineOn = false

    while true do
        if cache.seat == -1 and VehicleState.currentVehicle ~= 0 and DoesEntityExist(VehicleState.currentVehicle) then
            local vehicle  = VehicleState.currentVehicle
            local engineOn = GetIsVehicleEngineRunning(vehicle)

            if engineOn and not wasEngineOn and PRCarkeys.engineTransitionVehicle ~= vehicle then
                local plate = VehicleState.currentPlate
                if not plate then
                    PRCarkeys.SetEngineState(vehicle, false, true, true, "missing_vehicle_plate")
                    VehicleState.isEngineRunning = false
                    VehicleState.hasKey = false
                else
                    local revision = PRCarkeys.engineAccessRevision
                    local hasAccess = pr_lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
                    -- The callback yields. Do not apply an old reply after exit or vehicle change.
                    if revision ~= PRCarkeys.engineAccessRevision or PRCarkeys.engineTransitionVehicle == vehicle
                        or VehicleState.currentVehicle ~= vehicle or VehicleState.currentPlate ~= plate
                        or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
                        wasEngineOn = false
                        goto nextEngineCheck
                    end

                    if not hasAccess then
                        PRCarkeys.SetEngineState(vehicle, false, true, true, "watchdog_access_denied")
                        VehicleState.isEngineRunning = false
                        VehicleState.hasKey = false
                        PRCarkeys.Notify(Config.Notify.noPermission)
                    else
                        VehicleState.hasKey = true
                        VehicleState.isEngineRunning = true
                    end
                end
            elseif not engineOn then
                PRCarkeys.BlockAutomaticEngineStart()
                VehicleState.isEngineRunning = false
            end

            wasEngineOn = engineOn
            ::nextEngineCheck::
            Wait(250)
        else
            wasEngineOn = false
            Wait(700)
        end
    end
end)

-- ----------------------------------------------------------------
-- Ao trocar de arma
-- ----------------------------------------------------------------
lib.onCache("weapon", function(weapon)
    VehicleState.currentWeapon = weapon
end)

-- ----------------------------------------------------------------
-- Servidor confirma chave disponível no carro
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyAvailableInVehicle", function(plate, barcode)
    plate = PRCarkeys.SanitizePlate(plate)
    if VehicleState.currentPlate ~= plate then return end
    if cache.seat ~= -1 then return end

    requestDriverValidation(cache.vehicle, plate)

end)

-- ----------------------------------------------------------------
-- Chave pega do carro com sucesso
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyPickedUp", function(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    Wait(300)
    VehicleState:RebuildFromInventory()
    VehicleState.hasKey = VehicleState:HasKey(plate)
    clearDriverHintUI()
    PRCarkeys.Notify(Config.Notify.keyInVehicle or Config.Notify.keyUsed)
end)

-- ----------------------------------------------------------------
-- Receber chave temp (hotwire, carjack, confisco policial)
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:addTempKey", function(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    VehicleState:AddTempKey(plate)
    -- Remove de permanentKeys imediatamente — chave está no carro, não no inventário
    -- Isso evita que RebuildFromInventory subsequente restaure perm=true durante a transição
    VehicleState.permanentKeys[plate] = nil
    if VehicleState.currentPlate == plate and cache.seat == -1 then
        VehicleState.hasKey = true
        clearDriverHintUI()
    end
    Debug("INFO", ("[addTempKey] plate=%s | perm agora=nil | temp=true"):format(plate))
end)

-- ----------------------------------------------------------------
-- Remover chave temp
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:removeTempKey", function(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    VehicleState:RemoveTempKey(plate)
    if VehicleState.currentPlate == plate and cache.seat == -1 then
        -- Removing one key type does not prove that all access was revoked.
        requestDriverValidation(VehicleState.currentVehicle, plate)
    end
end)

-- ----------------------------------------------------------------
-- Chave roubada do carro por outro player
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyTakenFromVehicle", function(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    VehicleState:RemoveTempKey(plate)
    VehicleState:RemovePermanentKey(plate)
    if VehicleState.currentPlate == plate and VehicleState.currentVehicle ~= 0 then
        PRCarkeys.engineAccessRevision = PRCarkeys.engineAccessRevision + 1
        Entity(VehicleState.currentVehicle).state:set("pr_carkeys_ignition", false, true)
        PRCarkeys.SetEngineState(VehicleState.currentVehicle, false, false, true, "ignition_key_taken")
        VehicleState.isEngineRunning = false
        VehicleState.hasKey = false
    end
    PRCarkeys.Notify(Config.Notify.keyStolen or Config.Notify.keyExpired)
end)

-- ----------------------------------------------------------------
-- Chave devolvida ao inventário (motor desligado)
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyReturnedToInventory", function(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    VehicleState:RemoveTempKey(plate)
    -- Aguarda inventário atualizar (ox_inventory tem latência de ~300ms)
    Wait(600)
    VehicleState:RebuildFromInventory()
    -- Busca chaves nas bolsas também (chave pode ter sido devolvida para bolsa)
    CreateThread(function()
        Wait(200)
        fetchKeysInBags()
        fetchAllKeyDbData()
        if VehicleState.currentPlate then
            VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)
        end
    end)
    Debug("INFO", ("[VehicleInit] Chave devolvida ao inventário: %s"):format(plate))
    PRCarkeys.Notify(Config.Notify.keyReturned or Config.Notify.keyUsed)
end)

-- ----------------------------------------------------------------
-- Inventário mudou: reconstruir
-- ----------------------------------------------------------------
if ActiveInventory == "ox_inventory" then
    local rebuildPending = false
    AddEventHandler("ox_inventory:updateInventory", function()
        if rebuildPending then return end
        rebuildPending = true
        CreateThread(function()
            Wait(300)
            rebuildPending = false
            VehicleState:RebuildFromInventory()
            fetchKeysInBags()
            if VehicleState.currentPlate then
                VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)
            end
        end)
    end)
else
    RegisterNetEvent("QBCore:Player:SetPlayerData", function(data)
        if data and data.items then
            VehicleState:RebuildFromInventory()
            fetchAllKeyDbData()
            if VehicleState.currentPlate then
                VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)
            end
        end
    end)
end

-- ----------------------------------------------------------------
-- Player carregado
-- ----------------------------------------------------------------
local function onPlayerLoaded()
    Wait(500)
    VehicleState:RebuildFromInventory()
    fetchAllKeyDbData()
    TriggerServerEvent("pr_carkeys:server:syncTempKeys")
    Debug("SUCCESS", "[VehicleInit] Player carregado — estado reconstruído.")
    -- fetchKeysInBags usa callback assíncrono, precisa rodar em thread separada
    CreateThread(function()
        Wait(800)
        fetchKeysInBags()
        -- Atualiza fetchAllKeyDbData com chaves das bolsas também
        fetchAllKeyDbData()
        if VehicleState.currentPlate then
            VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)
        end
    end)
end

AddEventHandler("QBCore:Client:OnPlayerLoaded", onPlayerLoaded)
AddEventHandler("esx:playerLoaded",              onPlayerLoaded)
AddEventHandler("ox:playerLoaded",               onPlayerLoaded)

local function onPlayerUnload()
    VehicleState:Reset()
end

AddEventHandler("QBCore:Client:OnPlayerUnload", onPlayerUnload)
AddEventHandler("esx:onPlayerLogout",            onPlayerUnload)
AddEventHandler("ox:playerLogout",               onPlayerUnload)

AddEventHandler("onResourceStart", function(resource)
    if GetCurrentResourceName() ~= resource then return end
    if (pr_lib.framework.IsSessionReady or pr_lib.framework.IsPlayerLoaded)() then onPlayerLoaded() end
end)

-- ----------------------------------------------------------------
-- Busca dados do banco para TODAS as chaves permanentes de uma vez
-- Chamado após RebuildFromInventory
-- ----------------------------------------------------------------


-- ----------------------------------------------------------------
-- Recebe dados do banco em lote e atualiza todas as chaves
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:allKeyDbData", function(rows)
    if not rows then return end
    for _, data in ipairs(rows) do
        VehicleState:UpdateKeyDbData(data.plate, data)
        Debug("INFO", ("[VehicleInit] DB sync | plate=%s | dist=%s | sound=%s | motor=%s")
            :format(data.plate, tostring(data.distance), tostring(data.sound), tostring(data.motor)))
    end
    -- Reavalia hasKey e dados do veículo atual
    if VehicleState.currentPlate then
        VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)
    end
end)

-- ----------------------------------------------------------------
-- Recebe dados do banco para uma chave específica (single fetch)
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyDbData", function(data)
    if not data or not data.plate then return end
    VehicleState:UpdateKeyDbData(data.plate, data)
    Debug("INFO", ("[VehicleInit] Dados do banco recebidos | plate=%s | dist=%s | sound=%s")
        :format(data.plate, tostring(data.distance), tostring(data.sound)))
end)

-- ----------------------------------------------------------------
-- Servidor rejeitou acesso — inventário local está desatualizado
-- Força rebuild imediato para sincronizar com o inventário real
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:forceInventoryRebuild", function()
    Debug("INFO", "[VehicleInit] Rebuild forçado pelo servidor — chave pode ter sido removida")
    VehicleState:RebuildFromInventory()
    fetchAllKeyDbData()

    if VehicleState.currentVehicle ~= 0 and cache.seat == -1 then
        requestDriverValidation(VehicleState.currentVehicle, VehicleState.currentPlate)
    end

    PRCarkeys.Notify(Config.Notify.noPermission)
end)


-- ----------------------------------------------------------------
-- Servidor pediu para desligar motor (chave expirada na ignição)
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:forceEngineOff", function(vehNetId)
    local vehicle = NetworkDoesNetworkIdExist(vehNetId)
        and NetToVeh(vehNetId) or nil

    if not vehicle or not DoesEntityExist(vehicle) then return end
    if PRCarkeys.engineTransitionVehicle == vehicle then
        PRCarkeys.engineAccessRevision = PRCarkeys.engineAccessRevision + 1
    end
    if NetworkHasControlOfEntity(vehicle) then
        Entity(vehicle).state:set("pr_carkeys_ignition", false, true)
    end


    PRCarkeys.SetEngineState(vehicle, false, true, true, "ignition_key_expired")
    VehicleState.isEngineRunning = false

    -- Se o player está no banco do motorista desse veículo, mostra hint
    if cache.vehicle == vehicle and cache.seat == -1 then
        VehicleState.hasKey = false
        if not VehicleState.showHotwireHint then
            lib.showTextUI(Config.Hotwire and Config.Hotwire.hintText or "[H] Ligar na força", {
                position = "right-center",
                icon     = "bolt",
            })
            VehicleState.showHotwireHint = true
            VehicleState.textUiMode = "hotwire"
        end
    end

    Debug("INFO", ("[forceEngineOff] Motor desligado por chave expirada | vehNetId=%s"):format(tostring(vehNetId)))
end)

-- ----------------------------------------------------------------
-- Hotwire: tecla configurável → minigame → chave temporária (export GiveTempKey no servidor)
-- ----------------------------------------------------------------
local hotwireBusy = false

local function showHotwireHint()
    if cache.seat ~= -1 or VehicleState.currentVehicle == 0 or VehicleState.hasKey then return end

    lib.showTextUI(Config.Hotwire.hintText or "[H] Ligação direta", {
        position = "right-center",
        icon     = "bolt",
    })
    VehicleState.showHotwireHint = true
    VehicleState.textUiMode = "hotwire"
end

RegisterNetEvent("pr_carkeys:client:grantTempAccessResult", function(success, reason)
    hotwireBusy = false
    VehicleState.hotwireToken = nil

    if success then
        VehicleState.hasKey = true
        clearDriverHintUI()
        PRCarkeys.Notify(Config.Hotwire.notifySuccess or {
            title       = "Ligação direta",
            description = "Acesso temporário concedido a este veículo.",
            type        = "success",
        })
        return
    end

    Debug("WARNING", ("[Hotwire] acesso recusado pelo servidor | reason=%s"):format(tostring(reason)))
    PRCarkeys.Notify({
        title       = "Ligação direta",
        description = "Não foi possível validar este veículo. Tente novamente.",
        type        = "error",
    })
    showHotwireHint()
end)

local function tryHotwireMinigame()
    if not Config.Hotwire or not Config.Hotwire.enabled then return end
    if hotwireBusy then return end
    if VehicleState.textUiMode ~= "hotwire" then return end
    if cache.seat ~= -1 or VehicleState.currentVehicle == 0 then return end
    if VehicleState.hasKey then return end

    local vehicle = VehicleState.currentVehicle
    local plate   = VehicleState.currentPlate
    if not vehicle or vehicle == 0 or not plate then return end
    if PRCarkeys.IsVehicleBlacklisted(vehicle) then return end

    hotwireBusy = true
    if VehicleState.showHotwireHint then
        lib.hideTextUI()
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local session = pr_lib.callback.await(
        "pr_carkeys:server:requestHotwireSession",
        false,
        netId,
        plate
    )

    if not session then
        hotwireBusy = false
        PRCarkeys.Notify({
            title       = "Ligação direta",
            description = "Não foi possível iniciar neste veículo.",
            type        = "error",
        })
        showHotwireHint()
        return
    end

    if session.hasAccess then
        hotwireBusy = false
        VehicleState.hasKey = true
        VehicleState.hotwireToken = nil
        clearDriverHintUI()
        return
    end

    VehicleState.hotwireToken = session.token
    local mode = (Config.Hotwire.minigameMode == "carjack") and "carjack" or "parked"
    local minigameOk, success = pcall(function()
        return Bridge.minigame and Bridge.minigame.Start(mode) or false
    end)

    if cache.seat ~= -1 or VehicleState.currentVehicle ~= vehicle or VehicleState.hasKey then
        hotwireBusy = false
        VehicleState.hotwireToken = nil
        return
    end

    if not minigameOk then
        hotwireBusy = false
        VehicleState.hotwireToken = nil
        Debug("ERROR", ("[Hotwire] falha ao iniciar minigame | error=%s"):format(tostring(success)))
        PRCarkeys.Notify({
            title       = "Ligação direta",
            description = "O minigame está indisponível no momento.",
            type        = "error",
        })
        showHotwireHint()
        return
    end

    if not success then
        hotwireBusy = false
        VehicleState.hotwireToken = nil
        PRCarkeys.Notify(Config.Hotwire.notifyFail or {
            title       = "Ligação direta",
            description = "A ligação direta falhou.",
            type        = "error",
        })
        showHotwireHint()
        return
    end

    TriggerServerEvent("pr_carkeys:server:grantTemporaryVehicleAccess", netId, plate, session.token)

    CreateThread(function()
        Wait(10000)
        if hotwireBusy and VehicleState.hotwireToken == session.token then
            hotwireBusy = false
            VehicleState.hotwireToken = nil
            showHotwireHint()
        end
    end)
end

RegisterCommand("pr_carkeys_hotwire", function()
    tryHotwireMinigame()
end, false)

RegisterKeyMapping(
    "pr_carkeys_hotwire",
    "pr_carkeys: ligação direta (hotwire)",
    "keyboard",
    (Config.Hotwire and Config.Hotwire.hotwireKey) or "H"
)

-- ----------------------------------------------------------------
-- Veiculos estacionados sem chave usam o arrombamento nativo do GTA:
-- segurar F quebra o vidro e abre a porta. A ignicao continua protegida
-- pelo hotwire acima, disponivel apenas no banco do motorista.
-- ----------------------------------------------------------------
local parkedVehicleLockRequests = {}

CreateThread(function()
    while true do
        Wait(500)

        -- só uma pequena verificaçao do veiculo ligado
        if cache.vehicle and cache.vehicle ~= 0 and cache.seat == -1 then
            lastKnownEngineState = GetIsVehicleEngineRunning(cache.vehicle)
        end

        if cache.vehicle then goto continue end

        local vehicle = pr_lib.framework.GetClosestVehicle and pr_lib.framework.GetClosestVehicle() or nil
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then goto continue end

        local distance = #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle))
        if distance > 4.0
            or PRCarkeys.IsVehicleBlacklisted(vehicle)
            or GetPedInVehicleSeat(vehicle, -1) ~= 0
            or GetIsVehicleEngineRunning(vehicle) then goto continue end

        local plate = PRCarkeys.GetVehicleKeyPlate(vehicle)
        if VehicleState:HasKey(plate) then goto continue end

        local lockStatus = GetVehicleDoorLockStatus(vehicle)
        if lockStatus == 0 or lockStatus == 1 then
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            local now = GetGameTimer()
            if (parkedVehicleLockRequests[netId] or 0) <= now then
                parkedVehicleLockRequests[netId] = now + 5000
                TriggerServerEvent("pr_carkeys:server:secureParkedVehicle", netId)
            end
        end

        ::continue::
    end
end)

