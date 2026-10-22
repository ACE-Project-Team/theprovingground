--[[
    The map editor's layout format. A layout is saved to disk and read back on
    every map load, so the parts that matter are that old files still load,
    that applying one replaces exactly what it says, and that an export pastes
    back as a working config.
]]

local function cfg()
    return TPG.Maps.BuildConfig("gm_construct", false)
end

describe("layout: teams")

it("reads every team id the gamemode has used", function()
    expect.eq(TPG.Layout.TeamName(1), "green")
    expect.eq(TPG.Layout.TeamName(2), "red")
    expect.eq(TPG.Layout.TeamName(TEAM_GREEN), "green")
    expect.eq(TPG.Layout.TeamName(TEAM_RED), "red")
    expect.eq(TPG.Layout.TeamName("RED"), "red")
    expect.nils(TPG.Layout.TeamName(3))
    expect.eq(TPG.Layout.TeamId("green"), TEAM_GREEN)
end)

describe("layout: Normalize")

it("migrates numeric teams and drops what it cannot place", function()
    local data = TPG.Layout.Normalize({ points = {
        { type = "spawn", team = 1, pos = { x = 1, y = 2, z = 3 } },
        { type = "spawn", team = 9, pos = { x = 1, y = 2, z = 3 } },
        { type = "cp", pos = { x = 1, y = 2, z = 3 }, name = "" },
        { type = "bogus", pos = { x = 0, y = 0, z = 0 } },
        { type = "koth" },
    } })
    expect.eq(#data.points, 2)
    expect.eq(data.points[1].team, "green")
    expect.nils(data.points[2].team)
    expect.nils(data.points[2].name)
    expect.eq(data.version, 2)
end)

it("makes an empty layout from nothing", function()
    local data = TPG.Layout.Normalize(nil)
    expect.eq(#data.points, 0)
    expect.truthy(data.settings)
end)

describe("layout: Apply")

it("replaces only what the layout has", function()
    local config = cfg()
    local kothBefore = #config[GAMEMODE_KOTH].objectives
    local redBefore = config.spawns[TEAM_RED]

    TPG.Layout.Apply(config, TPG.Layout.Normalize({ points = {
        { type = "spawn", team = "green", pos = { x = 10, y = 20, z = 30 } },
        { type = "cp", pos = { x = 1, y = 1, z = 1 } },
        { type = "cp", pos = { x = 2, y = 2, z = 2 }, name = "Bridge" },
        { type = "ctf", pos = { x = 5, y = 5, z = 5 } },
    } }))

    expect.eq(config.spawns[TEAM_GREEN], Vector(10, 20, 30))
    expect.eq(config.spawns[TEAM_RED], redBefore)
    expect.eq(#config[GAMEMODE_CP].objectives, 2)
    expect.eq(config[GAMEMODE_CP].objectives[1].name, "Point 1")
    expect.eq(config[GAMEMODE_CP].objectives[2].name, "Bridge")
    expect.eq(#config[GAMEMODE_KOTH].objectives, kothBefore)
    expect.eq(config.ctfFlag, Vector(5, 5, 5))
end)

it("puts settings where the round reads them", function()
    local config = cfg()
    TPG.Layout.Apply(config, TPG.Layout.Normalize({ settings = {
        points = 1234, weight = 56, props = 78, safezoneRadius = 900,
        capCP = 2, capKOTH = 0.5, winsToMapVote = 4, displayName = "Big City",
    } }))
    expect.eq(config.limits.points, 1234)
    expect.eq(config.limits.weight, 56)
    expect.eq(config.limits.props, 78)
    expect.eq(config.safezoneRadius, 900)
    expect.eq(config[GAMEMODE_CP].capMultiplier, 2)
    expect.eq(config[GAMEMODE_KOTH].capMultiplier, 0.5)
    expect.eq(config.winsToMapVote, 4)
    expect.eq(config.displayName, "Big City")
end)

describe("layout: Export")

it("pastes back as the same config", function()
    local config = cfg()
    TPG.Layout.Apply(config, TPG.Layout.Normalize({
        settings = { points = 999, displayName = "Test \"map\"" },
        points = {
            { type = "rush", pos = { x = 100, y = 0, z = 0 } },
            { type = "rush", pos = { x = 200, y = 0, z = 0 }, name = "Second" },
            { type = "ctf", pos = { x = 7, y = 8, z = 9 } },
        },
    }))

    local text = TPG.Layout.Export("gm_test", config, "open")
    local chunk = assert(loadstring("return {" .. text .. "}"))
    local back = chunk().gm_test

    expect.eq(back.displayName, "Test \"map\"")
    expect.eq(back.limits.points, 999)
    expect.eq(back.spawns[TEAM_GREEN], Vector(math.Round(config.spawns[TEAM_GREEN].x),
        math.Round(config.spawns[TEAM_GREEN].y), math.Round(config.spawns[TEAM_GREEN].z)))
    expect.eq(back.ctfFlag, Vector(7, 8, 9))
    expect.eq(#back[GAMEMODE_RUSH].objectives, 2)
    expect.eq(back[GAMEMODE_RUSH].objectives[2].name, "Second")
    expect.eq(#back[GAMEMODE_CP].objectives, #config[GAMEMODE_CP].objectives)
end)

describe("layout: Check")

it("finds overlapping safezones and points inside them", function()
    local config = cfg()
    config.safezoneRadius = 500
    config.spawns = { [TEAM_GREEN] = Vector(1, 0, 0), [TEAM_RED] = Vector(600, 0, 0) }
    config[GAMEMODE_CP] = { objectives = { { pos = Vector(10, 0, 0), name = "A" } } }

    local w = table.concat(TPG.Layout.Check(config), "\n")
    expect.truthy(w:find("overlap", 1, true), w)
    expect.truthy(w:find("Control point 1 (A) is inside the Green safezone", 1, true), w)
end)

it("is quiet on a sound layout", function()
    local config = cfg()
    config.safezoneRadius = 100
    config.spawns = { [TEAM_GREEN] = Vector(1, 0, 0), [TEAM_RED] = Vector(5000, 0, 0) }
    config[GAMEMODE_CP] = { objectives = { { pos = Vector(2500, 0, 0), name = "A" } } }
    config[GAMEMODE_KOTH] = { objectives = {} }
    config[GAMEMODE_RUSH] = nil
    config.ctfFlag = nil
    expect.eq(#TPG.Layout.Check(config), 0, table.concat(TPG.Layout.Check(config), "\n"))
end)
