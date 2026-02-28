-- Handles receiving and broadcasting custom tracks

RegisterNetEvent("GhostReplay:Server:SaveTrack")
AddEventHandler("GhostReplay:Server:SaveTrack", function(trackPayload)
    local src = source
    if not trackPayload or not trackPayload.name then return end
    
    -- Generate a simple unique ID for the track
    trackPayload.id = "track_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    trackPayload.creator = GetPlayerName(src)
    
    -- Save it to the JSON array via Storage
    Storage.SaveNewTrack(trackPayload)
    
    print("^2[GhostReplay Server]^7 New track created: " .. trackPayload.name .. " (" .. trackPayload.id .. ") by " .. trackPayload.creator)
    
    -- Broadcast the new track to all online clients so they can cache it
    TriggerClientEvent("GhostReplay:Client:SyncNewTrack", -1, trackPayload)
    
    -- Notify the creator
    TriggerClientEvent("chat:addMessage", src, {
        color = {0, 255, 0},
        args = {"[Track Builder]", "Successfully saved track: " .. trackPayload.name}
    })
end)

-- Send all tracks to a player when they join
-- In a real framework, you'd hook this to playerSpawned or similar
RegisterNetEvent("GhostReplay:Server:RequestAllTracks")
AddEventHandler("GhostReplay:Server:RequestAllTracks", function()
    local src = source
    local allTracks = Storage.GetAllTracks()
    if allTracks and #allTracks > 0 then
        TriggerClientEvent("GhostReplay:Client:SyncAllTracks", src, allTracks)
        print("^3[GhostReplay Server]^7 Sent " .. #allTracks .. " tracks to player " .. src)
    end
end)
