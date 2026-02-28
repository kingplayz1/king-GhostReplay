-- Utilizes ox_lib to create a Context Menu for the Track Builder

local function OpenActiveBuilderMenu()
    lib.registerContext({
        id = 'ghostreplay_builder_active',
        title = 'Building Track...',
        options = {
            {
                title = 'Set Start Line (LEFT)',
                description = 'Set left coordinate of start line',
                icon = 'flag',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:SetStart", "left")
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
                end
            },
            {
                title = 'Set Start Line (RIGHT)',
                description = 'Set right coordinate of start line',
                icon = 'flag',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:SetStart", "right")
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
                end
            },
            {
                title = 'Add Waypoint',
                description = 'Drop a waypoint at current location',
                icon = 'map-marker-alt',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:AddWaypoint")
                    -- Show property editor for the new waypoint
                    local input = lib.inputDialog('Waypoint Props', {
                        {type = 'number', label = 'Min Speed (km/h)', description = 'Penalty if slower than this', default = 0},
                        {type = 'number', label = 'Corridor Width (m)', description = 'Allowed deviation', default = 20}
                    })
                    if input then
                        TriggerEvent("GhostReplay:Client:Builder:SetWaypointProps", input[1], input[2])
                    end
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
                end
            },
            {
                title = 'Anti-Cut Zone Tool',
                description = 'Create a polygon zone that penalizes cutting',
                icon = 'draw-polygon',
                onSelect = function()
                    lib.registerContext({
                        id = 'ghostreplay_builder_zone',
                        title = 'Polygon Zone Creator',
                        menu = 'ghostreplay_builder_active',
                        options = {
                            {
                                title = 'Start New Zone',
                                icon = 'plus',
                                onSelect = function()
                                    TriggerEvent("GhostReplay:Client:Builder:StartZone")
                                    lib.showContext('ghostreplay_builder_zone')
                                end
                            },
                            {
                                title = 'Add Corner Point',
                                description = 'Add current position to polygon',
                                icon = 'vector-square',
                                onSelect = function()
                                    TriggerEvent("GhostReplay:Client:Builder:AddZonePoint")
                                    lib.showContext('ghostreplay_builder_zone')
                                end
                            },
                            {
                                title = 'Finalize Zone',
                                description = 'Close and save this polygon',
                                icon = 'check-circle',
                                onSelect = function()
                                    TriggerEvent("GhostReplay:Client:Builder:CompleteZone")
                                    lib.showContext('ghostreplay_builder_zone')
                                end
                            }
                        }
                    })
                    lib.showContext('ghostreplay_builder_zone')
                end
            },
            {
                title = 'Set Finish Line (LEFT)',
                description = 'Set left coordinate of finish line',
                icon = 'flag-checkered',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:SetFinish", "left")
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
                end
            },
            {
                title = 'Set Finish Line (RIGHT)',
                description = 'Set right coordinate of finish line',
                icon = 'flag-checkered',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:SetFinish", "right")
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
                end
            },
            {
                title = 'Save Track',
                description = 'Save tracking points to server',
                icon = 'save',
                onSelect = function()
                    -- Use ox_lib input dialog
                    local input = lib.inputDialog('Save Circuit', {
                        {type = 'input', label = 'Track Name', description = 'Enter a unique name for this track', required = true}
                    })

                    if not input then return end -- User cancelled dialog
                    
                    TriggerEvent("GhostReplay:Client:Builder:Save", input[1])
                end
            },
            {
                title = 'Cancel Build',
                description = 'Discard all progress',
                icon = 'times',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:Cancel")
                    lib.notify({description = 'Build cancelled.', type = 'error'})
                end
            }
        }
    })
    
    lib.showContext('ghostreplay_builder_active')
end

