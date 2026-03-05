-- ============================================================
-- GhostReplay Builder v2: Advanced Prop Placement Engine
-- Ghost preview, raycast aim, gizmos, magnetic snap,
-- ground alignment, category cycling, and controls
-- ============================================================

BuilderPropsV2 = {
    -- State
    Active         = false,
    GhostEntity    = nil,
    SelectedProp   = nil,  -- { id, entity, data }
    Mode           = "NONE", -- PREVIEW | EDIT | DELETE

    -- Current placement values
    Coords         = vector3(0, 0, 0),
    Rotation       = vector3(0, 0, 0),
    Distance       = 10.0, -- Default distance
    Elevation      = 0.0,  -- Height offset from ground

    -- Toggles
    SoloMode       = false, -- Toggle between Gate (false) and Solo Prop (true)

    -- Category / Prop selection
    CategoryIndex  = 1,
    PropIndex      = 1,

    -- Snap settings
    SnapGrid       = true,
    GridSize       = 1.0,
    RotSnap        = 5.0,
    DirectionSnap  = true,

    -- Placed props list (mirrors BuilderCore session)
    _props         = {},   -- { id, model, coords, rotation, entity }
    _nextId        = 1,

    -- Throttle
    _lastSync      = 0,
}

-- ──────────────────────────────────────────────
-- Prop Preview Mode entry
-- ──────────────────────────────────────────────
function BuilderPropsV2.EnterPreviewMode()
    BuilderPropsV2.Mode = "PREVIEW"
    BuilderPropsV2.Active = true

    print("^3[BuilderPropsV2] EnterPreviewMode called^7")
    local ped = PlayerPedId()
    if not BuilderPropsV2.Coords or #BuilderPropsV2.Coords == 0 then
        BuilderPropsV2.Coords = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 5.0
    end

    -- Do NOT spawn solo ghost here anymore.
    -- It will be lazy-loaded in _RunLoop only if SHIFT is held.
    SetNuiFocus(false, false) 

    -- Register controls hint
    Utils.ShowHint(BuilderPropsV2._GetControlsHint(), "right-center")

    BuilderPropsV2._RunLoop()
end

-- ──────────────────────────────────────────────
-- Edit Mode: Select and reposition placed prop
-- ──────────────────────────────────────────────
function BuilderPropsV2.EnterEditMode()
    BuilderPropsV2.Mode = "EDIT"
    BuilderPropsV2.Active = true
    lib.notify({ description = "Aim at a prop and press [F] to select it.", type = "info" })
    BuilderPropsV2._RunLoop()
end

-- ──────────────────────────────────────────────
-- Delete Mode
-- ──────────────────────────────────────────────
function BuilderPropsV2.EnterDeleteMode()
    BuilderPropsV2.Mode = "DELETE"
    BuilderPropsV2.Active = true
    lib.notify({ description = "Aim at a prop and press [DEL] to remove it.", type = "warning" })
    BuilderPropsV2._RunLoop()
end

-- Stop all prop activity
-- ──────────────────────────────────────────────
function BuilderPropsV2.ClearGhost()
    if BuilderPropsV2.GhostEntity and DoesEntityExist(BuilderPropsV2.GhostEntity) then
        DeleteEntity(BuilderPropsV2.GhostEntity)
    end
    BuilderPropsV2.GhostEntity = nil
end

function BuilderPropsV2.Stop()
    BuilderPropsV2.Active = false
    BuilderPropsV2.ClearGhost()
    BuilderPropsV2.ClearSelection()
    Utils.HideHint()
end

function BuilderPropsV2.ClearSelection()
    BuilderPropsV2.SelectedProp = nil
    BuilderPropsV2.ClearGhost()
end

