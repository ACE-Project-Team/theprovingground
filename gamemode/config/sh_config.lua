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
    -- Also free on spawn while underdog. Set to your installed medkit SWEP's
    -- class (many workshop ones use "weapon_medkit"); "" disables it. Skipped
    -- silently if the class isn't installed.
    underdogMedkitClass    = "weapon_medkit",

    -- Wait-for-players window at map start: the first round doesn't begin until
    -- loading players are in, so fast loaders can't burn team budget (or start
    -- earning) before slow loaders even exist. Base wait always applies; anyone
    -- mid-connect pushes the start back to at least waitJoinExtend from now,
    -- capped at waitMaxTotal overall.
    waitBaseTime   = 5,
    waitJoinExtend = 15,
    waitMaxTotal   = 90,

    -- Preparation period at the start of every round (core/sv_prep.lua). Once at
    -- least prepMinPlayers players are split across BOTH teams, a prepTime-second
    -- build/stage window begins during which everyone is confined to their own
    -- safezone (leaving teleports you back), so a round always opens with both
    -- sides ready in spawn instead of one team already rolling out. Before that
    -- condition is met there's no confinement (a lone player can still roam).
    prepTime       = 30,   -- seconds of confinement once both teams are present
    prepMinPlayers = 2,    -- total players (both teams) needed to start the countdown

    -- King of the Hill drain. KOTH bleeds the team that ISN'T holding the hill
    -- at (points held) * capMul every scoreStep (0.075s). Every map hardcodes a
    -- 0.15 KOTH capMultiplier, which drained a full 300-ticket lead in ~2.5 min
    -- of solid holding -- rounds were over almost instantly. This single knob
    -- retunes EVERY KOTH map at once (objectives/sv_objectives.lua applies it for
    -- KOTH regardless of the per-map value). Math: a continuous one-team hold
    -- drains 300 tickets in 300 * scoreStep / kothCapMul seconds. At 0.02 that's
    -- ~18.75 min for a total stomp; realistically contested rounds run 20-25+.
    kothCapMul           = 0.02,

    -- Objective overtime (CP / KOTH / CTF -- DM has its own bleed above).
    -- Objective modes can stalemate outright: two even teams trade the hill,
    -- neither side's tickets move, and the round just doesn't end (a 57-minute
    -- Stalingrad KOTH). Past objOvertimeStart the round starts closing itself
    -- out -- capture times collapse toward instant so a point can actually flip
    -- under fire, and the ticket drain ramps up -- reaching full effect
    -- objOvertimeRamp seconds later. Announced on screen when it kicks in.
    objOvertimeStart     = 900,   -- seconds of normal play before overtime starts
    objOvertimeRamp      = 300,   -- seconds from "just started" to full effect
    objOvertimeDrainMul  = 4,     -- ticket drain multiplier at full effect
    objOvertimeCapMul    = 0.1,   -- capture times shrink to this fraction at full effect

    -- Per-gametype overtime start, overriding objOvertimeStart. CP is the odd
    -- one out: it has SEVERAL points, so the drain already scales with how many
    -- you hold and a team that's winning is banking tickets the whole round --
    -- it does not stalemate the way a single-point KOTH does. Overtime was
    -- arriving while CP rounds were still a real fight and ending them early,
    -- so CP gets a much later start and a gentler ramp. KOTH and CTF, which do
    -- genuinely deadlock, keep the original timing.
    objOvertimeStartByType = {
        [GAMEMODE_CP] = 1500,   -- 25 min (was 15)
    },
    objOvertimeRampByType = {
        [GAMEMODE_CP] = 480,    -- 8 min to full effect (was 5)
    },

    -- Capture the Flag (objectives/sv_ctf.lua). Its OWN game mode: one neutral
    -- flag that sits on the map's KOTH capture point; grab it and carry it to
    -- your own spawn to score. Only offered on maps that have a KOTH point.
    ctfChance            = 0.25,   -- per-round chance CTF is the mode (see TPG.SelectRandomGameType)
    ctfDeliverRadius     = 500,    -- fallback delivery radius if the safezone can't be resolved
    ctfCaptureTicketLoss = 40,     -- enemy tickets lost per delivered flag (75 ended rounds in ~4 caps; ~8 now)
    ctfCaptureReward     = 1500,   -- per-player economy reward to the carrier on delivery
    ctfReturnTime        = 25,     -- seconds a dropped flag waits before returning to its point
    ctfMaxCarryTime      = 150,    -- a single carry auto-returns after this many seconds (anti-hoarding)
    -- Where the flag spawns each CTF round: the KOTH point keeps at least this
    -- share, the rest is split evenly among the map's CP capture points, so the
    -- flag doesn't always sit on the same hill (objectives/sv_ctf.lua). With one
    -- extra point that's 50/50; with two it's 50/25/25; etc. Clamped to >= 0.5.
    ctfKothWeight        = 0.5,
    -- CTF also bleeds a little on kills (systems/sv_commendations.lua), so fights
    -- between flag runs matter -- but flags stay the decisive scoring, so kills
    -- drain only this fraction of the full DM per-kill loss. 0 disables it.
    ctfKillTicketFrac    = 0.4,

    -- Bonus disposable AT (entities/weapons/disposableat): every teamed player
    -- gets a free single-use AT tube on top of their loadout, so everyone always
    -- has an answer to armour even after a chosen launcher runs dry. Set the
    -- class to "" to disable.
    disposableATClass   = "disposableat",
    -- When the bonus tube is handed out, a small chance to upgrade it into a
    -- real launcher instead (must be an installed, enabled loadout weapon).
    disposableATUpgradeChance = 0.2,
    disposableATUpgrades      = { "weapon_ace_stinger", "weapon_ace_javelin" },

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

    --[[
        Floor for the summed speed percentage, before it reaches the engine.

        Armor and weapon penalties are added together, and a Juggernaut (-40)
        carrying an ordinary kit (Primary -5, Special -10) summed to exactly
        55 - 55 = 0 -- and with an LMG it went negative. A max speed of zero or
        below doesn't stop a player: Source skips the clamp entirely and falls
        back to sv_maxspeed, so the heaviest armour in the game came out the
        FASTEST thing on the field. See player/sv_loadout.lua.

        15 is the Juggernaut's own tier before any weapon penalty, so at the
        floor it moves at 60 walk / 89 run. That is deliberately crawling; raise
        this if it plays too slow.
    ]]
    minSpeedPercent     = 15,
    
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
    maxDupeWeight       = 250000,   -- 250t hard cap on a single dupe (weight in kg)
    
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
    -- Scramble tuning (player/sv_teams.lua). Ratings are jittered by this
    -- fraction before drafting so the same roster doesn't produce the identical
    -- two teams every time -- small enough that it only reorders players who
    -- were close anyway. Anyone whose lifetime captures+flags per round is at
    -- or above scrambleCapperRate is drafted as a "capper" in a separate pass,
    -- so both sides get people who play the objective. autoScrambleChance is
    -- the per-round chance teams are scrambled without anyone voting for it.
    scrambleJitter      = 0.08,
    scrambleCapperRate  = 0.5,
    autoScrambleChance  = 0.15,
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

    if not hasACE then
        print("[TPG] ================================================================")
        print("[TPG] WARNING: ACE (Armored Combat Extended) was not found.")
        print("[TPG] TPG is an ACE gamemode and will not work correctly without it.")
        print("[TPG] Install ACE under garrysmod/addons/ and restart the server.")
        print("[TPG] ================================================================")
    end

    print("[TPG] ACE: " .. tostring(hasACE) .. ", CFW: " .. tostring(hasCFW))
    return hasACE, hasCFW
end

-- tpg_e2sf_sandbox (the E2/Starfall tpg* chip functions) has to exist as a REAL
-- addon under garrysmod/addons/ -- normally a junction/symlink to this repo's
-- addons/tpg_e2sf_sandbox folder, since git doesn't carry filesystem
-- links. Easy to forget on a fresh deploy, so check for it and say so loudly
-- rather than let it fail silently. See README.md for setup.
function TPG.Config.ValidateE2SFSandbox()
    local mounted = file.Exists("autorun/server/tpg_e2sf_stub.lua", "LUA")
    TPG.E2SFSandboxMounted = mounted

    if not mounted then
        print("[TPG] ================================================================")
        print("[TPG] NOTE: tpg_e2sf_sandbox addon not found under garrysmod/addons/.")
        print("[TPG] E2/Starfall tpg* chip functions will only work while TPG is the")
        print("[TPG] active gamemode (they won't load in plain sandbox). See")
        print("[TPG] addons/tpg_e2sf_sandbox and README.md to fix.")
        print("[TPG] ================================================================")
    end

    print("[TPG] E2/SF sandbox addon mounted: " .. tostring(mounted))
    return mounted
end