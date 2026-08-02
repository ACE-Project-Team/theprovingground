--- The Proving Ground team-info library.
-- Team-scoped: every call only returns data about the chip owner's OWN team.
-- Enemy names, positions and equipment are never exposed.
-- @name tpg
-- @class library
-- @libtbl tpg_library
SF.RegisterLibrary("tpg")

return function(instance)

local tpg_library  = instance.Libraries.tpg
local ents_methods = instance.Types.Entity.Methods
local getent       = instance.Types.Entity.GetEntity
local sanitize     = instance.Sanitize

-- ── Helpers ────────────────────────────────────────────────────────────────
local function ownerTeam()
    local ply = instance.player
    return (IsValid(ply) and ply:IsPlayer()) and ply:Team() or 0
end

local function onTeam(t)
    return t == TEAM_GREEN or t == TEAM_RED
end

local function isTeammate(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local t = ownerTeam()
    return onTeam(t) and ply:Team() == t
end

local function armorName(ply)
    local id = tonumber(ply:GetPData("TPG_Armor", 1)) or 1
    local a  = TPG.Armor and TPG.Armor[id]
    return a and a.name or "Unknown"
end

local function pdataStr(ply, key)
    return tostring(ply:GetPData("TPG_" .. key, "") or "")
end

local function loadoutOf(ply)
    return {
        primary   = pdataStr(ply, "Primary"),
        secondary = pdataStr(ply, "Secondary"),
        special   = pdataStr(ply, "Special"),
        armor     = armorName(ply),
    }
end

-- ── Library functions ───────────────────────────────────────────────────────

--- Number of players on your team.
-- @server
-- @return number Player count (0 if you aren't on a team)
function tpg_library.getTeamCount()
    local t = ownerTeam()
    if not onTeam(t) then return 0 end
    return team.NumPlayers(t)
end

--- Your team's display name.
-- @server
-- @return string Name, or "" if you aren't on a team
function tpg_library.getTeamName()
    local t = ownerTeam()
    if not onTeam(t) then return "" end
    return (TPG.GetTeamData(t) or {}).name or ""
end

--- Array of the player entities on your team.
-- @server
-- @return table Array of players
function tpg_library.getTeammates()
    local out = {}
    local t = ownerTeam()
    if not onTeam(t) then return sanitize(out) end
    for _, ply in ipairs(team.GetPlayers(t)) do
        out[#out + 1] = ply
    end
    return sanitize(out)
end

--- Full roster of your team: an array of tables, each
--- { player = entity, name = string, pos = vector,
---   primary, secondary, special, armor = strings }.
-- @server
-- @return table Roster array
function tpg_library.getRoster()
    local out = {}
    local t = ownerTeam()
    if not onTeam(t) then return sanitize(out) end
    for _, ply in ipairs(team.GetPlayers(t)) do
        local lo = loadoutOf(ply)
        out[#out + 1] = {
            player    = ply,
            name      = ply:Nick(),
            pos       = ply:GetPos(),
            primary   = lo.primary,
            secondary = lo.secondary,
            special   = lo.special,
            armor     = lo.armor,
        }
    end
    return sanitize(out)
end

--- Loadout of a teammate: { primary, secondary, special, armor }.
--- Returns an empty table for enemies / non-players.
-- @server
-- @return table Loadout
function ents_methods:tpgGetLoadout()
    local ply = getent(self)
    if not isTeammate(ply) then return {} end
    return sanitize(loadoutOf(ply))
end

--- Whether this player is on your team.
-- @server
-- @return boolean True if a teammate
function ents_methods:tpgIsTeammate()
    return isTeammate(getent(self))
end

end
