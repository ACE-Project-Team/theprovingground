--[[
    Map voting: RTV, the disabled-by-admin path, the "stay" pseudo-candidate,
    and the reopen-menu escape.

    Same precedent as test_vehiclekill/test_rush: loads ONE server file and
    calls its functions by hand. The net messages, the menu Derma and the
    chat hook are left to in-game testing.
]]

local gmod = expect.load.gmod

-- ── stubs ───────────────────────────────────────────────────────────────────
-- Re-applied per case: other suites can clobber the shared globals.

local broadcasts  = {}
local pms         = {}
local pstates     = {}
local scheduled   = {}  -- { delay, fn } timer.Simple calls
local rcc         = {}  -- RunConsoleCommand calls
local synced      = {}  -- TPG.Net calls
local setups      = 0
local concommands = {}  -- ply -> { cmd, ... }

local function applyStubs()
    TPG.Config = {
        rtvPercentRequired = 0.6,
        rtvMinPlayers      = 1,
        scramblePercent    = 0.6,
        mapVoteTime        = 20,
        mapVoteSlots       = { open = 2, urban = 1, bonus = 0 },
    }
    TPG.State = {
        voting = { active = false, endTime = 0, votes = {}, maps = {} },
        round  = { active = false, wins = { [TEAM_GREEN] = 2, [TEAM_RED] = 1 } },
        GetPlayer = function(ply)
            pstates[ply] = pstates[ply] or { votes = {} }
            return pstates[ply]
        end,
    }
    TPG.Util = TPG.Util or {}
    TPG.Util.ChatBroadcast = function(msg) broadcasts[#broadcasts + 1] = msg end
    TPG.Util.ChatMessage = function(ply, msg) pms[#pms + 1] = { ply = ply, msg = msg } end
    TPG.Maps = {
        LayoutVoteMaps = function() return { open = {}, urban = {} } end,
        GetVoteInfo = function(map)
            return { displayName = map, points = 100, weight = 50, props = 30, objectives = 2 }
        end,
    }
    TPG.Net = {
        SyncMapVote   = function(maps) synced[#synced + 1] = { "maps", maps } end,
        SyncVoteTally = function(counts) synced[#synced + 1] = { "tally", counts } end,
    }
    TPG.Rounds = { Setup = function() setups = setups + 1 end }
    TPG.PlayerTeams = { ScrambleAll = function() end }

    timer.Simple = function(delay, fn) scheduled[#scheduled + 1] = { delay = delay, fn = fn } end
    RunConsoleCommand = function(cmd, arg) rcc[#rcc + 1] = { cmd = cmd, arg = arg } end
end

local function ply(teamId)
    local p = gmod.player(teamId, {
        ConCommand = function(self, cmd)
            concommands[self] = concommands[self] or {}
            concommands[self][#concommands[self] + 1] = cmd
        end,
    })
    return p
end

-- Candidate maps "installed" for the vote: anything in the hardcoded lists
-- that we plant a .bsp for. Enough for open=2, urban=1.
local INSTALL = {
    "gm_emp_palmbay", "gm_emp_midbridge", "gm_greenchoke",
    "gm_emp_manticore", "gm_baik_stalingrad", "gm_bigcity_improved",
}

local function reset()
    broadcasts, pms, pstates, scheduled, rcc, synced, concommands = {}, {}, {}, {}, {}, {}, {}
    setups = 0
    gmod.map = "gm_flatgrass"
    gmod.files = {}
    for _, m in ipairs(INSTALL) do
        gmod.files["maps/" .. m .. ".bsp"] = true
    end
    applyStubs()
    expect.load.dofile(expect.root .. "/gamemode/voting/sv_voting.lua")
end

-- ── cases ───────────────────────────────────────────────────────────────────

describe("voting: map vote gating + stay + reopen")

it("starts a vote with candidates when enabled", function()
    reset()
    TPG.Voting.StartMapVote()

    expect.truthy(TPG.State.voting.active, "vote should be active")
    expect.truthy(#TPG.State.voting.maps >= 2, "installed maps should produce candidates")
    -- no candidate is the map we're on
    for _, m in ipairs(TPG.State.voting.maps) do
        expect.truthy(m.map ~= "gm_flatgrass", "current map must not be a candidate")
    end
    expect.truthy(scheduled[#scheduled], "countdown/end timers should be scheduled")
end)

it("clears stale map picks when a new vote opens", function()
    reset()
    local p = ply(TEAM_GREEN)
    TPG.State.GetPlayer(p).votes.map = 3 -- leftover from a previous vote

    TPG.Voting.StartMapVote()
    expect.nils(TPG.State.GetPlayer(p).votes.map, "old pick should be wiped")

    -- the broadcast tally must not count the stale vote either
    local tally = synced[#synced] and synced[#synced][2] or {}
    local total = 0
    for _, c in pairs(tally) do total = total + c end
    expect.eq(total, 0, "no votes should exist at open")
end)

it("RTV during an open vote reopens the menu instead of tallying", function()
    reset()
    TPG.Voting.StartMapVote()

    local p = ply(TEAM_GREEN)
    TPG.Voting.RockTheVote(p)

    expect.falsy(TPG.State.GetPlayer(p).votes.rtv, "no rtv vote should be counted mid-vote")
    expect.truthy(concommands[p] and concommands[p][1] == "tpg_menu_mapvote",
        "player should get the menu concommand")
end)

it("RTV votes tally and trigger the map vote at threshold", function()
    reset()
    gmod.convars["tpg_mapvote_enabled"] = "1"
    local a, b = ply(TEAM_GREEN), ply(TEAM_RED)

    TPG.Voting.RockTheVote(a)
    expect.falsy(TPG.State.voting.active, "one of two is below the 60% bar")

    TPG.Voting.RockTheVote(b)
    expect.truthy(TPG.State.voting.active, "threshold should open the vote")
    expect.falsy(TPG.State.GetPlayer(a).votes.rtv, "rtv flags reset after pass")
end)

describe("voting: stay + disabled")

it("disabled: StartMapVote never opens a vote and stays put", function()
    reset()
    gmod.convars["tpg_mapvote_enabled"] = "0"

    TPG.Voting.StartMapVote()
    expect.falsy(TPG.State.voting.active, "no vote may open while disabled")
    expect.truthy(#rcc == 0, "no changelevel")
    local last = broadcasts[#broadcasts] or ""
    expect.truthy(string.find(last, "disabled"), "should announce the disabled state")

    -- round was over: wins reset and next round is owed via a timer
    expect.eq(TPG.State.round.wins[TEAM_GREEN], 0)
    expect.eq(TPG.State.round.wins[TEAM_RED], 0)
    local setupTimer
    for _, s in ipairs(scheduled) do
        if s.delay == 10 then setupTimer = s end
    end
    expect.truthy(setupTimer, "next-round timer should be scheduled")
    setupTimer.fn()
    expect.eq(setups, 1)
end)

it("disabled: mid-round just carries on, no round reset", function()
    reset()
    gmod.convars["tpg_mapvote_enabled"] = "0"
    TPG.State.round.active = true

    TPG.Voting.StartMapVote()
    expect.eq(TPG.State.round.wins[TEAM_GREEN], 2, "wins untouched mid-round")
    expect.eq(setups, 0)
    for _, s in ipairs(scheduled) do
        expect.neq(s.delay, 10, "no next-round timer mid-round")
    end
end)

it("disabled: RTV tells the voter and registers nothing", function()
    reset()
    gmod.convars["tpg_mapvote_enabled"] = "0"
    local p = ply(TEAM_GREEN)

    TPG.Voting.RockTheVote(p)
    expect.falsy(TPG.State.GetPlayer(p).votes.rtv)
    expect.truthy(#pms == 1 and string.find(pms[1].msg, "disabled"), "voter should be told")
    expect.falsy(TPG.State.voting.active)
end)

it("CastMapVote 0 votes to stay and tallies at index 0", function()
    reset()
    TPG.Voting.StartMapVote()

    local p = ply(TEAM_GREEN)
    TPG.Voting.CastMapVote(p, 0)
    expect.eq(TPG.State.GetPlayer(p).votes.map, 0)
    expect.truthy(string.find(broadcasts[#broadcasts] or "", "stay"), "should say they voted to stay")

    local tally = synced[#synced] and synced[#synced][2] or {}
    expect.eq(tally[0], 1, "stay vote should count at index 0")
end)

it("TallyVotes: stay wins its own votes and all ties", function()
    reset()
    TPG.Voting.StartMapVote()
    local a, b = ply(TEAM_GREEN), ply(TEAM_RED)

    TPG.Voting.CastMapVote(a, 0)  -- stay
    TPG.Voting.CastMapVote(b, 1)  -- some map -> 1-1 tie

    TPG.Voting.TallyVotes()
    expect.truthy(string.find(broadcasts[#broadcasts] or "", "Staying"), "tie should keep the map")
    expect.truthy(#rcc == 0, "no changelevel on a stay win")
    expect.eq(TPG.State.round.wins[TEAM_GREEN], 0, "round loop owes a reset")
end)

it("TallyVotes: a map that beats stay changelevels to it", function()
    reset()
    TPG.Voting.StartMapVote()
    local a, b, c = ply(TEAM_GREEN), ply(TEAM_RED), ply(TEAM_GREEN)

    TPG.Voting.CastMapVote(a, 0)
    TPG.Voting.CastMapVote(b, 1)
    TPG.Voting.CastMapVote(c, 1)  -- map wins 2-1

    TPG.Voting.TallyVotes()
    local winner = TPG.State.voting.maps[1].map
    expect.truthy(string.find(broadcasts[#broadcasts] or "", "Changing to map: " .. winner))

    -- changelevel rides a 3s timer; fire it
    local changeTimer
    for _, s in ipairs(scheduled) do
        if s.delay == 3 then changeTimer = s end
    end
    expect.truthy(changeTimer, "changelevel should be scheduled")
    changeTimer.fn()
    expect.truthy(#rcc == 1 and rcc[1].cmd == "changelevel" and rcc[1].arg == winner)
end)
