--[[
    Weapon Discovery Engine

    Builds TPG.Weapons.{Primary,Secondary,Special} at runtime from installed
    SWEPs (see sh_weapons_config.lua for what gets included). Replaces the old
    hardcoded list, so any ACE-based weapon pack is supported with no code edits.

    Entries are keyed by weapon CLASS (or a virtual sentinel), so saved loadouts
    survive list changes. Public API (GetWeapon / GetWeaponList /
    CalculateSpeedBonus) is unchanged, but ids are now strings instead of ints.
]]

TPG.Weapons = TPG.Weapons or {}

local CATEGORIES = { "Primary", "Secondary", "Special" }

-- Admin-set enable/override state (from data/tpg/weapons.json), applied on top
-- of discovery. Kept so a re-discover (late-mounted content) re-applies it.
TPG.Weapons._state = TPG.Weapons._state or nil

--[[
    How many rounds the player will actually walk away with.

    Mirrors TopUpAmmo in player/sv_loadout.lua: ply:Give hands over DefaultClip
    rounds in total, and the loadout then raises that to the per-class top-up or
    the Special-slot floor if either is higher. Computed once at discovery so
    the menu can print it without re-deriving the rule (and without touching a
    SWEP table every frame).

    nil means "this doesn't consume ammo" -- ClipSize -1 is ACE's marker for
    tools and melee, and printing "0 rounds" on those would be a lie.
]]
local function roundsFor(cfg, swep, class, category)
    local primary = swep and swep.Primary
    if not primary then return nil end
    if (primary.ClipSize or -1) < 0 then return nil end

    local rounds = math.max(primary.DefaultClip or 0, 0)

    local target = cfg.AmmoTopUp and cfg.AmmoTopUp[class]
    if not target and category == "Special" then target = cfg.SpecialAmmoMin end
    if target then rounds = math.max(rounds, target) end

    if rounds <= 0 then return nil end
    return rounds
end

--[[
    Which menu tab this weapon belongs under.

    An explicit override wins; otherwise the SWEP's own SubCategory is run
    through SubCategoryAlias, which merges packs' near-duplicate names and drops
    the ones that aren't a weapon class at all. A `false` alias means "no tab" --
    distinct from "no alias entry", which passes the raw string straight
    through, so an unknown pack still gets sensible grouping for free.
]]
local function subCategoryFor(cfg, swep, override)
    if override.subCategory ~= nil then return override.subCategory or nil end

    local raw = swep and swep.SubCategory
    if not raw then return nil end

    local alias = cfg.SubCategoryAlias and cfg.SubCategoryAlias[raw]
    if alias == false then return nil end
    return alias or raw
end

local function passesExclude(cfg, swep, class)
    if cfg.Exclude[class] then return false end

    -- SubCategory is the reliable signal: ACE and its packs tag every SWEP with
    -- one, and it doesn't depend on the class name happening to contain a word.
    -- The pack mines are classed weapon_ace_PMN / TM62 / VS50, which no sane
    -- name pattern catches, but all three declare SubCategory "Mines".
    local sub = swep.SubCategory
    if sub and cfg.ExcludeSubCategories and cfg.ExcludeSubCategories[sub] then
        return false
    end

    local lc = string.lower(class)
    for _, pat in ipairs(cfg.ExcludePatterns or {}) do
        if string.find(lc, pat) then return false end
    end
    return true
end

