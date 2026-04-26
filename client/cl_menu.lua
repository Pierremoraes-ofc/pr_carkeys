-- ============================================================
--   pr_carkeys — client/cl_menu.lua
--   Menu de gerenciamento de chaves.
--   Suporta ox_lib (se disponível) e qb-menu (fallback).
--
--   Hierarquia ox_lib:
--     pr_carkeys_manage_main        (lista de chaves da bolsa)
--       └─ pr_carkeys_key_{barcode} (edição de chave específica)
--
--   Ao editar som/distância/motor:
--     - Atualiza lastKeyArgs localmente
--     - Reabre o submenu da chave (sem ir ao servidor)
--     - Botão "voltar" do ox_lib leva ao pai correto
-- ============================================================

local currentMenuSlot = nil   -- slot da bolsa no inventário (nil = sem bolsa)
local lastMenuData    = nil   -- último menuData da bolsa (para reabrir sem ir ao servidor)
local lastKeyArgs     = nil   -- último args da chave aberta (para reabrir após edição)

-- ----------------------------------------------------------------
-- Receber dados do server e abrir o menu de gerenciamento da bolsa
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:openManageMenu", function(menuData)
    currentMenuSlot = menuData.slot
    lastMenuData    = menuData

    if Config.Default.closeInventory then
        Bridge.inventory.closeInventory()
    end

    renderManageMenu(menuData)
end)

-- ----------------------------------------------------------------
-- Renderizar menu principal (lista de chaves da bolsa)
-- ----------------------------------------------------------------
function renderManageMenu(menuData)
    local keys     = menuData.keys or {}
    local bagLabel = menuData.bagLabel or "Bolsa de Chaves"

    if #keys == 0 then
        PRCarkeys.Notify(Config.Notify.noKeys)
        return
    end

    -- ── ox_lib ────────────────────────────────────────────────
    if GetResourceState("ox_lib"):find("start") and lib then
        local options = {}

        for _, keyEntry in ipairs(keys) do
            local meta    = keyEntry.metadata or {}
            local dbData  = keyEntry.dbData   or {}
            local label   = keyEntry.itemLabel or keyEntry.itemName
            local plate   = meta.plate   or dbData.plate   or "???"
            local model   = meta.modelo  or "Desconhecido"
            local barcode = meta.barcode or "???"
            local sound   = dbData.sound    or Config.Sound.soundDefault
            local motor   = dbData.motor == 1 or dbData.motor == true
            local dist    = dbData.distance or Config.Default.UseKeyAnim.DefaultDistance or 5.0
            local keyType = dbData.key_type or "permanent"
            local level   = dbData.level    or "original"

            -- Registrar o contexto filho (submenu da chave)
            -- menu = "pr_carkeys_manage_main" faz o botão "voltar" ir para a lista
            registerKeyContext({
                barcode  = barcode,
                plate    = plate,
                model    = model,
                label    = label,
                sound    = sound,
                motor    = motor,
                distance = dist,
                key_type = keyType,
                level    = level,
            }, "pr_carkeys_manage_main")

            table.insert(options, {
                title       = label,
                description = ("Placa: %s | %s | %s"):format(plate, keyType, level),
                arrow       = true,
                onSelect    = function()
                    -- Salva contexto atual antes de abrir o submenu
                    lastKeyArgs = {
                        barcode  = barcode,
                        plate    = plate,
                        model    = model,
                        label    = label,
                        sound    = sound,
                        motor    = motor,
                        distance = dist,
                        key_type = keyType,
                        level    = level,
                    }
                    lib.showContext("pr_carkeys_key_" .. barcode)
                end,
            })
        end

        lib.registerContext({
            id      = "pr_carkeys_manage_main",
            title   = bagLabel .. " — Gerenciar Chaves",
            options = options,
        })
        lib.showContext("pr_carkeys_manage_main")

    -- ── qb-menu fallback ──────────────────────────────────────
    elseif GetResourceState("qb-menu"):find("start") then
        local menuItems = {
            { header = bagLabel .. " — Gerenciar Chaves", isMenuHeader = true },
        }

        for _, keyEntry in ipairs(keys) do
            local meta    = keyEntry.metadata or {}
            local dbData  = keyEntry.dbData   or {}
            local label   = keyEntry.itemLabel or keyEntry.itemName
            local plate   = meta.plate   or dbData.plate   or "???"
            local barcode = meta.barcode or "???"
            local keyType = dbData.key_type or "permanent"
            local level   = dbData.level    or "original"
            local sound   = dbData.sound    or Config.Sound.soundDefault
            local motor   = dbData.motor == 1 or dbData.motor == true
            local dist    = dbData.distance or Config.Default.UseKeyAnim.DefaultDistance or 5.0

            table.insert(menuItems, {
                header = ("%s | %s"):format(label, plate),
                txt    = ("Tipo: %s | Nivel: %s"):format(keyType, level),
                params = {
                    event = "pr_carkeys:client:__openKeySubMenu",
                    args  = {
                        barcode  = barcode,
                        label    = label,
                        plate    = plate,
                        sound    = sound,
                        motor    = motor,
                        distance = dist,
                        key_type = keyType,
                        level    = level,
                        fromBag  = true,
                    },
                },
            })
        end

        TriggerEvent("qb-menu:client:openMenu", menuItems)
    end
