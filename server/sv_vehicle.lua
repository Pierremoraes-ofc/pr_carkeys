-- ============================================================
--   pr_carkeys — server/sv_vehicle.lua
-- ============================================================

-- { [vehNetId] = { plate, barcode, citizenid, itemName, fromStash, fromBagItem, isCarjack } }
-- Exposto em _G para rotinas de expiração (single_use cronômetro) removerem da ignição.
VehiclesWithKeyInside = VehiclesWithKeyInside or {}

-- { [citizenid] = { [plate] = true } }
local TempKeys = {}
local MissingVehicleChecks = {}
local RecentTempKeyGrants = {}

-- ================================================================
--   HELPERS
-- ================================================================

local function sanitize(plate)
    return PRCarkeys.SanitizePlate(plate)
end

local function hasTemporaryItemForPlate(src, plate)
    if ActiveInventory ~= "ox_inventory" then return false end
    local slots = exports.ox_inventory:Search(src, "slots", "carkey_temp", { plate = plate })
    return slots and #slots > 0
end

local function getOnlineSourceByCitizenid(citizenid)
    if not citizenid then return nil end
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and Bridge.framework.GetIdentifier(src) == citizenid then
            return src
        end
    end
    return nil
end

--- Verifica se o jogador tem qualquer forma de acesso à placa
--- Checa: TempKeys (hotwire/lockpick/chave no carro) + item no inventário
---@param src number
---@param citizenid string
---@param plate string
---@return boolean
local function playerHasAccess(src, citizenid, plate)
    plate = sanitize(plate)

    -- 1. TempKey (hotwire/lockpick/chave no carro)
    local tempEntry = TempKeys[citizenid] and TempKeys[citizenid][plate] or nil
    if tempEntry then
        if type(tempEntry) ~= "table" then
            return true
        end

        if tempEntry.kind ~= "vehicle" then
            -- TempKey concedida (hotwire/exports) NÃO pode burlar inventário/bolsa.
            -- Ela serve apenas como “flag” de curto prazo; a existência do item decide o acesso.
            Debug("INFO", ("playerHasAccess: temp key concedida (aguardando item) | citizenid=%s | plate=%s | kind=%s"):format(
                citizenid, plate, tostring(tempEntry.kind)))
            -- continua para checar inventário/bolsa
        end

        -- Verificar se é chave no carro (legítima) ou obsoleta
        local isKeyInCar = false
        for _, data in pairs(VehiclesWithKeyInside) do
            if data.plate == plate and data.citizenid == citizenid then
                isKeyInCar = true; break
            end
        end
        if isKeyInCar then return true end
        -- Não é chave no carro — verifica inventário antes de aceitar
    end

    -- 2. Busca no inventário e bolsas
    if ActiveInventory == "ox_inventory" then
        -- 2a. Inventário direto
        for itemName, _ in pairs(Config.KeyTypes) do
            local slots = exports.ox_inventory:GetSlotsWithItem(src, itemName, nil)
            if slots then
                for _, slot in pairs(slots) do
                    local meta = slot.metadata or {}
                    if meta.plate and sanitize(meta.plate) == plate then
                        Debug("INFO", ("playerHasAccess: chave no inventario | plate=%s | item=%s"):format(plate, itemName))
                        return true
                    end
                end
            end
        end

        -- 2b. Bolsas
        for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
            local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, bagName, nil)
            if bagSlots then
                for _, bagSlot in pairs(bagSlots) do
                    local bagMeta = bagSlot.metadata or {}
                    if bagMeta.barcode then
                        local stashId = "pr_carkeys_bag_" .. bagMeta.barcode
                        for itemName, _ in pairs(Config.KeyTypes) do
                            local keySlots = exports.ox_inventory:Search(stashId, "slots", itemName, { plate = plate })
                            if keySlots and #keySlots > 0 then
                                Debug("INFO", ("playerHasAccess: chave na bolsa | plate=%s | stash=%s"):format(plate, stashId))
                                return true
                            end
                        end
                    end
                end
            end
        end
    else
        local Player = Bridge.framework.GetPlayer(src)
        if Player then
            for _, item in pairs(Player.PlayerData.items or {}) do
                if item and Config.KeyTypes[item.name] then
                    local meta = item.info or item.metadata or {}
                    if meta.plate and sanitize(meta.plate) == plate then return true end
                end
            end
        end
    end

    -- TempKey sem chave no inventário e sem chave no carro = obsoleta, limpar
    if tempEntry and type(tempEntry) == "table" and tempEntry.kind == "vehicle" then
        TempKeys[citizenid][plate] = nil
        Debug("WARNING", ("playerHasAccess: TempKey obsoleta removida | citizenid=%s | plate=%s"):format(citizenid, plate))
    end

    Debug("INFO", ("playerHasAccess: sem acesso | src=%d | plate=%s"):format(src, plate))
    return false
end

