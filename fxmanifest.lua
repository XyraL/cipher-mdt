fx_version 'cerulean'
game 'gta5'

name 'CipherMDT'
description 'Full-featured Police MDT with CAD integration for QBox/QBCore'
version '1.4.0'
author 'cipher-mdt'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'oxmysql',
}

client_scripts {
    'client/main.lua',
    'client/cad.lua',
    'client/blips.lua',
    'client/dispatch.lua',
    'client/sounds.lua',
    'client/target.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/dispatch.lua',
    'server/officers.lua',
    'server/civilians.lua',
    'server/vehicles.lua',
    'server/warrants.lua',
    'server/bolos.lua',
    'server/records.lua',
    'server/penal.lua',
    'server/incidents.lua',
    'server/cad.lua',
    'server/bulletins.lua',
    'server/bodycam.lua',
    'server/target.lua',
    'server/shiftlog.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/panels/officer.js',
    'html/js/panels/civilians.js',
    'html/js/panels/vehicles.js',
    'html/js/panels/warrants.js',
    'html/js/panels/bolos.js',
    'html/js/panels/records.js',
    'html/js/panels/penal.js',
    'html/js/panels/incidents.js',
    'html/js/panels/cad.js',
    'html/js/panels/bulletins.js',
    'html/js/panels/quickdispatch.js',
    'html/js/panels/mugshots.js',
    'html/js/panels/callhistory.js',
    'html/js/panels/shiftlog.js',
    'html/js/components/namesearch.js',
}

lua54 'yes'
