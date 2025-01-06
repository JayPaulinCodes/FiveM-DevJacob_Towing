Logger = {}
Logger.__index = Logger

function Logger.Debug(message, ...)
    if Config.DebugMode == true then
		print(("DEBUG: " .. message):format(...))
    end
end

function Logger.Info(message, ...)
    print(("INFO: " .. message):format(...))
end

function Logger.Warning(message, ...)
    print(("WARNING: " .. message):format(...))
end

function Logger.Error(message, ...)
    print(("ERROR: " .. message):format(...))
end


function toInputString(cmd)
    local hexStr = ("%x"):format(joaat(cmd))
    local formattedHex = hexStr:sub(-8):upper()
    return ("INPUT_%s"):format(formattedHex)
end

function lerp(a, b, t)
    return a + (b - a) * t
end

function lerpVector3(vectorA, vectorB, lerpVal)
    if vectorB == 0.0 or vectorB == nil then
        return vector3(lerp(vectorA.x, 0.0, lerpVal), lerp(vectorA.y, 0.0, lerpVal), lerp(vectorA.z, 0.0, lerpVal))
    elseif vectorA == 0.0 or vectorA == nil then
        return vector3(lerp(0.0, vectorB.x, lerpVal), lerp(0.0, vectorB.y, lerpVal), lerp(0.0, vectorB.z, lerpVal))
    else
        return vector3(lerp(vectorA.x, vectorB.x, lerpVal), lerp(vectorA.y, vectorB.y, lerpVal), lerp(vectorA.z, vectorB.z, lerpVal))
    end
end

function getOffsetFromCoordsInWorldCoords(position, rotation, offset)
    local rotX = math.rad(rotation.x)
    local rotY = math.rad(rotation.y)
    local rotZ = math.rad(rotation.z)

    local matrix = {
        {
            math.cos(rotZ) * math.cos(rotY) - math.sin(rotZ) * math.sin(rotX) * math.sin(rotY),
            math.cos(rotY) * math.sin(rotZ) + math.cos(rotZ) * math.sin(rotX) * math.sin(rotY),
            (-1 * math.cos(rotX)) * math.sin(rotY),
            1
        },
        {
            (-1 * math.cos(rotX)) * math.sin(rotZ),
            math.cos(rotZ) * math.cos(rotX),
            math.sin(rotX),
            1
        },
        {
            math.cos(rotZ) * math.sin(rotY) + math.cos(rotY) * math.sin(rotZ) * math.sin(rotX),
            math.sin(rotZ) * math.sin(rotY) - math.cos(rotZ) * math.cos(rotY) * math.sin(rotX),
            math.cos(rotX) * math.cos(rotY),
            1
        },
        {
            position.x,
            position.y,
            position.z,
            1
        }
    }

    local x = offset.x * matrix[1][1] + offset.y * matrix[2][1] + offset.z * matrix[3][1] + matrix[4][1]
    local y = offset.x * matrix[1][2] + offset.y * matrix[2][2] + offset.z * matrix[3][2] + matrix[4][2]
    local z = offset.x * matrix[1][3] + offset.y * matrix[2][3] + offset.z * matrix[3][3] + matrix[4][3]

    return vector3(x, y, z)
end

function getOppositeRotationValue(rotVal)
    return rotVal + (180.0 * ternary(rotVal < 0.0, 1, -1))
end

function getOffsetBetweenRotValues(rotVal1, rotVal2)
    local a = rotVal1
    local c = rotVal2
    local b = c - a
    return b
end

function getOffsetBetweenRotations(rot1, rot2)
    return vector3(
        getOffsetBetweenRotValues(rot1.x, rot2.x),
        getOffsetBetweenRotValues(rot1.y, rot2.y),
        getOffsetBetweenRotValues(rot1.z, rot2.z)
    )
end

function ternary(condition, trueValue, falseValue)
    if condition then
        return trueValue
    else
        return falseValue
    end
end

function round(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end