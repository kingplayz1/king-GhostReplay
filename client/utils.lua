-- High-Performance Math and Utilities for GhostReplay

Utils = {}

--- Calculates cross product of 2D vectors (ignoring Z for track line crossing)
-- Used for determining which side of a line segment a point is on
-- Positive = Left, Negative = Right, 0 = Collinear
function Utils.CrossProduct2D(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end

--- Checks if a line segment AC intersects with segment BD
function Utils.IsLineIntersecting(a, b, c, d)
    local cp1 = Utils.CrossProduct2D(a, b, c)
    local cp2 = Utils.CrossProduct2D(a, b, d)
    local cp3 = Utils.CrossProduct2D(c, d, a)
    local cp4 = Utils.CrossProduct2D(c, d, b)

    if ((cp1 > 0 and cp2 < 0) or (cp1 < 0 and cp2 > 0)) and 
       ((cp3 > 0 and cp4 < 0) or (cp3 < 0 and cp4 > 0)) then
        return true
    end
    return false
end

--- Determines if movement from oldPos to newPos crossed line segment defined by (lineLeft, lineRight)
-- For a start/finish line defined left-to-right from driver's perspective
-- we can enforce directionality based on the crossing vector
function Utils.CrossedLine(oldPos, newPos, lineLeft, lineRight)
    -- First check basic intersection
    if not Utils.IsLineIntersecting(oldPos, newPos, lineLeft, lineRight) then
        return false, 0
    end
    
    -- Determine direction of crossing
    -- If driver crosses Left-to-Right segment from behind, the cross product of 
    -- (lineRight - lineLeft) and (newPos - oldPos) will be positive (depending on cord system, adjust appropriately)
    local lineVec = { x = lineRight.x - lineLeft.x, y = lineRight.y - lineLeft.y }
    local moveVec = { x = newPos.x - oldPos.x, y = newPos.y - oldPos.y }
    
    local cross = (lineVec.x * moveVec.y) - (lineVec.y * moveVec.x)
    
    -- Return true if intersected, and the cross product to indicate direction (1 or -1)
    return true, (cross > 0 and 1 or -1)
end

--- Linear interpolation between two numbers
function Utils.Lerp(a, b, t)
    return a + (b - a) * t
end

--- Spherical linear interpolation between two vectors (for rotations)
-- FiveM handles heading mostly, but proper quaternion or vector lerping is cleaner
function Utils.LerpVector3(v1, v2, t)
    return vector3(
        Utils.Lerp(v1.x, v2.x, t),
        Utils.Lerp(v1.y, v2.y, t),
        Utils.Lerp(v1.z, v2.z, t)
    )
end

--- Angle interpolation that wraps correctly around 360 degrees
function Utils.LerpAngle(startAngle, endAngle, t)
    local difference = (endAngle - startAngle) % 360
    if difference > 180.0 then
        difference = difference - 360.0
    end
    return startAngle + (difference * t)
end

--- Captures essential vehicle modifications
function Utils.GetVehicleCosmetics(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    local colorPrimary, colorSecondary = GetVehicleColours(vehicle)
    local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)
    local interiorColor = GetVehicleInteriorColor(vehicle)
    local dashboardColor = GetVehicleDashboardColor(vehicle)
    
    return {
        colors = {colorPrimary, colorSecondary},
        extraColors = {pearlescentColor, wheelColor},
        interiorColor = interiorColor,
        dashboardColor = dashboardColor,
        wheelType = GetVehicleWheelType(vehicle),
        plateText = GetVehicleNumberPlateText(vehicle),
        plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        liveries = GetVehicleLivery(vehicle)
    }
end

--- Applies captured modifications to a vehicle
function Utils.SetVehicleCosmetics(vehicle, data)
    if not DoesEntityExist(vehicle) or not data then return end
    SetVehicleModKit(vehicle, 0)
    SetVehicleColours(vehicle, data.colors[1], data.colors[2])
    SetVehicleExtraColours(vehicle, data.extraColors[1], data.extraColors[2])
    SetVehicleInteriorColor(vehicle, data.interiorColor)
    SetVehicleDashboardColor(vehicle, data.dashboardColor)
    SetVehicleNumberPlateText(vehicle, data.plateText)
    SetVehicleNumberPlateTextIndex(vehicle, data.plateIndex)
    SetVehicleWindowTint(vehicle, data.windowTint)
    if data.liveries then SetVehicleLivery(vehicle, data.liveries) end
end

--- Captures ped clothing and props
function Utils.GetPedAppearance(ped)
    if not DoesEntityExist(ped) then return nil end
    local components = {}
    for i = 0, 11 do
        components[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end
    
    local props = {}
    for i = 0, 2 do -- Hat, Glasses, Ears
        props[i] = {
            drawable = GetPedPropIndex(ped, i),
            texture = GetPedPropTextureIndex(ped, i)
        }
    end
    
    return {
        model = GetEntityModel(ped),
        components = components,
        props = props
    }
end

--- Applies captured appearance to a ped
function Utils.SetPedAppearance(ped, data)
    if not DoesEntityExist(ped) or not data then return end
    for i, comp in pairs(data.components) do
        SetPedComponentVariation(ped, i, comp.drawable, comp.texture, comp.palette)
    end
    for i, prop in pairs(data.props) do
        if prop.drawable ~= -1 then
            SetPedPropIndex(ped, i, prop.drawable, prop.texture, true)
        else
            ClearPedProp(ped, i)
        end
    end
end

--- High-Efficiency Frame Packing (Elite 100% Phase)
--- Strips keys and converts frames to a flat numerical array
function Utils.PackFrames(frames)
    if not frames or #frames == 0 then return nil end
    local packed = {}
    for i, f in ipairs(frames) do
        local frameArray = {
            f.time,                             -- 1
            f.pos.x, f.pos.y, f.pos.z,           -- 2,3,4
            f.rot.x, f.rot.y, f.rot.z,           -- 5,6,7
            f.steering or 0,                    -- 8
            f.braking and 1 or 0,               -- 9
            f.rpm or 0,                         -- 10
            f.gear or 0,                        -- 11
            f.throttle or 0,                    -- 12
            f.siren and 1 or 0,                 -- 13
            f.indL and 1 or 0,                  -- 14
            f.indR and 1 or 0,                  -- 15
            f.lights or 0,                      -- 16
            f.roof or -1,                       -- 17
            f.velocity and f.velocity.x or 0,    -- 18
            f.velocity and f.velocity.y or 0,    -- 19
            f.velocity and f.velocity.z or 0,    -- 20
        }
        
        -- Append Wheels (21-24)
        if f.wheelRots then
            for j = 0, 3 do table.insert(frameArray, f.wheelRots[j] or 0) end
        else
            for j = 0, 3 do table.insert(frameArray, 0) end
        end
        
        -- Append Suspension (25-28)
        if f.suspension then
            for j = 0, 3 do table.insert(frameArray, f.suspension[j] or 0) end
        else
            for j = 0, 3 do table.insert(frameArray, 0) end
        end
        
        table.insert(packed, frameArray)
    end
    return packed
end

--- Unpacks high-efficiency arrays back into frame objects
function Utils.UnpackFrames(packed)
    if not packed or #packed == 0 then return nil end
    local frames = {}
    for i, p in ipairs(packed) do
        -- Check if it's already unpacked (backward compatibility)
        if type(p) == "table" and p.time then return packed end
        
        local frame = {
            time = p[1],
            pos = vector3(p[2], p[3], p[4]),
            rot = vector3(p[5], p[6], p[7]),
            steering = p[8],
            braking = p[9] == 1,
            rpm = p[10],
            gear = p[11],
            throttle = p[12],
            siren = p[13] == 1,
            indL = p[14] == 1,
            indR = p[15] == 1,
            lights = p[16],
            roof = (p[17] == -1) and nil or p[17],
            velocity = vector3(p[18], p[19], p[20]),
            wheelRots = {[0] = p[21], [1] = p[22], [2] = p[23], [3] = p[24]},
            suspension = {[0] = p[25], [1] = p[26], [2] = p[27], [3] = p[28]}
        }
        table.insert(frames, frame)
    end
    return frames
end

--- Elite: Calculates the distance from a point to a line segment
--- Used for Anti-Shortcut corridors
function Utils.GetDistanceToSegment(p, a, b)
    local ab = b - a
    local ap = p - a
    local t = dot(ap, ab) / dot(ab, ab)
    t = math.max(0, math.min(1, t))
    local closestPoint = a + t * ab
    return #(p - closestPoint)
end

--- Elite: Cubic Hermite Spline Interpolation for smooth movement
--- p0: Start Pos, v0: Start Velocity, p1: End Pos, v1: End Velocity, dt: Delta Time, t: Interp Factor (0-1)
function Utils.Hermite(p0, v0, p1, v1, dt, t)
    local t2 = t * t
    local t3 = t2 * t
    
    local h1 = 2*t3 - 3*t2 + 1
    local h2 = -2*t3 + 3*t2
    local h3 = t3 - 2*t2 + t
    local h4 = t3 - t2
    
    return p0 * h1 + p1 * h2 + v0 * dt * h3 + v1 * dt * h4
end

--- Elite: Ray-casting algorithm to detect if a point is inside a polygon
--- Used for Anti-Cut zones
function Utils.IsPointInPolygon(p, polygon)
    local isInside = false
    local j = #polygon
    for i = 1, #polygon do
        if ((polygon[i].y > p.y) ~= (polygon[j].y > p.y)) and
           (p.x < (polygon[j].x - polygon[i].x) * (p.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x) then
            isInside = not isInside
        end
        j = i
    end
    return isInside
end

--- Elite: Analyzes track geometry to provide metadata (Distance, Elevation, Difficulty)
function Utils.AnalyzeTrack(trackData)
    local waypoints = trackData.waypoints
    if #waypoints < 2 then return nil end

    local totalDistance = 0
    local totalElevationGain = 0
    local totalAngle = 0
    local turnCount = 0

    local startPos = vector3(trackData.startLine.left.x, trackData.startLine.left.y, trackData.startLine.left.z)
    local prevPos = startPos

    for i, wp in ipairs(waypoints) do
        local currentPos = vector3(wp.x, wp.y, wp.z)
        local dist = #(currentPos - prevPos)
        totalDistance = totalDistance + dist

        -- Elevation
        local elevationDiff = currentPos.z - prevPos.z
        if elevationDiff > 0 then
            totalElevationGain = totalElevationGain + elevationDiff
        end

        -- Turns and Curvature
        if i > 1 then
            local nextPos = waypoints[i+1] and vector3(waypoints[i+1].x, waypoints[i+1].y, waypoints[i+1].z)
            if nextPos then
                local v1 = currentPos - prevPos
                local v2 = nextPos - currentPos
                local angle = math.abs(math.deg(math.acos(dot(norm(v1), norm(v2)))))
                
                if angle > 15.0 then -- Threshold for a "Turn"
                    turnCount = turnCount + 1
                    totalAngle = totalAngle + angle
                end
            end
        end

        prevPos = currentPos
    end

    -- Add distance to finish line
    local flPos = vector3(trackData.finishLine.left.x, trackData.finishLine.left.y, trackData.finishLine.left.z)
    totalDistance = totalDistance + #(flPos - prevPos)

    -- Classification Logic
    local avgCurvature = totalAngle / (totalDistance / 1000) -- Angle per km
    local class = "Balanced"
    
    if totalDistance < 800 and turnCount <= 2 then
        class = "Drag"
    elseif avgCurvature > 300 then
        class = "Technical"
    elseif avgCurvature < 100 then
        class = "High Speed"
    end

    return {
        distance = totalDistance,
        elevation = totalElevationGain,
        turns = turnCount,
        curvature = avgCurvature,
        class = class
    }
end

function Utils.DebugPrint(msg)
    if Config.Debug then
        print("^3[GhostReplay]^7 " .. tostring(msg))
    end
end
