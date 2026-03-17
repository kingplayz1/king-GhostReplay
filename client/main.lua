-- Main Entry point for client side ghost logic

-- ── Helper: normalize server record → client-friendly track object ──
local function _NormalizeTrack(t)
    if not t then return nil end
    -- Server stores track_name; alias it to .name for client use
    t.name = t.name or t.track_name or "Unknown"
    -- Compatibility: extract checkpoint data from nested track_data if needed
    if not t.checkpoints and t.track_data then
        t.checkpoints  = t.track_data.checkpoints
        t.props        = t.track_data.props
        t.antiCutZones = t.track_data.antiCutZones
    end
    return t
end

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
    local hasFrames = ghostData and ghostData.frames and #ghostData.frames > 0
    local hasParticipants = ghostData and ghostData.participants and #ghostData.participants > 0

    if hasFrames or hasParticipants then
        Utils.DebugPrint("Received ghost data for track: " .. trackName .. ". Starting playback.")
        GhostPlayback.Play(ghostData, trackName)
    else
        Utils.DebugPrint("Received empty or invalid ghost data for track: " .. trackName)
    end
end)

-- Main hook into your race script
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

-- ── Sync all tracks on join ──
RegisterNetEvent("GhostReplay:Client:SyncAllTracks")
AddEventHandler("GhostReplay:Client:SyncAllTracks", function(tracks)
    loadedTracks = {}
    for _, t in ipairs(tracks) do
        table.insert(loadedTracks, _NormalizeTrack(t))
    end
    Utils.DebugPrint("Synchronized " .. #loadedTracks .. " tracks from server.")
    -- Push list to NUI
    SendNUIMessage({ action = "updateTrackList", tracks = loadedTracks })
end)

-- ── Sync newly saved track to all clients ──
RegisterNetEvent("GhostReplay:Client:SyncNewTrack")
AddEventHandler("GhostReplay:Client:SyncNewTrack", function(track)
    local t = _NormalizeTrack(track)
    table.insert(loadedTracks, t)
    Utils.DebugPrint("New live track synced: " .. t.name)
    -- Push full updated list to NUI
    SendNUIMessage({ action = "updateTrackList", tracks = loadedTracks })
end)

-- ── NUI: Request track list (on demand) ──
RegisterNUICallback("requestTrackList", function(data, cb)
    TriggerServerEvent("GhostReplay:Server:RequestAllTracks")
    cb("ok")
end)

-- ── NUI: Player picked a track — load it and start the race ──
RegisterNUICallback("selectTrackAndRace", function(data, cb)
    local trackId = data.trackId
    local found = nil
    for _, t in ipairs(loadedTracks) do
        if t.track_id == trackId then
            found = t
            break
        end
    end
    if not found then
        lib.notify({ description = "Track not found!", type = "error" })
        cb("not_found")
        return
    end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not vehicle or vehicle == 0 then
        lib.notify({ description = "You must be in a vehicle to start a race!", type = "error" })
        cb("no_vehicle")
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })

    TrackSystem.LoadTrack(found)
    TrackSystem.StartRace(vehicle)
    GhostRecorder.Start()

    lib.notify({ title = "Race Started", description = "🏁 " .. found.name, type = "success" })
    cb("ok")
end)

-- ── NUI: Load a specific track (no race, just load) ──
RegisterNUICallback("loadTrack", function(data, cb)
    local trackId = data.trackId
    for _, t in ipairs(loadedTracks) do
        if t.track_id == trackId then
            TrackSystem.LoadTrack(t)
            lib.notify({ description = "Track loaded: " .. t.name, type = "info" })
            cb("ok")
            return
        end
    end
    lib.notify({ description = "Track not found!", type = "error" })
    cb("not_found")
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
                if track.checkpoints and track.checkpoints[1] and track.checkpoints[1].midpoint then
                    local mp = track.checkpoints[1].midpoint
                    local slVec = vector3(mp.x, mp.y, mp.z)
                    local dist = #(coords - slVec)
                    
                    if dist < closestDist then
                        closestDist = dist
                        closestTrack = track
                    end
                end
            end
            
            if closestTrack and (not TrackSystem.CurrentTrack or TrackSystem.CurrentTrack.track_id ~= closestTrack.track_id) then
                TrackSystem.LoadTrack(closestTrack)
                Utils.DebugPrint("Activated nearby track: " .. closestTrack.name)
            elseif not closestTrack and TrackSystem.CurrentTrack then
                -- Move away from start line → unload track memory
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

-- ── In-world START / FINISH flag rendering ──
-- Shows 3D markers over the first (START) and last (FINISH) checkpoints
-- while a track is loaded. Uses DrawMarker type 4 (vertical flag cylinder).
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local track = TrackSystem.CurrentTrack
        if track and track.checkpoints and #track.checkpoints >= 2 then
            local cps = track.checkpoints
            local startCp  = cps[1]
            local finishCp = cps[#cps]

            -- START  → green glow
            if startCp and startCp.midpoint then
                local mp = startCp.midpoint
                DrawMarker(4, mp.x, mp.y, mp.z + 1.5, 0,0,0, 0,0,0, 1.5, 1.5, 3.0, 0, 220, 0, 180, false, true, 2, false, nil, nil, false)
                DrawMarker(27, mp.x, mp.y, mp.z, 0,0,0, 0,0,0, 10.0, 10.0, 0.3, 0, 220, 0, 80, false, false, 2, false, nil, nil, false)
            end

            -- FINISH → red glow
            if finishCp and finishCp.midpoint then
                local mp = finishCp.midpoint
                DrawMarker(4, mp.x, mp.y, mp.z + 1.5, 0,0,0, 0,0,0, 1.5, 1.5, 3.0, 220, 0, 0, 180, false, true, 2, false, nil, nil, false)
                DrawMarker(27, mp.x, mp.y, mp.z, 0,0,0, 0,0,0, 10.0, 10.0, 0.3, 220, 0, 0, 80, false, false, 2, false, nil, nil, false)
            end
        else
            Wait(500) -- no track loaded, sleep longer
        end
    end
end)
