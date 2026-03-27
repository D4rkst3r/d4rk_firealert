fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author  'D4rkst3r'
version '2.1.0'

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

-- FIX #10: ACE-Permissions für Commands registrieren
-- In server.cfg: add_ace group.firefighter command.install_bma allow
--                add_ace group.admin command.test_bma allow
ace_permissions {
    'command.install_bma',
    'command.test_bma',
}