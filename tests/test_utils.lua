local gmod = expect.load.gmod

describe("util: math")

it("clamps to both ends of the range", function()
    expect.eq(TPG.Util.Clamp(5, 0, 10), 5)
    expect.eq(TPG.Util.Clamp(-5, 0, 10), 0)
    expect.eq(TPG.Util.Clamp(15, 0, 10), 10)
    expect.eq(TPG.Util.Clamp(0, 0, 10), 0)
    expect.eq(TPG.Util.Clamp(10, 0, 10), 10)
end)

it("clamps a range that is a single value", function()
    expect.eq(TPG.Util.Clamp(5, 3, 3), 3)
end)

describe("util: distance units")

it("round-trips metres and Source units", function()
    for _, metres in ipairs({ 0, 1, 5, 100, 1234.5 }) do
        expect.near(TPG.Util.UnitsToMeters(TPG.Util.MetersToUnits(metres)), metres, 1e-9)
    end
end)

it("treats a Source unit as roughly an inch", function()
    -- The compass and objective HUD both read in metres because that is what
    -- the vehicles are scaled to; if this divisor drifts, every distance the
    -- player is shown drifts with it.
    expect.near(TPG.Util.MetersToUnits(1), 39.37, 0.01)
    expect.near(TPG.Util.UnitsToMeters(39.37), 1, 0.001)
end)

it("measures the distance between two points in metres", function()
    local a, b = Vector(0, 0, 0), Vector(39.37, 0, 0)
    expect.near(TPG.Util.GetDistanceMeters(a, b), 1, 0.001)
end)

describe("util: radius checks")

it("is inclusive of nothing beyond the radius", function()
    local ply = gmod.player(TEAM_GREEN)
    ply:SetPos(Vector(0, 0, 0))

    expect.truthy(TPG.Util.IsWithinDistance(ply, Vector(99, 0, 0), 100))
    expect.falsy(TPG.Util.IsWithinDistance(ply, Vector(101, 0, 0), 100))
end)

it("excludes a point exactly on the boundary", function()
    -- The comparison is strictly less-than on squared distances; worth pinning
    -- because safezone and capture radii both run through it.
    local ply = gmod.player(TEAM_GREEN)
    ply:SetPos(Vector(0, 0, 0))
    expect.falsy(TPG.Util.IsWithinDistance(ply, Vector(100, 0, 0), 100))
end)

it("measures in three dimensions", function()
    local ply = gmod.player(TEAM_GREEN)
    ply:SetPos(Vector(0, 0, 0))
    expect.falsy(TPG.Util.IsWithinDistance(ply, Vector(0, 0, 200), 100),
        "height must count toward the radius")
end)

describe("util: team membership")

it("is true only for the two playing teams", function()
    expect.truthy(TPG.Util.IsOnTeam(gmod.player(TEAM_GREEN)))
    expect.truthy(TPG.Util.IsOnTeam(gmod.player(TEAM_RED)))
    expect.falsy(TPG.Util.IsOnTeam(gmod.player(TEAM_UNASSIGNED)))
    expect.falsy(TPG.Util.IsOnTeam(gmod.player(9999)))
end)

describe("util: team balance")

it("reports zero when the teams are even", function()
    gmod.player(TEAM_GREEN)
    gmod.player(TEAM_RED)
    expect.eq(TPG.Util.GetTeamDifference(), 0)
    expect.nils(TPG.Util.GetUndermannedTeam())
end)

it("reads positive when green has more", function()
    gmod.player(TEAM_GREEN)
    gmod.player(TEAM_GREEN)
    gmod.player(TEAM_RED)

    expect.eq(TPG.Util.GetTeamDifference(), 1)
    expect.eq(TPG.Util.GetUndermannedTeam(), TEAM_RED)
end)

it("reads negative when red has more", function()
    gmod.player(TEAM_RED)
    gmod.player(TEAM_RED)
    gmod.player(TEAM_GREEN)

    expect.eq(TPG.Util.GetTeamDifference(), -1)
    expect.eq(TPG.Util.GetUndermannedTeam(), TEAM_GREEN)
end)

