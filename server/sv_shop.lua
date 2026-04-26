-- ============================================================
--   pr_carkeys — server/sv_shop.lua
--   Exports para integração com lojas/NPCs externos.
--
--   Como usar em outro resource:
--
--   -- Comprar chave original (plate já vinculada)
--   exports["pr_carkeys"]:BuyOriginalKey(source, plate, duration)
--
--   -- Tirar cópia de uma chave existente
--   exports["pr_carkeys"]:CopyKey(source, originalBarcode, duration)
--
--   Ambos retornam: { success, barcode, reason }
--   'duration' é opcional — só usado em chaves temporárias (segundos)
--
--   Chave temporária lógica (hotwire / minigame / integração externa):
--     exports["pr_carkeys"]:GiveTempKey(source, plate)
--   Ou evento interno (servidor valida motorista + placa do veículo):
--     TriggerServerEvent("pr_carkeys:server:grantTemporaryVehicleAccess", netId, plate)
-- ============================================================

-- ----------------------------------------------------------------
-- Interno: gera barcode único sem colisão no cache
-- ----------------------------------------------------------------
local function generateUniqueBarcode()
    local barcode  = PRCarkeys.GenerateBarcode()
    local attempts = 0
    while attempts < 10 do
        if not PRCarkeys.Cache.GetKey(barcode) then break end
        barcode  = PRCarkeys.GenerateBarcode()
        attempts = attempts + 1
    end
    return barcode
end

-- ----------------------------------------------------------------
-- Interno: insere chave no banco, popula cache e entrega ao jogador
-- ----------------------------------------------------------------
local function deliverKeyItem(src, citizenid, plate, keyType, level, barcode, expiresAt)
    local itemName = PRCarkeys.ResolveKeyItem(keyType, level)
    if not itemName then
        Debug("ERROR", ("deliverKeyItem: nenhum item para keyType='%s' level='%s'"):format(keyType, level))
        return false, "item_not_found"
    end

    local insertId = ExecuteSQLInsert(
        [[INSERT INTO pr_carkeys (barcode, citizenid, plate, key_type, sound, motor, level, distance, expires_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            barcode,
            citizenid,
            plate,
            keyType,
            Config.Sound.soundDefault,
            0,
            level,
            Config.Default.UseKeyAnim.DefaultDistance,
            expiresAt,
        }
    )

    if not insertId then
        Debug("ERROR", ("deliverKeyItem: falha no INSERT | plate=%s | barcode=%s"):format(plate, barcode))
        return false, "db_error"
    end

    PRCarkeys.Cache.SetKey(barcode, {
        id         = insertId,
        barcode    = barcode,
        citizenid  = citizenid,
        plate      = plate,
        key_type   = keyType,
        sound      = Config.Sound.soundDefault,
        motor      = 0,
        level      = level,
        distance   = Config.Default.UseKeyAnim.DefaultDistance,
        expires_at = expiresAt,
    })

    local labelType = level == "original" and "ORIGINAL" or "COPIA"
    local metadata = {
        label   = ("Placa: %s\nTipo: %s\nSerial: %s"):format(plate, labelType, barcode),
        barcode = barcode,
        plate   = plate,
    }

    Bridge.inventory.AddItem(src, itemName, 1, metadata)

    Debug("SUCCESS", ("deliverKeyItem: entregue | src=%d | item=%s | plate=%s | barcode=%s | type=%s")
        :format(src, itemName, plate, barcode, keyType))

    return true, barcode
end

-- ================================================================
--   EXPORT: BuyOriginalKey
-- ================================================================
exports("BuyOriginalKey", function(src, plate, duration)
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then
        return { success = false, reason = "player_not_found" }
    end

    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then
        return { success = false, reason = "invalid_plate" }
    end

    local keyType   = duration and "temporary" or "permanent"
    local expiresAt = duration and (os.time() + tonumber(duration)) or nil
    local barcode   = generateUniqueBarcode()

    local ok, result = deliverKeyItem(src, citizenid, plate, keyType, "original", barcode, expiresAt)

    if not ok then
        return { success = false, reason = result }
    end

    Bridge.notify.Notify(src, {
        title       = "Chave Original",
        description = ("Chave original criada para o veiculo %s."):format(plate),
        type        = "success",
    })

    return { success = true, barcode = barcode }
end)

-- ================================================================
--   EXPORT: CopyKey
-- ================================================================
exports("CopyKey", function(src, originalBarcode, duration)
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then
        return { success = false, reason = "player_not_found" }
    end

    local original = PRCarkeys.Cache.GetKey(originalBarcode)
    if not original then
        return { success = false, reason = "original_not_found" }
    end

    if original.key_type == "single_use" then
        return { success = false, reason = "cannot_copy_single_use" }
    end

    local plate     = original.plate
    local keyType   = duration and "temporary" or "permanent"
    local expiresAt = duration and (os.time() + tonumber(duration)) or nil
    local barcode   = generateUniqueBarcode()

    local ok, result = deliverKeyItem(src, citizenid, plate, keyType, "copy", barcode, expiresAt)

    if not ok then
        return { success = false, reason = result }
    end

    Bridge.notify.Notify(src, {
        title       = "Copia de Chave",
        description = ("Copia criada para o veiculo %s."):format(plate),
        type        = "success",
    })

    Debug("SUCCESS", ("CopyKey: original=%s → nova=%s | plate=%s"):format(originalBarcode, barcode, plate))

    return { success = true, barcode = barcode }
end)
