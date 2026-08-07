--[[
    TPG.Config is one flat table of hand-tuned numbers, and nearly every read
    site is `TPG.Config.xyz or <fallback>` -- so a deleted or renamed key does
    not error, it silently reads as the fallback everywhere. These assert the
    keys exist and the relationships BETWEEN them still hold, which is the part
    no single read site can check for itself.
]]

describe("config: keys that must exist")

it("has every field the round loop reads", function()
    local required = {
        "startingTickets", "winsToMapVote",
        "dmTicketRefPlayers", "dmTicketMaxMult",
        "dmOvertimeStart", "dmOvertimeBleed", "dmOvertimeRamp",
        "dmOvertimeRampEvery", "dmOvertimeBleedMax",
        "objOvertimeStart", "objOvertimeRamp", "objOvertimeDrainMul", "objOvertimeCapMul",
        "kothCapMul", "scoreStep", "captureStep",
    }
    for _, key in ipairs(required) do
        expect.eq(type(TPG.Config[key]), "number", "TPG.Config." .. key)
    end
end)

it("has every field the loadout and movement code reads", function()
    local required = {
        "baseWalkSpeed", "baseRunSpeed", "baseSpeedPercent", "minSpeedPercent",
        "safezoneRadius", "spawnProtectionTime",
    }
    for _, key in ipairs(required) do
        expect.eq(type(TPG.Config[key]), "number", "TPG.Config." .. key)
    end
end)

describe("config: the speed floor")

it("keeps the heaviest loadout above zero speed", function()
    -- The bug this floor exists for: Juggernaut (-40) plus an ordinary kit
    -- summed to exactly baseSpeedPercent - 55 = 0, and Source skips its speed
    -- clamp entirely at <= 0, falling back to sv_maxspeed -- so the heaviest
    -- armour came out the fastest thing on the field.
    local jugg = TPG.Armor[4].speedBonus
    local kit  = TPG.WeaponConfig.DefaultSpeed.Primary
              + TPG.WeaponConfig.DefaultSpeed.Secondary
              + TPG.WeaponConfig.DefaultSpeed.Special

    local raw = TPG.Config.baseSpeedPercent + jugg + kit
    expect.truthy(raw <= 0,
        "this test guards a floor that only matters if the raw sum can reach 0; " ..
        "raw sum is now " .. raw .. ", so re-derive the guard")

    expect.truthy(TPG.Config.minSpeedPercent > 0,
        "minSpeedPercent must be above zero or the engine ignores the clamp")
end)

it("clamps to a speed that is slow but non-zero", function()
    local pct = math.max(TPG.Config.minSpeedPercent, 0)
    expect.truthy(TPG.Config.baseWalkSpeed * pct / 100 >= 1, "walk speed at the floor")
    expect.truthy(TPG.Config.baseRunSpeed * pct / 100 >= 1, "run speed at the floor")
end)

describe("config: relationships between fields")

it("warns before it kicks", function()
    expect.truthy(TPG.Config.afkKickTime > TPG.Config.afkWarningTime,
        "afkKickTime must exceed afkWarningTime or the warning never shows")
end)

it("orders the wait-for-players window", function()
    expect.truthy(TPG.Config.waitMaxTotal >= TPG.Config.waitJoinExtend)
    expect.truthy(TPG.Config.waitJoinExtend >= TPG.Config.waitBaseTime)
end)

it("caps the DM overtime bleed above where it starts", function()
    expect.truthy(TPG.Config.dmOvertimeBleedMax >= TPG.Config.dmOvertimeBleed)
    expect.truthy(TPG.Config.dmOvertimeRamp > 0)
    expect.truthy(TPG.Config.dmOvertimeRampEvery > 0)
end)

it("never lets a full capture be faster than a neutral one", function()
    expect.truthy(TPG.Config.capTimeMax >= TPG.Config.capTimeNeutral,
        "taking a point off the enemy should cost at least as much as taking a neutral one")
end)

it("keeps the underdog thresholds inside their ranges", function()
    expect.truthy(TPG.Config.underdogRatio > 0 and TPG.Config.underdogRatio < 1)
    expect.truthy(TPG.Config.underdogMinGap > 0)
    expect.truthy(TPG.Config.underdogIncomeMult >= 1)
    expect.truthy(TPG.Config.underdogMinGap < TPG.Config.startingTickets,
        "a gap larger than the whole pool could never be reached")
end)

