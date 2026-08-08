describe("game types: the definitions")

local ALL = { GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_DM, GAMEMODE_CTF, GAMEMODE_RUSH }

--[[
    Both map-gated modes, hosted or not. The roll drops a mode whose IsSupported
    says no, so a test about the odds has to say which map it is standing on.

    The real modules are put back rather than nil'd: TPG.Rush is a real table by
    the time these cases run, and leaving it nil breaks every later suite that
    expects it -- silently, since the roll treats a missing module as "this map
    cannot host it" and carries on.

    They are captured on first use rather than when this file loads, because
    every suite is loaded before any case runs: at load time TPG.Rush is still
    nil, and saving that would restore the same hole it is meant to avoid.
]]
local realCTF, realRush, captured

local function support(ctf, rush)
    if not captured then
        realCTF, realRush, captured = TPG.CTF, TPG.Rush, true
    end
    TPG.CTF  = { IsSupported = function() return ctf end }
    TPG.Rush = { IsSupported = function() return rush end }
end

local function supportAll() support(true, true) end

local function supportNone()
    TPG.CTF, TPG.Rush = realCTF, realRush
end

it("defines every GAMEMODE_ constant", function()
    for _, id in ipairs(ALL) do
        expect.truthy(TPG.GameTypes[id], "no TPG.GameTypes entry for game type " .. id)
    end
    expect.eq(table.Count(TPG.GameTypes), #ALL,
        "a game type exists in the table with no constant, or vice versa")
end)

it("keeps the constants distinct", function()
    local seen = {}
    for _, id in ipairs(ALL) do
        expect.falsy(seen[id], "two game types share the id " .. id)
        seen[id] = true
    end
end)

it("gives every mode the fields the HUD and round loop read", function()
    for id, gt in pairs(TPG.GameTypes) do
        expect.eq(gt.id, id, "entry " .. id .. " does not repeat its own key")
        expect.eq(type(gt.name), "string", "game type " .. id .. " name")
        expect.eq(type(gt.shortName), "string", "game type " .. id .. " shortName")
        expect.eq(type(gt.description), "string", "game type " .. id .. " description")
        expect.eq(type(gt.useDeathTickets), "boolean", "game type " .. id .. " useDeathTickets")
        expect.eq(type(gt.defaultCapMul), "number", "game type " .. id .. " defaultCapMul")
    end
end)

it("gives each mode its own short name", function()
    local seen = {}
    for id, gt in pairs(TPG.GameTypes) do
        expect.falsy(seen[gt.shortName], "two modes share the HUD pill text " .. gt.shortName)
        seen[gt.shortName] = true
        expect.truthy(#gt.shortName > 0, "game type " .. id .. " has an empty shortName")
    end
end)

describe("game types: how each one scores")

it("drains tickets on death in deathmatch only", function()
    expect.truthy(TPG.GameTypes[GAMEMODE_DM].useDeathTickets)
    for _, id in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_CTF, GAMEMODE_RUSH }) do
        expect.falsy(TPG.GameTypes[id].useDeathTickets,
            TPG.GameTypes[id].name .. " should not drain on death")
    end
end)

it("gives the point-ownership modes a positive drain", function()
    for _, id in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH }) do
        expect.truthy(TPG.GameTypes[id].defaultCapMul > 0,
            TPG.GameTypes[id].name .. " needs a drain or the round cannot end")
    end
end)

it("gives the modes that score their own way no passive drain", function()
    -- DM bleeds on death, CTF on flag captures, Rush on completed stages; a
    -- non-zero capMultiplier here would add a second, invisible scoring channel
    -- on top. Rush especially: a passive drain for standing on the live point
    -- would pay a team that never completes the hold.
    expect.eq(TPG.GameTypes[GAMEMODE_DM].defaultCapMul, 0)
    expect.eq(TPG.GameTypes[GAMEMODE_CTF].defaultCapMul, 0)
    expect.eq(TPG.GameTypes[GAMEMODE_RUSH].defaultCapMul, 0)
end)

describe("game types: the lookup")

it("returns the real entry for a real id", function()
    for _, id in ipairs(ALL) do
        expect.eq(TPG.GetGameType(id), TPG.GameTypes[id])
    end
end)

it("falls back to control points, never nil", function()
    expect.eq(TPG.GetGameType(nil), TPG.GameTypes[GAMEMODE_CP])
    expect.eq(TPG.GetGameType(999), TPG.GameTypes[GAMEMODE_CP])
    expect.eq(TPG.GetGameType("ctf"), TPG.GameTypes[GAMEMODE_CP])
end)

it("reads the short name off whatever the lookup returned", function()
    expect.eq(TPG.GetGameTypeName(GAMEMODE_KOTH), TPG.GameTypes[GAMEMODE_KOTH].shortName)
    expect.eq(TPG.GetGameTypeName(999), TPG.GameTypes[GAMEMODE_CP].shortName)
end)