end

-- ----------------------------------------------------------------
-- Registra o contexto ox_lib de uma chave específica
-- parentMenu define o "voltar" — nil = fecha, string = vai para aquele id
-- ----------------------------------------------------------------
function registerKeyContext(args, parentMenu)
    local barcode = args.barcode
    local keyId   = "pr_carkeys_key_" .. barcode
    local label   = args.label   or (args.key_type .. " / " .. (args.level or ""))
    local plate   = args.plate   or "???"
    local sound   = args.sound   or Config.Sound.soundDefault
    local motor   = (args.motor == 1 or args.motor == true)
    local dist    = tonumber(args.distance) or Config.Default.UseKeyAnim.DefaultDistance or 5.0
    local keyType = args.key_type or "permanent"
    local level   = args.level   or "original"
    local model   = args.model   or "Desconhecido"

    lib.registerContext({
        id    = keyId,
        title = ("%s | %s"):format(label, plate),
        menu  = parentMenu,  -- botão "voltar" do ox_lib
        options = {
            {
                title       = "Informacoes",
                description = ("Placa: %s | Modelo: %s | Tipo: %s | Nivel: %s")
                    :format(plate, model, keyType, level),
                disabled    = true,
            },
            {
                title       = ("Som: %s"):format(resolveSoundLabel(sound)),
                description = "Alterar som ao trancar/destrancar",
                onSelect    = function()
                    editSound(barcode)
                end,
            },
            {
                title       = ("Motor ao destrancar: %s"):format(motor and "SIM" or "NAO"),
                description = "Ligar/desligar motor automatico",
                onSelect    = function()
                    -- Atualiza local imediatamente e reenvia o contexto atualizado
                    local newVal = motor and 0 or 1
                    TriggerServerEvent("pr_carkeys:server:updateKeyConfig", barcode, "motor", newVal)
                    -- Reabre o submenu localmente com o valor já invertido
                    local updated = shallowCopy(args)
                    updated.motor = newVal
                    lastKeyArgs = updated
                    registerKeyContext(updated, parentMenu)
                    lib.showContext(keyId)
                end,
            },
            {
                title       = ("Distancia do sinal: %.1f m"):format(dist),
                description = "Alterar alcance do sinal",
                onSelect    = function()
                    editDistance(barcode)
                end,
            },
            {
                title    = ("Registro: %s"):format(barcode),
                disabled = true,
            },
        },
    })
end

-- ----------------------------------------------------------------
-- Utilitário: copia rasa de tabela
-- ----------------------------------------------------------------
function shallowCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do copy[k] = v end
    return copy
end

-- ----------------------------------------------------------------
-- Utilitário: resolve o label do som pelo id configurado
-- Ex: "tranca_1" → "Som Padrao"
-- ----------------------------------------------------------------
function resolveSoundLabel(soundId)
    for _, s in ipairs(Config.Sound.sounds) do
        if s.id == soundId then return s.label end
    end
    return soundId  -- fallback: retorna o próprio id se não encontrar
end

