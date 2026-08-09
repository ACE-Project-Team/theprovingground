--[[--
    Server entry point, and the file that defines TPG's load order.

    Everything here runs on the server at map load. There are two separate
    lists and they do different jobs:

      * `AddCSLuaFile(path)` only SENDS a file to connecting clients. It does
        not run it, on either realm. A file that is AddCSLuaFile'd here but not
        `include`d in `cl_init.lua` reaches the client and is never executed.
      * `include(path)` runs the file, here, on the server.

    A shared (`sh_`) file therefore needs BOTH: an `AddCSLuaFile` here so the
    client has a copy, and an `include` on each realm that needs it. Forgetting
    the AddCSLuaFile gives you a server that works and clients that error on a
    nil table -- the single most common way to break this gamemode.

    Order matters, and the server `include` block below is in dependency order,
    not alphabetical. `sv_gamestate.lua` must come before anything that reads
    `TPG.State`, and `sv_rounds.lua` before the systems that hook round
    transitions. Adding a system usually means appending to the `systems/`
    group; adding a shared config means a line in BOTH lists.

    Nothing is `require`d and there are no Lua modules -- every file hangs its
    tables off the one global `TPG` created in `shared.lua`. See ARCHITECTURE.md
    for the wider picture, and `cl_init.lua` for the client's own include list.

    @module tpg.init
    @realm server
]]

AddCSLuaFile("shared.lua")
include("shared.lua")

-- Client files
AddCSLuaFile("cl_init.lua")

-- Shared configs
AddCSLuaFile("config/sh_config.lua")
AddCSLuaFile("config/sh_palette.lua")
AddCSLuaFile("config/sh_teams.lua")
AddCSLuaFile("config/sh_armor.lua")
AddCSLuaFile("config/sh_weapons_config.lua")
AddCSLuaFile("config/sh_weapons.lua")
AddCSLuaFile("config/sh_gear.lua")
AddCSLuaFile("config/sh_gametypes.lua")
AddCSLuaFile("config/sh_ranks.lua")
AddCSLuaFile("core/sh_utils.lua")
AddCSLuaFile("core/sh_commands.lua")
AddCSLuaFile("objectives/sh_controlpoint.lua")
AddCSLuaFile("maps/_loader.lua")

-- Client player systems
AddCSLuaFile("player/cl_movement.lua")

-- Client UI
AddCSLuaFile("ui/cl_hud.lua")
AddCSLuaFile("ui/cl_hud_prep.lua")
AddCSLuaFile("ui/cl_hud_economy.lua")
AddCSLuaFile("ui/cl_hud_compass.lua")
AddCSLuaFile("ui/cl_hud_objectives.lua")
AddCSLuaFile("ui/cl_hud_ctf.lua")
AddCSLuaFile("ui/cl_hud_rush.lua")
AddCSLuaFile("ui/cl_hud_overtime.lua")
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
include("player/sv_repair.lua")
include("player/sv_protection.lua")
include("player/sv_afk.lua")

include("systems/sv_entrestrictions.lua")
include("systems/sv_ace_integration.lua")
include("systems/sv_ace_permission.lua")
include("systems/sv_proptracking.lua")
include("systems/sv_economy.lua")
include("systems/sv_gear.lua")
include("systems/sv_underdog.lua")
include("systems/sv_stats.lua")
include("systems/sv_duplication.lua")
include("systems/sv_vehicles.lua")
include("systems/sv_commendations.lua")

include("objectives/sv_objectives.lua")
include("objectives/sv_ctf.lua")
include("objectives/sv_rush.lua")
include("voting/sv_voting.lua")

-- Ship the Exo 2 font (point tool HUD) to clients.
for _, w in ipairs({ "400", "600", "700", "800" }) do
    resource.AddFile("resource/fonts/Exo2-" .. w .. ".ttf")
end

--[[--
    Gamemode boot.

    The real work is deferred 3 seconds behind a `timer.Simple`, deliberately:
    ACE and E2SF Sandbox are separate addons that finish loading after the
    gamemode does, so validating them (or reading anything they define) at
    Initialize time reports them missing on a server where they are installed
    and fine.

    After the delay this validates the addon dependencies, loads the per-map
    config (`TPG.Maps.Load`), and starts the first round through the
    wait-for-players window rather than immediately, so fast loaders can't
    build for 30 seconds before slow loaders arrive.

    The console commands set here are engine sandbox settings, not TPG config.
    `sbox_maxprops` is set high on purpose: TPG governs builds with its own
    per-team prop/weight/point limits (`TPG.State.maxLimits`), and the engine's
    per-player cap should never be the thing that stops a spawn.

    @realm server
]]
function GM:Initialize()
    self.BaseClass.Initialize(self)
    
    timer.Simple(3, function()
        TPG.Config.ValidateACE()
        TPG.Config.ValidateE2SFSandbox()
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