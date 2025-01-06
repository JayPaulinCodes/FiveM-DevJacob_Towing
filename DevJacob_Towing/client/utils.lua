local _CACHE = {}

function getHash(str)
    _CACHE.Hashes = _CACHE.Hashes or {}

    if not _CACHE.Hashes[str] then
        _CACHE.Hashes[str] = joaat(str)
    end

    return _CACHE.Hashes[str]
end

function isModelHashValid(hash)
    _CACHE.ValidModelHashes = _CACHE.ValidModelHashes or {}

    if not _CACHE.ValidModelHashes[hash] then
        _CACHE.ValidModelHashes[hash] = IsModelValid(hash) or IsModelInCdimage(hash)
    end

    return _CACHE.ValidModelHashes[hash]
end

function groundCoords(coords, maxRetries, retryCount)
    _CACHE.GroundAtCoords = _CACHE.GroundAtCoords or {}

	retryCount = retryCount or 0
	maxRetries = maxRetries or 3
	local origCoords = coords
	coords = vector3(round(coords.x, 1), round(coords.y, 1), round(coords.z, 1))
	local key = vector2(coords.x, coords.y)
	local _result = function(z)
		return vector3(origCoords.x, origCoords.y, z)
	end

	-- Check the cache
	if _CACHE.GroundAtCoords[key] ~= nil then
		return _result(_CACHE.GroundAtCoords[key])
	end
	
	-- Try to fetch
	RequestCollisionAtCoord(coords.x, coords.y, coords.x)
	local fetchSuccessful, zCoord = GetGroundZExcludingObjectsFor_3dCoord(coords.x, coords.y, coords.z, true)

	-- If the fetch failed, and we are still able to retry, try again
	if not fetchSuccessful and retryCount < maxRetries then
		return groundCoords(origCoords, maxRetries, retryCount + 1)
	end

	-- If the fetch was successful cache the result, otherwise default
	if fetchSuccessful then
		_CACHE.GroundAtCoords[key] = zCoord
		return _result(zCoord)
	else
		local playerPos = GetEntityCoords(PlayerPedId())
		return _result(playerPos.z - 0.9)
	end
end

function loadRopeTexturesAsync(timeout)
    timeout = timeout or 1000
    local _promise = promise.new()

    local runFunc = function()
        -- Check if the textures are loaded
        if not RopeAreTexturesLoaded(modelHash) then
            _promise:resolve(true)
        end

        -- Try to load the textures
        local timer = 0
        while not RopeAreTexturesLoaded(modelHash) and timer < timeout do
            RopeLoadTextures(modelHash)
            timer = timer + 1
            Citizen.Wait(1)
        end

        local result = RopeAreTexturesLoaded(modelHash)
        _promise:resolve(result == 1)
    end

    runFunc()
    return _promise
end

function requestModelAsync(modelName, timeout)
    timeout = timeout or 1000
    local _promise = promise.new()

    local runFunc = function()
        -- Get the hash for the model
        local modelHash = type(modelName) == "string" and getHash(modelName) or modelName
        
        -- Get the model validity state
        local modelValid = isModelHashValid(modelHash)

        -- Check if the model is valid
        if not modelValid then
            _promise:resolve(false)
        end

        -- Check if the model is loaded
        if HasModelLoaded(modelHash) then
            _promise:resolve(true)
        end

        -- Try to requets the model
        local timer = 0
        while not HasModelLoaded(modelHash) and timer < timeout do
            RequestModel(modelHash)
            timer = timer + 1
            Citizen.Wait(1)
        end

        local result = HasModelLoaded(modelHash)
        _promise:resolve(result == 1)
    end

    runFunc()
    return _promise
end

function drawText2DThisFrame(drawOptions)
    -- Validate the draw options
    if drawOptions.coords == nil then error("Missing options field \"coords\", it must be a valid vector3 or vector2 object!", 2) end
    local coords = drawOptions.coords

    if drawOptions.text == nil or drawOptions.text == "" then error("Missing options field \"text\", it must be a valid string!", 2) end
    local text = drawOptions.text
    
    local colour = drawOptions.colour or { r = 255, g = 255, b = 255, a = 215 }
    local scale = drawOptions.scale or 0.35
    local outline = drawOptions.outline or false
    local font = drawOptions.font or 4
    local alignment = drawOptions.alignment or 1

    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextColour(colour.r, colour.g, colour.b, colour.a)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 255)
    SetTextDropShadow()
    if outline == true then SetTextOutline() end

    if alignment == 0 or alignment == 2 then
        SetTextJustification(alignment)

        if alignment == 2 then
            SetTextWrap(0, coords.x)
        end
    end 

    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(coords.x, coords.y)
end