ScoopTowTruck = {
    ACTION = TowTruck.ACTION,
    CONTROL_MODE = TowTruck.CONTROL_MODE,
    STATE = {
        NONE = -1,
        RAISED = 0,
        LOWERING = 1,
        LOWERED = 2,
        RAISING = 3,
    },
}
ScoopTowTruck.__index = ScoopTowTruck

function ScoopTowTruck.new(truckConfig, truckHandle)
    local self = setmetatable({}, ScoopTowTruck)

    self.config = ScoopTowTruck.ValidateConfig(truckConfig)
    self.cache = {}

    self.truckHandle = truckHandle
    self.truckNetId = VehToNet(truckHandle)
    
    self.hookBoneIndex = GetEntityBoneIndexByName(self.truckHandle, self.config.hookRoot.boneName)
    self.attachBoneIndex = GetEntityBoneIndexByName(self.truckHandle, self.config.bedAttach.boneName)

    self.hookPropHandle = nil
    self.hookRopeHandle = nil
    self.hookThread = false

    -- Prompts
    self.prompts = {
        bedControls = {
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


    Citizen.CreateThread(ScoopTowTruck.GetLifeCycleThread(self))

    return self
end

function ScoopTowTruck.ValidateConfig(truckCfg)
    if truckCfg == nil then return nil end
    if TowTruck.ParseType(truckCfg.truckType) ~= TowTruck.TYPE.SCOOP_BASED then return nil end

    local newConfigTable = {}
    local defaultCfg = {
		controlBoxOffset = vector3(-1.1, -1.3, -0.4),
		hookRoot = {
			boneName = "attach_male",
			offset = vector3(0.0, 0.0, 0.0),
		},
		bedAttach = {
			boneName = "misc_z",
			offset = vector3(0.0, 0.0, 0.0),
		},
		bedPositions = {
			raised = 0.0,
			lowered = 0.25,
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

    truckCfg["hookRoot"] = truckCfg["hookRoot"] or {}
    truckCfg["bedAttach"] = truckCfg["bedAttach"] or {}
    truckCfg["bedPositions"] = truckCfg["bedPositions"] or {}

    newConfigTable["truckType"] = TowTruck.TYPE.SCOOP_BASED
    newConfigTable["truckModel"] = truckCfg["truckModel"]
    newConfigTable["controlBoxOffset"] = getValue("controlBoxOffset")

    newConfigTable["hookRoot"] = getValue("hookRoot", truckCfg["hookRoot"])
    newConfigTable["hookRoot"]["boneName"] = getValue("boneName", truckCfg["hookRoot"])
    newConfigTable["hookRoot"]["offset"] = getValue("offset", truckCfg["hookRoot"])

    newConfigTable["bedAttach"] = getValue("bedAttach", truckCfg["bedAttach"])
    newConfigTable["bedAttach"]["boneName"] = getValue("boneName", truckCfg["bedAttach"])
    newConfigTable["bedAttach"]["offset"] = getValue("offset", truckCfg["bedAttach"])

    newConfigTable["bedPositions"] = getValue("bedPositions", truckCfg["bedPositions"])
    newConfigTable["bedPositions"]["raised"] = getValue("raised", truckCfg["bedPositions"])
    newConfigTable["bedPositions"]["lowered"] = getValue("lowered", truckCfg["bedPositions"])


    return newConfigTable
end



-- ###############################################
-- ###   Life Cycle Thread Functions | START   ###
-- ###############################################

    function ScoopTowTruck.GetLifeCycleThread(towTruck)
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

                -- Setup shared data table
                local sharedData = {}
                sharedData.playerPed = PlayerPedId()
                sharedData.pedPosition = GetEntityCoords(sharedData.playerPed)
                sharedData.isUsingControls = false
                sharedData.isHookInUse = towTruck:IsHookInUse()
                sharedData.isCarHooked = towTruck:IsCarHooked()

                -- Handle bed movement
                towTruck:Thread_ProcessBedMovement()

                -- Handle control box based controls
                towTruck:Thread_CheckControlBox(sharedData)
                
                -- Handle winch movement
                towTruck:Thread_ProcessWinchMovement(sharedData)

                -- Handle Grab Hook / Strap Vehicle
                towTruck:Thread_ProcessGrabHookStrapVeh(sharedData)

                -- Handle Unhooking Vehicle
                towTruck:Thread_ProcessUnhookVeh(sharedData)
                
                -- Handle starting hook thread
                if towTruck.hookThread == false and sharedData.isHookInUse and IsEntityAttachedToEntity(sharedData.playerPed, towTruck.hookPropHandle) == 1 then
                    -- Handle attaching to vehicles
                    Citizen.CreateThread(ScoopTowTruck.GetHookThread(towTruck))
                end

                -- Handle UI display
                towTruck:DisplayPromptsThisFrame()
        
                -- Debug Stuff
                towTruck:Thread_DrawDebugUi()
        
                ::continue::
            end
        
        end

        return threadFunc
    end

    function ScoopTowTruck:Thread_ProcessBedMovement()
        local action = self:GetAction()
        if action == TowTruck.ACTION.LOWERING then
            self:LowerBed()
        elseif action == TowTruck.ACTION.RAISING then
            self:RaiseBed()
        end
    end

    function ScoopTowTruck:Thread_CheckControlBox(data)
        local controlBoxPos = GetOffsetFromEntityInWorldCoords(self.truckHandle, self.config.controlBoxOffset)
        local controlsDist = #(data.pedPosition - controlBoxPos)
        data.isUsingControls = controlsDist <= 1.0

        self.prompts.bedControls.controlBed = data.isUsingControls
        self.cache.canControlBed = data.isUsingControls
    end

    function ScoopTowTruck:Thread_ProcessWinchMovement(data)
        if not data.isUsingControls or not data.isCarHooked then
            -- if self.cache.previewCar ~= nil then
            --     DeleteEntity(self.cache.previewCar)
            --     local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
            --     ResetEntityAlpha(towingCarHandle)
            --     self.cache.previewCar = nil
            -- end

            return
        end

        self.prompts.winchControls.controlWinch = true
        
        -- Disable take cover key
        DisableControlAction(0, 44, false)


        -- Preview Car
        -- if Config["DebugMode"] then
        --     if self.cache.previewCar == nil then
        --         local pos = GetEntityCoords(self.towingCarHandle)
        --         local hash = GetEntityModel(self.towingCarHandle)
        --         self.cache.previewCar = CreateVehicle(
        --             hash,
        --             pos.x,
        --             pos.y,
        --             pos.z + 20.0,
        --             GetEntityHeading(self.towingCarHandle),
        --             false,
        --             false
        --         )
        --         FreezeEntityPosition(self.cache.previewCar, true)
        --     end

        --     local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
            
        --     local carPos = GetEntityCoords(towingCarHandle, false)
        --     local attachPointPos = self:GetAttachPointWorldPosition()
        --     local carAttachOffset = GetOffsetFromEntityGivenWorldCoords(towingCarHandle, attachPointPos)
        --     local attachPos = carAttachOffset + self.config.bedAttach.offset
            
        --     print("=======================")
        --     print("carPos", carPos)
        --     print("attachPointPos", attachPointPos)
        --     print("carAttachOffset", carAttachOffset)
        --     print("self.config.bedAttach.offset", self.config.bedAttach.offset)
        --     print("attachPos", attachPos)
        --     print("-----")
            
        --     local carRot = GetEntityRotation(towingCarHandle, 2)
        --     local attachPointRot = GetEntityBoneRotation(self.truckHandle, self.attachBoneIndex)
        --     local attachRot = getOffsetBetweenRotations(attachPointRot, carRot)
        --     print("carRot", carRot)
        --     print("attachPointRot", attachPointRot)
        --     print("attachRot", attachRot)
        --     attachRot = vector3(0, 0, 0)
            
        --     SetEntityAlpha(towingCarHandle, 100, false)
        --     FreezeEntityPosition(self.cache.previewCar, true)
        
        --     DetachEntity(self.cache.previewCar, false, false)
        --     AttachEntityToEntity(self.cache.previewCar, self.truckHandle, self.attachBoneIndex, attachPos, attachRot, false, false, false, false, 2, true)
        -- end
        

        -- Wind
        if IsControlPressed(0, 51) and not IsControlPressed(0, 52) then
            self:DetachCar()
            ActivatePhysics(self.towingCarHandle)
            StartRopeWinding(self.hookRopeHandle)
            
        elseif IsControlJustReleased(0, 51) then
            StopRopeWinding(self.hookRopeHandle)
            -- self:AttachCarToBed()
        end
        
        -- Unwind
        if IsControlPressed(0, 52) and not IsControlPressed(0, 51) then
            self:DetachCar()
            ActivatePhysics(self.towingCarHandle)
            StartRopeUnwindingFront(self.hookRopeHandle)
            
        elseif IsControlJustReleased(0, 52) then
            StopRopeUnwindingFront(self.hookRopeHandle)
            -- self:AttachCarToBed()
        end
    end

    function ScoopTowTruck:Thread_ProcessGrabHookStrapVeh(data)
        local hookStorage = self:GetHookStorageWorldPosition()
        local hookStorageDist = #(data.pedPosition - hookStorage)
        if hookStorageDist > 1.4 or not IsPedOnFoot(data.playerPed) then
            return
        end

        if data.isCarHooked then
            local isCarStraped = IsEntityAttachedToEntity(self.truckHandle, self.towingCarHandle)

            if isCarStraped then
                self.prompts.winchControls.unStrapVehicle = true
            else
                self.prompts.winchControls.strapVehicle = true
            end
            
            if IsControlJustPressed(0, 51) then
                if isCarStraped then
                    self:DetachCar()
                    self:SetTowingCar(nil)
                else
                    DeleteRope(self.hookRopeHandle)
                    self.hookRopeHandle = nil

                    self:AttachCarToBed()
                end
            end

        else
            if data.isHookInUse then
                self.prompts.winchControls.storeHook = true
            else
                self.prompts.winchControls.grabHook = true
            end
            
            if IsControlJustPressed(0, 51) then
                if data.isHookInUse then
                    DeleteEntity(self.hookPropHandle)
                    DeleteRope(self.hookRopeHandle)

                    self.hookPropHandle = nil
                    self.hookRopeHandle = nil
                else
                    Citizen.Await(self:GrabHookAsync(data.playerPed))
                end
            end
        end
    end

    function ScoopTowTruck:Thread_ProcessUnhookVeh(data)
        if not data.isCarHooked or self.hookRopeHandle == nil then
            return 
        end
        
        local hookedVeh = GetOffsetFromEntityInWorldCoords(self.towingCarHandle, self.towingCarAttachOffset)
        local hookedVehDist = #(data.pedPosition - hookedVeh)
        if hookedVehDist > 1.4 or not IsPedOnFoot(data.playerPed) then
            return
        end
        
        self.prompts.winchControls.unHookVehicle = true
        
        -- Disable take cover key
        DisableControlAction(0, 44, false)

        if IsControlJustPressed(0, 52) then
            DeleteRope(self.hookRopeHandle)
            self.hookRopeHandle = nil
            self.towingCarAttachOffset = nil
            self:SetTowingCar(nil)
        end
    end

    function ScoopTowTruck:Thread_DrawDebugUi()
        if Config["DebugMode"] ~= true then
            return
        end

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

        local nextY = 0.3
        local drawAlignedText = function(x, text)
            _DrawText2DThisFrame(x, nextY, text)
            nextY = nextY + 0.025
        end

        drawAlignedText(0.02, "Tow Truck State: " .. self:GetState())
        drawAlignedText(0.02, "Tow Truck Action: " .. self:GetAction())
        drawAlignedText(0.02, "Tow Truck Pos: " .. self:GetBedPos())


        if self.towingCarHandle ~= nil then
            drawAlignedText(0.02, " ")
            drawAlignedText(0.02, "Towing Car Rot: " .. GetEntityRotation(self.towingCarHandle, 2))

            drawAlignedText(0.02, " ")
            local truckRot = GetEntityRotation(self.truckHandle, 2)
            drawAlignedText(0.02, "Truck Rot: " .. truckRot)
    
            local attachPointRotWorld = GetEntityBoneRotation(self.truckHandle, self.attachBoneIndex)
            drawAlignedText(0.02, "Attach Point Rot (World): " .. attachPointRotWorld)
    
            local attachPointRotLocal = GetEntityBoneRotationLocal(self.truckHandle, self.attachBoneIndex)
            drawAlignedText(0.02, "Attach Point Rot (Local): " .. attachPointRotLocal)
    
            local modifiedTruckRot = vector3(attachPointRotWorld.x, truckRot.y, truckRot.z)
            drawAlignedText(0.02, "Modified Truck Rot: " .. modifiedTruckRot)
    
            local carRot = GetEntityRotation(self.towingCarHandle, 2)
            drawAlignedText(0.02, "Car Rot: " .. carRot)
    
            local attachRot = getOffsetBetweenRotations(modifiedTruckRot, carRot)
            drawAlignedText(0.02, "Attachment Rot: " .. attachRot)
        end

        local drawPos = self:GetHookStorageWorldPosition()
        DrawMarker(28, drawPos.x, drawPos.y, drawPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 128, 0, 100, false, true, 2, nil, nil, false)

        local drawPos2 = self:GetControlBoxStorageWorldPosition()
        DrawMarker(28, drawPos2.x, drawPos2.y, drawPos2.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 0, 122, 100, false, true, 2, nil, nil, false)
    end

-- #############################################
-- ###   Life Cycle Thread Functions | END   ###
-- #############################################



-- ##################################
-- ###   Misc Functions | START   ###
-- ##################################

    function ScoopTowTruck:Destroy(deleteVehicle)
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
        
        if self.cache.previewCar ~= nil then
            DeleteEntity(self.cache.previewCar)
            local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
            ResetEntityAlpha(towingCarHandle)
            self.cache.previewCar = nil
        end

        self:SetState(nil)
        self:SetAction(nil)
        self:SetBedPos(nil)
    end

    function ScoopTowTruck:GetHookStorageWorldPosition()
        local bonePos = GetWorldPositionOfEntityBone(self.truckHandle, self.hookBoneIndex)
        local boneRot = GetEntityBoneRotation(self.truckHandle, self.hookBoneIndex)

        return getOffsetFromCoordsInWorldCoords(bonePos, boneRot, self.config.hookRoot.offset)
    end

    function ScoopTowTruck:GetHookStorageEntityOffset()
        local pos = self:GetHookStorageWorldPosition()
        return GetOffsetFromEntityGivenWorldCoords(self.truckHandle, pos.x, pos.y, pos.z)
    end

    function ScoopTowTruck:GetControlBoxStorageWorldPosition()
        return GetOffsetFromEntityInWorldCoords(self.truckHandle, self.config.controlBoxOffset)
    end

    function ScoopTowTruck:GetAttachPointEntityOffset()
        local pos = self:GetAttachPointWorldPosition()
        return GetOffsetFromEntityGivenWorldCoords(self.truckHandle, pos.x, pos.y, pos.z)
    end

    function ScoopTowTruck:GetAttachPointWorldPosition()
        local bonePos = GetWorldPositionOfEntityBone(self.truckHandle, self.attachBoneIndex)
        local boneRot = GetEntityBoneRotation(self.truckHandle, self.attachBoneIndex)

        return getOffsetFromCoordsInWorldCoords(bonePos, boneRot, self.config.bedAttach.offset)
    end

    function ScoopTowTruck:GetAttachPointEntityOffset()
        local pos = self:GetAttachPointWorldPosition()
        return GetOffsetFromEntityGivenWorldCoords(self.truckHandle, pos.x, pos.y, pos.z)
    end

-- ################################
-- ###   Misc Functions | END   ###
-- ################################



-- ###################################
-- ###   State Functions | START   ###
-- ###################################

    function ScoopTowTruck:GetState()
        local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:State"]
        
        if bagValue == nil then
            self:SetState(ScoopTowTruck.STATE.NONE)
            return ScoopTowTruck.STATE.NONE
        end

        return bagValue
    end

    function ScoopTowTruck:SetState(state)
        Entity(self.truckHandle).state:set("DevJacob_Tow:State", state, true)
    end

-- #################################
-- ###   State Functions | END   ###
-- #################################



-- ####################################
-- ###   Action Functions | START   ###
-- ####################################

    function ScoopTowTruck:GetAction()
        local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:Action"]
        
        if bagValue == nil then
            self:SetAction(TowTruck.ACTION.NONE)
            return TowTruck.ACTION.NONE
        end

        return bagValue
    end

    function ScoopTowTruck:SetAction(action)
        Entity(self.truckHandle).state:set("DevJacob_Tow:Action", action, true)
    end

-- ##################################
-- ###   Action Functions | END   ###
-- ##################################



-- ################################
-- ###   UI Functions | START   ###
-- ################################

    function ScoopTowTruck:DisplayBedControlsThisFrame()
        local data = self.prompts.bedControls
        local prompts = {}
        
        if data["controlBed"] == true then
            prompts[#prompts + 1] = ("Press ~%s~ to raise bed"):format(toInputString("+towingBedRaise"))
            prompts[#prompts + 1] = ("Press ~%s~ to lower bed"):format(toInputString("+towingBedLower"))
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
            controlBed = false,
        }
    end

    function ScoopTowTruck:DisplayWinchControlsThisFrame()
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

    function ScoopTowTruck:DisplayPromptsThisFrame()
        self:DisplayBedControlsThisFrame()
        self:DisplayWinchControlsThisFrame()
    end

-- ##############################
-- ###   UI Functions | END   ###
-- ##############################



-- ##########################################
-- ###   Bed Movement Functions | START   ###
-- ##########################################

    function ScoopTowTruck:GetBedPos()
        local bagValue = Entity(self.truckHandle).state["DevJacob_Tow:BedPos"]
        
        if bagValue == nil then
            self:SetBedPos(0.0)
            return 0.0
        end

        return bagValue
    end

    function ScoopTowTruck:SetBedPos(posVal)
        Entity(self.truckHandle).state:set("DevJacob_Tow:BedPos", posVal, true)
        SetVehicleBulldozerArmPosition(self.truckHandle, posVal, true)
    end

    function ScoopTowTruck:CanControlBed()
        return self.cache.canControlBed == true
    end

    function ScoopTowTruck:LowerBed()
        local origState = self:GetState()
        local state = origState

        -- If the bed is already down, stop
        if state == ScoopTowTruck.STATE.LOWERED then
            return
        end

        -- Set the state to lowering to start movement
        state = ScoopTowTruck.STATE.LOWERING

        -- Process actual movement
        if state == ScoopTowTruck.STATE.LOWERING then
            local origPos = self:GetBedPos()
            local bedPos = origPos
            bedPos = bedPos + 0.01

            if bedPos >= self.config.bedPositions.lowered then
                state = ScoopTowTruck.STATE.LOWERED
                bedPos = self.config.bedPositions.lowered
            end

            if bedPos ~= origPos then
                self:SetBedPos(bedPos)
            end
        end

        -- Update the statebag if it has changed
        if state ~= origState then
            self:SetState(state)
        end
    end

    function ScoopTowTruck:RaiseBed()
        local origState = self:GetState()
        local state = origState

        -- If the bed is already down, stop
        if state == ScoopTowTruck.STATE.RAISED then
            return
        end

        -- Set the state to raising to start movement
        state = ScoopTowTruck.STATE.RAISING

        -- Process actual movement
        if state == ScoopTowTruck.STATE.RAISING then
            local origPos = self:GetBedPos()
            local bedPos = origPos
            bedPos = bedPos - 0.01

            if bedPos <= self.config.bedPositions.raised then
                state = ScoopTowTruck.STATE.RAISED
                bedPos = self.config.bedPositions.raised
            end

            if bedPos ~= origPos then
                self:SetBedPos(bedPos)
            end
        end

        -- Update the statebag if it has changed
        if state ~= origState then
            self:SetState(state)
        end
    end

-- ########################################
-- ###   Bed Movement Functions | END   ###
-- ########################################



-- ########################################
-- ###   Winch Hook Functions | START   ###
-- ########################################

    function ScoopTowTruck.GetHookThread(towTruck)
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
                            local bedAttachPos = towTruck:GetHookStorageWorldPosition()
                            local ropeLength = #(lastCastResult.endCoords - bedAttachPos)
                            local newRopeHandle = AddRope(carPos.x, carPos.y, carPos.z, 0.0, 0.0, 0.0, ropeLength, 3, ropeLength, 1.0, 0.5, false, true, true, 1.0, true, 0)
                            towTruck.hookRopeHandle = newRopeHandle
                            ActivatePhysics(towTruck.hookRopeHandle)
                    
                            -- Attach the rope to the car
                            AttachEntitiesToRope(towTruck.hookRopeHandle, towTruck.truckHandle, lastCastResult.entityHit, 
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

    function ScoopTowTruck:IsHookInUse()
        return self.hookPropHandle ~= nil
    end

    function ScoopTowTruck:GrabHookAsync(ped)
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

            local truckAttachPos = self:GetHookStorageWorldPosition()
            local hookAttachPos = GetOffsetFromEntityInWorldCoords(self.hookPropHandle, 0.0, 0.0, 0.03)
            AttachEntitiesToRope(self.hookRopeHandle, self.truckHandle, self.hookPropHandle, 
                truckAttachPos.x, truckAttachPos.y, truckAttachPos.z,
                hookAttachPos.x, hookAttachPos.y, hookAttachPos.z,
                5.0, false, false, nil, nil)

            _promise:resolve()
        end

        runFunc()
        return _promise

    end


-- ######################################
-- ###   Winch Hook Functions | END   ###
-- ######################################



-- ########################################
-- ###   Car Attach Functions | START   ###
-- ########################################

    function ScoopTowTruck:GetTowingCarNetId()
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

    function ScoopTowTruck:SetTowingCar(car)
        Entity(self.truckHandle).state:set("DevJacob_Tow:TowingCar", car, true)
        self.towingCarHandle = ternary(car == nil, nil, NetToObj(car))
    end

    function ScoopTowTruck:IsCarHooked()
        return self.towingCarHandle ~= nil
    end

    function ScoopTowTruck:AttachCarToBed()
        local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
        local carPos = GetEntityCoords(towingCarHandle, false)
        local bedPos = GetEntityCoords(self.truckHandle, false)
        local attachPos = self.config.bedAttach.offset + vector3(0.0, 0.0, carPos.z - bedPos.z - 0.30)
    

        local truckRot = GetEntityRotation(self.truckHandle, 2)
        local attachPointRotLocal = GetEntityBoneRotationLocal(self.truckHandle, self.attachBoneIndex)
        local modifiedTruckRot = vector3(attachPointRotLocal.x, truckRot.y, truckRot.z)
        local carRot = GetEntityRotation(self.towingCarHandle, 2)
        local attachRot = getOffsetBetweenRotations(modifiedTruckRot, carRot)
        local finalRot = vector3(0, attachRot.y, attachRot.z)
    
        AttachEntityToEntity(towingCarHandle, self.truckHandle, self.attachBoneIndex, attachPos, finalRot, false, false, false, false, 2, true)
    end
    
    function ScoopTowTruck:DetachCar()
        local towingCarHandle = NetToVeh(self:GetTowingCarNetId())
        DetachEntity(towingCarHandle, false, false)
    end

-- ######################################
-- ###   Car Attach Functions | END   ###
-- ######################################
