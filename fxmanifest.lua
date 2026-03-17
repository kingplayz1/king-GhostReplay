fx_version 'cerulean'
game 'gta5'

description 'High-Performance Ghost Racing Replay + Pro Track Builder v2'
version '3.2.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'config/track_props.lua',   -- [NEW] Config-based prop catalogue
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js'
}

client_scripts {
    -- Core utilities
    'client/utils.lua',

    -- Builder v2 (Simplified & Unified)
    'client/builder_v2/undo.lua',
    'client/builder_v2/fsm.lua',
    'client/builder_v2/analysis.lua',
    'client/builder_v2/checkpoints.lua',
    'client/builder_v2/props.lua',
    'client/builder_v2/preview.lua',
    'client/builder_v2/core.lua',

    -- Race engine & replay (unchanged)
    'client/track.lua',
    'client/recorder.lua',
    'client/playback.lua',
    'client/passenger.lua',
    'client/hud.lua',
    'client/camera.lua',
    'client/menu.lua',
    'client/main.lua',
}

server_scripts {
    'server/storage.lua',
    'server/tracks.lua',   -- [UPDATED] v2 CRUD
    'server/main.lua',
}