--- Encontra o item de chave no inventário OU bolsa pela placa.
--- Retorna dados suficientes para REMOÇÃO determinística (inclui slot).
--- @return barcode, itemName, fromStashId, itemSlot, fromBagItemName
local function findKeyItemByPlate(src, plate)
    plate = sanitize(plate)
    local function plateMatches(metaPlate)
        return metaPlate and sanitize(metaPlate) == plate
    end

    if ActiveInventory == "ox_inventory" then
        -- 1. Inventário direto usando Search com match na metadata
        for itemName, _ in pairs(Config.KeyTypes) do
            local slots = exports.ox_inventory:Search(src, "slots", itemName, { plate = plate })
            if slots and #slots > 0 then
                -- escolhe o primeiro slot com barcode válido (evita falso positivo quando meta está incompleta)
                for _, s in ipairs(slots) do
                    local meta = s.metadata or {}
                    if meta.barcode then
                        Debug("INFO", ("findKeyItemByPlate: inventario | item=%s | barcode=%s | slot=%s"):format(
                            itemName, tostring(meta.barcode), tostring(s.slot)))
                        return meta.barcode, itemName, nil, s.slot, nil
                    end
                end
            end
        end

        -- 1b. Fallback robusto (metadata plate pode vir sem sanitize no item)
        for itemName, _ in pairs(Config.KeyTypes) do
            local invSlots = exports.ox_inventory:GetSlotsWithItem(src, itemName, nil)
            if invSlots then
                for _, slot in pairs(invSlots) do
                    local meta = slot.metadata or {}
                    if meta.barcode and plateMatches(meta.plate) then
                        Debug("INFO", ("findKeyItemByPlate: inventario(fallback) | item=%s | barcode=%s | slot=%s"):format(
                            itemName, tostring(meta.barcode), tostring(slot.slot)))
                        return meta.barcode, itemName, nil, slot.slot, nil
                    end
                end
            end
        end

        -- 2. Bolsas
        for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
            local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, bagName, nil)
            if bagSlots then
                for _, bagSlot in pairs(bagSlots) do
                    local bagMeta = bagSlot.metadata or {}
                    if bagMeta.barcode then
                        local stashId = "pr_carkeys_bag_" .. bagMeta.barcode
                        for itemName, _ in pairs(Config.KeyTypes) do
                            local keySlots = exports.ox_inventory:Search(stashId, "slots", itemName, { plate = plate })
                            if keySlots and #keySlots > 0 then
                                for _, ks in ipairs(keySlots) do
                                    local meta = ks.metadata or {}
                                    if meta.barcode then
                                        local targetSlot = ks.slot
                                        Debug("INFO", ("findKeyItemByPlate: bolsa | stash=%s | item=%s | barcode=%s | slot=%s | bag=%s"):format(
                                            stashId, itemName, tostring(meta.barcode), tostring(targetSlot), bagName))
                                        return meta.barcode, itemName, stashId, targetSlot, bagName
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2b. Fallback robusto para bolsas (scan completo do stash e sanitize da placa)
        for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
            local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, bagName, nil)
            if bagSlots then
                for _, bagSlot in pairs(bagSlots) do
                    local bagMeta = bagSlot.metadata or {}
                    if bagMeta.barcode then
                        local stashId = "pr_carkeys_bag_" .. bagMeta.barcode
                        local stashItems = exports.ox_inventory:GetInventoryItems(stashId)
                        if stashItems then
                            for _, item in pairs(stashItems) do
                                if item and Config.KeyTypes[item.name] then
                                    local meta = item.metadata or {}
                                    if meta.barcode and plateMatches(meta.plate) then
                                        Debug("INFO", ("findKeyItemByPlate: bolsa(fallback) | stash=%s | item=%s | barcode=%s | slot=%s | bag=%s"):format(
                                            stashId, tostring(item.name), tostring(meta.barcode), tostring(item.slot), bagName))
                                        return meta.barcode, item.name, stashId, item.slot, bagName
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        local Player = Bridge.framework.GetPlayer(src)
        if Player then
            for _, item in pairs(Player.PlayerData.items or {}) do
                if item and Config.KeyTypes[item.name] then
                    local meta = item.info or item.metadata or {}
                    if meta.plate and sanitize(meta.plate) == plate then
                        return meta.barcode, item.name, nil
                    end
                end
            end
        end
    end

    Debug("WARNING", ("findKeyItemByPlate: nao encontrado | src=%d | plate=%s"):format(src, plate))
    return nil, nil, nil
end

--- Remove a chave do inventário/bolsa de forma confirmada.
--- Retorna (ok, data) onde data contém onde estava.
local function removeKeyItemConfirmed(src, plate)
    local barcode, itemName, fromStash, itemSlot, fromBagItem = findKeyItemByPlate(src, plate)
    if not barcode then
        return false, nil
    end

    -- single_use (modo cronômetro) pode ir para a ignição também

    if ActiveInventory ~= "ox_inventory" then
        -- Fallback legacy (qb-inventory etc.)
        Bridge.inventory.RemoveItemByBarcode(src, barcode)
        return true, { barcode = barcode, itemName = itemName, fromStash = nil, fromBagItem = nil }
    end

    -- Slot numérico: ox_inventory indexa por número; string quebra a remoção por slot
    local slot = itemSlot and (tonumber(itemSlot) or itemSlot) or nil

    local function stillInSameContainer()
        -- Confirma no MESMO container de onde removemos (evita falso positivo se a chave
        -- existir só na bolsa e Search no player "principal" se comportar diferente)
        local invId = fromStash or src
        local slots = exports.ox_inventory:Search(invId, "slots", itemName, { barcode = barcode })
        return slots and #slots > 0
    end

    local removed = false

    if fromStash then
        removed = not not exports.ox_inventory:RemoveItem(fromStash, itemName, 1, nil, slot)
    else
        removed = not not exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)
    end

    if not removed then
        Wait(150)
        if fromStash then
            removed = not not exports.ox_inventory:RemoveItem(fromStash, itemName, 1, nil, slot)
        else
            removed = not not exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)
        end
    end

    if removed and stillInSameContainer() then
        removed = false
    end

    if not removed then
        Debug("WARNING", ("removeKeyItemConfirmed: FALHOU remover | src=%d | plate=%s | item=%s | barcode=%s | fromStash=%s | slot=%s"):format(
            src, tostring(plate), tostring(itemName), tostring(barcode), tostring(fromStash), tostring(slot)))
        return false, nil
    end

    return true, { barcode = barcode, itemName = itemName, fromStash = fromStash, fromBagItem = fromBagItem }
end

-- ================================================================
--   LOCK / UNLOCK SEGURO
-- ================================================================

