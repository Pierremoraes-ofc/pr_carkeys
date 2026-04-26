-- ============================================================
--   pr_carkeys — client/modules/vehicle_init.lua
--   Inicialização reativa via lib.onCache.
-- ============================================================

local VehicleState = require 'client.modules.vehicle_state'
local VehicleLock  = require 'client.modules.vehicle_lock'
local KeyInVehicle = require 'client.modules.key_in_vehicle'

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
    for _, data in pairs(VehicleState.permanentKeys) do
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
    local bagKeys = lib.callback.await("pr_carkeys:server:getKeysInBags", false)
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
        (function() local c=0; for _ in pairs(VehicleState.permanentKeys) do c=c+1 end; return c end)()
    ))
end

-- ----------------------------------------------------------------
-- Ao entrar/sair de veículo
-- ----------------------------------------------------------------
lib.onCache("vehicle", function(vehicle)
    if vehicle then
        VehicleState.currentVehicle  = vehicle
        local plate = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
        VehicleState.currentPlate    = plate
        VehicleState.isInDriverSeat  = (GetPedInVehicleSeat(vehicle, -1) == cache.ped)
        VehicleState.hasKey          = VehicleState:HasKey(plate)
        VehicleState.isEngineRunning = GetIsVehicleEngineRunning(vehicle)

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
    else
        -- Saiu do veículo
        local leftVehicle = cache.vehicle
        if leftVehicle and leftVehicle ~= 0 then
            -- keepVehicleEngineOn: mantém motor ligado ao sair do carro
            -- Usa parâmetro 'instantly=true, otherwise=false' para não religar automaticamente
            if Config.KeyInVehicle.keepVehicleEngineOn
            and VehicleState.isInDriverSeat
            and VehicleState.isEngineRunning then
                -- 'true, true, false' = ligar, instantly, sem forçar novo estado
                SetVehicleEngineOn(leftVehicle, true, true, false)
                Debug("INFO", ("[keepEngineOn] Motor mantido ligado ao sair | plate=%s"):format(
                    tostring(VehicleState.currentPlate)))
            end
        end

        VehicleState.currentVehicle  = 0
        VehicleState.currentPlate    = nil
        VehicleState.isInDriverSeat  = false
        VehicleState.isEngineRunning = false
        VehicleState.hasKey          = false

        clearDriverHintUI()
    end
end)

-- ----------------------------------------------------------------
-- Ao mudar de assento
-- ----------------------------------------------------------------
lib.onCache("seat", function(seat)
    if not cache.vehicle or cache.vehicle == 0 then return end
    VehicleState.isInDriverSeat = (seat == -1)

    if seat ~= -1 then
        clearDriverHintUI()
        return
    end

    -- Entrou no banco do motorista — delega validação ao servidor
    local vehicle = cache.vehicle
    local plate   = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
    VehicleState.currentPlate = plate
    VehicleState.hasKey       = VehicleState:HasKey(plate)

    -- Aguarda resposta do servidor antes de desligar motor
    -- Evita desligar motor de quem tem chave mas o cache ainda não sincronizou
    TriggerServerEvent("pr_carkeys:server:validateDriverSeat",
        NetworkGetNetworkIdFromEntity(vehicle), plate)
end)

-- ----------------------------------------------------------------
-- Resposta da validação do banco do motorista
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:driverSeatValidation", function(result)
    if not result then return end
    local plate   = result.plate
    local vehicle = VehicleState.currentVehicle
    if not vehicle or vehicle == 0 then return end
    if cache.seat ~= -1 then return end  -- saiu do banco antes de responder

    if result.hasAccess then
        VehicleState.hasKey = true
        clearDriverHintUI()

        -- Acesso confirmado
        local engineAlreadyOn = GetIsVehicleEngineRunning(vehicle)
        local hasTempKey = VehicleState.temporaryKeys[result.plate] == true
        Debug("INFO", ("[driverSeatValidation] Acesso OK | plate=%s | motor=%s | temp=%s"):format(
            tostring(result.plate), tostring(engineAlreadyOn), tostring(hasTempKey)))

        -- Motor só desliga se não tem nenhum tipo de acesso (sem TempKey e sem permanente)
        -- TempKey = carjack, hotwire, chave no carro — motor deve ficar ligado
        if engineAlreadyOn and not hasTempKey then
            SetVehicleEngineOn(vehicle, false, true, true)
            VehicleState.isEngineRunning = false
            Debug("INFO", ("[driverSeatValidation] Motor desligado — sem TempKey"))
        elseif engineAlreadyOn and hasTempKey then
            VehicleState.isEngineRunning = true
            Debug("INFO", ("[driverSeatValidation] Motor mantido — tem TempKey"))
        end
    elseif result.keyAvailable then
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
        -- Sem chave — mantém motor desligado e mostra hint de hotwire
        SetVehicleEngineOn(vehicle, false, true, true)
        if not VehicleState.showHotwireHint then
            lib.showTextUI(Config.Hotwire and Config.Hotwire.hintText or "[H] Ligação direta", {
                position = "right-center",
                icon     = "bolt",
            })
            VehicleState.showHotwireHint = true
            VehicleState.textUiMode = "hotwire"
        end
    end

    -- Thread contínua: mantém motor desligado enquanto não tiver chave
    -- Continua mesmo se o player tentar religar o motor manualmente
    if not result.hasAccess and not result.keyAvailable then
        CreateThread(function()
            while cache.seat == -1 and not VehicleState.hasKey do
                if DoesEntityExist(vehicle) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                    -- Bloqueia input de motor para não religar
                    DisableControlAction(0, 86, true)  -- INPUT_VEH_EXIT (E)
                end
                Wait(200)
            end
            -- Liberou porque ganhou chave (hotwire etc.) — motor pode ligar normalmente
        end)
    end
