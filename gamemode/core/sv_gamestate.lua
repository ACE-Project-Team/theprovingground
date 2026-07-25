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

    -- Economy: reset wallets for the new round (only acts if active)
    if TPG.Economy and TPG.Economy.OnRoundReset then
        TPG.Economy.OnRoundReset()
    end
end

--[[
    Rejoin carryover.

    Per-player state is keyed by the player ENTITY, so it was destroyed the
    moment someone disconnected and rebuilt from scratch when they came back.
    That made reconnecting a reset button for everything punitive or spendable:
    a long duplicator cooldown, a spent wallet and a team-switch cooldown all
    went away if you just dropped and rejoined -- and people were doing it.

    So park those on the way out under the SteamID and put them back on the way
    in. Only within CARRYOVER_TTL, and the duplicator cooldown only if it's
    still the same round (rounds clear it anyway, so restoring one from a
    finished round would be punishing someone for nothing).
]]
local CARRYOVER_TTL = 900   -- seconds; a rejoin much later isn't dodging anything

local carryover = {}        -- [sid64] = { at, round, dupeCooldown, money, lastSwitch }

local function StashCarryover(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64()
    if not isstring(sid) or #sid ~= 17 then return end

    local pState = TPG.State.players[ply]
    if not pState then return end

    carryover[sid] = {
        at           = CurTime(),
        round        = TPG.State.round.startTime,
        dupeCooldown = math.max((pState.dupeCooldown or 0) - CurTime(), 0),
        money        = pState.money,
        lastSwitch   = ply.tpgLastTeamSwitch,
    }
end

local function RestoreCarryover(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64()
    local c = isstring(sid) and carryover[sid]
    if not c then return end

    carryover[sid] = nil
    if CurTime() - c.at > CARRYOVER_TTL then return end

    local pState = TPG.State.GetPlayer(ply)

    if c.round == TPG.State.round.startTime and (c.dupeCooldown or 0) > 0 then
        pState.dupeCooldown = CurTime() + c.dupeCooldown
    end

    -- Wallet: sv_economy's initial stipend reads this instead of handing out a
    -- fresh startingMoney when it's set.
    if c.money then pState.carriedMoney = c.money end

    if c.lastSwitch then ply.tpgLastTeamSwitch = c.lastSwitch end
end

-- Hook for player connect/disconnect
hook.Add("PlayerInitialSpawn", "TPG_InitPlayerState", function(ply)
    TPG.State.InitPlayer(ply)
    RestoreCarryover(ply)
end)

hook.Add("PlayerDisconnected", "TPG_CleanupPlayerState", function(ply)
    StashCarryover(ply)
    TPG.State.CleanupPlayer(ply)
end)