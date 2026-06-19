fx_version 'cerulean'
game 'gta5'

author 'Gemini AI'
description 'Sistema di citofono con telecamera integrata per Qbox e ox_doorlock'
version '1.0.0'

use_fxv2_oal 'yes'

ui_page 'html/index.html'

shared_script '@ox_lib/init.lua'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_doorlock'
}