RegisterNetEvent("pr_carkeys:server:setVehicleLockState", function(vehNetId, state, plate)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end
    if state ~= 1 and state ~= 2 then return end

    -- Policial tem acesso irrestrito
    if not PRCarkeys.IsPlayerPolice(src) then
        if not playerHasAccess(src, citizenid, plate) then
            Debug("WARNING", ("setVehicleLockState: sem acesso | src=%d | plate=%s"):format(src, tostring(plate)))
            -- Força rebuild no client para corrigir estado local desatualizado
            TriggerClientEvent("pr_carkeys:client:forceInventoryRebuild", src)
            return
        end
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 then return end

    SetVehicleDoorsLocked(vehicle, state)
    Entity(vehicle).state:set("doorslockstate", state, true)

    Debug("INFO", ("setVehicleLockState: src=%d | plate=%s | state=%d"):format(src, tostring(plate), state))
end)

-- Callback: valida se player realmente tem a chave no inventário AGORA
-- Consultado pelo client ANTES de qualquer ação de lock/unlock
lib.callback.register("pr_carkeys:server:validateKeyAccess", function(src, plate)
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return false end
    if PRCarkeys.IsPlayerPolice(src) then return true end
    return playerHasAccess(src, citizenid, sanitize(plate))
end)

-- ================================================================
--   VALIDAÇÃO DE MOTOR — impede ligar sem chave (server-side)
-- ================================================================

--- Chamado pelo client quando entra no banco do motorista
--- Servidor verifica se tem acesso e autoriza ou bloqueia o motor
RegisterNetEvent("pr_carkeys:server:validateDriverSeat", function(vehNetId, plate)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    plate = sanitize(plate)
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 then return end

    local hasAccess = PRCarkeys.IsPlayerPolice(src) or playerHasAccess(src, citizenid, plate)

    -- Verifica também se há chave no carro disponível para pegar
    local keyInCar = VehiclesWithKeyInside[vehNetId]
    local keyAvailable = keyInCar and keyInCar.plate == plate
    if keyInCar then
        keyInCar.lastDriverSrc = src
        keyInCar.lastDriverCitizenid = citizenid
    end

    TriggerClientEvent("pr_carkeys:client:driverSeatValidation", src, {
        hasAccess    = hasAccess,
        keyAvailable = keyAvailable,
        barcode      = keyAvailable and keyInCar.barcode or nil,
        plate        = plate,
    })
end)

-- ================================================================
--   CHAVE NO CARRO
-- ================================================================

RegisterNetEvent("pr_carkeys:server:keyLeftInVehicle", function(vehNetId, plate)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    plate = sanitize(plate)
    Debug("INFO", ("keyLeftInVehicle: recebido | src=%d | plate=%s | vehNetId=%d"):format(src, plate, vehNetId))

    -- Já tem chave registrada nesse veículo? Ignorar (evita duplicatas)
    if VehiclesWithKeyInside[vehNetId] then
        Debug("INFO", ("keyLeftInVehicle: chave ja registrada nesse veiculo, ignorando"):format())
        return
    end

    local okRemove, removedData = removeKeyItemConfirmed(src, plate)
    if not okRemove or not removedData then
        Debug("WARNING", ("keyLeftInVehicle: item nao encontrado em lugar algum | src=%d | plate=%s"):format(src, plate))
        return
    end

    VehiclesWithKeyInside[vehNetId] = {
        plate     = plate,
        barcode   = removedData.barcode,
        citizenid = citizenid,
        lastDriverSrc = src,
        lastDriverCitizenid = citizenid,
        itemName  = removedData.itemName,
        fromStash = removedData.fromStash,
        fromBagItem = removedData.fromBagItem,
    }

    if not TempKeys[citizenid] then TempKeys[citizenid] = {} end
    TempKeys[citizenid][plate] = { kind = "vehicle" }
    TriggerClientEvent("pr_carkeys:client:addTempKey", src, plate)

    Debug("SUCCESS", ("keyLeftInVehicle: TempKey criada | src=%d | plate=%s | item=%s | origem=%s"):format(
        src, plate, tostring(removedData.itemName), tostring(removedData.fromStash or "inventario")))
end)

