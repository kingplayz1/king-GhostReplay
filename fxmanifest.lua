fx_version 'cerulean'
game 'gta5'

description 'High-Performance Zero-Overhead Ghost Racing Replay System'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/builder.lua',
    'client/menu.lua',
    'client/track.lua',
    'client/recorder.lua',
    'client/playback.lua',
    'client/main.lua'
}

server_scripts {
    'server/storage.lua',
    'server/tracks.lua',
    'server/main.lua'
}
