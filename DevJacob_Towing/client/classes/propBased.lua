PropTowTruck = {
    ACTION = TowTruck.ACTION,
    CONTROL_MODE = TowTruck.CONTROL_MODE,
    STATE = {
        NONE = -1,
        RAISED = 0,
        LOWERINGSLIDE = 1,
        LOWERINGTILT = 2,
        LOWERED = 3,
        RAISINGTILT = 4,
        RAISINGSLIDE = 5,
    },
}
PropTowTruck.__index = PropTowTruck

function PropTowTruck.new(truckConfig, truckHandle)
    local self = setmetatable({}, PropTowTruck)

    self.config = PropTowTruck.ValidateConfig(truckConfig)
    self.lerpVal = 0.0
    self.cache = {}
    self.hookThread = false

    self.truckHandle = truckHandle
    self.truckNetId = VehToNet(truckHandle)
    self.remotePropHandle = nil
    self.remoteRopeHandle = nil
    self.hookPropHandle = nil
    self.hookRopeHandle = nil
    self.bedHandle = NetToObj(self:GetBedNetId())
    self.towingCarHandle = nil
    self.towingCarAttachOffset = nil

    -- Prompts
    self.prompts = {
        bedControls = {
            grabRemote = false,
            storeRemote = false,
            controlBed = false,
        },
        winchControls = {
            cannotAttach = false,
            attachToVehicle = false,
            grabHook = false,
            storeHook = false,
            strapVehicle = false,
            unStrapVehicle = false,
            controlWinch = false,
            unHookVehicle = false,
        },
    }

    -- Control fields
    self.controlMode = PropTowTruck.CONTROL_MODE.BED


    Citizen.CreateThread(PropTowTruck.GetLifeCycleThread(self))

    return self
end

function PropTowTruck.ValidateConfig(truckCfg)
    if truckCfg == nil then return nil end
    if TowTruck.ParseType(truckCfg.truckType) ~= TowTruck.TYPE.PROP_BASED then return nil end

    local newConfigTable = {}
    local defaultCfg = {
		lerpMult = 4.0,
		hasRemote = true,
		remoteStorageOffset = vector3(-1.05, -1.0, 0.0),
		controlBoxOffset = vector3(-1.05, -1.0, 0.0),
		hookRootOffset = vector3(0.025, 4.5, 0.1),
		bedAttachOffset = vector3(0.0, 1.5, 0.3),
		bedOffsets = {
			raised = {
				pos = vector3(0.0, -3.8, 0.45),
				rot = vector3(0.0, 0.0, 0.0),
			},
			back = {
				pos = vector3(0.0, -4.0, 0.0),
				rot = vector3(0.0, 0.0, 0.0),
			},
			lowered = {
				pos = vector3(0.0, -0.4, -1.0),
				rot = vector3(12.0, 0.0, 0.0),
			},
		},
    }
    
    local getValue = function(key, cfg)
        local _cfg = cfg or truckCfg
        if _cfg[key] ~= nil then
            return _cfg[key]
        else
            return defaultCfg[key]
        end
    end

    truckCfg["bedOffsets"] = truckCfg["bedOffsets"] or {}
    truckCfg["bedOffsets"]["raised"] = truckCfg["bedOffsets"]["raised"] or {}
    truckCfg["bedOffsets"]["back"] = truckCfg["bedOffsets"]["back"] or {}
    truckCfg["bedOffsets"]["lowered"] = truckCfg["bedOffsets"]["lowered"] or {}

    newConfigTable["truckType"] = TowTruck.TYPE.PROP_BASED
    newConfigTable["truckModel"] = truckCfg["truckModel"]
    newConfigTable["bedModel"] = truckCfg["bedModel"]
    newConfigTable["bedExtraIndex"] = getValue("bedExtraIndex")
    newConfigTable["lerpMult"] = getValue("lerpMult")
    newConfigTable["hasRemote"] = getValue("hasRemote")
    newConfigTable["remoteStorageOffset"] = getValue("remoteStorageOffset")
    newConfigTable["controlBoxOffset"] = getValue("controlBoxOffset")
    newConfigTable["hookRootOffset"] = getValue("hookRootOffset")
    newConfigTable["bedAttachOffset"] = getValue("bedAttachOffset")
    newConfigTable["bedOffsets"] = getValue("bedOffsets")
    
    newConfigTable["bedOffsets"]["raised"] = getValue("raised", truckCfg["bedOffsets"])
    newConfigTable["bedOffsets"]["raised"]["pos"] = getValue("pos", truckCfg["bedOffsets"]["raised"])
    newConfigTable["bedOffsets"]["raised"]["rot"] = getValue("rot", truckCfg["bedOffsets"]["raised"])
    
    newConfigTable["bedOffsets"]["back"] = getValue("back", truckCfg["bedOffsets"])
    newConfigTable["bedOffsets"]["back"]["pos"] = getValue("pos", truckCfg["bedOffsets"]["back"])
    newConfigTable["bedOffsets"]["back"]["rot"] = getValue("rot", truckCfg["bedOffsets"]["back"])

    newConfigTable["bedOffsets"]["lowered"] = getValue("lowered", truckCfg["bedOffsets"])
    newConfigTable["bedOffsets"]["lowered"]["pos"] = getValue("pos", truckCfg["bedOffsets"]["lowered"])
    newConfigTable["bedOffsets"]["lowered"]["rot"] = getValue("rot", truckCfg["bedOffsets"]["lowered"])

    return newConfigTable
