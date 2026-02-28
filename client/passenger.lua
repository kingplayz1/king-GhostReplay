-- Allows player to ride inside a ghost vehicle
PassengerMode = {}
PassengerMode.IsActive = false
PassengerMode.GhostID = nil
PassengerMode.OriginalVeh = nil
PassengerMode.OriginalCoords = nil

function PassengerMode.Enter(ghostId)
    if PassengerMode.IsActive then return end
    
    local ghost = GhostPlayback.ActiveGhosts[ghostId]
    if not ghost then 
        lib.notify({description = "No ghost found to spectate.", type = "error"})
        return 
    end

    local ped = PlayerPedId()
    PassengerMode.IsActive = true
    PassengerMode.GhostID = ghostId
    PassengerMode.OriginalVeh = GetVehiclePedIsIn(ped, false)
    PassengerMode.OriginalCoords = GetEntityCoords(ped)

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    -- Hide original vehicle or ped safely
    if PassengerMode.OriginalVeh ~= 0 then
        SetEntityVisible(PassengerMode.OriginalVeh, false, false)
        SetEntityCollision(PassengerMode.OriginalVeh, false, false)
        FreezeEntityPosition(PassengerMode.OriginalVeh, true)
    end
    SetEntityVisible(ped, false, false)

    -- Teleport into ghost
    SetPedIntoVehicle(ped, ghost.vehicle, 0) -- Seat 0 is Passenger
    
    -- Sync camera
    NetworkSetInSpectatorMode(true, ghost.vehicle)

    DoScreenFadeIn(500)
    lib.notify({description = "Entered Passenger Mode. Press ESC or Menu to exit.", type = "info"})
end

function PassengerMode.Exit()
    if not PassengerMode.IsActive then return end

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, 0)

    -- Restore visibility
    if PassengerMode.OriginalVeh ~= 0 and DoesEntityExist(PassengerMode.OriginalVeh) then
        SetEntityVisible(PassengerMode.OriginalVeh, true, false)
        SetEntityCollision(PassengerMode.OriginalVeh, true, true)
        FreezeEntityPosition(PassengerMode.OriginalVeh, false)
        SetPedIntoVehicle(ped, PassengerMode.OriginalVeh, -1)
    else
        SetEntityCoords(ped, PassengerMode.OriginalCoords.x, PassengerMode.OriginalCoords.y, PassengerMode.OriginalCoords.z, false, false, false, false)
        SetEntityVisible(ped, true, false)
    end

    PassengerMode.IsActive = false
    PassengerMode.GhostID = nil

    DoScreenFadeIn(500)
    lib.notify({description = "Exited Passenger Mode.", type = "info"})
end

-- Command to toggle easily
RegisterCommand("ghostride", function()
    if PassengerMode.IsActive then
        PassengerMode.Exit()
    else
        -- Pick first active ghost
        for id, _ in pairs(GhostPlayback.ActiveGhosts) do
            PassengerMode.Enter(id)
            break
        end
    end
end, false)
