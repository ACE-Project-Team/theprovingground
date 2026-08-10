--[[--
    Central game state: the server's authoritative picture of the round.

    One table, `TPG.State`, holding the current game type, both teams' ticket
    pools, this round's spawns, the prop/weight/point limits and what each team
    has spent of them, the live objectives, round bookkeeping, per-player state
    and the voting state. Clients get a copy of the parts they need through
    `TPG.Net.SyncState`; nothing here is networked automatically.

    Per-player state is keyed by the player **entity**, so it dies with the
    player. Anything punitive or spendable that must survive a reconnect is
    parked under the SteamID by the carryover block at the bottom of this file.

    @module tpg.state
    @realm server
]]

TPG.State = {
    gameType = GAMEMODE_CP,
    
    scores = {
        [TEAM_GREEN] = 300,
        [TEAM_RED]   = 300,
    },
    
    -- Published by TPG.Rounds.Setup once a round actually starts. Deliberately
    -- EMPTY until then: these used to default to Vector(0, 0, 0), which is a
    -- perfectly truthy Vector, so every "do we have a spawn yet" check said yes
    -- and handed out the map origin. See player/sv_spawning.lua for what that
    -- cost. Read them through TPG.State.GetSpawn, never directly.
    spawns = {},
    
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

--[[--
    The round's spawn for a team, or nil if there isn't a real one yet.

    Always read spawns through this rather than indexing `TPG.State.spawns`,
    which is empty until @{tpg.rounds.Setup} publishes a round's spawns.

    "Real" excludes the map origin on purpose. Nothing legitimately spawns at
    0,0,0 -- it is what you get from an unset Vector and from
    `TPG.Maps.GetSpawn`'s own fallback -- and on most maps it is inside the
    world or under it, which is an out-of-world death that god mode does not
    stop. `TPG.State.spawns` used to default to that Vector, which is perfectly
    truthy, so every "do we have a spawn yet" check said yes and handed out the
    map origin. See `player/sv_spawning.lua` for what that cost.

    @tparam number teamId TEAM_GREEN or TEAM_RED.
    @treturn ?Vector The spawn, or nil if none has been published this round.
    @realm server
]]
function TPG.State.GetSpawn(teamId)
    local pos = TPG.State.spawns[teamId]
    if not isvector(pos) or pos:IsZero() then return nil end
    return pos
end

--- Create a player's state table, discarding anything already there.
-- Called from `PlayerInitialSpawn`. Prefer @{GetPlayer}, which initialises on
-- demand; calling this on a connected player wipes their cooldowns and votes.
-- @tparam Player ply
-- @realm server
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

--- Drop a player's state table.
-- Called from `PlayerDisconnected`, after the carryover has been stashed.
-- @tparam Player ply
-- @realm server
function TPG.State.CleanupPlayer(ply)
    TPG.State.players[ply] = nil
end

--[[--
    A player's state table, creating it if needed.

    The normal way in. Returns the live table, so writing to it is how the rest
    of the gamemode records cooldowns, per-round stats and votes:

        dupeCooldown     CurTime() past which the duplicator is usable again
        spawnProtection  CurTime() past which spawn protection has expired
        stats            this round only: kills, killsPerTon, objectiveKills,
                         captures. Cleared by @{ResetRound}
        votes            rtv, scramble, map
        money            wallet, when the per-player economy is running
        gearCooldowns    [gear key] = { charges, expires, cooldown } -- lives
                         left in the item's current run, and the CurTime its
                         timer runs out (0 while none is running). See
                         @{tpg.gearsystem}.

    @tparam Player ply
    @treturn table The live state table.
    @realm server
]]
function TPG.State.GetPlayer(ply)
    if not TPG.State.players[ply] then
        TPG.State.InitPlayer(ply)
    end
    return TPG.State.players[ply]
end

--- Add to (or drain from) a team's ticket pool, clamped at zero.
-- Scoring drains the *losing* side rather than adding to the winner, so in
-- practice `amount` is negative. The pool never goes below zero, so a large
-- overshoot is not carried into the next round.
-- Does not itself end the round; @{tpg.rounds.CheckWinCondition} notices.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @tparam number amount Signed.
-- @realm server
function TPG.State.AddScore(teamId, amount)
    TPG.State.scores[teamId] = TPG.State.scores[teamId] + amount
    
    if TPG.State.scores[teamId] < 0 then
        TPG.State.scores[teamId] = 0
    end
end

--- Reset per-round state and mark the round live.
-- Refills both ticket pools to `TPG.Config.startingTickets`, zeroes both teams'
-- spent limits, stamps the start time, clears every player's duplicator
-- cooldown, paste grace and per-round stats, and resets economy wallets if
-- that mode is running this round. Called from @{tpg.rounds.Setup}, after the map cleanup
-- and before objectives spawn.
-- @realm server
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
            -- Per-life, and a new round is a new life even for someone who was
            -- alive when the last one ended. See the grace comment in
            -- `systems/sv_duplication.lua`.
            data.graceUsed = nil
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

-- [sid64] = { at, round, dupeCooldown, money, gear, lastSwitch }, where gear is
-- [gear key] = { charges, left, cooldown } -- `left` is seconds remaining, not
-- an absolute deadline, so it survives the CurTime the player comes back to.
local carryover = {}

local function StashCarryover(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64()
    if not isstring(sid) or #sid ~= 17 then return end

    local pState = TPG.State.players[ply]
    if not pState then return end

    -- Premium gear: lives left in each run, and any timer stored as remaining
    -- seconds so it resumes rather than restarts. Same reasoning as the
    -- duplicator cooldown -- a reconnect can't be the cheapest way to get
    -- another Javelin -- and it now has to cover the charges too, or dropping
    -- out mid-run would hand the whole allowance back.
    local gear = {}
    for key, st in pairs(pState.gearCooldowns or {}) do
        local left = math.max((st.expires or 0) - CurTime(), 0)
        -- A finished run is not worth carrying: it means the same as never
        -- having taken the item.
        if left > 0 or (st.charges or 0) > 0 then
            gear[key] = { charges = st.charges or 0, left = left, cooldown = st.cooldown or 0 }
        end
    end

    carryover[sid] = {
        at           = CurTime(),
        round        = TPG.State.round.startTime,
        dupeCooldown = math.max((pState.dupeCooldown or 0) - CurTime(), 0),
        money        = pState.money,
        gear         = gear,
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

    -- Gear runs outlive rounds by design, so unlike the duplicator these come
    -- back regardless of which round the player left in.
    if istable(c.gear) and next(c.gear) then
        pState.gearCooldowns = pState.gearCooldowns or {}
        for key, saved in pairs(c.gear) do
            pState.gearCooldowns[key] = {
                charges  = saved.charges or 0,
                -- Rebased onto this session's CurTime, not restored absolute.
                expires  = (saved.left or 0) > 0 and (CurTime() + saved.left) or 0,
                cooldown = saved.cooldown or 0,
            }
        end
    end

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