-- ----------------------------------------------------------------
-- Sub-menu de edição de chave — chamado do inventário direto
-- (sem bolsa: parentMenu = nil, botão voltar fecha o menu)
-- ----------------------------------------------------------------
local function openKeySubMenuHandler(args)
    if not args or not args.barcode then return end

    lastKeyArgs = shallowCopy(args)

    -- Se não vem da bolsa, zera o slot para keyConfigUpdated saber
    if not args.fromBag then
        currentMenuSlot = nil
        lastMenuData    = nil
    end

    if Config.Default.closeInventory then
        Bridge.inventory.closeInventory()
    end

    if GetResourceState("ox_lib"):find("start") and lib then
        -- parentMenu: se veio da bolsa aponta para o menu principal, senão nil
        local parentMenu = (currentMenuSlot and currentMenuSlot > 0)
            and "pr_carkeys_manage_main" or nil

        registerKeyContext(args, parentMenu)
        lib.showContext("pr_carkeys_key_" .. args.barcode)
    else
        -- qb-menu
        local motor   = (args.motor == 1 or args.motor == true)
        local dist    = tonumber(args.distance) or Config.Default.UseKeyAnim.DefaultDistance or 5.0
        local label   = args.label or (args.key_type .. " / " .. (args.level or ""))
        local plate   = args.plate or "???"
        local barcode = args.barcode
        local sound   = args.sound or Config.Sound.soundDefault

        -- Se veio da bolsa, adiciona opção de voltar
        local menu = {}
        if args.fromBag then
            table.insert(menu, {
                header = "← Voltar para a Bolsa",
                txt    = "",
                params = {
                    event = "pr_carkeys:client:__reopenBagMenu",
                    args  = {},
                },
            })
        end

        table.insert(menu, { header = ("%s | %s"):format(label, plate), isMenuHeader = true })
        table.insert(menu, {
            header = ("Som: %s"):format(resolveSoundLabel(sound)),
            txt    = "Alterar som",
            params = { event = "pr_carkeys:client:__editSound", args = { barcode = barcode } },
        })
        table.insert(menu, {
            header = ("Motor ao destrancar: %s"):format(motor and "SIM" or "NAO"),
            txt    = "Clique para alternar",
            params = {
                isServer = true,
                event    = "pr_carkeys:server:updateKeyConfig",
                args     = { barcode, "motor", motor and 0 or 1 },
            },
        })
        table.insert(menu, {
            header = ("Distancia: %.1f m"):format(dist),
            txt    = "Alterar alcance",
            params = { event = "pr_carkeys:client:__editDistance", args = { barcode = barcode } },
        })

        TriggerEvent("qb-menu:client:openMenu", menu)
    end
end

-- Chamado pelo servidor (manageKey — inventário direto)
RegisterNetEvent("pr_carkeys:client:openKeySubMenu", function(args)
    openKeySubMenuHandler(args)
end)

-- Chamado localmente pelo qb-menu (vem da bolsa)
AddEventHandler("pr_carkeys:client:__openKeySubMenu", openKeySubMenuHandler)

-- qb-menu: voltar para o menu da bolsa
AddEventHandler("pr_carkeys:client:__reopenBagMenu", function()
    if lastMenuData then
        renderManageMenu(lastMenuData)
    end
end)

