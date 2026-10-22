--[[--
    Armored-vehicle detection for the NPC bots (gamemode/bots/sv_bots.lua).

    A bot's targeting depends on whether an enemy player is in an armored
    vehicle: AT bots go after armor, rifles and support ignore it. This file
    decides "armored" once per contraption, when ACE recalculates its points,
    and stores the answer on the contraption as `con.TPG_Armored`. Nothing
    runs per tick: a bot reads the cached flag when relations are applied.

    A contraption counts as armored when its armor points reach
    `tpg_bots_armor_points` and it has a gun or an engine. Guns and racks share
    ACE's "Firepower" category, so a rack alone also qualifies.

    Relations refresh right away when someone enters or leaves a vehicle, so a
    tank that just got in or out is picked up without waiting for the brain's
    5 second pass. The leave hook runs the refresh on the next tick, once the
    player is no longer in the seat.

    @module tpg.bots.threat
    @realm server
]]

TPG.Bots = TPG.Bots or {}

local cvArmor = CreateConVar("tpg_bots_armor_points", "200", { FCVAR_ARCHIVE },
    "Armor points above which a vehicle counts as armored for bots.")

-- ACE point categories (ACE.ClassToType in ace/shared/sh_ace_functions.lua).
local CAT_FIREPOWER = "Firepower"  -- acf_gun, acf_rack, explosives
local CAT_ENGINES   = "Engines"    -- acf_engine

-- Decide and cache whether a contraption is armored.
local function classify(con)
    local perType = con.ACEPointsPerType or {}
    local hasWeapon = (perType[CAT_FIREPOWER] or 0) > 0 or (perType[CAT_ENGINES] or 0) > 0
    local armored = (con.ACEArmorPoints or 0) >= cvArmor:GetFloat() and hasWeapon

    con.TPG_Armored = armored
    return armored
end

hook.Add("ACE_OnContraptionPointsRecalculated", "TPG_BotsThreat", function(con)
    if istable(con) then classify(con) end
end)

--- Is this player in an armored vehicle, as far as the bots are concerned?
-- Reads the contraption behind the vehicle the player sits in. Anyone on
-- foot, in a vehicle with no contraption (a stock vehicle), or with no ACE
-- points yet is not armored.
-- @tparam Entity ent
-- @treturn boolean
-- @realm server
function TPG.Bots.IsArmoredTarget(ent)
    if not IsValid(ent) or not ent:IsPlayer() then return false end

    local veh = ent:GetVehicle()
    if not IsValid(veh) or not veh.CFW_GetContraption then return false end

    local con = veh:CFW_GetContraption()
    if not istable(con) then return false end

    if con.TPG_Armored == nil then classify(con) end
    return con.TPG_Armored == true
end

hook.Add("PlayerEnteredVehicle", "TPG_BotsThreatEnter", function()
    timer.Simple(0, TPG.Bots.RefreshRelations)
end)

hook.Add("PlayerLeaveVehicle", "TPG_BotsThreatLeave", function()
    timer.Simple(0, TPG.Bots.RefreshRelations)
end)
