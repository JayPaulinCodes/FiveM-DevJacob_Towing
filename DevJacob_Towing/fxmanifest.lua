fx_version "cerulean"
lua54 "yes"
game "gta5"

author "DevJacob"
description "A realistic towing script for FiveM"
version "1.1.0"

shared_scripts {
	"shared/utils.lua",
	"shared/config.lua",
}

client_scripts {
	"client/utils.lua",
	"client/classes/towTruck.lua",
	"client/classes/scoopBased.lua",
	"client/classes/propBased.lua",
	"client/main.lua",
}