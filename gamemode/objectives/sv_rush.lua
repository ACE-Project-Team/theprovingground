--[[--
    Rush: one point at a time, over several stages.

    A Rush round is a sequence of stages rather than one long fight over a fixed
    set of points. Each stage reveals exactly ONE control point, drawn from the
    map's `GAMEMODE_CP` objective list; the first team to own it for
    `TPG.Config.rushHoldTime` unbroken seconds takes the stage and the losing
    side drops @{StageTicketLoss} tickets. Kills bleed tickets throughout
    (`rushKillTicketFrac`, applied in @{tpg.commendations}), so the fight around
    the point matters before anyone holds it.

    THE BREAK BETWEEN STAGES. A stage ending does not reveal the next point --
    it starts a `rushStageBreak` gap in which no point exists anywhere on the
    map. The kill bleed runs through it, so it is fighting time rather than
    waiting time, and because nothing is placed until it ends, neither team can
    spend it walking to a point they already know about. That concealment is the
    entire reason the gap exists; revealing the point at the start of the break
    and merely delaying its capture would be a slower version of no break.

    WHY THE STAGE COUNT IS COMPUTED. `rushStages` is a ceiling, not the number
    played. Six stages with a five-minute break between them is over an hour of
    round, which is not a round anybody sees the end of, so @{MaxStages} works
    out how many fit inside `rushRoundBudget` and @{BuildStages} takes the
    smaller of that and the ceiling. Raising the break therefore SHORTENS the
    round rather than extending it, which is the one behaviour that keeps the
    two knobs from fighting each other.

    Borrowing the CP list is what lets Rush run on every map already configured,
    with no `[GAMEMODE_RUSH]` block to write anywhere. The trade is that the
    points were placed to be contested simultaneously, not one at a time; a map
    that wants a hand-authored reveal order can get one by giving Rush its own
    block, which @{BuildStages} picks up in preference.

    HOW A ROUND ENDS. Two ways, and the ticket pool is still the real one:
    either a pool hits zero, which @{tpg.rounds.CheckWinCondition} notices the
    way it does in every other mode, or every stage is done and @{Finish} ends
    it on whoever holds more. The two agree by construction -- see
    @{StageTicketLoss}.

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
    How many stages fit inside the round's time budget.

    A stage costs, worst case, `rushStageTimeLimit` of nobody managing to take
    the point plus `rushHoldTime` of somebody finally doing it -- the abandon
    limit is only checked while the point is neutral (see @{Think}), so a team
    that flips it on the last second still gets its full hold. Between stages
    sits a `rushStageBreak`, and there are one fewer breaks than stages because
    the last stage ends the round rather than leading anywhere.

    So the budget has to cover `n * stageCost + (n - 1) * break`, and the
    largest n that fits is the floor of `(budget + break) / (stageCost + break)`.
    At the shipped numbers -- 300s limit, 60s hold, 300s break, 1800s budget --
    that is 3 stages and a worst case of 28 minutes.

    Never returns less than 1. A budget too small for even one stage is a
    misconfiguration, and a Rush round with zero stages is not a shorter round,
    it is a round that cannot be played at all.

    @treturn number Stage count, at least 1.
    @realm server
]]
function TPG.Rush.MaxStages()
    local limit  = math.max(TPG.Config.rushStageTimeLimit or 300, 0)
    local hold   = math.max(TPG.Config.rushHoldTime or 60, 1)
    local brk    = math.max(TPG.Config.rushStageBreak or 0, 0)
    local budget = math.max(TPG.Config.rushRoundBudget or 1800, 0)

    return math.max(math.floor((budget + brk) / (limit + hold + brk)), 1)
end

--[[--
    Tickets the losing side drops per stage lost.

    Derived rather than configured: a clean sweep has to land the loser on
    precisely zero, or the stage count and the ticket pool disagree about when
    the round is over and one of them quietly decides first. Dividing the
    starting pool by the stages actually being played keeps that true at any
    count, which a constant cannot once @{MaxStages} is choosing the count.

    `TPG.Config.rushStageTicketLoss` above zero overrides this, for a server
    that would rather tune the number and own the invariant itself.

    @treturn number Tickets, always positive.
    @realm server
]]
function TPG.Rush.StageTicketLoss()
    local override = TPG.Config.rushStageTicketLoss or 0
    if override > 0 then return override end

    local stages = math.max(TPG.Rush.total or 0, 1)
    return (TPG.Config.startingTickets or 300) / stages
