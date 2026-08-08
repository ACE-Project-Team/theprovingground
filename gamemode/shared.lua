--[[--
    Shared entry point: the global namespace, the constants, and the include
    order for everything shared.

    A team-based vehicle combat gamemode for ACE (Armored Combat Extended).

    This file runs on both realms and runs *early*, so the constants it declares
    are available to every file that follows. Anything that mentions
    `TEAM_GREEN` or `GAMEMODE_CP` must therefore load after this, which is why
    the include list at the bottom is ordered rather than alphabetical.

    There are no Lua modules here and nothing is `require`d. Every file hangs
    its own sub-table off the single global `TPG`. See `ARCHITECTURE.md` for
    the load order in full and for how to add a game type.

    @module tpg
    @realm shared
]]

GM.Name     = "The Proving Ground"
GM.Author   = "RDC"
GM.Email    = "N/A"
GM.Website  = "N/A"

DeriveGamemode("sandbox")

-- Global namespace
TPG = TPG or {}

--[[--
    Team constants.

    GREEN and RED use a high ID range on purpose. ULX's "Manage Teams" (UTeam)
    registers usergroup teams starting at index 21 and force-assigns members
    onto them; a high range keeps TPG clear of both ID overlap and UTeam's
    auto-reset of teams in the 21-and-up band. The force-assignment itself is
    suppressed in `core/sv_ulx_compat.lua`.

    Spectators and anyone who hasn't picked yet sit on `TEAM_UNASSIGNED`, so
    most scoring paths guard with @{tpg.util.IsOnTeam} rather than testing for
    a specific team.

    @table Teams
    @field TEAM_UNASSIGNED 0, no team picked yet.
    @field TEAM_GREEN 2001
    @field TEAM_RED 2002
    @realm shared
]]
TEAM_UNASSIGNED = 0
TEAM_GREEN      = 2001
TEAM_RED        = 2002

--[[--
    Game type constants.

    The id a round runs under. Each one has an entry in `TPG.GameTypes`
    (`config/sh_gametypes.lua`) carrying its name, description and ticket
    behaviour, and each map config is keyed by these values.

    Adding one is a five-step change; `ARCHITECTURE.md` walks through it.

    @table GameTypes
    @field GAMEMODE_CP 1, control points.
    @field GAMEMODE_KOTH 2, king of the hill.
    @field GAMEMODE_DM 3, deathmatch; drains tickets on death rather than by
     point ownership.
    @field GAMEMODE_CTF 4, capture the flag. Only rolls on maps that define
     flag positions.
    @field GAMEMODE_RUSH 5, rush; one revealed point at a time, over several
     stages. Borrows the map's control point list, so it needs no map config
     of its own.
    @realm shared
]]
GAMEMODE_CP     = 1
GAMEMODE_KOTH   = 2
GAMEMODE_DM     = 3
GAMEMODE_CTF    = 4
GAMEMODE_RUSH   = 5

-- Shared includes
include("config/sh_config.lua")
include("config/sh_palette.lua")
include("config/sh_teams.lua")
include("config/sh_armor.lua")
include("config/sh_weapons_config.lua")
include("config/sh_weapons.lua")
include("config/sh_gear.lua")
include("config/sh_gametypes.lua")
include("config/sh_ranks.lua")
include("core/sh_utils.lua")
include("objectives/sh_controlpoint.lua")
include("maps/_loader.lua")