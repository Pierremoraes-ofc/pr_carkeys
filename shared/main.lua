-- ============================================================
--   pr_carkeys — shared/main.lua
--   Utilitários compartilhados, detecção de framework,
--   sistema de Debug e wrapper de SQL.
-- ============================================================

PRCarkeys       = {}
PRCarkeys.Cache = PRCarkeys.Cache or {}

-- ============================================================
--   SISTEMA DE DEBUG
-- ============================================================
local DebugFilters = {
    SUCCESS = function(...)
        print('^2[DEBUG SUCCESS]:^0', ...)
    end,
    INFO = function(...)
        print('^3[DEBUG INFO]:^0', ...)
    end,
    ERROR = function(...)
        print('^1[DEBUG ERROR]:^0', ...)
    end,
    WARNING = function(...)
        print('^4[DEBUG WARNING]:^0', ...)
    end,
}

function Debug(level, ...)
    if not Config.Debug then return end
    local fn = DebugFilters[level]
    if fn then
        fn(...)
    else
        print('[DEBUG]:', ...)
    end
end

-- ============================================================
--   DETECÇÃO DE FRAMEWORK
-- ============================================================
local frameworkPriority = {
    { resource = "qbx-core",    ownerColumn = "citizenid" },
    { resource = "ND_Core",     ownerColumn = "citizenid" },
    { resource = "ox_core",     ownerColumn = "charId"    },
    { resource = "es_extended", ownerColumn = "identifier"},
    { resource = "qb-core",     ownerColumn = "citizenid" },
}

local detected = false

-- Permite forçar framework via Config
if Config.Framework and Config.Framework ~= "auto" then
    for _, fw in ipairs(frameworkPriority) do
        if fw.resource == Config.Framework then
            PRCarkeys.OwnerColumn    = fw.ownerColumn
            PRCarkeys.ActiveResource = fw.resource
            detected = true
            Debug("INFO", ("Framework forcado via config: '%s' | coluna owner: '%s'"):format(fw.resource, fw.ownerColumn))
            break
        end
    end
end

if not detected then
    for _, fw in ipairs(frameworkPriority) do
        if GetResourceState(fw.resource):find("start") then
            PRCarkeys.OwnerColumn    = fw.ownerColumn
            PRCarkeys.ActiveResource = fw.resource
            detected = true
            Debug("SUCCESS", ("Framework detectado: '%s' | coluna owner: '%s'"):format(fw.resource, fw.ownerColumn))
            break
        end
    end
end

if not detected then
    PRCarkeys.OwnerColumn    = "citizenid"
    PRCarkeys.ActiveResource = "unknown"
    Debug("WARNING", "Nenhum framework detectado — usando fallback citizenid")
end

-- ============================================================
--   DETECÇÃO DE INVENTÁRIO
-- ============================================================
if Config.SQL and Config.SQL ~= "auto" then
    SqlServer = Config.SQL
    Debug("INFO", ("Sistema de Banco de dados configurado: '%s'"):format(SqlServer))
elseif GetResourceState("oxmysql"):find("start") then
    SqlServer = "oxmysql"
    Debug("INFO", ("Sistema de Banco de dados detectado: '%s'"):format(SqlServer))
elseif GetResourceState("ghmattimysql"):find("start") then
    SqlServer = "ghmattimysql"
    Debug("INFO", ("Sistema de Banco de dados detectado: '%s'"):format(SqlServer))
elseif GetResourceState("mysql-async"):find("start") then
    SqlServer = "mysql-async"
    Debug("INFO", ("Sistema de Banco de dados detectado: '%s'"):format(SqlServer))
else
    Debug("INFO", ("Não foi encontrado um sistema de banco de dados, favor : '%s'"):format(Config.SQL))
end

-- ============================================================
--   DETECÇÃO DE INVENTÁRIO
-- ============================================================
if Config.Inventory and Config.Inventory ~= "auto" then
    ActiveInventory = Config.Inventory
    Debug("INFO", ("Inventario forcado via config: '%s'"):format(ActiveInventory))
elseif GetResourceState("ox_inventory"):find("start") then
    ActiveInventory = "ox_inventory"
    Debug("SUCCESS", "Inventario detectado: ox_inventory")
else
    ActiveInventory = "qb-inventory"
    Debug("INFO", "Inventario detectado: qb-inventory (fallback)")
end



