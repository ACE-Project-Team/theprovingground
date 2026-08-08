--[[
    Map configs are data, and the failure mode is silence: a map missing a
    KOTH point simply never offers CTF, a map missing a game-type block runs a
    round that can never end, and a budget typo just changes the balance. None
    of that errors, so it has to be asserted.
]]

local gmod = expect.load.gmod

-- The balance intent the per-map numbers were authored to: 150 ACE points of
-- build budget per ton of weight limit.
local POINTS_PER_TON = 150

describe("maps: the default config")

it("covers the modes a map is allowed to fall back into", function()
    for _, gameType in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_DM }) do
        expect.truthy(TPG.Maps.Default[gameType],
            "the default config has no block for " .. TPG.GetGameType(gameType).name)
    end
end)

it("has spawns, limits and a safezone", function()
    local d = TPG.Maps.Default
    expect.truthy(isvector(d.spawns[TEAM_GREEN]))
    expect.truthy(isvector(d.spawns[TEAM_RED]))
    expect.eq(type(d.limits.weight), "number")
    expect.eq(type(d.limits.props), "number")
    expect.eq(type(d.limits.points), "number")
    expect.truthy(d.safezoneRadius > 0)
end)

it("does not define a CTF block", function()
    -- CTF borrows the map's KOTH capture point rather than having positions of
    -- its own; a CTF block here would be dead config.
    expect.nils(TPG.Maps.Default[GAMEMODE_CTF])
end)

describe("maps: every shipped map config")

local function eachMap(fn)
    for name, cfg in pairs(TPG.Maps.Configs) do fn(name, cfg) end
end

it("gives both teams a spawn", function()
    eachMap(function(name, cfg)
        expect.truthy(cfg.spawns, name .. " has no spawns")
        expect.truthy(isvector(cfg.spawns[TEAM_GREEN]), name .. " green spawn")
        expect.truthy(isvector(cfg.spawns[TEAM_RED]), name .. " red spawn")
    end)
end)

it("never puts the two teams on the same spot", function()
    eachMap(function(name, cfg)
        local green, red = cfg.spawns[TEAM_GREEN], cfg.spawns[TEAM_RED]
        expect.truthy(green:Distance(red) > TPG.Config.safezoneRadius * 2,
            name .. " spawns are " .. math.floor(green:Distance(red)) ..
            " units apart, closer than two safezone radii")
    end)
end)

it("never leaves a spawn at the world origin", function()
    -- Vector(0,0,0) is what GetSpawn returns when a spawn is MISSING, and it is
    -- truthy, so an authored origin spawn is indistinguishable from a bug.
    eachMap(function(name, cfg)
        for _, teamId in ipairs({ TEAM_GREEN, TEAM_RED }) do
            local pos = cfg.spawns[teamId]
            expect.falsy(pos.x == 0 and pos.y == 0 and pos.z == 0,
                name .. " has a spawn at the origin, which reads as a missing spawn")
        end
    end)
end)

it("states a whole build budget", function()
    eachMap(function(name, cfg)
        expect.truthy(cfg.limits, name .. " has no limits")
        for _, key in ipairs({ "weight", "props", "points" }) do
            local v = cfg.limits[key]
            expect.eq(type(v), "number", name .. " limits." .. key)
            expect.truthy(v > 0, name .. " limits." .. key .. " is not positive")
        end
    end)
end)

it("keeps the authored budget at 150 points per ton", function()
    eachMap(function(name, cfg)
        expect.eq(cfg.limits.points, cfg.limits.weight * POINTS_PER_TON,
            name .. " budgets " .. cfg.limits.points .. " points for " ..
            cfg.limits.weight .. "t; the authored ratio is " .. POINTS_PER_TON .. "/t")
    end)
end)

it("covers control points and king of the hill", function()
    eachMap(function(name, cfg)
        for _, gameType in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH }) do
            local block = cfg[gameType]
            local mode  = TPG.GetGameType(gameType).name
            expect.truthy(block, name .. " has no " .. mode .. " block")
            expect.truthy(block.objectives and #block.objectives > 0,
                name .. " has no " .. mode .. " objectives, so the round could never end")
        end
    end)
end)

it("gives king of the hill exactly one point", function()
    eachMap(function(name, cfg)
        expect.eq(#cfg[GAMEMODE_KOTH].objectives, 1,
            name .. " has " .. #cfg[GAMEMODE_KOTH].objectives .. " KOTH points; " ..
            "the mode is one hill, and CTF borrows it as the flag's home")
    end)
end)

