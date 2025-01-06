local currentTowTruck = nil
local canOperateBed = false
local movementControls = {
    lowerBed = false,
    raiseBed = false,
}

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if currentTowTruck ~= nil then
        currentTowTruck:Destroy()
    end
end)

-- Vehicle detection thread
Citizen.CreateThread(function()
    while true do
        Wait(100)
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, true)
        
        -- Check if we got a return on the vehicle
        if vehicle == 0 then
            goto continue
        end

        -- Check if the vehicle is a tow truck
        local vehicleHash = GetEntityModel(vehicle)
        local towTruckConfig = Config.TowTrucks[vehicleHash]
        if towTruckConfig == nil then
            if currentTowTruck ~= nil then
                currentTowTruck:SetAction(TowTruck.ACTION.NONE)
            else
                canOperateBed = false
            end
            goto continue
        end

        -- Ensure we have control of the entity
        if not NetworkHasControlOfEntity(vehicle) then
            if currentTowTruck ~= nil then
                currentTowTruck:SetAction(TowTruck.ACTION.NONE)
            else
                canOperateBed = false
            end
            goto continue
        end

        -- Create the truck object
        if currentTowTruck == nil then
            currentTowTruck = TowTruck.new(towTruckConfig, vehicle)
        else
            local vehicleNetId = VehToNet(vehicle)
            if currentTowTruck.truckNetId ~= vehicleNetId then
                currentTowTruck = TowTruck.new(towTruckConfig, vehicle)
            end
        end

        -- Check if the player can operate the bed
        if currentTowTruck ~= nil then
            local lastVehIsTruck = currentTowTruck.truckHandle == vehicle
            local isInSeat = playerPed == GetPedInVehicleSeat(vehicle, -1)
            
            canOperateBed = lastVehIsTruck and (isInSeat or currentTowTruck:CanControlBed())

            if not canOperateBed then
                currentTowTruck:SetAction(TowTruck.ACTION.NONE)
            end
        end

        ::continue::
    end
end)

local function OnCommandBedRaise_Down()
    -- Ensure the current tow truck exists
    if currentTowTruck == nil then
        return
    end
    
    -- Check if the player can operate the bed
    if not canOperateBed then 
        return
    end

    -- Ensure the other movement key isn't in use
    if movementControls.lowerBed == true then
        return
    end

    movementControls.raiseBed = true
    currentTowTruck:SetAction(TowTruck.ACTION.RAISING)
end

local function OnCommandBedRaise_Up()
    -- Ensure the current tow truck exists
    if currentTowTruck == nil then
        return
    end

    -- Ensure the the movement key is infact in use
    if movementControls.raiseBed == false then
        return
    end

    movementControls.raiseBed = false
    currentTowTruck:SetAction(TowTruck.ACTION.NONE)
end

local function OnCommandBedLower_Down()
    -- Ensure the current tow truck exists
    if currentTowTruck == nil then
        return
    end
    
    -- Check if the player can operate the bed
    if not canOperateBed then 
        return
    end

    -- Ensure the other movement key isn't in use
    if movementControls.raiseBed == true then
        return
    end

    movementControls.lowerBed = true
    currentTowTruck:SetAction(TowTruck.ACTION.LOWERING)
end

local function OnCommandBedLower_Up()
    -- Ensure the current tow truck exists
    if currentTowTruck == nil then
        return
    end

    -- Ensure the the movement key is infact in use
    if movementControls.lowerBed == false then
        return
    end

    movementControls.lowerBed = false
    currentTowTruck:SetAction(TowTruck.ACTION.NONE)
end

RegisterKeyMapping("+towingBedLower", "Lower Tow Truck Bed", "KEYBOARD", "PAGEDOWN")
RegisterKeyMapping("~!+towingBedLower", "Lower Tow Truck Bed - Alternate Key", "KEYBOARD", "RBRACKET")
RegisterCommand("+towingBedLower", OnCommandBedLower_Down)
RegisterCommand("-towingBedLower", OnCommandBedLower_Up)
RegisterCommand("~!+towingBedLower", OnCommandBedLower_Down)
RegisterCommand("~!-towingBedLower", OnCommandBedLower_Up)

RegisterKeyMapping("+towingBedRaise", "Raise Tow Truck Bed", "KEYBOARD", "PAGEUP")
RegisterKeyMapping("~!+towingBedRaise", "Raise Tow Truck Bed - Alternate Key", "KEYBOARD", "LBRACKET")
RegisterCommand("+towingBedRaise", OnCommandBedRaise_Down)
RegisterCommand("-towingBedRaise", OnCommandBedRaise_Up)
RegisterCommand("~!+towingBedRaise", OnCommandBedRaise_Down)
RegisterCommand("~!-towingBedRaise", OnCommandBedRaise_Up)
