-- ============================================================
--   pr_carkeys — server/sv_commands.lua
--   /givekey [id] [tipo] [placa]
-- ============================================================

-- fw acessível no escopo do arquivo via PRCarkeys.ActiveResource
local fw = PRCarkeys.ActiveResource

local TYPE_MAP = {
    permanente = "carkey_permanent", permanent  = "carkey_permanent",
    copia      = "carkey_copy",      copy       = "carkey_copy",
    temporaria = "carkey_temp",      temp       = "carkey_temp",      temporary  = "carkey_temp",
    unico      = "carkey_single",    single     = "carkey_single",    single_use = "carkey_single",
}

-- ----------------------------------------------------------------
-- Interno: modelo do veículo via banco (player_vehicles — QBCore)
-- ----------------------------------------------------------------
local function getVehicleLabel(plate)
    local ok, rows = pcall(function()
        return ExecuteSQL(
            "SELECT `vehicle` FROM `player_vehicles` WHERE `plate` = ? LIMIT 1",
            { plate }
        )
    end)
    if ok and rows and rows[1] and rows[1].vehicle then
        return rows[1].vehicle
    end
    return nil
end

-- ----------------------------------------------------------------
-- Interno: nome do dono — detecta coluna por framework
-- ----------------------------------------------------------------
local function getPlayerName(citizenid)
    -- QBCore / QBX: tabela players com charinfo JSON
    if fw == "qb-core" or fw == "qbx-core" then
        local ok, rows = pcall(function()
            return ExecuteSQL(
                "SELECT `charinfo` FROM `players` WHERE `citizenid` = ? LIMIT 1",
                { citizenid }
            )
        end)
        if ok and rows and rows[1] and rows[1].charinfo then
            local info = type(rows[1].charinfo) == "string"
                and json.decode(rows[1].charinfo)
                or rows[1].charinfo
            if info and info.firstname then
                return info.firstname .. " " .. (info.lastname or "")
            end
        end

    -- ESX: tabela users com firstname/lastname separados
    elseif fw == "es_extended" then
        local ok, rows = pcall(function()
            return ExecuteSQL(
                "SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ? LIMIT 1",
                { citizenid }
            )
        end)
        if ok and rows and rows[1] then
            local r = rows[1]
            if r.firstname then
                return r.firstname .. " " .. (r.lastname or "")
            end
        end

    -- ox_core / ND_Core: tabela characters com name ou firstName/lastName
    elseif fw == "ox_core" or fw == "ND_Core" then
        local ok, rows = pcall(function()
            return ExecuteSQL(
                "SELECT `firstName`, `lastName` FROM `characters` WHERE `charId` = ? LIMIT 1",
                { citizenid }
            )
        end)
        if ok and rows and rows[1] then
            local r = rows[1]
            if r.firstName then
                return r.firstName .. " " .. (r.lastName or "")
            end
        end
    end

    return nil
end

-- ----------------------------------------------------------------
-- Gera barcode único (exposto como PRCarkeys.GenerateUniqueBarcode)
-- ----------------------------------------------------------------
local function generateUniqueBarcode()
    local barcode  = PRCarkeys.GenerateBarcode()
    local attempts = 0
    while attempts < 10 do
        if not PRCarkeys.Cache.GetKey(barcode) then break end
        barcode  = PRCarkeys.GenerateBarcode()
        attempts = attempts + 1
    end
    if attempts >= 10 then
        Debug("WARNING", "generateUniqueBarcode: limite de tentativas atingido; usando ultimo barcode gerado.")
    end
    return barcode
end

-- ================================================================
-- PRCarkeys.CreateTempKeyItem
-- Cria item físico de chave temporária para o player
-- Usado por carjack, hotwire, lockpick
-- ================================================================
function PRCarkeys.CreateTempKeyItem(src, plate, itemName)
    itemName = itemName or "carkey_temp"
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return nil end

    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then return nil end

    local barcode = generateUniqueBarcode()
    local keyCfg  = Config.KeyTypes[itemName]
    local keyType = keyCfg and keyCfg.keyType or "temporary"
    local level   = keyCfg and keyCfg.level   or "copy"

    -- TEMPORÁRIA: não registra no banco (vive só como item físico e é limpa ao entrar/sair da cidade)
    if keyType ~= "temporary" then
        Debug("WARNING", ("CreateTempKeyItem: item '%s' não é temporary (keyType=%s). Use CreateKeyTimed/CreateKeyPermanent."):format(
            tostring(itemName), tostring(keyType)))
    end

    local vehicleLabel = getVehicleLabel(plate) or plate
    local labelLines = {
        "Modelo: " .. vehicleLabel,
        "Placa: "  .. plate,
        "Serial: " .. barcode,
    }

    local metadata = {
        label    = table.concat(labelLines, "\n"),
        barcode  = barcode,
        plate    = plate,
        modelo   = vehicleLabel,
        code     = barcode,
    }

    local added = Bridge.inventory.AddItem(src, itemName, 1, metadata)
    if not added then
        Debug("WARNING", ("CreateTempKeyItem: AddItem FALHOU | src=%d | plate=%s | item=%s | barcode=%s"):format(
            src, plate, itemName, barcode))
        return nil
    end

    Debug("SUCCESS", ("CreateTempKeyItem: item criado | src=%d | plate=%s | item=%s | barcode=%s"):format(
        src, plate, itemName, barcode))
    return barcode
