--[[
    The loadout list is DISCOVERED from installed SWEPs rather than hardcoded,
    which is what lets a weapon pack work with no code change -- and also what
    makes it the one piece of shared code with real branching to get wrong. The
    stub lets us hand Discover() exactly the SWEPs a pack would register.
]]

local gmod = expect.load.gmod

local CATEGORIES = { "Primary", "Secondary", "Special" }

-- Register a fake SWEP the way a weapon pack would.
local function swep(class, fields)
    local s = {
        Base = "weapon_ace_base",
        Spawnable = true,
        Slot = 2,
        PrintName = class,
    }
    for k, v in pairs(fields or {}) do s[k] = v end
    weapons.Register(s, class)
    return s
end

local function discover()
    TPG.Weapons._state = nil
    TPG.Weapons.Discover()
end

describe("weapons: discovery basics")

it("always offers a free None in every slot", function()
    discover()
    for _, cat in ipairs(CATEGORIES) do
        local none = TPG.GetWeapon(cat, "none")
        expect.truthy(none, cat .. " has no None option")
        expect.eq(none.cost, 0)
        expect.truthy(none.enabled)
        expect.nils(none.class, "None must not resolve to a real weapon class")
    end
end)

it("makes None a speed bonus, not a penalty", function()
    discover()
    for _, cat in ipairs(CATEGORIES) do
        expect.truthy(TPG.GetWeapon(cat, "none").speedBonus >= 0,
            "carrying nothing in " .. cat .. " should not slow you down")
    end
end)

it("buckets a SWEP by its slot", function()
    swep("w_pistol", { Slot = 1 })
    swep("w_rifle",  { Slot = 2 })
    swep("w_sniper", { Slot = 3 })
    swep("w_tube",   { Slot = 4 })
    discover()

    expect.truthy(TPG.GetWeapon("Secondary", "w_pistol"), "slot 1 should be Secondary")
    expect.truthy(TPG.GetWeapon("Primary", "w_rifle"), "slot 2 should be Primary")
    expect.truthy(TPG.GetWeapon("Primary", "w_sniper"), "slot 3 should be Primary")
    expect.truthy(TPG.GetWeapon("Special", "w_tube"), "slot 4 should be Special")
end)

it("ignores a SWEP whose base is not allowed", function()
    swep("w_foreign", { Base = "weapon_base" })
    discover()

    for _, cat in ipairs(CATEGORIES) do
        expect.nils(TPG.GetWeapon(cat, "w_foreign"))
    end
end)

it("ignores a SWEP that is not spawnable", function()
    swep("w_hidden", { Spawnable = false })
    discover()
    expect.nils(TPG.GetWeapon("Primary", "w_hidden"))
end)

it("drops a SWEP whose slot maps to nothing", function()
    -- Filed under something wrong is worse than absent, so discovery drops it.
    swep("w_odd", { Slot = 9 })
    discover()
    for _, cat in ipairs(CATEGORIES) do
        expect.nils(TPG.GetWeapon(cat, "w_odd"))
    end
end)

it("rebuilds from scratch, so an uninstalled pack disappears", function()
    swep("w_temp")
    discover()
    expect.truthy(TPG.GetWeapon("Primary", "w_temp"))

    gmod.sweps = {}
    discover()
    expect.nils(TPG.GetWeapon("Primary", "w_temp"), "a rediscovery must not keep stale entries")
end)

describe("weapons: exclusion")

it("hides an explicitly excluded class", function()
    swep("weapon_ace_antipersonmine", { Slot = 4 })
    swep("disposableat", { Slot = 4 })
    discover()

    expect.nils(TPG.GetWeapon("Special", "weapon_ace_antipersonmine"),
        "the ACE mines are bundled into the virtual Mines entry")
    expect.nils(TPG.GetWeapon("Special", "disposableat"),
        "the disposable tube is a consolation prize, never a menu pick")
end)

it("hides a pack's own mines by subcategory", function()
    -- Pack mines are classed weapon_ace_PMN / TM62 / VS50, which no name pattern
    -- catches; the SubCategory is the reliable signal.
    swep("weapon_ace_pmn", { Slot = 4, SubCategory = "Mines" })
    discover()
    expect.nils(TPG.GetWeapon("Special", "weapon_ace_pmn"))
end)

