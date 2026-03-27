fx_version 'cerulean'
game 'gta5'
lua54 'yes' -- Nutze Lua 5.4 für bessere Performance

author 'D4rkst3r'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/utils.lua',
    'server/database.lua', -- Zuerst laden!
    'server/main.lua'
}

client_scripts {
    'client/placement.lua',
    'client/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql'
}