local function restoreDeletedVehicleKey(vehNetId, keyData)
    if not keyData then return end

    local targetSrc = nil
    if keyData.lastDriverSrc and GetPlayerName(keyData.lastDriverSrc) then
        targetSrc = keyData.lastDriverSrc
    elseif keyData.lastDriverCitizenid then
        targetSrc = getOnlineSourceByCitizenid(keyData.lastDriverCitizenid)
    end
    if not targetSrc and keyData.citizenid then
        targetSrc = getOnlineSourceByCitizenid(keyData.citizenid)
    end

    if not targetSrc then
        Debug("WARNING", ("restoreDeletedVehicleKey: sem player online para devolver | vehNetId=%s | plate=%s | barcode=%s"):format(
            tostring(vehNetId), tostring(keyData.plate), tostring(keyData.barcode)))
        return
    end

    local plate = sanitize(keyData.plate)

    if keyData.isCarjack then
        local metadata = {
            label   = "Modelo: " .. plate .. "\nPlaca: " .. plate .. "\nSerial: " .. tostring(keyData.barcode),
            barcode = keyData.barcode,
            plate   = plate,
            modelo  = plate,
            code    = keyData.barcode,
        }
        local added = Bridge.inventory.AddItem(targetSrc, "carkey_temp", 1, metadata)
        if not added then
            Debug("WARNING", ("restoreDeletedVehicleKey: falhou devolver carkey_temp | src=%d | plate=%s"):format(targetSrc, plate))
            return
        end
    else
        local rows = ExecuteSQL(
            "SELECT barcode, plate, key_type, sound, motor, distance FROM pr_carkeys WHERE barcode = ? LIMIT 1",
            { keyData.barcode }
        )
        local row = rows and rows[1]
        if not row then
            Debug("WARNING", ("restoreDeletedVehicleKey: chave nao encontrada no DB | barcode=%s"):format(tostring(keyData.barcode)))
            return
        end

        if PRCarkeys.IsKeyExpired(row) then
            ExecuteSQL("DELETE FROM pr_carkeys WHERE barcode = ?", { keyData.barcode })
            PRCarkeys.Cache.InvalidateKey(keyData.barcode)
            TriggerClientEvent("pr_carkeys:client:keyExpired", targetSrc)
            return
        end

        local metadata = {
            label    = ("Placa: %s\nSerial: %s"):format(plate, tostring(keyData.barcode)),
            barcode  = keyData.barcode,
            plate    = plate,
            modelo   = plate,
            code     = keyData.barcode,
            sound    = row.sound or Config.Sound.soundDefault,
            motor    = row.motor or 0,
            distance = row.distance or Config.Default.UseKeyAnim.DefaultDistance,
        }

        local added = false
        if ActiveInventory == "ox_inventory" and keyData.fromStash then
            local hasBag = false
            for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
                local bagSlots = exports.ox_inventory:GetSlotsWithItem(targetSrc, bagName, nil)
                if bagSlots then
                    for _, bagSlot in pairs(bagSlots) do
                        local bagMeta = bagSlot.metadata or {}
                        if bagMeta.barcode and ("pr_carkeys_bag_" .. bagMeta.barcode) == keyData.fromStash then
                            hasBag = true
                            break
                        end
                    end
                end
                if hasBag then break end
            end

            if hasBag then
                local bagBarcode = keyData.fromStash:gsub("pr_carkeys_bag_", "")
                local bagCfg = Config.Bags[(keyData.fromBagItem or "")] or Config.Bags.carkey_bag or { label = "Bolsa de Chaves", slots = 10, weight = 5000 }
                exports.ox_inventory:RegisterStash(
                    keyData.fromStash,
                    bagCfg.label .. " | " .. bagBarcode,
                    bagCfg.slots,
                    bagCfg.weight,
                    false
                )
                Wait(100)
                added = exports.ox_inventory:AddItem(keyData.fromStash, keyData.itemName, 1, metadata) == true
            end
        end

        if not added then
            added = Bridge.inventory.AddItem(targetSrc, keyData.itemName, 1, metadata)
        end
        if not added then
            Debug("WARNING", ("restoreDeletedVehicleKey: falhou devolver chave | src=%d | plate=%s | item=%s"):format(
                targetSrc, plate, tostring(keyData.itemName)))
            return
        end
    end

    if TempKeys[keyData.citizenid] then TempKeys[keyData.citizenid][plate] = nil end
    local targetCitizenid = Bridge.framework.GetIdentifier(targetSrc)
    if targetCitizenid and TempKeys[targetCitizenid] then
        TempKeys[targetCitizenid][plate] = nil
    end
    TriggerClientEvent("pr_carkeys:client:removeTempKey", targetSrc, plate)
    TriggerClientEvent("pr_carkeys:client:keyReturnedToInventory", targetSrc, plate)

    VehiclesWithKeyInside[vehNetId] = nil
    MissingVehicleChecks[vehNetId] = nil

    Debug("SUCCESS", ("restoreDeletedVehicleKey: chave devolvida apos delete | vehNetId=%s | src=%d | plate=%s"):format(
        tostring(vehNetId), targetSrc, plate))
end

CreateThread(function()
    while true do
        Wait(4000)
        for vehNetId, keyData in pairs(VehiclesWithKeyInside) do
            local veh = NetworkGetEntityFromNetworkId(vehNetId)
            local missing = (not veh or veh == 0 or not DoesEntityExist(veh))
            if missing then
                MissingVehicleChecks[vehNetId] = (MissingVehicleChecks[vehNetId] or 0) + 1
                if MissingVehicleChecks[vehNetId] >= 3 then
                    restoreDeletedVehicleKey(vehNetId, keyData)
                end
            else
                MissingVehicleChecks[vehNetId] = nil
            end
        end
    end
end)

RegisterNetEvent("pr_carkeys:server:checkKeyInVehicle", function(vehNetId, plate)
    local src = source
    if not Bridge.framework.GetIdentifier(src) then return end

    plate = sanitize(plate)
    local keyData = VehiclesWithKeyInside[vehNetId]
    if not keyData or keyData.plate ~= plate then return end

    TriggerClientEvent("pr_carkeys:client:keyAvailableInVehicle", src, plate, keyData.barcode)
end)

RegisterNetEvent("pr_carkeys:server:pickupKeyFromVehicle", function(vehNetId, plate, barcode)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    plate = sanitize(plate)
    local keyData = VehiclesWithKeyInside[vehNetId]
    if not keyData or keyData.plate ~= plate or keyData.barcode ~= barcode then return end

    -- Remover temp do dono original e notificá-lo
    local prevOwner = keyData.citizenid
    if TempKeys[prevOwner] then TempKeys[prevOwner][plate] = nil end

    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if Bridge.framework.GetIdentifier(pid) == prevOwner then
            TriggerClientEvent("pr_carkeys:client:keyTakenFromVehicle", pid, plate)
            break
        end
    end

    -- Atualizar dono no banco
    local row = PRCarkeys.Cache.GetKey(barcode)
    if row then
        ExecuteSQL("UPDATE pr_carkeys SET citizenid = ? WHERE barcode = ?", { citizenid, barcode })
        PRCarkeys.Cache.UpdateField(barcode, "citizenid", citizenid)
    end

    local metadata = {
        barcode = barcode,
        plate   = plate,
        label   = ("[%s] %s"):format(keyData.itemName, plate),
    }
    Bridge.inventory.AddItem(src, keyData.itemName, 1, metadata)
    VehiclesWithKeyInside[vehNetId] = nil

    TriggerClientEvent("pr_carkeys:client:keyPickedUp", src, plate)
    Debug("INFO", ("pickupKeyFromVehicle: src=%d | plate=%s"):format(src, plate))
end)

