-- GhostReplay Elite: NUI Controller
-- Replaces legacy ox_lib menus with full custom HTML/JS Dashboard

local isUIPaused = false

function OpenMainMenu()
    local track = TrackSystem.CurrentTrack
    local trackName = track and track.name or "No Track Loaded"
    local trackType = track and (track.trackType or "Technical") or "---"
    
    -- Telemetry/Stats
    local pbTime = "No PB set"
    local wrTime = "No WR set"
    
    local lastRunStr = nil
    if GhostRecorder.LastRunData then
        lastRunStr = string.format("%.2fs", GhostRecorder.LastRunData.time / 1000)
    end

    SendNUIMessage({
        action = "open",
        data = {
            trackName = trackName,
            trackType = trackName ~= "No Track Loaded" and trackType or "---",
            pbTime = pbTime,
            wrTime = wrTime,
            lastRun = GhostRecorder.LastRunData and { timeStr = lastRunStr } or nil,
            builderState = BuilderStateMachine.CurrentState
        },
        sessionHistory = GhostRecorder.SessionHistory
    })
    
    SetNuiFocus(true, true)
end

-- NUI CALLBACKS: CORE
RegisterNUICallback("closeUI", function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb("ok")
end)

RegisterNUICallback("startQuickRace", function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not vehicle or vehicle == 0 then
        lib.notify({description = 'You must be in a vehicle!', type = 'error'})
        cb("ok")
        return
    end
    
    if not TrackSystem.CurrentTrack then
        TrackSystem.LoadTrack({
            name = "Quick Race",
            type = "Technical",
            startLine = { left = vector3(0,0,0), right = vector3(10,0,0) }
        })
    end
    
    TrackSystem.StartRace(vehicle)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb("ok")
end)

RegisterNUICallback("replayLastRun", function(data, cb)
    local data = GhostRecorder.LastRunData
    if data then
        local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
        data.type = "session"
        data.name = "Last Run"
        TriggerEvent("GhostReplay:Client:ReceiveGhostData", trackName, data)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb("ok")
end)

RegisterNUICallback("playSessionLap", function(data, cb)
    local lapData = GhostRecorder.SessionHistory[data.index + 1]
    if lapData then
        local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
        lapData.type = "session"
        lapData.name = "Session Lap"
        TriggerEvent("GhostReplay:Client:ReceiveGhostData", trackName, lapData)
    end
    cb("ok")
end)

RegisterNUICallback("startChase", function(data, cb)
    local lapData = GhostRecorder.SessionHistory[data.index + 1]
    if lapData then
        local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
        lapData.type = "session"
        lapData.name = "Ghost Lead"
        
        GhostPlayback.Play(lapData, trackName, false)
        TriggerServerEvent("GhostReplay:Server:RequestGridStart", trackName)
        
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "close" })
    end
    cb("ok")
end)

-- NUI CALLBACKS: BUILDER
RegisterNUICallback("buildAction", function(data, cb)
    if data.type == "setStart" then
        TriggerEvent("GhostReplay:Client:Builder:SetStart", data.side)
    elseif data.type == "setFinish" then
        TriggerEvent("GhostReplay:Client:Builder:SetFinish", data.side)
    elseif data.type == "addWaypoint" then
        TriggerEvent("GhostReplay:Client:Builder:AddWaypoint")
        -- Note: Custom Waypoint props dialog could be added here in NUI if needed
    elseif data.type == "startZone" then
        TriggerEvent("GhostReplay:Client:Builder:StartZone")
    elseif data.type == "autoLink" then
        -- Find nearest prop and set line
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local nearest = nil
        local minDist = 5.0
        
        for _, p in ipairs(PropBuilder.TrackProps) do
            local dist = #(pos - p.data.coords)
            if dist < minDist then
                minDist = dist
                nearest = p
            end
        end
        
        if nearest then
            local rot = nearest.data.rotation
            local forward = Utils.RotationToDirection(rot)
            local right = vector3(-forward.y, forward.x, 0.0)
            local halfWidth = 5.0 -- 10m total width arch
            
            local leftPoint = nearest.data.coords + (right * -halfWidth)
            local rightPoint = nearest.data.coords + (right * halfWidth)
            
            if data.side == "start" then
                TrackBuilder.CurrentData.startLine.left = leftPoint
                TrackBuilder.CurrentData.startLine.right = rightPoint
            else
                TrackBuilder.CurrentData.finishLine.left = leftPoint
                TrackBuilder.CurrentData.finishLine.right = rightPoint
            end
            lib.notify({description = "Linked " .. data.side .. " to nearest arch!", type = "success"})
        else
            lib.notify({description = "No prop found within 5m!", type = "error"})
        end
    elseif data.type == "save" then
        -- Placeholder: In v2.4 we'll add the track naming input to NUI
        TriggerEvent("GhostReplay:Client:Builder:Save", "Custom Track " .. math.random(100, 999))
    elseif data.type == "cancel" then
        TriggerEvent("GhostReplay:Client:Builder:Cancel")
    end
    cb("ok")
end)

-- NUI CALLBACKS: SETTINGS
RegisterNUICallback("updateSetting", function(data, cb)
    if data.id == "set-hologram" then
        GhostPlayback.Settings.HologramMode = data.value
    elseif data.id == "set-camera" then
        GhostCamera.Toggle()
    elseif data.id == "set-hud" then
        GhostHUD.Visible = data.value
    elseif data.id == "set-labels" then
        GhostHUD.LabelsVisible = data.value
    end
    cb("ok")
end)

RegisterNUICallback("requestGridStart", function(data, cb)
    local trackName = (TrackSystem and TrackSystem.CurrentTrack and TrackSystem.CurrentTrack.name) or "test_track"
    TriggerServerEvent("GhostReplay:Server:RequestGridStart", trackName)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb("ok")
end)

RegisterNUICallback("clearGhosts", function(data, cb)
    GhostPlayback.StopAll()
    cb("ok")
end)

RegisterNUICallback("setBuilderState", function(data, cb)
    if data.state then
        BuilderStateMachine.SetState(data.state)
    end
    cb("ok")
end)

RegisterNUICallback("selectProp", function(data, cb)
    if data.model then
        -- Close UI and start placement via state machine
        BuilderStateMachine.SetState("PLACEMENT")
        BuilderStateMachine.SetSubState("PLACEMENT", "PREVIEW")
        PropBuilder.Start(data.model)
    end
    cb("ok")
end)

-- COMMAND
RegisterCommand("trackmenu", function()
    OpenMainMenu()
end, false)

-- HUD Integration
Citizen.CreateThread(function()
    while true do
        if GhostRecorder.IsRecording then
            local time = GetGameTimer() - GhostRecorder.RecordStartTime
            local timeStr = string.format("%.2f", time / 1000)
            -- We could send this to NUI to show a live timer
            -- SendNUIMessage({ action = "updateTimer", time = timeStr })
        end
        Wait(100)
    end
end)
