--[[
    Round Management
]]

-- Initialize namespace FIRST
TPG.Rounds = TPG.Rounds or {}

function TPG.Rounds.Setup(skipCleanup)
    -- If a round is being set up by any path (admin restart, points reload),
    -- the wait-for-players window is over -- never leave building blocked.
    TPG.State.waitingForPlayers = false
    timer.Remove("TPG_WaitForPlayers")

    -- Keep ULX UTeam from yanking grouped players (admins) off their TPG team.
    if TPG.DisableExternalTeamForcing then TPG.DisableExternalTeamForcing() end

    -- Load map config
    local mapConfig = TPG.Maps.Load()
    
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
    
    -- Clean map
    if not skipCleanup then
        game.CleanUpMap(true)
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
    
    -- Kill all players to respawn them
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then
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

function TPG.Rounds.EndRound(winningTeam)
    TPG.State.round.active = false
    TPG.State.round.wins[winningTeam] = TPG.State.round.wins[winningTeam] + 1
    
    local teamData = TPG.GetTeamData(winningTeam)
    
    TPG.Util.ChatBroadcast(teamData.name .. " has won the round!", teamData.color)
    
    -- Play sounds
    for _, ply in ipairs(player.GetAll()) do
        if ply:Team() == winningTeam then
            TPG.Util.PlaySound(ply, "mvm/mvm_tele_activate.wav")
        else
            TPG.Util.PlaySound(ply, "mvm/mvm_warning.wav")
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
        ran = true
    end

    if ran then
        TPG.Rounds.CheckWinCondition()
        if TPG.Net and TPG.Net.SyncScores then
            TPG.Net.SyncScores()
        end
    end
end)