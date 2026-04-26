-- ============================================================
--   pr_carkeys — server/sv_cache.lua
--   Cache server-side dos dados das chaves por barcode.
--   Índice por citizenid para limpeza eficiente ao desconectar.
-- ============================================================

local KeyCache        = {}  -- [barcode]    = { row do banco }
local CitizenIndex    = {}  -- [citizenid]  = { barcode, barcode, ... }

-- ----------------------------------------------------------------
-- Interno: índice citizenid → barcode
-- ----------------------------------------------------------------
local function indexAdd(citizenid, barcode)
    if not citizenid then return end
    if not CitizenIndex[citizenid] then
        CitizenIndex[citizenid] = {}
    end
    CitizenIndex[citizenid][barcode] = true
end

local function indexRemove(citizenid, barcode)
    if not citizenid or not CitizenIndex[citizenid] then return end
    CitizenIndex[citizenid][barcode] = nil
end

-- ----------------------------------------------------------------
-- Interno: busca no banco via wrapper SQL
-- ----------------------------------------------------------------
local function fetchFromDb(barcode)
    local rows = ExecuteSQL(
        "SELECT * FROM pr_carkeys WHERE barcode = ? LIMIT 1",
        { barcode }
    )
    return rows and rows[1] or nil
end

-- ----------------------------------------------------------------
-- GetKey — retorna dados da chave (cache first, depois banco)
-- ----------------------------------------------------------------
function PRCarkeys.Cache.GetKey(barcode)
    if KeyCache[barcode] then
        return KeyCache[barcode]
    end
    local row = fetchFromDb(barcode)
    if row then
        KeyCache[barcode] = row
        indexAdd(row.citizenid, barcode)
    end
    return row
end

-- ----------------------------------------------------------------
-- SetKey — popula cache após INSERT
-- ----------------------------------------------------------------
function PRCarkeys.Cache.SetKey(barcode, data)
    KeyCache[barcode] = data
    if data and data.citizenid then
        indexAdd(data.citizenid, barcode)
    end
end

-- ----------------------------------------------------------------
-- InvalidateKey — remove do cache após DELETE
-- ----------------------------------------------------------------
function PRCarkeys.Cache.InvalidateKey(barcode)
    local row = KeyCache[barcode]
    if row and row.citizenid then
        indexRemove(row.citizenid, barcode)
    end
    KeyCache[barcode] = nil
end

-- ----------------------------------------------------------------
-- UpdateField — atualiza campo específico sem invalidar tudo
-- ----------------------------------------------------------------
function PRCarkeys.Cache.UpdateField(barcode, field, value)
    if KeyCache[barcode] then
        KeyCache[barcode][field] = value
    end
end

-- ----------------------------------------------------------------
-- Limpar cache do player ao desconectar — O(1) via índice
-- ----------------------------------------------------------------
AddEventHandler("playerDropped", function()
    local src       = source
    local citizenid = Bridge.framework.GetIdentifier(src)
    if not citizenid then return end

    local barcodes = CitizenIndex[citizenid]
    if barcodes then
        for barcode, _ in pairs(barcodes) do
            KeyCache[barcode] = nil
        end
        CitizenIndex[citizenid] = nil
        Debug("INFO", ("Cache limpo para citizenid=%s"):format(citizenid))
    end
end)

Debug("SUCCESS", "Cache de chaves iniciado.")