-- ──────────────────────────────────────────────
-- Main Loop
-- ──────────────────────────────────────────────
function BuilderPropsV2._RunLoop()
    Citizen.CreateThread(function()
        while BuilderPropsV2.Active do
            Wait(0)
            local ped = PlayerPedId()
            local fwd = GetEntityForwardVector(ped)
            local pPos = GetEntityCoords(ped)
            local shiftHeld = IsDisabledControlPressed(0, 21) -- SHIFT

            -- 1. BASE POSITIONING
            local center = pPos + fwd * BuilderPropsV2.Distance
            local rotRad = math.rad(BuilderPropsV2.Rotation.z)
            local dir    = vector3(math.cos(rotRad), math.sin(rotRad), 0.0)
            
            -- Ground alignment for center
            local _, gzC = GetGroundZFor_3dCoord(center.x, center.y, center.z + 5.0, 0)
            local finalCenter = vector3(center.x, center.y, gzC + 0.1 + BuilderPropsV2.Elevation)
            BuilderPropsV2.Coords = finalCenter

            -- 2. PLACEMENT GHOST LOGIC (Toggle-based)
            if not BuilderPropsV2.SoloMode then
                -- GATE MODE (Double Prop)
                if BuilderPropsV2.GhostEntity then SetEntityVisible(BuilderPropsV2.GhostEntity, false, false) end
                
                -- Calculate gate poles
                local width = BuilderCheckpoints._gateWidth or 8.0
                local lPos  = finalCenter + dir * (width / 2.0)
                local rPos = finalCenter - dir * (width / 2.0)
                
                -- Ground align poles relative to the elevated center? 
                -- Usually, poles should stay on ground, but if center is elevated, maybe the whole gate?
                -- User said "i can do up or down this flag position", so elevation should apply.
                local leftPos  = vector3(lPos.x, lPos.y, lPos.z)
                local rightPos = vector3(rPos.x, rPos.y, rPos.z)
                
                -- Maintain Checkpoint Ghosts
                local styleIdx = BuilderCheckpoints._currentStyle or 1
                local style = TrackProps.GateStyles[styleIdx]
                
                if not BuilderPropsV2._cpL or not DoesEntityExist(BuilderPropsV2._cpL) then
                    local h = GetHashKey(style.left)
                    lib.requestModel(h)
                    BuilderPropsV2._cpL = CreateObject(h, leftPos.x, leftPos.y, leftPos.z, false, false, false)
                    SetEntityAlpha(BuilderPropsV2._cpL, 180, false)
                    SetEntityCollision(BuilderPropsV2._cpL, false, false)
                end
                if not BuilderPropsV2._cpR or not DoesEntityExist(BuilderPropsV2._cpR) then
                    local h = GetHashKey(style.right)
                    lib.requestModel(h)
                    BuilderPropsV2._cpR = CreateObject(h, rightPos.x, rightPos.y, rightPos.z, false, false, false)
                    SetEntityAlpha(BuilderPropsV2._cpR, 180, false)
                    SetEntityCollision(BuilderPropsV2._cpR, false, false)
                end

                SetEntityCoordsNoOffset(BuilderPropsV2._cpL, leftPos.x, leftPos.y, leftPos.z, false, false, false)
                SetEntityCoordsNoOffset(BuilderPropsV2._cpR, rightPos.x, rightPos.y, rightPos.z, false, false, false)
                SetEntityRotation(BuilderPropsV2._cpL, 0.0, 0.0, BuilderPropsV2.Rotation.z, 2, true)
                SetEntityRotation(BuilderPropsV2._cpR, 0.0, 0.0, BuilderPropsV2.Rotation.z, 2, true)
                SetEntityVisible(BuilderPropsV2._cpL, true, false)
                SetEntityVisible(BuilderPropsV2._cpR, true, false)

                -- Visual Line
                DrawLine(leftPos.x, leftPos.y, leftPos.z+1.0, rightPos.x, rightPos.y, rightPos.z+1.0, 0, 255, 255, 200)
            else
                -- SOLO PROP MODE
                if not BuilderPropsV2.GhostEntity or not DoesEntityExist(BuilderPropsV2.GhostEntity) then
                    BuilderPropsV2._SpawnGhost()
                end

                if BuilderPropsV2.GhostEntity then 
                    SetEntityVisible(BuilderPropsV2.GhostEntity, true, false) 
                    SetEntityCoordsNoOffset(BuilderPropsV2.GhostEntity, finalCenter.x, finalCenter.y, finalCenter.z, false, false, false)
                    SetEntityRotation(BuilderPropsV2.GhostEntity, BuilderPropsV2.Rotation.x, BuilderPropsV2.Rotation.y, BuilderPropsV2.Rotation.z, 2, true)
                end
                -- Hide checkpoint ghosts
                if BuilderPropsV2._cpL then SetEntityVisible(BuilderPropsV2._cpL, false, false) end
                if BuilderPropsV2._cpR then SetEntityVisible(BuilderPropsV2._cpR, false, false) end
            end

            DrawMarker(27, BuilderPropsV2.Coords.x, BuilderPropsV2.Coords.y, BuilderPropsV2.Coords.z, 0,0,0, 0,0,BuilderPropsV2.Rotation.z, 1.2,1.2,1.2, 255,255,0,150, false,false,2,false,nil,nil,false)

            -- Hover highlight for EDIT/DELETE
            local hit, ent = BuilderPropsV2._EntityRaycast()
            if hit and IsEntityAnObject(ent) then
                local c = GetEntityCoords(ent)
                DrawMarker(28, c.x, c.y, c.z, 0,0,0, 0,0,0, 1.0,1.0,1.0, 255,255,255,120, false,false,2,false,nil,nil,false)
            end

            -- Cull Far Props
            if GetGameTimer() - (BuilderPropsV2._lastCull or 0) > 1000 then
                local pCoords = GetEntityCoords(ped)
                for _, p in ipairs(BuilderPropsV2._props) do
                    local dist = #(pCoords - p.coords)
                    if dist > 250.0 then if p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) p.entity = nil end
                    else if not p.entity or not DoesEntityExist(p.entity) then
                        local hash = GetHashKey(p.model)
                        if HasModelLoaded(hash) then
                            p.entity = CreateObject(hash, p.coords.x, p.coords.y, p.coords.z, false, false, false)
                            SetEntityRotation(p.entity, p.rotation.x, p.rotation.y, p.rotation.z, 2, true)
                            FreezeEntityPosition(p.entity, true)
                        end
                    end end
                end
                BuilderPropsV2._lastCull = GetGameTimer()
            end

            BuilderPropsV2._HandleControls()
        end
        Utils.HideHint()
        if BuilderPropsV2._cpL then DeleteEntity(BuilderPropsV2._cpL) end
        if BuilderPropsV2._cpR then DeleteEntity(BuilderPropsV2._cpR) end
        BuilderPropsV2._cpL, BuilderPropsV2._cpR = nil, nil
    end)
