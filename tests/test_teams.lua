describe("teams: the constants")

it("keeps the two playing teams distinct and non-zero", function()
    expect.eq(TEAM_UNASSIGNED, 0)
    expect.ne(TEAM_GREEN, TEAM_RED)
    expect.ne(TEAM_GREEN, TEAM_UNASSIGNED)
    expect.ne(TEAM_RED, TEAM_UNASSIGNED)
end)

it("stays clear of ULX's usergroup team range", function()
    -- ULX's Manage Teams registers usergroup teams from index 21 upward and
    -- resets what it finds in that band, so TPG deliberately sits far above it.
    expect.truthy(TEAM_GREEN > 1000, "TEAM_GREEN is " .. TEAM_GREEN)
    expect.truthy(TEAM_RED > 1000, "TEAM_RED is " .. TEAM_RED)
end)

describe("teams: the display table")

it("has an entry for every team constant", function()
    for _, id in ipairs({ TEAM_UNASSIGNED, TEAM_GREEN, TEAM_RED }) do
        local data = TPG.Teams[id]
        expect.truthy(data, "no TPG.Teams entry for " .. id)
        expect.eq(type(data.name), "string")
        expect.truthy(IsColor(data.color), "team " .. id .. " colour")
        expect.truthy(isvector(data.vector), "team " .. id .. " vector")
    end
end)

it("takes the team colours from the palette", function()
    -- The point of the palette is that the scoreboard, the score bar and the
    -- point markers are literally the same value, not near-misses.
    expect.eq(TPG.Teams[TEAM_GREEN].color, TPG.Colors.Green)
    expect.eq(TPG.Teams[TEAM_RED].color, TPG.Colors.Red)
end)

it("falls back to the unassigned entry, never nil", function()
    expect.eq(TPG.GetTeamData(999999), TPG.Teams[TEAM_UNASSIGNED])
    expect.eq(TPG.GetTeamData(nil), TPG.Teams[TEAM_UNASSIGNED])
    expect.eq(type(TPG.GetTeamData(nil).name), "string")
end)

describe("teams: the enemy lookup")

it("pairs the two playing teams", function()
    expect.eq(TPG.GetEnemyTeam(TEAM_GREEN), TEAM_RED)
    expect.eq(TPG.GetEnemyTeam(TEAM_RED), TEAM_GREEN)
end)

it("is its own inverse", function()
    expect.eq(TPG.GetEnemyTeam(TPG.GetEnemyTeam(TEAM_GREEN)), TEAM_GREEN)
    expect.eq(TPG.GetEnemyTeam(TPG.GetEnemyTeam(TEAM_RED)), TEAM_RED)
end)

it("gives a non-playing team no enemy", function()
    expect.eq(TPG.GetEnemyTeam(TEAM_UNASSIGNED), TEAM_UNASSIGNED)
    expect.eq(TPG.GetEnemyTeam(12345), TEAM_UNASSIGNED)
end)

describe("teams: registration")

it("registers all three with the engine", function()
    for _, id in ipairs({ TEAM_UNASSIGNED, TEAM_GREEN, TEAM_RED }) do
        expect.truthy(team.Valid(id), "team " .. id .. " was not registered")
        expect.eq(team.GetName(id), TPG.Teams[id].name)
    end
end)

it("refuses to overwrite a team another addon already holds", function()
    expect.load.gmod.reset()

    -- Something else gets there first, and TPG has no record of owning it.
    team.SetUp(TEAM_GREEN, "ULX Moderators", Color(0, 0, 255))
    TPG._ownTeams = nil

    TPG.SetupTeams()

    expect.eq(team.GetName(TEAM_GREEN), "ULX Moderators",
        "TPG stomped a team it did not register")
    expect.eq(team.GetName(TEAM_RED), TPG.Teams[TEAM_RED].name,
        "the teams it does own should still be set up")
end)

it("re-registers its own teams on a second call", function()
    -- Once TPG owns an ID the guard stops applying, so a hot reload can rebuild
    -- the teams instead of tripping the "already in use" branch forever.
    TPG.SetupTeams()
    team.SetUp(TEAM_GREEN, "stale", Color(0, 0, 0))
    TPG.SetupTeams()

    expect.eq(team.GetName(TEAM_GREEN), TPG.Teams[TEAM_GREEN].name)
end)
