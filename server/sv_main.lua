-- ============================================================
--   pr_carkeys — server/sv_main.lua
--   Inicialização do servidor, auto SQL e registro de itens.
-- ============================================================

local resourceName = GetCurrentResourceName()

local function getTemporaryKeyItems()
    local tempItems = {}
    for itemName, cfg in pairs(Config.KeyTypes) do
        if cfg.keyType == "temporary" then
            tempItems[itemName] = true
        end
    end
    return tempItems
end

local function removeTemporaryKeysFromPlayerInventory(src, tempItems)
    for itemName, _ in pairs(tempItems) do
        local slots = exports.ox_inventory:GetSlotsWithItem(src, itemName, nil)
        if slots then
            for _, slot in pairs(slots) do
                exports.ox_inventory:RemoveItem(src, itemName, slot.count or 1, nil, slot.slot)
            end
        end
    end
end

local function removeTemporaryKeysFromPlayerBags(src, tempItems)
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
                            if item and tempItems[item.name] then
                                exports.ox_inventory:RemoveItem(stashId, item.name, item.count or 1, nil, item.slot)
                                Debug("INFO", ("Bag cleanup: removido %s stash=%s slot=%s | src=%d"):format(
                                    tostring(item.name), tostring(stashId), tostring(item.slot), src))
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------
-- Auto SQL — cria tabela pr_carkeys ao iniciar o resource
-- ----------------------------------------------------------------
AddEventHandler("onResourceStart", function(resource)
    if resource ~= resourceName then return end

    -- Pequeno delay para garantir que o SQL esteja pronto
    SetTimeout(1000, function()
        ExecuteSQL([[
            CREATE TABLE IF NOT EXISTS `pr_carkeys` (
                `id`         INT          NOT NULL AUTO_INCREMENT,
                `barcode`    VARCHAR(20)  NOT NULL UNIQUE COMMENT 'Codigo de barras unico da chave',
                `citizenid`  VARCHAR(50)  NOT NULL        COMMENT 'CitizenID do dono da chave',
                `plate`      VARCHAR(15)  NOT NULL        COMMENT 'Placa do veiculo',
                `key_type`   VARCHAR(20)  NOT NULL DEFAULT 'permanent' COMMENT 'permanent | temporary | single_use',
                `sound`      VARCHAR(50)  NOT NULL DEFAULT 'tranca_1'  COMMENT 'Nome do som configurado',
                `motor`      TINYINT(1)   NOT NULL DEFAULT 0           COMMENT '1 = liga motor ao destrancar',
                `level`      VARCHAR(20)  NOT NULL DEFAULT 'original'  COMMENT 'original | copy',
                `distance`   FLOAT        NOT NULL DEFAULT 5.0         COMMENT 'Distancia do sinal (metros)',
                `expires_at` BIGINT       NULL     DEFAULT NULL        COMMENT 'Timestamp de expiracao (apenas temporary)',
                `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_barcode`   (`barcode`),
                INDEX `idx_citizenid` (`citizenid`),
                INDEX `idx_plate`     (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Configuracoes individuais das chaves de veiculo';
        ]], nil)

        Debug("SUCCESS", "Tabela 'pr_carkeys' verificada/criada com sucesso.")
    end)
end)

-- ----------------------------------------------------------------
-- Registro de itens usáveis — bolsas e chaves
-- Feito via evento para garantir que o framework esteja pronto.
-- ----------------------------------------------------------------
AddEventHandler("onResourceStart", function(resource)
    if resource ~= resourceName then return end

    SetTimeout(500, function()
        -- Registrar bolsas como itens usáveis
        for bagItem, _ in pairs(Config.Bags) do
            Bridge.framework.RegisterUsableItem(bagItem, function(source, data)
                TriggerClientEvent("pr_carkeys:client:useBag", source, {
                    slot = data.slot,
                    item = bagItem,
                })
            end)
            Debug("INFO", ("Item de bolsa registrado: '%s'"):format(bagItem))
        end

        -- Registrar chaves como itens usáveis
        for keyItem, _ in pairs(Config.KeyTypes) do
            Bridge.framework.RegisterUsableItem(keyItem, function(source, data)
                TriggerClientEvent("pr_carkeys:client:useKey", source, {
                    slot = data.slot,
                    item = keyItem,
                })
            end)
            Debug("INFO", ("Item de chave registrado: '%s'"):format(keyItem))
        end

        local version = GetResourceMetadata(resourceName, "version", 0) or "?"
        Debug("SUCCESS", ("Resource iniciado — v%s | Framework: %s | Inventario: %s | SQL: %s")
            :format(version, PRCarkeys.ActiveResource, ActiveInventory, SqlServer))
    end)
end)

-- ================================================================
--   LIMPEZA DE CHAVES TEMPORÁRIAS AO INICIAR
--   Apenas itens com keyType="temporary" são removidos do inventário/bolsas.
--   OBS: single_use agora expira por timer (expires_at) e NÃO deve ser removida aqui.
-- ================================================================
AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if ActiveInventory ~= "ox_inventory" then return end

    -- Aguarda ox_inventory estar pronto
    Wait(3000)

    local tempItems = getTemporaryKeyItems()
    local hasAny = next(tempItems) ~= nil
    if not hasAny then return end

    -- Remove todos os itens temporários de todos os jogadores online
    -- (jogadores que logaram antes do resource iniciar)
    for _, playerId in ipairs(GetPlayers()) do
        playerId = tonumber(playerId)
        removeTemporaryKeysFromPlayerInventory(playerId, tempItems)
        removeTemporaryKeysFromPlayerBags(playerId, tempItems)
    end

    local names = {}
    for itemName, _ in pairs(tempItems) do names[#names+1] = itemName end
    Debug("SUCCESS", ("Startup: limpeza de itens temporarios concluida | items: %s"):format(
        table.concat(names, ", ")))
end)

-- ================================================================
--   LIMPEZA DE carkey_temp AO SAIR DA CIDADE (playerDropped)
--   Remove SOMENTE keyType="temporary" do inventário/bolsas ao desconectar.
--   Não remove single_use (expira por timer) e não mexe na ignição.
-- ================================================================
AddEventHandler("playerDropped", function()
    local src = source
    if ActiveInventory ~= "ox_inventory" then return end

    local tempItems = getTemporaryKeyItems()
    removeTemporaryKeysFromPlayerInventory(src, tempItems)
    removeTemporaryKeysFromPlayerBags(src, tempItems)

    Debug("INFO", ("playerDropped: chaves temporarias removidas | src=%d"):format(src))
end)

-- ================================================================
--   LIMPEZA AO ENTRAR NA CIDADE (playerLoaded)
--   Remove chaves temporárias (temporary) do inventário e bolsas.
--   single_use NÃO é removida aqui (ela expira por timer).
-- ================================================================
local function cleanupTemporaryKeysForPlayer(src)
    if ActiveInventory ~= "ox_inventory" then return end
    if not src or not GetPlayerName(src) then return end

    local tempItems = getTemporaryKeyItems()
    if not next(tempItems) then return end

    removeTemporaryKeysFromPlayerInventory(src, tempItems)
    removeTemporaryKeysFromPlayerBags(src, tempItems)
    Debug("INFO", ("playerLoaded: chaves temporarias removidas | src=%d"):format(src))
end

-- QBCore / QBX
AddEventHandler("QBCore:Server:OnPlayerLoaded", function(player)
    local src = type(player) == "number" and player or (player and player.PlayerData and player.PlayerData.source)
    if src then cleanupTemporaryKeysForPlayer(src) end
end)

-- ESX Legacy
AddEventHandler("esx:playerLoaded", function(src)
    if src then cleanupTemporaryKeysForPlayer(src) end
end)

-- ox_core
AddEventHandler("ox:playerLoaded", function(src)
    if src then cleanupTemporaryKeysForPlayer(src) end
end)