end

function BuilderPropsV2._HandleControls()
    local altHeld   = IsDisabledControlPressed(0, 19)
    local shiftJustPressed = IsDisabledControlJustPressed(0, 21)
    local ctrlHeld  = IsDisabledControlPressed(0, 36)

    -- ── TOGGLE MODE (SHIFT)
    if shiftJustPressed then
        BuilderPropsV2.SoloMode = not BuilderPropsV2.SoloMode
        local modeName = BuilderPropsV2.SoloMode and "SOLO PROP" or "GATE"
        lib.notify({ description = "Builder Mode: " .. modeName, type = "info" })
    end

    -- ── ELEVATION (PgUp/PgDn)
    if IsDisabledControlPressed(0, 10) then -- Page Up
        BuilderPropsV2.Elevation = BuilderPropsV2.Elevation + 0.05
    elseif IsDisabledControlPressed(0, 11) then -- Page Down
        BuilderPropsV2.Elevation = math.max(-5.0, BuilderPropsV2.Elevation - 0.05)
    end

    -- ── DISTANCE (Arrows Up/Down)
    if IsDisabledControlPressed(0, 172) then -- Up
        BuilderPropsV2.Distance = math.min(50.0, BuilderPropsV2.Distance + 0.1)
    elseif IsDisabledControlPressed(0, 173) then -- Down
        BuilderPropsV2.Distance = math.max(1.0, BuilderPropsV2.Distance - 0.1)
    end

    -- ── ROTATION (Arrows Left/Right)
    if IsDisabledControlPressed(0, 174) then -- Left
        BuilderPropsV2.Rotation = vector3(BuilderPropsV2.Rotation.x, BuilderPropsV2.Rotation.y, BuilderPropsV2.Rotation.z + 2.0)
    elseif IsDisabledControlPressed(0, 175) then -- Right
        BuilderPropsV2.Rotation = vector3(BuilderPropsV2.Rotation.x, BuilderPropsV2.Rotation.y, BuilderPropsV2.Rotation.z - 2.0)
    end

    -- ── GRID SNAP (G)
    if IsDisabledControlJustPressed(0, 47) then
        BuilderPropsV2.SnapGrid = not BuilderPropsV2.SnapGrid
        lib.notify({ description = "Grid Snap: " .. (BuilderPropsV2.SnapGrid and "ON" or "OFF"), type = "info" })
    end

    -- ── CYCLING (ALT + Scroll or Scroll)
    if IsDisabledControlJustPressed(0, 14) then -- Scroll Up
        if altHeld then
            if not BuilderPropsV2.SoloMode then
                BuilderCheckpoints._currentStyle = ((BuilderCheckpoints._currentStyle or 1) % #TrackProps.GateStyles) + 1
                lib.notify({ description = "Gate Style: " .. TrackProps.GateStyles[BuilderCheckpoints._currentStyle].name, type = "info" })
            else
                BuilderPropsV2._CycleProp(1)
            end
        else
            if not BuilderPropsV2.SoloMode then
                BuilderCheckpoints._gateWidth = math.min(30.0, (BuilderCheckpoints._gateWidth or 8.0) + 0.5)
            end
        end
    elseif IsDisabledControlJustPressed(0, 15) then -- Scroll Down
        if altHeld then
            if not BuilderPropsV2.SoloMode then
                BuilderCheckpoints._currentStyle = ((BuilderCheckpoints._currentStyle - 2) % #TrackProps.GateStyles) + 1
                lib.notify({ description = "Gate Style: " .. TrackProps.GateStyles[BuilderCheckpoints._currentStyle].name, type = "info" })
            else
                BuilderPropsV2._CycleProp(-1)
            end
        else
            if not BuilderPropsV2.SoloMode then
                BuilderCheckpoints._gateWidth = math.max(2.0, (BuilderCheckpoints._gateWidth or 8.0) - 0.5)
            end
        end
    end

    -- ── DELETE AIMED (CTRL)
    if ctrlHeld then
        local hit, ent = BuilderPropsV2._EntityRaycast()
        if hit and IsEntityAnObject(ent) then
            BuilderPropsV2._DeleteProp(ent)
            Wait(150)
        end
    end

    -- ── UNDO last CP (Q)
    if IsDisabledControlJustPressed(0, 44) then -- Q
        local all = BuilderCheckpoints.GetAll()
        if #all > 0 then BuilderCheckpoints.RemoveById(all[#all].id) end
    end

    -- ── PLACE (E)
    if IsDisabledControlJustPressed(0, 38) then
        if not BuilderPropsV2.SoloMode then
            -- Place Checkpoint Gate
            local width = BuilderCheckpoints._gateWidth or 8.0
            local rotRad = math.rad(BuilderPropsV2.Rotation.z)
            local dir = vector3(math.cos(rotRad), math.sin(rotRad), 0.0)
            
            -- Ensure poles are at the elevated height
            local lPos = BuilderPropsV2.Coords + dir * (width / 2.0)
            local rPos = BuilderPropsV2.Coords - dir * (width / 2.0)
            
            BuilderCheckpoints.Add({
                id = BuilderCheckpoints._nextId,
                left = { x = lPos.x, y = lPos.y, z = lPos.z },
                right = { x = rPos.x, y = rPos.y, z = rPos.z },
                styleIndex = BuilderCheckpoints._currentStyle or 1,
                rotation = BuilderPropsV2.Rotation.z,
                type = "AUTO"
            })
            BuilderCheckpoints._nextId = BuilderCheckpoints._nextId + 1
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            lib.notify({ description = "Gate placed.", type = "success" })
        else
            -- Place Single Prop
            BuilderPropsV2.ConfirmPlace()
        end
    end

    -- ── EXIT (RMB)
    if IsDisabledControlJustPressed(0, 25) then
        BuilderPropsV2.Stop()
    end

    -- Suppress standard actions
    DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
    DisableControlAction(0, 140, true); DisableControlAction(0, 37, false)
end

-- ──────────────────────────────────────────────
-- Confirm Placement
-- ──────────────────────────────────────────────
function BuilderPropsV2.ConfirmPlace()
    local model = BuilderPropsV2._GetCurrentModel()
    if not model then return end

    local hash = GetHashKey(model)
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - t > 5000 then
            lib.notify({ description = "Failed to load model: " .. model, type = "error" })
            return
        end
    end

    -- Rule 9: strict prop count limit check (MAX 300)
    local maxProps = 300
    if #BuilderPropsV2._props >= maxProps then
        lib.notify({ description = "Prop limit reached! (Maximum " .. maxProps .. ")", type = "error" })
        return
    end

    local ent = CreateObject(hash, BuilderPropsV2.Coords.x, BuilderPropsV2.Coords.y, BuilderPropsV2.Coords.z, false, false, false)
    SetEntityRotation(ent, BuilderPropsV2.Rotation.x, BuilderPropsV2.Rotation.y, BuilderPropsV2.Rotation.z, 2, true)
    FreezeEntityPosition(ent, true)
    SetModelAsNoLongerNeeded(hash)

    local id = BuilderPropsV2._nextId
    BuilderPropsV2._nextId = id + 1

    local data = {
        id       = id,
        model    = model,
        coords   = BuilderPropsV2.Coords,
        rotation = BuilderPropsV2.Rotation,
        entity   = ent,
    }
    table.insert(BuilderPropsV2._props, data)

    -- Mirror into session
    local session = BuilderCore.GetSession()
    if session then table.insert(session.props, data) end

    -- Push to undo
    BuilderUndo.Push({ type = BuilderUndo.ActionType.PLACE_PROP, propId = id, after = data })

    lib.notify({ description = "✅ Prop placed: " .. model .. " (" .. #BuilderPropsV2._props .. "/" .. maxProps .. ")", type = "success" })
end

-- ──────────────────────────────────────────────
-- Remove by ID (used by Undo)
-- ──────────────────────────────────────────────
function BuilderPropsV2.RemoveById(id)
    for i, p in ipairs(BuilderPropsV2._props) do
        if p.id == id then
            if p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) end
            table.remove(BuilderPropsV2._props, i)

            local session = BuilderCore.GetSession()
            if session then
                for j, sp in ipairs(session.props) do
                    if sp.id == id then table.remove(session.props, j) break end
                end
            end
            return
        end
    end
end

-- ──────────────────────────────────────────────
-- Spawn from data (used by Undo/Redo)
-- ──────────────────────────────────────────────
function BuilderPropsV2.SpawnFromData(data)
    local hash = GetHashKey(data.model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local ent = CreateObject(hash, data.coords.x, data.coords.y, data.coords.z, false, false, false)
    SetEntityRotation(ent, data.rotation.x, data.rotation.y, data.rotation.z, 2, true)
    FreezeEntityPosition(ent, true)
    SetModelAsNoLongerNeeded(hash)
    data.entity = ent
    table.insert(BuilderPropsV2._props, data)
    local session = BuilderCore.GetSession()
    if session then table.insert(session.props, data) end
end

-- ──────────────────────────────────────────────
-- Destroy all props on exit
-- ──────────────────────────────────────────────
function BuilderPropsV2.DestroyAll()
    for _, p in ipairs(BuilderPropsV2._props) do
        if p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) end
    end
    BuilderPropsV2._props   = {}
    BuilderPropsV2._nextId  = 1
    BuilderPropsV2.ClearGhost()
end

function BuilderPropsV2.GetAll() return BuilderPropsV2._props end
function BuilderPropsV2.GetEntityById(id)
    for _, p in ipairs(BuilderPropsV2._props) do
        if p.id == id then return p.entity end
    end
end

-- ──────────────────────────────────────────────
-- Internal helpers
-- ──────────────────────────────────────────────
function BuilderPropsV2._SpawnGhost()
    BuilderPropsV2.ClearGhost()
    local model = BuilderPropsV2._GetCurrentModel()
    print("^3[BuilderPropsV2::_SpawnGhost] Model selected: " .. tostring(model) .. "^7")
    
    if not model then return end
    
    local hash = GetHashKey(model)
    if not IsModelValid(hash) then
        print("^1[BuilderPropsV2::_SpawnGhost] ERROR - Model is invalid in GTA engine: " .. tostring(model) .. "^7")
        return
    end

    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - t > 5000 then 
            print("^1[BuilderPropsV2::_SpawnGhost] ERROR - Model failed to load (timeout): " .. tostring(model) .. "^7")
            return 
        end
    end
    print("^2[BuilderPropsV2::_SpawnGhost] Model loaded! Spawning " .. tostring(model) .. "^7")
    
    local ent = CreateObject(hash, 0, 0, 0, false, false, false)
    SetEntityAlpha(ent, 140, false)
    SetEntityCollision(ent, false, false)
    SetEntityInvincible(ent, true)
    SetModelAsNoLongerNeeded(hash)
    BuilderPropsV2.GhostEntity = ent
end

function BuilderPropsV2._GetCurrentModel()
    if not TrackPropCategoryOrder or not TrackProps then
        print("^1[BuilderPropsV2::_GetCurrentModel] ERROR - TrackProps config is MISSING or not loaded!^7")
        return nil
    end

    local cat  = TrackPropCategoryOrder[BuilderPropsV2.CategoryIndex]
    if not cat then 
        print("^1[BuilderPropsV2::_GetCurrentModel] ERROR - Invalid CategoryIndex: " .. tostring(BuilderPropsV2.CategoryIndex) .. "^7")
        return nil 
    end
    local list = TrackProps[cat]
    if not list or #list == 0 then 
        print("^1[BuilderPropsV2::_GetCurrentModel] ERROR - Category list empty: " .. tostring(cat) .. "^7")
        return nil 
    end
    local idx  = math.max(1, math.min(BuilderPropsV2.PropIndex, #list))
    return list[idx]
end

function BuilderPropsV2._CycleCategory(dir)
    BuilderPropsV2.CategoryIndex = ((BuilderPropsV2.CategoryIndex - 1 + dir) % #TrackPropCategoryOrder) + 1
    BuilderPropsV2.PropIndex      = 1
    BuilderPropsV2._SpawnGhost()
    local cat = TrackPropCategoryOrder[BuilderPropsV2.CategoryIndex]
    lib.notify({ description = "Category: " .. (TrackPropCategoryIcons[cat] or "") .. "  " .. cat, type = "info" })
    SendNUIMessage({ action = "builderCategoryChange", category = cat, propIndex = 1 })
end

function BuilderPropsV2._CycleProp(dir)
    local cat  = TrackPropCategoryOrder[BuilderPropsV2.CategoryIndex]
    local list = TrackProps[cat] or {}
    if #list == 0 then return end
    BuilderPropsV2.PropIndex = ((BuilderPropsV2.PropIndex - 1 + dir) % #list) + 1
    BuilderPropsV2._SpawnGhost()
    lib.notify({ description = "Prop: " .. (list[BuilderPropsV2.PropIndex] or "?"), type = "info" })
    SendNUIMessage({ action = "builderPropChange", prop = list[BuilderPropsV2.PropIndex], index = BuilderPropsV2.PropIndex })
end

-- ── Raycast for ground placement ──
function BuilderPropsV2._Raycast()
    local cam    = GetGameplayCamCoord()
    local rot    = GetGameplayCamRot(2)
    local fwd    = Utils.RotationToDirection(rot)
    local target = cam + fwd * 25.0
    local handle = StartShapeTestRay(cam.x, cam.y, cam.z, target.x, target.y, target.z, -1, PlayerPedId(), 0)
    local _, hit, coords, normal, _ = GetShapeTestResult(handle)
    return hit, coords, normal, target
end

-- ── Raycast for entity selection ──
function BuilderPropsV2._EntityRaycast()
    local cam    = GetGameplayCamCoord()
    local rot    = GetGameplayCamRot(2)
    local fwd    = Utils.RotationToDirection(rot)
    local target = cam + fwd * 30.0
    local handle = StartShapeTestRay(cam.x, cam.y, cam.z, target.x, target.y, target.z, 16, PlayerPedId(), 0)
    local _, hit, _, _, ent = GetShapeTestResult(handle)
    return hit, ent
end

-- ── Snap coordinates to grid ──
function BuilderPropsV2._SnapCoords(coords)
    if not BuilderPropsV2.SnapGrid then return coords end
    local g = BuilderPropsV2.GridSize
    return vector3(
        math.floor(coords.x / g + 0.5) * g,
        math.floor(coords.y / g + 0.5) * g,
        coords.z
    )
end

-- ── Align pitch/roll to terrain normal ──
function BuilderPropsV2._AlignToGround(coords, normal)
    if not normal or not BuilderPropsV2.DirectionSnap then
        return vector3(0, 0, BuilderPropsV2.Rotation.z)
    end
    -- Convert normal to pitch (x tilt) and roll (y tilt)
    local pitchRad = math.asin(math.max(-1, math.min(1, normal.y)))
    local rollRad  = math.asin(math.max(-1, math.min(1, -normal.x)))
    return vector3(math.deg(pitchRad), math.deg(rollRad), BuilderPropsV2.Rotation.z)
end

-- ── Magnetic snap: pull to nearest prop edge within 1.5m ──
function BuilderPropsV2._MagneticSnap(coords)
    local snapDist = 1.5
    local closest  = nil
    local closestD = snapDist

    for _, p in ipairs(BuilderPropsV2._props) do
        local d = #(coords - p.coords)
        if d < closestD then
            closestD = d
            closest  = p
        end
    end

    if closest then
        -- Snap Z to same height, X/Y by offset direction
        local dir = (coords - closest.coords)
        local len = #dir
        if len > 0.01 then
            dir = dir / len
        else
            dir = vector3(1, 0, 0)
        end
        -- Assume 1m half-extent bounding box — snap to far edge
        return closest.coords + dir * 1.0
    end
    return nil
end

-- ── Draw 3D RGB gizmo axes ──
function BuilderPropsV2._DrawGizmos(coords, rotation)
    local fwd, right, up = Utils.RotationToVectors(rotation)
    DrawLine(coords.x, coords.y, coords.z, coords.x + right.x*2, coords.y + right.y*2, coords.z + right.z*2, 255, 50,  50,  220)
    DrawLine(coords.x, coords.y, coords.z, coords.x + fwd.x*2,   coords.y + fwd.y*2,   coords.z + fwd.z*2,   50,  255, 50,  220)
    DrawLine(coords.x, coords.y, coords.z, coords.x + up.x*2,    coords.y + up.y*2,    coords.z + up.z*2,    50,  50,  255, 220)
end

-- ── Pick up a placed prop for re-editing ──
function BuilderPropsV2._PickupProp(ent)
    for _, p in ipairs(BuilderPropsV2._props) do
        if p.entity == ent then
            -- Snapshot for undo
            local before = { coords = p.coords, rotation = p.rotation }
            BuilderUndo.Push({ type = BuilderUndo.ActionType.MOVE_PROP, propId = p.id, before = before, after = nil })

            BuilderPropsV2.SelectedProp = p
            BuilderPropsV2.Coords       = p.coords
            BuilderPropsV2.Rotation     = p.rotation

            -- Make the real entity the ghost temporarily
            SetEntityAlpha(p.entity, 140, false)
            lib.notify({ description = "Prop picked up. Place again with [E].", type = "info" })
            return
        end
    end
end

-- ── Delete a prop ──
function BuilderPropsV2._DeleteProp(ent)
    for i, p in ipairs(BuilderPropsV2._props) do
        if p.entity == ent then
            BuilderUndo.Push({ type = BuilderUndo.ActionType.DELETE_PROP, propId = p.id, before = p, after = nil })
            if DoesEntityExist(p.entity) then DeleteEntity(p.entity) end
            table.remove(BuilderPropsV2._props, i)

            local session = BuilderCore.GetSession()
            if session then
                for j, sp in ipairs(session.props) do
                    if sp.id == p.id then table.remove(session.props, j) break end
                end
            end

            lib.notify({ description = "🗑 Prop deleted.", type = "warning" })
            return
        end
    end
end

-- ── Move selected prop ──
function BuilderPropsV2._MoveSelected(delta)
    local p = BuilderPropsV2.SelectedProp
    if not p then return end
    if delta.rz then
        p.rotation = vector3(p.rotation.x, p.rotation.y, p.rotation.z + delta.rz)
        SetEntityRotation(p.entity, p.rotation.x, p.rotation.y, p.rotation.z, 2, true)
    end
end

-- ── Sync Property Inspector to NUI ──
function BuilderPropsV2._SyncInspector()
    local hasGhost = BuilderPropsV2.GhostEntity ~= nil
    local hasSel   = BuilderPropsV2.SelectedProp ~= nil
    local active   = hasGhost or hasSel

    SendNUIMessage({
        action = "syncInspector",
        active = active,
        data   = active and {
            coords   = { x = BuilderPropsV2.Coords.x, y = BuilderPropsV2.Coords.y, z = BuilderPropsV2.Coords.z },
            rotation = { x = BuilderPropsV2.Rotation.x, y = BuilderPropsV2.Rotation.y, z = BuilderPropsV2.Rotation.z },
            model    = BuilderPropsV2._GetCurrentModel() or
                       (BuilderPropsV2.SelectedProp and BuilderPropsV2.SelectedProp.model) or "---",
            snap     = BuilderPropsV2.SnapGrid,
        } or nil,
    })
end

-- ── Controls hint string for text UI ──
function BuilderPropsV2._GetControlsHint()
    return "~b~[SHIFT]~w~ Toggle Solo/Gate  ~b~[E]~w~ Place  ~b~[Arrows]~w~ Move/Rot  ~b~[PgUp/Dn]~w~ Elevate  ~b~[ALT+Scroll]~w~ Cycle"
end
