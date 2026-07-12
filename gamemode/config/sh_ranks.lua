--[[
    Rank Ladder (shared)

    Persistent skill-rating ranks, CS:GO-style ladder with names that fit a
    server where everyone's tank is held together with duct tape. Rating is
    earned across ALL maps and sessions (systems/sv_stats.lua); everyone starts
    at 1000 and the ladder is centered there.

    Keep this ordered by ascending min.
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

-- Rank entry + its index for a rating value.
function TPG.GetRank(rating)
    rating = rating or 1000
    local best, bestIdx = TPG.Ranks[1], 1
    for i, rank in ipairs(TPG.Ranks) do
        if rating >= rank.min then best, bestIdx = rank, i end
    end
    return best, bestIdx
end

-- Progress (0..1) through the current rank toward the next, for progress bars.
-- Returns progress, nextRank (nil at the top).
function TPG.GetRankProgress(rating)
    local _, idx = TPG.GetRank(rating)
    local cur, nxt = TPG.Ranks[idx], TPG.Ranks[idx + 1]
    if not nxt then return 1, nil end
    return math.Clamp((rating - cur.min) / (nxt.min - cur.min), 0, 1), nxt
end
