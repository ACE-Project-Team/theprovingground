--[[--
    Client entry point: the client's include list, and nothing else.

    This runs on every connecting client. It only `include`s -- a file has to
    already have been sent by an `AddCSLuaFile` in `init.lua` for the include
    to find it, so the two lists have to be kept in step. A client-side file
    added here but not AddCSLuaFile'd there fails to load with a file-not-found
    that names the client file, not the missing server line.

    Note that this list is SHORTER than init.lua's AddCSLuaFile block, and that
    is correct: shared config files (`config/sh_*.lua`, `maps/_loader.lua`,
    `objectives/sh_controlpoint.lua`) are shipped to the client but included by
    `shared.lua`, not here, so they load on both realms from one place.

    Order barely matters on this side -- the UI files register hooks and build
    panels on demand rather than reading each other at load time -- with the
    exception of `shared.lua`, which must be first because it creates `TPG`.

    @module tpg.clinit
    @realm client
]]

include("shared.lua")

-- Console commands (client-side autocomplete/forwarding shim)
include("core/sh_commands.lua")

-- Keeps predicted movement in step with the speed the server actually set
include("player/cl_movement.lua")

-- UI includes
include("ui/cl_hud.lua")
include("ui/cl_hud_prep.lua")
include("ui/cl_hud_economy.lua")
include("ui/cl_hud_compass.lua")
include("ui/cl_hud_objectives.lua")
include("ui/cl_hud_ctf.lua")
include("ui/cl_hud_rush.lua")
include("ui/cl_hud_overtime.lua")
include("ui/cl_menu_team.lua")
include("ui/cl_menu_loadout.lua")
include("ui/cl_menu_weapons.lua")
include("ui/cl_menu_voting.lua")
include("ui/cl_menu_profile.lua")
include("ui/cl_menu_manual.lua")
include("ui/cl_binds.lua")