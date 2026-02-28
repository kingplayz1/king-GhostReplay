-- Handles spawning and animating ghost vehicles locally

GhostPlayback = {}
GhostPlayback.ActiveGhosts = {}
GhostPlayback.LiveGhosts = {} -- Elite: { [source] = {entity, targetPos, targetRot, lastUpdate} }
GhostPlayback.Settings = {
    HologramMode = false,
    CinematicCamera = false
}

--- Utility to load a model synchronously
local function LoadModel(modelHash)
    if not IsModelInCdimage(modelHash) then return false end
    RequestModel(modelHash)
    
    local start = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(0)
        if GetGameTimer() - start > Config.ModelPreloadTimeout then
            Utils.DebugPrint("Failed to load model: " .. tostring(modelHash))
            return false
        end
    end
    return true
end

--- Start playing back a recorded ghost
-- @param ghostData Table containing `frames` (from recorder) and `model` (vehicle hash)
function GhostPlayback.Play(ghostData, trackName, autoStart)
    if autoStart == nil then autoStart = true end
    if not ghostData then return end

    -- Elite Stage 6: Handle multi-car bundles
    if ghostData.participants and #ghostData.participants > 0 then
        Utils.DebugPrint("Loading multi-car bundle (" .. #ghostData.participants .. " cars)")
        for i, pData in ipairs(ghostData.participants) do
            -- Reconstruct a temporary ghostData for the individual participant
            local instanceData = {
                model = pData.model,
                vehicleCosmetics = pData.vehicleCosmetics,
                pedAppearance = pData.pedAppearance,
                frames = pData.frames,
                name = (ghostData.name or "Ghost") .. " [" .. i .. "]",
                type = ghostData.type
            }
            GhostPlayback.SpawnInstance(instanceData, trackName, autoStart)
        end
    elseif ghostData.frames and #ghostData.frames > 0 then
        -- Legacy / Single Ghost support
        GhostPlayback.SpawnInstance(ghostData, trackName, autoStart)
    else
        Utils.DebugPrint("Cannot play ghost: invalid or empty frames.")
    end
end

function GhostPlayback.SpawnInstance(ghostData, trackName, autoStart)
    if not ghostData or not ghostData.frames then return end
    
    -- Enforce max ghosts
    local currentGhosts = 0
    for k, v in pairs(GhostPlayback.ActiveGhosts) do currentGhosts = currentGhosts + 1 end
    if currentGhosts >= Config.MaxActiveGhosts then
        Utils.DebugPrint("Cannot play ghost: reached max active ghosts limit.")
        return
    end

    local ghostId = "GHOST_" .. math.random(1000, 9999)
    ghostData.frames = Utils.UnpackFrames(ghostData.frames) -- Ensure unpacked
    
    Citizen.CreateThread(function()
        local modelHash = ghostData.model or GetHashKey("blista") -- fallback
        Utils.DebugPrint("Attempting to load vehicle model: " .. tostring(modelHash))
        if not LoadModel(modelHash) then 
            Utils.DebugPrint("ABORT: Vehicle model failed to load!")
            return 
        end
        
        local pedModel = GetHashKey("mp_m_freemode_01") -- Use more common model
        Utils.DebugPrint("Attempting to load ped model: " .. tostring(pedModel))
        if not LoadModel(pedModel) then 
            Utils.DebugPrint("ABORT: Ped model failed to load!")
            return 
        end

        local startFrame = ghostData.frames[1]
        Utils.DebugPrint("Spawning ghost instance at: " .. tostring(startFrame.pos))
        
        -- Create Vehicle locally (isNetwork = false, bScriptHostPed = false)
        local ghostVeh = CreateVehicle(modelHash, startFrame.pos.x, startFrame.pos.y, startFrame.pos.z, startFrame.rot.z, false, false)
        
        -- Create Ped locally
        local ghostPed = CreatePed(4, pedModel, startFrame.pos.x, startFrame.pos.y, startFrame.pos.z, startFrame.rot.z, false, false)
        
        if not DoesEntityExist(ghostVeh) then
            Utils.DebugPrint("ABORT: CreateVehicle returned 0! (Entity limit or distance issue)")
            return
        end
        
        -- Configure properties
        SetEntityNoCollisionEntity(ghostVeh, PlayerPedId(), false)
        SetEntityNoCollisionEntity(ghostPed, PlayerPedId(), false)
        SetVehicleDoorsLocked(ghostVeh, 10) -- Fully locked
        SetEntityInvincible(ghostVeh, true)
        SetEntityInvincible(ghostPed, true)
        SetPedIntoVehicle(ghostPed, ghostVeh, -1)
        -- Elite: Opacity set to 255 (solid) via Config
        SetEntityAlpha(ghostVeh, Config.GhostAlpha, false)
        SetEntityAlpha(ghostPed, Config.GhostAlpha, false)
        
        -- Apply cosmetics
        if ghostData.vehicleCosmetics then
            Utils.SetVehicleCosmetics(ghostVeh, ghostData.vehicleCosmetics)
        end
        if ghostData.pedAppearance then
            Utils.SetPedAppearance(ghostPed, ghostData.pedAppearance)
        end

        -- Create Minimap Blip
        local blip = AddBlipForEntity(ghostVeh)
        SetBlipSprite(blip, 225) -- Car icon
        SetBlipColour(blip, (ghostData.type == "pb") and 2 or 5) -- Green for PB, Yellow for Global
        SetBlipScale(blip, 0.7)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Ghost: " .. (ghostData.name or "Racer"))
        EndTextCommandSetBlipName(blip)

        -- Register ghost
        GhostPlayback.ActiveGhosts[ghostId] = {
            vehicle = ghostVeh,
            ped = ghostPed,
            blip = blip,
            data = ghostData,
            startTime = GetGameTimer(),
            currentTime = 0,
            currentIndex = 1,
            isPaused = not autoStart
        }
        
        Utils.DebugPrint("Started ghost playback: " .. ghostId .. " (Paused: " .. tostring(not autoStart) .. ")")
    end)
end

--- Stops a specific ghost and cleans up entities
function GhostPlayback.Stop(ghostId)
    local ghost = GhostPlayback.ActiveGhosts[ghostId]
    if not ghost then return end
    
    if DoesEntityExist(ghost.ped) then DeleteEntity(ghost.ped) end
    if ghost.blip then RemoveBlip(ghost.blip) end
    DeleteEntity(ghost.ped)
    DeleteEntity(ghost.vehicle)
    GhostPlayback.ActiveGhosts[ghostId] = nil
    Utils.DebugPrint("Stopped ghost playback: " .. ghostId)
end

--- Stops all ghosts
function GhostPlayback.StopAll()
    for id, _ in pairs(GhostPlayback.ActiveGhosts) do
        GhostPlayback.Stop(id)
    end
end

--- Toggles pause for a specific ghost
function GhostPlayback.TogglePause(ghostId, state)
    local ghost = GhostPlayback.ActiveGhosts[ghostId]
    if not ghost then return end
    
    ghost.isPaused = (state ~= nil) and state or not ghost.isPaused
    if not ghost.isPaused then
        -- Adjust startTime so playback resumes from where it paused
        ghost.startTime = GetGameTimer() - ghost.currentTime
    end
end

--- Scrubs the ghost to a relative offset in ms
function GhostPlayback.Scrub(ghostId, offsetMs)
    local ghost = GhostPlayback.ActiveGhosts[ghostId]
    if not ghost then return end
    
    ghost.currentTime = math.max(0, ghost.currentTime + offsetMs)
    if not ghost.isPaused then
        ghost.startTime = GetGameTimer() - ghost.currentTime
    end
    
    -- Reset index to force search from beginning or around current area
    ghost.currentIndex = 1 
end

--- Main interpolation thread for smooth playback
-- Runs every frame (Wait(0)) to interpolate the 25ms data
-- Elite Part 7: Performance Optimized Interpolation (v2.3)
Citizen.CreateThread(function()
    -- Native Caching for Loop Performance
    local GetGameTimer = GetGameTimer
    local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
    local SetEntityRotation = SetEntityRotation
    local SetEntityVelocity = SetEntityVelocity
    local SetVehicleSteeringAngle = SetVehicleSteeringAngle
    local SetVehicleBrakeLights = SetVehicleBrakeLights
    local PlayerPedId = PlayerPedId
    local GetEntityCoords = GetEntityCoords
    
    while true do
        Wait(0)
        local now = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for id, ghost in pairs(GhostPlayback.ActiveGhosts) do
            local frames = ghost.data.frames
            
            if not ghost.isPaused then
                ghost.currentTime = GetGameTimer() - ghost.startTime
            end

            local elapsedTime = ghost.currentTime
            
            -- Find the frame we should be at based on time
            -- Use the cached index to avoid iterating the whole table every frame
            local idx = ghost.currentIndex
            local safetyCount = 0
            while frames[idx + 1] and frames[idx + 1].time <= elapsedTime do
                idx = idx + 1
                safetyCount = safetyCount + 1
                if safetyCount > 1000 then break end -- Prevents script deadloop if elapsed time skips massively
            end
            ghost.currentIndex = idx
            
            local frameA = frames[idx]
            local frameB = frames[idx + 1]
            
            if frameB then
                -- Elite: Calculate interpolation factor t (0.0 to 1.0)
                local timeDiff = frameB.time - frameA.time
                local t = (timeDiff > 0) and ((elapsedTime - frameA.time) / timeDiff) or 0
                t = math.max(0.0, math.min(1.0, t))

                local currentPos = Utils.LerpVector3(frameA.pos, frameB.pos, t)
                
                -- Elite: Advanced Hermite Interpolation (Stage 4)
                if frameA.velocity and frameB.velocity then
                    local dt = (frameB.time - frameA.time) / 1000.0
                    currentPos = Utils.Hermite(frameA.pos, frameA.velocity, frameB.pos, frameB.velocity, dt, t)
                end

                local currentRot = vector3(Utils.LerpAngle(frameA.rot.x, frameB.rot.x, t), Utils.LerpAngle(frameA.rot.y, frameB.rot.y, t), Utils.LerpAngle(frameA.rot.z, frameB.rot.z, t))
                
                -- Elite Stage 7: Performance-Strict LOD System
                local dist = #(currentPos - playerCoords)
                local isClose = dist < 120.0
                local isMedium = dist < 200.0

                -- Only apply velocity and steering if close to the player
                if isClose then
                    local deltaT = (frameB.time - frameA.time) / 1000.0
                    if deltaT > 0 then
                        local velocity = (vector3(frameB.pos.x, frameB.pos.y, frameB.pos.z) - vector3(frameA.pos.x, frameA.pos.y, frameA.pos.z)) / deltaT
                        SetEntityVelocity(ghost.vehicle, velocity.x, velocity.y, velocity.z)
                    end
                end

                -- Primary Teleportation (Always required)
                SetEntityCoordsNoOffset(ghost.vehicle, currentPos.x, currentPos.y, currentPos.z, false, false, false)
                SetEntityRotation(ghost.vehicle, currentRot.x, currentRot.y, currentRot.z, 2, true)
                
                -- Elite: Opacity handling (v2.1 Solid Mode)
                if GhostPlayback.Settings.HologramMode then
                    -- Even in hologram mode, respect user's solid car preference if Alpha is 255
                    local pulse = Config.GhostAlpha
                    if Config.GhostAlpha < 255 then
                        pulse = math.abs(math.sin(GetGameTimer() / 500.0) * 100) + 150
                    end
                    SetEntityAlpha(ghost.vehicle, math.floor(pulse), false)
                    SetEntityAlpha(ghost.ped, math.floor(pulse), false)
                    
                    -- Neon Glow (Blue for WR, Red for PB)
                    local r, g, b = 0, 150, 255 
                    if ghost.data.type == "pb" then r, g, b = 255, 50, 50 end
                    SetVehicleCustomPrimaryColour(ghost.vehicle, r, g, b)
                    SetVehicleCustomSecondaryColour(ghost.vehicle, r, g, b)
                else
                    SetEntityAlpha(ghost.vehicle, Config.GhostAlpha, false)
                    SetEntityAlpha(ghost.ped, Config.GhostAlpha, false)
                end

                if isClose then
                    SetVehicleSteeringAngle(ghost.vehicle, Utils.Lerp(frameA.steering, frameB.steering, t))
                    
                    -- Wheel and Suspension Sync
                    if frameA.wheelRots and frameB.wheelRots then
                        for i = 0, 3 do
                            if frameA.wheelRots[i] and frameB.wheelRots[i] and SetVehicleWheelRotation then
                                SetVehicleWheelRotation(ghost.vehicle, i, Utils.Lerp(frameA.wheelRots[i], frameB.wheelRots[i], t))
                            end
                            if frameA.suspension and frameB.suspension and frameA.suspension[i] and frameB.suspension[i] and SetVehicleWheelSuspensionCompression then
                                SetVehicleWheelSuspensionCompression(ghost.vehicle, i, Utils.Lerp(frameA.suspension[i], frameB.suspension[i], t))
                            end
                        end
                    end

                    -- Convertible Roof Sync
                    if frameA.roof ~= nil then
                        local currentRoof = GetConvertibleRoofState(ghost.vehicle)
                        if frameA.roof ~= currentRoof then
                            if frameA.roof == 0 or frameA.roof == 3 then
                                RaiseConvertibleRoof(ghost.vehicle, false)
                            elseif frameA.roof == 1 or frameA.roof == 2 then
                                LowerConvertibleRoof(ghost.vehicle, false)
                            end
                        end
                    end

                    -- Advanced Telemetry Application (Inspired by SP GhostReplay)
                    if frameA.indL ~= nil then SetVehicleIndicatorLights(ghost.vehicle, 1, frameA.indL) end
                    if frameA.indR ~= nil then SetVehicleIndicatorLights(ghost.vehicle, 0, frameA.indR) end
                    
                    if frameA.siren ~= nil then 
                        SetVehicleSiren(ghost.vehicle, frameA.siren)
                        if frameA.siren then
                            SetVehicleHasMutedSirens(ghost.vehicle, false)
                        end
                    end

                    if frameA.lights ~= nil then
                        if frameA.lights == 0 then
                            SetVehicleLights(ghost.vehicle, 0)
                        elseif frameA.lights == 1 then
                            SetVehicleLights(ghost.vehicle, 2) -- Forced on
                        elseif frameA.lights == 2 then
                            SetVehicleLights(ghost.vehicle, 3) -- High beams
                        end
                    end

                    if frameA.braking then
                        SetVehicleBrakeLights(ghost.vehicle, true)
                    else
                        SetVehicleBrakeLights(ghost.vehicle, false)
                    end
                end
            else
                -- Playback reached the end
                GhostPlayback.Stop(id)
            end
        end
    end
end)

-- Ensure cleanup if resource restarts
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        GhostPlayback.StopAll()
    end
end)