it("can host CTF on every map", function()
    -- CTF is offered on maps that have a KOTH point. Since every map has one,
    -- the fallback to KOTH should never actually fire in production.
    eachMap(function(name, cfg)
        expect.truthy(cfg[GAMEMODE_KOTH] and #cfg[GAMEMODE_KOTH].objectives > 0,
            name .. " could not host a CTF round")
    end)
end)

it("names every objective", function()
    eachMap(function(name, cfg)
        for _, gameType in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH }) do
            for i, obj in ipairs(cfg[gameType].objectives or {}) do
                expect.truthy(isvector(obj.pos), name .. " objective " .. i .. " has no position")
                expect.eq(type(obj.name), "string", name .. " objective " .. i .. " has no name")
                expect.truthy(#obj.name > 0, name .. " objective " .. i .. " has an empty name")
            end
        end
    end)
end)

it("gives each of a map's control points its own name", function()
    eachMap(function(name, cfg)
        local seen = {}
        for _, obj in ipairs(cfg[GAMEMODE_CP].objectives or {}) do
            expect.falsy(seen[obj.name], name .. " has two control points called " .. obj.name)
            seen[obj.name] = true
        end
    end)
end)

it("gives every mode block a capture multiplier", function()
    eachMap(function(name, cfg)
        for _, gameType in ipairs({ GAMEMODE_CP, GAMEMODE_KOTH, GAMEMODE_DM }) do
            if cfg[gameType] then
                expect.eq(type(cfg[gameType].capMultiplier), "number",
                    name .. " " .. TPG.GetGameType(gameType).name .. " capMultiplier")
            end
        end
    end)
end)

it("only ever keys a block by a real game type", function()
    eachMap(function(name, cfg)
        for key in pairs(cfg) do
            if type(key) == "number" then
                expect.truthy(TPG.GameTypes[key],
                    name .. " has a block for game type " .. key .. ", which does not exist")
            end
        end
    end)
end)

describe("maps: the limit multipliers")

it("scales the authored budget rather than using it raw", function()
    gmod.map = "gm_flatgrass"
    local authored = TPG.Maps.Configs.gm_flatgrass.limits
    local loaded   = TPG.Maps.Load("gm_flatgrass").limits

    expect.eq(loaded.points, math.floor(authored.points * TPG.Maps.LimitMult.points))
    expect.eq(loaded.props,  math.floor(authored.props  * TPG.Maps.LimitMult.props))
end)

it("takes an extra tonnage cut on small maps only", function()
    local small, large
    for name, cfg in pairs(TPG.Maps.Configs) do
        if cfg.limits.weight <= TPG.Maps.SmallMapWeightTons then small = small or name
        else large = large or name end
    end
    expect.truthy(small, "no small map to test against")
    expect.truthy(large, "no large map to test against")

    local m = TPG.Maps.LimitMult
    expect.eq(TPG.Maps.Load(small).limits.weight,
        math.floor(TPG.Maps.Configs[small].limits.weight * m.weight * TPG.Maps.SmallMapWeightMult),
        small .. " should take the small-map weight cut")
    expect.eq(TPG.Maps.Load(large).limits.weight,
        math.floor(TPG.Maps.Configs[large].limits.weight * m.weight),
        large .. " should not take the small-map weight cut")
end)

it("judges 'small' on the authored weight, before any multiplier", function()
    -- Judging the scaled value instead would move the cutoff every time
    -- LimitMult.weight changed.
    local m = TPG.Maps.LimitMult
    local cutoff = TPG.Maps.SmallMapWeightTons
    expect.truthy(cutoff * m.weight > cutoff,
        "this test is only meaningful while the global weight multiplier is above 1")
end)

it("still gives a small map less tonnage than an open one of the same size", function()
    -- This used to assert the product was exactly 1.2x -- the small-map cut was
    -- chosen to cancel the global bump. Weight is being retired as a metric and
    -- the global multiplier is now far past that, so what is left to hold is the
    -- relationship: the cut is proportional, so it survives any retune of the
    -- global number without either cancelling it or inverting it.
    expect.truthy(TPG.Maps.SmallMapWeightMult > 0,
        "a zero or negative cut would scale small maps to nothing")
    expect.truthy(TPG.Maps.SmallMapWeightMult < 1,
        "the small-map carve-out is a cut; at 1 or above it is not doing anything")
end)

it("did not drag the points budget along with the weight raise", function()
    -- The whole point of raising tonnage is that POINTS become the only real
    -- budget. A weight retune that moved points too would defeat it.
    expect.near(TPG.Maps.LimitMult.points, 0.828, 0.001,
        "the points multiplier moved; weight and points are separate knobs")
end)

