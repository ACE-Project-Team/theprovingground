--[[
    Round Management
]]

-- Initialize namespace FIRST
TPG.Rounds = TPG.Rounds or {}

function TPG.Rounds.Setup(skipCleanup)
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

    if economyOn then
        TPG.Util.ChatBroadcast(
            "[TPG] PER-PLAYER ECONOMY is ON this round: you each spend a PERSONAL point budget, and destroyed vehicles are NOT refunded.",
            Color(120, 230, 120))
    end
end

function TPG.Rounds.CheckWinCondition()
    if not TPG.State.round.active then return end
    
    local winner = nil
    
    if TPG.State.scores[TEAM_GREEN] <= 0 then
        winner = TEAM_RED
    elseif TPG.State.scores[TEAM_RED] <= 0 then
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