-- Elite: Handle Live Telemetry from other players (Stage 3)
RegisterNetEvent("GhostReplay:Client:ReceiveLivePacket")
AddEventHandler("GhostReplay:Client:ReceiveLivePacket", function(src, trackName, packet)
    if not TrackSystem.CurrentTrack or TrackSystem.CurrentTrack.name ~= trackName then return end
    if src == GetPlayerServerId(PlayerId()) then return end

    if not GhostPlayback.LiveGhosts[src] then
        lib.requestModel(packet.model)
        local entity = CreateVehicle(packet.model, packet.pos.x, packet.pos.y, packet.pos.z, packet.rot.z, false, false)
        SetEntityAlpha(entity, Config.GhostAlpha, false)
        SetEntityNoCollisionEntity(entity, PlayerPedId(), false)
        SetVehicleDoorsLocked(entity, 10)
        SetEntityInvincible(entity, true)
        
        GhostPlayback.LiveGhosts[src] = {
            entity = entity,
            targetPos = vector3(packet.pos.x, packet.pos.y, packet.pos.z),
            targetRot = vector3(packet.rot.x, packet.rot.y, packet.rot.z),
            targetVel = vector3(packet.velocity.x, packet.velocity.y, packet.velocity.z),
            lastUpdate = GetGameTimer()
        }
    else
        local lg = GhostPlayback.LiveGhosts[src]
        lg.targetPos = vector3(packet.pos.x, packet.pos.y, packet.pos.z)
        lg.targetRot = vector3(packet.rot.x, packet.rot.y, packet.rot.z)
        lg.targetVel = vector3(packet.velocity.x, packet.velocity.y, packet.velocity.z)
        lg.lastUpdate = GetGameTimer()
    end
end)

