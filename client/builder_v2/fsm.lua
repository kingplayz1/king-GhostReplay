-- ============================================================
-- GhostReplay Builder v2: Full 12-State Finite State Machine
-- Manages all builder mode transitions with guard logic
-- ============================================================

BuilderFSM = {
    Current = "IDLE",
    Previous = "IDLE",
    _listeners = {},
}

-- ── Enum ──
BuilderFSM.State = {
    IDLE                  = "IDLE",
    ENTER_BUILDER         = "ENTER_BUILDER",
    PROP_PREVIEW          = "PROP_PREVIEW",
    PROP_PLACEMENT        = "PROP_PLACEMENT",
    CHECKPOINT_PLACEMENT  = "CHECKPOINT_PLACEMENT",
    PROP_EDIT_MODE        = "PROP_EDIT_MODE",
    DELETE_MODE           = "DELETE_MODE",
    PREVIEW_TRACK         = "PREVIEW_TRACK",
    SIMULATION_MODE       = "SIMULATION_MODE",
    SAVE_TRACK            = "SAVE_TRACK",
    EXIT_BUILDER          = "EXIT_BUILDER",
}

-- ── Legal Transition Table ──
-- Keys = current state. Values = set of allowed next states.
local _transitions = {
    IDLE                  = { ENTER_BUILDER = true },
    ENTER_BUILDER         = { PROP_PREVIEW = true, CHECKPOINT_PLACEMENT = true, EXIT_BUILDER = true },
    PROP_PREVIEW          = { PROP_PLACEMENT = true, CHECKPOINT_PLACEMENT = true, PROP_EDIT_MODE = true, DELETE_MODE = true, PREVIEW_TRACK = true, SAVE_TRACK = true, EXIT_BUILDER = true },
    PROP_PLACEMENT        = { PROP_PREVIEW = true, PROP_EDIT_MODE = true, EXIT_BUILDER = true },
    CHECKPOINT_PLACEMENT  = { PROP_PREVIEW = true, PREVIEW_TRACK = true, EXIT_BUILDER = true },
    PROP_EDIT_MODE        = { PROP_PREVIEW = true, DELETE_MODE = true, EXIT_BUILDER = true },
    DELETE_MODE           = { PROP_PREVIEW = true, EXIT_BUILDER = true },
    PREVIEW_TRACK         = { PROP_PREVIEW = true, SIMULATION_MODE = true, SAVE_TRACK = true, EXIT_BUILDER = true },
    SIMULATION_MODE       = { PROP_PREVIEW = true, SAVE_TRACK = true, EXIT_BUILDER = true },
    SAVE_TRACK            = { EXIT_BUILDER = true },
    EXIT_BUILDER          = { IDLE = true },
}

-- ── Guard Rules ──
local function _CheckGuards(newState, data)
    if newState == BuilderFSM.State.SIMULATION_MODE or newState == BuilderFSM.State.PREVIEW_TRACK then
        local cps = BuilderCheckpoints and BuilderCheckpoints.GetAll() or {}
        local hasStart, hasFinish = false, false
        for _, cp in ipairs(cps) do
            if cp.type == "START" then hasStart = true end
            if cp.type == "FINISH" then hasFinish = true end
        end
        if not hasStart or not hasFinish then
            lib.notify({ title = "Builder", description = "Track needs a START and FINISH checkpoint!", type = "error" })
            return false
        end
    end

    if newState == BuilderFSM.State.SAVE_TRACK then
        local cps = BuilderCheckpoints and BuilderCheckpoints.GetAll() or {}
        if #cps < 2 then
            lib.notify({ title = "Builder", description = "Need at least 2 checkpoints to save!", type = "error" })
            return false
        end
    end

    if newState == BuilderFSM.State.DELETE_MODE then
        local props = BuilderPropsV2 and BuilderPropsV2.GetAll() or {}
        local cps   = BuilderCheckpoints and BuilderCheckpoints.GetAll() or {}
        if #props == 0 and #cps == 0 then
            lib.notify({ description = "Nothing to delete yet.", type = "warning" })
            return false
        end
    end

    -- Block everything except EXIT while saving
    if BuilderFSM.Current == BuilderFSM.State.SAVE_TRACK and newState ~= BuilderFSM.State.EXIT_BUILDER then
        lib.notify({ description = "Track is saving, please wait...", type = "warning" })
        return false
    end

    return true
end

-- ── Core Transition ──
function BuilderFSM.SetState(newState)
    if newState == BuilderFSM.Current then return true end

    -- Emergency override: IDLE and EXIT always allowed
    local isEmergency = (newState == BuilderFSM.State.IDLE or newState == BuilderFSM.State.EXIT_BUILDER)

    if not isEmergency then
        -- Check transition table
        local allowed = _transitions[BuilderFSM.Current]
        if not allowed or not allowed[newState] then
            lib.notify({
                title = "Builder FSM",
                description = ("Invalid transition: %s → %s"):format(BuilderFSM.Current, newState),
                type = "error"
            })
            return false
        end

        -- Run guard logic
        if not _CheckGuards(newState) then return false end
    end

    local oldState = BuilderFSM.Current

    -- OnExit
    BuilderFSM._OnExit(oldState)

    BuilderFSM.Previous = oldState
    BuilderFSM.Current  = newState

    -- OnEnter
    BuilderFSM._OnEnter(newState)

    -- Sync NUI
    SendNUIMessage({ action = "builderStateChange", state = newState, prev = oldState })

    -- Fire listeners
    for _, fn in ipairs(BuilderFSM._listeners) do
        fn(oldState, newState)
    end

    print(("^3[BuilderFSM] %s → %s^7"):format(oldState, newState))
    return true
