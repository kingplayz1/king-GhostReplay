-- Records and maintains lap telemetry 

GhostRecorder = {}
GhostRecorder.Frames = {}
GhostRecorder.IsRecording = false
GhostRecorder.RecordStartTime = 0

local maxFrames = (Config.MaxRecordingTimeSeconds * 1000) / Config.Timestep

function GhostRecorder.Start()
    if GhostRecorder.IsRecording then return end
    
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end

    GhostRecorder.Frames = {}
    GhostRecorder.IsRecording = true
    GhostRecorder.RecordStartTime = GetGameTimer()
    
    local frameCount = 0
    
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
            local steeringAngle = GetVehicleSteeringAngle(currentVehicle)
            
            -- For basic wheels animation and lights
            local brakes = IsControlPressed(0, 72) or IsControlPressed(0, 76) -- 72 is Brake, 76 is Handbrake
            
            table.insert(GhostRecorder.Frames, {
                time = now,
                pos = pos,
                rot = rot,
                steering = steeringAngle,
                braking = brakes
            })
            
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
    return GhostRecorder.Frames
end
