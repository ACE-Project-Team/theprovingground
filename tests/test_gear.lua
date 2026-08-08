describe("gear: the cooldown key")

it("keeps armor ids and weapon classes in separate namespaces", function()
    expect.eq(TPG.Gear.Key("armor", 3), "armor:3")
    expect.eq(TPG.Gear.Key("weapon", "weapon_ace_javelin"), "weapon_ace_javelin")
    expect.ne(TPG.Gear.Key("armor", 3), TPG.Gear.Key("weapon", 3))
end)

it("treats anything that is not armor as a weapon", function()
    expect.eq(TPG.Gear.Key("weapon", "x"), "x")
    expect.eq(TPG.Gear.Key(nil, "x"), "x")
    expect.eq(TPG.Gear.Key("something-else", "x"), "x")
end)

it("produces the same key from a numeric and a string armor id", function()
    -- Both realms build this key, and the client can arrive with either.
    expect.eq(TPG.Gear.Key("armor", 3), TPG.Gear.Key("armor", "3"))
end)

describe("gear: the price table")

it("prices everything it lists with a positive cost and cooldown", function()
    for class, entry in pairs(TPG.Gear.Weapons) do
        expect.eq(type(entry.cost), "number", class .. " cost")
        expect.eq(type(entry.cooldown), "number", class .. " cooldown")
        expect.truthy(entry.cost > 0, class .. " is listed with a zero cost; absent IS the free state")
        expect.truthy(entry.cooldown > 0, class .. " has no cooldown, so it is free in a normal round")
    end

    for id, entry in pairs(TPG.Gear.Armor) do
        expect.truthy(entry.cost > 0, "armor " .. id .. " cost")
        expect.truthy(entry.cooldown > 0, "armor " .. id .. " cooldown")
    end
end)

it("leaves the free anti-tank baseline unpriced", function()
    -- The whole gating scheme rests on every player being able to answer a tank
    -- for free, every life. If the AT-4 ever gets a price, that stops being true.
    expect.nils(TPG.Gear.Price("weapon", "weapon_ace_at4"),
        "the AT-4 is the deliberate free baseline")
end)

it("keeps nothing more expensive than a tank", function()
    -- Sized against a ~6,000-point modern tank: gear should never be the reason
    -- a player cannot field a vehicle.
    for class, entry in pairs(TPG.Gear.Weapons) do
        expect.truthy(entry.cost <= 2000, class .. " costs " .. entry.cost .. ", which rivals a vehicle")
    end
end)

it("keeps the two currencies roughly in step", function()
    -- Cost and cooldown are two prices for the same item, one paid under the
    -- economy and one under the team budget. They are hand-tuned rather than
    -- derived, so they are not strictly monotonic against each other -- but if
    -- an item's points-per-second drifts far outside the band the rest sit in,
    -- the two modes have started disagreeing about how strong it is.
    --
    -- The band brackets COST_PER_COOLDOWN_SEC = 3 in sh_gear.lua, which is the
    -- rate used to invent a cooldown for an admin-set cost.
    local LO, HI = 2.0, 4.2

    local function check(label, entry)
        local rate = entry.cost / entry.cooldown
        expect.truthy(rate >= LO and rate <= HI,
            string.format("%s is %.2f points per second of cooldown, outside %.1f-%.1f",
                label, rate, LO, HI))
    end

    for class, entry in pairs(TPG.Gear.Weapons) do check(class, entry) end
    for id, entry in pairs(TPG.Gear.Armor) do check("armor " .. id, entry) end

    expect.truthy(3 >= LO and 3 <= HI, "the derived rate should sit inside the band the data uses")
end)

describe("gear: Price")

it("returns nil for anything unlisted", function()
    expect.nils(TPG.Gear.Price("weapon", "weapon_ace_m16"))
    expect.nils(TPG.Gear.Price("weapon", "weapon_that_does_not_exist"))
    expect.nils(TPG.Gear.Price("armor", 0))
    expect.nils(TPG.Gear.Price("armor", 99))
end)

-- Price returns a COPY, not the config entry, so that defaulting `lives` on the
-- way out cannot write the default into the shared table. Every test below
-- compares fields for that reason; an identity check would be testing the thing
-- the copy exists to prevent.
local function samePrice(got, want, msg)
    expect.truthy(got, (msg or "price") .. ": nothing returned")
    expect.eq(got.cost, want.cost, (msg or "price") .. " cost")
    expect.eq(got.cooldown, want.cooldown, (msg or "price") .. " cooldown")
end

it("looks armor up in the gear table, not the tier table", function()
    -- TPG.Gear.Armor (prices) and TPG.Armor (stats) are different tables keyed
    -- the same way, and confusing them is easy.
    samePrice(TPG.Gear.Price("armor", 3), TPG.Gear.Armor[3])
    samePrice(TPG.Gear.Price("armor", "3"), TPG.Gear.Armor[3], "string ids must work too")
end)

it("returns the static baseline when no admin override is set", function()
    samePrice(TPG.Gear.Price("weapon", "weapon_ace_javelin"), TPG.Gear.Weapons["weapon_ace_javelin"])
end)

it("never hands out the config table itself", function()
    -- Writing to the returned table must not retune the item for everyone.
    local before = TPG.Gear.Weapons["weapon_ace_javelin"].cost
    local price = TPG.Gear.Price("weapon", "weapon_ace_javelin")
    price.cost = 1

    expect.eq(TPG.Gear.Weapons["weapon_ace_javelin"].cost, before,
        "Price handed back the live config entry")
end)

