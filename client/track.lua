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
TrackSystem.ActiveProps = {} -- Elite: { [index] = entity }
TrackSystem.IsRacing = false
TrackSystem.Vehicle = nil

function TrackSystem.LoadTrack(trackData)
    TrackSystem.CleanupProps()
    TrackSystem.CurrentTrack = trackData
    TrackSystem.IsRacing = false
    if trackData then
        Utils.DebugPrint("Track loaded: " .. tostring(trackData.name))
        TrackSystem.StartPropStreamer()
        TrackSystem.StartGateStreamer() -- New streamer for gate props
    else
        Utils.DebugPrint("Track unloaded.")
    end
end

function TrackSystem.CleanupProps()
    for _, entity in pairs(TrackSystem.ActiveProps) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    TrackSystem.ActiveProps = {}
end

function TrackSystem.StartPropStreamer()
    Citizen.CreateThread(function()
        local tData = TrackSystem.CurrentTrack
        if not tData or not tData.props then return end

        while TrackSystem.CurrentTrack == tData do
            local playerCoords = GetEntityCoords(PlayerPedId())
            for i, p in ipairs(tData.props) do
                local propCoords = vector3(p.coords.x, p.coords.y, p.coords.z)
                local dist = #(playerCoords - propCoords)
                if dist < 200.0 then
                    if not TrackSystem.ActiveProps["p"..i] then
                        local hash = GetHashKey(p.model)
                        lib.requestModel(hash)
                        local obj = CreateObject(hash, p.coords.x, p.coords.y, p.coords.z, true, true, false)
                        SetEntityRotation(obj, p.rotation.x, p.rotation.y, p.rotation.z, 2, true)
                        FreezeEntityPosition(obj, true)
                        TrackSystem.ActiveProps["p"..i] = obj
                    end
                else
                    if TrackSystem.ActiveProps["p"..i] then
                        DeleteEntity(TrackSystem.ActiveProps["p"..i])
                        TrackSystem.ActiveProps["p"..i] = nil
                    end
                end
            end
            Wait(1000)
        end
    end)
end

function TrackSystem.StartGateStreamer()
    Citizen.CreateThread(function()
        local tData = TrackSystem.CurrentTrack
        if not tData or not tData.checkpoints then return end

        while TrackSystem.CurrentTrack == tData do
            local playerCoords = GetEntityCoords(PlayerPedId())
            for i, cp in ipairs(tData.checkpoints) do
                local mid = vector3(cp.midpoint.x, cp.midpoint.y, cp.midpoint.z)
                local dist = #(playerCoords - mid)
                
                -- Rule: Props streamed only within 300 meters
                if dist < 300.0 then
                    if not TrackSystem.ActiveProps["g_l"..i] then
                        local style = TrackProps.GateStyles[cp.styleIndex]
                        local lHash, rHash = GetHashKey(style.left), GetHashKey(style.right)
                        lib.requestModel(lHash); lib.requestModel(rHash)

                        local lObj = CreateObject(lHash, cp.left.x, cp.left.y, cp.left.z, true, true, false)
                        local rObj = CreateObject(rHash, cp.right.x, cp.right.y, cp.right.z, true, true, false)
                        
                        SetEntityRotation(lObj, 0.0, 0.0, cp.rotation, 2, true)
                        SetEntityRotation(rObj, 0.0, 0.0, cp.rotation, 2, true)
                        FreezeEntityPosition(lObj, true); FreezeEntityPosition(rObj, true)
                        
                        TrackSystem.ActiveProps["g_l"..i] = lObj
                        TrackSystem.ActiveProps["g_r"..i] = rObj
                    end
                else
                    if TrackSystem.ActiveProps["g_l"..i] then
                        DeleteEntity(TrackSystem.ActiveProps["g_l"..i]); DeleteEntity(TrackSystem.ActiveProps["g_r"..i])
                        TrackSystem.ActiveProps["g_l"..i] = nil; TrackSystem.ActiveProps["g_r"..i] = nil
                    end
                end
            end
            Wait(1000)
        end
    end)
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
    local cps = tData.checkpoints

    if cps and #cps > 0 then
        -- Check current gate
        if TrackSystem.CurrentWaypointIdx <= #cps then
            local cp = cps[TrackSystem.CurrentWaypointIdx]
            local left = vector3(cp.left.x, cp.left.y, cp.left.z)
            local right = vector3(cp.right.x, cp.right.y, cp.right.z)
            
            -- Proximity check (30m)
            local mid = (left + right) / 2.0
            if #(currentPos - mid) < 30.0 then
                local crossed, direction = Utils.CrossedLine(TrackSystem.LastPos, currentPos, left, right)
                if crossed and direction > 0 then
                    -- Hit!
                    TrackSystem.CurrentWaypointIdx = TrackSystem.CurrentWaypointIdx + 1
                    
                    -- Sector calculation (1, 2, 3)
                    local total = #cps
                    local sector = (TrackSystem.CurrentWaypointIdx-1 <= total/3 and 1) or (TrackSystem.CurrentWaypointIdx-1 <= 2*total/3 and 2) or 3
                    if not TrackSystem.Sectors[sector] then
                        TrackSystem.Sectors[sector] = GetGameTimer() - TrackSystem.LapStartTime
                        TriggerEvent("GhostReplay:Client:OnSectorComplete", sector, TrackSystem.Sectors[sector])
                    end

                    -- Play Sound
                    PlaySoundFrontend(-1, "RACE_PLACE", "HUD_FRONTEND_CUSTOM_SOUND_01", false)
                    Utils.DebugPrint("Gate #" .. (TrackSystem.CurrentWaypointIdx-1) .. " cleared!")

                    -- Check if it was FINISH
                    if cp.type == "FINISH" or TrackSystem.CurrentWaypointIdx > #cps then
                        TrackSystem.EndRace(true)
                    end
                end
            end
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
