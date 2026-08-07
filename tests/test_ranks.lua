describe("ranks: the ladder's shape")

it("stays sorted ascending by min", function()
    -- Both lookups walk the table front-to-back and keep the last entry the
    -- rating clears, so an out-of-order insert silently hands out the wrong
    -- rank rather than erroring.
    for i = 2, #TPG.Ranks do
        expect.truthy(TPG.Ranks[i].min > TPG.Ranks[i - 1].min,
            string.format("rank %d (%s, min %d) is not above rank %d (%s, min %d)",
                i, TPG.Ranks[i].name, TPG.Ranks[i].min,
                i - 1, TPG.Ranks[i - 1].name, TPG.Ranks[i - 1].min))
    end
end)

it("starts at zero so no rating is unranked", function()
    expect.eq(TPG.Ranks[1].min, 0)
end)

it("is a plain array with no holes", function()
    expect.eq(#TPG.Ranks, table.Count(TPG.Ranks),
        "TPG.Ranks must be a contiguous array; ipairs would stop early otherwise")
end)

it("gives every tier a name and a colour", function()
    local seen = {}
    for i, rank in ipairs(TPG.Ranks) do
        expect.eq(type(rank.name), "string", "rank " .. i .. " name")
        expect.truthy(#rank.name > 0, "rank " .. i .. " has an empty name")
        expect.falsy(seen[rank.name], "duplicate rank name: " .. rank.name)
        seen[rank.name] = true
        expect.truthy(IsColor(rank.color), "rank " .. i .. " colour")
    end
end)

it("centres the ladder on the starting rating", function()
    -- Everyone starts at 1000, and the ladder is built around that: some tiers
    -- below it, most above.
    local below, above = 0, 0
    for _, rank in ipairs(TPG.Ranks) do
        if rank.min < 1000 then below = below + 1 else above = above + 1 end
    end
    expect.truthy(below > 0, "a new player should be able to fall below their starting tier")
    expect.truthy(above > below, "most of the ladder should be above the starting rating")
end)

describe("ranks: GetRank")

it("defaults an absent rating to 1000", function()
    expect.eq(TPG.GetRank(), TPG.GetRank(1000))
    expect.eq(TPG.GetRank(nil), TPG.GetRank(1000))
end)

it("never returns nil, however extreme the rating", function()
    for _, rating in ipairs({ 0, -1, -99999, 1, 999999 }) do
        local rank, idx = TPG.GetRank(rating)
        expect.truthy(rank, "no rank for rating " .. rating)
        expect.truthy(idx >= 1 and idx <= #TPG.Ranks, "index out of range for rating " .. rating)
    end
end)

it("puts a rating exactly on a threshold into the higher tier", function()
    for i, rank in ipairs(TPG.Ranks) do
        local got, idx = TPG.GetRank(rank.min)
        expect.eq(idx, i, "rating " .. rank.min .. " should be " .. rank.name .. ", got " .. got.name)
    end
end)

it("puts a rating one below a threshold into the lower tier", function()
    for i = 2, #TPG.Ranks do
        local _, idx = TPG.GetRank(TPG.Ranks[i].min - 1)
        expect.eq(idx, i - 1, "one point below " .. TPG.Ranks[i].name .. " should still be the tier below")
    end
end)

it("caps at the top tier", function()
    local _, idx = TPG.GetRank(TPG.Ranks[#TPG.Ranks].min + 100000)
    expect.eq(idx, #TPG.Ranks)
end)

describe("ranks: GetRankProgress")

it("reads 0 at the bottom of a tier and approaches 1 at the top", function()
    for i = 1, #TPG.Ranks - 1 do
        local cur, nxt = TPG.Ranks[i], TPG.Ranks[i + 1]

        local atFloor = TPG.GetRankProgress(cur.min)
        expect.near(atFloor, 0, 1e-9, "progress at the floor of " .. cur.name)

        local justBelow = TPG.GetRankProgress(nxt.min - 1)
        expect.truthy(justBelow > 0.5 and justBelow < 1,
            "progress just below " .. nxt.name .. " should be nearly full, got " .. justBelow)
    end
end)

it("stays inside 0..1 everywhere", function()
    for rating = -500, 3000, 25 do
        local p = TPG.GetRankProgress(rating)
        expect.truthy(p >= 0 and p <= 1, "progress out of range at rating " .. rating .. ": " .. p)
    end
end)

it("reports a full bar and no next tier at the top", function()
    local top = TPG.Ranks[#TPG.Ranks]
    local progress, nxt = TPG.GetRankProgress(top.min)
    expect.eq(progress, 1)
    expect.nils(nxt)

    local progress2, nxt2 = TPG.GetRankProgress(top.min + 5000)
    expect.eq(progress2, 1)
    expect.nils(nxt2)
end)

it("names the tier the player is climbing toward", function()
    for i = 1, #TPG.Ranks - 1 do
        local _, nxt = TPG.GetRankProgress(TPG.Ranks[i].min)
        expect.eq(nxt, TPG.Ranks[i + 1], "wrong next tier above " .. TPG.Ranks[i].name)
    end
end)

it("defaults to the starting rating like GetRank does", function()
    local a = TPG.GetRankProgress()
    local b = TPG.GetRankProgress(1000)
    expect.eq(a, b)
end)