RegisterNetEvent("pr_carkeys:server:returnKeyFromVehicle", function(vehNetId, plate)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    plate = sanitize(plate)
    local keyData = VehiclesWithKeyInside[vehNetId]
    if not keyData or keyData.plate ~= plate then return end

    -- Qualquer player com TempKey pode devolver (inclusive quem não é o dono)
    if TempKeys[citizenid] then TempKeys[citizenid][plate] = nil end

    -- Determina onde devolver:
    -- Se é o dono original → devolve para onde tirou (bolsa ou inventário)
    -- Se é outro player → devolve para o inventário direto desse player (não para a bolsa do dono)
    local isOriginalOwner = (keyData.citizenid == citizenid)
    local targetSrc = src  -- sempre devolve para quem desligou

    -- Chave de carjack: não tem registro no banco, cria item diretamente
    if keyData.isCarjack then
        local vehicleLabel = plate
        local ok2, vrows = pcall(function()
            return ExecuteSQL("SELECT `vehicle` FROM `player_vehicles` WHERE `plate` = ? LIMIT 1", { plate })
        end)
        if ok2 and vrows and vrows[1] then vehicleLabel = vrows[1].vehicle or plate end

        local metadata = {
            label   = "Modelo: " .. vehicleLabel .. "\nPlaca: " .. plate .. "\nSerial: " .. keyData.barcode,
            barcode = keyData.barcode,
            plate   = plate,
            modelo  = vehicleLabel,
            code    = keyData.barcode,
        }
        -- Devolve ao inventário direto de quem desligou (sem stash)
        local added = Bridge.inventory.AddItem(src, "carkey_temp", 1, metadata)
        if not added then
            Debug("WARNING", ("returnKeyFromVehicle(carjack): AddItem FALHOU | src=%d"):format(src))
        else
            Debug("SUCCESS", ("returnKeyFromVehicle(carjack): carkey_temp entregue | src=%d | plate=%s"):format(src, plate))
        end
        VehiclesWithKeyInside[vehNetId] = nil
        TriggerClientEvent("pr_carkeys:client:keyReturnedToInventory", src, plate)
        return
    end

    -- Busca dados completos do banco
    local rows = ExecuteSQL(
        "SELECT barcode, plate, key_type, sound, motor, level, distance, citizenid FROM pr_carkeys WHERE barcode = ? LIMIT 1",
        { keyData.barcode }
    )
    local row = rows and rows[1]

    -- Se a chave expirar enquanto estava na ignição (single_use), não devolve: ela some e o carro já deve ser desligado pela rotina.
    if row and PRCarkeys.IsKeyExpired(row) then
        PRCarkeys.Cache.InvalidateKey(keyData.barcode)
        ExecuteSQL("DELETE FROM pr_carkeys WHERE barcode = ?", { keyData.barcode })
        VehiclesWithKeyInside[vehNetId] = nil
        TriggerClientEvent("pr_carkeys:client:removeTempKey", src, plate)
        Debug("INFO", ("returnKeyFromVehicle: chave expirada na ignicao, removida | barcode=%s | plate=%s"):format(
            tostring(keyData.barcode), tostring(plate)))
        TriggerClientEvent("pr_carkeys:client:keyExpired", src)
        return
    end

    -- Busca modelo do veículo (igual ao givekey)
    local vehicleLabel = plate
    local ok, vrows = pcall(function()
        return ExecuteSQL(
            "SELECT `vehicle` FROM `player_vehicles` WHERE `plate` = ? LIMIT 1",
            { plate }
        )
    end)
    if ok and vrows and vrows[1] and vrows[1].vehicle then
        vehicleLabel = vrows[1].vehicle
    end

    -- Busca nome do dono (igual ao givekey)
    local ownerName = nil
    if Config.Default.KeyMetadata and Config.Default.KeyMetadata.showOwner then
        local fw = PRCarkeys.ActiveResource
        local ok2, nrows = pcall(function()
            if fw == "qb-core" or fw == "qbx-core" then
                return ExecuteSQL(
                    "SELECT `charinfo` FROM `players` WHERE `citizenid` = ? LIMIT 1",
                    { keyData.citizenid }
                )
            end
        end)
        if ok2 and nrows and nrows[1] and nrows[1].charinfo then
            local info = type(nrows[1].charinfo) == "string"
                and json.decode(nrows[1].charinfo) or nrows[1].charinfo
            if info and info.firstname then
                ownerName = info.firstname .. " " .. (info.lastname or "")
            end
        end
    end

    -- Reconstrói label idêntico ao givekey
    local labelLines = {
        "Modelo: " .. vehicleLabel,
        "Placa: "  .. plate,
    }
    if ownerName then
        table.insert(labelLines, "Proprietario: " .. ownerName)
    end
    table.insert(labelLines, "Serial: " .. keyData.barcode)

    local metadata = {
        label         = table.concat(labelLines, "\n"),
        barcode       = keyData.barcode,
        plate         = plate,
        modelo        = vehicleLabel,
        code          = keyData.barcode,
        sound         = row and row.sound    or Config.Sound.soundDefault,
        motor         = row and row.motor    or 0,
        distance      = row and row.distance or Config.Default.UseKeyAnim.DefaultDistance,
    }
    if ownerName then
        metadata.proprietario = ownerName
    end

    Debug("INFO", ("returnKeyFromVehicle: adicionando item | item=%s | barcode=%s | owner=%s | isOriginalOwner=%s"):format(
        tostring(keyData.itemName),
        tostring(metadata.barcode),
        tostring(keyData.citizenid),
        tostring(isOriginalOwner)
    ))

    local added = false

    if keyData.fromStash then
        -- Verifica se quem desligou possui a bolsa da qual a chave saiu
        local bagName = nil
        local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, "carkey_bag", nil)
        if bagSlots then
            for _, bagSlot in pairs(bagSlots) do
                local bagMeta = bagSlot.metadata or {}
                if bagMeta.barcode and ("pr_carkeys_bag_" .. bagMeta.barcode) == keyData.fromStash then
                    bagName = keyData.fromStash
                    break
                end
            end
        end
        if not bagName then
            local bagSlotsLarge = exports.ox_inventory:GetSlotsWithItem(src, "carkey_bag_large", nil)
            if bagSlotsLarge then
                for _, bagSlot in pairs(bagSlotsLarge) do
                    local bagMeta = bagSlot.metadata or {}
                    if bagMeta.barcode and ("pr_carkeys_bag_" .. bagMeta.barcode) == keyData.fromStash then
                        bagName = keyData.fromStash
                        break
                    end
                end
            end
        end

        if bagName then
            -- Quem desligou tem a bolsa → garante que stash está registrada antes de adicionar
            if ActiveInventory == "ox_inventory" then
                local bagBarcode = keyData.fromStash:gsub("pr_carkeys_bag_", "")
                -- Usa a configuração correta da bolsa (salva ao remover), com fallback seguro
                local bagCfg = Config.Bags[(keyData.fromBagItem or "")] or Config.Bags.carkey_bag or { label = "Bolsa de Chaves", slots = 10, weight = 5000 }
                -- RegisterStash garante que a stash está carregada e aceita items
                exports.ox_inventory:RegisterStash(
                    keyData.fromStash,
                    bagCfg.label .. " | " .. bagBarcode,
                    bagCfg.slots,
                    bagCfg.weight,
                    false
                )
                -- Pequeno wait para o ox_inventory processar o RegisterStash
                Wait(100)
            end
            added = exports.ox_inventory:AddItem(keyData.fromStash, keyData.itemName, 1, metadata)
            Debug("INFO", ("returnKeyFromVehicle: quem desligou tem a bolsa | stash=%s | src=%d"):format(keyData.fromStash, src))
        else
            -- Quem desligou não tem a bolsa → devolve ao inventário direto
            added = exports.ox_inventory:AddItem(src, keyData.itemName, 1, metadata)
            Debug("INFO", ("returnKeyFromVehicle: bolsa nao encontrada com src=%d → inventario direto"):format(src))
        end
    else
        -- Chave veio do inventário direto → devolve ao inventário de quem desligou
        added = exports.ox_inventory:AddItem(src, keyData.itemName, 1, metadata)
        Debug("INFO", ("returnKeyFromVehicle: devolvida ao inventario | src=%d"):format(src))
    end

    if not added then
        Debug("WARNING", ("returnKeyFromVehicle: AddItem FALHOU | src=%d | item=%s"):format(
            src, keyData.itemName))
    else
        Debug("SUCCESS", ("returnKeyFromVehicle: devolvida | src=%d | plate=%s"):format(src, plate))
    end

    VehiclesWithKeyInside[vehNetId] = nil
    TriggerClientEvent("pr_carkeys:client:keyReturnedToInventory", src, plate)
    Debug("INFO", ("returnKeyFromVehicle: finalizado | src=%d | plate=%s"):format(src, plate))
