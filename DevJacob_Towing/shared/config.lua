Config = {}

Config["DebugMode"] = false

--[[
	Forces the rope for the remote to not clip through the ground,
	this can reduce performance and make the script run a lot more expensively
]]
Config["GroundRemoteRope"] = false


Config["MaxHookReach"] = 10.0


Config["RemoteModel"] = `w_am_digiscanner_reh`


Config["HookModel"] = `prop_v_hook_s`


Config["TowTrucks"] = {
	[`flatbed3`] = {
		truckType = "prop",
		truckModel = `flatbed3`,
		bedModel = `flatbed3_base`,
		bedExtraIndex = 1,
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
	},

	[`biftowmfd2`] = {
		truckType = "scoop",
		truckModel = `biftowmfd2`,
		controlBoxOffset = vector3(-1.1, -1.3, -0.4),
		hookRoot = {
			boneName = "attach_male",
			offset = vector3(0.0, 0.0, 0.0),
		},
		bedAttach = {
			boneName = "misc_z",
			offset = vector3(0.0, 0.0, 0.70),
		},
		bedPositions = {
			raised = 0.0,
			lowered = 0.25,
		},
	},
}