end

function PropTowTruck.GetLifeCycleThread(towTruck)
    local threadFunc = function()
        while true do
            Citizen.Wait(0)
    
            -- Ensure the truck exists
            if not DoesEntityExist(towTruck.truckHandle) then
                
                -- Try to find it from the net id
                local newTruckHandle = NetToObj(towTruck.truckNetId)
                if DoesEntityExist(newTruckHandle) then
                    towTruck.truckHandle = newTruckHandle
                else
                    -- If the net id doesn't exist, ensure we cleanup
                    towTruck:Destroy()
                    break
                end
                
            end
    
            -- Ensure the bed exists
            if not DoesEntityExist(towTruck.bedHandle) then
                local newHandle = NetToObj(towTruck:GetBedNetId())
                if DoesEntityExist(newHandle) then
                    towTruck.bedHandle = newHandle
                else
                    Logger.Error("Couldn't recreate the bed object, life cycle thread exiting!")
                    break
                end
            end

            -- Handle bed movement
            local action = towTruck:GetAction()
            if action == PropTowTruck.ACTION.LOWERING then
                towTruck:LowerBed()
            elseif action == PropTowTruck.ACTION.RAISING then
                towTruck:RaiseBed()
            end

            local playerPed = PlayerPedId()
            local pedPosition = GetEntityCoords(playerPed)
            local isUsingControls = false
            local canReturnRemote = false
            local isHookInUse = towTruck:IsHookInUse()
            local isCarHooked = towTruck:IsCarHooked()

            if towTruck.config.hasRemote == true then
                -- Handle remote based controls

                isUsingControls = towTruck:IsRemoteInUse()

                -- Handle Grab / Return Remote
                local remoteStorage = GetOffsetFromEntityInWorldCoords(towTruck.truckHandle, towTruck.config.remoteStorageOffset)
                local remoteStorageDist = #(pedPosition - remoteStorage)
                canReturnRemote = remoteStorageDist <= 1.0

                if canReturnRemote then
                    if isUsingControls then
                        towTruck.prompts.bedControls.storeRemote = true
                    else
                        towTruck.prompts.bedControls.grabRemote = true
                    end
                
                    if IsControlJustPressed(0, 51) then
                        if isUsingControls then
                            DeleteEntity(towTruck.remotePropHandle)
                            DeleteRope(towTruck.remoteRopeHandle)

                            towTruck.remotePropHandle = nil
                            towTruck.remoteRopeHandle = nil
                        else
                            Citizen.Await(towTruck:GrabRemoteAsync(playerPed))
                        end
                    end
                end

                -- Freeze the tow truck when using the remote, this is because of weird GTA rope collisions I can't seem to solve
                if isUsingControls then
                    if not IsEntityPositionFrozen(towTruck.truckHandle) then
                        FreezeEntityPosition(towTruck.truckHandle, true)
                    end
                else
                    if IsEntityPositionFrozen(towTruck.truckHandle) then
                        FreezeEntityPosition(towTruck.truckHandle, false)
                    end
                end

            else
                -- Handle control box based controls

                local controlBoxPos = GetOffsetFromEntityInWorldCoords(towTruck.truckHandle, towTruck.config.controlBoxOffset)
                local controlsDist = #(pedPosition - controlBoxPos)
                isUsingControls = controlsDist <= 1.0

                towTruck.prompts.bedControls.controlBed = isUsingControls
                towTruck.cache.canControlBed = isUsingControls
                
            end
            

            -- Handle winch movement
            if isUsingControls and isCarHooked and not canReturnRemote then
                towTruck.prompts.winchControls.controlWinch = true
                
                -- Disable take cover key
                DisableControlAction(0, 44, false)
                
                -- Wind
                if IsControlPressed(0, 51) and not IsControlPressed(0, 52) then
                    -- towTruck:DetachCar()
                    ActivatePhysics(towTruck.towingCarHandle)
                    StartRopeWinding(towTruck.hookRopeHandle)
                    
                elseif IsControlJustReleased(0, 51) then
                    StopRopeWinding(towTruck.hookRopeHandle)
                end
                
                -- Unwind
                if IsControlPressed(0, 52) and not IsControlPressed(0, 51) then
                    -- towTruck:DetachCar()
                    ActivatePhysics(towTruck.towingCarHandle)
                    StartRopeUnwindingFront(towTruck.hookRopeHandle)
                    
                elseif IsControlJustReleased(0, 52) then
                    StopRopeUnwindingFront(towTruck.hookRopeHandle)
                end
            end

            -- Handle Grab Hook / Strap Vehicle
            local hookStorage = GetOffsetFromEntityInWorldCoords(towTruck.bedHandle, towTruck.config.hookRootOffset)
            local hookStorageDist = #(pedPosition - hookStorage)
            if hookStorageDist <= 1.4 and IsPedOnFoot(playerPed) then

                if isCarHooked then
                    local isCarStraped = IsEntityAttachedToEntity(towTruck.bedHandle, towTruck.towingCarHandle)

                    if isCarStraped then
                        towTruck.prompts.winchControls.unStrapVehicle = true
                    else
                        towTruck.prompts.winchControls.strapVehicle = true
                    end
                    
                    if IsControlJustPressed(0, 51) then
                        if isCarStraped then
                            towTruck:DetachCar()
                            towTruck:SetTowingCar(nil)
                        else
                            DeleteRope(towTruck.hookRopeHandle)
                            towTruck.hookRopeHandle = nil

                            towTruck:AttachCarToBed()
                        end
                    end

                else
                    if isHookInUse then
                        towTruck.prompts.winchControls.storeHook = true
                    else
                        towTruck.prompts.winchControls.grabHook = true
                    end
                    
                    if IsControlJustPressed(0, 51) then
                        if isHookInUse then
                            DeleteEntity(towTruck.hookPropHandle)
                            DeleteRope(towTruck.hookRopeHandle)

                            towTruck.hookPropHandle = nil
                            towTruck.hookRopeHandle = nil
                        else
                            Citizen.Await(towTruck:GrabHookAsync(playerPed))
                        end
                    end
                end

            end

            -- Handle Unhooking Vehicle
            if isCarHooked and towTruck.hookRopeHandle ~= nil then
                local hookedVeh = GetOffsetFromEntityInWorldCoords(towTruck.towingCarHandle, towTruck.towingCarAttachOffset)
                local hookedVehDist = #(pedPosition - hookedVeh)

                if hookedVehDist <= 1.4 and IsPedOnFoot(playerPed) then
                    towTruck.prompts.winchControls.unHookVehicle = true
                    
                    -- Disable take cover key
                    DisableControlAction(0, 44, false)

                    if IsControlJustPressed(0, 52) then
                        DeleteRope(towTruck.hookRopeHandle)
                        towTruck.hookRopeHandle = nil
                        towTruck.towingCarAttachOffset = nil
                        towTruck:SetTowingCar(nil)
                    end
                end
            end
            
            -- Handle starting hook thread
            if towTruck.hookThread == false and isHookInUse and IsEntityAttachedToEntity(playerPed, towTruck.hookPropHandle) == 1 then
                -- Handle attaching to vehicles
                Citizen.CreateThread(PropTowTruck.GetHookThread(towTruck))
            end

            towTruck:DisplayPromptsThisFrame()
    
            -- Debug Stuff
            if Config["DebugMode"] == true then
                local _DrawText2DThisFrame = function(x, y, text)
                    drawText2DThisFrame({
                        coords = vector2(x, y),
                        text = text,
                        scale = 0.45,
                        colour = {
                            r = 255,
                            g = 255,
                            b = 255,
                            a = 200
                        }
                    })
                end
                _DrawText2DThisFrame(0.02, 0.3, "Tow Truck State: " .. towTruck:GetState())
                _DrawText2DThisFrame(0.02, 0.325, "Tow Truck Action: " .. towTruck:GetAction())
                _DrawText2DThisFrame(0.02, 0.35, "Tow Truck lerp: " .. towTruck.lerpVal)
                _DrawText2DThisFrame(0.02, 0.4, "Tow Truck Hook Storage Dist: " .. hookStorageDist)

                if towTruck.towingCarHandle ~= nil then
                    _DrawText2DThisFrame(0.02, 0.425, "Towing Car Rot: " .. GetEntityRotation(towTruck.towingCarHandle, 2))
                end
                if towTruck.bedHandle ~= nil then
                    _DrawText2DThisFrame(0.02, 0.45, "Bed Rot: " .. GetEntityRotation(towTruck.bedHandle, 2))
                end

                local drawPos = GetOffsetFromEntityInWorldCoords(towTruck.truckHandle, towTruck.config.remoteStorageOffset)
                DrawMarker(28, drawPos.x, drawPos.y, drawPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 128, 0, 100, false, true, 2, nil, nil, false)

                local drawPos2 = GetOffsetFromEntityInWorldCoords(towTruck.bedHandle, towTruck.config.hookRootOffset)
                DrawMarker(28, drawPos2.x, drawPos2.y, drawPos2.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 0, 122, 100, false, true, 2, nil, nil, false)
            end
    
            ::continue::
        end
    
    end

    return threadFunc