function TPG.Weapons.Discover()
    local cfg = TPG.WeaponConfig
    if not cfg then return end

    local buckets = { Primary = {}, Secondary = {}, Special = {} }

    -- "None" option per category.
    for _, cat in ipairs(CATEGORIES) do
        buckets[cat]["none"] = {
            id = "none", name = "None", class = nil,
            speedBonus = cfg.NoneSpeed[cat] or 0, cost = 0,
            base = nil, enabled = true,
        }
    end

    -- Discover installed SWEPs.
    for _, swep in ipairs(weapons.GetList()) do
        local class = swep.ClassName
        if not class or not swep.Spawnable then continue end

        local base = swep.Base
        if not (base and cfg.Bases[base]) then continue end
        if not passesExclude(cfg, swep, class) then continue end

        local override = cfg.Overrides[class] or {}
        local cat = override.category or cfg.SlotCategory[swep.Slot or -1]
        if not cat or not buckets[cat] then continue end

        buckets[cat][class] = {
            id = class,
            name = override.name or swep.PrintName or class,
            class = class,
            speedBonus = override.speedBonus or cfg.DefaultSpeed[cat] or 0,
            cost = override.cost or 0,
            base = base,
            -- Shared, unlike PrintName and Slot on some SWEPs, so both realms
            -- agree on it. The menu groups by this so a forty-weapon Primary
            -- list becomes "Assault Rifles / SMGs / Shotguns / ...".
            subCategory = subCategoryFor(cfg, swep, override),
            rounds = roundsFor(cfg, swep, class, cat),
            enabled = true,
        }
    end

    -- Virtual entries (multi-class / fallback).
    for cat, entries in pairs(cfg.Virtual or {}) do
        if buckets[cat] then
            for id, data in pairs(entries) do
                buckets[cat][id] = {
                    id = id,
                    name = data.name or id,
                    class = data.class,
                    multipleClasses = data.multipleClasses,
                    fallbackClass = data.fallbackClass,
                    speedBonus = data.speedBonus or cfg.DefaultSpeed[cat] or 0,
                    cost = data.cost or 0,
                    base = "virtual",
                    subCategory = data.subCategory,
                    -- exactAmmo is a hard total, not a floor: see the mines
                    -- entry in sh_weapons_config.lua for why they need one.
                    exactAmmo = data.exactAmmo,
                    rounds = data.exactAmmo,
                    enabled = true,
                }
            end
        end
    end

    TPG.Weapons.Primary   = buckets.Primary
    TPG.Weapons.Secondary = buckets.Secondary
    TPG.Weapons.Special   = buckets.Special
    TPG.Weapons.Default   = cfg.AlwaysGive
    TPG.Weapons.TeamTools = cfg.TeamTools

    -- Re-apply admin state (enable flags / overrides) after a rebuild.
    if TPG.Weapons._state then
        TPG.Weapons.ApplyState(TPG.Weapons._state)
    end
end

-- Apply admin enable/override state. Shape:
--   { bases = { [base]=bool }, weapons = { [id]=bool }, overrides = { [id]={...} } }
function TPG.Weapons.ApplyState(state)
    if not state then return end
    TPG.Weapons._state = state

    for _, cat in ipairs(CATEGORIES) do
        for id, entry in pairs(TPG.Weapons[cat] or {}) do
            if id ~= "none" then
                -- Base toggle (a disabled base hides all its weapons)...
                if entry.base and state.bases and state.bases[entry.base] == false then
                    entry.enabled = false
                else
                    entry.enabled = true
                end
                -- ...overridden by an explicit per-weapon toggle.
                if state.weapons and state.weapons[id] ~= nil then
                    entry.enabled = state.weapons[id]
                end
                -- Field overrides.
                local ov = state.overrides and state.overrides[id]
                if ov then
                    if ov.speedBonus ~= nil then entry.speedBonus = ov.speedBonus end
                    if ov.cost ~= nil then entry.cost = ov.cost end
                    if ov.name ~= nil and ov.name ~= "" then entry.name = ov.name end
                end
            end
        end
    end
end

-- Set of SWEP bases actually present (for the admin panel's base toggles).
function TPG.Weapons.GetDiscoveredBases()
    local bases = {}
    for _, cat in ipairs(CATEGORIES) do
        for _, entry in pairs(TPG.Weapons[cat] or {}) do
            if entry.base and entry.base ~= "virtual" then
                bases[entry.base] = true
            end
        end
    end
    return bases
end

-- ── Public API (unchanged signatures; ids are now strings) ─────────────────
function TPG.GetWeapon(category, id)
    local cat = TPG.Weapons[category]
    if not cat then return nil end
    return cat[id]
end

function TPG.GetWeaponClass(category, id)
    local weapon = TPG.GetWeapon(category, id)
    return weapon and weapon.class
end

-- Returns only ENABLED entries, sorted by name ("None" first).
function TPG.GetWeaponList(category, includeDisabled)
    local cat = TPG.Weapons[category]
    if not cat then return {} end

    local list = {}
    for id, data in pairs(cat) do
        if includeDisabled or data.enabled then
            list[#list + 1] = { id = id, name = data.name, cost = data.cost, enabled = data.enabled }
        end
    end

    table.sort(list, function(a, b)
        if a.id == "none" then return true end
        if b.id == "none" then return false end
        return a.name < b.name
    end)
    return list
end

function TPG.CalculateSpeedBonus(primaryId, secondaryId, specialId)
    local bonus = 0
    local primary   = TPG.GetWeapon("Primary", primaryId)
    local secondary = TPG.GetWeapon("Secondary", secondaryId)
    local special   = TPG.GetWeapon("Special", specialId)

    if primary   then bonus = bonus + (primary.speedBonus or 0)   end
    if secondary then bonus = bonus + (secondary.speedBonus or 0) end
    if special   then bonus = bonus + (special.speedBonus or 0)   end
    return bonus
end

-- Build now, and again once everything (incl. late-mounted content) is loaded.
TPG.Weapons.Discover()
hook.Add("InitPostEntity", "TPG_DiscoverWeapons", TPG.Weapons.Discover)
concommand.Add("tpg_weapons_refresh", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    TPG.Weapons.Discover()
end)