it("keeps every probability a probability", function()
    for _, key in ipairs({ "ctfChance", "economyChance", "rtvPercentRequired",
                           "scramblePercent", "autoScrambleChance", "scrambleJitter",
                           "disposableATUpgradeChance" }) do
        local v = TPG.Config[key]
        expect.eq(type(v), "number", "TPG.Config." .. key)
        expect.truthy(v >= 0 and v <= 1, "TPG.Config." .. key .. " should be 0..1, is " .. tostring(v))
    end
end)

describe("config: the game-type roll bands")

it("leaves room for KOTH to roll", function()
    -- The bands in sh_gametypes.lua are cumulative thresholds on one
    -- math.random(), and only the first is configurable: CTF takes roll <
    -- ctfChance, KOTH takes the slice up to a hard-coded 0.45. At ctfChance =
    -- 0.45 KOTH stops rolling at all, silently.
    expect.truthy(TPG.Config.ctfChance < 0.45,
        "ctfChance at or above 0.45 eats KOTH's whole slice; move the 0.45 in " ..
        "RollGameType with it if that is really the intent")
end)

it("keeps the CTF flag mostly on the KOTH point", function()
    expect.truthy(TPG.Config.ctfKothWeight >= 0.5,
        "documented as clamped to at least 0.5")
    expect.truthy(TPG.Config.ctfKothWeight <= 1)
end)

describe("config: the per-gametype overtime overrides")

it("keys the overrides by real game types", function()
    for _, tbl in ipairs({ "objOvertimeStartByType", "objOvertimeRampByType" }) do
        for gameType in pairs(TPG.Config[tbl] or {}) do
            expect.truthy(TPG.GameTypes[gameType],
                tbl .. " has an entry for unknown game type " .. tostring(gameType))
        end
    end
end)

it("does not override the mode that has its own bleed", function()
    expect.nils(TPG.Config.objOvertimeStartByType[GAMEMODE_DM],
        "deathmatch uses the dmOvertime* fields, not the objective ones")
end)

describe("config: the map-vote ballot")

it("splits the ballot into whole slots", function()
    local total = 0
    for _, n in pairs(TPG.Config.mapVoteSlots) do
        expect.eq(n, math.floor(n), "slot counts must be whole numbers")
        expect.truthy(n > 0)
        total = total + n
    end
    expect.eq(total, 6, "documented as 6 candidates total")
end)

describe("config: ACE validation")

-- ValidateACE mutates TPG.Config.useACEPoints, and the gamemode is loaded once
-- for the whole run, so each of these puts the flag back rather than leaking a
-- disabled point system into every suite that follows.
local function withACE(ace, cfw, fn)
    local saved = TPG.Config.useACEPoints
    ACE, ACF, CFW = ace and {} or nil, ace and {} or nil, cfw and {} or nil
    local ok, err = pcall(fn)
    ACE, ACF, CFW = nil, nil, nil
    TPG.Config.useACEPoints = saved
    if not ok then error(err, 0) end
end

it("turns ACE points off when CFW is missing", function()
    withACE(false, false, function()
        TPG.Config.useACEPoints = true

        local hasACE, hasCFW = TPG.Config.ValidateACE()

        expect.falsy(hasACE)
        expect.falsy(hasCFW)
        expect.falsy(TPG.Config.useACEPoints, "point limits need CFW")
        expect.falsy(TPG.ACEAvailable)
    end)
end)

it("leaves ACE points on when CFW is present", function()
    withACE(true, true, function()
        TPG.Config.useACEPoints = true

        local hasACE, hasCFW = TPG.Config.ValidateACE()

        expect.truthy(hasACE)
        expect.truthy(hasCFW)
        expect.truthy(TPG.Config.useACEPoints)
    end)
end)

it("never turns ACE points back on by itself", function()
    -- Documented as a one-way trip: once CFW-missing has flipped it off, a
    -- later call with CFW present must not silently re-enable it.
    withACE(true, true, function()
        TPG.Config.useACEPoints = false
        TPG.Config.ValidateACE()
        expect.falsy(TPG.Config.useACEPoints)
    end)
end)
