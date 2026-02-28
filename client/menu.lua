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
                    Wait(100)
                    lib.showContext('ghostreplay_builder_active')
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

local function OpenMainMenu()
    lib.registerContext({
        id = 'ghostreplay_builder_main',
        title = 'GhostReplay Track Builder',
        options = {
            {
                title = 'Start New Track',
                description = 'Begin mapping a new track',
                icon = 'plus',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:Builder:Start")
                    Wait(200)
                    OpenActiveBuilderMenu()
                end
            },
            {
                title = 'Start Ghost Record',
                description = 'Begin recording telemetry for the current track',
                icon = 'video',
                onSelect = function()
                    -- Use track name if loaded, otherwise fallback
                    local name = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
                    
                    if TrackSystem and not TrackSystem.CurrentTrack then
                        -- Mock track for testing if not loaded
                        TrackSystem.LoadTrack({
                            name = name,
                            type = "circuit",
                            startLine = { left = vector3(0,0,0), right = vector3(10,0,0) }
                        })
                    end
                    
                    if TrackSystem then
                        TrackSystem.StartRace(GetVehiclePedIsIn(PlayerPedId(), false))
                    end
                    TriggerEvent("GhostReplay:Client:RecordStart")
                    lib.notify({description = 'Recording Started on ' .. name, type = 'success'})
                end
            },
            {
                title = 'Stop Ghost Record',
                description = 'Finish recording and save',
                icon = 'stop-circle',
                onSelect = function()
                    TriggerEvent("GhostReplay:Client:RecordStop")
                    if TrackSystem then
                        TrackSystem.EndRace(true)
                        
                        -- Auto save test
                        local testData = {
                            model = GetEntityModel(GetVehiclePedIsIn(PlayerPedId(), false)),
                            frames = GhostRecorder.GetRecordedData()
                        }
                        TriggerServerEvent("GhostReplay:Server:SaveGhostData", TrackSystem.CurrentTrack.name, testData)
                    end
                    lib.notify({description = 'Recording Stopped & Sent to Server', type = 'info'})
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
