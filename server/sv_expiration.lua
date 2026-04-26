-- ============================================================
--   pr_carkeys — server/sv_expiration.lua
--   Expiração de chaves "single_use" (modo cronômetro).
--   Remove do inventário/bolsas/ignição e desliga o veículo.
-- ============================================================

if not IsDuplicityVersion() then return end

local function getPlayerSourceFromPed(targetPed)
    if not targetPed or targetPed == 0 then return nil end
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and GetPlayerPed(src) == targetPed then
            return src
        end
    end
    return nil
end

local function stopVehicleIfKeyInIgnition(barcode)
    for vehNetId, data in pairs((rawget(_G, "VehiclesWithKeyInside") or {})) do
        if data and tostring(data.barcode) == tostring(barcode) then
            -- Server não desliga motor diretamente; delega ao cliente do motorista.
            local veh = NetworkGetEntityFromNetworkId(vehNetId)
            if veh and veh ~= 0 then
                -- Broadcast para garantir desligamento mesmo se troca de driver/owner em rede.
                TriggerClientEvent("pr_carkeys:client:forceEngineOff", -1, vehNetId)

                local driverPed = GetPedInVehicleSeat(veh, -1)
                if driverPed and driverPed ~= 0 and IsPedAPlayer(driverPed) then
                    local src = getPlayerSourceFromPed(driverPed)
                    if src and src > 0 then
                        TriggerClientEvent("pr_carkeys:client:forceEngineOff", src, vehNetId)
                    end
                end
            end

            -- Remove do registro da ignição
            ;(rawget(_G, "VehiclesWithKeyInside") or {})[vehNetId] = nil

            Debug("INFO", ("[Expiration] chave removida da ignicao | barcode=%s | vehNetId=%s"):format(
                tostring(barcode), tostring(vehNetId)))
            return true, vehNetId, veh
        end
    end
    return false, nil, nil
end

local function tryRemoveFromVehicleDriver(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local driverPed = GetPedInVehicleSeat(veh, -1)
    if not driverPed or driverPed == 0 then return nil end
    if not IsPedAPlayer(driverPed) then return nil end
    local src = getPlayerSourceFromPed(driverPed)
    if not src or src <= 0 then return nil end
    return src
end

local function removeKeyByBarcodeFromOnlinePlayers(barcode)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid then
            Bridge.inventory.RemoveItemByBarcode(pid, barcode)
        end
    end
end

CreateThread(function()
    -- Dá tempo do SQL/cache subirem
    Wait(3000)

    while true do
        -- Intervalo curto o suficiente pra “cortar” corrida/tempo
        Wait(5000)

        local now = os.time()
        local nowMs = now * 1000
        local rows = ExecuteSQL(
            [[
                SELECT barcode, key_type, expires_at
                FROM pr_carkeys
                WHERE expires_at IS NOT NULL
                  AND (
                    (expires_at <= ? AND expires_at < 2000000000)
                    OR
                    (expires_at <= ? AND expires_at >= 2000000000)
                  )
            ]],
            { now, nowMs }
        )

        if rows and #rows > 0 then
            for _, r in ipairs(rows) do
                local barcode = r.barcode and tostring(r.barcode) or nil
                if not barcode then goto continue end

                -- 1) ignição primeiro (se estiver no carro, deve desligar/remover)
                local wasInIgnition, _, veh = stopVehicleIfKeyInIgnition(barcode)

                -- 2) tenta remover do inventário/bolsas do player que ESTÁ no veículo (melhor esforço)
                local removedFrom = nil
                if wasInIgnition and veh then
                    local driverSrc = tryRemoveFromVehicleDriver(veh)
                    if driverSrc then
                        Bridge.inventory.RemoveItemByBarcode(driverSrc, barcode)
                        removedFrom = ("driver:%d"):format(driverSrc)
                    end
                end

                -- 3) fallback: varre players online e remove onde existir (não depende de citizenid do DB)
                if not removedFrom then
                    removeKeyByBarcodeFromOnlinePlayers(barcode)
                    removedFrom = "scan_online"
                end

                -- 4) remove do banco/cache (sempre)
                ExecuteSQL("DELETE FROM pr_carkeys WHERE barcode = ?", { barcode })
                PRCarkeys.Cache.InvalidateKey(barcode)

                -- Verificação defensiva para confirmar persistência da remoção.
                local check = ExecuteSQL("SELECT barcode FROM pr_carkeys WHERE barcode = ? LIMIT 1", { barcode })
                local deleted = not (check and check[1])
                if not deleted then
                    Debug("WARNING", ("[Expiration] DELETE nao removeu registro | barcode=%s | keyType=%s | expiresAt=%s"):format(
                        tostring(barcode), tostring(r.key_type), tostring(r.expires_at)))
                else
                    Debug("SUCCESS", ("[Expiration] chave expirada removida | barcode=%s | keyType=%s | ignition=%s | removedFrom=%s"):format(
                        tostring(barcode), tostring(r.key_type), tostring(wasInIgnition), tostring(removedFrom)))
                end

                ::continue::
            end
        end
    end
end)

