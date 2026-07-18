-- ============================================================
--   pr_carkeys — client/modules/vehicle_state.lua
--   Estado global do veículo/chaves do jogador.
--   permanentKeys: { [plate] = { barcode, distance, sound, motor } }
--   temporaryKeys: { [plate] = true }
-- ============================================================

local VehicleState = {
    permanentKeys  = {},   -- dados completos do banco por placa
    temporaryKeys  = {},   -- chaves temp (hotwire/lockpick/carjack)
    currentVehicle = 0,
    currentPlate   = nil,
    isInDriverSeat = false,
    isEngineRunning = false,
    hasKey          = false,
    currentWeapon   = nil,
    showHotwireHint = false,
    hotwireToken    = nil,
    --- "hotwire" | "pickup" | nil — distingue TextUI de ligação direta vs pegar chave no carro
    textUiMode      = nil,
}

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

--- Retorna dados da chave permanente para a placa (ou nil)
---@param plate string
---@return table|nil
function VehicleState:GetKeyData(plate)
    if not plate then return nil end
    plate = PRCarkeys.SanitizePlate(plate)
    return self.permanentKeys[plate] or nil
end

--- Verifica se tem qualquer chave para a placa
---@param plate string
---@return boolean
function VehicleState:HasKey(plate)
    if not plate then return false end
    plate = PRCarkeys.SanitizePlate(plate)
    return self.permanentKeys[plate] ~= nil or self.temporaryKeys[plate] == true
end

--- Adiciona chave temporária
---@param plate string
function VehicleState:AddTempKey(plate)
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)
    self.temporaryKeys[plate] = true
    if self.currentPlate == plate then self.hasKey = true end
    Debug("INFO", ("[VehicleState] Chave temp adicionada: %s"):format(plate))
end

--- Remove chave temporária
---@param plate string
function VehicleState:RemoveTempKey(plate)
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)
    self.temporaryKeys[plate] = nil
    if self.currentPlate == plate then self.hasKey = self:HasKey(plate) end
end

--- Adiciona/atualiza chave permanente com dados do banco
---@param plate string
---@param data table  { barcode, distance, sound, motor }
function VehicleState:AddPermanentKey(plate, data)
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)
    self.permanentKeys[plate] = data or { barcode = nil }
    if self.currentPlate == plate then self.hasKey = true end
end

--- Remove chave permanente
---@param plate string
function VehicleState:RemovePermanentKey(plate)
    if not plate then return end
    plate = PRCarkeys.SanitizePlate(plate)
    self.permanentKeys[plate] = nil
    if self.currentPlate == plate then self.hasKey = self:HasKey(plate) end
end

--- Reconstrói permanentKeys a partir dos itens do inventário + banco de dados
--- Chamado ao carregar player e quando inventário muda
function VehicleState:RebuildFromInventory()
    self.permanentKeys = {}

    local function processItem(item)
        if not item or not Config.KeyTypes[item.name] then return end
        local meta = (ActiveInventory == "ox_inventory")
            and (item.metadata or {})
            or  (item.info or item.metadata or {})
        if not meta.plate or not meta.barcode then return end
        local plate = PRCarkeys.SanitizePlate(meta.plate)
        if not plate then return end
        if self.temporaryKeys[plate] then return end
        self.permanentKeys[plate] = {
            barcode  = meta.barcode,
            plate    = plate,
            itemName = item.name,
            distance = Config.Default.UseKeyAnim.DefaultDistance,
            sound    = Config.Sound.soundDefault,
            motor    = false,
        }
    end

    local allItems = (pr_lib.inventory.GetPlayerItems and pr_lib.inventory.GetPlayerItems())
        or (pr_lib.framework.GetPlayerInventory and pr_lib.framework.GetPlayerInventory())
        or {}

    local items = snapshotTableValues(allItems)
    for i = 1, #items do
        processItem(items[i])
    end

    if self.currentPlate then
        self.hasKey = self:HasKey(self.currentPlate)
    end

    Debug("INFO", ("[VehicleState] Inventário reconstruído | permanentes: %d"):format(
        countTableEntries(self.permanentKeys)
    ))
end

--- Atualiza os dados do banco (distance, sound, motor) para uma chave
---@param plate string
---@param dbData table  { distance, sound, motor }
function VehicleState:UpdateKeyDbData(plate, dbData)
    if not plate or not dbData then return end
    plate = PRCarkeys.SanitizePlate(plate)
    if self.permanentKeys[plate] then
        self.permanentKeys[plate].distance = dbData.distance or self.permanentKeys[plate].distance
        self.permanentKeys[plate].sound    = dbData.sound    or self.permanentKeys[plate].sound
        self.permanentKeys[plate].motor    = dbData.motor == 1 or dbData.motor == true
    end
end

--- Limpa todo o estado (logout)
function VehicleState:Reset()
    self.permanentKeys   = {}
    self.temporaryKeys   = {}
    self.currentVehicle  = 0
    self.currentPlate    = nil
    self.isInDriverSeat  = false
    self.isEngineRunning = false
    self.hasKey          = false
    self.currentWeapon   = nil
    self.showHotwireHint = false
    self.hotwireToken    = nil
    self.textUiMode      = nil
end

return VehicleState