end

function PropTowTruck.GetHookThread(towTruck)
    local threadFunc = function()
        if towTruck.hookThread == true then
            return
        end

        towTruck.hookThread = true
        
        local playerPed = PlayerPedId()
        local targetData = nil

        -- Cast Thread
        local castThread = true
        Citizen.CreateThread(function()
            while towTruck:IsHookInUse() and IsEntityAttachedToEntity(playerPed, towTruck.hookPropHandle) == 1 do
                Citizen.Wait(0)
                
                local camCoords = GetFinalRenderedCamCoord()
                local camRot = GetFinalRenderedCamRot(2)
                local destination = getOffsetFromCoordsInWorldCoords(camCoords, camRot, vector3(0.0, Config["MaxHookReach"], 0.0))
                local castHandle = StartShapeTestLosProbe(camCoords, destination, 4294967295, 0, 4)
            
                local state, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(castHandle)
                while state == 1 do
                    Citizen.Wait(0)
                    state, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(castHandle)
                end
    
                if state == 2 then
                    lastCastResult = {
                        state = state,
                        hit = hit,
                        endCoords = endCoords,
                        surfaceNormal = surfaceNormal,
                        entityHit = entityHit,
                    }
                end
            end

            castThread = false
        end)

        -- Draw & Process Thread
        local processThread = true
        Citizen.CreateThread(function()
            while towTruck:IsHookInUse() and IsEntityAttachedToEntity(playerPed, towTruck.hookPropHandle) == 1 do
                Citizen.Wait(0)

                if lastCastResult ~= nil then
                    local canAttach = lastCastResult.hit and lastCastResult.entityHit ~= nil and DoesEntityExist(lastCastResult.entityHit) 
                        and IsEntityAVehicle(lastCastResult.entityHit) and lastCastResult.entityHit ~= towTruck.truckHandle
                    local endRgb = ternary(canAttach, { r = 0, g = 255, b = 0 }, { r = 255, g = 0, b = 0 })
                
                    DrawMarker(28, lastCastResult.endCoords.x, lastCastResult.endCoords.y, lastCastResult.endCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, endRgb.r, endRgb.g, endRgb.b, 100, false, true, 2, nil, nil, false)

                    if canAttach then
                        towTruck.prompts.winchControls.attachToVehicle = true
                    else
                        towTruck.prompts.winchControls.cannotAttach = true
                    end

                    if canAttach and IsControlJustPressed(0, 51) then

                        -- Delete the hook prop
                        if towTruck.hookPropHandle ~= nil and DoesEntityExist(towTruck.hookPropHandle) then
                            DeleteEntity(towTruck.hookPropHandle)
                            towTruck.hookPropHandle = nil
                        end
                        
                        -- Delete the hook rope
                        if towTruck.hookRopeHandle ~= nil and DoesRopeExist(towTruck.hookRopeHandle) then
                            DeleteRope(towTruck.hookRopeHandle)
                            towTruck.hookRopeHandle = nil
                        end
                        
                        -- Create a new rope
                        local carPos = GetEntityCoords(lastCastResult.entityHit)
                        local ropeLength = #(lastCastResult.endCoords - GetOffsetFromEntityInWorldCoords(towTruck.bedHandle, towTruck.config.hookRootOffset))
                        local newRopeHandle = AddRope(carPos.x, carPos.y, carPos.z, 0.0, 0.0, 0.0, ropeLength, 3, ropeLength, 1.0, 0.5, false, true, true, 1.0, true, 0)
                        towTruck.hookRopeHandle = newRopeHandle
                        ActivatePhysics(towTruck.hookRopeHandle)
                
                        -- Attach the rope to the car
                        local bedAttachPos = GetOffsetFromEntityInWorldCoords(towTruck.bedHandle, towTruck.config.hookRootOffset)
                        AttachEntitiesToRope(towTruck.hookRopeHandle, towTruck.bedHandle, lastCastResult.entityHit, 
                            bedAttachPos, lastCastResult.endCoords, ropeLength, false, false, nil, nil)
                        
                        -- Set the towing car data
                        towTruck:SetTowingCar(VehToNet(lastCastResult.entityHit))
                        towTruck.towingCarAttachOffset = GetOffsetFromEntityGivenWorldCoords(lastCastResult.entityHit, lastCastResult.endCoords)

                    end
                end
            end

            processThread = false
        end)

        while castThread and processThread do
            Citizen.Wait(100)
        end

        towTruck.hookThread = false
    end

    return threadFunc
