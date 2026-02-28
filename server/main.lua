-- Main server events and network receivers

RegisterNetEvent("GhostReplay:Server:SaveGhostData")
AddEventHandler("GhostReplay:Server:SaveGhostData", function(trackName, ghostData)
    local src = source
    if not trackName or not ghostData then return end
    
    -- Use the time provided by the client (with penalties) if available
    local lapTimeMs = ghostData.time or (#ghostData.frames * Config.Timestep)
    
    -- Global Record check
    local isNewRecord = Storage.UpdateLap(trackName, lapTimeMs, ghostData)
    
    -- Personal Best check
    local license = GetPlayerIdentifierByType(src, 'license')
    local isNewPB = Storage.UpdatePB(license, trackName, lapTimeMs, ghostData)

    if isNewRecord then
        TriggerClientEvent("chat:addMessage", -1, {
            color = {255, 215, 0},
            multiline = true,
            args = {"[Ghost Racing]", "Player " .. GetPlayerName(src) .. " set a new GLOBAL record on " .. trackName .. " (" .. (lapTimeMs/1000) .. "s)!"}
        })
    elseif isNewPB then
        TriggerClientEvent("chat:addMessage", src, {
            color = {0, 255, 0},
            multiline = true,
            args = {"[Ghost Racing]", "You set a new Personal Best on " .. trackName .. " (" .. (lapTimeMs/1000) .. "s)!"}
        })
    end
end)

RegisterNetEvent("GhostReplay:Server:RequestGhostData")
AddEventHandler("GhostReplay:Server:RequestGhostData", function(trackName, type)
    local src = source
    local type = type or "global"
    local record = nil
    
    if type == "global" then
        record = Storage.GetTrackData(trackName)
    elseif type == "pb" then
        local license = GetPlayerIdentifierByType(src, 'license')
        record = Storage.GetPB(license, trackName)
    end
    
    if record and record.ghostData then
        -- Add metadata for client to label the ghost
        record.ghostData.type = type
        record.ghostData.name = (type == "global") and "World Record" or "Personal Best"
        
        print("^3[GhostReplay Server]^7 Sending " .. type .. " ghost data for " .. trackName .. " to player " .. src)
        TriggerClientEvent("GhostReplay:Client:ReceiveGhostData", src, trackName, record.ghostData)
    else
        print("^3[GhostReplay Server]^7 No " .. type .. " ghost found for " .. trackName .. " requested by player " .. src)
        TriggerClientEvent("GhostReplay:Client:ReceiveGhostData", src, trackName, nil)
    end
end)
RegisterNetEvent("GhostReplay:Server:RequestLeaderboard")
AddEventHandler("GhostReplay:Server:RequestLeaderboard", function(trackName)
    local src = source
    local global = Storage.GetTrackData(trackName)
    local license = GetPlayerIdentifierByType(src, 'license')
    local pb = Storage.GetPB(license, trackName)
    
    TriggerClientEvent("GhostReplay:Client:ReceiveLeaderboard", src, trackName, {
        global = global and global.time or nil,
        pb = pb and pb.time or nil
    })
end)

RegisterNetEvent("GhostReplay:Server:RequestGridStart")
AddEventHandler("GhostReplay:Server:RequestGridStart", function(trackName)
    local src = source
    local coords = GetEntityCoords(GetPlayerPed(src))
    
    -- Coordinate all players within 30m of the requester
    local players = GetPlayers()
    for _, player in ipairs(players) do
        local pPed = GetPlayerPed(player)
        local pCoords = GetEntityCoords(pPed)
        if #(coords - pCoords) < 30.0 then
            TriggerClientEvent("GhostReplay:Client:StartCountdown", player, trackName)
        end
    end
end)

-- Elite: Live Ghost Streaming Rebroadcast
RegisterNetEvent("GhostReplay:Server:StreamPacket")
AddEventHandler("GhostReplay:Server:StreamPacket", function(trackName, packet)
    local src = source
    -- Rebroadcast to everyone on the same track (except sender)
    TriggerClientEvent("GhostReplay:Client:ReceiveLivePacket", -1, src, trackName, packet)
end)
