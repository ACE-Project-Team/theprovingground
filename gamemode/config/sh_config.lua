--[[
    Core Configuration
]]

TPG.Config = {
    -- Scoring
    startingTickets     = 300,
    winsToMapVote       = 2,
    
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
    
    -- Duplication
    dupeCooldownPerTon  = 2,
    dupeGracePeriod     = 60,
    lightVehicleWeight  = 5000,
    lightVehicleProps   = 140,
    maxDupeWeight       = 65000,
    
    -- Vehicles
    maxSpeedUnits       = 3500,
    maxGForce           = 50,
    easyEntryRange      = 750,
    easyEntryDelay      = 4,
    
    -- AFK
    afkWarningTime      = 20,
    afkKickTime         = 120,
    
    -- Voting
    mapVoteTime         = 20,
    rtvMinPlayers       = 3,
    rtvPercentRequired  = 0.5,
    scramblePercent     = 0.25,
    
    -- Capture Points
    capDistanceMeters   = 5,
    capTimeNeutral      = 10,
    capTimeMax          = 15,
    capMaxPlayers       = 3,
    
    -- Think rates
    gameThinkInterval   = 5,
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