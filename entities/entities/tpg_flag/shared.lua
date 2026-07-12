--[[
    TPG CTF Flag (one neutral flag)

    A single neutral flag sits on the map's KOTH point. Either team can grab it;
    while a team carries it, the enemy's tickets drain (a "mobile hill"). On the
    carrier's death it drops, and after a timeout it returns to the point. No
    base delivery -- scoring is by possession, so it only needs the KOTH point.

    Visual is an AAS-style waving cloth on a pole (cl_init.lua), tinted by the
    carrying team (grey while neutral).
]]

ENT.Type    = "anim"
ENT.Base    = "base_gmodentity"

ENT.PrintName         = "TPG Flag"
ENT.Category          = "The Proving Ground"
ENT.Spawnable         = false
ENT.AdminOnly         = true
ENT.DisableDuplicator = true

ENT.STATE_HOME    = 0   -- neutral, parked on the KOTH point
ENT.STATE_CARRIED = 1
ENT.STATE_DROPPED = 2

function ENT:SetupDataTables()
    self:NetworkVar("Int",    0, "FlagState")    -- STATE_*
    self:NetworkVar("Int",    1, "PossessTeam")  -- team currently carrying (0 = none)
    self:NetworkVar("Entity", 0, "Carrier")
    self:NetworkVar("Float",  0, "CarryEnd")     -- CurTime() the carry auto-returns (0 = not carried)
end
