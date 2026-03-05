-- ============================================================
-- GhostReplay Builder v2: Core Lifecycle
-- Handles activation, deactivation, save prompting, and
-- wiring together all builder sub-systems
-- ============================================================

BuilderCore = {
    _isActive   = false,
    _trackName  = "",
    _session    = nil,  -- Current track being built
}

-- ── New empty session ──
local function _NewSession()
    return {
        props       = {},   -- { id, model, coords, rotation, entity }
        checkpoints = {},   -- { id, left, right, midpoint, rotation, styleIndex, type, sector }
        antiCutZones = {},
        metadata    = nil,
    }
end

-- ── Activate builder mode ──
function BuilderCore.Activate()
    if BuilderCore._isActive then return end
    BuilderCore._isActive = true
    BuilderCore._session  = _NewSession()

    -- Isolate from race engine
    TriggerEvent("GhostReplay:Client:Builder:Begin")

    -- Disable ambient traffic (optional, config-gated)
    if Config.Builder and Config.Builder.DisableTraffic then
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
    end

    -- Open NUI in builder mode (in background, focus off)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action    = "openBuilder",
        propData  = BuilderCore.GetSerializedProps(),
        categories = TrackPropCategoryOrder,
        icons      = TrackPropCategoryIcons,
    })

    lib.notify({ title = "Track Builder", description = "Builder Mode Activated! Hit ESC to exit.", type = "success" })
    print("^2[BuilderCore] Builder activated^7")
end

-- ── Deactivate builder mode ──
function BuilderCore.Deactivate()
    if not BuilderCore._isActive then return end
    BuilderCore._isActive = false

    -- Clean client-side objects
    if BuilderPropsV2     then BuilderPropsV2.DestroyAll()     end
    if BuilderCheckpoints then BuilderCheckpoints.DestroyAll() end
    if BuilderPreview     then BuilderPreview.Stop()           end
    if BuilderUndo        then BuilderUndo.Clear()             end

    -- Restore focus and close NUI
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeBuilder" })

    -- Restore race engine
    TriggerEvent("GhostReplay:Client:Builder:End")

    BuilderCore._session = nil
    lib.notify({ title = "Track Builder", description = "Exited Builder Mode.", type = "info" })
    print("^3[BuilderCore] Builder deactivated^7")
end

-- ── Prompt for track name and trigger save ──
function BuilderCore.PromptSave()
    Citizen.CreateThread(function()
        local input = lib.inputDialog("Save Track", {
            { type = "input", label = "Track Name", placeholder = "My Awesome Track", required = true, min = 3, max = 40 },
            { type = "input", label = "Description", placeholder = "Short description..." },
        })

        if not input or not input[1] then
            lib.notify({ description = "Save cancelled.", type = "warning" })
            BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
            return
        end

        BuilderCore._trackName = input[1]

        -- Run analysis before saving
        local meta = BuilderAnalysis.Analyze(BuilderCore._session)
        BuilderCore._session.metadata = meta

        -- Build final payload
        local payload = BuilderCore._BuildPayload(BuilderCore._trackName, input[2] or "")

        -- Validate
        local ok, err = BuilderCore.Validate(payload)
        if not ok then
            lib.notify({ description = "Cannot save: " .. err, type = "error" })
            BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
            return
        end

        -- Send to server
        TriggerServerEvent("GhostReplay:Server:SaveTrackV2", payload)
        lib.notify({ title = "Track Builder", description = "Saving '" .. BuilderCore._trackName .. "'...", type = "info" })
    end)
end

-- ── Validate payload before sending to server ──
function BuilderCore.Validate(payload)
    if not payload.name or payload.name == "" then return false, "Track name is empty." end
    if not payload.checkpoints or #payload.checkpoints < 2 then 
        return false, ("Need at least 2 checkpoints (got %d)."):format(#(payload.checkpoints or {})) 
    end

    local hasStart, hasFinish = false, false
    local debugStr = ""
    
    for i, cp in ipairs(payload.checkpoints) do
        local t = tostring(cp.type or "NONE"):upper()
        if t == "START"  then hasStart  = true end
        if t == "FINISH" then hasFinish = true end
        debugStr = debugStr .. ("[%d:%s] "):format(i, t)
    end

    print("^3[BuilderCore] Validating track: " .. debugStr .. "^7")

    if not hasStart  then return false, "Missing START checkpoint. Types: " .. debugStr end
    if not hasFinish then return false, "Missing FINISH checkpoint. Types: " .. debugStr end

    return true
end

-- ── Build serialized payload ──
function BuilderCore._BuildPayload(name, desc)
    local session = BuilderCore._session
    local cps     = {}
    local props   = {}

    for _, cp in ipairs(session.checkpoints) do
        table.insert(cps, {
            id         = cp.id,
            left       = cp.left,
            right      = cp.right,
            midpoint   = cp.midpoint,
            rotation   = cp.rotation,
            styleIndex = cp.styleIndex,
            type       = cp.type,
            sector     = cp.sector,
        })
    end

    for _, p in ipairs(session.props) do
        table.insert(props, {
            model    = p.model,
            coords   = { x = p.coords.x, y = p.coords.y, z = p.coords.z },
            rotation = { x = p.rotation.x, y = p.rotation.y, z = p.rotation.z },
        })
    end

    return {
        name         = name,
        description  = desc,
        checkpoints  = cps,
        props        = props,
        antiCutZones = session.antiCutZones,
        metadata     = session.metadata,
    }
end

-- ── Serialize TrackProps config for NUI ──
function BuilderCore.GetSerializedProps()
    local out = {}
    for _, cat in ipairs(TrackPropCategoryOrder) do
        out[cat] = TrackProps[cat] or {}
    end
    return out
end

-- ── Check if builder is active ──
function BuilderCore.IsActive()
    return BuilderCore._isActive
end

-- ── Listen for server save confirmation ──
RegisterNetEvent("GhostReplay:Client:TrackSaved")
AddEventHandler("GhostReplay:Client:TrackSaved", function(trackId)
    lib.notify({
        title       = "Track Saved!",
        description = "'" .. BuilderCore._trackName .. "' saved successfully! ID: " .. tostring(trackId),
        type        = "success",
    })
    BuilderFSM.SetState(BuilderFSM.State.EXIT_BUILDER)
end)

-- ── Listen for server save failure ──
RegisterNetEvent("GhostReplay:Client:TrackSaveFailed")
AddEventHandler("GhostReplay:Client:TrackSaveFailed", function(reason)
    lib.notify({ title = "Save Failed", description = reason, type = "error" })
    BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
end)

-- ── Expose session for sub-modules ──
function BuilderCore.GetSession()
    return BuilderCore._session
end
