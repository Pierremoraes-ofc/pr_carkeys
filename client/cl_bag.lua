-- ============================================================
--   pr_carkeys — client/cl_bag.lua
--   Lógica client-side das bolsas de chave.
-- ============================================================

-- Estado da bolsa em uso (protegido contra double-click com flag de lock)
local bagInUse       = false
local pendingBagSlot = nil
local pendingBagItem = nil

-- ----------------------------------------------------------------
-- Uso do item bolsa — disparado pelo server via RegisterUsableItem
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:useBag", function(data)
    -- Proteção contra race condition (duplo uso rápido)
    if bagInUse then
        PRCarkeys.Debug("useBag: ignorado — bolsa ja em uso.")
        return
    end

    local bagConfig = Config.Bags[data.item]
    if not bagConfig then return end

    bagInUse       = true
    pendingBagSlot = data.slot
    pendingBagItem = data.item

    if Config.Default.KeyMetadata.openMenu then
        showBagChoiceMenu(data, bagConfig)
    else
        openBagAsStash(pendingBagSlot, bagConfig)
    end
end)

-- ----------------------------------------------------------------
-- Menu de escolha do modo de uso da bolsa
-- ----------------------------------------------------------------
function showBagChoiceMenu(data, bagConfig)
    -- ox_lib (opcional)
    if GetResourceState("ox_lib"):find("start") and lib then
        lib.registerContext({
            id    = "pr_carkeys_bag_choice",
            title = bagConfig.label,
            options = {
                {
                    title       = "Abrir Bolsa",
                    description = "Visualizar chaves como inventario",
                    onSelect    = function()
                        openBagAsStash(data.slot, bagConfig)
                    end,
                },
                {
                    title       = "Gerenciar Chaves",
                    description = "Configurar cada chave individualmente",
                    onSelect    = function()
                        TriggerServerEvent("pr_carkeys:server:manageBag", data.slot)
                    end,
                },
            },
            onClose = function()
                bagInUse = false
            end,
        })
        lib.showContext("pr_carkeys_bag_choice")

    -- qb-menu fallback
    elseif GetResourceState("qb-menu"):find("start") then
        exports["qb-menu"]:openMenu({
            {
                header       = bagConfig.label,
                isMenuHeader = true,
            },
            {
                header = "Abrir Bolsa",
                txt    = "Visualizar chaves como inventario",
                params = {
                    event = "pr_carkeys:client:__openBagAsStash",
                    args  = { slot = data.slot, itemName = data.item },
                },
            },
            {
                header = "Gerenciar Chaves",
                txt    = "Configurar cada chave individualmente",
                params = {
                    isServer = true,
                    event    = "pr_carkeys:server:manageBag",
                    args     = data.slot,
                },
            },
        })
        -- qb-menu não tem onClose; libera após curto delay
        SetTimeout(300, function() bagInUse = false end)

    else
        -- Nenhum menu disponível: abre direto como stash
        openBagAsStash(data.slot, bagConfig)
    end
end

-- ----------------------------------------------------------------
-- Abre a bolsa como stash (inventário visual)
-- ----------------------------------------------------------------
function openBagAsStash(slot, bagConfig)
    local cfg = bagConfig or Config.Bags[pendingBagItem]
    if not cfg then
        bagInUse = false
        return
    end

    PRCarkeys.ProgressBar(
        "Abrindo " .. cfg.label .. "...",
        cfg.openTime,
        cfg.anim,
        function(success)
            if not success then
                bagInUse = false
                return
            end
            TriggerServerEvent("pr_carkeys:server:openBag", slot or pendingBagSlot)
            -- bagInUse liberado quando o stash fechar (ou após delay de segurança)
            SetTimeout(cfg.openTime + 2000, function()
                bagInUse = false
            end)
        end
    )
end

-- Evento local usado pelo qb-menu (params.event) para abrir como stash
AddEventHandler("pr_carkeys:client:__openBagAsStash", function(args)
    local cfg = Config.Bags[args.itemName]
    openBagAsStash(args.slot, cfg)
end)

-- ----------------------------------------------------------------
-- Recebe stashId do servidor e abre o inventário localmente (ox)
-- Feito no client para evitar o erro "cannot open inventory (is busy)"
-- ----------------------------------------------------------------
RegisterNetEvent("pr_carkeys:client:openStash", function(stashId)
    -- ActiveInventory é definido em shared/main.lua e acessível no client
    if ActiveInventory == "ox_inventory" then
        exports.ox_inventory:openInventory("stash", stashId)
    end
    -- Para qb-inventory o servidor já abre diretamente
    bagInUse = false
end)