-- ============================================================
--   WRAPPER SQL — suporta oxmysql | ghmattimysql | mysql-async
--   Apenas server-side; no client esta função não existe.
-- ============================================================
if IsDuplicityVersion() then

    ---Executa uma query SQL de forma bloqueante (coroutine-safe).
    ---Retorna os dados assim que o banco responder.
    ---@param query string
    ---@param parameters table|nil
    ---@return table|nil
    function ExecuteSQL(query, parameters)
        parameters = parameters or {}
        local result = nil
        local isDone = false

        local function onResult(data)
            result = data
            isDone = true
        end

        -- Detectar tipo de query: SELECT usa fetch/query, resto usa execute
        local isSelect = query:match("^%s*SELECT") ~= nil

        if SqlServer == "oxmysql" then
            if isSelect then
                exports.oxmysql:query(query, parameters, onResult)
            else
                exports.oxmysql:execute(query, parameters, onResult)
            end
        elseif SqlServer == "ghmattimysql" then
            if isSelect then
                exports.ghmattimysql:fetchAll(query, parameters, onResult)
            else
                exports.ghmattimysql:execute(query, parameters, onResult)
            end
        elseif SqlServer == "mysql-async" then
            if isSelect then
                MySQL.Async.fetchAll(query, parameters, onResult)
            else
                MySQL.Async.execute(query, parameters, onResult)
            end
        else
            Debug("ERROR", ("ExecuteSQL: SQL '%s' nao reconhecido. Verifique Config.SQL."):format(tostring(SqlServer)))
            return nil
        end

        while not isDone do
            Citizen.Wait(0)
        end

        return result
    end

    ---Executa INSERT e retorna o ID gerado.
    ---@param query string
    ---@param parameters table|nil
    ---@return number|nil
    function ExecuteSQLInsert(query, parameters)
        parameters = parameters or {}
        local insertId = nil
        local isDone   = false

        if SqlServer == "oxmysql" then
            exports.oxmysql:insert(query, parameters, function(id)
                insertId = id
                isDone   = true
            end)
        elseif SqlServer == "ghmattimysql" then
            exports.ghmattimysql:execute(query, parameters, function(data)
                insertId = data and data.insertId or nil
                isDone   = true
            end)
        elseif SqlServer == "mysql-async" then
            MySQL.Async.execute(query, parameters, function(rowsAffected, lastInsertId)
                insertId = lastInsertId
                isDone   = true
            end)
        else
            Debug("ERROR", ("ExecuteSQLInsert: SQL '%s' nao reconhecido."):format(tostring(SqlServer)))
            isDone = true
        end

        while not isDone do
            Citizen.Wait(0)
        end

        return insertId
    end

end -- fim IsDuplicityVersion()

-- ============================================================
--   GERADOR DE SERIAL / BARCODE
--   Baseado no gerador do ox_inventory, adaptado.
-- ============================================================

local function GenerateText(length)
    local chars  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local result = ""
    for _ = 1, length do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

---Gera um serial único no formato: 6digits + 3letters + 6digits
---@param text string|nil  sufixo opcional (mínimo 3 chars); se nil gera aleatório
---@return string
function PRCarkeys.GenerateBarcode(text)
    math.randomseed(os.clock() * 10000 + os.time())
    if text and #text > 3 then
        return text
    end
    local suffix = (text == nil) and GenerateText(3) or text
    return ("%s%s%s"):format(
        math.random(100000, 999999),
        suffix,
        math.random(100000, 999999)
    )
end

-- ============================================================
--   UTILITÁRIOS
-- ============================================================

---Sanitiza placa removendo espaços e convertendo para maiúsculo.
---@param plate string
---@return string|false
function PRCarkeys.SanitizePlate(plate)
    if not plate or plate == "" then return false end
    return plate:gsub("%s+", ""):upper()
end

---Retorna o stashId da bolsa pelo seu barcode.
---@param bagBarcode string
---@return string
function PRCarkeys.GetStashId(bagBarcode)
    return "pr_carkeys_bag_" .. bagBarcode
end

---Resolve o itemName de uma chave pelo tipo e nível.
---Retorna o primeiro match exato (keyType + level).
---Sem fallback ambíguo — retorna nil se não encontrar.
---@param keyType string  "permanent"|"temporary"|"single_use"
---@param level   string  "original"|"copy"
---@return string|nil
function PRCarkeys.ResolveKeyItem(keyType, level)
    for itemName, cfg in pairs(Config.KeyTypes) do
        if cfg.keyType == keyType and cfg.level == level then
            return itemName
        end
    end
    -- Fallback: qualquer chave do mesmo tipo (sem ambiguidade de level)
    -- Só usado se não existir item com o level solicitado
    for itemName, cfg in pairs(Config.KeyTypes) do
        if cfg.keyType == keyType then
            Debug("WARNING", ("ResolveKeyItem: nenhum item com keyType='%s' level='%s'; retornando '%s' sem level exato."):format(keyType, level, itemName))
            return itemName
        end
    end
    return nil
end

---Verifica se um item é uma bolsa configurada.
---@param itemName string
---@return boolean
function PRCarkeys.IsBag(itemName)
    return Config.Bags[itemName] ~= nil
end

---Verifica se um item é uma chave configurada.
---@param itemName string
---@return boolean
function PRCarkeys.IsKey(itemName)
    return Config.KeyTypes[itemName] ~= nil
end

---Verifica se o modelo do veículo está na blacklist (não precisa de chave).
---@param vehicle number  entity handle
---@return boolean
function PRCarkeys.IsVehicleBlacklisted(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    return Config.NoKeyNeeded[model] == true
end

---Resolve o arquivo de som pelo ID configurado.
---@param soundId string
---@return string|nil
function PRCarkeys.ResolveSoundFile(soundId)
    for _, s in ipairs(Config.Sound.sounds) do
        if s.id == soundId then return s.file end
    end
    -- Fallback para o som padrão
    for _, s in ipairs(Config.Sound.sounds) do
        if s.id == Config.Sound.soundDefault then return s.file end
    end
    return Config.Sound.sounds[1] and Config.Sound.sounds[1].file or nil
end

---Verifica se uma chave está expirada (só para tipo "temporary").
---@param row table  linha do banco
---@return boolean
function PRCarkeys.IsKeyExpired(row)
    -- "temporary" e "single_use" (modo cronômetro) expiram por expires_at
    if row.key_type ~= "temporary" and row.key_type ~= "single_use" then return false end
    if not row.expires_at then return false end
    return os.time() > tonumber(row.expires_at)
end
