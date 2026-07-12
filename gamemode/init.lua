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
AddCSLuaFile("config/sh_weapons_config.lua")
AddCSLuaFile("config/sh_weapons.lua")
AddCSLuaFile("config/sh_gametypes.lua")
AddCSLuaFile("config/sh_ranks.lua")
AddCSLuaFile("core/sh_utils.lua")
AddCSLuaFile("core/sh_commands.lua")
AddCSLuaFile("objectives/sh_controlpoint.lua")
AddCSLuaFile("maps/_loader.lua")

-- Client UI
AddCSLuaFile("ui/cl_hud.lua")
AddCSLuaFile("ui/cl_hud_prep.lua")
AddCSLuaFile("ui/cl_hud_economy.lua")
AddCSLuaFile("ui/cl_hud_compass.lua")
AddCSLuaFile("ui/cl_hud_objectives.lua")
AddCSLuaFile("ui/cl_hud_ctf.lua")
AddCSLuaFile("ui/cl_menu_team.lua")
AddCSLuaFile("ui/cl_menu_loadout.lua")
AddCSLuaFile("ui/cl_menu_weapons.lua")
AddCSLuaFile("ui/cl_menu_voting.lua")
AddCSLuaFile("ui/cl_menu_profile.lua")
AddCSLuaFile("ui/cl_menu_manual.lua")
AddCSLuaFile("ui/cl_binds.lua")

-- Server includes
include("core/sv_networking.lua")
include("core/sv_gamestate.lua")
include("maps/sv_custom_points.lua")
include("core/sv_rounds.lua")
include("core/sv_prep.lua")
include("core/sv_commands.lua")
include("core/sh_commands.lua")
include("core/sv_weapons.lua")
include("core/sv_ulx_compat.lua")

include("player/sv_spawning.lua")
include("player/sv_loadout.lua")
include("player/sv_teams.lua")
include("player/sv_protection.lua")
include("player/sv_afk.lua")

include("systems/sv_ace_integration.lua")
include("systems/sv_proptracking.lua")
include("systems/sv_economy.lua")
include("systems/sv_underdog.lua")
include("systems/sv_stats.lua")
include("systems/sv_duplication.lua")
include("systems/sv_vehicles.lua")
include("systems/sv_commendations.lua")

include("objectives/sv_objectives.lua")
include("objectives/sv_ctf.lua")
include("voting/sv_voting.lua")

-- Ship the Exo 2 font (point tool HUD) to clients.
for _, w in ipairs({ "400", "600", "700", "800" }) do
    resource.AddFile("resource/fonts/Exo2-" .. w .. ".ttf")
end

-- Initialize gamemode
function GM:Initialize()
    self.BaseClass.Initialize(self)
    
    timer.Simple(3, function()
        TPG.Config.ValidateACE()
        TPG.Maps.Load()
        -- First round starts through the wait-for-players window, so fast
        -- loaders can't get a head start on slower ones.
        TPG.Rounds.BeginInitialWait()
        
        -- Server settings
        RunConsoleCommand("sbox_godmode", "0")
        RunConsoleCommand("sbox_playershurtplayers", "1")
        RunConsoleCommand("sv_alltalk", "0")
        RunConsoleCommand("mp_falldamage", "1")
        -- TPG governs builds with its own per-team prop/weight/point limits
        -- (see TPG.State.maxLimits), so the engine's per-player sbox cap should
        -- sit well above them and never be the thing that stops a spawn. 200 was
        -- far too low and just annoyed players; raise it out of the way.
        RunConsoleCommand("sbox_maxprops", "2000")
        RunConsoleCommand("wire_holograms_max", "150")
    end)
end