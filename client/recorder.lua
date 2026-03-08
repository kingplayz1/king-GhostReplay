-- Records and maintains lap telemetry 

GhostRecorder = {}
GhostRecorder.Frames = {}
GhostRecorder.IsRecording = false
GhostRecorder.RecordStartTime = 0
GhostRecorder.LastRunData = nil -- Elite: Stores the last successfully captured run
GhostRecorder.SessionHistory = {} -- Elite Part 5: List of session recordings
GhostRecorder.LastPacket = {} -- Elite Part 7: Tracking for Delta Compression

local maxFrames = (Config.MaxRecordingTimeSeconds * 1000) / Config.Timestep

function GhostRecorder.Start()
    if GhostRecorder.IsRecording then return end
    
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end

    GhostRecorder.Frames = {}
    GhostRecorder.IsRecording = true
    GhostRecorder.RecordStartTime = GetGameTimer()
    -- Capture Metadata for spawning
    GhostRecorder.ModelHash = GetEntityModel(vehicle)
    GhostRecorder.VehicleCosmetics = Utils.GetVehicleCosmetics(vehicle)
    GhostRecorder.PedAppearance = Utils.GetPedAppearance(PlayerPedId())
    
    local frameCount = 0
    GhostRecorder.IsRecording = true
    
    -- Main recording loop (Runs every Config.Timestep, e.g., 25ms)
    Citizen.CreateThread(function()
        while GhostRecorder.IsRecording do
            local currentVehicle = GetVehiclePedIsIn(ped, false)
            
            -- Stop if out of vehicle or max frames reached
            if not currentVehicle or currentVehicle == 0 or frameCount >= maxFrames then
                GhostRecorder.Stop()
                break
            end
            
            local now = GetGameTimer() - GhostRecorder.RecordStartTime
            local pos = GetEntityCoords(currentVehicle)
            local rot = GetEntityRotation(currentVehicle, 2)
            local velocity = GetEntityVelocity(currentVehicle) -- Elite: Capture for Hermite Splines
            local steeringAngle = GetVehicleSteeringAngle(currentVehicle)
            
            -- Enhanced Telemetry (Inspired by SP GhostReplay)
            local rpm = GetVehicleCurrentRpm(currentVehicle)
            local gear = GetVehicleCurrentGear(currentVehicle)
            local throttle = GetControlValue(0, 71) -- Acceleration
            local siren = IsVehicleSirenOn(currentVehicle)
            local indicators = GetVehicleIndicatorLights(currentVehicle)
            local indLeft = (indicators == 1 or indicators == 3)
            local indRight = (indicators == 2 or indicators == 3)
            
            -- Wheels and Suspension (Inspired by SP GhostReplay)
            local wheelRotations = {}
            local suspensionCompressions = {}
            for i = 0, 3 do
                if GetVehicleWheelRotation then
                    wheelRotations[i] = GetVehicleWheelRotation(currentVehicle, i)
                end
                if GetVehicleWheelSuspensionCompression then
                    suspensionCompressions[i] = GetVehicleWheelSuspensionCompression(currentVehicle, i)
                end
            end

            -- Roof state for convertibles
            local roofState = nil
            if IsVehicleAConvertible(currentVehicle, false) then
                roofState = GetConvertibleRoofState(currentVehicle)
            end

            -- Lights state
            local _, low, high = GetVehicleLightsState(currentVehicle)
            local lightState = (high == 1) and 2 or (low == 1 and 1 or 0)

            -- For basic wheels animation and lights
            local brakes = IsControlPressed(0, 72) or IsControlPressed(0, 76) -- 72 is Brake, 76 is Handbrake
            
            table.insert(GhostRecorder.Frames, {
                time = now,
                pos = pos,
                rot = rot,
                velocity = velocity, -- Elite: Velocity capture
                steering = steeringAngle,
                braking = brakes,
                rpm = rpm,
                gear = gear,
                throttle = throttle,
                siren = siren,
                indL = indLeft,
                indR = indRight,
                lights = lightState,
                wheelRots = wheelRotations,
                suspension = suspensionCompressions,
                roof = roofState
            })

            -- Elite Stage 7: Delta Compression (Networking Optimization)
            if frameCount % 4 == 0 then
                local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
                
                -- Check for significant movement or state change
                local last = GhostRecorder.LastPacket
                local distMoved = last.pos and #(pos - last.pos) or 10.0
                local rotChanged = last.rot and #(rot - last.rot) or 10.0
                local stateChanged = (brakes ~= last.braking) or (siren ~= last.siren) or (indicators ~= last.indicators)

                if distMoved > 0.5 or rotChanged > 2.0 or stateChanged then
                    TriggerServerEvent("GhostReplay:Server:StreamPacket", trackName, {
                        model = GhostRecorder.ModelHash,
                        pos = pos,
                        rot = rot,
                        velocity = velocity,
                        time = now,
                        braking = brakes,
                        siren = siren,
                        indicators = indicators
                    })
                    GhostRecorder.LastPacket = { pos = pos, rot = rot, braking = brakes, siren = siren, indicators = indicators }
                end
            end
            
            frameCount = frameCount + 1
            Wait(Config.Timestep)
        end
    end)
    
    Utils.DebugPrint("Ghost recording started.")