it("ignores spectators entirely", function()
    gmod.player(TEAM_GREEN)
    gmod.player(TEAM_RED)
    for _ = 1, 5 do gmod.player(TEAM_UNASSIGNED) end

    expect.eq(TPG.Util.GetTeamDifference(), 0)
    expect.nils(TPG.Util.GetUndermannedTeam(),
        "a crowd of spectators should not make a team look undermanned")
end)

it("calls an empty server even", function()
    expect.eq(TPG.Util.GetTeamDifference(), 0)
    expect.nils(TPG.Util.GetUndermannedTeam())
end)

describe("util: per-player storage")

it("namespaces every key so other addons cannot collide", function()
    local ply = gmod.player(TEAM_GREEN)
    TPG.Util.SetPData(ply, "armor", 3)

    expect.truthy(ply._pdata["TPG_armor"], "the TPG_ prefix is missing")
    expect.nils(ply._pdata["armor"])
end)

it("reads back a number as a number, not a string", function()
    -- PData stores strings; callers store an armor id and expect an armor id
    -- back, not "3".
    local ply = gmod.player(TEAM_GREEN)
    TPG.Util.SetPData(ply, "armor", 3)

    local got = TPG.Util.GetPData(ply, "armor")
    expect.eq(got, 3)
    expect.eq(type(got), "number")
end)

it("leaves a non-numeric value as a string", function()
    local ply = gmod.player(TEAM_GREEN)
    TPG.Util.SetPData(ply, "primary", "weapon_ace_m16")
    expect.eq(TPG.Util.GetPData(ply, "primary"), "weapon_ace_m16")
end)

it("returns the default when nothing is stored", function()
    local ply = gmod.player(TEAM_GREEN)
    expect.eq(TPG.Util.GetPData(ply, "never_set", 7), 7)
    expect.eq(TPG.Util.GetPData(ply, "never_set", "fallback"), "fallback")
    expect.nils(TPG.Util.GetPData(ply, "never_set"))
end)

it("round-trips whatever the caller stored", function()
    local ply = gmod.player(TEAM_GREEN)
    for _, value in ipairs({ 0, 4, -1, 1.5, "none", "weapon_ace_glock" }) do
        TPG.Util.SetPData(ply, "k", value)
        expect.eq(TPG.Util.GetPData(ply, "k"), value, "round trip of " .. tostring(value))
    end
end)

describe("util: chat helpers")

it("exists on the server realm", function()
    -- These are all defined inside `if SERVER`, so a client-realm caller would
    -- get a nil-index error rather than a silent no-op.
    expect.eq(type(TPG.Util.ChatMessage), "function")
    expect.eq(type(TPG.Util.ChatBroadcast), "function")
    expect.eq(type(TPG.Util.ChatTeam), "function")
    expect.eq(type(TPG.Util.PlaySound), "function")
end)

it("sends a team message to that team's players only", function()
    local sent = {}
    local saved = TPG.Util.ChatMessage
    TPG.Util.ChatMessage = function(ply) sent[#sent + 1] = ply end

    local g1, g2 = gmod.player(TEAM_GREEN), gmod.player(TEAM_GREEN)
    local r1 = gmod.player(TEAM_RED)
    gmod.player(TEAM_UNASSIGNED)

    TPG.Util.ChatTeam(TEAM_GREEN, "hello")

    expect.eq(#sent, 2, "should reach both green players and nobody else")
    expect.truthy(table.HasValue(sent, g1))
    expect.truthy(table.HasValue(sent, g2))
    expect.falsy(table.HasValue(sent, r1))

    TPG.Util.ChatMessage = saved
end)

it("defaults a team message to that team's own colour", function()
    local seen
    local saved = TPG.Util.ChatMessage
    TPG.Util.ChatMessage = function(_, _, color) seen = color end

    gmod.player(TEAM_RED)
    TPG.Util.ChatTeam(TEAM_RED, "hello")

    expect.eq(seen, TPG.GetTeamData(TEAM_RED).color)

    TPG.Util.ChatMessage = saved
end)
