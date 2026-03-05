-- ============================================================
-- GhostReplay Builder v2: Track Metadata Analyser
-- Computes distance, elevation, turns, curvature, top speed
-- sections, and auto-classifies the track type
-- ============================================================

BuilderAnalysis = {}

-- ── Main analysis entry point ──
-- session: { checkpoints = [], props = [] }
-- Returns a metadata table
function BuilderAnalysis.Analyze(session)
    local cps = session and session.checkpoints or {}
    if #cps < 2 then return nil end

    local totalDistance    = 0.0
    local totalElevation   = 0.0
    local totalAngle       = 0.0
    local turnCount        = 0
    local maxStraightLen   = 0.0
    local curStraight      = 0.0
    local sectors          = { {dist=0}, {dist=0}, {dist=0} }

    local prevPos  = vector3(cps[1].midpoint.x, cps[1].midpoint.y, cps[1].midpoint.z)
    local prevDir  = nil

    for i = 2, #cps do
        local cp  = cps[i]
        local pos = vector3(cp.midpoint.x, cp.midpoint.y, cp.midpoint.z)

        local dist = #(pos - prevPos)
        totalDistance = totalDistance + dist

        -- Elevation
        local dz = pos.z - prevPos.z
        if dz > 0 then totalElevation = totalElevation + dz end

        -- Sector distance
        local sector = math.max(1, math.min(3, cp.sector or 1))
        sectors[sector].dist = sectors[sector].dist + dist

        -- Turn detection
        local curDir = (pos - prevPos)
        local curLen = #curDir
        if curLen > 0.01 then curDir = curDir / curLen end

        if prevDir ~= nil then
            local dotVal  = math.max(-1, math.min(1, prevDir.x * curDir.x + prevDir.y * curDir.y + prevDir.z * curDir.z))
            local angleDeg = math.deg(math.acos(dotVal))

            if angleDeg > 15.0 then
                turnCount    = turnCount + 1
                totalAngle   = totalAngle + angleDeg
                maxStraightLen = math.max(maxStraightLen, curStraight)
                curStraight    = 0.0
            else
                curStraight = curStraight + dist
            end
        end

        prevDir = curDir
        prevPos = pos
    end

    maxStraightLen = math.max(maxStraightLen, curStraight)

    -- Curvature: total angle change per km
    local avgCurvature = 0.0
    if totalDistance > 0 then
        avgCurvature = totalAngle / (totalDistance / 1000.0)
    end

    -- Estimate top speed section (longer straights  → higher raw speed)
    local estimatedTopSpeed = 120 + math.floor(maxStraightLen / 5)

    -- ── Classification ──
    local class = "Balanced"
    if totalDistance < 800 and turnCount <= 2 then
        class = "Drag"
    elseif avgCurvature > 300 then
        class = "Technical"
    elseif avgCurvature < 100 then
        class = "High Speed"
    elseif totalElevation < 5.0 and avgCurvature >= 150 and avgCurvature <= 300 then
        class = "Drift"
    end

    -- ── Difficulty Score (1–10) ──
    local difficulty = math.min(10, math.floor(
        (turnCount * 0.5) + (totalElevation * 0.05) + (avgCurvature * 0.01)
    ))

    local meta = {
        distance         = math.floor(totalDistance * 10) / 10,
        elevation        = math.floor(totalElevation * 10) / 10,
        turns            = turnCount,
        avgCurvature     = math.floor(avgCurvature * 10) / 10,
        maxStraightLen   = math.floor(maxStraightLen * 10) / 10,
        estimatedTopSpeed = estimatedTopSpeed,
        class            = class,
        difficulty       = difficulty,
        sectors          = sectors,
        checkpointCount  = #cps,
        propCount        = session.props and #session.props or 0,
    }

    print(("[BuilderAnalysis] Class: %s | %.0fm | %d turns | Curvature: %.0f°/km"):format(
        meta.class, meta.distance, meta.turns, meta.avgCurvature))

    return meta
end

-- ── Format as human-readable summary ──
function BuilderAnalysis.FormatSummary(meta)
    if not meta then return "No data." end
    return string.format(
        "🏎 %s Track | %.0fm | %d Turns | %.0f°/km | Difficulty: %d/10 | Top Speed: ~%d km/h",
        meta.class, meta.distance, meta.turns, meta.avgCurvature, meta.difficulty, meta.estimatedTopSpeed
    )
end