end

function PropTowTruck:IsRemoteInUse()
    if self.config.hasRemote == false then
        return false
    end
    
    return self.remotePropHandle ~= nil
end

function PropTowTruck:CanControlBed()
    return self.cache.canControlBed == true or self:IsRemoteInUse()
end

function PropTowTruck:IsHookInUse()
    return self.hookPropHandle ~= nil
end

function PropTowTruck:IsCarHooked()
    return self.towingCarHandle ~= nil
end

function PropTowTruck:GetBoneIndexByName(name)
    if self.cache.boneIndexes == nil then
        self.cache.boneIndexes = {}
    end

    if self.cache.boneIndexes[name] ~= nil then
        return self.cache.boneIndexes[name]
    end

    local boneIndex = GetEntityBoneIndexByName(self.truckHandle, name)
    if boneIndex ~= -1 then
        self.cache.boneIndexes[name] = boneIndex
    end

    return boneIndex
end

function PropTowTruck:Destroy(deleteVehicle)
    if self.bedHandle ~= nil and DoesEntityExist(self.bedHandle) then
        DeleteEntity(self.bedHandle)
        self.bedHandle = nil
    end
    
    if self.remotePropHandle ~= nil and DoesEntityExist(self.remotePropHandle) then
        DeleteEntity(self.remotePropHandle)
        self.remotePropHandle = nil
    end
    
    if self.remoteRopeHandle ~= nil and DoesRopeExist(self.remoteRopeHandle) then
        DeleteRope(self.remoteRopeHandle)
        self.remoteRopeHandle = nil
    end
    
    if self.hookPropHandle ~= nil and DoesEntityExist(self.hookPropHandle) then
        DeleteEntity(self.hookPropHandle)
        self.hookPropHandle = nil
    end
    
    if self.hookRopeHandle ~= nil and DoesRopeExist(self.hookRopeHandle) then
        DeleteRope(self.hookRopeHandle)
        self.hookRopeHandle = nil
    end

    if deleteVehicle == true and self.truckHandle ~= nil and DoesEntityExist(self.truckHandle) then
        DeleteEntity(self.truckHandle)
        self.truckHandle = nil
    end

    if IsEntityPositionFrozen(self.truckHandle) then
        FreezeEntityPosition(self.truckHandle, false)
    end

    self:SetBedNetId(nil)
    self:SetState(nil)
    self:SetAction(nil)