it("matches the mine subcategory however the pack spells it", function()
    swep("w_mine_a", { Slot = 4, SubCategory = "Mines" })
    swep("w_mine_b", { Slot = 4, SubCategory = "mine" })
    swep("w_mine_c", { Slot = 4, SubCategory = "MINES" })
    discover()

    for _, class in ipairs({ "w_mine_a", "w_mine_b", "w_mine_c" }) do
        expect.nils(TPG.GetWeapon("Special", class), class .. " slipped through the mine filter")
    end
end)

it("hides dev and test junk by class-name pattern", function()
    swep("weapon_ace_modtest")
    swep("weapon_ace_sometest")
    discover()

    expect.nils(TPG.GetWeapon("Primary", "weapon_ace_modtest"))
    expect.nils(TPG.GetWeapon("Primary", "weapon_ace_sometest"))
end)

it("keeps the mine detector, which only ends in 'detector'", function()
    -- The mine pattern is anchored at the end for exactly this reason.
    swep("weapon_ace_minedetector", { Slot = 1 })
    discover()
    expect.truthy(TPG.GetWeapon("Secondary", "weapon_ace_minedetector"),
        "weapon_ace_minedetector is not a mine and must survive the filter")
end)

describe("weapons: overrides")

it("forces a category, overruling the SWEP's slot", function()
    -- ACE files its guided launchers under the sniper slot, so without this a
    -- player could carry a Javelin AS a rifle and still take an AT-4 on top.
    swep("weapon_ace_javelin", { Slot = 3 })
    discover()

    expect.truthy(TPG.GetWeapon("Special", "weapon_ace_javelin"), "should be forced into Special")
    expect.nils(TPG.GetWeapon("Primary", "weapon_ace_javelin"))
end)

it("repairs a realm split, which is the reason category overrides exist", function()
    -- A SWEP may declare Slot inside `if CLIENT then`, so the two realms see
    -- different slots. The override is shared code, so both land in one bucket.
    swep("weapon_ace_slam", { Slot = 2 })   -- what the SERVER sees
    discover()
    local asServer = TPG.GetWeapon("Special", "weapon_ace_slam")

    gmod.sweps = {}
    swep("weapon_ace_slam", { Slot = 4 })   -- what the CLIENT sees
    discover()
    local asClient = TPG.GetWeapon("Special", "weapon_ace_slam")

    expect.truthy(asServer, "server realm put S.L.A.M. somewhere else")
    expect.truthy(asClient, "client realm put S.L.A.M. somewhere else")
end)

it("overrides the display name for a client-only PrintName", function()
    swep("weapon_ace_slam", { Slot = 4, PrintName = "ACE Base Weapon" })
    discover()
    expect.eq(TPG.GetWeapon("Special", "weapon_ace_slam").name, "Mine-S.L.A.M.")
end)

it("overrides the speed penalty for heavy weapons", function()
    swep("weapon_ace_m249saw", { Slot = 2 })
    swep("w_ordinary_rifle", { Slot = 2 })
    discover()

    local heavy    = TPG.GetWeapon("Primary", "weapon_ace_m249saw")
    local ordinary = TPG.GetWeapon("Primary", "w_ordinary_rifle")

    expect.eq(heavy.speedBonus, -15)
    expect.truthy(heavy.speedBonus < ordinary.speedBonus, "an LMG should be slower than a rifle")
end)

it("falls back to the category default speed", function()
    swep("w_plain", { Slot = 2 })
    discover()
    expect.eq(TPG.GetWeapon("Primary", "w_plain").speedBonus,
        TPG.WeaponConfig.DefaultSpeed.Primary)
end)

describe("weapons: menu tabs")

it("collapses spelling variants onto one tab", function()
    swep("w_smg_a", { Slot = 2, SubCategory = "Submachine Guns" })
    swep("w_smg_b", { Slot = 2, SubCategory = "sub-machine guns" })
    swep("w_smg_c", { Slot = 2, SubCategory = "SUBMACHINE GUN" })
    discover()

    for _, class in ipairs({ "w_smg_a", "w_smg_b", "w_smg_c" }) do
        expect.eq(TPG.GetWeapon("Primary", class).subCategory, "Submachine Guns",
            class .. " landed on its own tab")
    end
end)

it("gives an unrecognised subcategory no tab at all", function()
    -- A closed list, deliberately: letting packs name their own tabs is how the
    -- strip filled up with near-duplicates.
    swep("w_weird", { Slot = 2, SubCategory = "Blasters Of Doom" })
    discover()
    expect.nils(TPG.GetWeapon("Primary", "w_weird").subCategory)
end)

