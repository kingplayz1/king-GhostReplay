BuilderCheckpoints = {
    _checkpoints = {},      -- { id, left, right, midpoint, width, styleIndex, type, sector, blip }
    _nextId      = 1,
    _mode        = "NONE",
    Active       = false,

    -- Placement state
    _currentStyle = 1,
    _leftPos      = nil,
    _rightPos     = nil,
    _leftEnt      = nil,
    _rightEnt     = nil,
    _ghostRot     = 0.0,
    _gateWidth    = 8.0,
    _gateDist     = 10.0,
}

-- ── SECTOR COLORS (for DrawMarker) ──
local SECTOR_COLOR = {
    [1] = { r=0,   g=255, b=255 },  -- Cyan
    [2] = { r=255, g=0,   b=255 },  -- Magenta
    [3] = { r=255, g=255, b=0   },  -- Yellow
}
local TYPE_COLOR = {
    START  = { r=0,   g=255, b=0   },
    FINISH = { r=255, g=0,   b=0   },
    NORMAL = { r=255, g=255, b=255 },
}

-- ──────────────────────────────────────────────
-- Enter Placement Mode
-- ──────────────────────────────────────────────
function BuilderCheckpoints.EnterPlacementMode(modeType)
    -- This is now a simple helper to notify systems if needed.
    -- The actual loop is handled in props.lua for a unified experience.
    BuilderCheckpoints._mode   = modeType
    BuilderCheckpoints.Active  = true
    SetNuiFocus(false, false)

    -- Ensure we have defaults if not set
    if not BuilderCheckpoints._gateWidth then BuilderCheckpoints._gateWidth = 8.0 end
    if not BuilderCheckpoints._currentStyle then BuilderCheckpoints._currentStyle = 1 end

    Utils.ShowHint(
        "~b~[E]~w~ Prop  ~b~[SHIFT+E]~w~ Gate  ~b~[Arrows]~w~ Move/Rot  ~b~[ALT]~w~ Style  ~b~[CTRL]~w~ Delete  ~b~[Q]~w~ Undo",
        "right-center"
    )
end

function BuilderCheckpoints.ExitPlacementMode()
    BuilderCheckpoints.Active = false
    BuilderCheckpoints._mode  = "NONE"
end

-- ──────────────────────────────────────────────
-- Placement Logic
-- ──────────────────────────────────────────────
function BuilderCheckpoints.Add(data, noUndo)
    local maxCheckpoints = 120
    if #BuilderCheckpoints._checkpoints >= maxCheckpoints then
        lib.notify({ description = "Checkpoint limit reached!", type = "error" })
        return nil
    end

    -- Midpoint and width for blip/trigger
    local left = vector3(data.left.x, data.left.y, data.left.z)
    local right = vector3(data.right.x, data.right.y, data.right.z)
    local mid = (left + right) / 2.0
    data.midpoint = { x = mid.x, y = mid.y, z = mid.z }
    data.width    = #(left - right)

    -- Sequential Type Assignment
    local countBefore = #BuilderCheckpoints._checkpoints
    if countBefore == 0 then
        data.type = "START"
    else
        data.type = "FINISH"
        -- Set previous last to NORMAL if it wasn't the first
        if countBefore > 1 then
            BuilderCheckpoints._checkpoints[countBefore].type = "NORMAL"
            local sess = BuilderCore.GetSession()
            if sess and sess.checkpoints[countBefore] then 
                sess.checkpoints[countBefore].type = "NORMAL" 
            end
        end
        -- Sync first to START
        BuilderCheckpoints._checkpoints[1].type = "START"
        local sess = BuilderCore.GetSession()
        if sess and sess.checkpoints[1] then sess.checkpoints[1].type = "START" end
    end

    data.sector = BuilderCheckpoints._CalculateSector(countBefore + 1)
    
    -- Blip at midpoint
    BuilderCheckpoints._RebuildBlip(data, countBefore + 1)

    table.insert(BuilderCheckpoints._checkpoints, data)

    -- Mirror into session
    local sess = BuilderCore.GetSession()
    if sess then table.insert(sess.checkpoints, data) end

    -- Undo
    if not noUndo then
        BuilderUndo.Push({ type = BuilderUndo.ActionType.ADD_CHECKPOINT, checkpointId = data.id, before = nil, after = data })
    end

    lib.notify({ description = ("Gate #%d placed!"):format(data.id), type = "success" })
    BuilderCheckpoints._RecalculateAllSectors()
    BuilderCheckpoints._RecalculateAllBlips()
    return data
