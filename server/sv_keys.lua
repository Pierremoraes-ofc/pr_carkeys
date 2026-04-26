-- ============================================================
--   pr_carkeys — server/sv_keys.lua
--   CRUD das chaves + tocar som 3D via pr_3dsound
-- ============================================================

-- ----------------------------------------------------------------
-- Criar chave no banco
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:server:createKey", function(data)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    if not data or not data.plate or not data.barcode then
        Debug("ERROR", ("createKey: dados invalidos de src=%d"):format(src))
        return
    end

    local plate    = PRCarkeys.SanitizePlate(data.plate)
    if not plate then
        Debug("ERROR", ("createKey: placa invalida de src=%d"):format(src))
        return
    end

    local keyType   = data.key_type or "permanent"
    local soundId   = data.sound    or Config.Sound.soundDefault
    local motor     = data.motor    and 1 or 0
    local level     = data.level    or "original"
    local distance  = data.distance or Config.Default.UseKeyAnim.DefaultDistance
    local expiresAt = nil

    if (keyType == "temporary" or keyType == "single_use") and data.duration then
        expiresAt = os.time() + tonumber(data.duration)
    end

    -- Anti-dup via cache
    if PRCarkeys.Cache.GetKey(data.barcode) then
        TriggerClientEvent("pr_carkeys:client:keyCreated", src, { success = true, barcode = data.barcode })
        return
    end

    local insertId = ExecuteSQLInsert(
        [[INSERT INTO pr_carkeys (barcode, citizenid, plate, key_type, sound, motor, level, distance, expires_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { data.barcode, citizenid, plate, keyType, soundId, motor, level, distance, expiresAt }
    )

    if insertId then
        PRCarkeys.Cache.SetKey(data.barcode, {
            id = insertId, barcode = data.barcode, citizenid = citizenid,
            plate = plate, key_type = keyType, sound = soundId,
            motor = motor, level = level, distance = distance, expires_at = expiresAt,
        })
        Debug("SUCCESS", ("createKey: chave criada | barcode=%s | plate=%s"):format(data.barcode, plate))
    else
        Debug("ERROR", ("createKey: falha no INSERT | barcode=%s"):format(data.barcode))
    end

    TriggerClientEvent("pr_carkeys:client:keyCreated", src, { success = insertId ~= nil, barcode = data.barcode })
end)

-- ----------------------------------------------------------------
-- Usar chave — validar e tocar som via pr_3dsound
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:server:useKey", function(barcode, netId, vehicleCoords)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local row = PRCarkeys.Cache.GetKey(barcode)

    if not row then
        Debug("WARNING", ("useKey: barcode '%s' nao encontrado."):format(barcode))
        Bridge.notify.Notify(src, Config.Notify.vehicleNotFound)
        return
    end

    if PRCarkeys.IsKeyExpired(row) then
        Bridge.notify.Notify(src, Config.Notify.keyExpired)
        PRCarkeys.Cache.InvalidateKey(barcode)
        -- Deletar do banco
        ExecuteSQL("DELETE FROM pr_carkeys WHERE barcode = ?", { barcode })
        -- Notificar client para apenas exibir mensagem (sem consumeSingleUseKey)
        TriggerClientEvent("pr_carkeys:client:keyExpired", src)
        return
    end

    -- Som 3D para todos os players no raio
    if vehicleCoords and GetResourceState("pr_3dsound"):find("start") then
        local soundFile = PRCarkeys.ResolveSoundFile(row.sound)
        if soundFile then
            local uniqueId = "carkey_" .. barcode .. "_" .. GetGameTimer()
            exports["pr_3dsound"]:Play(
                vector3(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z),
                soundFile,
                Config.Sound.volume,
                Config.Sound.radius,
                uniqueId,
                "pr_carkeys",
                false
            )
        end
    end

    local keyData = {
        barcode  = row.barcode,
        plate    = row.plate,
        sound    = row.sound,
        motor    = row.motor == 1,
        distance = row.distance,
        key_type = row.key_type,
        level    = row.level,
        netId    = netId,
    }

    -- single_use (modo cronômetro) NÃO é consumida ao usar.
    -- Ela expira por tempo e é limpa por rotina de expiração.

    TriggerClientEvent("pr_carkeys:client:executeUseKey", src, keyData)
end)

-- ----------------------------------------------------------------
-- Atualizar campo de uma chave (sound, motor, distance)
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:server:updateKeyConfig", function(barcode, field, value)
    local src = source
    if not Bridge.framework.GetIdentifier(src) then return end

    local editableFields = { sound = true, motor = true, distance = true }
    if not editableFields[field] then
        Debug("WARNING", ("updateKeyConfig: campo '%s' nao editavel. src=%d"):format(field, src))
        return
    end

    local row = PRCarkeys.Cache.GetKey(barcode)
    if not row then
        Debug("WARNING", ("updateKeyConfig: barcode '%s' nao encontrado."):format(barcode))
        return
    end

    ExecuteSQL(
        ("UPDATE pr_carkeys SET `%s` = ? WHERE barcode = ?"):format(field),
        { value, barcode }
    )

    PRCarkeys.Cache.UpdateField(barcode, field, value)

    Debug("SUCCESS", ("updateKeyConfig: barcode=%s | %s=%s"):format(barcode, field, tostring(value)))

    TriggerClientEvent("pr_carkeys:client:keyConfigUpdated", src, barcode, field, value)
end)

-- ----------------------------------------------------------------
-- Callback: buscar dados de uma chave (cache first)
-- ----------------------------------------------------------------
local function getKeyDataHandler(src, barcode)
    if not Bridge.framework.GetIdentifier(src) then return nil end

    local row = PRCarkeys.Cache.GetKey(barcode)
    if not row then return nil end

    if PRCarkeys.IsKeyExpired(row) then
        PRCarkeys.Cache.InvalidateKey(barcode)
        return { expired = true, barcode = barcode }
    end

    return row
end

-- Registro via lib.callback (ox_lib) se disponível, senão via NetEvent
if GetResourceState("ox_lib"):find("start") then
    -- Aguarda lib estar inicializado
    SetTimeout(200, function()
        if lib and lib.callback then
            lib.callback.register("pr_carkeys:server:getKeyData", getKeyDataHandler)
        else
            RegisterNetEvent("pr_carkeys:server:getKeyData", function(barcode)
                local src    = source
                local result = getKeyDataHandler(src, barcode)
                TriggerClientEvent("pr_carkeys:client:getKeyDataReturn", src, result)
            end)
        end
    end)
else
    RegisterNetEvent("pr_carkeys:server:getKeyData", function(barcode)
        local src    = source
        local result = getKeyDataHandler(src, barcode)
        TriggerClientEvent("pr_carkeys:client:getKeyDataReturn", src, result)
    end)
end

-- ----------------------------------------------------------------
-- Deletar chave
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:server:deleteKey", function(barcode)
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local row = PRCarkeys.Cache.GetKey(barcode)
    if not row then return end

    ExecuteSQL("DELETE FROM pr_carkeys WHERE barcode = ?", { barcode })
    PRCarkeys.Cache.InvalidateKey(barcode)

    Debug("SUCCESS", ("deleteKey: removida | barcode=%s"):format(barcode))
end)

-- ----------------------------------------------------------------
-- Consumir chave de uso único do inventário do player
-- Chamado apenas quando key_type == "single_use" e já foi usada.
-- ----------------------------------------------------------------
-- OBS: consumeSingleUseKey removido.
-- single_use agora expira por timer e é removida automaticamente.
