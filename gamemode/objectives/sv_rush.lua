--[[--
    Rush: one point at a time, over several stages.

    A Rush round is a sequence of stages rather than one long fight over a fixed
    set of points. Each stage reveals exactly ONE control point, drawn from the
    map's `GAMEMODE_CP` objective list; the first team to own it for
    `TPG.Config.rushHoldTime` unbroken seconds takes the stage, the losing side
    drops `rushStageTicketLoss` tickets, and the next point is revealed. Kills
    bleed tickets throughout (`rushKillTicketFrac`, applied in
    @{tpg.commendations}), so the fight around the point matters before anyone
    holds it.

    Borrowing the CP list is what lets Rush run on every map already configured,
    with no `[GAMEMODE_RUSH]` block to write anywhere. The trade is that the
    points were placed to be contested simultaneously, not one at a time; a map
    that wants a hand-authored reveal order can get one by giving Rush its own
    block, which @{BuildStages} picks up in preference.

    HOW A ROUND ENDS. Two ways, and the ticket pool is still the real one:
    either a pool hits zero, which @{tpg.rounds.CheckWinCondition} notices the
    way it does in every other mode, or all `rushStages` stages are done and
    @{Finish} ends it on whoever holds more. The two are tuned to agree -- see
    `rushStageTicketLoss` in `config/sh_config.lua`.

    THE HOLD IS UNBROKEN. Losing the point resets the timer to zero rather than
    pausing it. A stage is meant to be a thing you take and keep for a minute,
    and a pause-and-resume version rewards a team that can touch the point six
    times for ten seconds exactly as much as one that held it for sixty -- which
    are not the same achievement and should not score the same.

    State lives on `TPG.Rush` and is rebuilt by @{Begin} every round, so an
    admin restart mid-stage cannot leave a half-finished stage behind.

    @module tpg.rush
    @realm server
]]

TPG.Rush = TPG.Rush or {}

--- Whether this map can host a Rush round at all.
-- Needs at least one control point to reveal. Checked by the game type roll in
-- `config/sh_gametypes.lua`, so a map with no points rolls something else
-- rather than starting a round that can never score.
-- @treturn boolean
-- @realm server
function TPG.Rush.IsSupported()
    return #TPG.Rush.BuildStages() > 0
end

