--[[
    The Proving Ground - Expression 2 functions

    Team-scoped intel: every function only ever returns data about the chip
    owner's OWN team. If you're on Green you get nothing about Red, and vice
    versa. Spectators/unassigned get empty results.

    Embedded in the gamemode (gamemodes/theprovingground/lua/...), so it loads
    through Wire's normal core/custom scan without a separate addon.
]]

E2Lib.RegisterExtension("tpg", true,
    "Team-scoped info for The Proving Ground (you only ever see your own team).")

-- ── Helpers ────────────────────────────────────────────────────────────────
local function ownerTeam(self)
    local ply = self.player
    return (IsValid(ply) and ply:IsPlayer()) and ply:Team() or 0
end

local function onTeam(t)
    return t == TEAM_GREEN or t == TEAM_RED
end

-- True only when `ent` is a player on the SAME team as the chip owner.
local function isTeammate(self, ent)
    if not (IsValid(ent) and ent:IsPlayer()) then return false end
    local t = ownerTeam(self)
    return onTeam(t) and ent:Team() == t
end

local function armorName(ply)
    local id = tonumber(ply:GetPData("TPG_Armor", 1)) or 1
    local a  = TPG.Armor and TPG.Armor[id]
    return a and a.name or "Unknown"
end

local function pdataStr(ply, key)
    return tostring(ply:GetPData("TPG_" .. key, "") or "")
end

-- ── Team-wide queries ───────────────────────────────────────────────────────
__e2setcost(5)

-- Number of players on your team.
e2function number tpgTeamCount()
    local t = ownerTeam(self)
    if not onTeam(t) then return 0 end
    return team.NumPlayers(t)
end

-- Your team's display name ("" if you aren't on a team).
e2function string tpgTeamName()
    local t = ownerTeam(self)
    if not onTeam(t) then return "" end
    return (TPG.GetTeamData(t) or {}).name or ""
end

-- Array of player entities on your team. Combine with :pos(), :name() etc.
e2function array tpgTeammates()
    local out = {}
    local t = ownerTeam(self)
    if not onTeam(t) then return out end
    for _, ply in ipairs(team.GetPlayers(t)) do
        out[#out + 1] = ply
    end
    return out
end

-- Array of the names of everyone on your team.
e2function array tpgTeammateNames()
    local out = {}
    local t = ownerTeam(self)
    if not onTeam(t) then return out end
    for _, ply in ipairs(team.GetPlayers(t)) do
        out[#out + 1] = ply:Nick()
    end
    return out
end

-- ── Per-player getters (teammates only) ─────────────────────────────────────
__e2setcost(3)

-- 1 if this player is on your team, else 0.
e2function number entity:tpgIsTeammate()
    return isTeammate(self, this) and 1 or 0
end

-- Equipment of a teammate. Empty string for non-teammates / enemies.
e2function string entity:tpgArmor()
    if not isTeammate(self, this) then return "" end
    return armorName(this)
end

e2function string entity:tpgPrimary()
    if not isTeammate(self, this) then return "" end
    return pdataStr(this, "Primary")
end

e2function string entity:tpgSecondary()
    if not isTeammate(self, this) then return "" end
    return pdataStr(this, "Secondary")
end

e2function string entity:tpgSpecial()
    if not isTeammate(self, this) then return "" end
    return pdataStr(this, "Special")
end
