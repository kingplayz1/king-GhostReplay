-- Elite Physical Track Creator: Prop Placement Engine
-- Handles ghost previews, raycast aiming, and smart snapping

PropBuilder = {
    Active = false,
    CurrentModel = nil,
    GhostEntity = nil,
    
    -- Placement State
    Coords = vector3(0,0,0),
    Rotation = vector3(0,0,0), -- Pitch, Roll, Yaw
    SnapEnabled = true,
    SnapGrid = 1.0,
    SnapRot = 5.0,
    
    TrackProps = {}, -- Current session's placed props
    SelectedEntity = nil,
    SelectedPropData = nil,
    IsDragging = false,
    LastSync = 0
}

function PropBuilder.Start(model)
    PropBuilder.Cleanup()
    
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
    
    PropBuilder.CurrentModel = model
    PropBuilder.GhostEntity = CreateObject(hash, 0, 0, 0, false, false, false)
    SetEntityAlpha(PropBuilder.GhostEntity, 150, false)
    SetEntityCollision(PropBuilder.GhostEntity, false, false)
    SetEntityInvincible(PropBuilder.GhostEntity, true)
    
    PropBuilder.Active = true
    BuilderStateMachine.SetSubState("PLACEMENT", "PREVIEW")
    
    SetNuiFocus(false, false) -- Allow game control while placement is active
    
    PropBuilder.Loop()
end

function PropBuilder.Cleanup()
    if PropBuilder.GhostEntity and DoesEntityExist(PropBuilder.GhostEntity) then
        DeleteEntity(PropBuilder.GhostEntity)
    end
    PropBuilder.GhostEntity = nil
    PropBuilder.Active = false
end

function PropBuilder.Loop()
    Citizen.CreateThread(function()
        while PropBuilder.Active do
            Wait(0)
            
            -- 1. Aiming Logic (Raycast)
            local hit, coords, normal = PropBuilder.GetRaycastResult()
            if hit then
                local finalCoords = coords
                if PropBuilder.SnapEnabled then
                    finalCoords = vector3(
                        math.floor(coords.x / PropBuilder.SnapGrid + 0.5) * PropBuilder.SnapGrid,
                        math.floor(coords.y / PropBuilder.SnapGrid + 0.5) * PropBuilder.SnapGrid,
                        coords.z -- Keep Z natural or snap slightly
                    )
                end
                
                SetEntityCoordsNoOffset(PropBuilder.GhostEntity, finalCoords.x, finalCoords.y, finalCoords.z, false, false, false)
                SetEntityRotation(PropBuilder.GhostEntity, PropBuilder.Rotation.x, PropBuilder.Rotation.y, PropBuilder.Rotation.z, 2, true)
                
                PropBuilder.Coords = finalCoords
            end
            
            -- Gizmo Rendering (If selected or previewing)
            PropBuilder.DrawGizmos(PropBuilder.Coords, PropBuilder.Rotation)
            
            -- Selection Raycast (If not currently moving a ghost)
            if not PropBuilder.GhostEntity then
                PropBuilder.UpdateSelection()
            end
            
            -- Sync Inspector (50ms Throttle)
            if GetGameTimer() - PropBuilder.LastSync > 50 then
                PropBuilder.UpdateInspector()
                PropBuilder.LastSync = GetGameTimer()
            end
            
            -- 2. Controls
            PropBuilder.HandleControls()
            
            -- 3. Visual Hints
            DrawMarker(27, PropBuilder.Coords.x, PropBuilder.Coords.y, PropBuilder.Coords.z + 0.05, 0,0,0, 0,0,0, 1.5, 1.5, 1.5, 0, 255, 242, 100, false, false, 2, false, nil, nil, false)
        end
        
        SendNUIMessage({ action = "setPlacementMode", active = false })
    end)
end

function PropBuilder.UpdateSelection()
    local hit, entity = PropBuilder.GetEntityRaycast()
    if hit and IsEntityAnObject(entity) then
        -- Highlight hovered
        local coords = GetEntityCoords(entity)
        DrawMarker(28, coords.x, coords.y, coords.z, 0,0,0, 0,0,0, 0.5, 0.5, 0.5, 255, 255, 255, 100, false, false, 2, false, nil, nil, false)
        
        if IsDisabledControlJustPressed(0, 23) then -- F to select
            PropBuilder.SelectProp(entity)
        end
    end
end

function PropBuilder.SelectProp(entity)
    PropBuilder.SelectedEntity = entity
    -- Find internal data
    for _, p in ipairs(PropBuilder.TrackProps) do
        if p.entity == entity then
            PropBuilder.SelectedPropData = p.data
            PropBuilder.Coords = p.data.coords
            PropBuilder.Rotation = p.data.rotation
            lib.notify({description = "Prop Selected: " .. p.data.model, type = "info"})
            break
        end
    end
end

function PropBuilder.DrawGizmos(coords, rotation)
    local forward, right, up = Utils.RotationToVectors(rotation)
    
    -- X Axis (Red) - Right
    DrawLine(coords.x, coords.y, coords.z, coords.x + right.x * 2.0, coords.y + right.y * 2.0, coords.z + right.z * 2.0, 255, 0, 0, 200)
    -- Y Axis (Green) - Forward
    DrawLine(coords.x, coords.y, coords.z, coords.x + forward.x * 2.0, coords.y + forward.y * 2.0, coords.z + forward.z * 2.0, 0, 255, 0, 200)
    -- Z Axis (Blue) - Up
    DrawLine(coords.x, coords.y, coords.z, coords.x + up.x * 2.0, coords.y + up.y * 2.0, coords.z + up.z * 2.0, 0, 0, 255, 200)
