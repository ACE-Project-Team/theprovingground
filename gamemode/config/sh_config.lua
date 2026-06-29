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

    -- Capture the Flag (objectives/sv_ctf.lua). One neutral flag on the KOTH
    -- point; grab it and carry it to your own spawn to score. KOTH maps only.
    ctfChanceWithinKoth  = 0.5,    -- chance CTF replaces KOTH when the KOTH slot is rolled
    ctfDeliverRadius     = 500,    -- fallback delivery radius if the safezone can't be resolved
    ctfCaptureTicketLoss = 75,     -- enemy tickets lost per delivered flag
    ctfCaptureReward     = 1500,   -- per-player economy reward to the carrier on delivery
    ctfReturnTime        = 25,     -- seconds a dropped flag waits before returning to its point
    ctfMaxCarryTime      = 150,    -- a single carry auto-returns after this many seconds (anti-hoarding)

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
    economyChance       = 0.30,

    -- Duplication
    dupeCooldownPerTon  = 2,
    dupeCooldownPer1kPoints = 3,    -- +seconds of cooldown per 1000 ACE points of the build (item: pricier builds = longer cooldown)
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