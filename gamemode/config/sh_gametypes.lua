--[[--
    Game type definitions and the per-round roll that picks one.

    `TPG.GameTypes` is a table keyed by the `GAMEMODE_*` constants from
    @{tpg}. Each entry carries what the HUD shows and how the round drains
    tickets:

        id               the GAMEMODE_* constant, repeated in the entry
        name             full name, for menus
        shortName        what the HUD pill shows
        description      one line, shown on the round intro
        useDeathTickets  true drains tickets on death instead of by point
                         ownership; deathmatch is the only one that does
        defaultCapMul    ticket drain per unit of point ownership, used when
                         the map config does not override it

    Both teams start with a pool of tickets and scoring drains the *losing*
    side's pool, so a mode is defined by what makes the other team bleed.
    A mode that scores some other way sets `defaultCapMul = 0` and does its own
    accounting, the way CTF does in `objectives/sv_ctf.lua`.

    Adding a mode is a five-step change and this file is two of the five;
    `ARCHITECTURE.md` walks through all of them.

    @module tpg.gametypes
    @realm shared
]]

TPG.GameTypes = {
    [GAMEMODE_CP] = {
        id              = GAMEMODE_CP,
        name            = "Control Points",
        -- Spelled out rather than "CP": the abbreviation reads as an initialism
        -- nobody outside the gamemode knows, and the HUD pill sizes itself to
        -- whatever string it's given (TPG.UI.Pill), so length costs nothing.
        shortName       = "Control Point",
        description     = "Capture and hold control points",
        useDeathTickets = false,
        defaultCapMul   = 0.02,
    },
    [GAMEMODE_KOTH] = {
        id              = GAMEMODE_KOTH,
        name            = "King of the Hill",
        shortName       = "KOTH",
        description     = "Hold the central point",
        useDeathTickets = false,
        defaultCapMul   = 0.15,
    },
    [GAMEMODE_DM] = {
        id              = GAMEMODE_DM,
        name            = "Deathmatch",
        shortName       = "DM",
        description     = "Destroy enemy vehicles",
        useDeathTickets = true,
        defaultCapMul   = 0,
    },
    [GAMEMODE_CTF] = {
        id              = GAMEMODE_CTF,
        name            = "Capture the Flag",
        shortName       = "CTF",
        description     = "Steal the enemy flag, bring it back to your base",
        useDeathTickets = false,
        -- Scoring is handled by flag captures (objectives/sv_ctf.lua), not the
        -- passive control-point drain, so no cap multiplier here.
        defaultCapMul   = 0,
    },
}

--[[
    Slot split: CP 40% / CTF 25% / KOTH 20% / DM 15%. CP is the most common mode
    (bumped from 30% after the last event); DM stays deliberately rare. CTF is
    its own mode -- it borrows the map's KOTH capture point as the flag's home
    (TPG.CTF.GetFlagPoint), it does NOT replace a KOTH round. On a map that
    can't host a flag, CTF's slice falls through to KOTH.

    The bands are cumulative thresholds on one math.random(), and only the first
    one is configurable. Raising TPG.Config.ctfChance therefore takes its extra
    share out of KOTH, not out of CP, because the next threshold is a hard 0.45:
    at ctfChance = 0.45 KOTH stops rolling at all. Move the 0.45 with it if that
    is not what you wanted.
]]
local function RollGameType()
    local roll = math.random()

    if roll < (TPG.Config.ctfChance or 0.25) then
        if TPG.CTF and TPG.CTF.IsSupported and TPG.CTF.IsSupported() then
            return GAMEMODE_CTF
        end
        return GAMEMODE_KOTH
    elseif roll < 0.45 then
        return GAMEMODE_KOTH
    elseif roll < 0.60 then
        return GAMEMODE_DM
    else
        return GAMEMODE_CP
    end
end

local lastGameType

--- Pick the game type for the next round.
-- Called from `TPG.Rounds.Setup`. Includes a single anti-repeat reroll when the
-- same mode comes up twice running, which halves the odds of a back-to-back
-- repeat without ever forbidding one.
-- @treturn number A `GAMEMODE_*` constant.
-- @realm shared
function TPG.SelectRandomGameType()
    local picked = RollGameType()

    -- Anti-repeat: one reroll when the same mode comes up twice in a row, which
    -- halves the odds of a back-to-back repeat without ever forbidding it.
    if picked == lastGameType then
        picked = RollGameType()
    end

    lastGameType = picked
    return picked
end

--- Look up a game type definition.
-- Never returns nil: an unknown id falls back to control points, so callers on
-- the HUD path can read `.name` off the result without guarding. That also
-- means a typo'd id shows up as a round that looks like CP rather than as an
-- error, which is worth knowing when a new mode appears not to take effect.
-- @tparam number typeId A `GAMEMODE_*` constant.
-- @treturn table The definition; see the module summary for its fields.
-- @realm shared
function TPG.GetGameType(typeId)
    return TPG.GameTypes[typeId] or TPG.GameTypes[GAMEMODE_CP]
end

--- The short display name for a game type, as shown on the HUD pill.
-- @tparam number typeId A `GAMEMODE_*` constant.
-- @treturn string
-- @realm shared
function TPG.GetGameTypeName(typeId)
    local gt = TPG.GetGameType(typeId)
    return gt.shortName
end