describe("game types: the per-round roll")

it("only ever picks a mode that exists", function()
    math.randomseed(20260808)
    for _ = 1, 500 do
        local picked = TPG.SelectRandomGameType()
        expect.truthy(TPG.GameTypes[picked], "rolled an unknown game type: " .. tostring(picked))
    end
end)

it("never rolls a mode this map cannot host", function()
    -- Both gated modes off. Their weight is supposed to be redistributed across
    -- what is left, not silently handed to whichever mode came next in a chain.
    support(false, false)

    math.randomseed(1)
    local counts = {}
    for _ = 1, 800 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    expect.nils(counts[GAMEMODE_CTF], "CTF rolled on a map that cannot host it")
    expect.nils(counts[GAMEMODE_RUSH], "Rush rolled on a map that cannot host it")
    for _, id in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_DM }) do
        expect.truthy((counts[id] or 0) > 0,
            TPG.GameTypes[id].name .. " should still roll with the gated modes off")
    end

    supportNone()
end)

it("can roll the gated modes when the map supports them", function()
    supportAll()

    math.randomseed(7)
    local sawCTF, sawRush = false, false
    for _ = 1, 2000 do
        local picked = TPG.SelectRandomGameType()
        if picked == GAMEMODE_CTF  then sawCTF  = true end
        if picked == GAMEMODE_RUSH then sawRush = true end
        if sawCTF and sawRush then break end
    end

    expect.truthy(sawCTF,  "CTF never rolled despite being supported")
    expect.truthy(sawRush, "Rush never rolled despite being supported")
    supportNone()
end)

it("keeps every other mode rollable at a high ctfChance", function()
    -- The old bands were cumulative on one random(), so raising ctfChance ate
    -- KOTH's share rather than its own, and at 0.45 KOTH stopped rolling with
    -- nothing to say so. Weights are independent: a big CTF weight dilutes
    -- everything proportionally and starves nothing.
    supportAll()
    local saved = TPG.Config.ctfChance
    TPG.Config.ctfChance = 0.45

    math.randomseed(99)
    local counts = {}
    for _ = 1, 4000 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    for _, id in ipairs(ALL) do
        expect.truthy((counts[id] or 0) > 0,
            TPG.GameTypes[id].name .. " was starved by ctfChance = 0.45")
    end

    TPG.Config.ctfChance = saved
    supportNone()
end)

it("rolls every mode over enough rounds", function()
    supportAll()

    math.randomseed(4242)
    local counts = {}
    for _ = 1, 4000 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    for _, id in ipairs(ALL) do
        expect.truthy((counts[id] or 0) > 0,
            TPG.GameTypes[id].name .. " never rolled in 4000 rounds")
    end

    supportNone()
end)

it("gives no mode more of the roll than its weight allows", function()
    -- A guard on the cumulative arithmetic itself. If the running total is ever
    -- built out of order, one band swallows the rest of the range and its share
    -- runs far above its weight -- which is exactly the bug the old chain had.
    supportAll()

    math.randomseed(31337)
    local N, counts = 6000, {}
    for _ = 1, N do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    -- CP has the largest weight at 0.30; nothing should be anywhere near half.
    for _, id in ipairs(ALL) do
        expect.truthy((counts[id] or 0) / N < 0.5,
            TPG.GameTypes[id].name .. " took over half the roll")
    end

    supportNone()
end)

it("keeps the modes in their intended order of frequency", function()
    -- CP > KOTH > CTF > Rush > DM. The weights are private to sh_gametypes, so
    -- this reads them back off the roll itself -- which is the thing that has to
    -- be right anyway.
    supportAll()

    math.randomseed(8080)
    local counts = {}
    for _ = 1, 20000 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    local order = { GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_CTF, GAMEMODE_RUSH, GAMEMODE_DM }
    for i = 1, #order - 1 do
        local a, b = order[i], order[i + 1]
        expect.truthy((counts[a] or 0) > (counts[b] or 0),
            TPG.GameTypes[b].name .. " rolled more often than " ..
            TPG.GameTypes[a].name .. ", which should be the commoner mode")
    end

    supportNone()
end)

it("keeps deathmatch the rarest mode", function()
    -- DM is the one mode with no objective, so it is the one you want least
    -- often; it has drifted up before when another mode's share was cut.
    supportAll()

    math.randomseed(5150)
    local counts = {}
    for _ = 1, 20000 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    for _, id in ipairs(ALL) do
        if id ~= GAMEMODE_DM then
            expect.truthy((counts[id] or 0) > (counts[GAMEMODE_DM] or 0),
                TPG.GameTypes[id].name .. " is rarer than deathmatch")
        end
    end

    supportNone()
end)
