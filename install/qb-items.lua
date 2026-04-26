-- ============================================================
--   pr_carkeys — install/qb-items.lua
--   Cole estes itens no seu qb-core/shared/items.lua
-- ============================================================

-- ===== BOLSAS =====
["carkey_bag"] = {
    name        = "carkey_bag",
    label       = "Bolsa de Chaves",
    weight      = 500,
    type        = "item",
    image       = "carkey_bag.png",
    unique      = true,   -- item único (não empilha)
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Bolsa exclusiva para guardar chaves de veículo."
},

["carkey_bag_large"] = {
    name        = "carkey_bag_large",
    label       = "Bolsa de Chaves Grande",
    weight      = 800,
    type        = "item",
    image       = "carkey_bag_large.png",
    unique      = true,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Bolsa grande para guardar várias chaves de veículo."
},

-- ===== CHAVES =====
["carkey_permanent"] = {
    name        = "carkey_permanent",
    label       = "Chave Original",
    weight      = 50,
    type        = "item",
    image       = "carkey_permanent.png",
    unique      = true,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Chave original de veículo. Permanente."
},

["carkey_copy"] = {
    name        = "carkey_copy",
    label       = "Chave Cópia",
    weight      = 50,
    type        = "item",
    image       = "carkey_copy.png",
    unique      = true,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Cópia de chave de veículo."
},

["carkey_temp"] = {
    name        = "carkey_temp",
    label       = "Chave Temporária",
    weight      = 50,
    type        = "item",
    image       = "carkey_temp.png",
    unique      = true,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Chave temporária. Expira após o período configurado."
},

["carkey_single"] = {
    name        = "carkey_single",
    label       = "Chave Avulsa",
    weight      = 50,
    type        = "item",
    image       = "carkey_single.png",
    unique      = true,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = "Chave de uso único. Some após usar."
},
