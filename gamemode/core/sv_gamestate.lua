--[[
    Central Game State Management
]]

TPG.State = {
    gameType = GAMEMODE_CP,
    
    scores = {
        [TEAM_GREEN] = 300,
        [TEAM_RED]   = 300,
    },
    
    spawns = {
        [TEAM_GREEN] = Vector(0, 0, 0),
        [TEAM_RED]   = Vector(0, 0, 0),
    },
    
    limits = {
        [TEAM_GREEN] = { props = 0, weight = 0, points = 0 },
        [TEAM_RED]   = { props = 0, weight = 0, points = 0 },
    },
    
    maxLimits = {
        props   = 300,
        weight  = 100000,
        points  = 5000,
    },
    
    objectives = {},
    
    round = {
        active      = false,
        startTime   = 0,
        wins        = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 },
    },
    
    players = {},  -- Per-player state
    
    voting = {
        active  = false,
        maps    = {},
        votes   = {},
        endTime = 0,
    },
}

-- Initialize player state
function TPG.State.InitPlayer(ply)
    TPG.State.players[ply] = {
        dupeCooldown    = 0,
        spawnProtection = 0,
        stats           = {
            kills           = 0,
            killsPerTon     = 0,
            objectiveKills  = 0,
            captures        = 0,
        },
        votes = {
            rtv         = false,
            scramble    = false,
            map         = nil,
        },
    }
end

-- Clean up player state
function TPG.State.CleanupPlayer(ply)
    TPG.State.players[ply] = nil
end

-- Get player state (with auto-init)
function TPG.State.GetPlayer(ply)
    if not TPG.State.players[ply] then
        TPG.State.InitPlayer(ply)
    end
    return TPG.State.players[ply]
end

-- Modify score
function TPG.State.AddScore(teamId, amount)
    TPG.State.scores[teamId] = TPG.State.scores[teamId] + amount
    
    if TPG.State.scores[teamId] < 0 then
        TPG.State.scores[teamId] = 0
    end
end

-- Reset for new round
function TPG.State.ResetRound()
    TPG.State.scores[TEAM_GREEN] = TPG.Config.startingTickets
    TPG.State.scores[TEAM_RED] = TPG.Config.startingTickets
    
    TPG.State.limits[TEAM_GREEN] = { props = 0, weight = 0, points = 0 }
    TPG.State.limits[TEAM_RED] = { props = 0, weight = 0, points = 0 }
    
    TPG.State.round.active = true
    TPG.State.round.startTime = CurTime()
    
    -- Reset player stats
    for ply, data in pairs(TPG.State.players) do
        if IsValid(ply) then
            data.dupeCooldown = 0
            data.stats = { kills = 0, killsPerTon = 0, objectiveKills = 0, captures = 0 }
        end
    end
end

-- Hook for player connect/disconnect
hook.Add("PlayerInitialSpawn", "TPG_InitPlayerState", function(ply)
    TPG.State.InitPlayer(ply)
end)

hook.Add("PlayerDisconnected", "TPG_CleanupPlayerState", function(ply)
    TPG.State.CleanupPlayer(ply)
end)