end

--[[--
    The points this round will reveal, in order.

    An authored `[GAMEMODE_RUSH]` block wins if the map has one -- that is the
    hand-tuned reveal order. Otherwise the control point list is borrowed and
    shuffled, so the same map does not open on the same point every round.

    Capped at whichever is smaller, `TPG.Config.rushStages` or what
    @{MaxStages} says the time budget affords -- the ceiling and the clock, and
    the round obeys both. A map with fewer points than that runs fewer stages
    still, rather than revealing one twice: a stage whose point the losing team
    already learned is not the same stage.

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

    local cap = math.min(math.max(TPG.Config.rushStages or 6, 1), TPG.Rush.MaxStages())
    while #list > cap do table.remove(list) end

    return list
end

-- Everything the HUD needs, as globals rather than a net message: all of them
-- are small, they change at most once a second, and a global is already how the
-- HUD reads overtime and the economy flag.
--
-- TPG_RushBreak is seconds LEFT rather than the CurTime it ends at, so the HUD
-- does not have to reason about clock skew to draw a countdown -- at the cost of
-- republishing it every scoring step, which is a cheap thing to spend.
local function publish()
    SetGlobalInt("TPG_RushStage",   TPG.Rush.stage or 0)
    SetGlobalInt("TPG_RushStages",  TPG.Rush.total or 0)
    SetGlobalInt("TPG_RushGreen",   TPG.Rush.wins and TPG.Rush.wins[TEAM_GREEN] or 0)
    SetGlobalInt("TPG_RushRed",     TPG.Rush.wins and TPG.Rush.wins[TEAM_RED] or 0)
    SetGlobalInt("TPG_RushHoldTeam", TPG.Rush.holdTeam or 0)
    SetGlobalFloat("TPG_RushHoldFrac", TPG.Rush.holdFrac or 0)

    local left = (TPG.Rush.breakUntil or 0) - CurTime()
    SetGlobalFloat("TPG_RushBreak", left > 0 and left or 0)
end

--- Clear every Rush global. Called when a non-Rush round starts, so the HUD
-- does not keep drawing last round's stage counter over a CP round.
-- @realm server
function TPG.Rush.Clear()
    TPG.Rush.stage, TPG.Rush.total = 0, 0
    TPG.Rush.wins = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }
    TPG.Rush.holdTeam, TPG.Rush.holdFrac = 0, 0
    TPG.Rush.stages, TPG.Rush.holdStart, TPG.Rush.stageStart = nil, nil, nil
    TPG.Rush.breakUntil = nil
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
    TPG.Rush.breakUntil = nil

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

        TPG.State.AddScore(loser, -TPG.Rush.StageTicketLoss())

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

    TPG.Rush.BeginBreak()
end

--[[--
    Open the skirmish gap before the next stage.

    Takes the point off the map first, through `SpawnAll` with an empty list --
    the same call that would spawn one, so there is a single path by which
    objectives come and go. That removal IS the break: with nothing placed,
    there is nowhere to pre-position, and the next point is news when it lands
    rather than a destination people have been driving to for five minutes.

    A break of zero or less is not an error, it is the old behaviour, and it
    reveals the next stage immediately rather than leaving the map empty for a
    tick.

    @realm server
]]
function TPG.Rush.BeginBreak()
    local brk = TPG.Config.rushStageBreak or 0

    if brk <= 0 then
        TPG.Rush.RevealStage(TPG.Rush.stage + 1)
        return
    end

    TPG.Objectives.SpawnAll({})

    TPG.Rush.breakUntil = CurTime() + brk
    TPG.Rush.holdTeam   = 0
    TPG.Rush.holdFrac   = 0
    TPG.Rush.holdStart  = nil
    publish()

    TPG.Util.ChatBroadcast(string.format(
        "[TPG] Next point in %d seconds. Location unknown until then - kills " ..
        "still bleed tickets.", math.Round(brk)), Color(255, 190, 60))
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

    --[[
        Mid-break. Republish so the countdown moves, and reveal the next stage
        the step it runs out.

        This comes before the point lookup deliberately: during a break there IS
        no point, and the lookup below would take the `return` for "the objective
        got removed somehow" and never advance the break at all.
    ]]
    if TPG.Rush.breakUntil then
        if CurTime() < TPG.Rush.breakUntil then
            publish()
            return
        end

        TPG.Rush.RevealStage(TPG.Rush.stage + 1)
        return
    end

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
