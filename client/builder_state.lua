-- Elite Builder: Finite State Machine (FSM)
-- Manages advanced track building modes and isolation

BuilderStateMachine = {
    CurrentState = "IDLE",
    
    -- Sub-States
    PlacementSubState = "NONE", -- PREVIEW, ROTATING, HEIGHT_ADJUST, CONFIRM
    CaptureSubState = "NONE",   -- RECORDING, PAUSED, SMOOTHING
    
    States = {
        IDLE = "IDLE",
        ENTER_BUILDER = "ENTER_BUILDER",
        PLACEMENT = "PLACEMENT",
        START_FINISH = "START_FINISH",
        CAPTURE_LINE = "CAPTURE_LINE",
        CORRIDOR_EDIT = "CORRIDOR_EDIT",
        ANTI_CUT_EDIT = "ANTI_CUT_EDIT",
        PROP_MANAGEMENT = "PROP_MANAGEMENT",
        GRID_EDIT = "GRID_EDIT",
        THEME_EDIT = "THEME_EDIT",
        ANALYZE = "ANALYZE",
        SIMULATION = "SIMULATION",
        SAVING = "SAVING",
        EXIT_BUILDER = "EXIT_BUILDER"
    }
}

-- Events
AddEventHandler("GhostReplay:Client:Builder:StateChanged", function(oldState, newState)
    print("^3[Builder] State Transition: " .. oldState .. " -> " .. newState .. "^7")
end)

function BuilderStateMachine.SetState(newState)
    local oldState = BuilderStateMachine.CurrentState
    if oldState == newState then return end
    
    -- 1. Guard Checks
    if not BuilderStateMachine.CanTransition(oldState, newState) then
        lib.notify({description = "Invalid state transition!", type = "error"})
        return false
    end
    
    -- 2. Exit Logic
    BuilderStateMachine.OnExitState(oldState)
    
    -- 3. Transition
    BuilderStateMachine.CurrentState = newState
    
    -- 4. Entry Logic
    BuilderStateMachine.OnEnterState(newState)
    
    -- 5. Notify NUI
    SendNUIMessage({
        action = "updateBuilderState",
        state = newState
    })
    
    TriggerEvent("GhostReplay:Client:Builder:StateChanged", oldState, newState)
    return true
end

function BuilderStateMachine.CanTransition(oldState, newState)
    -- EMERGENCY_RESET/EXIT always allowed
    if newState == "EXIT_BUILDER" or newState == "IDLE" then return true end
    
    -- Cannot Enter Simulation without triggers
    if newState == "SIMULATION" then
        if not TrackBuilder.CurrentData.startLine.left or not TrackBuilder.CurrentData.finishLine.left then
            lib.notify({description = "Start/Finish triggers missing!", type = "error"})
            return false
        end
    end
    
    -- If already saving, block everything else
    if oldState == "SAVING" and newState ~= "EXIT_BUILDER" then return false end
    
    return true
end

function BuilderStateMachine.OnEnterState(state)
    if state == "ENTER_BUILDER" then
        -- Isolate Client
        SetNuiFocus(true, true)
        -- Optionally disable traffic, local player noclip etc.
    elseif state == "PLACEMENT" then
        -- Logic handled by PropBuilder
    elseif state == "CAPTURE_LINE" then
        lib.notify({description = "Entering Racing Line Capture Mode", type = "info"})
    elseif state == "SIMULATION" then
        -- Start local race test
        TriggerEvent("GhostReplay:Client:Builder:StartSimulation")
    elseif state == "EXIT_BUILDER" then
        BuilderStateMachine.Cleanup()
        BuilderStateMachine.SetState("IDLE")
    end
end

function BuilderStateMachine.OnExitState(state)
    if state == "PLACEMENT" then
        PropBuilder.Cleanup()
    elseif state == "CAPTURE_LINE" then
        -- Save captured line to memory
    end
end

function BuilderStateMachine.Cleanup()
    PropBuilder.Cleanup()
    -- Clear preview markers, reset recording buffers etc.
    lib.notify({description = "Builder Memory Cleaned Safely", type = "success"})
end

-- Helper to set sub-states
function BuilderStateMachine.SetSubState(mainState, subState)
    if mainState == "PLACEMENT" then
        BuilderStateMachine.PlacementSubState = subState
        SendNUIMessage({ action = "setPlacementMode", active = true, subState = subState })
    elseif mainState == "CAPTURE" then
        BuilderStateMachine.CaptureSubState = subState
    end
end

-- Emergency Reset
function BuilderStateMachine.EmergencyReset()
    print("^1[Builder] EMERGENCY RESET TRIGGERED^7")
    BuilderStateMachine.Cleanup()
    BuilderStateMachine.SetState("IDLE")
    SetNuiFocus(false, false)
end

-- Exports for other modules
exports("GetBuilderState", function() return BuilderStateMachine.CurrentState end)
exports("SetBuilderState", function(state) return BuilderStateMachine.SetState(state) end)
