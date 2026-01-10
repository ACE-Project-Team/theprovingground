--[[
    The Proving Ground - Server Entry Point
]]

AddCSLuaFile("shared.lua")
include("shared.lua")

-- Client files
AddCSLuaFile("cl_init.lua")

-- Shared configs
AddCSLuaFile("config/sh_config.lua")
AddCSLuaFile("config/sh_teams.lua")
AddCSLuaFile("config/sh_armor.lua")
AddCSLuaFile("config/sh_weapons.lua")
AddCSLuaFile("config/sh_gametypes.lua")
AddCSLuaFile("core/sh_utils.lua")
AddCSLuaFile("maps/_loader.lua")

-- Client UI
AddCSLuaFile("ui/cl_hud.lua")
AddCSLuaFile("ui/cl_hud_compass.lua")
AddCSLuaFile("ui/cl_hud_objectives.lua")
AddCSLuaFile("ui/cl_menu_team.lua")
AddCSLuaFile("ui/cl_menu_loadout.lua")
AddCSLuaFile("ui/cl_menu_voting.lua")
AddCSLuaFile("ui/cl_binds.lua")

-- Server includes
include("core/sv_networking.lua")
include("core/sv_gamestate.lua")
include("core/sv_rounds.lua")
include("core/sv_commands.lua")

include("player/sv_spawning.lua")
include("player/sv_loadout.lua")
include("player/sv_teams.lua")
include("player/sv_protection.lua")
include("player/sv_afk.lua")

include("systems/sv_ace_integration.lua")
include("systems/sv_proptracking.lua")
include("systems/sv_duplication.lua")
include("systems/sv_vehicles.lua")
include("systems/sv_commendations.lua")

include("objectives/sv_objectives.lua")
include("voting/sv_voting.lua")

-- Initialize gamemode
function GM:Initialize()
    self.BaseClass.Initialize(self)
    
    timer.Simple(3, function()
        TPG.Config.ValidateACE()
        TPG.Maps.Load()
        TPG.Rounds.Setup()
        
        -- Server settings
        RunConsoleCommand("sbox_godmode", "0")
        RunConsoleCommand("sbox_playershurtplayers", "1")
        RunConsoleCommand("sv_alltalk", "0")
        RunConsoleCommand("mp_falldamage", "1")
        RunConsoleCommand("sbox_maxprops", "200")
        RunConsoleCommand("wire_holograms_max", "150")
    end)
end