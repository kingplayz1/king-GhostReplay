-- Main server events and network receivers

RegisterNetEvent("GhostReplay:Server:SaveGhostData")
AddEventHandler("GhostReplay:Server:SaveGhostData", function(trackName, ghostData)
    local src = source
    if not trackName or not ghostData then return end
    
    -- In a full implementation, the time should be validated server-side,
    -- but for performance this zero-overhead system relies on client trust for the time recording.
    -- ghostData.time could be sent alongside, or we calculate it from the array length:
    local framesCount = #ghostData.frames
    local lapTimeMs = framesCount * Config.Timestep
    
    local isNewRecord = Storage.UpdateLap(trackName, lapTimeMs, ghostData)
    
    if isNewRecord then
        TriggerClientEvent("chat:addMessage", -1, {
            color = {255, 215, 0},
            multiline = true,
            args = {"[Ghost Racing]", "Player " .. GetPlayerName(src) .. " set a new record on " .. trackName .. " (" .. (lapTimeMs/1000) .. "s)!"}
        })
    end
end)

RegisterNetEvent("GhostReplay:Server:RequestGhostData")
AddEventHandler("GhostReplay:Server:RequestGhostData", function(trackName)
    local src = source
    local record = Storage.GetTrackData(trackName)
    
    if record and record.ghostData then
        -- Send data to the requesting client ONLY
        print("^3[GhostReplay Server]^7 Sending ghost data for " .. trackName .. " to player " .. src)
        TriggerClientEvent("GhostReplay:Client:ReceiveGhostData", src, trackName, record.ghostData)
    else
        print("^3[GhostReplay Server]^7 No ghost data found for " .. trackName .. " requested by player " .. src)
        TriggerClientEvent("GhostReplay:Client:ReceiveGhostData", src, trackName, nil)
    end
end)
