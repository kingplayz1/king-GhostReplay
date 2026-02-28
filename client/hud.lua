-- Delta/Gap HUD for GhostReplay
GhostHUD = {}
GhostHUD.Visible = true -- For Gap HUD
GhostHUD.LabelsVisible = true -- For 3D Names

local function DrawText2D(x, y, text, scale, color)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(color.r, color.g, color.b, color.a or 255)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(color.centre or false)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local violationNotice = { text = "", time = 0, color = {r=255, g=255, b=255} }

AddEventHandler("GhostReplay:Client:OnViolation", function(reason, isFatal)
    violationNotice.text = reason
    violationNotice.time = GetGameTimer() + 3000
    violationNotice.color = isFatal and {r=255, g=50, b=50} or {r=255, g=200, b=50}
    
    if isFatal then
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_SHOP_SOUNDSET", 1)
    else
        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
    end
end)

local countdownNotice = { text = "", time = 0, color = {r=255, g=255, b=255} }

AddEventHandler("GhostReplay:Client:OnCountdownTick", function(text, color)
    countdownNotice.text = text
    countdownNotice.time = GetGameTimer() + 1000
    countdownNotice.color = color
end)

local function DrawText3D(x, y, z, text, r, g, b)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(r, g, b, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 0, 0, 0, 100)
    end
end

local sectorNotification = { text = "", time = 0, color = {r=255,g=255,b=255} }

RegisterNetEvent("GhostReplay:Client:OnSectorComplete")
AddEventHandler("GhostReplay:Client:OnSectorComplete", function(num, timeMs)
    local bestGhostDelta = nil
    for _, ghost in pairs(GhostPlayback.ActiveGhosts) do
        -- Find frame at this sector (approximate by time)
        -- In an ideal world, we'd have exact ghost sector times. 
        -- For now, we compare current session times.
        local delta = (timeMs - ghost.currentTime) / 1000.0
        if bestGhostDelta == nil or math.abs(delta) < math.abs(bestGhostDelta) then
            bestGhostDelta = delta
        end
    end

    if bestGhostDelta then
        local sign = bestGhostDelta > 0 and "+" or "-"
        local color = bestGhostDelta > 0 and {r=255,g=50,b=50} or {r=50,g=255,b=50}
        sectorNotification.text = string.format("SECTOR %d: %s%.2fs", num, sign, math.abs(bestGhostDelta))
        sectorNotification.time = GetGameTimer() + 3000
        sectorNotification.color = color
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        -- Draw Floating Labels
        if GhostHUD.LabelsVisible then
            for _, ghost in pairs(GhostPlayback.ActiveGhosts) do
                if DoesEntityExist(ghost.vehicle) then
                    local coords = GetEntityCoords(ghost.vehicle)
                    local dist = #(coords - GetEntityCoords(PlayerPedId()))
                    if dist < 50.0 then
                        local color = (ghost.data.type == "pb") and {r=100, g=255, b=100} or {r=255, g=200, b=50}
                        local label = string.format("%s (%s)", ghost.data.name or "Racer", (ghost.data.type == "pb" and "PB" or "WR"))
                        DrawText3D(coords.x, coords.y, coords.z + 1.2, label, color.r, color.g, color.b)
                    end
                end
            end
        end

        -- Draw Sector Notification
        if GetGameTimer() < sectorNotification.time then
            DrawText2D(0.45, 0.2, sectorNotification.text, 0.6, {r=sectorNotification.color.r, g=sectorNotification.color.g, b=sectorNotification.color.b, a=255})
        end

        -- Draw Violation Notice (v1.6 Elite)
        if GetGameTimer() < violationNotice.time then
            DrawText2D(0.5, 0.3, violationNotice.text, 0.8, {r=violationNotice.color.r, g=violationNotice.color.g, b=violationNotice.color.b, a=255, centre=true})
        end

        -- Draw Countdown (Elite Grid)
        if GetGameTimer() < countdownNotice.time then
            DrawText2D(0.5, 0.4, countdownNotice.text, 2.5, {r=countdownNotice.color.r, g=countdownNotice.color.g, b=countdownNotice.color.b, a=255, centre=true})
        end

        -- Draw Recording Indicator (v1.6)
        if GhostRecorder.IsRecording then
            local alpha = math.floor(math.abs(math.sin(GetGameTimer() / 300.0) * 200) + 55)
            DrawText2D(0.02, 0.05, "● RECORDING", 0.5, {r=255, g=50, b=50, a=alpha})
        end

        if GhostHUD.Visible and (TrackSystem.IsRacing or GhostRecorder.IsRecording) then
            local pTime = 0
            local timerColor = {r=255, g=255, b=255}
            
            if TrackSystem.IsRacing then
                pTime = GetGameTimer() - TrackSystem.LapStartTime
                -- Elite: Stain timer red if lap is dirty
                if TrackSystem.IsLapDirty then
                    timerColor = {r=255, g=50, b=50}
                end
            elseif GhostRecorder.IsRecording then
                pTime = GetGameTimer() - GhostRecorder.RecordStartTime
            end
            
            local timeStr = string.format("%02d:%02d.%02d", 
                math.floor(pTime / 60000), 
                math.floor((pTime % 60000) / 1000), 
                math.floor((pTime % 1000) / 10))
            
            DrawText2D(0.46, 0.9, timeStr, 0.7, timerColor)

            local closestDelta = nil
            local ghostName = ""

            for _, ghost in pairs(GhostPlayback.ActiveGhosts) do
                -- Compare ghost's currentTime vs player's current session time
                -- Note: This assumes they are roughly synced on the track
                local delta = (pTime - ghost.currentTime) / 1000.0
                
                if closestDelta == nil or math.abs(delta) < math.abs(closestDelta) then
                    closestDelta = delta
                    ghostName = ghost.data.name or "Racer"
                end
            end

            if closestDelta then
                local color = {r = 255, g = 255, b = 255, a = 200}
                local sign = ""
                if closestDelta > 0 then
                    color = {r = 255, g = 50, b = 50, a = 255} -- Slower (Red)
                    sign = "+"
                elseif closestDelta < 0 then
                    color = {r = 50, g = 255, b = 50, a = 255} -- Faster (Green)
                    sign = "-"
                end

                local text = string.format("%s: %s%.2fs", ghostName, sign, math.abs(closestDelta))
                DrawText2D(0.45, 0.9, text, 0.45, color)
            end
        end
    end
end)