end)

-- ================================================================
--   CHAVES TEMPORÁRIAS
-- ================================================================

function PRCarkeys.GiveTempKey(src, plate, kind)
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end
    plate = sanitize(plate)
    if not TempKeys[citizenid] then TempKeys[citizenid] = {} end
    TempKeys[citizenid][plate] = { kind = kind or "granted" }
    TriggerClientEvent("pr_carkeys:client:addTempKey", src, plate)
    Debug("INFO", ("GiveTempKey: src=%d | plate=%s"):format(src, plate))
end

function PRCarkeys.RemoveTempKey(src, plate)
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end
    plate = sanitize(plate)
    if TempKeys[citizenid] then TempKeys[citizenid][plate] = nil end
    TriggerClientEvent("pr_carkeys:client:removeTempKey", src, plate)
end

RegisterNetEvent("pr_carkeys:server:syncTempKeys", function()
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end
    local keys = TempKeys[citizenid] or {}
    for plate, _ in pairs(keys) do
        TriggerClientEvent("pr_carkeys:client:addTempKey", src, plate)
    end
end)

AddEventHandler("playerDropped", function()
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end
    TempKeys[citizenid] = nil
end)

-- ================================================================
--   BUSCAR DADOS DO BANCO (distance, sound, motor)
-- ================================================================

RegisterNetEvent("pr_carkeys:server:fetchKeyDbData", function(plate, barcode)
    local src = source
    if not Bridge.framework.GetIdentifier(src) then return end
    if not plate then return end

    plate = sanitize(plate)
    local rows

    -- Se temos o barcode (do metadata do item), busca direto por ele
    if barcode then
        rows = ExecuteSQL(
            "SELECT barcode, sound, motor, distance FROM pr_carkeys WHERE barcode = ? LIMIT 1",
            { barcode }
        )
    else
        -- Fallback: busca pela placa (pega a primeira chave encontrada)
        rows = ExecuteSQL(
            "SELECT barcode, sound, motor, distance FROM pr_carkeys WHERE plate = ? LIMIT 1",
            { plate }
        )
    end

    local row = rows and rows[1]
    if not row then return end

    TriggerClientEvent("pr_carkeys:client:keyDbData", src, {
        plate    = plate,
        barcode  = row.barcode,
        sound    = row.sound,
        motor    = row.motor,
        distance = row.distance,
    })
end)