end)

-- ----------------------------------------------------------------
-- Gerencia chave no carro baseado no estado do motor
-- Chamado explicitamente pelo toggleengine e pelo destrancar com motor=true
-- NÃO usa polling — evita falsos positivos
-- ----------------------------------------------------------------

--- Chamado quando o motor LIGA (Z ou destrancar com motor=true)
--- Remove chave do inventário se estiver lá (permanente OU carkey_temp)
function PRCarkeys.OnEngineStarted(vehicle, plate)
    if not Config.KeyInVehicle or not Config.KeyInVehicle.enabled then return end
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)

    Debug("INFO", ("[Engine] OnEngineStarted | plate=%s | perm=%s | temp=%s"):format(
        plate,
        tostring(VehicleState.permanentKeys[plate] ~= nil),
        tostring(VehicleState.temporaryKeys[plate] == true)
    ))

    -- NUNCA retornar cedo com base só em cache local:
    -- chave na bolsa não entra no RebuildFromInventory, e TempKey pode estar obsoleta.
    -- O servidor decide (findKeyItemByPlate + duplicate check em VehiclesWithKeyInside).

    -- Não depende exclusivamente do cache local:
    -- ao ligar, o servidor decide se existe item real (inventário/bolsa) e remove.
    -- Isso evita falha quando o player liga logo após desligar (antes do rebuild local).
    local keyData = VehicleState:GetKeyData(plate)
    Debug("INFO", ("[Engine] Chave vai para o carro | plate=%s | barcode=%s | item=%s"):format(
        plate,
        tostring(keyData and keyData.barcode or "unknown"),
        tostring(keyData and keyData.itemName or "unknown")))
    TriggerServerEvent("pr_carkeys:server:keyLeftInVehicle",
        NetworkGetNetworkIdFromEntity(vehicle), plate)
end

function PRCarkeys.OnEngineStopped(vehicle, plate)
    if not Config.KeyInVehicle or not Config.KeyInVehicle.enabled then return end
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)

    Debug("INFO", ("[Engine] OnEngineStopped | plate=%s | perm=%s | temp=%s"):format(
        plate,
        tostring(VehicleState.permanentKeys[plate] ~= nil),
        tostring(VehicleState.temporaryKeys[plate] == true)
    ))

    -- Só devolve se há temp key para esta placa
    -- NÃO checamos permanentKeys localmente — pode estar desatualizado
    -- O servidor verifica o estado real em VehiclesWithKeyInside
    if not VehicleState.temporaryKeys[plate] then
        Debug("WARNING", ("[Engine] OnEngineStopped — sem temp key para plate=%s, nada a devolver"):format(plate))
        return
    end

    Debug("INFO", ("[Engine] Devolvendo chave | plate=%s"):format(plate))
    TriggerServerEvent("pr_carkeys:server:returnKeyFromVehicle",
        NetworkGetNetworkIdFromEntity(vehicle), plate)
end

-- ----------------------------------------------------------------
-- Bloqueia W (aceleração) quando motor está desligado sem chave
-- O player só pode ligar o motor via Z (toggleengine) ou hotwire
-- ----------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)
        -- Só atua se está no banco do motorista
        if cache.seat == -1 and VehicleState.currentVehicle ~= 0 then
            local vehicle = VehicleState.currentVehicle
            local engineOn = GetIsVehicleEngineRunning(vehicle)

            -- Motor desligado: bloqueia W para não ligar acelerando
            if not engineOn then
                -- Bloqueia INPUT_VEH_ACCELERATE (71) e INPUT_VEH_MOVE_UP_ONLY (72)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
                -- Bloqueia também o input de ligar motor via teclado padrão do GTA
                DisableControlAction(0, 86, true)  -- INPUT_VEH_HANDBRAKE (que também liga motor)
            end
        else
            Wait(500)  -- Fora do banco, polling mais lento
        end
    end
