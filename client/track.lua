-- Handles Track definitions, lap validation, and crossing checks

TrackSystem = {}
TrackSystem.CurrentTrack = nil
TrackSystem.LapStartTime = 0
TrackSystem.IsRacing = false
TrackSystem.Vehicle = nil
TrackSystem.CurrentWaypointIdx = 0
TrackSystem.LastPos = vector3(0,0,0)
TrackSystem.Sectors = {} -- { [1] = timeMs, [2] = timeMs, [3] = timeMs }
TrackSystem.IsLapDirty = false -- Elite: Invalidation flag
TrackSystem.PenaltyTime = 0 -- Elite: In ms
TrackSystem.Violations = 0 -- Elite: Count
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
    TrackSystem.Sectors = {}
    TrackSystem.IsLapDirty = false
    TrackSystem.PenaltyTime = 0
    TrackSystem.Violations = 0
    
    Utils.DebugPrint("Race started on track: " .. TrackSystem.CurrentTrack.name)
    TriggerEvent("GhostReplay:OnRaceStart", TrackSystem.CurrentTrack.name)
end

--- Elite: Handle a track violation
function TrackSystem.AddViolation(reason)
    if not TrackSystem.IsRacing then return end
    TrackSystem.Violations = TrackSystem.Violations + 1
    
    if TrackSystem.Violations <= 2 then
        TrackSystem.PenaltyTime = TrackSystem.PenaltyTime + 2000
        Utils.DebugPrint("Violation (" .. reason .. "): +2s Penalty")
        TriggerEvent("GhostReplay:Client:OnViolation", reason, false)
    else
        TrackSystem.IsLapDirty = true
        Utils.DebugPrint("Violation (" .. reason .. "): Lap INVALIDATED")
        TriggerEvent("GhostReplay:Client:OnViolation", reason, true)
    end
end

--- End racing logic (either manually or crossing finish line)
function TrackSystem.EndRace(wasCompleted)
    TrackSystem.IsRacing = false
    local rawTimeMs = GetGameTimer() - TrackSystem.LapStartTime
    local finalTimeMs = rawTimeMs + TrackSystem.PenaltyTime
    
    if wasCompleted then
        local msg = string.format("Race finished in %.2fs", finalTimeMs / 1000.0)
        if TrackSystem.IsLapDirty then
            msg = msg .. " (INVALIDATED)"
        elseif TrackSystem.PenaltyTime > 0 then
            msg = msg .. string.format(" (+%.1fs Penalty)", TrackSystem.PenaltyTime / 1000.0)
        end
        
        Utils.DebugPrint(msg)
        TriggerEvent("GhostReplay:OnRaceFinish", TrackSystem.CurrentTrack.name, finalTimeMs, TrackSystem.IsLapDirty)
        
        -- Only save to server if NOT dirty
        if not TrackSystem.IsLapDirty then
            TriggerServerEvent("GhostReplay:Server:SaveLap", TrackSystem.CurrentTrack.name, finalTimeMs)
        else
            lib.notify({description = 'Lap Invalidated - Not saved to leaderboard.', type = 'warning'})
        end
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
            
            -- Elite: Validation (Speed Check)
            if #(currentPos - targetVec) < 15.0 then
                local speedKmh = GetEntitySpeed(TrackSystem.Vehicle) * 3.6
                if targetWp.min_speed and speedKmh < targetWp.min_speed then
                    TrackSystem.AddViolation("SLOW SPEED")
                end

                TrackSystem.CurrentWaypointIdx = TrackSystem.CurrentWaypointIdx + 1
                
                -- Elite: Sector Detection
                local totalWps = #tData.waypoints
                local sectorSize = math.ceil(totalWps / 3)
                if TrackSystem.CurrentWaypointIdx % sectorSize == 0 or TrackSystem.CurrentWaypointIdx > totalWps then
                    local sectorNum = math.min(3, math.ceil(TrackSystem.CurrentWaypointIdx / sectorSize))
                    if not TrackSystem.Sectors[sectorNum] then
                        TrackSystem.Sectors[sectorNum] = GetGameTimer() - TrackSystem.LapStartTime
                        TriggerEvent("GhostReplay:Client:OnSectorComplete", sectorNum, TrackSystem.Sectors[sectorNum])
                    end
                end
                
                Utils.DebugPrint("Hit waypoint! Moving to " .. TrackSystem.CurrentWaypointIdx)
            end

            -- Elite: Validation (Corridor Check)
            -- Check if player is straying too far from the racing line between lastWP and targetWP
            if TrackSystem.CurrentWaypointIdx > 1 then
                local prevWp = tData.waypoints[TrackSystem.CurrentWaypointIdx - 1]
                local prevVec = vector3(prevWp.x, prevWp.y, prevWp.z)
                local deviation = Utils.GetDistanceToSegment(currentPos, prevVec, targetVec)
                local allowedWidth = targetWp.allowed_width or 20.0 -- 20m default width
                
                if deviation > allowedWidth then
                    TrackSystem.AddViolation("TRACK LIMITS")
                end
            end

            -- Elite: Validation (Anti-Cut Zones)
            if tData.antiCutZones then
                for _, zone in ipairs(tData.antiCutZones) do
                    if Utils.IsPointInPolygon(currentPos, zone.points) then
                        TrackSystem.AddViolation("ANTI-CUT ZONE")
                    end
                end
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

--- Elite: Synchronized Grid Countdown
RegisterNetEvent("GhostReplay:Client:StartCountdown")
AddEventHandler("GhostReplay:Client:StartCountdown", function(trackName)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return end

    -- Freeze and Start
    Citizen.CreateThread(function()
        TrackSystem.IsRacing = false -- Pre-start state
        FreezeEntityPosition(veh, true)
        
        local timer = 3
        while timer > 0 do
            TriggerEvent("GhostReplay:Client:OnCountdownTick", tostring(timer), {r=255, g=timer*80, b=0})
            PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
            Wait(1000)
            timer = timer - 1
        end

        TriggerEvent("GhostReplay:Client:OnCountdownTick", "GO!", {r=0, g=255, b=0})
        PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
        FreezeEntityPosition(veh, false)
        
        -- Elite Part 5: Resume all paused ghosts for synchronized start
        for id, ghost in pairs(GhostPlayback.ActiveGhosts) do
            if ghost.isPaused then
                GhostPlayback.TogglePause(id, false)
            end
        end

        -- Auto-start the race logic
        TrackSystem.StartRace(veh)
        Wait(1000)
    end)
end)
