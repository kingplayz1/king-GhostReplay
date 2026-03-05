-- ============================================================
-- GhostReplay Builder v2: Server-Side Track CRUD
-- Handles SaveTrackV2, RequestTrack, ListTracks, DeleteTrack
-- Full schema with metadata, sectors, props, and checkpoints
-- ============================================================

local _trackDatabase = nil  -- Cached in-memory table

-- ── Load tracks from disk on startup ──
local function _Load()
    if _trackDatabase then return _trackDatabase end
    local raw = LoadResourceFile(GetCurrentResourceName(), "tracks.json")
    if raw and raw ~= "" then
        local ok, data = pcall(json.decode, raw)
        _trackDatabase = (ok and type(data) == "table") and data or {}
    else
        _trackDatabase = {}
    end
    return _trackDatabase
end

local function _Save()
    local ok, encoded = pcall(json.encode, _trackDatabase)
    if ok then SaveResourceFile(GetCurrentResourceName(), "tracks.json", encoded, -1) end
end

local function _GenerateId()
    return "trk_" .. os.time() .. "_" .. tostring(math.random(10000, 99999))
end

-- ── SAVE TRACK V2 ──
RegisterNetEvent("GhostReplay:Server:SaveTrackV2")
AddEventHandler("GhostReplay:Server:SaveTrackV2", function(payload)
    local src = source
    if not payload or not payload.name then
        TriggerClientEvent("GhostReplay:Client:TrackSaveFailed", src, "Invalid payload received.")
        return
    end

    -- Basic server-side validation
    if #(payload.name) < 3 then
        TriggerClientEvent("GhostReplay:Client:TrackSaveFailed", src, "Track name too short.")
        return
    end

    local cps = payload.checkpoints or {}
    if #cps < 2 then
        TriggerClientEvent("GhostReplay:Client:TrackSaveFailed", src, "Minimum 2 checkpoints required.")
        return
    end

    local tracks = _Load()

    -- Build full record
    local record = {
        track_id         = _GenerateId(),
        track_name       = payload.name,
        description      = payload.description or "",
        creator          = GetPlayerName(src) or "Unknown",
        creator_license  = GetPlayerIdentifierByType(src, "license") or "",
        date_created     = os.date("%Y-%m-%d %H:%M:%S"),
        track_distance   = payload.metadata and payload.metadata.distance or 0,
        checkpoint_count = #cps,
        difficulty       = payload.metadata and payload.metadata.class or "Unknown",
        difficulty_score = payload.metadata and payload.metadata.difficulty or 0,
        track_data       = {
            checkpoints  = cps,
            props        = payload.props or {},
            antiCutZones = payload.antiCutZones or {},
            metadata     = payload.metadata or {},
        }
    }

    table.insert(tracks, record)
    _Save()

    print(("^2[Tracks] Saved '%s' (ID: %s) by %s — %d checkpoints, %d props^7"):format(
        record.track_name, record.track_id, record.creator,
        #cps, #(payload.props or {})))

    -- Notify creator
    TriggerClientEvent("GhostReplay:Client:TrackSaved", src, record.track_id)

    -- Broadcast to all online clients so they cache the new track
    TriggerClientEvent("GhostReplay:Client:SyncNewTrack", -1, record)
end)

-- ── LIST ALL TRACKS (summary, not full data) ──
RegisterNetEvent("GhostReplay:Server:ListTracks")
AddEventHandler("GhostReplay:Server:ListTracks", function()
    local src = source
    local tracks = _Load()
    local summaries = {}
    for _, t in ipairs(tracks) do
        table.insert(summaries, {
            track_id         = t.track_id,
            track_name       = t.track_name,
            creator          = t.creator,
            date_created     = t.date_created,
            track_distance   = t.track_distance,
            checkpoint_count = t.checkpoint_count,
            difficulty       = t.difficulty,
            difficulty_score = t.difficulty_score,
        })
    end
    TriggerClientEvent("GhostReplay:Client:TrackList", src, summaries)
end)

-- ── REQUEST SPECIFIC TRACK (full data) ──
RegisterNetEvent("GhostReplay:Server:RequestTrack")
AddEventHandler("GhostReplay:Server:RequestTrack", function(trackId)
    local src = source
    local tracks = _Load()
    for _, t in ipairs(tracks) do
        if t.track_id == trackId then
            TriggerClientEvent("GhostReplay:Client:TrackData", src, t)
            return
        end
    end
    TriggerClientEvent("GhostReplay:Client:TrackNotFound", src, trackId)
end)

-- ── DELETE TRACK (admin only) ──
RegisterNetEvent("GhostReplay:Server:DeleteTrack")
AddEventHandler("GhostReplay:Server:DeleteTrack", function(trackId)
    local src = source
    -- Simple admin check: IsPlayerAceAllowed
    if not IsPlayerAceAllowed(src, "ghostreplay.deletetrack") then
        TriggerClientEvent("GhostReplay:Client:TrackSaveFailed", src, "No permission to delete tracks.")
        return
    end

    local tracks = _Load()
    for i, t in ipairs(tracks) do
        if t.track_id == trackId then
            table.remove(tracks, i)
            _Save()
            TriggerClientEvent("GhostReplay:Client:TrackDeleted", src, trackId)
            print(("^1[Tracks] Track '%s' deleted by %s^7"):format(trackId, GetPlayerName(src)))
            return
        end
    end
    TriggerClientEvent("GhostReplay:Client:TrackSaveFailed", src, "Track not found: " .. trackId)
end)

-- ── REQUEST ALL TRACKS (legacy compat) ──
RegisterNetEvent("GhostReplay:Server:RequestAllTracks")
AddEventHandler("GhostReplay:Server:RequestAllTracks", function()
    local src = source
    local tracks = _Load()
    TriggerClientEvent("GhostReplay:Client:SyncAllTracks", src, tracks)
end)
