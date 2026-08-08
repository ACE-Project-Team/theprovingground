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
    [GAMEMODE_RUSH] = {
        id              = GAMEMODE_RUSH,
        name            = "Rush",
        shortName       = "Rush",
        description     = "One point at a time - take it and hold it",
        useDeathTickets = false,
        -- Scoring is per stage (objectives/sv_rush.lua), not the passive
        -- ownership drain: holding the live point is worth nothing until the
        -- hold completes, which is what makes a stage a race rather than a
        -- slow bleed.
        defaultCapMul   = 0,
    },
}

--[[
    Slot split: CP 30% / CTF 25% / KOTH 20% / DM 15% / Rush 10%. CP is still the
    most common mode; DM stays deliberately rare. CTF is its own mode -- it
    borrows the map's KOTH capture point as the flag's home
    (TPG.CTF.GetFlagPoint), it does NOT replace a KOTH round. On a map that
    can't host a flag, CTF's slice falls through to KOTH. Rush took its 10% out
    of CP, which had the most to spare.

    Rush needs no map support beyond a control point list, since it reveals the
    map's CP points one at a time (TPG.Rush.BuildStages), so unlike CTF it has
    no fallthrough -- any map that can host CP can host Rush.

    The bands were cumulative thresholds on one math.random(), which made every
    threshold after the first depend on the ones before it: raising ctfChance
    silently ate KOTH's share rather than CP's, and at ctfChance = 0.45 KOTH
    stopped rolling entirely with nothing to show for it. They are weights now.
    Changing one changes only its own share of the roll, and a mode that cannot
    run this round is dropped from the draw rather than falling through to
    whatever the next threshold happened to be.
]]
local WEIGHTS = {
    [GAMEMODE_CP]   = 0.30,
    [GAMEMODE_CTF]  = 0.25,   -- TPG.Config.ctfChance overrides this one
    [GAMEMODE_KOTH] = 0.20,
    [GAMEMODE_DM]   = 0.15,
    [GAMEMODE_RUSH] = 0.10,
}

-- Whether a mode can run on this map at all. Anything absent can always run.
local SUPPORTED = {
    [GAMEMODE_CTF] = function()
        return TPG.CTF and TPG.CTF.IsSupported and TPG.CTF.IsSupported() or false
    end,
    [GAMEMODE_RUSH] = function()
        return TPG.Rush and TPG.Rush.IsSupported and TPG.Rush.IsSupported() or false
    end,
}

-- The modes that can run right now, lowest id first. Sorted rather than left in
-- pairs() order, which Lua does not promise: the same weights would otherwise
-- map to different modes on different servers, and differently between runs of
-- the tests.
local function eligible()
    local ids = {}
    for id in pairs(WEIGHTS) do ids[#ids + 1] = id end
    table.sort(ids)

    local pool, total = {}, 0
    for _, id in ipairs(ids) do
        local weight = (id == GAMEMODE_CTF) and (TPG.Config.ctfChance or WEIGHTS[id]) or WEIGHTS[id]
        local supported = SUPPORTED[id]

        if weight > 0 and (not supported or supported()) then
            total = total + weight
            pool[#pool + 1] = { id = id, upTo = total }
        end
    end

    return pool, total
end

local function RollGameType()
    local pool, total = eligible()

    -- Nothing at all could run: control points is the mode every map supports,
    -- and TPG.GetGameType already treats it as the safe answer.
    if total <= 0 then return GAMEMODE_CP end

    local roll = math.random() * total
    for _, entry in ipairs(pool) do
        if roll < entry.upTo then return entry.id end
    end

    -- Only reachable on a float landing exactly on the top of the range.
    return pool[#pool].id
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