--[[
    Core Configuration
]]

TPG.Config = {
    -- Scoring
    startingTickets     = 300,
    winsToMapVote       = 2,

    -- Deathmatch ticket drain scales up when the server is emptier, so low-pop
    -- rounds still resolve. At/above dmTicketRefPlayers it's the plain rate;
    -- below it the per-kill loss is multiplied up to dmTicketMaxMult.
    dmTicketRefPlayers  = 8,
    dmTicketMaxMult     = 2.0,

    -- DM overtime: deaths are DM's only ticket drain, so two passive teams made
    -- a round literally endless (and spawn camping stalled it on purpose).
    -- After dmOvertimeStart seconds BOTH teams bleed tickets, and the bleed
    -- ramps up over time -- active play decides the round early, camping just
    -- loses it slowly.
    dmOvertimeStart     = 600,   -- seconds of normal play before the bleed starts
    dmOvertimeBleed     = 0.2,   -- tickets/second at overtime start (both teams)
    dmOvertimeRamp      = 0.2,   -- added to the rate every dmOvertimeRampEvery
    dmOvertimeRampEvery = 120,   -- seconds per ramp step
    dmOvertimeBleedMax  = 2.0,   -- rate cap

    -- Underdog comeback bonuses (systems/sv_underdog.lua). A team is the
    -- underdog while its tickets are <= underdogRatio of the enemy's AND the
    -- absolute gap is at least underdogMinGap (no flicker at round start).
    underdogRatio          = 0.6,
    underdogMinGap         = 60,
    underdogProtectionTime = 8,      -- spawn protection seconds (base is spawnProtectionTime)
    underdogAmmoBonus      = 2,      -- added to the Special-slot ammo floor
    underdogIncomeMult     = 1.25,   -- multiplier on ALL per-player economy income
    underdogSmokeClass     = "weapon_ace_smokegrenade",  -- free on spawn while underdog

    -- Wait-for-players window at map start: the first round doesn't begin until
    -- loading players are in, so fast loaders can't burn team budget (or start
    -- earning) before slow loaders even exist. Base wait always applies; anyone
    -- mid-connect pushes the start back to at least waitJoinExtend from now,
    -- capped at waitMaxTotal overall.
    waitBaseTime   = 5,
    waitJoinExtend = 15,
    waitMaxTotal   = 90,

    -- Capture the Flag (objectives/sv_ctf.lua). Its OWN game mode: one neutral
    -- flag that sits on the map's KOTH capture point; grab it and carry it to
    -- your own spawn to score. Only offered on maps that have a KOTH point.
    ctfChance            = 0.30,   -- per-round chance CTF is the mode (see TPG.SelectRandomGameType)
    ctfDeliverRadius     = 500,    -- fallback delivery radius if the safezone can't be resolved
    ctfCaptureTicketLoss = 40,     -- enemy tickets lost per delivered flag (75 ended rounds in ~4 caps; ~8 now)
    ctfCaptureReward     = 1500,   -- per-player economy reward to the carrier on delivery
    ctfReturnTime        = 25,     -- seconds a dropped flag waits before returning to its point
    ctfMaxCarryTime      = 150,    -- a single carry auto-returns after this many seconds (anti-hoarding)

    -- Bonus disposable AT (entities/weapons/disposableat): every teamed player
    -- who brings neither a launcher nor mines in their Special slot gets a
    -- single-use AT tube for free, so plain infantry always have an answer to
    -- armour. Set the class to "" to disable.
    disposableATClass   = "disposableat",

    -- Voluntary team-switch cooldown (sv_teams.lua). Stops green<->red flipping
    -- to chase the winning side / dodge autobalance / double-dip team budgets.
    -- Admins bypass it; a scramble ignores it (and re-stamps everyone so the
    -- forced move can't be instantly reversed). First join is always free.
    teamSwitchCooldown  = 30,

    -- Safezone
    safezoneRadius      = 750,
    spawnProtectionTime = 5,
    
    -- Movement
    baseWalkSpeed       = 200,
    baseRunSpeed        = 350,
    baseSpeedPercent    = 55,
    
    -- Limits (fallback if ACE unavailable)
    fallbackPropLimit   = 300,
    fallbackWeightLimit = 100,
    
    -- ACE Integration
    useACEPoints        = true,
    teamPointLimit      = 5000,
    playerPointLimit    = 2500,

    -- Per-player economy as a secondary mode (see systems/sv_economy.lua).
    -- Per-round chance it activates, unless an admin forces it via the
    -- tpg_economy_enabled convar.
    economyChance       = 0.45,

    -- Duplication
    dupeCooldownPerTon  = 2.5,
    dupeCooldownPer1kPoints = 3.75,    -- +seconds of cooldown per 1000 ACE points of the build (item: pricier builds = longer cooldown)
    dupeGracePeriod     = 60,
    lightVehicleWeight  = 5000,
    lightVehicleProps   = 140,
    maxDupeWeight       = 65000,
    
    -- Vehicles
    maxSpeedUnits       = 3500,
    maxGForce           = 50,
    easyEntryRange      = 750,
    easyEntryDelay      = 3,
    
    -- AFK
    afkWarningTime      = 20,
    afkKickTime         = 120,
    
    -- Voting
    mapVoteTime         = 20,
    rtvMinPlayers       = 3,
    rtvPercentRequired  = 0.5,
    scramblePercent     = 0.25,
    -- Map-vote ballot size by category (6 candidates total).
    mapVoteSlots        = { open = 3, urban = 2, bonus = 1 },

    -- Capture Points
    capDistanceMeters   = 5,
    capTimeNeutral      = 10,
    capTimeMax          = 15,
    capMaxPlayers       = 3,
    
    -- Think rates (wall-clock seconds). Game logic used to run every N *ticks*,
    -- so captures and ticket drain ran slower on low-tickrate (e.g. 33-tick)
    -- servers. These keep the 66-tick feel on any tickrate (~0.075s = 5 ticks @66).
    captureStep         = 0.075,    -- capture-point progress step
    scoreStep           = 0.075,    -- round scoring / ticket drain step
    propUpdateInterval  = 100,
}

function TPG.Config.ValidateACE()
    local hasACE = ACE ~= nil and ACF ~= nil
    local hasCFW = CFW ~= nil
    
    TPG.ACEAvailable = hasACE
    TPG.CFWAvailable = hasCFW
    
    if TPG.Config.useACEPoints and not hasCFW then
        print("[TPG] Warning: CFW not found, using weight-based limits")
        TPG.Config.useACEPoints = false
    end
    
    print("[TPG] ACE: " .. tostring(hasACE) .. ", CFW: " .. tostring(hasCFW))
    return hasACE, hasCFW
end