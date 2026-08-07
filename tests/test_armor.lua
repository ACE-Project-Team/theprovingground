describe("armor: the tier table")

it("defines every tier with the fields the game reads off it", function()
    for id = 0, 4 do
        local tier = TPG.Armor[id]
        expect.truthy(tier, "no armor tier " .. id)
        expect.eq(tier.id, id, "tier " .. id .. " repeats its key wrong")
        expect.eq(type(tier.name), "string", "tier " .. id .. " name")
        expect.eq(type(tier.health), "number", "tier " .. id .. " health")
        expect.eq(type(tier.armor), "number", "tier " .. id .. " armor")
        expect.eq(type(tier.speedBonus), "number", "tier " .. id .. " speedBonus")
        expect.eq(type(tier.model), "string", "tier " .. id .. " model")
        expect.eq(type(tier.canUseSeat), "boolean", "tier " .. id .. " canUseSeat")
    end
end)

it("has no tiers beyond the five", function()
    expect.eq(table.Count(TPG.Armor), 5)
end)

it("gets tougher and slower as the id climbs", function()
    for id = 1, 4 do
        expect.truthy(TPG.Armor[id].health >= TPG.Armor[id - 1].health,
            "tier " .. id .. " should not have less health than " .. (id - 1))
        expect.truthy(TPG.Armor[id].speedBonus <= TPG.Armor[id - 1].speedBonus,
            "tier " .. id .. " should not be faster than " .. (id - 1))
    end
end)

it("locks only the Juggernaut out of vehicle seats", function()
    for id = 0, 3 do
        expect.truthy(TPG.Armor[id].canUseSeat, "tier " .. id .. " should fit a seat")
    end
    expect.falsy(TPG.Armor[4].canUseSeat,
        "taking the heaviest tier is supposed to cost you crew slots")
end)

describe("armor: the lookup")

it("falls back to Light, not None", function()
    -- Worth pinning: a nil armorId does NOT come back unarmoured, it comes back
    -- as the cheapest actually-armoured tier, and spawn code depends on that.
    expect.eq(TPG.GetArmor(nil), TPG.Armor[1])
    expect.eq(TPG.GetArmor(99), TPG.Armor[1])
    expect.eq(TPG.GetArmor("nonsense"), TPG.Armor[1])
end)

it("returns the real tier for a real id", function()
    for id = 0, 4 do
        expect.eq(TPG.GetArmor(id), TPG.Armor[id])
    end
end)

it("does not treat id 0 as missing", function()
    -- 0 is falsy in plenty of languages but not in Lua; a regression to
    -- `TPG.Armor[armorId or 1]` would still pass, one to a truthiness test
    -- would not.
    expect.eq(TPG.GetArmor(0).name, "None")
end)

describe("armor: models")

-- Which tiers use a %d placeholder is a property of the data, not something
-- to hardcode here: it was None only, and is now None and Light.
local function usesPlaceholder(id)
    return TPG.Armor[id].model:find("%%d") ~= nil
end

it("has at least one randomised and one fixed model", function()
    local randomised, fixed = 0, 0
    for id = 0, 4 do
        if usesPlaceholder(id) then randomised = randomised + 1 else fixed = fixed + 1 end
    end
    expect.truthy(randomised > 0, "no tier uses a %d placeholder; the rest of this suite is moot")
    expect.truthy(fixed > 0, "no tier uses a fixed model path")
end)

it("resolves every placeholder to a real filename", function()
    for id = 0, 4 do
        if usesPlaceholder(id) then
            for _ = 1, 25 do
                local model = TPG.GetArmorModel(id)
                expect.falsy(model:find("%%d"), "tier " .. id .. " left a placeholder: " .. model)
                expect.truthy(model:match("Male_0%d%.mdl$"),
                    "tier " .. id .. " produced an unexpected path: " .. model)
            end
        end
    end
end)

it("picks a different variant across repeated calls", function()
    -- Documented behaviour: calling twice for the same armor can return
    -- different models. A regression to picking once at load would still
    -- resolve the placeholder, but every player would look identical.
    local id
    for i = 0, 4 do if usesPlaceholder(i) then id = i break end end

    local seen = {}
    for _ = 1, 200 do seen[TPG.GetArmorModel(id)] = true end
    expect.truthy(table.Count(seen) > 1, "the model choice never varied over 200 calls")
end)

it("returns fixed model paths unchanged", function()
    for id = 0, 4 do
        if not usesPlaceholder(id) then
            expect.eq(TPG.GetArmorModel(id), TPG.Armor[id].model)
        end
    end
end)

describe("armor: the menu list")

it("lists every tier, ascending by id", function()
    local list = TPG.GetArmorList()
    expect.eq(#list, 5)
    for i, entry in ipairs(list) do
        expect.eq(entry.id, i - 1, "list is not id-sorted")
        expect.eq(entry.name, TPG.Armor[entry.id].name)
    end
end)

describe("armor: how it lines up with the gear prices")

it("prices only Heavy and Juggernaut", function()
    for id = 0, 2 do
        expect.nils(TPG.Gear.Price("armor", id),
            TPG.Armor[id].name .. " is supposed to be free")
    end
    for id = 3, 4 do
        expect.truthy(TPG.Gear.Price("armor", id),
            TPG.Armor[id].name .. " is supposed to be priced")
    end
end)

it("keeps the denied-pick fallback a free tier", function()
    -- FreeArmor is what a player drops to when a premium pick is refused, so
    -- it must not itself be something they have to pay for.
    local free = TPG.Gear.FreeArmor
    expect.truthy(TPG.Armor[free], "FreeArmor points at a tier that does not exist")
    expect.nils(TPG.Gear.Price("armor", free), "the fallback armor is not free")
end)

it("makes the fallback the best free tier", function()
    local best = -1
    for id, tier in pairs(TPG.Armor) do
        if not TPG.Gear.Price("armor", id) and tier.armor >= (TPG.Armor[best] and TPG.Armor[best].armor or -1) then
            best = id
        end
    end
    expect.eq(TPG.Gear.FreeArmor, best,
        "a denied premium pick should leave the player with the best free tier")
end)

it("prices every armor id that actually exists", function()
    for id in pairs(TPG.Gear.Armor) do
        expect.truthy(TPG.Armor[id], "gear prices armor id " .. tostring(id) .. ", which has no tier")
    end
end)
