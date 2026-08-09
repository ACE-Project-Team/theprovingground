--[[--
    Round management: the loop the whole gamemode runs on.

    A round is set up by @{Setup}, ends when @{CheckWinCondition} sees a ticket
    pool hit zero, and @{EndRound} either starts the next one or hands off to
    the map vote. At map start @{BeginInitialWait} sits in front of the first
    @{Setup} so late loaders aren't left behind.

    Scoring is driven from a `Think` hook at the bottom of this file, on a fixed
    real-time step rather than per tick: ticket drain used to run at half speed
    on a 33-tick server and full speed on a 66-tick one. Catch-up is capped at
    eight steps per frame so a lag spike can't drain a whole pool at once.

    Almost every call out of this file is guarded (`if TPG.X and TPG.X.Y then`).
    That is deliberate -- the round loop must still run when an optional system
    isn't loaded -- so a system that silently fails to load shows up as a round
    that runs with a feature missing, not as an error.

    @module tpg.rounds
    @realm server
]]

-- Initialize namespace FIRST
TPG.Rounds = TPG.Rounds or {}

-- ── Map cleanup ────────────────────────────────────────────────────────────

-- Entities a sweep must never touch: the engine's own bookkeeping and the
-- things a player is made of. `game.CleanUpMap` knows to leave these alone;
-- the sweep below has to be told.
local CLEANUP_KEEP = {
    ["player"]              = true,
    ["worldspawn"]          = true,
    ["predicted_viewmodel"] = true,
    ["gmod_hands"]          = true,
    ["player_manager"]      = true,
    ["gmod_gamerules"]      = true,
    ["soundent"]            = true,
    ["network"]             = true,
    ["bodyque"]             = true,
}

--- Everything a spectator owns, plus the constraints holding it together.
local function SpectatorBuilds()
    local owned, any = {}, false

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            local owner = TPG.Util.GetOwner(ent)
            if owner and not TPG.Util.IsOnTeam(owner) then
                owned[ent] = true
                any = true
            end
        end
    end

    if not any then return nil end

    -- Welds and other constraint entities carry no CPPI owner of their own, so
    -- they have to be found through what they hold: keeping the props but not
    -- the welds would hand the spectator a pile of loose parts, which is not a
    -- build surviving the round.
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not owned[ent] then
            for i = 1, 4 do
                local held = ent["Ent" .. i]
                if IsValid(held) and owned[held] then
                    owned[ent] = true
                    break
                end
            end
        end
    end

    return owned
end

--[[--
    Clear the map between rounds, leaving spectators' builds standing.

    `game.CleanUpMap` has no per-entity opt-out -- its only filter is by class,
    and a spectator's props are the same `prop_physics` as everyone else's --
    so exempting an owner means not calling it. That is a real cost: it also
    restores map entities to their starting state, and a hand-rolled sweep does
    not. So it is still the path taken whenever no spectator owns anything,
    which is nearly every round; the sweep is the exception, not the rule.

    The sweep fires `PreCleanupMap`/`PostCleanupMap` itself, because addons
    (ACE and CFW among them) drop cached state on those and would otherwise be
    left holding references to entities that have gone.

    @realm server
]]
function TPG.Rounds.CleanupMap()
    local keep = SpectatorBuilds()

    if not keep then
        game.CleanUpMap(true)
        return
    end

    hook.Run("PreCleanupMap")

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not keep[ent]
            and not CLEANUP_KEEP[ent:GetClass()]
            and not ent:CreatedByMap() then

            -- A held weapon belongs to the player carrying it, not to the
            -- round; removing it here disarms everyone on respawn.
            local owner = ent:GetOwner()
            if not (ent:IsWeapon() and IsValid(owner) and owner:IsPlayer()) then
                ent:Remove()
            end
        end
    end

    hook.Run("PostCleanupMap")
end