end

function BuilderCheckpoints.RemoveById(id, noUndo)
    for i, cp in ipairs(BuilderCheckpoints._checkpoints) do
        if cp.id == id then
            if cp.blip then RemoveBlip(cp.blip) end
            table.remove(BuilderCheckpoints._checkpoints, i)

            local sess = BuilderCore.GetSession()
            if sess then
                for j, scp in ipairs(sess.checkpoints) do
                    if scp.id == id then table.remove(sess.checkpoints, j) break end
                end
            end

            if #BuilderCheckpoints._checkpoints > 0 then
                for idx, scp in ipairs(BuilderCheckpoints._checkpoints) do
                    local newType = "NORMAL"
                    if idx == 1 then newType = "START"
                    elseif idx == #BuilderCheckpoints._checkpoints then newType = "FINISH" end
                    
                    scp.type = newType
                    -- Sync back to session if exists
                    local sess = BuilderCore.GetSession()
                    if sess and sess.checkpoints[idx] then
                        sess.checkpoints[idx].type = newType
                    end
                end
            end

            BuilderCheckpoints._RecalculateAllSectors()
            BuilderCheckpoints._RecalculateAllBlips()
            lib.notify({ description = "Gate removed.", type = "warning" })
            return
        end
    end
end

function BuilderCheckpoints.GetAll()    return BuilderCheckpoints._checkpoints end
function BuilderCheckpoints.DestroyAll() 
    for _, cp in ipairs(BuilderCheckpoints._checkpoints) do if cp.blip then RemoveBlip(cp.blip) end end
    BuilderCheckpoints._checkpoints = {}
    BuilderCheckpoints._nextId = 1
    BuilderCheckpoints.ExitPlacementMode()
end

-- ──────────────────────────────────────────────
-- Render Loop (Draw 3D Gates)
-- ──────────────────────────────────────────────
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local isActive = BuilderFSM and BuilderFSM.Current ~= BuilderFSM.State.IDLE
        if isActive and #BuilderCheckpoints._checkpoints > 0 then
            for i, cp in ipairs(BuilderCheckpoints._checkpoints) do
                local left = vector3(cp.left.x, cp.left.y, cp.left.z)
                local right = vector3(cp.right.x, cp.right.y, cp.right.z)
                local mid = (left + right) / 2.0

                local col = TYPE_COLOR[cp.type] or TYPE_COLOR.NORMAL
                
                -- Line between poles
                DrawLine(left.x, left.y, left.z + 1.0, right.x, right.y, right.z + 1.0, col.r, col.g, col.b, 200)
                
                -- Floating Number
                DrawText3D(mid.x, mid.y, mid.z + 2.5, ("~y~#%d~w~ [%s]"):format(i, cp.type))
                
                -- Midpoint marker
                DrawMarker(27, mid.x, mid.y, mid.z, 0,0,0, 0,0,0, 1.0, 1.0, 1.0, col.r, col.g, col.b, 80, false, false, 2, false)
            end
        else
            Wait(500)
        end
    end
end)