end

function GhostRecorder.Stop()
    if not GhostRecorder.IsRecording then return end
    GhostRecorder.IsRecording = false
    Utils.DebugPrint("Ghost recording stopped. Saved " .. #GhostRecorder.Frames .. " frames.")
end

function GhostRecorder.GetRecordedData()
    return Utils.PackFrames(GhostRecorder.Frames)
end

-- Elite: Workflow Sync (v1.6)
AddEventHandler("GhostReplay:OnRaceStart", function(trackName)
    Utils.DebugPrint("Auto-sync: Starting recording for track " .. trackName)
    GhostRecorder.Start()
end)

AddEventHandler("GhostReplay:OnRaceFinish", function(trackName, timeMs, isDirty)
    if GhostRecorder.IsRecording then
        Utils.DebugPrint("Auto-sync: Stopping recording for track " .. trackName)
        GhostRecorder.Stop()
        
        -- Elite Stage 6: Multi-Car Bundling (Recursive Grid)
        if not isDirty then
            local participants = {}
            
            -- 1. Add any existing ghosts that were being chased
            for _, ghost in pairs(GhostPlayback.ActiveGhosts) do
                -- Only bundle "Replay" ghosts, not "Live" ghosts from other players
                if ghost.data and not ghost.isLive then
                    -- If the ghost already has multiple participants, add them all
                    if ghost.data.participants then
                        for _, p in ipairs(ghost.data.participants) do
                            table.insert(participants, p)
                        end
                    else
                        -- Legacy single-ghost data
                        table.insert(participants, {
                            model = ghost.data.model,
                            vehicleCosmetics = ghost.data.vehicleCosmetics,
                            pedAppearance = ghost.data.pedAppearance,
                            frames = ghost.data.frames
                        })
                    end
                end
            end
            
            -- 2. Add the player's new recording as the final participant
            table.insert(participants, {
                model = GhostRecorder.ModelHash,
                vehicleCosmetics = GhostRecorder.VehicleCosmetics,
                pedAppearance = GhostRecorder.PedAppearance,
                frames = GhostRecorder.GetRecordedData()
            })

            local data = {
                time = timeMs,
                participants = participants,
                isBundle = true -- Tag for playback logic
            }
            
            GhostRecorder.LastRunData = data -- Persist for instant replay
            table.insert(GhostRecorder.SessionHistory, 1, data) -- Add to head of history
            
            -- Limit history to 15 entries
            if #GhostRecorder.SessionHistory > 15 then
                table.remove(GhostRecorder.SessionHistory, 1)
            end

            TriggerServerEvent("GhostReplay:Server:SaveGhostData", trackName, data)
        end
    end
end)
