-- Handles spawning and animating ghost vehicles locally

GhostPlayback = {}
GhostPlayback.ActiveGhosts = {}

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
function GhostPlayback.Play(ghostData, trackName)
    if not ghostData or not ghostData.frames or #ghostData.frames == 0 then
        Utils.DebugPrint("Cannot play ghost: invalid data.")
        return
    end
    
    -- Enforce max ghosts
    local currentGhosts = 0
    for k, v in pairs(GhostPlayback.ActiveGhosts) do currentGhosts = currentGhosts + 1 end
    if currentGhosts >= Config.MaxActiveGhosts then
        Utils.DebugPrint("Cannot play ghost: reached max active ghosts limit.")
        return
    end

    local ghostId = tostring(#GhostPlayback.ActiveGhosts + 1) .. "_" .. tostring(GetGameTimer())
    
    Citizen.CreateThread(function()
        local modelHash = ghostData.model or GetHashKey("blista") -- fallback
        if not LoadModel(modelHash) then return end
        
        local pedModel = GetHashKey("a_m_m_stig_01")
        if not LoadModel(pedModel) then return end

        local startFrame = ghostData.frames[1]
        
        -- Create Vehicle locally (isNetwork = false, bScriptHostPed = false)
        local ghostVeh = CreateVehicle(modelHash, startFrame.pos.x, startFrame.pos.y, startFrame.pos.z, startFrame.rot.z, false, false)
        
        -- Create Ped locally
        local ghostPed = CreatePed(4, pedModel, startFrame.pos.x, startFrame.pos.y, startFrame.pos.z, startFrame.rot.z, false, false)
        
        -- Configure properties
        SetEntityNoCollisionEntity(ghostVeh, PlayerPedId(), false)
        SetEntityNoCollisionEntity(ghostPed, PlayerPedId(), false)
        SetEntityCollision(ghostVeh, false, false)
        SetEntityCollision(ghostPed, false, false)
        SetEntityInvincible(ghostVeh, true)
        SetEntityInvincible(ghostPed, true)
        SetEntityAlpha(ghostVeh, Config.GhostAlpha, false)
        SetEntityAlpha(ghostPed, Config.GhostAlpha, false)
        FreezeEntityPosition(ghostVeh, true) -- We control position manually
        SetPedIntoVehicle(ghostPed, ghostVeh, -1)
        SetBlockingOfNonTemporaryEvents(ghostPed, true)
        
        -- Clean up memory
        SetModelAsNoLongerNeeded(modelHash)
        SetModelAsNoLongerNeeded(pedModel)
        
        -- Register ghost
        GhostPlayback.ActiveGhosts[ghostId] = {
            vehicle = ghostVeh,
            ped = ghostPed,
            data = ghostData,
            startTime = GetGameTimer(),
            currentIndex = 1
        }
        
        Utils.DebugPrint("Started ghost playback: " .. ghostId)
    end)
end

--- Stops a specific ghost and cleans up entities
function GhostPlayback.Stop(ghostId)
    local ghost = GhostPlayback.ActiveGhosts[ghostId]
    if not ghost then return end
    
    if DoesEntityExist(ghost.ped) then DeleteEntity(ghost.ped) end
    if DoesEntityExist(ghost.vehicle) then DeleteEntity(ghost.vehicle) end
    
    GhostPlayback.ActiveGhosts[ghostId] = nil
    Utils.DebugPrint("Stopped and cleaned up ghost: " .. ghostId)
end

--- Stops all ghosts
function GhostPlayback.StopAll()
    for id, _ in pairs(GhostPlayback.ActiveGhosts) do
        GhostPlayback.Stop(id)
    end
end

--- Main interpolation thread for smooth playback
-- Runs every frame (Wait(0)) to interpolate the 25ms data
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local now = GetGameTimer()
        
        for id, ghost in pairs(GhostPlayback.ActiveGhosts) do
            local frames = ghost.data.frames
            local elapsedTime = now - ghost.startTime
            
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
                -- Interpolate between frameA and frameB
                local timeDiff = frameB.time - frameA.time
                local t = (timeDiff > 0) and ((elapsedTime - frameA.time) / timeDiff) or 0
                
                -- Clamp t between 0 and 1
                t = math.max(0.0, math.min(1.0, t))
                
                local currentPos = Utils.LerpVector3(frameA.pos, frameB.pos, t)
                local currentRot = Utils.LerpVector3(frameA.rot, frameB.rot, t)
                
                -- Update Vehicle
                -- FreezeEntityPosition must be true for SetEntityCoordsNoOffset to purely control the ped
                SetEntityCoordsNoOffset(ghost.vehicle, currentPos.x, currentPos.y, currentPos.z, false, false, false)
                SetEntityRotation(ghost.vehicle, currentRot.x, currentRot.y, currentRot.z, 2, true)
                
                SetVehicleSteeringAngle(ghost.vehicle, Utils.Lerp(frameA.steering, frameB.steering, t))
                if frameA.braking then
                    SetVehicleBrakeLights(ghost.vehicle, true)
                else
                    SetVehicleBrakeLights(ghost.vehicle, false)
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