--[[--
    Start a round: pick the mode, reset the map and state, spawn objectives,
    and open the prep window.

    In order, this ends the wait-for-players window, clears overtime, loads the
    map config, maybe scrambles the teams, rolls the game type and the economy,
    swaps the two sides' spawns, applies the map's prop and point limits, cleans
    the map, resets round state, spawns objectives, safezones and (in CTF) the
    flags, respawns everyone on a team, syncs to clients, and calls
    `TPG.Prep.Begin`.

    Two things only happen from the second round on, both gated on
    `TPG.State.round.startTime > 0`: the spawn swap, so the first round of a map
    uses the config as written; and the auto-scramble, which also needs at least
    four players on teams.

    Respawning kills only players who are on a playing team. Spectators are
    skipped on purpose: they have no spawn to be moved to, so killing them was a
    death for nothing, and at map start (nobody has picked a side yet) that is a
    death for *everyone* on the server as their first impression of the
    gamemode.

    Safe to call at any time -- an admin restart or a points reload comes
    through here too, which is why it force-clears the wait window rather than
    assuming it is already closed.

    @tparam[opt=false] boolean skipCleanup Skip the map cleanup entirely (see
     @{TPG.Rounds.CleanupMap}). Used when the caller has already cleaned, or is
     reloading config mid-round and wants players' builds left standing.
    @realm server
]]
function TPG.Rounds.Setup(skipCleanup)
    -- If a round is being set up by any path (admin restart, points reload),
    -- the wait-for-players window is over -- never leave building blocked.
    TPG.State.waitingForPlayers = false
    timer.Remove("TPG_WaitForPlayers")

    -- Keep ULX UTeam from yanking grouped players (admins) off their TPG team.
    if TPG.DisableExternalTeamForcing then TPG.DisableExternalTeamForcing() end

    -- Overtime is per-round state; clear it before anything can read it.
    SetGlobalBool("TPG_ObjOvertime", false)
    SetGlobalFloat("TPG_ObjOvertimeStart", 0)

    -- Load map config
    local mapConfig = TPG.Maps.Load()

    -- Occasional unprompted scramble. Teams settle into the same two line-ups
    -- over an evening even without anyone stacking on purpose -- people rejoin
    -- to the side they were on, friends group up -- and nobody calls a vote
    -- because no single round felt unfair. A small per-round chance keeps the
    -- match-ups moving without making rosters feel arbitrary. Skipped while
    -- waiting for players (nobody's really on a team yet).
    local scrambleChance = TPG.Config.autoScrambleChance or 0
    if scrambleChance > 0 and TPG.State.round.startTime > 0
        and team.NumPlayers(TEAM_GREEN) + team.NumPlayers(TEAM_RED) >= 4
        and math.random() < scrambleChance then
        TPG.Util.ChatBroadcast("[TPG] Rolling a fresh match-up for this round.", Color(255, 255, 0))
        TPG.PlayerTeams.ScrambleAll()
    end

    -- Select gametype
    TPG.State.gameType = TPG.SelectRandomGameType()
    local gameType = TPG.GetGameType(TPG.State.gameType)

    -- Per-player economy is a secondary mode: roll its activation for this round
    -- (before ResetRound, which resets wallets when active).
    local economyOn = TPG.Economy and TPG.Economy.RollForRound and TPG.Economy.RollForRound() or false

    -- Set spawns (swap each round)
    if TPG.State.round.startTime > 0 then
        -- Swap spawns
        local temp = mapConfig.spawns[TEAM_GREEN]
        mapConfig.spawns[TEAM_GREEN] = mapConfig.spawns[TEAM_RED]
        mapConfig.spawns[TEAM_RED] = temp
    end
    
    TPG.State.spawns[TEAM_GREEN] = mapConfig.spawns[TEAM_GREEN]
    TPG.State.spawns[TEAM_RED] = mapConfig.spawns[TEAM_RED]
    
    -- Set limits
    TPG.State.maxLimits.props = mapConfig.limits.props or TPG.Config.fallbackPropLimit
    TPG.State.maxLimits.weight = (mapConfig.limits.weight or TPG.Config.fallbackWeightLimit) * 1000
    TPG.State.maxLimits.points = mapConfig.limits.points or TPG.Config.teamPointLimit
    
    -- Clean map. Spectators' builds are exempt (see TPG.Rounds.CleanupMap):
    -- their whole reason to be here is testing a vehicle between matches, and
    -- losing it every round switch made that impossible.
    if not skipCleanup then
        TPG.Rounds.CleanupMap()
    end
    
    -- Reset state
    TPG.State.ResetRound()
    
    -- Spawn objectives
    local objectives = TPG.Maps.GetObjectives(TPG.State.gameType)
    if TPG.Objectives and TPG.Objectives.SpawnAll then
        TPG.Objectives.SpawnAll(objectives)
    end
    
    -- Spawn safezone markers
    if TPG.Objectives and TPG.Objectives.SpawnSafezones then
        TPG.Objectives.SpawnSafezones()
    end

    -- Spawn CTF flags (no-ops unless this round is Capture the Flag)
    if TPG.CTF and TPG.CTF.SpawnFlags then
        TPG.CTF.SpawnFlags()
    end

    -- Start the Rush stage run. Called unconditionally: on a non-Rush round it
    -- clears its own state rather than leaving last round's stage list behind.
    -- It runs AFTER SpawnAll because it replaces the points SpawnAll just put
    -- down with a single revealed one.
    if TPG.Rush and TPG.Rush.Begin then
        TPG.Rush.Begin()
    end
    
    -- Respawn everyone who's actually playing, so they start the round in their
    -- (possibly just-swapped) spawn. Spectators are skipped: they have no spawn
    -- to be moved to, so killing them was a death for nothing -- and at map
    -- start, when nobody has picked a side yet, that's a death for *everyone*
    -- on the server as their first impression of the gamemode.
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and TPG.Util.IsOnTeam(ply) then
            ply:Kill()
        end
    end
    
    -- Sync to clients
    if TPG.Net and TPG.Net.SyncState then
        TPG.Net.SyncState()
    end
    
    TPG.Util.ChatBroadcast("[TPG] Round started: " .. gameType.name, Color(0, 255, 255))

    -- Open the preparation window: confine both teams to spawn to build/stage
    -- once enough players are present (core/sv_prep.lua).
    if TPG.Prep and TPG.Prep.Begin then
        TPG.Prep.Begin()
    end

    if economyOn then
        TPG.Util.ChatBroadcast(
            "[TPG] PER-PLAYER ECONOMY is ON this round: you each spend a PERSONAL point budget, and destroyed vehicles are NOT refunded.",
            Color(120, 230, 120))
    end
end

--- End the round if either team's ticket pool has run out.
-- Called from the scoring `Think` after each batch of steps, and does nothing
-- unless a round is active. Both pools can cross zero in the same tick under
-- the deathmatch overtime bleed, so that case is resolved by whoever has the
-- higher remaining count, and an exact tie by coin flip.
-- @realm server
function TPG.Rounds.CheckWinCondition()
    if not TPG.State.round.active then return end

    local green = TPG.State.scores[TEAM_GREEN]
    local red   = TPG.State.scores[TEAM_RED]
    local winner = nil

    if green <= 0 and red <= 0 then
        -- Both at zero in the same tick (possible under the DM overtime bleed):
        -- higher remaining fraction won the race; a dead tie is a coin flip.
        winner = green > red and TEAM_GREEN
            or red > green and TEAM_RED
            or (math.random() < 0.5 and TEAM_GREEN or TEAM_RED)
    elseif green <= 0 then
        winner = TEAM_RED
    elseif red <= 0 then
        winner = TEAM_GREEN
    end

    if winner then
        TPG.Rounds.EndRound(winner)
    end
end

--[[--
    Close out a round and decide what happens next.

    Marks the round inactive, credits the win, announces it, plays a win or loss
    cue to each player, clears duplicator cooldowns, awards commendations and
    applies the round result to everyone's lifetime rating via
    @{tpg.stats.OnRoundEnd}.

    Then one of two things: once the two teams' wins add up to
    `TPG.Config.winsToMapVote` it hands off to the map vote, otherwise it
    queues the next @{Setup} ten seconds later.

    @tparam number winningTeam TEAM_GREEN or TEAM_RED. There is no draw path --
     @{CheckWinCondition} resolves a simultaneous wipe before calling here.
    @realm server
]]
function TPG.Rounds.EndRound(winningTeam)
    TPG.State.round.active = false
    TPG.State.round.wins[winningTeam] = TPG.State.round.wins[winningTeam] + 1
    
    local teamData = TPG.GetTeamData(winningTeam)
    
    TPG.Util.ChatBroadcast(teamData.name .. " has won the round!", teamData.color)
    
    -- Play sounds
    for _, ply in ipairs(player.GetAll()) do
        if ply:Team() == winningTeam then
            TPG.Util.PlaySound(ply, "friends/friend_online.wav")
        else
            TPG.Util.PlaySound(ply, "friends/friend_offline.wav")
        end
        
        -- Clear dupe cooldowns
        local pState = TPG.State.GetPlayer(ply)
        pState.dupeCooldown = 0
    end
    
    -- Award commendations
    if TPG.Commendations and TPG.Commendations.Award then
        TPG.Commendations.Award()
    end

    -- Persistent stats: wins/losses + rating for everyone on a team.
    if TPG.Stats and TPG.Stats.OnRoundEnd then
        TPG.Stats.OnRoundEnd(winningTeam)
    end
    
    -- Check for map vote
    local totalWins = TPG.State.round.wins[TEAM_GREEN] + TPG.State.round.wins[TEAM_RED]
    
    if totalWins >= TPG.Config.winsToMapVote then
        if TPG.Voting and TPG.Voting.StartMapVote then
            TPG.Voting.StartMapVote()
        end
    else
        -- Start new round after delay
        timer.Simple(10, function()
            TPG.Rounds.Setup()
        end)
    end
end

--[[
    Wait-for-players window (map start only).

    Fast loaders used to join, take a team, and start burning the team budget
    (or earning economy income) while slow loaders were still on the loading
    screen. The first round now waits: a small base delay always, extended
    whenever someone is mid-connect, hard-capped so one stuck client can't
    hold the server hostage. Building is blocked until the round starts
    (sv_duplication / PlayerSpawnProp check TPG.State.waitingForPlayers).
]]

local pendingJoins = {}   -- [steamid] = time the connect started

gameevent.Listen("player_connect")
hook.Add("player_connect", "TPG_WaitTrackConnect", function(d)
    if tonumber(d.bot) == 1 then return end
    pendingJoins[d.networkid] = CurTime()
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "TPG_WaitTrackDisconnect", function(d)
    pendingJoins[d.networkid] = nil
end)

hook.Add("PlayerInitialSpawn", "TPG_WaitTrackSpawned", function(ply)
    pendingJoins[ply:SteamID()] = nil
end)

local function AnyoneConnecting()
    local now = CurTime()
    for sid, started in pairs(pendingJoins) do
        if now - started > 180 then
            pendingJoins[sid] = nil   -- stale entry (client gave up silently)
        else
            return true
        end
    end
    return false
end

--[[--
    Hold the first round of a map until players have finished loading in.

    Fast loaders used to join, take a team, and start burning the team budget
    (or earning economy income) while slow loaders were still on the loading
    screen. This waits `TPG.Config.waitBaseTime` as a floor, pushes the start
    `waitJoinExtend` further out whenever someone is mid-connect, and gives up
    at `waitMaxTotal` so one stuck client cannot hold the server hostage. A
    connection that goes quiet is forgotten after three minutes.

    While it runs, `TPG.State.waitingForPlayers` is true and building is blocked
    (`sv_duplication` and the `PlayerSpawnProp` check read that flag). @{Setup}
    force-clears it, so no path can leave building blocked.

    Called once from `GM:Initialize`. It ends by calling @{Setup} itself.

    @realm server
]]
function TPG.Rounds.BeginInitialWait()
    local beganAt = CurTime()
    local startAt = beganAt + (TPG.Config.waitBaseTime or 5)
    local deadline = beganAt + (TPG.Config.waitMaxTotal or 90)

    TPG.State.waitingForPlayers = true
    TPG.Util.ChatBroadcast("[TPG] Waiting for players to load in...", Color(0, 255, 255))

    timer.Create("TPG_WaitForPlayers", 1, 0, function()
        local now = CurTime()

        -- Someone's still connecting: keep the start at least waitJoinExtend
        -- away (but never past the hard deadline).
        if AnyoneConnecting() then
            startAt = math.min(math.max(startAt, now + (TPG.Config.waitJoinExtend or 15)), deadline)
        end

        if now < startAt then return end

        timer.Remove("TPG_WaitForPlayers")
        TPG.State.waitingForPlayers = false
        TPG.Rounds.Setup()
    end)
end

-- Game think for round logic. Scoring advances on a fixed real-time step so
-- ticket drain runs at the same rate regardless of tickrate (a 33-tick server
-- used to drain half as fast as 66-tick). Catch-up is clamped against lag.
local scoreAccum     = 0
local lastScoreThink = CurTime()

hook.Add("Think", "TPG_RoundThink", function()
    if not TPG.State.round.active then
        lastScoreThink = CurTime()
        scoreAccum     = 0
        return
    end

    local step = TPG.Config.scoreStep or 0.075
    scoreAccum = scoreAccum + (CurTime() - lastScoreThink)
    lastScoreThink = CurTime()

    local ran, steps = false, 0
    while scoreAccum >= step and steps < 8 do
        scoreAccum = scoreAccum - step
        steps = steps + 1
        if TPG.Objectives and TPG.Objectives.ProcessScoring then
            TPG.Objectives.ProcessScoring()
        end
        -- Rush checks its hold clock here rather than on its own timer, so the
        -- stage it completes is read from the same ownership the scoring step
        -- just resolved. No-ops outside a Rush round.
        if TPG.Rush and TPG.Rush.Think then
            TPG.Rush.Think()
        end
        ran = true
    end

    if ran then
        TPG.Rounds.CheckWinCondition()
        if TPG.Net and TPG.Net.SyncScores then
            TPG.Net.SyncScores()
        end
    end
end)