it("lets an admin cost override beat the baseline", function()
    local class = "weapon_ace_javelin"
    local saved = TPG.Weapons.Special[class]
    TPG.Weapons.Special[class] = { id = class, cost = 42, enabled = true }

    local price = TPG.Gear.Price("weapon", class)
    expect.eq(price.cost, 42, "the admin panel's cost should win outright")

    TPG.Weapons.Special[class] = saved
end)

it("borrows the baseline cooldown for an overridden cost", function()
    -- Discovery never populates entry.cooldown, so an admin who sets a cost in
    -- the weapon panel gets the static file's cooldown rather than none.
    local class = "weapon_ace_javelin"
    local saved = TPG.Weapons.Special[class]
    TPG.Weapons.Special[class] = { id = class, cost = 42, enabled = true }

    expect.eq(TPG.Gear.Price("weapon", class).cooldown,
        TPG.Gear.Weapons[class].cooldown)

    TPG.Weapons.Special[class] = saved
end)

it("derives a cooldown when there is no baseline to borrow", function()
    local class = "weapon_from_some_pack"
    local saved = TPG.Weapons.Primary[class]
    TPG.Weapons.Primary[class] = { id = class, cost = 300, enabled = true }

    local price = TPG.Gear.Price("weapon", class)
    expect.eq(price.cost, 300)
    expect.truthy(price.cooldown > 0,
        "an admin-priced weapon with no baseline still needs a cooldown, or gating it does nothing in a normal round")

    TPG.Weapons.Primary[class] = saved
end)

it("ignores a zero cost override", function()
    local class = "weapon_ace_javelin"
    local saved = TPG.Weapons.Special[class]
    TPG.Weapons.Special[class] = { id = class, cost = 0, enabled = true }

    samePrice(TPG.Gear.Price("weapon", class), TPG.Gear.Weapons[class],
        "cost 0 means 'no override set', not 'free'")

    TPG.Weapons.Special[class] = saved
end)

describe("gear: lives before the timer")

it("fills in the configured default for every priced item", function()
    -- Nothing ships an explicit `lives`, so every item should be reporting the
    -- global. A test that read the entry instead would pass even if the
    -- defaulting in Price stopped happening.
    local want = TPG.Config.gearCooldownLives
    expect.truthy(want and want > 0, "gearCooldownLives is what every item leans on")

    for class in pairs(TPG.Gear.Weapons) do
        expect.eq(TPG.Gear.Price("weapon", class).lives, want, class .. " lives")
    end
    for id in pairs(TPG.Gear.Armor) do
        expect.eq(TPG.Gear.Price("armor", id).lives, want, "armor " .. id .. " lives")
    end
end)

it("lets an item override the default", function()
    local class = "weapon_ace_javelin"
    local saved = TPG.Gear.Weapons[class].lives
    TPG.Gear.Weapons[class].lives = 2

    expect.eq(TPG.Gear.Price("weapon", class).lives, 2)

    TPG.Gear.Weapons[class].lives = saved
end)

it("moves every unopinionated item when the global changes", function()
    -- The reason lives is defaulted in Price rather than written into each
    -- entry: one knob has to be able to retune the whole file.
    local saved = TPG.Config.gearCooldownLives
    TPG.Config.gearCooldownLives = 3

    expect.eq(TPG.Gear.Price("weapon", "weapon_ace_javelin").lives, 3)
    expect.eq(TPG.Gear.Price("armor", 4).lives, 3)

    TPG.Config.gearCooldownLives = saved
end)

it("never reports a run shorter than one life", function()
    -- 0 lives would mean the timer starts before the player ever gets the item,
    -- which is a gate with no upside rather than a price.
    local saved = TPG.Config.gearCooldownLives

    for _, bad in ipairs({ 0, -5, 0.4 }) do
        TPG.Config.gearCooldownLives = bad
        expect.truthy(TPG.Gear.Price("weapon", "weapon_ace_javelin").lives >= 1,
            "a gearCooldownLives of " .. bad .. " produced a run nobody could use")
    end

    TPG.Config.gearCooldownLives = saved
end)

it("carries lives through an admin cost override", function()
    local class = "weapon_ace_javelin"
    local saved = TPG.Weapons.Special[class]
    TPG.Weapons.Special[class] = { id = class, cost = 42, enabled = true }

    expect.eq(TPG.Gear.Price("weapon", class).lives, TPG.Config.gearCooldownLives,
        "an overridden cost must not lose the run length")

    TPG.Weapons.Special[class] = saved
end)

describe("gear: Name")

it("names an armor tier from the tier table", function()
    expect.eq(TPG.Gear.Name("armor", 4), TPG.Armor[4].name)
    expect.eq(TPG.Gear.Name("armor", "4"), TPG.Armor[4].name)
end)

it("names a weapon from whichever slot holds it", function()
    local class = "weapon_test_named"
    TPG.Weapons.Special[class] = { id = class, name = "Test Launcher", enabled = true }

    expect.eq(TPG.Gear.Name("weapon", class), "Test Launcher")

    TPG.Weapons.Special[class] = nil
end)

it("falls back to the raw id for a weapon that is no longer installed", function()
    -- A saved loadout can outlive the pack it came from; this must not error.
    expect.eq(TPG.Gear.Name("weapon", "weapon_from_a_removed_pack"), "weapon_from_a_removed_pack")
end)

describe("gear: which price is in force")

it("follows the networked economy flag", function()
    SetGlobalBool("TPG_EconomyActive", true)
    expect.truthy(TPG.Gear.EconomyActive())

    SetGlobalBool("TPG_EconomyActive", false)
    expect.falsy(TPG.Gear.EconomyActive())
end)

it("defaults to the team-budget mode before anything sets the flag", function()
    expect.falsy(TPG.Gear.EconomyActive(),
        "an unset flag must not read as the economy being live")
end)
