Config = {}

-- Determines the recording granularity (milliseconds per frame)
-- 25ms = 40 Hz, which is a good balance between accuracy and data size.
Config.Timestep = 25

-- The maximum length of a recording in seconds to prevent memory overflow
-- default 15 minutes (900 seconds) = 36000 frames at 25ms.
Config.MaxRecordingTimeSeconds = 900

-- Playback visual settings
Config.GhostAlpha = 255 -- Solid cars (100% opaque)
Config.MaxActiveGhosts = 15 -- Max ghost cars playing at once (session chase)

-- Model cache config
Config.ModelPreloadTimeout = 5000 -- Max ms to wait for a model to load before giving up

-- Server storage configuration
Config.DataFile = "ghost_data.json"
Config.TracksFile = "tracks.json"

-- Runtime Optimization
Config.TrackLoadRadius = 200.0 -- Player must be within this distance (meters) to the start line to activate checking

-- Debug mode for console prints
Config.Debug = true