it("gives a weapon with no subcategory no tab", function()
    swep("w_bare", { Slot = 2 })
    discover()
    expect.nils(TPG.GetWeapon("Primary", "w_bare").subCategory)
end)

it("lets an override place a weapon ACE filed under its catch-all", function()
    swep("weapon_ace_at4", { Slot = 4, SubCategory = "Special" })
    discover()
    expect.eq(TPG.GetWeapon("Special", "weapon_ace_at4").subCategory, "Anti-Tank")
end)

describe("weapons: ammo counts")

it("reports the reserve the player will actually get", function()
    swep("weapon_ace_at4", { Slot = 4, SubCategory = "Special",
        Primary = { ClipSize = 1, DefaultClip = 1 } })
    discover()
    expect.eq(TPG.GetWeapon("Special", "weapon_ace_at4").rounds,
        TPG.WeaponConfig.AmmoTopUp["weapon_ace_at4"],
        "a DefaultClip of 1 is topped up before the player sees it")
end)

it("applies the Special-slot floor to a pack launcher with no entry of its own", function()
    swep("w_pack_launcher", { Slot = 4, Primary = { ClipSize = 1, DefaultClip = 1 } })
    discover()
    expect.eq(TPG.GetWeapon("Special", "w_pack_launcher").rounds,
        TPG.WeaponConfig.SpecialAmmoMin)
end)

it("leaves a weapon already above the floor alone", function()
    swep("w_big_mag", { Slot = 4, Primary = { ClipSize = 12, DefaultClip = 30 } })
    discover()
    expect.eq(TPG.GetWeapon("Special", "w_big_mag").rounds, 30)
end)

it("reports nil, not zero, for something that does not use ammo", function()
    -- ClipSize -1 is ACE's marker for tools and melee; printing "0 rounds"
    -- would be a lie.
    swep("w_tool", { Slot = 1, Primary = { ClipSize = -1, DefaultClip = 0 } })
    discover()
    expect.nils(TPG.GetWeapon("Secondary", "w_tool").rounds)
end)

describe("weapons: virtual entries")

