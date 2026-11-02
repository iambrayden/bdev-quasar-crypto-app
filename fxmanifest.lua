fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bdev-quasar-crypto-app'
author 'bdev'
description 'Crypto exchange app for the Quasar smartphone (Qbox)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/phone.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/prices.lua',
    'server/main.lua',
    'server/admin.lua',
}

-- The phone loads the app UI in an iframe via https://cfx-nui-<resource>/html/index.html
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/icon.png',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}
