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
            builderState = BuilderFSM and BuilderFSM.Current or "IDLE",
            isBuilderActive = BuilderFSM and (BuilderFSM.Current ~= BuilderFSM.State.IDLE) or false
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
    if data.type == "addWaypoint" then
        BuilderFSM.SetState(BuilderFSM.State.CHECKPOINT_PLACEMENT)
        -- Note: Custom Waypoint props dialog could be added here in NUI if needed
    elseif data.type == "startZone" then
        TriggerEvent("GhostReplay:Client:Builder:StartZone")
    elseif data.type == "autoLink" then
        -- Find nearest prop and set line (v2 version)
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local nearest = nil
        local minDist = 8.0
        
        local allProps = BuilderPropsV2.GetAll()
        for _, p in ipairs(allProps) do
            local dist = #(pos - p.coords)
            if dist < minDist then
                minDist = dist
                nearest = p
            end
        end
        
        -- Note: v2 handles start/finish via the START_FINISH_PLACE state loop
        -- This auto-link helper will notify the user to use the placement tools instead
        if nearest then
            lib.notify({description = "Prop found! Use placement tools (E / SHIFT+E) to link.", type = "info"})
        else
            lib.notify({description = "No prop found within 8m!", type = "error"})
        end
    elseif data.type == "save" then
        BuilderCore.PromptSave()
    elseif data.type == "exitBuilder" then
        BuilderFSM.SetState(BuilderFSM.State.EXIT_BUILDER)
    elseif data.type == "undo" then
        BuilderUndo.Undo()
    elseif data.type == "redo" then
        BuilderUndo.Redo()
    elseif data.type == "deleteSelected" then
        -- Delete the currently selected/previewed prop
        if BuilderPropsV2 and BuilderPropsV2.SelectedProp then
            BuilderPropsV2._DeleteProp(BuilderPropsV2.SelectedProp.entity)
        end
    elseif data.type == "analyze" then
        local session = BuilderCore and BuilderCore.GetSession()
        if session then
            local meta = BuilderAnalysis.Analyze(session)
            SendNUIMessage({ action = "trackAnalysis", meta = meta })
            if meta then
                lib.notify({ description = BuilderAnalysis.FormatSummary(meta), type = "info" })
            end
        end
    elseif data.type == "cancel" then
        -- Legacy compat
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

-- ── v2 FSM state change from NUI mode chips ──
RegisterNUICallback("setBuilderFSM", function(data, cb)
    if data.state and BuilderFSM then
        BuilderFSM.SetState(data.state)
    end
    cb("ok")
end)

-- ── Legacy compat (old setBuilderState) ──
RegisterNUICallback("setBuilderState", function(data, cb)
    if data.state and BuilderFSM then
        BuilderFSM.SetState(data.state)
    end
    cb("ok")
end)

-- ── Toggle builder mode on/off from NUI button ──
RegisterNUICallback("toggleBuilderMode", function(data, cb)
    if not BuilderFSM then cb("ok") return end
    if BuilderFSM.Current == BuilderFSM.State.IDLE then
        BuilderFSM.SetState(BuilderFSM.State.ENTER_BUILDER)
    else
        BuilderFSM.SetState(BuilderFSM.State.EXIT_BUILDER)
    end
    cb("ok")
end)

-- ── Prop selected from palette ──
RegisterNUICallback("selectProp", function(data, cb)
    if data.model and BuilderFSM then
        -- Switch to PROP_PREVIEW state and set the selected model
        if BuilderFSM.Current == BuilderFSM.State.IDLE then
            BuilderFSM.SetState(BuilderFSM.State.ENTER_BUILDER)
        end
        BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
        -- Set current model on the prop engine
        if BuilderPropsV2 then
            -- Find category and index for this model
            for catIdx, cat in ipairs(TrackPropCategoryOrder) do
                local list = TrackProps[cat] or {}
                for propIdx, model in ipairs(list) do
                    if model == data.model then
                        BuilderPropsV2.CategoryIndex = catIdx
                        BuilderPropsV2.PropIndex     = propIdx
                        BuilderPropsV2._SpawnGhost()
                        break
                    end
                end
            end
        end
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "minimizeBuilder" })
    end
    cb("ok")
end)

-- ── Runtime builder settings from NUI toggles ──
RegisterNUICallback("builderSetting", function(data, cb)
    if not BuilderPropsV2 then cb("ok") return end
    if data.key == "snapGrid" then
        BuilderPropsV2.SnapGrid = (data.value == true)
    elseif data.key == "snapMagnetic" then
        -- Toggle magnetic snap (used in props.lua _MagneticSnap)
        BuilderPropsV2._magneticEnabled = (data.value == true)
    elseif data.key == "snapGround" then
        BuilderPropsV2.DirectionSnap = (data.value == true)
    elseif data.key == "gridSize" and type(data.value) == "number" then
        BuilderPropsV2.GridSize = data.value
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