-- Elite: Live Ghost Update Loop (Stage 3, 4 & 7 Optimized)
Citizen.CreateThread(function()
    local GetGameTimer = GetGameTimer
    local GetEntityCoords = GetEntityCoords
    local PlayerPedId = PlayerPedId
    local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
    local SetEntityRotation = SetEntityRotation
    local DoesEntityExist = DoesEntityExist
    local DeleteEntity = DeleteEntity

    while true do
        local now = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        for src, lg in pairs(GhostPlayback.LiveGhosts) do
            if now - lg.lastUpdate > 5000 then
                if DoesEntityExist(lg.entity) then DeleteEntity(lg.entity) end
                GhostPlayback.LiveGhosts[src] = nil
            else
                if DoesEntityExist(lg.entity) then
                    local currentPos = GetEntityCoords(lg.entity)
                    local dist = #(lg.targetPos - playerCoords)
                    
                    -- Optimization: Faster Lerp for far ghosts, Hermite for close ones
                    local lerpFactor = (dist < 50.0) and 0.2 or 0.1
                    local newPos = currentPos + (lg.targetPos - currentPos) * lerpFactor
                    
                    SetEntityCoordsNoOffset(lg.entity, newPos.x, newPos.y, newPos.z, false, false, false)
                    SetEntityRotation(lg.entity, lg.targetRot.x, lg.targetRot.y, lg.targetRot.z, 2, true)
                end
            end
        end
        Wait(0)
    end
end)
