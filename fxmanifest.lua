fx_version 'cerulean'
game 'gta5'

description 'High-Performance Zero-Overhead Ghost Racing Replay System'
version '2.3.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js'
}

client_scripts {
    'client/utils.lua',
    'client/builder.lua',
    'client/builder_props.lua',
    'client/builder_state.lua',
    'client/menu.lua',
    'client/track.lua',
    'client/recorder.lua',
    'client/playback.lua',
    'client/passenger.lua',
    'client/hud.lua',
    'client/camera.lua',
    'client/main.lua'
}

server_scripts {
    'server/storage.lua',
    'server/tracks.lua',
    'server/main.lua'
}
