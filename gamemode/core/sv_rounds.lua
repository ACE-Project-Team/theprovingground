--[[
    Round Management
]]

-- Initialize namespace FIRST
TPG.Rounds = TPG.Rounds or {}

function TPG.Rounds.Setup(skipCleanup)
    -- Load map config
    local mapConfig = TPG.Maps.Load()
    
    -- Select gametype
    TPG.State.gameType = TPG.SelectRandomGameType()
    local gameType = TPG.GetGameType(TPG.State.gameType)
    
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

-- Game think for round logic
local thinkTick = 0

hook.Add("Think", "TPG_RoundThink", function()
    thinkTick = thinkTick + 1
    
    if thinkTick < TPG.Config.gameThinkInterval then return end
    thinkTick = 0
    
    if not TPG.State.round.active then return end
    
    -- Process objective scoring
    if TPG.Objectives and TPG.Objectives.ProcessScoring then
        TPG.Objectives.ProcessScoring()
    end
    
    -- Check win condition
    TPG.Rounds.CheckWinCondition()
    
    -- Sync scores
    if TPG.Net and TPG.Net.SyncScores then
        TPG.Net.SyncScores()
    end
end)