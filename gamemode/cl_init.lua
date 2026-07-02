--[[
    The Proving Ground - Client Entry Point
]]

include("shared.lua")

-- Console commands (client-side autocomplete/forwarding shim)
include("core/sh_commands.lua")

-- UI includes
include("ui/cl_hud.lua")
include("ui/cl_hud_economy.lua")
include("ui/cl_hud_compass.lua")
include("ui/cl_hud_objectives.lua")
include("ui/cl_hud_ctf.lua")
include("ui/cl_menu_team.lua")
include("ui/cl_menu_loadout.lua")
include("ui/cl_menu_weapons.lua")
include("ui/cl_menu_voting.lua")
include("ui/cl_binds.lua")