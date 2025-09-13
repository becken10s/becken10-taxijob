fx_version 'cerulean'
game 'gta5'
name 'nxtvjr_taxi'
description 'Advanced NPC Taxi System with Cinematic Experience'
author 'nxtvjr'
version '2.0.0'

shared_scripts {
    'config/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'qb-core',
    'oxmysql'
}

lua54 'yes'