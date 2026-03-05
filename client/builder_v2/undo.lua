-- ============================================================
-- GhostReplay Builder v2: Undo / Redo Action Stack
-- Supports CTRL+Z (Undo) and CTRL+Y (Redo) for all builder ops
-- ============================================================

BuilderUndo = {
    _undoStack = {},
    _redoStack = {},
    MAX_HISTORY = 50,
}

-- ── Action Types ──
BuilderUndo.ActionType = {
    PLACE_PROP         = "PLACE_PROP",
    DELETE_PROP        = "DELETE_PROP",
    MOVE_PROP          = "MOVE_PROP",
    ADD_CHECKPOINT     = "ADD_CHECKPOINT",
    REMOVE_CHECKPOINT  = "REMOVE_CHECKPOINT",
    EDIT_CHECKPOINT    = "EDIT_CHECKPOINT",
}

-- ── Push a new action onto the undo stack ──
-- action = { type, propId (optional), before, after }
-- 'before'/'after' are snapshots of the world state relevant to this action.
function BuilderUndo.Push(action)
    if not action or not action.type then return end

    table.insert(BuilderUndo._undoStack, action)
    BuilderUndo._redoStack = {} -- New action clears the redo branch

    -- Enforce max history size (drop oldest)
    if #BuilderUndo._undoStack > BuilderUndo.MAX_HISTORY then
        table.remove(BuilderUndo._undoStack, 1)
    end

    BuilderUndo._NotifyNUI()
end

-- ── Undo last action ──
function BuilderUndo.Undo()
    if #BuilderUndo._undoStack == 0 then
        lib.notify({ description = "Nothing to undo.", type = "warning" })
        return
    end

    local action = table.remove(BuilderUndo._undoStack)
    BuilderUndo._Apply(action, "undo")
    table.insert(BuilderUndo._redoStack, action)
    BuilderUndo._NotifyNUI()

    lib.notify({ description = "↩ Undid: " .. action.type, type = "info" })
end

-- ── Redo last undone action ──
function BuilderUndo.Redo()
    if #BuilderUndo._redoStack == 0 then
        lib.notify({ description = "Nothing to redo.", type = "warning" })
        return
    end

    local action = table.remove(BuilderUndo._redoStack)
    BuilderUndo._Apply(action, "redo")
    table.insert(BuilderUndo._undoStack, action)
    BuilderUndo._NotifyNUI()

    lib.notify({ description = "↪ Redid: " .. action.type, type = "info" })
end

-- ── Internal: Apply restoration logic ──
function BuilderUndo._Apply(action, direction)
    local restore = (direction == "undo") and action.before or action.after

    if action.type == BuilderUndo.ActionType.PLACE_PROP then
        if direction == "undo" then
            -- Remove the prop that was placed
            BuilderPropsV2.RemoveById(action.propId)
        else
            -- Re-place the prop
            BuilderPropsV2.SpawnFromData(restore)
        end

    elseif action.type == BuilderUndo.ActionType.DELETE_PROP then
        if direction == "undo" then
            -- Re-spawn the deleted prop
            BuilderPropsV2.SpawnFromData(restore)
        else
            -- Re-delete it
            BuilderPropsV2.RemoveById(action.propId)
        end

    elseif action.type == BuilderUndo.ActionType.MOVE_PROP then
        -- Teleport prop entity back to restore position/rotation
        local ent = BuilderPropsV2.GetEntityById(action.propId)
        if ent and DoesEntityExist(ent) then
            SetEntityCoordsNoOffset(ent, restore.coords.x, restore.coords.y, restore.coords.z, false, false, false)
            SetEntityRotation(ent, restore.rotation.x, restore.rotation.y, restore.rotation.z, 2, true)
        end

    elseif action.type == BuilderUndo.ActionType.ADD_CHECKPOINT then
        if direction == "undo" then
            BuilderCheckpoints.RemoveById(action.checkpointId, true)
        else
            BuilderCheckpoints.Add(restore, true)
        end
        BuilderCheckpoints._RecalculateAllBlips()

    elseif action.type == BuilderUndo.ActionType.REMOVE_CHECKPOINT then
        if direction == "undo" then
            BuilderCheckpoints.Add(restore, true)
        else
            BuilderCheckpoints.RemoveById(action.checkpointId, true)
        end
        BuilderCheckpoints._RecalculateAllBlips()
    end
end

-- ── Notify NUI of current stack depth ──
function BuilderUndo._NotifyNUI()
    SendNUIMessage({
        action     = "updateUndoState",
        canUndo    = #BuilderUndo._undoStack > 0,
        canRedo    = #BuilderUndo._redoStack > 0,
        undoDepth  = #BuilderUndo._undoStack,
        redoDepth  = #BuilderUndo._redoStack,
    })
end

-- ── Clear all history (called on EXIT_BUILDER) ──
function BuilderUndo.Clear()
    BuilderUndo._undoStack = {}
    BuilderUndo._redoStack = {}
    BuilderUndo._NotifyNUI()
end
