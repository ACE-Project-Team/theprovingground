--[[--
    The persistent skill-rating ladder.

    CS:GO-style ladder with names that fit a server where everyone's tank is
    held together with duct tape. Rating is earned across ALL maps and
    sessions (`systems/sv_stats.lua`); everyone starts at 1000 and the ladder
    is centered there, which is why the lowest tiers sit below that and most
    of the named tiers sit above it.

    `TPG.Ranks` is an array (not keyed by anything), and it MUST stay ordered
    by ascending `min` -- @{TPG.GetRank} and @{TPG.GetRankProgress} both walk
    it front-to-back and rely on that order to find the right tier and its
    neighbour. Each entry has:

        min     the rating threshold this tier starts at
        name    display name, shown on the scoreboard/HUD wherever a rank
                shows
        color   Color, used the same places

    @module tpg.ranks
    @realm shared
]]

TPG.Ranks = {
    { min = 0,    name = "Traffic Cone",               color = Color(255, 140, 0)   },
    { min = 850,  name = "Cannon Fodder",              color = Color(170, 170, 170) },
    { min = 950,  name = "Cardboard Corporal",         color = Color(196, 164, 132) },
    { min = 1050, name = "Rust Bucket",                color = Color(183, 110, 60)  },
    { min = 1150, name = "Scrap Sergeant",             color = Color(140, 150, 160) },
    { min = 1250, name = "Duct Tape Engineer",         color = Color(120, 180, 210) },
    { min = 1400, name = "Certified Road Hazard",      color = Color(240, 200, 60)  },
    { min = 1550, name = "Turret Whisperer",           color = Color(120, 210, 120) },
    { min = 1700, name = "Sabot Sommelier",            color = Color(190, 120, 220) },
    { min = 1900, name = "Steel Baron",                color = Color(90, 160, 255)  },
    { min = 2150, name = "Ballistic Computer With Legs", color = Color(255, 90, 90) },
    { min = 2400, name = "Global Proving Elite",       color = Color(255, 215, 0)   },
}

--- The rank entry for a rating value, and its index in `TPG.Ranks`.
-- Rating defaults to 1000 (the ladder's centre, and every new player's
-- starting rating) when not given. Walks the whole table keeping the LAST
-- entry whose `min` the rating still clears, so it depends on `TPG.Ranks`
-- staying sorted ascending by `min`; never returns nil since Ranks[1].min is 0
-- and every rating is >= 0.
-- @tparam[opt=1000] number rating
-- @treturn table The matching rank entry.
-- @treturn number Its index in `TPG.Ranks`.
-- @realm shared
function TPG.GetRank(rating)
    rating = rating or 1000
    local best, bestIdx = TPG.Ranks[1], 1
    for i, rank in ipairs(TPG.Ranks) do
        if rating >= rank.min then best, bestIdx = rank, i end
    end
    return best, bestIdx
end

--- Progress through the current rank toward the next, for progress bars.
-- @tparam[opt=1000] number rating
-- @treturn number Progress from 0 to 1. Always 1 at the top rank, since there
--  is no next tier to measure progress toward.
-- @treturn ?table The next rank entry, or nil when already at the top of the
--  ladder.
-- @realm shared
function TPG.GetRankProgress(rating)
    -- Defaulted here as well as in GetRank: GetRank applies the default
    -- internally but returns the entry, not the rating, so the arithmetic
    -- below would still see the nil it was handed.
    rating = rating or 1000
    local _, idx = TPG.GetRank(rating)
    local cur, nxt = TPG.Ranks[idx], TPG.Ranks[idx + 1]
    if not nxt then return 1, nil end
    return math.Clamp((rating - cur.min) / (nxt.min - cur.min), 0, 1), nxt
end
