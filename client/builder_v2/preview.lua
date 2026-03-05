-- ============================================================
-- GhostReplay Builder v2: Preview & Simulation Mode
-- Test-drive mode: temporary checkpoints, lap timer, ESC to return
-- ============================================================

BuilderPreview = {
    _active          = false,
    _simActive       = false,
    _tempCheckpoints = {},  -- CreateCheckpointEx handles
    _startTime       = 0,
    _lastCheckpoint  = 0,
    _lapTime         = 0,
}

-- ──────────────────────────────────────────────
-- Start preview (test-drive without saving)
-- ──────────────────────────────────────────────
function BuilderPreview.Start()
    BuilderPreview._active = true

    -- Close NUI panel
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "minimizeBuilder" })

    -- Spawn temporary in-game gate props
    local cps = BuilderCheckpoints.GetAll()
    BuilderPreview._tempCheckpoints = {}

    for i, cp in ipairs(cps) do
        local style = TrackProps.GateStyles[cp.styleIndex]
        local lHash, rHash = GetHashKey(style.left), GetHashKey(style.right)
        lib.requestModel(lHash); lib.requestModel(rHash)

        local lObj = CreateObject(lHash, cp.left.x, cp.left.y, cp.left.z, false, false, false)
        local rObj = CreateObject(rHash, cp.right.x, cp.right.y, cp.right.z, false, false, false)
        SetEntityRotation(lObj, 0.0, 0.0, cp.rotation, 2, true)
        SetEntityRotation(rObj, 0.0, 0.0, cp.rotation, 2, true)
        FreezeEntityPosition(lObj, true); FreezeEntityPosition(rObj, true)

        table.insert(BuilderPreview._tempCheckpoints, { 
            lObj = lObj, 
            rObj = rObj, 
            data = cp 
        })
    end

    -- Reset lap timer
    BuilderPreview._startTime      = GetGameTimer()
    BuilderPreview._lastCheckpoint = 0

    -- Teleport to first gate Midpoint
    if cps[1] then
        local m   = cps[1].midpoint
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local targetPos = vector3(m.x, m.y, m.z + 1.0)
        
        if veh and veh ~= 0 then
            SetEntityCoords(veh, targetPos.x, targetPos.y, targetPos.z)
            SetEntityRotation(veh, 0.0, 0.0, cps[1].rotation, 2, true)
        else
            SetEntityCoords(ped, targetPos.x, targetPos.y, targetPos.z)
            SetEntityHeading(ped, cps[1].rotation)
        end
    end

    lib.notify({ title = "Preview Mode", description = "Test your gates! Press ESC to exit.", type = "info" })
    BuilderPreview._RunPreviewLoop()
end

function BuilderPreview.Stop()
    -- Delete temp gate props
    for _, cp in ipairs(BuilderPreview._tempCheckpoints) do
        if cp.lObj then DeleteEntity(cp.lObj) end
        if cp.rObj then DeleteEntity(cp.rObj) end
    end
    BuilderPreview._tempCheckpoints = {}
    BuilderPreview._active    = false
    BuilderPreview._simActive = false

    SendNUIMessage({ action = "restoreBuilder" })
    Utils.HideHint()
end

-- ──────────────────────────────────────────────
-- Preview Loop
-- ──────────────────────────────────────────────
function BuilderPreview._RunPreviewLoop()
    Citizen.CreateThread(function()
        while BuilderPreview._active do
            Wait(0)

            local ped      = PlayerPedId()
            local currentPos = GetEntityCoords(ped)
            
            -- Draw lap timer
            local elapsed = GetGameTimer() - BuilderPreview._startTime
            local elapsedStr = BuilderPreview._FormatTime(elapsed)

            SetTextFont(4)
            SetTextScale(0.6, 0.6)
            SetTextColour(255, 255, 0, 255)
            SetTextCentre(true)
            SetTextEntry("STRING")
            AddTextComponentString("🏁 PREVIEW: " .. elapsedStr)
            DrawText(0.5, 0.05)

            -- Render lines and Checkpoint detection
            for i, cp in ipairs(BuilderPreview._tempCheckpoints) do
                local left = vector3(cp.data.left.x, cp.data.left.y, cp.data.left.z)
                local right = vector3(cp.data.right.x, cp.data.right.y, cp.data.right.z)
                local mid = (left + right) / 2.0

                -- Draw visual line
                DrawLine(left.x, left.y, left.z + 1.0, right.x, right.y, right.z + 1.0, 255, 255, 0, 200)

                -- Detection logic
                local d = #(currentPos - mid)
                if d < 30.0 then
                    local crossed, direction = Utils.CrossedLine(BuilderPreview._lastPos or currentPos, currentPos, left, right)
                    if crossed and direction > 0 then
                        if i > BuilderPreview._lastCheckpoint then
                            BuilderPreview._lastCheckpoint = i

                            if cp.data.type == "FINISH" or i == #BuilderPreview._tempCheckpoints then
                                local lapStr = BuilderPreview._FormatTime(elapsed)
                                lib.notify({ title = "Finish Crossed!", description = "Time: " .. lapStr, type = "success" })
                            end

                            PlaySoundFrontend(-1, "RACE_PLACE", "HUD_FRONTEND_CUSTOM_SOUND_01", false)
                        end
                    end
                end
            end

            BuilderPreview._lastPos = currentPos

            -- ESC to exit preview
            if IsDisabledControlJustPressed(0, 200) then -- ESC
                BuilderPreview.Stop()
                BuilderFSM.SetState(BuilderFSM.State.PROP_PREVIEW)
            end
        end
    end)
end

function BuilderPreview._FormatTime(ms)
    local secs = math.floor(ms / 1000)
    local mil  = ms % 1000
    local m    = math.floor(secs / 60)
    local s    = secs % 60
    return string.format("%02d:%02d.%03d", m, s, mil)
end
