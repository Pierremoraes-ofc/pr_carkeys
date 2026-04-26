-- ============================================================
--   pr_carkeys — server/sv_bag.lua
--   Lógica server-side das bolsas de chave.
-- ============================================================

-- ----------------------------------------------------------------
-- Interno: registra stash e envia abertura ao client
-- ----------------------------------------------------------------
local function openBagStash(src, stashId, bagConfig)
    Bridge.inventory.RegisterStash(
        stashId,
        bagConfig.label .. " | " .. stashId:gsub("pr_carkeys_bag_", ""),
        bagConfig.slots,
        bagConfig.weight,
        false
    )

    if ActiveInventory == "ox_inventory" then
        -- Client abre via export local (evita "cannot open inventory is busy")
        TriggerClientEvent("pr_carkeys:client:openStash", src, stashId)
    else
        exports["qb-inventory"]:OpenInventory(src, stashId, {
            label     = bagConfig.label,
            maxweight = bagConfig.weight,
            slots     = bagConfig.slots,
        })
    end
end

-- ----------------------------------------------------------------
-- Interno: garante barcode na metadata da bolsa (lazy init)
-- ----------------------------------------------------------------
local function ensureBagBarcode(src, slot, item, bagConfig)
    local metadata = {}

    if ActiveInventory == "ox_inventory" then
        local slotData = Bridge.inventory.GetItemBySlot(src, slot)
        metadata = (slotData and (slotData.metadata or slotData.info)) or {}
    else
        local Player = Bridge.framework.GetPlayer(src)
        if Player then
            local slotItem = Player.PlayerData.items and Player.PlayerData.items[slot]
            metadata = (slotItem and (slotItem.info or slotItem.metadata)) or {}
        end
    end

    if not metadata.barcode then
        metadata.barcode = PRCarkeys.GenerateBarcode()
        metadata.label   = bagConfig.label
        Bridge.inventory.SetMetadata(src, slot, metadata)
        Debug("INFO", ("ensureBagBarcode: barcode gerado | slot=%d | barcode=%s"):format(slot, metadata.barcode))
    end

    return metadata
end

-- ----------------------------------------------------------------
-- Interno: busca todas as chaves de um stash em UMA única query
-- ----------------------------------------------------------------
local function getKeysFromStash(stashId)
    local rawInventory = Bridge.inventory.GetInventory(stashId) or {}
    local itemsTable   = (type(rawInventory) == "table" and rawInventory.items) or rawInventory

    -- Coletar barcodes das chaves presentes no stash
    local barcodes    = {}
    local keySlotMap  = {}  -- barcode → slotItem

    for _, slotItem in pairs(itemsTable) do
        if type(slotItem) == "table" and slotItem.name and PRCarkeys.IsKey(slotItem.name) then
            local meta = slotItem.metadata or slotItem.info or {}
            if meta.barcode then
                table.insert(barcodes, meta.barcode)
                keySlotMap[meta.barcode] = slotItem
            end
        end
    end

    if #barcodes == 0 then return {} end

    -- Uma única query com IN (?, ?, ...)
    local placeholders = table.concat(
        (function()
            local t = {}
            for _ = 1, #barcodes do table.insert(t, "?") end
            return t
        end)(),
        ", "
    )

    local rows = ExecuteSQL(
        ("SELECT id, barcode, citizenid, plate, key_type, sound, motor, level, distance, expires_at FROM pr_carkeys WHERE barcode IN (%s)"):format(placeholders),
        barcodes
    )

    -- Montar índice barcode → row do banco
    local dbIndex = {}
    if rows then
        for _, row in ipairs(rows) do
            dbIndex[row.barcode] = row
        end
    end

    -- Compor resultado final
    local keysInBag = {}
    for barcode, slotItem in pairs(keySlotMap) do
        local meta = slotItem.metadata or slotItem.info or {}
        local row  = dbIndex[barcode]
        table.insert(keysInBag, {
            slot      = slotItem.slot,
            itemName  = slotItem.name,
            itemLabel = Config.KeyTypes[slotItem.name] and Config.KeyTypes[slotItem.name].label or slotItem.name,
            metadata  = meta,
            dbData    = row,
        })
    end

    return keysInBag
