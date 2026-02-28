-- Handles Track definitions, lap validation, and crossing checks

TrackSystem = {}
TrackSystem.CurrentTrack = nil
TrackSystem.LapStartTime = 0
TrackSystem.IsRacing = false
TrackSystem.Vehicle = nil
TrackSystem.CurrentWaypointIdx = 0
TrackSystem.LastPos = vector3(0,0,0)
TrackSystem.IsRacing = false
TrackSystem.Vehicle = nil

--- Defines the current track parameters
--- Defines the current track parameters
-- `trackData` should contain: name, type (point/circuit), startLine (left/right vectors), checkpoints(optional)
function TrackSystem.LoadTrack(trackData)
    TrackSystem.CurrentTrack = trackData
    TrackSystem.IsRacing = false
    if trackData then
        Utils.DebugPrint("Track loaded: " .. tostring(trackData.name))
    else
        Utils.DebugPrint("Track unloaded.")
    end
end

--- Start racing logic
function TrackSystem.StartRace(vehicle)
    if not TrackSystem.CurrentTrack then
        return
    end
    
    TrackSystem.Vehicle = vehicle
    TrackSystem.IsRacing = true
    TrackSystem.LapStartTime = GetGameTimer()
    TrackSystem.LastPos = GetEntityCoords(vehicle)
    TrackSystem.CurrentWaypointIdx = 1
    
    Utils.DebugPrint("Race started on track: " .. TrackSystem.CurrentTrack.name)
    TriggerEvent("GhostReplay:OnRaceStart", TrackSystem.CurrentTrack.name)
end

--- End racing logic (either manually or crossing finish line)
function TrackSystem.EndRace(wasCompleted)
    TrackSystem.IsRacing = false
    local lapTimeMs = GetGameTimer() - TrackSystem.LapStartTime
    
    if wasCompleted then
        Utils.DebugPrint("Race finished in " .. lapTimeMs .. "ms")
        TriggerEvent("GhostReplay:OnRaceFinish", TrackSystem.CurrentTrack.name, lapTimeMs)
        TriggerServerEvent("GhostReplay:Server:SaveLap", TrackSystem.CurrentTrack.name, lapTimeMs)
    else
        Utils.DebugPrint("Race Aborted.")
    end
end

--- Call this in a client thread (optimally 100-250ms for performance, or frame-by-frame if accuracy is critical)
function TrackSystem.CheckLapProgress()
    if not TrackSystem.IsRacing or not TrackSystem.CurrentTrack then return end
    if not DoesEntityExist(TrackSystem.Vehicle) then return end

    local currentPos = GetEntityCoords(TrackSystem.Vehicle)
    local tData = TrackSystem.CurrentTrack

    -- Waypoint checking logic
    if tData.waypoints and #tData.waypoints > 0 then
        -- Are we still collecting waypoints?
        if TrackSystem.CurrentWaypointIdx <= #tData.waypoints then
            local targetWp = tData.waypoints[TrackSystem.CurrentWaypointIdx]
            local targetVec = vector3(targetWp.x, targetWp.y, targetWp.z)
            
            -- Simple radius check for waypoint (e.g. 15 meters)
            if #(currentPos - targetVec) < 15.0 then
                TrackSystem.CurrentWaypointIdx = TrackSystem.CurrentWaypointIdx + 1
                Utils.DebugPrint("Hit waypoint! Moving to " .. TrackSystem.CurrentWaypointIdx)
            end
            
            TrackSystem.LastPos = currentPos
            return -- Exit early, we must collect all waypoints before finishing
        end
    end

    -- If we get here, either no waypoints exist or all were collected
    -- Check Finish Line (Uses directional check to prevent cheating)
    if tData.finishLine and tData.finishLine.left then
        local flLeft = vector3(tData.finishLine.left.x, tData.finishLine.left.y, tData.finishLine.left.z)
        local flRight = vector3(tData.finishLine.right.x, tData.finishLine.right.y, tData.finishLine.right.z)
        
        -- Proximity check first to save math
        local distToFinish = #(currentPos - flLeft)
        if distToFinish < 100.0 then
            local crossed, direction = Utils.CrossedLine(TrackSystem.LastPos, currentPos, flLeft, flRight)
            if crossed and direction > 0 then
                Utils.DebugPrint("Finish line crossed correctly!")
                TrackSystem.EndRace(true)
            elseif crossed and direction <= 0 then
                Utils.DebugPrint("Crossed finish backwards! Ignoring.")
            end
        end
    else
        -- Fallback to Start Line if no explicit finish line defined (Circuit loop)
        local slLeft = vector3(tData.startLine.left.x, tData.startLine.left.y, tData.startLine.left.z)
        local slRight = vector3(tData.startLine.right.x, tData.startLine.right.y, tData.startLine.right.z)
        
        local distToStart = #(currentPos - slLeft)
        if distToStart < 100.0 then
            local crossed, direction = Utils.CrossedLine(TrackSystem.LastPos, currentPos, slLeft, slRight)
            if crossed and direction > 0 then
                Utils.DebugPrint("Start line crossed correctly! (Circuit lap completed)")
                TrackSystem.EndRace(true)
            end
        end
    end
    
    TrackSystem.LastPos = currentPos
end
