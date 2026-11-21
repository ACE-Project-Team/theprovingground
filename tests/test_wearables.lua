--[[
    ACE wearable issue rules.

    Loads the server file under stubs -- the only real thing under test is the
    rule table in `TPG.Wearables.ApplyFor` plus the suit's buy-and-count-down
    lifecycle, both of which are pure decisions. The ACE side (NW vars, armor
    layers, bonemerging) is ACE's own suite's business.

    Every stub is reinstalled inside `reset()` at the top of each case: `it`
    only registers its function, so anything installed at file scope would be
    active for EVERY suite's cases, and anything restored at file scope would
    be gone before the first case ran. TPG.State, TPG.Economy and
    TPG.Underdog are server modules the shared chain never loads, so there is
    nothing real to preserve.
]]

local gmod = expect.load.gmod

expect.load.dofile(expect.root .. "/gamemode/player/sv_wearables.lua")

local worn, charges, pStates

local function reset()
    -- [ply][slot] = { skin, tint } of the last SetWearing call
    worn, charges, pStates = {}, {}, {}

    _G.ACE = {
        Wearables = {
            SetWearing = function(ply, slot, on, skin, tint)
                worn[ply] = worn[ply] or {}
                worn[ply][slot] = on and { skin = skin, tint = tint } or nil
            end,
        },
    }

    TPG.State = TPG.State or {}
    TPG.State.GetPlayer = function(ply)
        pStates[ply] = pStates[ply] or {}
        return pStates[ply]
    end

    TPG.Economy = {
        Active = true,
        _chargeOk = true,
        Charge = function(ply, cost, reason)
            charges[#charges + 1] = { ply = ply, cost = cost, reason = reason }
            return TPG.Economy._chargeOk
        end,
    }

    TPG.Underdog = {
        _underdog = false,
        IsPlayerUnderdog = function() return TPG.Underdog._underdog end,
    }
end

local function green(fields)
    return gmod.player(TEAM_GREEN, fields)
end

describe("wearables: spawn issue rules")

it("gives the no-armour tier the standard helmet and no vest", function()
    reset()
    local ply = green()
    TPG.Wearables.ApplyFor(ply, 0)
    expect.truthy(worn[ply] and worn[ply].helmet, "tier 0 should wear the helmet")
    expect.falsy(worn[ply].vest, "tier 0 should not get a vest by default")
end)

it("issues nothing to the ordinary armoured tiers", function()
    reset()
    local ply = green()
    TPG.Wearables.ApplyFor(ply, 1)
    TPG.Wearables.ApplyFor(ply, 2)
    TPG.Wearables.ApplyFor(ply, 3)
    expect.falsy(worn[ply] and next(worn[ply]), "tiers 1-3 should stay bare")
end)

it("puts the heavy helmet on the juggernaut, tinted", function()
    reset()
    local ply = green()
    TPG.Wearables.ApplyFor(ply, 4)
    local heavy = worn[ply] and worn[ply].helmet_heavy
    expect.truthy(heavy, "tier 4 should wear helmet_heavy")
    expect.eq(heavy.skin, 1, "heavy helmet should use the tintable skin")
    expect.truthy(heavy.tint, "heavy helmet should carry a tint")
    expect.falsy(worn[ply].helmet, "juggernaut should not also wear the plain helmet")
end)

it("gives the underdog a free vest whatever their tier", function()
    reset()
    TPG.Underdog._underdog = true
    local ply = green()
    TPG.Wearables.ApplyFor(ply, 2)
    expect.truthy(worn[ply] and worn[ply].vest, "underdog should wear the vest")
    expect.falsy(worn[ply].helmet, "underdog vest should not come with a helmet")
end)

it("arms the whole suit while a purchase is running", function()
    reset()
    local ply = green()
    TPG.State.GetPlayer(ply).suitRounds = 5
    TPG.Wearables.ApplyFor(ply, 1)
    expect.truthy(worn[ply].helmet, "suit should give a helmet on a paid tier")
    expect.truthy(worn[ply].vest, "suit should give the vest")
end)

it("keeps the juggernaut in the heavy helmet when it buys the suit", function()
    reset()
    local ply = green()
    TPG.State.GetPlayer(ply).suitRounds = 5
    TPG.Wearables.ApplyFor(ply, 4)
    expect.truthy(worn[ply].helmet_heavy, "suit must not downgrade the juggernaut helmet")
    expect.falsy(worn[ply].helmet, "plain helmet must not stack on the heavy one")
    expect.truthy(worn[ply].vest, "suit still gives the vest")
end)

it("does nothing for spectators", function()
    reset()
    local ply = gmod.player(TEAM_UNASSIGNED)
    TPG.Wearables.ApplyFor(ply, 0)
    expect.falsy(worn[ply] and next(worn[ply]), "spectators should get no wearables")
end)

describe("wearables: buying the suit")

it("charges the price and runs for the configured rounds", function()
    reset()
    local ply = green()
    local ok = TPG.Wearables.BuySuit(ply)
    expect.truthy(ok, "the purchase should succeed")
    expect.eq(#charges, 1, "exactly one charge should have landed")
    expect.eq(charges[1].cost, TPG.Gear.Suit.cost, "charged the configured price")
    expect.eq(pStates[ply].suitRounds, TPG.Gear.Suit.rounds,
        "suit should run for the configured rounds")
end)

it("refuses a second purchase while the first still has rounds left", function()
    reset()
    local ply = green()
    TPG.State.GetPlayer(ply).suitRounds = 3
    local ok, why = TPG.Wearables.BuySuit(ply)
    expect.falsy(ok, "should refuse")
    expect.truthy(why, "should say why")
    expect.eq(#charges, 0, "a refused purchase must not charge")
end)

it("refuses when the wallet is short", function()
    reset()
    TPG.Economy._chargeOk = false
    local ply = green()
    local ok = TPG.Wearables.BuySuit(ply)
    expect.falsy(ok)
    expect.eq(pStates[ply].suitRounds or 0, 0, "a failed charge grants no suit")
end)

it("refuses with the economy off", function()
    reset()
    TPG.Economy.Active = false
    local ply = green()
    local ok = TPG.Wearables.BuySuit(ply)
    expect.falsy(ok, "suit is an economy purchase only")
end)

describe("wearables: the suit running down")

it("counts one round off each round end and stops arming at zero", function()
    reset()
    local ply = green()
    TPG.Wearables.BuySuit(ply)

    for _ = 1, TPG.Gear.Suit.rounds do TPG.Wearables.OnRoundEnd() end
    expect.eq(pStates[ply].suitRounds, 0, "the run should be spent")

    TPG.Wearables.ApplyFor(ply, 1)
    expect.falsy(worn[ply] and next(worn[ply]), "an expired suit arms nothing")
end)

it("only counts down players who own one", function()
    reset()
    local owner, other = green(), green()
    TPG.State.GetPlayer(owner).suitRounds = 1
    TPG.Wearables.OnRoundEnd()
    expect.eq(pStates[owner].suitRounds, 0)
    expect.eq(TPG.State.GetPlayer(other).suitRounds or 0, 0, "untouched player stays at zero")
end)

describe("wearables: absent ACE")

it("reports unavailable and issues nothing without the ACE API", function()
    reset()
    _G.ACE = nil
    expect.falsy(TPG.Wearables.Available())
    local ply = green()
    TPG.Wearables.ApplyFor(ply, 4)
    expect.falsy(worn[ply] and next(worn[ply]))
    local ok = TPG.Wearables.BuySuit(ply)
    expect.falsy(ok, "cannot buy what does not exist")
end)