end

function PropTowTruck:GetState()
    local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:State"]
    
    if bagValue == nil then
        self:SetState(PropTowTruck.STATE.NONE)
        return PropTowTruck.STATE.NONE
    end

    return bagValue
end

function PropTowTruck:SetState(state)
    Entity(self.truckHandle).state:set("DevJacob_Tow:State", state, true)
end

function PropTowTruck:GetAction()
    local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:Action"]
    
    if bagValue == nil then
        self:SetState(PropTowTruck.ACTION.NONE)
        return PropTowTruck.ACTION.NONE
    end

    return bagValue
end

function PropTowTruck:SetAction(action)
    Entity(self.truckHandle).state:set("DevJacob_Tow:Action", action, true)
end

function PropTowTruck:GetBedNetId()
    local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:SummonedBed"]
    
    if bagValue == nil then

        -- Create the bed
        local _1, _4, _3, pos = GetEntityMatrix(self.truckHandle)
        local bedHandle = CreateObjectNoOffset(self.config.bedModel, pos, true, 0, 1)
        local bedNetId = ObjToNet(bedHandle)
        if DoesEntityExist(bedHandle) then
            self:SetBedNetId(bedNetId)
            self:AttachBedToTruck(self.config.bedOffsets.raised.pos, self.config.bedOffsets.raised.rot, true)
            SetVehicleExtra(self.truckHandle, 1, not false)
            SetEntityCollision(bedHandle, true, true)
        end

        return bedNetId
    end

    return bagValue
end

function PropTowTruck:SetBedNetId(objNetId)
    Entity(self.truckHandle).state:set("DevJacob_Tow:SummonedBed", objNetId, true)
    self.bedHandle = NetToObj(objNetId)
end

function PropTowTruck:GetTowingCarNetId()
    local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:TowingCar"]
    
    if bagValue == nil then
        self:SetTowingCar(-1)
        return -1
    end

    local handle = NetToVeh(bagValue)
    if self.towingCarHandle ~= handle then
        self.towingCarHandle = handle
    end

    return bagValue
end

function PropTowTruck:SetTowingCar(car)
    Entity(self.truckHandle).state:set("DevJacob_Tow:TowingCar", car, true)
    self.towingCarHandle = ternary(car == nil, nil, NetToObj(car))
end

