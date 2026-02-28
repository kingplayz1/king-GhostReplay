-- Handles the dynamic creation of tracks in-game via commands

TrackBuilder = {}
TrackBuilder.IsBuilding = false
TrackBuilder.CurrentData = {
    name = "",
    startLine = {left = nil, right = nil},
    finishLine = {left = nil, right = nil},
    waypoints = {},
    antiCutZones = {}, -- Elite: { {points = {vector3, ...}} }
    currentZone = nil  -- Elite: Current zone being drawn
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
            
            -- Draw Waypoints, Corridors, and Zones
            for i, wp in ipairs(TrackBuilder.CurrentData.waypoints) do
                -- Draw Waypoint Marker
                DrawMarker(1, wp.x, wp.y, wp.z - 1.0, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 1.0, 255, 255, 0, 150, false, false, 2, false, nil, nil, false)
                
                -- Elite: Draw Corridor (Line to next waypoint)
                if i < #TrackBuilder.CurrentData.waypoints then
                    local nextWp = TrackBuilder.CurrentData.waypoints[i+1]
                    DrawLine(wp.x, wp.y, wp.z, nextWp.x, nextWp.y, nextWp.z, 255, 255, 255, 100)
                end
            end

            -- Elite: Draw Anti-Cut Zones
            for _, zone in ipairs(TrackBuilder.CurrentData.antiCutZones) do
                for j, p in ipairs(zone.points) do
                    local nextP = zone.points[j+1] or zone.points[1]
                    DrawLine(p.x, p.y, p.z, nextP.x, nextP.y, nextP.z, 255, 50, 50, 200)
                end
            end

            -- Elite: Draw current zone being drawn
            if TrackBuilder.CurrentData.currentZone then
                for j, p in ipairs(TrackBuilder.CurrentData.currentZone) do
                    local nextP = TrackBuilder.CurrentData.currentZone[j+1] or GetEntityCoords(PlayerPedId())
                    DrawLine(p.x, p.y, p.z, nextP.x, nextP.y, nextP.z, 255, 150, 0, 200)
                end
            end
            Wait(0)
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
    table.insert(TrackBuilder.CurrentData.waypoints, {
        x = GetEntityCoords(ped).x,
        y = GetEntityCoords(ped).y,
        z = GetEntityCoords(ped).z,
        min_speed = 0,
        allowed_width = 20.0
    })
end)

RegisterNetEvent("GhostReplay:Client:Builder:SetWaypointProps")
AddEventHandler("GhostReplay:Client:Builder:SetWaypointProps", function(speed, width)
    if not TrackBuilder.IsBuilding or #TrackBuilder.CurrentData.waypoints == 0 then return end
    local lastWp = TrackBuilder.CurrentData.waypoints[#TrackBuilder.CurrentData.waypoints]
    lastWp.min_speed = tonumber(speed) or lastWp.min_speed
    lastWp.allowed_width = tonumber(width) or lastWp.allowed_width
    lib.notify({description = string.format("Waypoint updated: Speed %d, Width %d", lastWp.min_speed, lastWp.allowed_width), type = 'info'})
end)

RegisterNetEvent("GhostReplay:Client:Builder:StartZone")
AddEventHandler("GhostReplay:Client:Builder:StartZone", function()
    if not TrackBuilder.IsBuilding then return end
    TrackBuilder.CurrentData.currentZone = {}
    lib.notify({description = 'Polygon creation started. Move and Add points.', type = 'info'})
end)

RegisterNetEvent("GhostReplay:Client:Builder:AddZonePoint")
AddEventHandler("GhostReplay:Client:Builder:AddZonePoint", function()
    if not TrackBuilder.IsBuilding or not TrackBuilder.CurrentData.currentZone then return end
    local coords = GetEntityCoords(PlayerPedId())
    table.insert(TrackBuilder.CurrentData.currentZone, {x = coords.x, y = coords.y, z = coords.z})
    lib.notify({description = 'Point added to polygon.', type = 'info'})
end)

RegisterNetEvent("GhostReplay:Client:Builder:CompleteZone")
AddEventHandler("GhostReplay:Client:Builder:CompleteZone", function()
    if not TrackBuilder.IsBuilding or not TrackBuilder.CurrentData.currentZone then return end
    if #TrackBuilder.CurrentData.currentZone < 3 then
        lib.notify({description = 'Need at least 3 points for a polygon!', type = 'error'})
        return
    end
    table.insert(TrackBuilder.CurrentData.antiCutZones, {points = TrackBuilder.CurrentData.currentZone})
    TrackBuilder.CurrentData.currentZone = nil
    lib.notify({description = 'Anti-Cut Zone finalized!', type = 'success'})
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
        waypoints = {},
        antiCutZones = TrackBuilder.CurrentData.antiCutZones -- Elite
    }
    
    for k,v in ipairs(TrackBuilder.CurrentData.waypoints) do
        table.insert(payload.waypoints, {
            x = v.x, 
            y = v.y, 
            z = v.z,
            min_speed = v.min_speed, -- Elite
            allowed_width = v.allowed_width -- Elite
        })
    end

    TriggerServerEvent("GhostReplay:Server:SaveTrack", payload)
    
    -- Elite: Analyze and notify
    local stats = Utils.AnalyzeTrack(payload)
    if stats then
        local msg = string.format("Track Analysis: %s | %.2fm | %d Turns", stats.class, stats.distance, stats.turns)
        lib.notify({title = 'Track Analysis', description = msg, type = 'info'})
    end

    TrackBuilder.IsBuilding = false
end)

-- Remove the old raw command as we now use /trackmenu
-- RegisterCommand("track", ...)