-- ──────────────────────────────────────────────
-- Placement Loop
-- ──────────────────────────────────────────────
function BuilderCheckpoints._RunLoop()
    Citizen.CreateThread(function()
        while BuilderCheckpoints.Active do
            Wait(0)
            local ped    = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local forward = GetEntityForwardVector(ped)
            
            -- 1. CALCULATE POSITIONS
            local center = coords + forward * BuilderCheckpoints._gateDist
            local rotRad = math.rad(BuilderCheckpoints._ghostRot)
            local dir    = vector3(math.cos(rotRad), math.sin(rotRad), 0.0)
            local leftPos  = center + dir * (BuilderCheckpoints._gateWidth / 2.0)
            local rightPos = center - dir * (BuilderCheckpoints._gateWidth / 2.0)

            -- Ensure Z-ground alignment for ghosts
            local _, gzL = GetGroundZFor_3dCoord(leftPos.x, leftPos.y, leftPos.z + 5.0, 0)
            local _, gzR = GetGroundZFor_3dCoord(rightPos.x, rightPos.y, rightPos.z + 5.0, 0)
            leftPos = vector3(leftPos.x, leftPos.y, gzL + 0.1)
            rightPos = vector3(rightPos.x, rightPos.y, gzR + 0.1)

            local style = TrackProps.GateStyles[BuilderCheckpoints._currentStyle]

            -- 2. SPAWN/UPDATE GHOSTS
            if not BuilderCheckpoints._leftEnt or not DoesEntityExist(BuilderCheckpoints._leftEnt) then
                local lHash = GetHashKey(style.left)
                lib.requestModel(lHash)
                BuilderCheckpoints._leftEnt = CreateObject(lHash, leftPos.x, leftPos.y, leftPos.z, false, false, false)
                SetEntityAlpha(BuilderCheckpoints._leftEnt, 150, false)
                FreezeEntityPosition(BuilderCheckpoints._leftEnt, true)
                SetEntityCollision(BuilderCheckpoints._leftEnt, false, false)
            end
            if not BuilderCheckpoints._rightEnt or not DoesEntityExist(BuilderCheckpoints._rightEnt) then
                local rHash = GetHashKey(style.right)
                lib.requestModel(rHash)
                BuilderCheckpoints._rightEnt = CreateObject(rHash, rightPos.x, rightPos.y, rightPos.z, false, false, false)
                SetEntityAlpha(BuilderCheckpoints._rightEnt, 150, false)
                FreezeEntityPosition(BuilderCheckpoints._rightEnt, true)
                SetEntityCollision(BuilderCheckpoints._rightEnt, false, false)
            end

            SetEntityCoordsNoOffset(BuilderCheckpoints._leftEnt, leftPos.x, leftPos.y, leftPos.z, false, false, false)
            SetEntityCoordsNoOffset(BuilderCheckpoints._rightEnt, rightPos.x, rightPos.y, rightPos.z, false, false, false)
            SetEntityRotation(BuilderCheckpoints._leftEnt, 0.0, 0.0, BuilderCheckpoints._ghostRot, 2, true)
            SetEntityRotation(BuilderCheckpoints._rightEnt, 0.0, 0.0, BuilderCheckpoints._ghostRot, 2, true)

            -- 3. CONTROLS
            
            -- MOVE DISTANCE (Arrows Up/Down)
            if IsDisabledControlPressed(0, 172) then -- Arrow Up
                BuilderCheckpoints._gateDist = BuilderCheckpoints._gateDist + 0.2
            elseif IsDisabledControlPressed(0, 173) then -- Arrow Down
                BuilderCheckpoints._gateDist = math.max(2.0, BuilderCheckpoints._gateDist - 0.2)
            end

            -- ROTATE (Arrows Left/Right)
            if IsDisabledControlPressed(0, 174) then -- Arrow Left
                BuilderCheckpoints._ghostRot = (BuilderCheckpoints._ghostRot + 2.0) % 360.0
            elseif IsDisabledControlPressed(0, 175) then -- Arrow Right
                BuilderCheckpoints._ghostRot = (BuilderCheckpoints._ghostRot - 2.0) % 360.0
            end

            -- WIDTH (Scroll Wheel)
            if IsDisabledControlPressed(0, 15) then -- Scroll Up
                BuilderCheckpoints._gateWidth = math.min(30.0, BuilderCheckpoints._gateWidth + 0.5)
            elseif IsDisabledControlPressed(0, 14) then -- Scroll Down
                BuilderCheckpoints._gateWidth = math.max(3.0, BuilderCheckpoints._gateWidth - 0.5)
            end

            -- STYLE (ALT)
            if IsDisabledControlJustPressed(0, 19) then -- Left ALT
                BuilderCheckpoints._currentStyle = (BuilderCheckpoints._currentStyle % #TrackProps.GateStyles) + 1
                local newStyle = TrackProps.GateStyles[BuilderCheckpoints._currentStyle]
                lib.notify({ description = "Style: " .. newStyle.name, type = "info" })
                -- Re-spawn on next tick
                DeleteEntity(BuilderCheckpoints._leftEnt)
                DeleteEntity(BuilderCheckpoints._rightEnt)
                BuilderCheckpoints._leftEnt = nil
                BuilderCheckpoints._rightEnt = nil
            end

            -- PLACE GATE (SHIFT + E)
            if IsDisabledControlPressed(0, 21) and IsDisabledControlJustPressed(0, 38) then -- SHIFT + E
                local id = BuilderCheckpoints._nextId
                BuilderCheckpoints._nextId = id + 1
                BuilderCheckpoints.Add({
                    id         = id,
                    left       = { x = leftPos.x, y = leftPos.y, z = leftPos.z },
                    right      = { x = rightPos.x, y = rightPos.y, z = rightPos.z },
                    styleIndex = BuilderCheckpoints._currentStyle,
                    rotation   = BuilderCheckpoints._ghostRot,
                    type       = "AUTO",
                })
                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            end

            -- REMOVE LAST (Q)
            if IsDisabledControlJustPressed(0, 44) then -- Q
                local all = BuilderCheckpoints.GetAll()
                if #all > 0 then
                    BuilderCheckpoints.RemoveById(all[#all].id)
                end
            end

            -- VISUALS: Line and markers
            DrawLine(leftPos.x, leftPos.y, leftPos.z + 1.0, rightPos.x, rightPos.y, rightPos.z + 1.0, 0, 255, 255, 200)
            DrawMarker(27, center.x, center.y, center.z, 0,0,0, 0,0,0, 1.0, 1.0, 1.0, 0, 255, 255, 150, false, false, 2, false)

            -- EXIT (RMB)
            if IsDisabledControlJustPressed(0, 25) then
                BuilderCheckpoints.ExitPlacementMode()
                BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
            end
        end
    end)
end

function BuilderCheckpoints._CalculateSector(index)
    local total = math.max(1, #BuilderCheckpoints._checkpoints + 1)
    local frac  = (index - 1) / total
    if frac < 0.33 then return 1 elseif frac < 0.66 then return 2 else return 3 end
end

function BuilderCheckpoints._RecalculateAllSectors()
    local total = #BuilderCheckpoints._checkpoints
    for i, cp in ipairs(BuilderCheckpoints._checkpoints) do
        local frac = (i - 1) / math.max(1, total)
        cp.sector = (frac < 0.33 and 1) or (frac < 0.66 and 2) or 3
    end
end

function BuilderCheckpoints._RebuildBlip(cp, index)
    if cp.blip then RemoveBlip(cp.blip) end
    local mid = cp.midpoint
    cp.blip = AddBlipForCoord(mid.x, mid.y, mid.z)
    SetBlipSprite(cp.blip, 8)
    SetBlipScale(cp.blip, 0.8)
    SetBlipColour(cp.blip, cp.type == "START" and 2 or (cp.type == "FINISH" and 1 or 5))
    local label = (cp.type == "START" and "START") or (cp.type == "FINISH" and "FINISH") or ("#" .. tostring(index))
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(cp.blip)
end

function BuilderCheckpoints._RecalculateAllBlips()
    for i, cp in ipairs(BuilderCheckpoints._checkpoints) do
        BuilderCheckpoints._RebuildBlip(cp, i)
    end
end

function DrawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString(text)
        DrawText(sx, sy)
    end
end
