fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author  'D4rkst3r'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua'
}

client_scripts {
    'client/placement.lua',
    'client/main.lua'
}

files {
    'stream/prop_fire_alarm.ytyp',
}
data_file 'DLC_ITYP_REQUEST' 'stream/prop_fire_alarm.ytyp'

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql'
}