-- ----------------------------------------------------------------
-- Editar som — abre input e reabre o submenu com valor atualizado
-- ----------------------------------------------------------------
function editSound(barcode)
    local soundOptions = {}
    for _, s in ipairs(Config.Sound.sounds) do
        table.insert(soundOptions, { value = s.id, label = s.label })
    end

    if GetResourceState("ox_lib"):find("start") and lib then
        local input = lib.inputDialog("Alterar Som", {
            {
                type    = "select",
                label   = "Som ao trancar/destrancar",
                options = soundOptions,
            },
        })
        if input and input[1] then
            TriggerServerEvent("pr_carkeys:server:updateKeyConfig", barcode, "sound", input[1])
            -- Reabre o submenu localmente com o novo som
            if lastKeyArgs and lastKeyArgs.barcode == barcode then
                lastKeyArgs.sound = input[1]
                local parentMenu = (currentMenuSlot and currentMenuSlot > 0)
                    and "pr_carkeys_manage_main" or nil
                registerKeyContext(lastKeyArgs, parentMenu)
                lib.showContext("pr_carkeys_key_" .. barcode)
            end
        else
            -- Usuário cancelou — reabre o submenu sem alteração
            if lastKeyArgs and lastKeyArgs.barcode == barcode then
                lib.showContext("pr_carkeys_key_" .. barcode)
            end
        end
    else
        local soundMenu = {
            { header = "Escolher Som", isMenuHeader = true },
        }
        for _, s in ipairs(Config.Sound.sounds) do
            table.insert(soundMenu, {
                header = s.label,
                params = {
                    isServer = true,
                    event    = "pr_carkeys:server:updateKeyConfig",
                    args     = { barcode, "sound", s.id },
                },
            })
        end
        TriggerEvent("qb-menu:client:openMenu", soundMenu)
    end
end

AddEventHandler("pr_carkeys:client:__editSound", function(args)
    editSound(args.barcode)
end)

-- ----------------------------------------------------------------
-- Editar distância — abre input e reabre o submenu com valor atualizado
-- ----------------------------------------------------------------
function editDistance(barcode)
    if GetResourceState("ox_lib"):find("start") and lib then
        local input = lib.inputDialog("Alterar Distancia do Sinal", {
            {
                type    = "number",
                label   = "Distancia (metros)",
                min     = 1,
                max     = 30,
                default = Config.Default.UseKeyAnim.DefaultDistance or 5.0,
            },
        })
        if input and input[1] then
            local dist = tonumber(input[1])
            if dist and dist >= 1 and dist <= 30 then
                TriggerServerEvent("pr_carkeys:server:updateKeyConfig", barcode, "distance", dist)
                -- Reabre o submenu localmente com a nova distância
                if lastKeyArgs and lastKeyArgs.barcode == barcode then
                    lastKeyArgs.distance = dist
                    local parentMenu = (currentMenuSlot and currentMenuSlot > 0)
                        and "pr_carkeys_manage_main" or nil
                    registerKeyContext(lastKeyArgs, parentMenu)
                    lib.showContext("pr_carkeys_key_" .. barcode)
                end
            end
        else
            -- Usuário cancelou — reabre o submenu sem alteração
            if lastKeyArgs and lastKeyArgs.barcode == barcode then
                lib.showContext("pr_carkeys_key_" .. barcode)
            end
        end
    else
        local distMenu = {
            { header = "Escolher Distancia", isMenuHeader = true },
        }
        for _, v in ipairs({ 2, 3, 5, 8, 10, 15, 20 }) do
            table.insert(distMenu, {
                header = v .. " metros",
                params = {
                    isServer = true,
                    event    = "pr_carkeys:server:updateKeyConfig",
                    args     = { barcode, "distance", v },
                },
            })
        end
        TriggerEvent("qb-menu:client:openMenu", distMenu)
    end
end

AddEventHandler("pr_carkeys:client:__editDistance", function(args)
    editDistance(args.barcode)
end)

-- ----------------------------------------------------------------
-- keyConfigUpdated — atualiza o VehicleState imediatamente
-- Garante que distância, som e motor reflitam a mudança sem precisar
-- reiniciar o script ou sair/entrar do veículo
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:keyConfigUpdated", function(barcode, field, value)
    PRCarkeys.Debug(("Config atualizada | barcode=%s | %s=%s"):format(barcode, field, tostring(value)))

    local VehicleState = require 'client.modules.vehicle_state'

    -- Atualiza diretamente no VehicleState.permanentKeys pelo barcode
    for plate, data in pairs(VehicleState.permanentKeys) do
        if data.barcode == barcode then
            if field == "sound" then
                data.sound = value
            elseif field == "distance" then
                data.distance = tonumber(value)
            elseif field == "motor" then
                data.motor = (value == 1 or value == true)
            end
            Debug("INFO", ("[keyConfigUpdated] Cache local atualizado | plate=%s | %s=%s"):format(
                plate, field, tostring(value)))
            break
        end
    end
    -- Nada mais a fazer — menu já foi reaberto localmente com valor novo
end)
