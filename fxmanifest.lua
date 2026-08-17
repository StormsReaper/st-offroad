fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'StormsReaper'
description 'QBCore Point-to-Point Offroad Trails with Trailhead Peds and Route Recording'
version '2.0.1'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'qb-core',
    'oxmysql'
}
