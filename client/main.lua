-- Main Entry point for client side ghost logic

-- Test Commands (For debug/standalone usage)
RegisterCommand("ghostrecord", function(source, args)
    local action = args[1]
    if action == "START" then
        local trackName = args[2] or "test_track"
        
        -- Mock loading a track for simple testing
        TrackSystem.LoadTrack({
            name = trackName,
            type = "circuit",
            startLine = {
                left = vector3(0, 0, 0), -- Replace with actual coords if needed
                right = vector3(10, 0, 0)
            }
        })
        TrackSystem.StartRace(GetVehiclePedIsIn(PlayerPedId(), false))
        GhostRecorder.Start()
        
    elseif action == "STOP" then
        GhostRecorder.Stop()
        TrackSystem.EndRace(true)
        
        -- Automatically send to server as a test
        local testData = {
            model = GhostRecorder.ModelHash,
            vehicleCosmetics = GhostRecorder.VehicleCosmetics,
            pedAppearance = GhostRecorder.PedAppearance,
            frames = GhostRecorder.GetRecordedData()
        }
        -- Note: If data is very large, FiveM server events might truncate or fail. 
        -- In a real setup, compress data or send chunks. For best laps, 30s is fine.
        TriggerServerEvent("GhostReplay:Server:SaveGhostData", TrackSystem.CurrentTrack.name, testData)
    end
end, false)

RegisterCommand("ghostplay", function(source, args)
    local trackName = args[1] or "test_track"
    -- Request the ghost data from server for this track
    TriggerServerEvent("GhostReplay:Server:RequestGhostData", trackName)
end, false)

RegisterNetEvent("GhostReplay:Client:ReceiveGhostData")
AddEventHandler("GhostReplay:Client:ReceiveGhostData", function(trackName, ghostData)
    if ghostData and ghostData.frames and #ghostData.frames > 0 then
        Utils.DebugPrint("Received ghost data for track: " .. trackName .. ". Starting playback.")
        GhostPlayback.Play(ghostData, trackName)
    else
        Utils.DebugPrint("Received empty or invalid ghost data for track: " .. trackName)
    end
end)

-- Main hook into your race script
-- Modify these event names to match your own race resource (e.g. qb-racing, ox_core loops, etc.)
RegisterNetEvent("YourRaceScript:Client:OnRaceStart")
AddEventHandler("YourRaceScript:Client:OnRaceStart", function(trackInfo)
    TrackSystem.LoadTrack(trackInfo)
    TrackSystem.StartRace(GetVehiclePedIsIn(PlayerPedId(), false))
    GhostRecorder.Start()
end)

RegisterNetEvent("YourRaceScript:Client:OnRaceFinish")
AddEventHandler("YourRaceScript:Client:OnRaceFinish", function(completed)
    GhostRecorder.Stop()
    TrackSystem.EndRace(completed)
    
    if completed then
        local myData = {
            model = GhostRecorder.ModelHash,
            vehicleCosmetics = GhostRecorder.VehicleCosmetics,
            pedAppearance = GhostRecorder.PedAppearance,
            frames = GhostRecorder.GetRecordedData()
        }
        TriggerServerEvent("GhostReplay:Server:SaveGhostData", TrackSystem.CurrentTrack.name, myData)
    end
end)

local loadedTracks = {}

Citizen.CreateThread(function()
    -- Wait a bit for player to spawn, then request tracks
    Wait(2000)
    TriggerServerEvent("GhostReplay:Server:RequestAllTracks")
end)

RegisterNetEvent("GhostReplay:Client:SyncAllTracks")
AddEventHandler("GhostReplay:Client:SyncAllTracks", function(tracks)
    loadedTracks = tracks
    Utils.DebugPrint("Synchronized " .. #loadedTracks .. " tracks from server.")
end)

RegisterNetEvent("GhostReplay:Client:SyncNewTrack")
AddEventHandler("GhostReplay:Client:SyncNewTrack", function(track)
    table.insert(loadedTracks, track)
    Utils.DebugPrint("New live track synced: " .. track.name)
end)

-- Proximity Scanner Loop (Zero Impact)
-- Finds nearest track start line to activate TrackSystem listening
Citizen.CreateThread(function()
    while true do
        Wait(1000) -- Check once per second, very cheap
        
        if not TrackSystem.IsRacing and #loadedTracks > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            
            local closestTrack = nil
            local closestDist = Config.TrackLoadRadius
            
            for _, track in ipairs(loadedTracks) do
                if track.startLine and track.startLine.left then
                    local slVec = vector3(track.startLine.left.x, track.startLine.left.y, track.startLine.left.z)
                    local dist = #(coords - slVec)
                    
                    if dist < closestDist then
                        closestDist = dist
                        closestTrack = track
                    end
                end
            end
            
            if closestTrack and (not TrackSystem.CurrentTrack or TrackSystem.CurrentTrack.id ~= closestTrack.id) then
                TrackSystem.LoadTrack(closestTrack)
                Utils.DebugPrint("Activated nearby track: " .. closestTrack.name)
            elseif not closestTrack and TrackSystem.CurrentTrack then
                -- Move away from start line -> unload track memory
                TrackSystem.LoadTrack(nil)
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(250) -- Check line crossing at 4Hz to save client frames
        if TrackSystem.IsRacing then
            TrackSystem.CheckLapProgress()
        end
    end
end)
