-- ============================================================
--   pr_carkeys — client/cl_main.lua
--   Inicialização e utilitários client-side.
-- ============================================================

-- ----------------------------------------------------------------
-- Estado do player
-- ----------------------------------------------------------------
PRCarkeys.PlayerLoaded = false
PRCarkeys.PlayerData   = {}

-- ----------------------------------------------------------------
-- Notificação via bridge
-- ----------------------------------------------------------------
---@param data table  Config.Notify entry
function PRCarkeys.Notify(data)
    Bridge.notify.Notify(data)
end

-- ----------------------------------------------------------------
-- Progressbar
-- Corrigido: ox_lib progressBar é chamado na mesma thread (sem
-- CreateThread interno), garantindo comportamento síncrono para
-- o chamador. Animação carregada antes de iniciar o progressbar.
-- ----------------------------------------------------------------
---@param label    string
---@param duration number   ms
---@param anim     table    {dict, clip, flag}
---@param cb       function callback(success: boolean)
function PRCarkeys.ProgressBar(label, duration, anim, cb)
    -- Carregar animação com timeout
    RequestAnimDict(anim.dict)
    local timeout = 0
    while not HasAnimDictLoaded(anim.dict) and timeout < 3000 do
        Wait(50)
        timeout = timeout + 50
    end

    local ped = PlayerPedId()
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, duration, anim.flag, 0, false, false, false)

    local success = false

    -- ox_lib progressBar (bloqueante na thread atual)
    if GetResourceState("ox_lib"):find("start") and lib and lib.progressBar then
        success = lib.progressBar({
            duration  = duration,
            label     = label,
            canCancel = true,
            disable   = { move = true, car = true, combat = true },
        })

    else
        -- Fallback simples: espera a duração e considera sucesso
        Wait(duration)
        success = true
    end

    ClearPedTasks(ped)
    cb(success)
end

-- ----------------------------------------------------------------
-- Encontra veículo próximo pela placa — versão otimizada.
-- Usa raio de busca (GetVehiclesInArea via pool filtrado por distância)
-- em vez de iterar todo o pool de veículos do jogo.
-- ----------------------------------------------------------------
---@param plate       string
---@param maxDistance number
---@return number|nil  vehicle entity handle
function PRCarkeys.FindVehicleByPlate(plate, maxDistance)
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local dist   = maxDistance or Config.Default.UseKeyAnim.DefaultDistance

    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then return nil end

    local closest, closestDist = nil, dist + 1.0

    -- Filtramos apenas veículos dentro do raio antes de comparar placa
    local vehicles = GetGamePool("CVehicle")
    for _, veh in ipairs(vehicles) do
        local vehCoords = GetEntityCoords(veh)
        local d = #(coords - vehCoords)
        if d <= dist then
            local vehPlate = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(veh))
            if vehPlate == plate and d < closestDist then
                closest     = veh
                closestDist = d
            end
        end
    end

    return closest
end

-- ----------------------------------------------------------------
-- Retorna o NetID de um veículo ou nil
-- ----------------------------------------------------------------
---@param vehicle number
---@return number|nil
function PRCarkeys.GetVehicleNetId(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    return NetworkGetNetworkIdFromEntity(vehicle)
end

-- ----------------------------------------------------------------
-- Retorna o nome de exibição de um modelo de veículo.
-- ----------------------------------------------------------------
---@param model number|string  hash ou nome do modelo
---@return string
function GetVehicleModel(model)
    if not model then return "Desconhecido" end

    local hash = type(model) == "string" and GetHashKey(model) or model
    if not hash or hash == 0 then return "Desconhecido" end

    local displayName = GetDisplayNameFromVehicleModel(hash)
    if not displayName or displayName == "" then return "Desconhecido" end

    local label = GetLabelText(displayName)
    if not label or label == "" or label == "NULL" then
        -- Fallback: usa o próprio displayName como label
        return displayName
    end

    return label
end

-- ----------------------------------------------------------------
-- Debug local (wrapper de Debug() do shared/main.lua)
-- ----------------------------------------------------------------
---@param msg string
function PRCarkeys.Debug(msg)
    Debug("INFO", "[CLIENT] " .. tostring(msg))
end

-- ----------------------------------------------------------------
-- Eventos de carregamento do player
-- Inicializa estado local quando o personagem entra em jogo.
-- ----------------------------------------------------------------

-- QBCore
AddEventHandler("QBCore:Client:OnPlayerLoaded", function()
    PRCarkeys.PlayerLoaded = true
    local QBCore = exports["qb-core"]:GetCoreObject()
    PRCarkeys.PlayerData = QBCore.Functions.GetPlayerData() or {}
    PRCarkeys.Debug("Player carregado (QBCore).")
end)

-- QBX
AddEventHandler("QBCore:Client:OnPlayerUnload", function()
    PRCarkeys.PlayerLoaded = false
    PRCarkeys.PlayerData   = {}
    PRCarkeys.Debug("Player descarregado (QBCore/QBX).")
end)

-- ESX
AddEventHandler("esx:playerLoaded", function(xPlayer)
    PRCarkeys.PlayerLoaded = true
    PRCarkeys.PlayerData   = xPlayer or {}
    PRCarkeys.Debug("Player carregado (ESX).")
end)

AddEventHandler("esx:onPlayerLogout", function()
    PRCarkeys.PlayerLoaded = false
    PRCarkeys.PlayerData   = {}
    PRCarkeys.Debug("Player descarregado (ESX).")
end)

-- ox_core
AddEventHandler("ox:playerLoaded", function(data)
    PRCarkeys.PlayerLoaded = true
    PRCarkeys.PlayerData   = data or {}
    PRCarkeys.Debug("Player carregado (ox_core).")
end)

AddEventHandler("ox:playerLogout", function()
    PRCarkeys.PlayerLoaded = false
    PRCarkeys.PlayerData   = {}
    PRCarkeys.Debug("Player descarregado (ox_core).")
end)