--[[--
    The points this round will reveal, in order.

    An authored `[GAMEMODE_RUSH]` block wins if the map has one -- that is the
    hand-tuned reveal order. Otherwise the control point list is borrowed and
    shuffled, so the same map does not open on the same point every round.

    Capped at `TPG.Config.rushStages`. A map with fewer points than that runs
    fewer stages rather than revealing one twice: a stage whose point the losing
    team already learned is not the same stage.

    @treturn {table,...} Objective entries, `{ pos = Vector, name = string }`.
    @realm server
]]
function TPG.Rush.BuildStages()
    local authored = TPG.Maps.GetObjectives(GAMEMODE_RUSH)
    local pool     = (#authored > 0) and authored or TPG.Maps.GetObjectives(GAMEMODE_CP)

    local list = {}
    for _, obj in ipairs(pool) do list[#list + 1] = obj end

    -- Only shuffled when the order was not authored: an authored block IS the
    -- order, and shuffling it would throw away the only reason to write one.
    if #authored == 0 then
        for i = #list, 2, -1 do
            local j = math.random(i)
            list[i], list[j] = list[j], list[i]
        end
    end

    local cap = math.max(TPG.Config.rushStages or 6, 1)
    while #list > cap do table.remove(list) end

    return list
end

-- Everything the HUD needs, as globals rather than a net message: all five are
-- small, they change at most once a second, and a global is already how the
-- HUD reads overtime and the economy flag.
local function publish()
    SetGlobalInt("TPG_RushStage",   TPG.Rush.stage or 0)
    SetGlobalInt("TPG_RushStages",  TPG.Rush.total or 0)
    SetGlobalInt("TPG_RushGreen",   TPG.Rush.wins and TPG.Rush.wins[TEAM_GREEN] or 0)
    SetGlobalInt("TPG_RushRed",     TPG.Rush.wins and TPG.Rush.wins[TEAM_RED] or 0)
    SetGlobalInt("TPG_RushHoldTeam", TPG.Rush.holdTeam or 0)
    SetGlobalFloat("TPG_RushHoldFrac", TPG.Rush.holdFrac or 0)
end

--- Clear every Rush global. Called when a non-Rush round starts, so the HUD
-- does not keep drawing last round's stage counter over a CP round.
-- @realm server
function TPG.Rush.Clear()
    TPG.Rush.stage, TPG.Rush.total = 0, 0
    TPG.Rush.wins = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }
    TPG.Rush.holdTeam, TPG.Rush.holdFrac = 0, 0
    TPG.Rush.stages, TPG.Rush.holdStart, TPG.Rush.stageStart = nil, nil, nil
    publish()
end

--[[--
    Reveal a stage's point, replacing whatever was live before.

    Goes through `TPG.Objectives.SpawnAll` with a one-entry list, which clears
    the previous point as part of spawning the new one -- so exactly one point
    exists at any moment, which is the whole shape of the mode.

    @tparam number index Which stage, 1-based.
    @realm server
]]
function TPG.Rush.RevealStage(index)
    local obj = TPG.Rush.stages and TPG.Rush.stages[index]
    if not obj then return end

    TPG.Rush.stage      = index
    TPG.Rush.holdStart  = nil
    TPG.Rush.holdTeam   = 0
    TPG.Rush.holdFrac   = 0
    TPG.Rush.stageStart = CurTime()

    TPG.Objectives.SpawnAll({ obj })
    publish()

    TPG.Util.ChatBroadcast(string.format(
        "[TPG] STAGE %d of %d: %s is live. Hold it for %ds to take the stage.",
        index, TPG.Rush.total, obj.name or ("Point " .. index),
        math.Round(TPG.Config.rushHoldTime or 60)), Color(255, 190, 60))
end

--[[--
    Start a Rush round, or clear Rush state if this round is something else.

    Called unconditionally from @{tpg.rounds.Setup} every round -- the same
    pattern as `TPG.CTF.SpawnFlags` -- so the round loop does not have to know
    which modes need setting up.

    Runs AFTER `TPG.Objectives.SpawnAll` has already spawned the round's full
    objective list, and deliberately replaces it: Setup spawns whatever the map
    lists for the game type, and Rush wants one point rather than all of them.

    @realm server
]]
function TPG.Rush.Begin()
    if TPG.State.gameType ~= GAMEMODE_RUSH then
        TPG.Rush.Clear()
        return
    end

    TPG.Rush.Clear()
    TPG.Rush.stages = TPG.Rush.BuildStages()
    TPG.Rush.total  = #TPG.Rush.stages

    if TPG.Rush.total == 0 then
        -- IsSupported should have kept the roll off this map. If it did not,
        -- say so rather than running a round with nothing to capture: a silent
        -- version of this is a round that can only end on the kill bleed.
        ErrorNoHalt("[TPG] Rush rolled on a map with no control points to " ..
            "reveal; the round has no objectives. Check TPG.Maps.Configs for " ..
            game.GetMap() .. ".\n")
        return
    end

    publish()
    TPG.Rush.RevealStage(1)
end

--[[--
    Award a stage and move on, or finish the round if that was the last one.

    @tparam ?number winner TEAM_GREEN or TEAM_RED, or nil when the stage timed
     out with nobody holding it -- which costs neither side anything.
    @realm server
]]
function TPG.Rush.CompleteStage(winner)
    if winner then
        local loser = (winner == TEAM_GREEN) and TEAM_RED or TEAM_GREEN
        TPG.Rush.wins[winner] = (TPG.Rush.wins[winner] or 0) + 1

        TPG.State.AddScore(loser, -(TPG.Config.rushStageTicketLoss or 50))

        local teamData = TPG.Teams[winner]
        TPG.Util.ChatBroadcast(string.format("[TPG] %s takes stage %d. %d - %d.",
            teamData and teamData.name or "A team", TPG.Rush.stage,
            TPG.Rush.wins[TEAM_GREEN], TPG.Rush.wins[TEAM_RED]),
            teamData and teamData.color or Color(255, 255, 255))
    else
        TPG.Util.ChatBroadcast(string.format(
            "[TPG] Nobody could hold stage %d. Moving on.", TPG.Rush.stage),
            Color(255, 190, 60))
    end

    publish()

    --[[
        A stage win can put a pool on zero, and the round is over the moment it
        does -- so ask before revealing the next point. Without this the round
        would show stage N+1 for the fraction of a second before the score
        think noticed, which reads as a stage that started and was taken away.
    ]]
    TPG.Rounds.CheckWinCondition()
    if not TPG.State.round.active then return end

    if TPG.Rush.stage >= TPG.Rush.total then
        TPG.Rush.Finish()
        return
    end

    TPG.Rush.RevealStage(TPG.Rush.stage + 1)
end

--[[--
    End a Rush round that ran out of stages rather than tickets.

    Whoever holds more tickets wins, which is the same rule every other mode
    ends on -- stages are how tickets move in Rush, not a separate scoreboard.
    A dead-level tie goes to whoever took more stages, and only a tie on both
    is a coin flip.

    @realm server
]]
function TPG.Rush.Finish()
    local green = TPG.State.scores[TEAM_GREEN]
    local red   = TPG.State.scores[TEAM_RED]

    local winner
    if green ~= red then
        winner = (green > red) and TEAM_GREEN or TEAM_RED
    else
        local gw, rw = TPG.Rush.wins[TEAM_GREEN] or 0, TPG.Rush.wins[TEAM_RED] or 0
        winner = (gw ~= rw) and ((gw > rw) and TEAM_GREEN or TEAM_RED)
            or (math.random() < 0.5 and TEAM_GREEN or TEAM_RED)
    end

    TPG.Util.ChatBroadcast(string.format(
        "[TPG] All %d stages done. Stages %d - %d, tickets %d - %d.",
        TPG.Rush.total, TPG.Rush.wins[TEAM_GREEN] or 0, TPG.Rush.wins[TEAM_RED] or 0,
        math.Round(green), math.Round(red)), Color(255, 190, 60))

    TPG.Rounds.EndRound(winner)
end

--[[--
    Advance the live stage by one scoring step.

    Called from the same fixed-step `Think` that drives @{tpg.objectives.ProcessScoring},
    so the hold clock does not depend on tickrate, and does nothing at all
    unless a Rush round is live.

    Reads the point's `CapOwnership` (-1 red, 0 neutral, 1 green) rather than
    counting who is standing on it: ownership is what the capture logic already
    resolved, so the hold starts when the point has actually FLIPPED, not when
    someone walked onto it.

    @realm server
]]
function TPG.Rush.Think()
    if TPG.State.gameType ~= GAMEMODE_RUSH then return end
    if not TPG.State.round.active then return end
    if not TPG.Rush.stages or TPG.Rush.total == 0 then return end

    local point
    for _, obj in pairs(TPG.State.objectives or {}) do
        if IsValid(obj) then point = obj break end
    end
    if not point then return end

    local owner = TPG.ControlPoint.StateToTeam(point.CapOwnership or 0)
    local hold  = math.max(TPG.Config.rushHoldTime or 60, 1)

    if owner == TEAM_GREEN or owner == TEAM_RED then
        -- A flip resets rather than transfers: the incoming team starts from
        -- zero, and so does the outgoing one if they take it back.
        if TPG.Rush.holdTeam ~= owner then
            TPG.Rush.holdTeam  = owner
            TPG.Rush.holdStart = CurTime()
        end

        local held = CurTime() - (TPG.Rush.holdStart or CurTime())
        TPG.Rush.holdFrac = math.Clamp(held / hold, 0, 1)
        publish()

        if held >= hold then
            TPG.Rush.CompleteStage(owner)
        end
        return
    end

    -- Neutral, contested, or nobody on it. Losing the point loses the hold
    -- outright; see the note at the top of the file about why this does not
    -- pause.
    if TPG.Rush.holdTeam ~= 0 then
        TPG.Rush.holdTeam  = 0
        TPG.Rush.holdStart = nil
        TPG.Rush.holdFrac  = 0
        publish()
    end

    -- Nobody can take it: abandon the stage rather than let the round sit here.
    local limit = TPG.Config.rushStageTimeLimit or 300
    if limit > 0 and TPG.Rush.stageStart and (CurTime() - TPG.Rush.stageStart) >= limit then
        TPG.Rush.CompleteStage(nil)
    end
end
