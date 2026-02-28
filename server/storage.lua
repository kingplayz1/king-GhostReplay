-- Handles saving and loading the ghost data JSON file

Storage = {}
Storage.Laps = {} -- memory cache of the JSON file map: trackName -> {time, ghostData}
Storage.Tracks = {} -- memory cache of the JSON file map: trackId -> trackDefinition

local function GetSavePath(file)
    return GetResourcePath(GetCurrentResourceName()) .. "/" .. file
end

function Storage.Init()
    -- Load Laps
    local fileContentLaps = LoadResourceFile(GetCurrentResourceName(), Config.DataFile)
    if fileContentLaps and fileContentLaps ~= "" then
        local success, decoded = pcall(json.decode, fileContentLaps)
        if success and decoded then
            Storage.Laps = decoded
            print("^2[GhostReplay Server]^7 Loaded " .. Config.DataFile .. " successfully.")
        else
            print("^1[GhostReplay Server]^7 Failed to parse " .. Config.DataFile)
        end
    else
        Storage.Laps = {}
        Storage.SaveToDisk("laps")
    end

    -- Load Tracks
    local fileContentTracks = LoadResourceFile(GetCurrentResourceName(), Config.TracksFile)
    if fileContentTracks and fileContentTracks ~= "" then
        local success, decoded = pcall(json.decode, fileContentTracks)
        if success and decoded then
            Storage.Tracks = decoded
            print("^2[GhostReplay Server]^7 Loaded " .. Config.TracksFile .. " successfully. (" .. #Storage.Tracks .. " tracks)")
        else
            print("^1[GhostReplay Server]^7 Failed to parse " .. Config.TracksFile)
        end
    else
        Storage.Tracks = {}
        Storage.SaveToDisk("tracks")
    end
end

function Storage.SaveToDisk(type)
    if type == "laps" then
        local encoded = json.encode(Storage.Laps)
        SaveResourceFile(GetCurrentResourceName(), Config.DataFile, encoded, -1)
    elseif type == "tracks" then
        local encoded = json.encode(Storage.Tracks)
        SaveResourceFile(GetCurrentResourceName(), Config.TracksFile, encoded, -1)
    end
end

function Storage.GetTrackData(trackName)
    return Storage.Laps[trackName]
end

function Storage.GetAllTracks()
    return Storage.Tracks
end

function Storage.SaveNewTrack(trackDef)
    table.insert(Storage.Tracks, trackDef)
    Storage.SaveToDisk("tracks")
end

--- Validates and saves a new lap time
-- @param trackName Name of the track
-- @param time The lap time in ms
-- @param ghostData The telemetry table (frames, model)
-- @return boolean true if it was a new record
function Storage.UpdateLap(trackName, time, ghostData)
    local currentRecord = Storage.Laps[trackName]
    
    if not currentRecord or time < currentRecord.time then
        Storage.Laps[trackName] = {
            time = time,
            ghostData = ghostData
        }
        Storage.SaveToDisk("laps")
        print("^2[GhostReplay Server]^7 New record saved for " .. trackName .. ": " .. time .. "ms")
        return true
    end
    
    return false
end

-- Load data on start
Citizen.CreateThread(function()
    Storage.Init()
end)