end)

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

            if engineOn and not wasEngineOn then
                local plate = VehicleState.currentPlate
                if not plate then
                    SetVehicleEngineOn(vehicle, false, true, true)
                    VehicleState.isEngineRunning = false
                    VehicleState.hasKey = false
                else
                    local hasAccess = lib.callback.await("pr_carkeys:server:validateKeyAccess", false, plate)
                    if not hasAccess then
                        SetVehicleEngineOn(vehicle, false, true, true)
                        VehicleState.isEngineRunning = false
                        VehicleState.hasKey = false
                        PRCarkeys.Notify(Config.Notify.noPermission)
                    else
                        VehicleState.hasKey = true
                        VehicleState.isEngineRunning = true
                    end
                end
            elseif not engineOn then
                VehicleState.isEngineRunning = false
            end

            wasEngineOn = engineOn
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

    local pickupTime = Config.KeyInVehicle and Config.KeyInVehicle.pickupTime or 0
    if pickupTime > 0 then
        if lib.progressBar({
            duration  = pickupTime,
            label     = (Config.KeyInVehicle and Config.KeyInVehicle.pickupLabel) or "Pegando chave...",
            canCancel = true,
            disable   = { move = false, car = true, combat = true },
        }) then
            TriggerServerEvent("pr_carkeys:server:pickupKeyFromVehicle",
                NetworkGetNetworkIdFromEntity(cache.vehicle), plate, barcode)
        end
    else
        TriggerServerEvent("pr_carkeys:server:pickupKeyFromVehicle",
            NetworkGetNetworkIdFromEntity(cache.vehicle), plate, barcode)
    end
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
-- Receber chave temp (hotwire, lockpick, carjack)
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
        VehicleState.hasKey = false
        SetVehicleEngineOn(cache.vehicle, false, false, true)
        VehicleState.isEngineRunning = false
        if not VehicleState.showHotwireHint then
            lib.showTextUI(Config.Hotwire and Config.Hotwire.hintText or "[H] Ligar na força", {
                position = "right-center", icon = "bolt",
            })
            VehicleState.showHotwireHint = true
            VehicleState.textUiMode = "hotwire"
        end
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
        SetVehicleEngineOn(VehicleState.currentVehicle, false, false, true)
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
    if LocalPlayer.state.isLoggedIn then onPlayerLoaded() end
end)

-- ================================================================
--   EXPORTS CLIENT
-- ================================================================
exports("HaveKey",          function(plate) return VehicleState:HasKey(plate) end)
exports("HavePermanentKey", function(plate)
    if not plate then return false end
    return VehicleState.permanentKeys[PRCarkeys.SanitizePlate(plate)] ~= nil
end)
exports("HaveTempKey", function(plate)
    if not plate then return false end
    return VehicleState.temporaryKeys[PRCarkeys.SanitizePlate(plate)] == true
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

    -- Se está no banco do motorista do veículo afetado, reavalia acesso
    if VehicleState.currentVehicle ~= 0 and cache.seat == -1 then
        VehicleState.hasKey = VehicleState:HasKey(VehicleState.currentPlate)

        if not VehicleState.hasKey then
            -- Perdeu o acesso — desliga motor e mostra hint
            SetVehicleEngineOn(VehicleState.currentVehicle, false, false, true)
            VehicleState.isEngineRunning = false
            if not VehicleState.showHotwireHint then
                lib.showTextUI(Config.Hotwire and Config.Hotwire.hintText or "[H] Ligar na força", {
                    position = "right-center",
                    icon     = "bolt",
                })
                VehicleState.showHotwireHint = true
                VehicleState.textUiMode = "hotwire"
            end
        end
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

    SetVehicleEngineOn(vehicle, false, true, true)
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

    local mode = (Config.Hotwire.minigameMode == "carjack") and "carjack" or "parked"
    local success = Bridge.minigame and Bridge.minigame.Start(mode) or false

    hotwireBusy = false

    if cache.seat ~= -1 or VehicleState.currentVehicle ~= vehicle or VehicleState.hasKey then return end

    if success then
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        TriggerServerEvent("pr_carkeys:server:grantTemporaryVehicleAccess", netId, plate)
        PRCarkeys.Notify(Config.Hotwire.notifySuccess or {
            title       = "Ligação direta",
            description = "Acesso temporário concedido a este veículo.",
            type        = "success",
        })
    else
        local failMsg = Config.Hotwire.notifyFail or Config.Notify.noPermission
        PRCarkeys.Notify(failMsg)
        if VehicleState.textUiMode == "hotwire" and not VehicleState.hasKey then
            lib.showTextUI(Config.Hotwire.hintText or "[H] Ligação direta", {
                position = "right-center",
                icon     = "bolt",
            })
            VehicleState.showHotwireHint = true
        end
    end
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