local function OpenPlaybackMenu()
    local options = {}
    
    for id, ghost in pairs(GhostPlayback.ActiveGhosts) do
        local name = ghost.data.name or "Unnamed Ghost"
        local timePos = string.format("%.2fs", ghost.currentTime / 1000)
        
        table.insert(options, {
            title = name .. " (" .. timePos .. ")",
            description = "Pause/Resume or Scrub timelines",
            icon = 'car-side',
            onSelect = function()
                lib.registerContext({
                    id = 'ghostreplay_control_' .. id,
                    title = 'Control: ' .. name,
                    menu = 'ghostreplay_playback_main',
                    options = {
                        {
                            title = ghost.isPaused and 'Resume Playback' or 'Pause Playback',
                            icon = ghost.isPaused and 'play' or 'pause',
                            onSelect = function()
                                GhostPlayback.TogglePause(id)
                                OpenPlaybackMenu()
                            end
                        },
                        {
                            title = 'Scrub Forward (+5s)',
                            icon = 'forward',
                            onSelect = function()
                                GhostPlayback.Scrub(id, 5000)
                                OpenPlaybackMenu()
                            end
                        },
                        {
                            title = 'Scrub Backward (-5s)',
                            icon = 'backward',
                            onSelect = function()
                                GhostPlayback.Scrub(id, -5000)
                                OpenPlaybackMenu()
                            end
                        },
                        {
                            title = 'Stop and Delete Ghost',
                            icon = 'trash',
                            onSelect = function()
                                GhostPlayback.Stop(id)
                                OpenPlaybackMenu()
                            end
                        }
                    }
                })
                lib.showContext('ghostreplay_control_' .. id)
            end
        })
    end

    if #options == 0 then
        lib.notify({description = "No active ghosts to control.", type = "error"})
        return
    end

    lib.registerContext({
        id = 'ghostreplay_playback_main',
        title = 'Active Ghost Controls',
        menu = 'ghostreplay_builder_main',
        options = options
    })
    lib.showContext('ghostreplay_playback')
end