-- ================================================================
--   BUSCAR DADOS DE TODAS AS CHAVES DO PLAYER DE UMA VEZ
--   Chamado após RebuildFromInventory para popular distance/sound/motor
-- ================================================================
RegisterNetEvent("pr_carkeys:server:fetchAllKeyDbData", function(barcodes)
    local src = source
    if not Bridge.framework.GetIdentifier(src) then return end
    if not barcodes or #barcodes == 0 then return end

    -- Uma query só com IN (?, ?, ...)
    local placeholders = table.concat(
        (function()
            local t = {}
            for _ = 1, #barcodes do t[#t+1] = "?" end
            return t
        end)(), ", "
    )

    local rows = ExecuteSQL(
        ("SELECT barcode, plate, sound, motor, distance FROM pr_carkeys WHERE barcode IN (%s)"):format(placeholders),
        barcodes
    )

    if not rows then return end

    local result = {}
    for _, row in ipairs(rows) do
        result[#result+1] = {
            plate    = sanitize(row.plate),
            barcode  = row.barcode,
            sound    = row.sound,
            motor    = row.motor,
            distance = row.distance,
        }
    end

    TriggerClientEvent("pr_carkeys:client:allKeyDbData", src, result)
end)

-- ================================================================
--   SOM DE TRANCA
-- ================================================================

RegisterNetEvent("pr_carkeys:server:playLockSound", function(coords, soundId)
    local src = source
    if not coords or not soundId then return end
    if not GetResourceState("pr_3dsound"):find("start") then return end
    local soundFile = PRCarkeys.ResolveSoundFile(soundId)
    if not soundFile then return end
    local uid = ("lock_%d_%d"):format(src, GetGameTimer())
    exports["pr_3dsound"]:Play(
        vector3(coords.x, coords.y, coords.z),
        soundFile, Config.Sound.volume, Config.Sound.radius,
        uid, "pr_carkeys", false
    )
end)

-- ================================================================
--   VERIFICAÇÃO DE POLICIAL
-- ================================================================

function PRCarkeys.IsPlayerPolice(src)
    if not Config.Police or not Config.Police.enabled then return false end
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return false end
    local fw = PRCarkeys.ActiveResource
    if fw == "qb-core" or fw == "qbx-core" then
        local Player = Bridge.framework.GetPlayer(src)
        if not Player then return false end
        local jobName = Player.PlayerData.job and Player.PlayerData.job.name
        for _, job in ipairs(Config.Police.jobs) do
            if jobName == job then return true end
        end
    elseif fw == "es_extended" then
        local xPlayer = Bridge.framework.GetPlayer(src)
        if not xPlayer then return false end
        local jobName = xPlayer.getJob and xPlayer.getJob().name
        for _, job in ipairs(Config.Police.jobs) do
            if jobName == job then return true end
        end
    elseif fw == "ox_core" then
        local player = Bridge.framework.GetPlayer(src)
        if not player then return false end
        local groups = player.getGroups and player.getGroups() or {}
        for _, job in ipairs(Config.Police.jobs) do
            if groups[job] then return true end
        end
    end
    return false
end

-- ================================================================
--   COMPAT qb-vehiclekeys / qbx_vehiclekeys
-- ================================================================

RegisterNetEvent("qb-vehiclekeys:server:setVehLockState", function(vehNetId, state)
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 then return end
    SetVehicleDoorsLocked(vehicle, state)
    Entity(vehicle).state:set("doorslockstate", state, true)
end)

RegisterNetEvent("qb-vehiclekeys:server:AcquireVehicleKeys", function(plate)
    PRCarkeys.GiveTempKey(source, plate)
end)

RegisterNetEvent("mm_carkeys:server:acquiretempvehiclekeys", function(plate)
    PRCarkeys.GiveTempKey(source, plate)
end)

--- Hotwire / minigame (client): valida motorista+veículo e concede TempKey via export interno.
RegisterNetEvent("pr_carkeys:server:grantTemporaryVehicleAccess", function(vehNetId, plate)
    local src = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "no_citizenid")
        return
    end

    vehNetId = tonumber(vehNetId)
    if not vehNetId then
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "invalid_netid")
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Debug("WARNING", ("grantTemporaryVehicleAccess: veiculo invalido | src=%d | net=%s"):format(src, tostring(vehNetId)))
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "invalid_vehicle")
        return
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or not IsPedInVehicle(ped, vehicle, false) then
        Debug("WARNING", ("grantTemporaryVehicleAccess: player fora do veiculo | src=%d"):format(src))
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "not_in_vehicle")
        return
    end

    if PRCarkeys.IsVehicleBlacklisted(vehicle) then
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "blacklisted")
        return
    end

    local vPlate = sanitize(GetVehicleNumberPlateText(vehicle))
    local pPlate = plate and sanitize(tostring(plate)) or nil
    if pPlate and pPlate ~= "" and pPlate ~= vPlate then
        Debug("WARNING", ("grantTemporaryVehicleAccess: placa mismatch | enviada=%s veiculo=%s | src=%d"):format(
            tostring(pPlate), tostring(vPlate), src))
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "plate_mismatch")
        return
    end

    local finalPlate = (pPlate and pPlate ~= "") and pPlate or vPlate
    if not finalPlate or finalPlate == "" then
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "invalid_plate")
        return
    end

    local grantKey = ("%s:%s"):format(tostring(src), finalPlate)
    local nowMs = GetGameTimer()
    local lastGrant = RecentTempKeyGrants[grantKey]
    if lastGrant and (nowMs - lastGrant) < 10000 then
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, true, "already_granted")
        return
    end
    if hasTemporaryItemForPlate(src, finalPlate) then
        RecentTempKeyGrants[grantKey] = nowMs
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, true, "already_has_item")
        return
    end

    -- Entrega o ITEM físico de chave temporária (carkey_temp).
    -- Isso garante que validações de lock/motor dependam de inventário/bolsa (regra do projeto).
    local ok, barcode = pcall(function()
        return PRCarkeys.CreateTempKeyItem(src, finalPlate, "carkey_temp")
    end)
    if not ok or not barcode then
        Debug("WARNING", ("grantTemporaryVehicleAccess: falhou criar item | src=%d | plate=%s"):format(src, finalPlate))
        TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, false, "additem_failed")
        return
    end
    RecentTempKeyGrants[grantKey] = nowMs
    Debug("SUCCESS", ("grantTemporaryVehicleAccess: carkey_temp entregue | src=%d | plate=%s | barcode=%s"):format(
        src, finalPlate, tostring(barcode)))
    TriggerClientEvent("pr_carkeys:client:grantTempAccessResult", src, true, tostring(barcode))