end

function PropBuilder.UpdateInspector()
    local active = (PropBuilder.GhostEntity ~= nil) or (PropBuilder.SelectedPropData ~= nil)
    local data = nil
    if active then
        data = {
            coords = PropBuilder.Coords,
            rotation = PropBuilder.Rotation,
            model = PropBuilder.CurrentModel or (PropBuilder.SelectedPropData and PropBuilder.SelectedPropData.model) or "Unknown"
        }
    end
    SendNUIMessage({
        action = "syncInspector",
        active = active,
        data = data
    })
end

function PropBuilder.GetEntityRaycast()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local forward = Utils.RotationToDirection(camRot)
    local target = camCoords + (forward * 30.0)
    
    local handle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, target.x, target.y, target.z, 16, PlayerPedId(), 0)
    local _, hit, coords, _, entity = GetShapeTestResult(handle)
    return hit, entity
end

function PropBuilder.GetRaycastResult()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local forward = Utils.RotationToDirection(camRot)
    local target = camCoords + (forward * 20.0) -- 20m reach
    
    local handle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, target.x, target.y, target.z, -1, PlayerPedId(), 0)
    local _, hit, coords, normal, _ = GetShapeTestResult(handle)
    return hit, coords, normal
end

function PropBuilder.HandleControls()
    -- Rotate Q/E
    if IsDisabledControlPressed(0, 44) or IsDisabledControlPressed(0, 38) then -- Q or E
        BuilderStateMachine.SetSubState("PLACEMENT", "ROTATING")
        if IsDisabledControlPressed(0, 44) then -- Q
            PropBuilder.Rotation = PropBuilder.Rotation + vector3(0, 0, PropBuilder.SnapEnabled and -PropBuilder.SnapRot or -1.0)
        end
        if IsDisabledControlPressed(0, 38) then -- E
            PropBuilder.Rotation = PropBuilder.Rotation + vector3(0, 0, PropBuilder.SnapEnabled and PropBuilder.SnapRot or 1.0)
        end
    end
    
    -- Elevate PGUP/PGDN
    if IsDisabledControlPressed(0, 10) or IsDisabledControlPressed(0, 11) then -- PAGEUP or PAGEDOWN
        BuilderStateMachine.SetSubState("PLACEMENT", "HEIGHT_ADJUST")
        if IsDisabledControlPressed(0, 10) then -- PAGEUP
            PropBuilder.Rotation = PropBuilder.Rotation + vector3(1.0, 0, 0)
        end
        if IsDisabledControlPressed(0, 11) then -- PAGEDOWN
            PropBuilder.Rotation = PropBuilder.Rotation + vector3(-1.0, 0, 0)
        end
    end

    -- Toggle Snap G
    if IsDisabledControlJustPressed(0, 47) then -- G
        PropBuilder.SnapEnabled = not PropBuilder.SnapEnabled
        lib.notify({description = "Snapping: " .. (PropBuilder.SnapEnabled and "ON" or "OFF"), type = "info"})
    end

    -- Confirm LMB
    if IsDisabledControlJustPressed(0, 24) then
        BuilderStateMachine.SetSubState("PLACEMENT", "CONFIRM")
        PropBuilder.ConfirmPlacement()
        Wait(500)
        BuilderStateMachine.SetSubState("PLACEMENT", "PREVIEW")
    end
    
    -- Cancel RMB
    if IsDisabledControlJustPressed(0, 25) then
        BuilderStateMachine.SetSubState("PLACEMENT", "CANCEL")
        PropBuilder.Cleanup()
        PropBuilder.SelectedEntity = nil
        PropBuilder.SelectedPropData = nil
        BuilderStateMachine.SetState("IDLE")
        OpenMainMenu() -- Return to UI
    end

    -- Duplicate CTRL+D (Pro feature)
    if IsDisabledControlPressed(0, 21) and IsDisabledControlJustPressed(0, 30) then -- SHIFT + D (mapping D/30)
        if PropBuilder.SelectedPropData then
            PropBuilder.Start(PropBuilder.SelectedPropData.model)
        end
    end
    
    -- Disable standard attacks
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 23, true) -- F (Selection)
end

function PropBuilder.ConfirmPlacement()
    local prop = {
        model = PropBuilder.CurrentModel,
        coords = PropBuilder.Coords,
        rotation = PropBuilder.Rotation
    }
    
    -- Spawn Real Object
    local hash = GetHashKey(prop.model)
    local obj = CreateObject(hash, prop.coords.x, prop.coords.y, prop.coords.z, false, false, false)
    SetEntityRotation(obj, prop.rotation.x, prop.rotation.y, prop.rotation.z, 2, true)
    FreezeEntityPosition(obj, true)
    
    table.insert(PropBuilder.TrackProps, {
        entity = obj,
        data = prop
    })
    
    lib.notify({description = "Prop Placed!", type = "success"})
    
    -- Stay in placement mode for quick placing
    -- PropBuilder.Cleanup() -- Uncomment if you want to exit after 1 place
end

    -- Stay in placement mode for quick placing
    -- PropBuilder.Cleanup() -- Uncomment if you want to exit after 1 place
end
