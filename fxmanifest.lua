name          "pr_carkeys"
description   "Sistema de Chaves de Veículo"
version       "1.3.0"
author        "Pierremoraes-ofc"
repository    "https://github.com/Pierremoraes-ofc/pr_carkeys"

fx_version "cerulean"
game       "gta5"
lua54      "yes"

use_experimental_fxv2_oal "yes"

-- ox_lib é OPCIONAL mas recomendado (menus, progressbar, skillcheck)
-- pr_3dsound é OPCIONAL (som 3D ao trancar/destrancar)
-- oxmysql | ghmattimysql | mysql-async: configure em Config.SQL
dependencies {
    -- nenhuma obrigatória no fxmanifest para não quebrar em setups variados
}

shared_scripts {
    'config/config.lua',
    'shared/main.lua',
    'shared/bridge.lua',
}

files {
    'song/*.ogg',
}

server_scripts {
    '@ox_lib/init.lua',
    'server/sv_main.lua',
    'server/sv_shop.lua',
    'server/sv_cache.lua',
    'server/sv_bag.lua',
    'server/sv_commands.lua',
    'server/sv_keys.lua',
    'server/sv_expiration.lua',
    'server/sv_vehicle.lua',
}

client_scripts {
    '@ox_lib/init.lua',
    'client/cl_main.lua',
    'client/cl_bag.lua',
    'client/cl_keys.lua',
    'client/cl_menu.lua',
    -- Módulos do sistema de veículos (Parte 1)
    'client/modules/vehicle_state.lua',
    'client/modules/vehicle_lock.lua',
    'client/modules/key_in_vehicle.lua',
    'client/modules/vehicle_init.lua',
    'client/modules/carjack.lua',
}