end)

-- Entrega carkey_temp (item) por proximidade — usado quando o NPC foge e o player o mata e "pega a chave".
RegisterNetEvent("pr_carkeys:server:grantTemporaryKeyItemNearbyVehicle", function(vehNetId, plate)
    local src = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    vehNetId = tonumber(vehNetId)
    if not vehNetId then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "invalid_netid")
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "invalid_vehicle")
        return
    end
    if PRCarkeys.IsVehicleBlacklisted(vehicle) then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "blacklisted")
        return
    end

    local vPlate = sanitize(GetVehicleNumberPlateText(vehicle))
    local pPlate = plate and sanitize(tostring(plate)) or nil
    if pPlate and pPlate ~= "" and pPlate ~= vPlate then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "plate_mismatch")
        return
    end
    local finalPlate = (pPlate and pPlate ~= "") and pPlate or vPlate
    if not finalPlate or finalPlate == "" then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "invalid_plate")
        return
    end

    local pPed = GetPlayerPed(src)
    if pPed == 0 then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "invalid_ped")
        return
    end

    local pCoords = GetEntityCoords(pPed)
    local vCoords = GetEntityCoords(vehicle)
    if #(pCoords - vCoords) > 12.0 then
        Debug("WARNING", ("grantTemporaryKeyItemNearbyVehicle: longe do veiculo | src=%d | dist=%.1f"):format(
            src, #(pCoords - vCoords)))
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "too_far")
        return
    end

    local ok, barcode = pcall(function()
        return PRCarkeys.CreateTempKeyItem(src, finalPlate, "carkey_temp")
    end)
    if not ok or not barcode then
        TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, false, "additem_failed")
        return
    end

    Debug("SUCCESS", ("grantTemporaryKeyItemNearbyVehicle: carkey_temp entregue | src=%d | plate=%s | barcode=%s"):format(
        src, finalPlate, tostring(barcode)))
    TriggerClientEvent("pr_carkeys:client:carjackLootKeyResult", src, true, barcode)
end)

exports("GiveTempKey",    function(src, plate) PRCarkeys.GiveTempKey(src, plate) end)
exports("RemoveTempKey",  function(src, plate) PRCarkeys.RemoveTempKey(src, plate) end)
exports("IsPlayerPolice", function(src) return PRCarkeys.IsPlayerPolice(src) end)
exports("SetLockState",   function(vehicle, state)
    if not vehicle or vehicle == 0 then return end
    SetVehicleDoorsLocked(vehicle, state)
    Entity(vehicle).state:set("doorslockstate", state, true)
end)
exports("GiveKeys", function(src, vehicle)
    local plate = type(vehicle) == "number" and vehicle > 0
        and GetVehicleNumberPlateText(vehicle)
        or tostring(vehicle)
    if plate then PRCarkeys.GiveTempKey(src, plate) end
end)

-- ================================================================
--   BUSCA CHAVES NAS BOLSAS DO PLAYER (server-side)
--   Client não consegue acessar stash diretamente
-- ================================================================
lib.callback.register("pr_carkeys:server:getKeysInBags", function(src)
    if not Bridge.framework.GetIdentifier(src) then return {} end

    local result = {}
    if ActiveInventory ~= "ox_inventory" then return result end

    for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
        local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, bagName, nil)
        if bagSlots then
            for _, bagSlot in pairs(bagSlots) do
                local bagMeta = bagSlot.metadata or {}
                if bagMeta.barcode then
                    local stashId = "pr_carkeys_bag_" .. bagMeta.barcode
                    for itemName, _ in pairs(Config.KeyTypes) do
                        local keySlots = exports.ox_inventory:GetInventoryItems(stashId)
                        if keySlots then
                            for _, kItem in pairs(keySlots) do
                                if kItem and kItem.name == itemName then
                                    local kMeta = kItem.metadata or {}
                                    if kMeta.plate and kMeta.barcode then
                                        table.insert(result, {
                                            name     = kItem.name,
                                            metadata = kMeta,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end)

-- ================================================================
--   CARJACK — Registra chave na ignição do veículo
--   Player só recebe carkey_temp quando desligar o motor
-- ================================================================
RegisterNetEvent("pr_carkeys:server:carjackRegisterKey", function(plate, vehNetId)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid or not plate or not vehNetId then return end

    plate = sanitize(plate)

    -- Gera barcode único para esta chave temporária
    local barcode = PRCarkeys.GenerateBarcode()

    -- Registra chave na ignição do veículo (igual ao keyLeftInVehicle mas sem item no inventário)
    VehiclesWithKeyInside[vehNetId] = {
        plate     = plate,
        barcode   = barcode,
        citizenid = citizenid,
        itemName  = "carkey_temp",
        fromStash = nil,
        isCarjack = true,  -- marca para saber que não veio do inventário
    }

    -- TempKey para que o player possa trancar/destrancar e ligar/desligar
    if not TempKeys[citizenid] then TempKeys[citizenid] = {} end
    TempKeys[citizenid][plate] = { kind = "vehicle" }
    TriggerClientEvent("pr_carkeys:client:addTempKey", src, plate)

    Debug("SUCCESS", ("carjackRegisterKey: chave na ignicao | src=%d | plate=%s | barcode=%s"):format(
        src, plate, barcode))
end)

-- Mantém compatibilidade com evento antigo
RegisterNetEvent("pr_carkeys:server:carjackSuccess", function(plate)
    -- Redireciona para o novo fluxo se chamado (retrocompatibilidade)
    local src = source
    Debug("INFO", ("carjackSuccess: redirecionando para carjackRegisterKey | src=%d"):format(src))
end)