local function OpenSessionHistoryMenu()
    local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
    local options = {}

    if #GhostRecorder.SessionHistory == 0 then
        table.insert(options, { title = 'No sessions recorded yet', description = 'Finish a lap to see it here', disabled = true })
    else
        for i, data in ipairs(GhostRecorder.SessionHistory) do
            local timeStr = string.format("%.2fs", data.time / 1000)
            table.insert(options, {
                title = "LAP #" .. (#GhostRecorder.SessionHistory - i + 1) .. " - " .. timeStr,
                description = "Captured in this session",
                onSelect = function()
                    lib.registerContext({
                        id = 'ghostreplay_session_detail',
                        title = 'Session Lap Options',
                        menu = 'ghostreplay_session_history',
                        options = {
                            {
                                title = 'Play Ghost',
                                icon = 'play',
                                onSelect = function()
                                    data.type = "session"
                                    data.name = "Session Lap"
                                    TriggerEvent("GhostReplay:Client:ReceiveGhostData", trackName, data)
                                end
                            },
                            {
                                title = 'START CHASE (Sync Start & Record)',
                                description = 'Spawns ghost and starts countdown to race it',
                                icon = 'car',
                                onSelect = function()
                                    data.type = "session"
                                    data.name = "Ghost Lead"
                                    -- 1. Play ghost in paused state (v1.9 Elite)
                                    GhostPlayback.Play(data, trackName, false)
                                    -- 2. Request countdown
                                    TriggerServerEvent("GhostReplay:Server:RequestGridStart", trackName)
                                    lib.notify({description = 'Setting up chase...', type = 'info'})
                                end
                            },
                            {
                                title = 'Delete From Session',
                                icon = 'trash',
                                onSelect = function()
                                    table.remove(GhostRecorder.SessionHistory, i)
                                    OpenSessionHistoryMenu()
                                end
                            }
                        }
                    })
                    lib.showContext('ghostreplay_session_detail')
                end
            })
        end
    end

    lib.registerContext({
        id = 'ghostreplay_session_history',
        title = 'Session LAP History',
        menu = 'ghostreplay_builder_main',
        options = options
    })
    lib.showContext('ghostreplay_session_history')
end

local function OpenLeaderboardMenu()
    local name = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
    TriggerServerEvent("GhostReplay:Server:RequestLeaderboard", name)
end

RegisterNetEvent("GhostReplay:Client:ReceiveLeaderboard")
AddEventHandler("GhostReplay:Client:ReceiveLeaderboard", function(trackName, data)
    local options = {
        {
            title = 'Global Record',
            description = data.global and string.format("%.2fs", data.global/1000) or "No record set",
            icon = 'trophy',
            onSelect = function()
                TriggerServerEvent("GhostReplay:Server:RequestGhostData", trackName, "global")
                lib.notify({description = 'Loading World Record Ghost...', type = 'info'})
            end
        },
        {
            title = 'Your Personal Best',
            description = data.pb and string.format("%.2fs", data.pb/1000) or "No record set",
            icon = 'user',
            onSelect = function()
                TriggerServerEvent("GhostReplay:Server:RequestGhostData", trackName, "pb")
                lib.notify({description = 'Loading your Personal Best Ghost...', type = 'info'})
            end
        }
    }
    
    lib.registerContext({
        id = 'ghostreplay_leaderboard',
        title = 'Leaderboard: ' .. trackName,
        menu = 'ghostreplay_builder_main',
        options = options
    })
    lib.showContext('ghostreplay_leaderboard')
end)

local function OpenSettingsMenu()
    local options = {
        {
            title = 'Hologram Mode',
            description = 'Make ghosts look like glowing neon holograms',
            icon = 'bolt',
            onSelect = function()
                GhostPlayback.Settings.HologramMode = not GhostPlayback.Settings.HologramMode
                lib.notify({description = 'Hologram Mode: ' .. (GhostPlayback.Settings.HologramMode and "ON" or "OFF"), type = 'info'})
            end
        },
        {
            title = 'Cinematic Replay Camera',
            description = 'Experience the replay from professional trackside angles',
            icon = 'video',
            onSelect = function()
                GhostCamera.Toggle()
                lib.notify({description = 'Cinematic Camera: ' .. (GhostCamera.Active and "ON" or "OFF"), type = 'info'})
            end
        },
        {
            title = 'Toggle Gap HUD',
            description = 'Show/hide the time difference timer',
            icon = 'stopwatch',
            onSelect = function()
                GhostHUD.Visible = not GhostHUD.Visible
                lib.notify({description = 'Gap HUD: ' .. (GhostHUD.Visible and "Visible" or "Hidden"), type = 'info'})
            end
        },
        {
            title = 'Toggle 3D Floating Names',
            description = 'Show/hide nametags above ghosts',
            icon = 'tag',
            onSelect = function()
                GhostHUD.LabelsVisible = not GhostHUD.LabelsVisible
                lib.notify({description = '3D Labels: ' .. (GhostHUD.LabelsVisible and "Visible" or "Hidden"), type = 'info'})
            end
        }
    }

    lib.registerContext({
        id = 'ghostreplay_settings',
        title = 'Visual & Cinematic Settings',
        menu = 'ghostreplay_builder_main',
        options = options
    })
    lib.showContext('ghostreplay_settings')
end

local function OpenMainMenu()
    local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
    
    lib.registerContext({
        id = 'ghostreplay_builder_main',
        title = 'GhostReplay Elite Menu',
        options = {
            {
                title = '1. QUICK RACE & RECORD',
                description = 'Instantly start the timer and record your car data',
                icon = 'play',
                onSelect = function()
                    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                    if not vehicle or vehicle == 0 then
                        lib.notify({description = 'You must be in a vehicle!', type = 'error'})
                        return
                    end
                    
                    if not TrackSystem.CurrentTrack then
                        -- Fallback for testing if no track loaded
                        TrackSystem.LoadTrack({
                            name = trackName,
                            type = "circuit",
                            startLine = { left = vector3(0,0,0), right = vector3(10,0,0) }
                        })
                    end
                    
                    TrackSystem.StartRace(vehicle)
                    lib.notify({description = 'Race & Recording will start when you cross the line!', type = 'success'})
                end
            },
            {
                title = 'INSTANT REPLAY LAST RUN',
                description = 'Watch your most recent successful lap immediately',
                icon = 'redo',
                disabled = (GhostRecorder.LastRunData == nil),
                onSelect = function()
                    local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
                    local data = GhostRecorder.LastRunData
                    if data then
                        -- Tag metadata for display
                        data.type = "session"
                        data.name = "Last Run (" .. string.format("%.2fs", data.time/1000) .. ")"
                        
                        TriggerEvent("GhostReplay:Client:ReceiveGhostData", trackName, data)
                        lib.notify({description = 'Loading your last run...', type = 'info'})
                    end
                end
            },
            {
                title = '2. TRACK LEADERBOARD',
                description = 'View and race against Personal Bests or World Records',
                icon = 'trophy',
                onSelect = function()
                    OpenLeaderboardMenu()
                end
            },
            {
                title = '3. MULTI-GHOST MANAGER',
                description = 'Load multiple ghosts to race against at once',
                icon = 'layer-group',
                onSelect = function()
                    -- PICKER: PB, WR, or Session History
                    lib.registerContext({
                        id = 'ghostreplay_multi_picker',
                        title = 'Multi-Ghost Manager',
                        menu = 'ghostreplay_builder_main',
                        options = {
                            {
                                title = 'SESSION LAP HISTORY',
                                description = 'View all recordings from this session',
                                icon = 'history',
                                onSelect = function() OpenSessionHistoryMenu() end
                            },
                            {
                                title = 'LOAD PERSONAL BEST',
                                icon = 'user',
                                onSelect = function() TriggerServerEvent("GhostReplay:Server:RequestGhostData", trackName, "pb") end
                            },
                            {
                                title = 'LOAD WORLD RECORD',
                                icon = 'globe',
                                onSelect = function() TriggerServerEvent("GhostReplay:Server:RequestGhostData", trackName, "global") end
                            }
                        }
                    })
                    lib.showContext('ghostreplay_multi_picker')
                end
            },
            {
                title = '4. VISUAL & CINEMATIC SETTINGS',
                description = 'Toggle Holograms, HUD, and Replay Cameras',
                icon = 'palette',
                onSelect = function()
                    OpenSettingsMenu()
                end
            },
            {
                title = '5. MULTIPLAYER GRID START',
                description = 'Synchronize 3-2-1-GO countdown for all nearby racers',
                icon = 'users',
                onSelect = function()
                    local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
                    TriggerServerEvent("GhostReplay:Server:RequestGridStart", trackName)
                    lib.notify({description = 'Requesting Grid Start...', type = 'info'})
                end
            },
            {
                title = 'Builder: Setup New Track',
                description = 'Begin mapping a new track layout',
                icon = 'map-marker-alt',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:Start")
                    Wait(200)
                    OpenActiveBuilderMenu()
                end
            },
            {
                title = 'Active Ghost Controls',
                description = 'Spectate, Pause, or Scrub active ghosts',
                icon = 'sliders-h',
                disabled = not next(GhostPlayback.ActiveGhosts),
                onSelect = function()
                    OpenPlaybackMenu()
                end
            },
            {
                title = 'Passenger Mode',
                description = 'Sit inside an active ghost car',
                icon = 'users',
                disabled = not next(GhostPlayback.ActiveGhosts),
                onSelect = function()
                    for id, _ in pairs(GhostPlayback.ActiveGhosts) do
                        PassengerMode.Enter(id)
                        break
                    end
                end
            }
        }
    })
    
    lib.showContext('ghostreplay_builder_main')
end

RegisterCommand("trackmenu", function()
    -- Check if building state is already active from builder.lua
    if TrackBuilder and TrackBuilder.IsBuilding then
        OpenActiveBuilderMenu()
    else
        OpenMainMenu()
    end
end, false)
