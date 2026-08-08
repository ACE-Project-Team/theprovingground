--[[
    Rush.

    This is the one suite that loads a SERVER file. The harness deliberately
    stops at the shared chain because the server files are hook and net plumbing
    the stubs cannot honestly drive -- but `TPG.Rush.BuildStages` is not that. It
    is a pure function of the map's objective list, it decides the shape of every
    Rush round, and it is the thing that would quietly break when a map config
    changes. Loading one file to test one pure function is worth the deviation;
    nothing here drives a hook or a net message, and anything that would need to
    (the hold clock, stage completion) is left to in-game testing.
]]

expect.load.dofile(expect.root .. "/gamemode/objectives/sv_rush.lua")

local savedGetObjectives = TPG.Maps.GetObjectives

-- Stand the map config up by hand: what BuildStages does with a list is the
-- thing under test, not which maps happen to ship with one.
local function withObjectives(byType)
    TPG.Maps.GetObjectives = function(gameType) return byType[gameType] or {} end
end

local function points(n, prefix)
    local list = {}
    for i = 1, n do
        list[i] = { pos = Vector(i * 100, 0, 0), name = (prefix or "P") .. i }
    end
    return list
end

local function names(list)
    local out = {}
    for i, obj in ipairs(list) do out[i] = obj.name end
    return out
end

describe("rush: building the stage list")

it("borrows the control point list when the map has no Rush block", function()
    withObjectives({ [GAMEMODE_CP] = points(4) })

    local stages = TPG.Rush.BuildStages()
    expect.eq(#stages, 4, "should have taken all four control points")

    -- Same points, whatever the order: the borrow must not invent or drop any.
    local seen = {}
    for _, name in ipairs(names(stages)) do seen[name] = true end
    for i = 1, 4 do expect.truthy(seen["P" .. i], "P" .. i .. " went missing") end

    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("prefers an authored Rush block over the control points", function()
    withObjectives({
        [GAMEMODE_CP]   = points(3, "CP"),
        [GAMEMODE_RUSH] = points(3, "RUSH"),
    })

    for _, name in ipairs(names(TPG.Rush.BuildStages())) do
        expect.truthy(name:find("RUSH", 1, true),
            "authored order was ignored in favour of the CP list: got " .. name)
    end

    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("keeps an authored order exactly as written", function()
    -- The whole reason to hand-author a block is the order; shuffling it would
    -- throw away the only thing it buys over the borrowed list.
    withObjectives({ [GAMEMODE_RUSH] = points(6, "A") })

    local wanted = { "A1", "A2", "A3", "A4", "A5", "A6" }
    for i, name in ipairs(names(TPG.Rush.BuildStages())) do
        expect.eq(name, wanted[i], "authored stage " .. i .. " moved")
    end

    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("shuffles the borrowed list so a map does not open the same way twice", function()
    withObjectives({ [GAMEMODE_CP] = points(6) })

    -- Any single shuffle can legitimately come back in order; a run of them all
    -- landing identically cannot. Compares first points across draws.
    math.randomseed(4242)
    local first, differed = TPG.Rush.BuildStages()[1].name, false
    for _ = 1, 40 do
        if TPG.Rush.BuildStages()[1].name ~= first then differed = true break end
    end

    expect.truthy(differed, "40 draws all opened on the same point; the list is not shuffled")
    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("never runs more stages than the config allows", function()
    withObjectives({ [GAMEMODE_CP] = points(12) })

    expect.eq(#TPG.Rush.BuildStages(), TPG.Config.rushStages,
        "a 12-point map should still run rushStages stages")

    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("runs short rather than revealing a point twice", function()
    -- A stage whose point the losing team already learned is not the same
    -- stage, so a small map gets fewer stages rather than a repeat.
    withObjectives({ [GAMEMODE_CP] = points(2) })

    local stages = TPG.Rush.BuildStages()
    expect.eq(#stages, 2)
    expect.ne(stages[1].name, stages[2].name, "the same point was revealed twice")

    TPG.Maps.GetObjectives = savedGetObjectives
end)

describe("rush: whether a map can host it")

it("supports any map that has control points", function()
    withObjectives({ [GAMEMODE_CP] = points(3) })
    expect.truthy(TPG.Rush.IsSupported())
    TPG.Maps.GetObjectives = savedGetObjectives
end)

it("refuses a map with nothing to reveal", function()
    -- The roll asks this before picking Rush; without it the mode would start a
    -- round that can only ever end on the kill bleed.
    withObjectives({})
    expect.falsy(TPG.Rush.IsSupported())
    TPG.Maps.GetObjectives = savedGetObjectives
end)

describe("rush: the ticket maths")

it("can decide a round on stage wins alone", function()
    -- A clean sweep has to be able to end it: if the stages cannot drain a full
    -- pool, a team could win every stage and still lose on the kill bleed.
    expect.truthy(TPG.Config.rushStageTicketLoss * TPG.Config.rushStages
        >= TPG.Config.startingTickets,
        "a team can win every stage without emptying the enemy pool")
end)

it("leaves the stage win worth more than the kill bleed", function()
    -- Kills are meant to be pressure between holds, not the scoring. One stage
    -- should outweigh a good few kills.
    expect.truthy(TPG.Config.rushKillTicketFrac < 1,
        "kills drain at full deathmatch rate; the point stops mattering")
end)

it("gives a stage long enough to be a fight, inside its own time limit", function()
    expect.truthy(TPG.Config.rushHoldTime > 0)
    expect.truthy(TPG.Config.rushStageTimeLimit > TPG.Config.rushHoldTime,
        "the stage times out before an uncontested hold could ever complete")
end)

TPG.Maps.GetObjectives = savedGetObjectives