end

-- ----------------------------------------------------------------
-- Interno: monta e envia keyData ao client (evita duplicação)
-- ----------------------------------------------------------------
local function sendKeySubMenu(src, row)
    if not row then return end

    TriggerClientEvent("pr_carkeys:client:openKeySubMenu", src, {
        barcode    = row.barcode,
        citizenid  = row.citizenid,
        plate      = row.plate,
        key_type   = row.key_type,
        sound      = row.sound,
        motor      = row.motor,
        level      = row.level,
        distance   = row.distance,
        expires_at = row.expires_at,
    })
end

-- ================================================================
--   EVENTOS
-- ================================================================

-- Abertura da bolsa como stash (modo 1 — visual)
RegisterNetEvent("pr_carkeys:server:openBag", function(slot)
    local src     = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local item = Bridge.inventory.GetItemBySlot(src, slot)
    if not item then
        Debug("WARNING", ("openBag: slot %d vazio para src %d"):format(slot, src))
        return
    end

    local bagConfig = Config.Bags[item.name]
    if not bagConfig then return end

    local metadata = ensureBagBarcode(src, slot, item.name, bagConfig)
    local stashId  = PRCarkeys.GetStashId(metadata.barcode)

    Debug("INFO", ("openBag: src=%d | stash=%s"):format(src, stashId))
    openBagStash(src, stashId, bagConfig)
end)

-- Gerenciamento da bolsa (modo 2 — menu)
RegisterNetEvent("pr_carkeys:server:manageBag", function(slot)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local item = Bridge.inventory.GetItemBySlot(src, slot)
    if not item then return end

    local bagConfig = Config.Bags[item.name]
    if not bagConfig then return end

    local metadata = ensureBagBarcode(src, slot, item.name, bagConfig)
    local stashId  = PRCarkeys.GetStashId(metadata.barcode)

    -- Garantir stash registrado antes de buscar itens
    Bridge.inventory.RegisterStash(
        stashId,
        bagConfig.label .. " | " .. stashId:gsub("pr_carkeys_bag_", ""),
        bagConfig.slots,
        bagConfig.weight,
        false
    )

    local keysInBag = getKeysFromStash(stashId)

    Debug("INFO", ("manageBag: src=%d | stash=%s | chaves=%d"):format(src, stashId, #keysInBag))

    TriggerClientEvent("pr_carkeys:client:openManageMenu", src, {
        bagLabel = bagConfig.label,
        stashId  = stashId,
        slot     = slot,
        keys     = keysInBag,
    })
end)

-- Gerenciar chave diretamente pelo slot do inventário
RegisterNetEvent("pr_carkeys:server:manageKey", function(slot)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local item    = Bridge.inventory.GetItemBySlot(src, slot)
    if not item then return end

    local meta    = item.metadata or item.info or {}
    local barcode = meta.barcode
    if not barcode then
        Debug("WARNING", ("manageKey: item no slot %d sem barcode. src=%d"):format(slot, src))
        return
    end

    local row = PRCarkeys.Cache.GetKey(barcode)
    if not row then
        Debug("WARNING", ("manageKey: barcode '%s' nao encontrado. src=%d"):format(barcode, src))
        return
    end

    Debug("INFO", ("manageKey: src=%d | barcode=%s | plate=%s"):format(src, row.barcode, row.plate))
    sendKeySubMenu(src, row)
end)

-- Gerenciar chave pelo barcode (botão do ox_inventory ou stash)
RegisterNetEvent("pr_carkeys:server:manageKeyByBarcode", function(barcode)
    local src = source
    if not Bridge.framework.GetIdentifier(src) then return end
    if not barcode or barcode == "" then return end

    local row = PRCarkeys.Cache.GetKey(barcode)
    if not row then
        Debug("WARNING", ("manageKeyByBarcode: barcode '%s' nao encontrado. src=%d"):format(barcode, src))
        return
    end

    Debug("INFO", ("manageKeyByBarcode: src=%d | barcode=%s | plate=%s"):format(src, row.barcode, row.plate))
    sendKeySubMenu(src, row)
end)