end

-- ================================================================
-- PRCarkeys.CreateTimedKeyItem (single_use = cronômetro)
-- Cria chave física + registro no banco com expires_at
-- ================================================================
function PRCarkeys.CreateTimedKeyItem(src, plate, durationSec, itemName, level)
    itemName = itemName or "carkey_single"
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return nil end

    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then return nil end

    durationSec = tonumber(durationSec or 0) or 0
    if durationSec <= 0 then
        Debug("WARNING", ("CreateTimedKeyItem: duration inválida (%s)"):format(tostring(durationSec)))
        return nil
    end

    local keyCfg = Config.KeyTypes[itemName]
    if not keyCfg or keyCfg.keyType ~= "single_use" then
        Debug("WARNING", ("CreateTimedKeyItem: item '%s' não é single_use (cronômetro)"):format(tostring(itemName)))
        return nil
    end

    local barcode  = generateUniqueBarcode()
    local soundId  = Config.Sound.soundDefault
    local expiresAt = os.time() + durationSec
    level = level or (keyCfg.level or "copy")

    local insertId = ExecuteSQLInsert(
        [[INSERT INTO pr_carkeys (barcode, citizenid, plate, key_type, sound, motor, level, distance, expires_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { barcode, citizenid, plate, "single_use", soundId, 0, level, Config.Default.UseKeyAnim.DefaultDistance, expiresAt }
    )
    if not insertId then
        Debug("ERROR", ("CreateTimedKeyItem: falha no INSERT | plate=%s | src=%d"):format(plate, src))
        return nil
    end

    PRCarkeys.Cache.SetKey(barcode, {
        id = insertId, barcode = barcode, citizenid = citizenid,
        plate = plate, key_type = "single_use", sound = soundId,
        motor = 0, level = level, distance = Config.Default.UseKeyAnim.DefaultDistance, expires_at = expiresAt,
    })

    local vehicleLabel = getVehicleLabel(plate) or plate
    local labelLines = {
        "Modelo: " .. vehicleLabel,
        "Placa: "  .. plate,
        ("Expira em: %ds"):format(durationSec),
        "Serial: " .. barcode,
    }
    local metadata = {
        label     = table.concat(labelLines, "\n"),
        barcode   = barcode,
        plate     = plate,
        modelo    = vehicleLabel,
        code      = barcode,
        expires_at = expiresAt,
        duration  = durationSec,
    }

    Bridge.inventory.AddItem(src, itemName, 1, metadata)
    Debug("SUCCESS", ("CreateTimedKeyItem: single_use criada | src=%d | plate=%s | barcode=%s | exp=%d"):format(
        src, plate, barcode, expiresAt))
    return barcode
end

-- ----------------------------------------------------------------
-- /givekey [id] [tipo] [placa]
-- ----------------------------------------------------------------
RegisterCommand("givekey", function(source, args, rawCommand)

    -- Verificar permissão
    if source ~= 0 then
        local allowed = false

        if IsPlayerAceAllowed(source, "command.givekey") then
            allowed = true

        elseif fw == "qb-core" then
            local QBCore = exports["qb-core"]:GetCoreObject()
            allowed = QBCore.Functions.HasPermission(source, "admin")

        elseif fw == "qbx-core" then
            local QBCore = exports["qb-core"]:GetCoreObject()
            allowed = QBCore.Functions.HasPermission(source, "admin")

        elseif fw == "es_extended" then
            local ESX     = exports["es_extended"]:getSharedObject()
            local xPlayer = ESX.GetPlayerFromId(source)
            allowed = xPlayer and (xPlayer.getGroup() == "admin" or xPlayer.getGroup() == "superadmin")

        elseif fw == "ox_core" then
            allowed = IsPlayerAceAllowed(source, "command.givekey")

        elseif fw == "ND_Core" then
            allowed = IsPlayerAceAllowed(source, "command.givekey")
        end

        if not allowed then
            Bridge.notify.Notify(source, { title = "Sistema", description = "Sem permissao.", type = "error" })
            return
        end
    end

    local targetId = tonumber(args[1])
    local typeArg  = args[2]
    local plate    = args[3]

    if not targetId or not typeArg or not plate then
        local hint = "Uso: /givekey [id] [tipo] [placa] | Tipos: permanente | copia | temporaria | unico"
        if source ~= 0 then
            Bridge.notify.Notify(source, { title = "Givekey", description = hint, type = "error" })
        end
        Debug("WARNING", hint)
        return
    end

    local itemName = TYPE_MAP[typeArg:lower()]
    if not itemName then
        local msg = ("Tipo invalido: '%s'"):format(typeArg)
        if source ~= 0 then
            Bridge.notify.Notify(source, { title = "Givekey", description = msg, type = "error" })
        end
        Debug("ERROR", msg)
        return
    end

    if not GetPlayerName(targetId) then
        local msg = ("Jogador ID %d nao encontrado."):format(targetId)
        if source ~= 0 then
            Bridge.notify.Notify(source, { title = "Givekey", description = msg, type = "error" })
        end
        return
    end

    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then
        if source ~= 0 then
            Bridge.notify.Notify(source, { title = "Givekey", description = "Placa invalida.", type = "error" })
        end
        return
    end

    local citizenid = Bridge.framework.GetIdentifier(targetId)
    if not citizenid then
        if source ~= 0 then
            Bridge.notify.Notify(source, { title = "Givekey", description = "Nao foi possivel obter o citizenid.", type = "error" })
        end
        return
    end

    local barcode = generateUniqueBarcode()

    local keyCfg  = Config.KeyTypes[itemName]
    local keyType = keyCfg and keyCfg.keyType or "permanent"
    local level   = keyCfg and keyCfg.level   or "original"
    local soundId = Config.Sound.soundDefault

    -- temporária: não registra no banco
    -- single_use (cronômetro): registra com expires_at (padrão 10min se não informado)
    local expiresAt = nil
    local insertId = nil

    if keyType == "temporary" then
        -- usa helper para manter padronizado
        PRCarkeys.CreateTempKeyItem(targetId, plate, itemName)
        insertId = true -- sentinel pra seguir fluxo de notificação
    elseif keyType == "single_use" then
        local duration = tonumber(args[4] or 600) or 600
        local b = PRCarkeys.CreateTimedKeyItem(targetId, plate, duration, itemName, level)
        if not b then
            if source ~= 0 then
                Bridge.notify.Notify(source, { title = "Givekey", description = "Erro ao criar chave temporizada.", type = "error" })
            end
            return
        end
        barcode = b
        insertId = true
    else
        insertId = ExecuteSQLInsert(
            [[INSERT INTO pr_carkeys (barcode, citizenid, plate, key_type, sound, motor, level, distance)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
            { barcode, citizenid, plate, keyType, soundId, 0, level, Config.Default.UseKeyAnim.DefaultDistance }
        )

        if not insertId then
            Debug("ERROR", ("givekey: falha no INSERT | plate=%s | target=%d"):format(plate, targetId))
            if source ~= 0 then
                Bridge.notify.Notify(source, { title = "Givekey", description = "Erro ao criar chave no banco.", type = "error" })
            end
            return
        end

        PRCarkeys.Cache.SetKey(barcode, {
            id = insertId, barcode = barcode, citizenid = citizenid,
            plate = plate, key_type = keyType, sound = soundId,
            motor = 0, level = level, distance = Config.Default.UseKeyAnim.DefaultDistance, expires_at = expiresAt,
        })
    end

    -- ── Metadata do item ─────────────────────────────────────────
    local vehicleLabel = getVehicleLabel(plate) or plate

    local ownerName = nil
    if Config.Default.KeyMetadata and Config.Default.KeyMetadata.showOwner then
        ownerName = getPlayerName(citizenid) or citizenid
    end

    -- Metadata com quebra de linha real.
    -- ox_inventory renderiza \n como nova linha na tooltip do item.
    -- qb-inventory: depende da versão, mas a maioria suporta.
    local labelLines = {
        "Modelo: "      .. vehicleLabel,
        "Placa: "       .. plate,
    }
    if ownerName then
        table.insert(labelLines, "Proprietario: " .. ownerName)
    end
    table.insert(labelLines, "Serial: " .. barcode)

    local metadata = {
        label         = table.concat(labelLines, "\n"),
        barcode       = barcode,
        plate         = plate,
        modelo        = vehicleLabel,
        code          = barcode,
    }
    if ownerName then
        metadata.proprietario = ownerName
    end
    -- ─────────────────────────────────────────────────────────────

    -- Evita duplicar item físico quando usamos CreateTempKeyItem/CreateTimedKeyItem
    if keyType ~= "temporary" and keyType ~= "single_use" then
        Bridge.inventory.AddItem(targetId, itemName, 1, metadata)
    end

    Bridge.notify.Notify(targetId, {
        title       = "Chave Recebida",
        description = ("Voce recebeu uma %s para o veiculo %s"):format(
            keyCfg and keyCfg.label or itemName, plate),
        type        = "success",
    })

    local giver = source == 0 and "Console" or ("ID " .. source)
    Debug("SUCCESS", ("%s → ID %d | %s | placa=%s | barcode=%s")
        :format(giver, targetId, itemName, plate, barcode))

    if source ~= 0 then
        Bridge.notify.Notify(source, {
            title       = "Givekey",
            description = ("Chave '%s' dada para ID %d (placa: %s)"):format(itemName, targetId, plate),
            type        = "success",
        })
    end
-- restricted=false porque já fazemos checagem de permissão acima.
-- Se deixar true, o FiveM bloqueia antes de entrar na nossa lógica (sem feedback).
end, false)