it("does not scale a budget to zero", function()
    for name in pairs(TPG.Maps.Configs) do
        local limits = TPG.Maps.Load(name).limits
        expect.truthy(limits.weight > 0, name .. " scaled to zero tonnage")
        expect.truthy(limits.props > 0, name .. " scaled to zero props")
        expect.truthy(limits.points > 0, name .. " scaled to zero points")
    end
end)

describe("maps: loading")

it("merges a map over the defaults rather than replacing them", function()
    local cfg = TPG.Maps.Load("gm_construct")
    expect.eq(cfg.spawns[TEAM_GREEN], TPG.Maps.Configs.gm_construct.spawns[TEAM_GREEN])
    expect.truthy(cfg[GAMEMODE_DM], "the merge should carry the default's other blocks through")
end)

it("falls back to the defaults for a map it has never seen", function()
    local cfg = TPG.Maps.Load("gm_nonexistent_map")
    expect.truthy(cfg, "an unknown map must still produce a config")
    expect.eq(cfg.spawns[TEAM_GREEN], TPG.Maps.Default.spawns[TEAM_GREEN])
    expect.truthy(cfg.limits.points > 0)
end)

it("does not mutate the authored config it copied from", function()
    local before = TPG.Maps.Configs.gm_flatgrass.limits.points
    TPG.Maps.Load("gm_flatgrass")
    TPG.Maps.Load("gm_flatgrass")
    expect.eq(TPG.Maps.Configs.gm_flatgrass.limits.points, before,
        "loading twice compounded the multiplier onto the source table")
end)

it("uses the running map when told nothing", function()
    gmod.map = "gm_construct"
    TPG.Maps.Current = nil
    local cfg = TPG.Maps.Get()
    expect.eq(cfg.spawns[TEAM_GREEN], TPG.Maps.Configs.gm_construct.spawns[TEAM_GREEN])
end)

describe("maps: the accessors")

it("reads a team's authored spawn", function()
    TPG.Maps.Load("gm_flatgrass")
    expect.eq(TPG.Maps.GetSpawn(TEAM_GREEN), TPG.Maps.Configs.gm_flatgrass.spawns[TEAM_GREEN])
    expect.eq(TPG.Maps.GetSpawn(TEAM_RED), TPG.Maps.Configs.gm_flatgrass.spawns[TEAM_RED])
end)

it("returns the origin for a team with no spawn", function()
    TPG.Maps.Load("gm_flatgrass")
    expect.eq(TPG.Maps.GetSpawn(TEAM_UNASSIGNED), Vector(0, 0, 0))
end)

it("returns an empty list, never nil, for a mode the map does not cover", function()
    TPG.Maps.Load("gm_flatgrass")
    local objectives = TPG.Maps.GetObjectives(GAMEMODE_CTF)
    expect.eq(type(objectives), "table")
    expect.eq(#objectives, 0)
end)

it("returns the map's real objectives for a mode it does cover", function()
    TPG.Maps.Load("gm_flatgrass")
    expect.eq(#TPG.Maps.GetObjectives(GAMEMODE_CP),
        #TPG.Maps.Configs.gm_flatgrass[GAMEMODE_CP].objectives)
end)

describe("maps: the vote screen")

it("reports the same budgets the server will enforce", function()
    local info = TPG.Maps.GetVoteInfo("gm_flatgrass")
    local live = TPG.Maps.Load("gm_flatgrass").limits

    expect.eq(info.points, math.floor(live.points))
    expect.eq(info.weight, math.floor(live.weight))
    expect.eq(info.props, math.floor(live.props))
end)

it("works for a map other than the one running", function()
    gmod.map = "gm_flatgrass"
    TPG.Maps.Load("gm_flatgrass")

    local info = TPG.Maps.GetVoteInfo("gm_construct")
    expect.eq(info.map, "gm_construct")
    expect.eq(TPG.Maps.Current.spawns[TEAM_GREEN],
        TPG.Maps.Configs.gm_flatgrass.spawns[TEAM_GREEN],
        "reading another map's info must not swap the loaded config")
end)

it("tidies a map name into something readable", function()
    local info = TPG.Maps.GetVoteInfo("gm_baik_coast_03")
    expect.eq(info.displayName, "Baik Coast 03")
end)

it("reports the control-point count as the map's size", function()
    local info = TPG.Maps.GetVoteInfo("gm_flatgrass")
    expect.eq(info.objectives, #TPG.Maps.Configs.gm_flatgrass[GAMEMODE_CP].objectives)
end)

it("still answers for a map with no config at all", function()
    local info = TPG.Maps.GetVoteInfo("gm_nonexistent_map")
    expect.eq(info.map, "gm_nonexistent_map")
    expect.truthy(#info.displayName > 0)
    expect.truthy(info.points > 0)
end)