it("adds the bundled mines entry even with no SWEPs installed", function()
    discover()
    local mines = TPG.GetWeapon("Special", "ace_mines")
    expect.truthy(mines, "the virtual Mines entry should always exist")
    expect.eq(mines.base, "virtual")
    expect.eq(#mines.multipleClasses, 3, "the set is supposed to be three SWEPs")
end)

it("treats the virtual entry's ammo as an exact total, not a floor", function()
    discover()
    local mines = TPG.GetWeapon("Special", "ace_mines")
    expect.eq(mines.exactAmmo, 19)
    expect.eq(mines.rounds, mines.exactAmmo,
        "the three mine SWEPs share one ammo pool, so this is a total")
end)

it("excludes the virtual pseudo-base from the admin panel's base list", function()
    swep("w_real", { Slot = 2 })
    discover()

    local bases = TPG.Weapons.GetDiscoveredBases()
    expect.truthy(bases["weapon_ace_base"], "a real base should be listed")
    expect.nils(bases["virtual"], "there is no SWEP behind the virtual base to toggle")
end)

describe("weapons: admin state")

it("hides every weapon of a disabled base", function()
    swep("w_a", { Slot = 2 })
    swep("w_b", { Slot = 1 })
    discover()

    TPG.Weapons.ApplyState({ bases = { weapon_ace_base = false } })

    expect.falsy(TPG.GetWeapon("Primary", "w_a").enabled)
    expect.falsy(TPG.GetWeapon("Secondary", "w_b").enabled)
end)

it("lets a per-weapon toggle beat its base being off", function()
    swep("w_a", { Slot = 2 })
    swep("w_b", { Slot = 2 })
    discover()

    TPG.Weapons.ApplyState({
        bases   = { weapon_ace_base = false },
        weapons = { w_a = true },
    })

    expect.truthy(TPG.GetWeapon("Primary", "w_a").enabled, "an explicit re-enable should win")
    expect.falsy(TPG.GetWeapon("Primary", "w_b").enabled)
end)

it("never disables None", function()
    discover()
    TPG.Weapons.ApplyState({
        bases   = { weapon_ace_base = false },
        weapons = { none = false },
    })

    for _, cat in ipairs(CATEGORIES) do
        expect.truthy(TPG.GetWeapon(cat, "none").enabled, cat .. "'s None got disabled")
        expect.eq(TPG.GetWeapon(cat, "none").cost, 0)
    end
end)

it("applies field overrides", function()
    swep("w_a", { Slot = 2 })
    discover()

    TPG.Weapons.ApplyState({ overrides = { w_a = { cost = 500, speedBonus = -3, name = "Renamed" } } })

    local entry = TPG.GetWeapon("Primary", "w_a")
    expect.eq(entry.cost, 500)
    expect.eq(entry.speedBonus, -3)
    expect.eq(entry.name, "Renamed")
end)

it("ignores an empty name override", function()
    swep("w_a", { Slot = 2, PrintName = "Original" })
    discover()

    TPG.Weapons.ApplyState({ overrides = { w_a = { name = "" } } })
    expect.eq(TPG.GetWeapon("Primary", "w_a").name, "Original")
end)

it("survives a rediscovery", function()
    -- Late-mounting content triggers a rebuild; admin choices must not be lost.
    swep("w_a", { Slot = 2 })
    discover()
    TPG.Weapons.ApplyState({ weapons = { w_a = false } })

    TPG.Weapons.Discover()

    expect.falsy(TPG.GetWeapon("Primary", "w_a").enabled,
        "the admin disable was dropped by the rebuild")
end)

it("does nothing at all when given no state", function()
    swep("w_a", { Slot = 2 })
    discover()
    TPG.Weapons.ApplyState(nil)
    expect.truthy(TPG.GetWeapon("Primary", "w_a").enabled)
end)

describe("weapons: the public lookups")

it("returns nil for an unknown category or id, with no fallback", function()
    discover()
    expect.nils(TPG.GetWeapon("Tertiary", "none"))
    expect.nils(TPG.GetWeapon("Primary", "w_nope"))
    expect.nils(TPG.GetWeaponClass("Primary", "w_nope"))
end)

it("gives no class for None or for a multi-class virtual entry", function()
    discover()
    expect.nils(TPG.GetWeaponClass("Primary", "none"))
    expect.nils(TPG.GetWeaponClass("Special", "ace_mines"),
        "the mines entry has multipleClasses, not one class")
end)

it("sorts the list by name with None always first", function()
    swep("w_zulu", { Slot = 2, PrintName = "Zulu" })
    swep("w_alpha", { Slot = 2, PrintName = "Alpha" })
    swep("w_mike", { Slot = 2, PrintName = "Mike" })
    discover()

    local list = TPG.GetWeaponList("Primary")
    expect.eq(list[1].id, "none")
    expect.eq(list[2].name, "Alpha")
    expect.eq(list[3].name, "Mike")
    expect.eq(list[4].name, "Zulu")
end)

it("leaves disabled weapons out unless asked for them", function()
    swep("w_a", { Slot = 2 })
    discover()
    TPG.Weapons.ApplyState({ weapons = { w_a = false } })

    local visible = TPG.GetWeaponList("Primary")
    local all     = TPG.GetWeaponList("Primary", true)

    expect.eq(#visible, 1, "only None should be visible")
    expect.eq(#all, 2)
end)

it("returns an empty list for an unknown category", function()
    discover()
    expect.eq(#TPG.GetWeaponList("Nonsense"), 0)
end)

describe("weapons: the loadout speed sum")

it("adds up all three slots", function()
    swep("w_rifle", { Slot = 2 })
    swep("w_pistol", { Slot = 1 })
    discover()

    local expected = TPG.GetWeapon("Primary", "w_rifle").speedBonus
                   + TPG.GetWeapon("Secondary", "w_pistol").speedBonus
                   + TPG.GetWeapon("Special", "none").speedBonus

    expect.eq(TPG.CalculateSpeedBonus("w_rifle", "w_pistol", "none"), expected)
end)

it("counts an unresolvable id as zero rather than erroring", function()
    -- A saved loadout can name a weapon from a pack that has since been
    -- removed; that shows up as a speed discrepancy, not a crash.
    discover()
    expect.eq(TPG.CalculateSpeedBonus("gone", "gone", "gone"), 0)
    expect.eq(TPG.CalculateSpeedBonus(nil, nil, nil), 0)
end)

describe("weapons: the config table's internal consistency")

it("only ever names a tab that exists", function()
    local tabs = {}
    for _, name in ipairs(TPG.WeaponConfig.SubCategoryTabs) do tabs[name] = true end

    for raw, target in pairs(TPG.WeaponConfig.SubCategoryAlias) do
        if target ~= false then
            expect.truthy(tabs[target],
                "alias " .. raw .. " points at '" .. tostring(target) .. "', which is not a tab")
        end
    end

    for class, ov in pairs(TPG.WeaponConfig.Overrides) do
        if ov.subCategory then
            expect.truthy(tabs[ov.subCategory],
                class .. " overrides subCategory to '" .. ov.subCategory .. "', which is not a tab")
        end
    end

    for _, entries in pairs(TPG.WeaponConfig.Virtual) do
        for id, data in pairs(entries) do
            if data.subCategory then
                expect.truthy(tabs[data.subCategory],
                    "virtual entry " .. id .. " names a tab that does not exist")
            end
        end
    end
end)

it("writes every alias key in the normalised form it will be looked up by", function()
    -- Matching happens on the lowercased, punctuation-stripped, de-pluralised
    -- form. An alias key that is not already in that shape can never match.
    for raw in pairs(TPG.WeaponConfig.SubCategoryAlias) do
        local normalised = raw:lower():gsub("[^%a%d]", ""):gsub("s$", "")
        expect.eq(raw, normalised,
            "alias key '" .. raw .. "' is not in normalised form and will never match")
    end

    for raw in pairs(TPG.WeaponConfig.ExcludeSubCategories) do
        local normalised = raw:lower():gsub("[^%a%d]", ""):gsub("s$", "")
        expect.eq(raw, normalised,
            "exclude key '" .. raw .. "' is not in normalised form")
    end
end)

it("only ever names a real category", function()
    local valid = { Primary = true, Secondary = true, Special = true }

    for slot, cat in pairs(TPG.WeaponConfig.SlotCategory) do
        expect.truthy(valid[cat], "slot " .. slot .. " maps to unknown category " .. tostring(cat))
    end
    for class, ov in pairs(TPG.WeaponConfig.Overrides) do
        if ov.category then
            expect.truthy(valid[ov.category], class .. " forces unknown category " .. tostring(ov.category))
        end
    end
    for cat in pairs(TPG.WeaponConfig.Virtual) do
        expect.truthy(valid[cat], "virtual entries under unknown category " .. tostring(cat))
    end
    for cat in pairs(TPG.WeaponConfig.DefaultSpeed) do
        expect.truthy(valid[cat], "DefaultSpeed names unknown category " .. tostring(cat))
    end
    for cat in pairs(TPG.WeaponConfig.NoneSpeed) do
        expect.truthy(valid[cat], "NoneSpeed names unknown category " .. tostring(cat))
    end
end)

it("gives every category a default and a None speed", function()
    for _, cat in ipairs(CATEGORIES) do
        expect.eq(type(TPG.WeaponConfig.DefaultSpeed[cat]), "number", cat .. " DefaultSpeed")
        expect.eq(type(TPG.WeaponConfig.NoneSpeed[cat]), "number", cat .. " NoneSpeed")
    end
end)

it("uses exclude patterns that are valid Lua patterns", function()
    for _, pat in ipairs(TPG.WeaponConfig.ExcludePatterns) do
        local ok = pcall(string.find, "sample_class_name", pat)
        expect.truthy(ok, "invalid Lua pattern in ExcludePatterns: " .. tostring(pat))
    end
end)

it("names a default loadout slot for every category", function()
    for _, cat in ipairs(CATEGORIES) do
        local id = TPG.WeaponConfig.DefaultLoadout[cat]
        expect.eq(type(id), "string", "DefaultLoadout." .. cat)
        expect.truthy(#id > 0)
    end
end)

it("does not both exclude a class and give it an override", function()
    for class in pairs(TPG.WeaponConfig.Exclude) do
        local ov = TPG.WeaponConfig.Overrides[class]
        expect.nils(ov, class .. " is excluded, so its override can never take effect")
    end
end)

it("prices no weapon it also excludes from the menu", function()
    for class in pairs(TPG.Gear.Weapons) do
        expect.nils(TPG.WeaponConfig.Exclude[class],
            class .. " has a gear price but is excluded from the loadout menu")
    end
end)
