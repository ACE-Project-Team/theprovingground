--[[
    The Proving Ground
    A team-based vehicle combat gamemode for ACE (Armored Combat Extended)
    
    shared.lua - Entry point for shared code
]]

GM.Name     = "The Proving Ground"
GM.Author   = "RDC"
GM.Email    = "N/A"
GM.Website  = "N/A"

DeriveGamemode("sandbox")

-- Global namespace
TPG = TPG or {}

-- Team constants
-- NOTE: GREEN/RED use a high ID range on purpose. ULX's "Manage Teams" (UTeam)
-- registers usergroup teams starting at index 21 and force-assigns members onto
-- them; a high range keeps TPG clear of both ID overlap and UTeam's auto-reset
-- of teams in [21, next). The force-assignment itself is suppressed in
-- core/sv_ulx_compat.lua.
TEAM_UNASSIGNED = 0
TEAM_GREEN      = 2001
TEAM_RED        = 2002

-- Gamemode type constants
GAMEMODE_CP     = 1
GAMEMODE_KOTH   = 2
GAMEMODE_DM     = 3
GAMEMODE_CTF    = 4

-- Shared includes
include("config/sh_config.lua")
include("config/sh_teams.lua")
include("config/sh_armor.lua")
include("config/sh_weapons_config.lua")
include("config/sh_weapons.lua")
include("config/sh_gametypes.lua")
include("config/sh_ranks.lua")
include("core/sh_utils.lua")
include("objectives/sh_controlpoint.lua")
include("maps/_loader.lua")