end

-- ── Entry Actions ──
function BuilderFSM._OnEnter(state)
    if state == BuilderFSM.State.ENTER_BUILDER then
        -- Activate builder systems
        BuilderCore.Activate()
        -- Auto-advance to PROP_PREVIEW immediately (in a thread to avoid re-entrancy)
        Citizen.CreateThread(function()
            Wait(50) -- one frame grace period
            if BuilderFSM.Current == BuilderFSM.State.ENTER_BUILDER then
                BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
            end
        end)

    elseif state == BuilderFSM.State.PROP_PREVIEW or state == BuilderFSM.State.CHECKPOINT_PLACEMENT then
        -- Unified placement mode for both props and checkpoints
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "minimizeBuilder" })
        BuilderPropsV2.EnterPreviewMode()
        
        -- If specifically entering checkpoint mode from NUI, we might want to tell the hinted system
        if state == BuilderFSM.State.CHECKPOINT_PLACEMENT then
            BuilderCheckpoints.Active = true
        end

    elseif state == BuilderFSM.State.PROP_EDIT_MODE then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "minimizeBuilder" })
        BuilderPropsV2.EnterEditMode()

    elseif state == BuilderFSM.State.DELETE_MODE then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "minimizeBuilder" })
        BuilderPropsV2.EnterDeleteMode()

    elseif state == BuilderFSM.State.PREVIEW_TRACK then
        BuilderPreview.Start()

    elseif state == BuilderFSM.State.SIMULATION_MODE then
        BuilderPreview.StartSimulation()

    elseif state == BuilderFSM.State.SAVE_TRACK then
        -- Re-open NUI for save dialog
        SetNuiFocus(true, true)
        SendNUIMessage({ action = "restoreBuilder" })
        Citizen.CreateThread(function()
            Wait(100)
            BuilderCore.PromptSave()
        end)

    elseif state == BuilderFSM.State.EXIT_BUILDER then
        BuilderCore.Deactivate()
        -- Defer IDLE transition to avoid re-entrancy inside OnEnter
        Citizen.CreateThread(function()
            Wait(0)
            BuilderFSM.Current = BuilderFSM.State.IDLE
            SendNUIMessage({ action = "builderStateChange", state = "IDLE", prev = "EXIT_BUILDER" })
            print("^3[BuilderFSM] EXIT_BUILDER → IDLE^7")
        end)
    end
end

-- ── Exit Actions ──
function BuilderFSM._OnExit(state)
    -- Don't stop if we are transitioning between unified placement modes
    local nextState = BuilderFSM.Current 
    local isUnified = (state == BuilderFSM.State.PROP_PREVIEW or state == BuilderFSM.State.CHECKPOINT_PLACEMENT)
    local nextIsUnified = (nextState == BuilderFSM.State.PROP_PREVIEW or nextState == BuilderFSM.State.CHECKPOINT_PLACEMENT)
    
    if isUnified and nextIsUnified then
        -- Skip stop, keep loop running
        return
    end

    if state == BuilderFSM.State.PROP_PREVIEW or state == BuilderFSM.State.CHECKPOINT_PLACEMENT then
        BuilderPropsV2.Stop()
        BuilderCheckpoints.ExitPlacementMode()

    elseif state == BuilderFSM.State.PROP_EDIT_MODE then
        BuilderPropsV2.Stop()

    elseif state == BuilderFSM.State.DELETE_MODE then
        BuilderPropsV2.Stop()

    elseif state == BuilderFSM.State.PREVIEW_TRACK or state == BuilderFSM.State.SIMULATION_MODE then
        BuilderPreview.Stop()
    end
end

-- ── Subscribe to state changes ──
function BuilderFSM.OnStateChange(fn)
    table.insert(BuilderFSM._listeners, fn)
end

-- ── Emergency Reset ──
function BuilderFSM.EmergencyReset()
    print("^1[BuilderFSM] EMERGENCY RESET^7")
    if BuilderPropsV2 then BuilderPropsV2.ClearGhost() end
    if BuilderPreview  then BuilderPreview.Stop()      end
    if BuilderUndo     then BuilderUndo.Clear()        end
    BuilderFSM.Current = BuilderFSM.State.IDLE
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "builderStateChange", state = "IDLE", prev = "RESET" })
    lib.notify({ description = "Builder reset safely.", type = "success" })
end

-- ── Commands ──
RegisterCommand("trackbuilder", function()
    if BuilderFSM.Current ~= BuilderFSM.State.IDLE then
        lib.notify({ description = "Already in builder mode!", type = "warning" })
        return
    end
    BuilderFSM.SetState(BuilderFSM.State.ENTER_BUILDER)
end, false)

RegisterCommand("builder_reset", function()
    BuilderFSM.EmergencyReset()
end, false)

-- ── Exports ──
exports("GetBuilderState",  function() return BuilderFSM.Current end)
exports("SetBuilderState",  function(s) return BuilderFSM.SetState(s) end)
exports("IsInBuilderMode",  function() return BuilderFSM.Current ~= BuilderFSM.State.IDLE end)
