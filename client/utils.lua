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

function Utils.DebugPrint(msg)
    if Config.Debug then
        print("^3[GhostReplay]^7 " .. tostring(msg))
    end
end
