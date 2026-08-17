fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'StormsReaper'
description 'QBCore Point-to-Point Offroad Trails with Trailhead Peds, Route Recording, Checkpoints and Leaderboards'
version '2.1.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/leaderboard.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'qb-core',
    'oxmysql'
}
