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
    -- Deliberately fewer points than the derived stage cap, so this tests the
    -- borrow and nothing else: with more, the cap would trim the list and a
    -- missing point would look like a borrow that dropped one.
    local n = math.min(3, TPG.Rush.MaxStages())
    withObjectives({ [GAMEMODE_CP] = points(n) })

    local stages = TPG.Rush.BuildStages()
    expect.eq(#stages, n, "should have taken every control point on offer")

    -- Same points, whatever the order: the borrow must not invent or drop any.
    local seen = {}
    for _, name in ipairs(names(stages)) do seen[name] = true end
    for i = 1, n do expect.truthy(seen["P" .. i], "P" .. i .. " went missing") end

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

    local cap = math.min(TPG.Config.rushStages, TPG.Rush.MaxStages())
    expect.eq(#TPG.Rush.BuildStages(), cap,
        "a 12-point map ran a number of stages neither knob asked for")

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

it("can decide a round on stage wins alone, at any stage count", function()
    -- A clean sweep has to land the loser on exactly zero. Short of that the
    -- stage count and the ticket pool disagree about when the round is over:
    -- too little and a team wins every stage and still loses on the kill bleed,
    -- too much and the round ends before the last stage is played.
    local savedTotal = TPG.Rush.total

    for _, n in ipairs({ 1, 2, 3, 6, 9 }) do
        TPG.Rush.total = n
        expect.eq(n * TPG.Rush.StageTicketLoss(), TPG.Config.startingTickets,
            "a clean sweep of " .. n .. " stages does not empty the pool exactly")
    end

    TPG.Rush.total = savedTotal
end)

it("lets a server override the per-stage loss and own the invariant", function()
    local savedLoss, savedTotal = TPG.Config.rushStageTicketLoss, TPG.Rush.total

    TPG.Config.rushStageTicketLoss = 75
    TPG.Rush.total = 4
    expect.eq(TPG.Rush.StageTicketLoss(), 75, "a configured loss was still derived over")

    TPG.Config.rushStageTicketLoss, TPG.Rush.total = savedLoss, savedTotal
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

describe("rush: the round time budget")

-- Worst case for the whole round, at whatever the config currently says. Kept
-- as a helper because every test below is really one assertion about this
-- number, and writing the arithmetic out five times is how the tests and the
-- implementation drift apart.
local function worstCase(stages)
    local perStage = TPG.Config.rushStageTimeLimit + TPG.Config.rushHoldTime
    return stages * perStage + (stages - 1) * TPG.Config.rushStageBreak
end

local function withTiming(limit, hold, brk, budget, fn)
    local saved = {
        TPG.Config.rushStageTimeLimit, TPG.Config.rushHoldTime,
        TPG.Config.rushStageBreak, TPG.Config.rushRoundBudget,
    }

    TPG.Config.rushStageTimeLimit = limit
    TPG.Config.rushHoldTime       = hold
    TPG.Config.rushStageBreak     = brk
    TPG.Config.rushRoundBudget    = budget

    fn()

    TPG.Config.rushStageTimeLimit, TPG.Config.rushHoldTime,
        TPG.Config.rushStageBreak, TPG.Config.rushRoundBudget =
        saved[1], saved[2], saved[3], saved[4]
end

it("keeps the shipped config inside its own budget", function()
    -- The whole reason the stage count is derived. If this fails, a Rush round
    -- runs longer than the budget says it may.
    expect.truthy(worstCase(TPG.Rush.MaxStages()) <= TPG.Config.rushRoundBudget,
        "the worst-case round is longer than rushRoundBudget allows")
end)

it("uses as much of the budget as it can", function()
    -- Fitting is not enough on its own: always returning 1 would also fit. One
    -- more stage has to genuinely not fit.
    expect.truthy(worstCase(TPG.Rush.MaxStages() + 1) > TPG.Config.rushRoundBudget,
        "another stage would have fit; the budget is being under-spent")
end)

it("drops stages when the break gets longer", function()
    -- The property that keeps the two knobs from fighting: adding break time
    -- shortens the round rather than extending it.
    withTiming(300, 60, 60, 1800, function()
        local short = TPG.Rush.MaxStages()

        withTiming(300, 60, 600, 1800, function()
            expect.truthy(TPG.Rush.MaxStages() < short,
                "a ten-minute break bought the same number of stages as a one-minute one")
        end)
    end)
end)

it("never derives a round with no stages in it", function()
    -- A budget too small for even one stage is a misconfiguration. Zero stages
    -- is not a shorter round, it is an unplayable one.
    withTiming(300, 60, 300, 1, function()
        expect.eq(TPG.Rush.MaxStages(), 1)
    end)
end)

it("stops raising stages once the ceiling is reached", function()
    -- rushStages is still a ceiling: a budget big enough for twenty stages must
    -- not produce twenty.
    withObjectives({ [GAMEMODE_CP] = points(30) })

    withTiming(300, 60, 300, 100000, function()
        expect.eq(#TPG.Rush.BuildStages(), TPG.Config.rushStages,
            "a huge budget overrode the rushStages ceiling")
    end)

    TPG.Maps.GetObjectives = savedGetObjectives
end)

TPG.Maps.GetObjectives = savedGetObjectives
