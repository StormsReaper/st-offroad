fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'OpenAI'
description 'QBCore Point-to-Point Offroad Trails with Trailhead Peds and Route Recording'
version '2.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/creation_indicator.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'qb-core',
    'oxmysql'
}
