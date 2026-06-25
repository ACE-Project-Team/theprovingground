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
-- binds usergroups to GMod teams at low sequential IDs (1, 2, 3...), and rank
-- scoreboards group players by those teams. Using low IDs here would overwrite
-- those role-teams on servers with custom ranks. Keep these well clear of them.
TEAM_UNASSIGNED = 0
TEAM_GREEN      = 2001
TEAM_RED        = 2002

-- Gamemode type constants
GAMEMODE_CP     = 1
GAMEMODE_KOTH   = 2
GAMEMODE_DM     = 3

-- Shared includes
include("config/sh_config.lua")
include("config/sh_teams.lua")
include("config/sh_armor.lua")
include("config/sh_weapons_config.lua")
include("config/sh_weapons.lua")
include("config/sh_gametypes.lua")
include("core/sh_utils.lua")
include("objectives/sh_controlpoint.lua")
include("maps/_loader.lua")