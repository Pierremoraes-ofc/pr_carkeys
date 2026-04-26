-- ============================================================
--   pr_carkeys — install/ox-items.lua
--   Cole estes itens no seu ox_inventory/data/items.lua
-- ============================================================

-- ===== BOLSAS =====
    ['carkey_bag'] = {
        label       = 'Bolsa de Chaves',
        weight      = 500,
        stack       = false,   -- ÚNICA por slot (não empilha)
        close       = true,
        description = 'Bolsa exclusiva para guardar chaves de veículo.',
        buttons     = {
            {
                label  = 'Gerenciar Chaves',
                action = function(slot)
                    TriggerServerEvent('pr_carkeys:server:manageBag', slot)
                end,
            },
        },
    },

    ['carkey_bag_large'] = {
        label       = 'Bolsa de Chaves Grande',
        weight      = 800,
        stack       = false,
        close       = true,
        description = 'Bolsa grande para guardar várias chaves de veículo.',
        buttons     = {
            {
                label  = 'Gerenciar Chaves',
                action = function(slot)
                    TriggerServerEvent('pr_carkeys:server:manageBag', slot)
                end,
            },
        },
    },

    -- ===== CHAVES =====
    ['carkey_permanent'] = {
        label       = 'Chave Original',
        weight      = 50,
        stack       = false,
        close       = true,
        description = 'Chave original de veículo. Permanente.',
        buttons     = {
            {
                label  = 'Configurar Chave',
                action = function(slot, item)
                    -- Passa o barcode direto da metadata — funciona do inventário e do stash
                    local barcode = item and item.metadata and item.metadata.barcode
                    if barcode then
                        TriggerServerEvent('pr_carkeys:server:manageKeyByBarcode', barcode)
                    end
                end,
            },
        },
    },

    ['carkey_copy'] = {
        label       = 'Chave Cópia',
        weight      = 50,
        stack       = false,
        close       = true,
        description = 'Cópia de chave de veículo.',
        buttons     = {
            {
                label  = 'Configurar Chave',
                action = function(slot, item)
                    local barcode = item and item.metadata and item.metadata.barcode
                    if barcode then
                        TriggerServerEvent('pr_carkeys:server:manageKeyByBarcode', barcode)
                    end
                end,
            },
        },
    },

    ['carkey_temp'] = {
        label       = 'Chave Temporária',
        weight      = 50,
        stack       = false,
        close       = true,
        description = 'Chave temporária. Expira após o período configurado.',
    },

    ['carkey_single'] = {
        label       = 'Chave Avulsa',
        weight      = 50,
        stack       = false,
        close       = true,
        description = 'Chave de uso único. Some após usar.',
    },
