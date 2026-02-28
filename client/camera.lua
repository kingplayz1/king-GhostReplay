-- Cinematic Replay Camera for GhostReplay
GhostCamera = {}
GhostCamera.Active = false
local cam = nil

function GhostCamera.Toggle(state)
    GhostCamera.Active = (state ~= nil) and state or not GhostCamera.Active
    
    if not GhostCamera.Active then
        if cam then
            RenderScriptCams(false, true, 500, true, true)
            DestroyCam(cam, true)
            cam = nil
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if GhostCamera.Active then
            -- Find the first active ghost to follow
            local targetGhost = nil
            for id, ghost in pairs(GhostPlayback.ActiveGhosts) do
                targetGhost = ghost
                break
            end

            if targetGhost and DoesEntityExist(targetGhost.vehicle) then
                if not cam then
                    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
                    SetCamActive(cam, true)
                    RenderScriptCams(true, true, 500, true, true)
                end

                local vehCoords = GetEntityCoords(targetGhost.vehicle)
                local offset = GetOffsetFromEntityInWorldCoords(targetGhost.vehicle, -5.0, -10.0, 3.0)
                
                -- Smoothly follow with offset
                SetCamCoord(cam, offset.x, offset.y, offset.z)
                PointCamAtEntity(cam, targetGhost.vehicle, 0.0, 0.0, 0.0, true)
            else
                -- No ghost found, disable cam
                if cam then
                    RenderScriptCams(false, true, 500, true, true)
                    DestroyCam(cam, true)
                    cam = nil
                end
            end
        else
            Wait(500)
        end
    end
end)