function PropTowTruck:DisplayBedControlsThisFrame()
    local data = self.prompts.bedControls
    local prompts = {}
    
    if data["controlBed"] == true then
        prompts[#prompts + 1] = ("Press ~%s~ to raise bed"):format(toInputString("+towingBedRaise"))
        prompts[#prompts + 1] = ("Press ~%s~ to lower bed"):format(toInputString("+towingBedLower"))
    end

    if self.config.hasRemote == true then
        
        if data["grabRemote"] == true then
            prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to grab remote"
        elseif data["storeRemote"] == true then
            prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to store remote"
        end

    end

    if #prompts == 0 then 
        return
    end

    BeginTextCommandDisplayHelp("STRING")
    AddTextEntry("DevJacob_Tow:BedControls", table.concat(prompts, "~n~"))
    AddTextComponentSubstringTextLabel("DevJacob_Tow:BedControls")
    EndTextCommandDisplayHelp(0, 0, 1, -1)

    -- Reset the active prompts
    self.prompts.bedControls = {
        grabRemote = false,
        storeRemote = false,
        controlBed = false,
    }
end

function PropTowTruck:DisplayWinchControlsThisFrame()
    local data = self.prompts.winchControls
    local prompts = {}
    
    if data["cannotAttach"] == true then
        prompts[#prompts + 1] = "Cannot attach hook to that!"
    elseif data["attachToVehicle"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to attach hook to vehicle"
    end

    if data["grabHook"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to grab hook"
    elseif data["storeHook"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to store hook"
    end

    if data["strapVehicle"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to strap down vehicle"
    elseif data["unStrapVehicle"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to unstrap vehicle"
    end

    if data["controlWinch"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT~ to wind winch"
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT_SECONDARY~ to unwind winch"
    end

    if data["unHookVehicle"] == true then
        prompts[#prompts + 1] = "Press ~INPUT_CONTEXT_SECONDARY~ to unhook the vehicle"
    end

    if #prompts == 0 then 
        return
    end

    BeginTextCommandDisplayHelp("STRING")
    AddTextEntry("DevJacob_Tow:WinchControls", table.concat(prompts, "~n~"))
    AddTextComponentSubstringTextLabel("DevJacob_Tow:WinchControls")
    EndTextCommandDisplayHelp(0, 0, 0, -1)

    -- Reset the active prompts
    self.prompts.winchControls = {
        cannotAttach = false,
        attachToVehicle = false,
        grabHook = false,
        storeHook = false,
        strapVehicle = false,
        unStrapVehicle = false,
        controlWinch = false,
        unHookVehicle = false,
    }
end

function PropTowTruck:DisplayPromptsThisFrame()
    self:DisplayBedControlsThisFrame()
    self:DisplayWinchControlsThisFrame()
end

function PropTowTruck:LowerBed()
    local origState = self:GetState()
    local state = origState

    -- If the bed is already down, stop
    if state == PropTowTruck.STATE.LOWERED then
        return
    end

    -- If the bed is in the init state or raised, set the state to slide to start movement
    if state == PropTowTruck.STATE.RAISED or state == PropTowTruck.STATE.NONE then
        state = PropTowTruck.STATE.LOWERINGSLIDE
    end

    -- If we are mid slide back, start in side state
    if state == PropTowTruck.STATE.RAISINGSLIDE then
        state = PropTowTruck.STATE.LOWERINGSLIDE
        self.lerpVal = 1.0 - self.lerpVal
    end

    -- If we are mid raise tilt, start in tilt state
    if state == PropTowTruck.STATE.RAISINGTILT then
        state = PropTowTruck.STATE.LOWERINGTILT
        self.lerpVal = 1.0 - self.lerpVal
    end

    -- Process actual movement
    if state == PropTowTruck.STATE.LOWERINGSLIDE then
        local offsetPos = self.config.bedOffsets.raised.pos + lerpVector3(0.0, self.config.bedOffsets.back.pos, self.lerpVal)
        local offsetRot = self.config.bedOffsets.raised.rot + lerpVector3(0.0, self.config.bedOffsets.back.rot, self.lerpVal)

        self:DetachBed()
        self:AttachBedToTruck(offsetPos, offsetRot, true)

        self.lerpVal = self.lerpVal + (1.0 * Timestep()) / self.config.lerpMult

        if self.lerpVal >= 1.0 then
            state = PropTowTruck.STATE.LOWERINGTILT
            self.lerpVal = 0.0
        end

    elseif state == PropTowTruck.STATE.LOWERINGTILT then
        local offsetPos = self.config.bedOffsets.raised.pos + self.config.bedOffsets.back.pos + lerpVector3(0.0, self.config.bedOffsets.lowered.pos, self.lerpVal)
        local offsetRot = self.config.bedOffsets.raised.rot + self.config.bedOffsets.back.rot + lerpVector3(0.0, self.config.bedOffsets.lowered.rot, self.lerpVal)

        self:DetachBed()
        self:AttachBedToTruck(offsetPos, offsetRot, true)

        self.lerpVal = self.lerpVal + (1.0 * Timestep()) / self.config.lerpMult

        if self.lerpVal >= 1.0 then
            state = PropTowTruck.STATE.LOWERED
            self.lerpVal = 0.0
        end

    end

    -- Update the statebag if it has changed
    if state ~= origState then
        self:SetState(state)
    end
end

function PropTowTruck:RaiseBed()
    local origState = self:GetState()
    local state = origState

    -- If the bed is already up, stop
    if state == PropTowTruck.STATE.RAISED then
        return
    end

    -- If the bed is in the lowered state, set the state to tilt to start movement
    if state == PropTowTruck.STATE.LOWERED then
        state = PropTowTruck.STATE.RAISINGTILT
    end

    -- If we are mid slide back, start in side state
    if state == PropTowTruck.STATE.LOWERINGSLIDE then
        state = PropTowTruck.STATE.RAISINGSLIDE
        self.lerpVal = 1.0 - self.lerpVal
    end

    -- If we are mid lower tilt, start in tilt state
    if state == PropTowTruck.STATE.LOWERINGTILT then
        state = PropTowTruck.STATE.RAISINGTILT
        self.lerpVal = 1.0 - self.lerpVal
    end

    -- Process actual movement
    if state == PropTowTruck.STATE.RAISINGTILT then
        local offsetPos = self.config.bedOffsets.raised.pos + self.config.bedOffsets.back.pos + lerpVector3(self.config.bedOffsets.lowered.pos, 0.0, self.lerpVal)
        local offsetRot = self.config.bedOffsets.raised.rot + self.config.bedOffsets.back.rot + lerpVector3(self.config.bedOffsets.lowered.rot, 0.0, self.lerpVal)

        self:DetachBed()
        self:AttachBedToTruck(offsetPos, offsetRot, true)

        self.lerpVal = self.lerpVal + (1.0 * Timestep()) / self.config.lerpMult

        if self.lerpVal >= 1.0 then
            state = PropTowTruck.STATE.RAISINGSLIDE
            self.lerpVal = 0.0
        end

    elseif state == PropTowTruck.STATE.RAISINGSLIDE then
        local offsetPos = self.config.bedOffsets.raised.pos + lerpVector3(self.config.bedOffsets.back.pos, 0.0, self.lerpVal)
        local offsetRot = self.config.bedOffsets.raised.rot + lerpVector3(self.config.bedOffsets.back.rot, 0.0, self.lerpVal)

        self:DetachBed()
        self:AttachBedToTruck(offsetPos, offsetRot, true)

        self.lerpVal = self.lerpVal + (1.0 * Timestep()) / self.config.lerpMult

        if self.lerpVal >= 1.0 then
            state = PropTowTruck.STATE.RAISED
            self.lerpVal = 0.0
        end

    end

    -- Update the statebag if it has changed
    if state ~= origState then
        self:SetState(state)
    end
end

function PropTowTruck:AttachBedToTruck(offset, rotation, collision)
    collision = collision or true

    local chassisBoneIndex = self:GetBoneIndexByName("chassis")
    AttachEntityToEntity(self.bedHandle, self.truckHandle, chassisBoneIndex, offset, rotation, false, false, collision, false, 0, true)
end

function PropTowTruck:DetachBed()
    DetachEntity(self.bedHandle, false, false)
end

function PropTowTruck:AttachCarToBed()
    local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
    local carPos = GetEntityCoords(towingCarHandle, false)
    local bedPos = GetEntityCoords(self.bedHandle, false)
    local attachPos = self.config.bedAttachOffset + vector3(0.0, 0.0, carPos.z - bedPos.z - 0.35)

    local bedRot = GetEntityRotation(self.bedHandle, 2)
    local carRot = GetEntityRotation(towingCarHandle, 2)
    local attachRot = getOffsetBetweenRotations(bedRot, carRot)

    AttachEntityToEntity(towingCarHandle, self.bedHandle, 0, attachPos, attachRot, false, false, false, false, 2, true)
end

function PropTowTruck:DetachCar()
    local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
    DetachEntity(towingCarHandle, false, false)
end

function PropTowTruck:GrabRemoteAsync(ped)
    local _promise = promise.new()

    local runFunc = function()
        -- Load prop model
        local modelLoaded = Citizen.Await(requestModelAsync(Config["RemoteModel"]))
        if modelLoaded == false then
            Logger.Error(("Failed to load model \"%s\""):format(Config["RemoteModel"]))
            _promise:reject()
            return
        end

        -- Create Prop
        local pedPos = GetEntityCoords(ped)
        local newPropHandle = CreateObjectNoOffset(Config["RemoteModel"], pedPos.x, pedPos.y, pedPos.z + 1, true, true, false)
        if newPropHandle == 0 then
            SetModelAsNoLongerNeeded(Config["RemoteModel"])
            Logger.Error(("Failed to create object for model \"%s\""):format(Config["RemoteModel"]))
            _promise:reject()
            return
        end
        self.remotePropHandle = newPropHandle
        SetModelAsNoLongerNeeded(Config["RemoteModel"])
        FreezeEntityPosition(self.truckHandle, true)
        
        local boneIndex = GetPedBoneIndex(ped, 18905) -- SKEL_L_Hand
        AttachEntityToEntity(self.remotePropHandle, ped, boneIndex, 0.1, 0.1, 0.0, 180.0, -65.0, -80.0, false, false, false, true, 2, true)

        -- Load rope textures
        local texturesLoaded = Citizen.Await(loadRopeTexturesAsync())
        if texturesLoaded == false then
            Logger.Error("Failed to load rope textures")
            _promise:reject("Failed to load rope textures")
            return
        end

        -- Create rope
        local remotePos = GetEntityCoords(self.remotePropHandle)
        local newRopeHandle = AddRope(remotePos.x, remotePos.y, remotePos.z, 0.0, 0.0, 0.0, 3.0, 1, 500.0, 1.0, 0.5, false, false, false, 1.0, true, 0)
        if not newRopeHandle then
            Logger.Error("Failed to create rope")
            _promise:resolve("Failed to create rope")
            return
        end
        self.remoteRopeHandle = newRopeHandle
        ActivatePhysics(self.remoteRopeHandle)
        
        -- Handle Grounding Remote Rope
        if Config["GroundRemoteRope"] == true then
            Citizen.CreateThread(function()
                local pinnedVerts = {}
                while self.remoteRopeHandle ~= nil do
                    Citizen.Wait(0)
                    local playerPos = GetEntityCoords(PlayerPedId())
                    local totalVerts = GetRopeVertexCount(self.remoteRopeHandle)
                    
                    for i = 0, totalVerts - 1 do
                        local vertCoords = GetRopeVertexCoord(self.remoteRopeHandle, i)
                        local groundedCoords = groundCoords(vertCoords)
                        groundedCoords = vector3(groundedCoords.x, groundedCoords.y, groundedCoords.z + 0.03)

                        RopeSetUpdatePinverts(self.remoteRopeHandle)
                        if vertCoords.z < groundedCoords.z then
                            PinRopeVertex(self.remoteRopeHandle, i, groundedCoords)
                            pinnedVerts[i] = groundedCoords
                            if Config["DebugMode"] == true then
                                DrawMarker(28, groundedCoords.x, groundedCoords.y, groundedCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.025, 0.025, 0.025, 255, 128, 0, 50, false, true, 2, nil, nil, false)
                            end
                        elseif pinnedVerts[i] ~= nil then
                            UnpinRopeVertex(self.remoteRopeHandle, i)
                            pinnedVerts[i] = nil
                            if Config["DebugMode"] == true then
                                DrawMarker(28, vertCoords.x, vertCoords.y, vertCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.025, 0.025, 0.025, 0, 128, 255, 50, false, true, 2, nil, nil, false)
                            end
                        end
                    end
                end
            end)
        end

        local truckAttachPos = GetOffsetFromEntityInWorldCoords(self.truckHandle, self.config.remoteStorageOffset)
        local remoteAttachPos = GetOffsetFromEntityInWorldCoords(self.remotePropHandle, 0.0, 0.020, 0.15)
        AttachEntitiesToRope(self.remoteRopeHandle, self.truckHandle, self.remotePropHandle, 
            truckAttachPos.x, truckAttachPos.y, truckAttachPos.z,
            remoteAttachPos.x, remoteAttachPos.y, remoteAttachPos.z,
            5.0, false, false, nil, nil)

        _promise:resolve()
    end

    runFunc()
    return _promise

end

function PropTowTruck:GrabHookAsync(ped)
    local _promise = promise.new()

    local runFunc = function()
        -- Load prop model
        local modelLoaded = Citizen.Await(requestModelAsync(Config["HookModel"]))
        if modelLoaded == false then
            Logger.Error(("Failed to load model \"%s\""):format(Config["HookModel"]))
            _promise:reject()
            return
        end

        -- Create Prop
        local pedPos = GetEntityCoords(ped)
        local newPropHandle = CreateObjectNoOffset(Config["HookModel"], pedPos.x, pedPos.y, pedPos.z + 1, true, true, false)
        if newPropHandle == 0 then
            SetModelAsNoLongerNeeded(Config["HookModel"])
            Logger.Error(("Failed to create object for model \"%s\""):format(Config["HookModel"]))
            _promise:reject()
            return
        end
        self.hookPropHandle = newPropHandle
        SetModelAsNoLongerNeeded(Config["HookModel"])
        
        local boneIndex = GetPedBoneIndex(ped, 18905) -- SKEL_L_Hand
        AttachEntityToEntity(self.hookPropHandle, ped, boneIndex, 0.175, -0.1, 0.07, 0.0, -75.0, 90.0, false, false, false, false, 2, true)

        -- Load rope textures
        local texturesLoaded = Citizen.Await(loadRopeTexturesAsync())
        if texturesLoaded == false then
            Logger.Error("Failed to load rope textures")
            _promise:reject()
            return
        end

        -- Create rope
        local hookPos = GetEntityCoords(self.hookPropHandle)
        local newRopeHandle = AddRope(hookPos.x, hookPos.y, hookPos.z, 0.0, 0.0, 0.0, 3.0, 3, 50.0, 0.0, 0.5, false, true, true, 1.0, true, 0)
        if not newRopeHandle then
            Logger.Error("Failed to create rope")
            _promise:reject()
            return
        end
        self.hookRopeHandle = newRopeHandle
        ActivatePhysics(self.hookRopeHandle)

        local truckAttachPos = GetOffsetFromEntityInWorldCoords(self.bedHandle, self.config.hookRootOffset)
        local hookAttachPos = GetOffsetFromEntityInWorldCoords(self.hookPropHandle, 0.0, 0.0, 0.03)
        AttachEntitiesToRope(self.hookRopeHandle, self.bedHandle, self.hookPropHandle, 
            truckAttachPos.x, truckAttachPos.y, truckAttachPos.z,
            hookAttachPos.x, hookAttachPos.y, hookAttachPos.z,
            5.0, false, false, nil, nil)

        _promise:resolve()
    end

    runFunc()
    return _promise

end
