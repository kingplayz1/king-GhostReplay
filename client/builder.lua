-- Handles the dynamic creation of tracks in-game via commands

TrackBuilder = {}
TrackBuilder.IsBuilding = false
TrackBuilder.CurrentData = {
    name = "",
    startLine = {left = nil, right = nil},
    finishLine = {left = nil, right = nil},
    waypoints = {}
}

-- Render loop for visual feedback
Citizen.CreateThread(function()
    while true do
        if TrackBuilder.IsBuilding then
            -- Draw Start Line
            if TrackBuilder.CurrentData.startLine.left and TrackBuilder.CurrentData.startLine.right then
                DrawLine(TrackBuilder.CurrentData.startLine.left.x, TrackBuilder.CurrentData.startLine.left.y, TrackBuilder.CurrentData.startLine.left.z,
                         TrackBuilder.CurrentData.startLine.right.x, TrackBuilder.CurrentData.startLine.right.y, TrackBuilder.CurrentData.startLine.right.z,
                         0, 255, 0, 200)
            end
            
            -- Draw Finish Line
            if TrackBuilder.CurrentData.finishLine.left and TrackBuilder.CurrentData.finishLine.right then
                DrawLine(TrackBuilder.CurrentData.finishLine.left.x, TrackBuilder.CurrentData.finishLine.left.y, TrackBuilder.CurrentData.finishLine.left.z,
                         TrackBuilder.CurrentData.finishLine.right.x, TrackBuilder.CurrentData.finishLine.right.y, TrackBuilder.CurrentData.finishLine.right.z,
                         255, 0, 0, 200)
            end
            
            -- Draw Waypoints
            for i, wp in ipairs(TrackBuilder.CurrentData.waypoints) do
                DrawMarker(1, wp.x, wp.y, wp.z - 1.0, 0, 0, 0, 0, 0, 0, 5.0, 5.0, 1.0, 255, 255, 0, 100, false, false, 2, false, nil, nil, false)
            end
            Wait(0) -- Draw natives must render every frame, thus Wait(0) when active
        else
            Wait(1000) -- Sleep when not building to save 100% of ms performance
        end
    end
end)

RegisterNetEvent("GhostReplay:Client:Builder:Start")
AddEventHandler("GhostReplay:Client:Builder:Start", function()
    TrackBuilder.IsBuilding = true
    -- Reset data
    TrackBuilder.CurrentData = {
        name = "",
        startLine = {left = nil, right = nil},
        finishLine = {left = nil, right = nil},
        waypoints = {}
    }
end)

RegisterNetEvent("GhostReplay:Client:Builder:Cancel")
AddEventHandler("GhostReplay:Client:Builder:Cancel", function()
    TrackBuilder.IsBuilding = false
end)

RegisterNetEvent("GhostReplay:Client:Builder:SetStart")
AddEventHandler("GhostReplay:Client:Builder:SetStart", function(side)
    if not TrackBuilder.IsBuilding then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if side == "left" then
        TrackBuilder.CurrentData.startLine.left = coords
    elseif side == "right" then
        TrackBuilder.CurrentData.startLine.right = coords
    end
end)

RegisterNetEvent("GhostReplay:Client:Builder:SetFinish")
AddEventHandler("GhostReplay:Client:Builder:SetFinish", function(side)
    if not TrackBuilder.IsBuilding then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if side == "left" then
        TrackBuilder.CurrentData.finishLine.left = coords
    elseif side == "right" then
        TrackBuilder.CurrentData.finishLine.right = coords
    end
end)

RegisterNetEvent("GhostReplay:Client:Builder:AddWaypoint")
AddEventHandler("GhostReplay:Client:Builder:AddWaypoint", function()
    if not TrackBuilder.IsBuilding then return end
    local ped = PlayerPedId()
    table.insert(TrackBuilder.CurrentData.waypoints, GetEntityCoords(ped))
end)

RegisterNetEvent("GhostReplay:Client:Builder:Save")
AddEventHandler("GhostReplay:Client:Builder:Save", function(trackName)
    if not TrackBuilder.IsBuilding then return end
    if not trackName or trackName == "" then return end
    
    -- Validate
    if not TrackBuilder.CurrentData.startLine.left or not TrackBuilder.CurrentData.startLine.right then
        lib.notify({title = 'Track Builder', description = 'Missing start line points!', type = 'error'})
        return
    end
    if not TrackBuilder.CurrentData.finishLine.left or not TrackBuilder.CurrentData.finishLine.right then
        lib.notify({title = 'Track Builder', description = 'Missing finish line points!', type = 'error'})
        return
    end
    
    TrackBuilder.CurrentData.name = trackName
    
    -- Serialize vector3 to tables for json crossing network
    local payload = {
        name = trackName,
        startLine = {
            left = {x=TrackBuilder.CurrentData.startLine.left.x, y=TrackBuilder.CurrentData.startLine.left.y, z=TrackBuilder.CurrentData.startLine.left.z},
            right = {x=TrackBuilder.CurrentData.startLine.right.x, y=TrackBuilder.CurrentData.startLine.right.y, z=TrackBuilder.CurrentData.startLine.right.z}
        },
        finishLine = {
            left = {x=TrackBuilder.CurrentData.finishLine.left.x, y=TrackBuilder.CurrentData.finishLine.left.y, z=TrackBuilder.CurrentData.finishLine.left.z},
            right = {x=TrackBuilder.CurrentData.finishLine.right.x, y=TrackBuilder.CurrentData.finishLine.right.y, z=TrackBuilder.CurrentData.finishLine.right.z}
        },
        waypoints = {}
    }
    
    for k,v in ipairs(TrackBuilder.CurrentData.waypoints) do
        table.insert(payload.waypoints, {x=v.x, y=v.y, z=v.z})
    end

    TriggerServerEvent("GhostReplay:Server:SaveTrack", payload)
    TrackBuilder.IsBuilding = false
    lib.notify({title = 'Track Builder', description = 'Sending track to server...', type = 'success'})
end)

-- Remove the old raw command as we now use /trackmenu
-- RegisterCommand("track", ...)
