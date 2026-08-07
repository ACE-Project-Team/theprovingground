describe("game types: the definitions")

local ALL = { GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_DM, GAMEMODE_CTF }

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
    for _, id in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_CTF }) do
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
    -- DM bleeds on death and CTF on flag captures; a non-zero capMultiplier
    -- here would add a second, invisible scoring channel on top.
    expect.eq(TPG.GameTypes[GAMEMODE_DM].defaultCapMul, 0)
    expect.eq(TPG.GameTypes[GAMEMODE_CTF].defaultCapMul, 0)
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

it("falls back to KOTH when CTF cannot be hosted", function()
    -- CTF borrows the map's KOTH point for the flag; with no CTF support its
    -- whole slice is supposed to land on KOTH, not error or return nil.
    TPG.CTF = { IsSupported = function() return false end }

    math.randomseed(1)
    local counts = {}
    for _ = 1, 800 do
        local picked = TPG.SelectRandomGameType()
        counts[picked] = (counts[picked] or 0) + 1
    end

    expect.nils(counts[GAMEMODE_CTF], "CTF rolled on a map that cannot host it")
    expect.truthy((counts[GAMEMODE_KOTH] or 0) > 0, "KOTH should absorb the CTF slice")

    TPG.CTF = nil
end)

it("can roll CTF when the map supports it", function()
    TPG.CTF = { IsSupported = function() return true end }

    math.randomseed(7)
    local sawCTF = false
    for _ = 1, 800 do
        if TPG.SelectRandomGameType() == GAMEMODE_CTF then sawCTF = true break end
    end

    expect.truthy(sawCTF, "CTF never rolled in 800 tries despite being supported")
    TPG.CTF = nil
end)

it("still rolls KOTH at the configured CTF chance", function()
    -- The bands are cumulative on one random(): CTF takes below ctfChance and
    -- KOTH the slice up to a hard-coded 0.45. If ctfChance ever reaches 0.45,
    -- KOTH stops appearing entirely and nothing says so.
    TPG.CTF = { IsSupported = function() return true end }

    math.randomseed(99)
    local sawKOTH = false
    for _ = 1, 2000 do
        if TPG.SelectRandomGameType() == GAMEMODE_KOTH then sawKOTH = true break end
    end

    expect.truthy(sawKOTH, "KOTH never rolled; check ctfChance against the 0.45 band")
    TPG.CTF = nil
end)

it("rolls every mode over enough rounds", function()
    TPG.CTF = { IsSupported = function() return true end }

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

    TPG.CTF = nil
end)
