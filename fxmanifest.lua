fx_version 'cerulean'
game 'gta5'

author 'D4RK Development'
description 'Realistisches Brandmeldesystem (BMA)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua' -- Wichtig: Vor Client/Server laden!
}

-- Unter server_scripts:
server_scripts {
    '@oxmysql/lib/utils.lua',
    'server/database.lua', -- Zuerst die DB-Funktionen definieren
    'server/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/placement.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql'
}
