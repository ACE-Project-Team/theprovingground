--[[--
    Builds the weapon lists by scanning installed SWEPs, instead of a hardcoded table.

    `TPG.Weapons.Discover()` populates `TPG.Weapons.{Primary,Secondary,Special}`
    at runtime from every currently-registered SWEP whose `Base` and category
    pass the rules in `config/sh_weapons_config.lua` (`TPG.WeaponConfig`), so
    any ACE-based weapon pack is supported with no code edits here -- installing
    a pack is enough.

    Entries are keyed by weapon CLASS (or a virtual sentinel like `"none"`),
    not by an integer index, so a saved loadout referencing a class survives a
    later re-discovery even if the list has reordered or grown. The public API
    (@{TPG.GetWeapon}, @{TPG.GetWeaponList}, @{TPG.CalculateSpeedBonus}) is
    unchanged from the old hardcoded-list version, but ids are strings now
    rather than ints.

    Discovery runs once at load, and again on `InitPostEntity` to pick up
    content that mounts late; admins can also force it via the
    `tpg_weapons_refresh` concommand (superadmin only). Every re-discovery
    rebuilds the buckets from scratch and then re-applies any admin state
    (`TPG.Weapons.ApplyState`) that was previously loaded, so enable flags and
    per-weapon overrides survive a rebuild.

    @module tpg.weapons
    @realm shared
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
    Fold a pack's SubCategory string down to something matchable.

    Lowercased, everything that isn't a letter or a digit removed, and a
    trailing plural "s" dropped. That is what makes "Submachine Guns",
    "sub-machine guns" and "Submachine Gun" one key instead of three tabs, and
    it's why SubCategoryAlias is written in that flattened form.
]]
local function normalise(raw)
    local s = string.gsub(string.lower(raw), "[^%a%d]", "")
    return (string.gsub(s, "s$", ""))
end

-- Raw SubCategory strings seen this discovery that aren't in the alias table.
-- Reported once, at the end of Discover, so adding a new pack's categories is a
-- deliberate edit rather than a guess.
local unknownSubCategories

--[[
    Which menu tab this weapon belongs under, or nil for "no tab".

    An explicit override wins; otherwise the SWEP's own SubCategory is
    normalised and looked up in SubCategoryAlias. The table is a CLOSED list:
    anything not in it gets no tab at all rather than inventing one, because
    letting packs name their own tabs is exactly how the strip filled up with
    "Machine gun" next to "Machine Guns".
]]
local function subCategoryFor(cfg, swep, override)
    if override.subCategory ~= nil then return override.subCategory or nil end

    local raw = swep and swep.SubCategory
    if not raw or raw == "" then return nil end

    local alias = cfg.SubCategoryAlias and cfg.SubCategoryAlias[normalise(raw)]
    if alias == nil and unknownSubCategories then
        unknownSubCategories[raw] = true
    end
    return alias or nil
end

local function passesExclude(cfg, swep, class)
    if cfg.Exclude[class] then return false end

    -- SubCategory is the reliable signal: ACE and its packs tag every SWEP with
    -- one, and it doesn't depend on the class name happening to contain a word.
    -- The pack mines are classed weapon_ace_PMN / TM62 / VS50, which no sane
    -- name pattern catches, but all three declare SubCategory "Mines".
    -- Normalised the same way the tab aliases are, so "Mines", "Mine" and
    -- "mines" are one rule rather than three that have to be kept in step.
    local sub = swep.SubCategory
    if sub and sub ~= "" and cfg.ExcludeSubCategories
        and cfg.ExcludeSubCategories[normalise(sub)] then
        return false
    end

    local lc = string.lower(class)
    for _, pat in ipairs(cfg.ExcludePatterns or {}) do
        if string.find(lc, pat) then return false end
    end
    return true
end

--[[--
    Rebuild `TPG.Weapons.Primary/Secondary/Special` from currently installed SWEPs.

    Starts each category with a `"none"` entry (always enabled, zero cost),
    then walks `weapons.GetList()` and keeps only SWEPs whose `Base` is
    allowed (`cfg.Bases`) and that pass `passesExclude` (explicit class
    exclusion, `SubCategory` exclusion, or a class-name pattern match). A kept
    SWEP is filed under the category from an explicit override or from its
    `Slot`; if neither maps to a known bucket, it is dropped silently rather
    than filed under something wrong. Virtual entries from `cfg.Virtual` (for
    multi-class or fallback weapons) are added on top of the discovered ones.

    Ammo counts (`rounds`) are computed once here via the local `roundsFor`,
    mirroring `TopUpAmmo` in `player/sv_loadout.lua`; `nil` means "does not
    consume ammo" (ACE's `ClipSize -1` marker for tools/melee), not "zero
    ammo" -- callers must not print "nil rounds" as "0 rounds".

    After rebuilding, re-applies `TPG.Weapons._state` if a state was
    previously loaded via @{TPG.Weapons.ApplyState}, so admin enable/override
    choices survive a rediscovery. On the server only, also logs any raw
    `SubCategory` strings seen that have no entry in `SubCategoryAlias`, as an
    operator note (nothing a player can act on).

    Called once at load and again on `InitPostEntity`; safe to call any time
    after that (e.g. `tpg_weapons_refresh`).

    @realm shared
]]
function TPG.Weapons.Discover()
    local cfg = TPG.WeaponConfig
    if not cfg then return end

    local buckets = { Primary = {}, Secondary = {}, Special = {} }
    unknownSubCategories = {}

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

    -- Server-side only: this is an operator note, not something a player can do
    -- anything about, and printing it on every client is just spam.
    if SERVER then
        local unknown = {}
        for raw in pairs(unknownSubCategories) do unknown[#unknown + 1] = raw end
        if #unknown > 0 then
            table.sort(unknown)
            MsgN("[TPG] Weapon categories with no tab (add them to " ..
                "SubCategoryAlias in config/sh_weapons_config.lua to group them): \"" ..
                table.concat(unknown, "\", \"") .. "\"")
        end
    end
    unknownSubCategories = nil
end

--[[--
    Apply admin enable/override state on top of the discovered weapon lists.

    Shape of `state`:

        { bases     = { [base] = bool },
          weapons   = { [id]   = bool },
          overrides = { [id]   = { speedBonus = n, cost = n, name = s } } }

    Precedence per weapon: a base-level disable turns `enabled` off, then an
    explicit per-weapon entry in `weapons` overrides that either way, so a
    single weapon can be re-enabled even when its whole base is off. The
    `"none"` entry in each category is never touched -- it is always enabled
    and always free, regardless of state.

    Mutates the entry tables in `TPG.Weapons.Primary/Secondary/Special` IN
    PLACE rather than replacing them, so any table reference a caller already
    holds from @{TPG.GetWeapon} changes under it when this runs; nothing here
    hands back a snapshot.

    Stores `state` on `TPG.Weapons._state` unconditionally (even before doing
    anything else), which is what lets @{TPG.Weapons.Discover} re-apply it
    after a rebuild -- but it also means a bad or partial state table is kept
    as "current" the moment this is called, not only once applied
    successfully.

    @tparam ?table state Admin state, or nil/falsy to no-op.
    @realm shared
]]
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

--- Which SWEP bases are actually present, for the admin panel's base toggles.
-- @treturn {[string]=boolean,...} A set (keys present = true) of base names;
--  the virtual pseudo-base is excluded, since it has no real SWEP to toggle.
-- @realm shared
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

--- Look up one discovered weapon entry.
-- @tparam string category "Primary", "Secondary", or "Special".
-- @tparam string id A weapon class, a virtual id, or `"none"`.
-- @treturn ?table The entry, or nil for an unknown category or id -- unlike
--  `TPG.GetArmor`, this has no fallback entry, so callers must handle nil.
-- @realm shared
function TPG.GetWeapon(category, id)
    local cat = TPG.Weapons[category]
    if not cat then return nil end
    return cat[id]
end

--- The SWEP class behind a discovered weapon id.
-- @tparam string category "Primary", "Secondary", or "Special".
-- @tparam string id
-- @treturn ?string The class, or nil if the id is unknown, is `"none"`, or is
--  a virtual entry with no single class (see `multipleClasses`/`fallbackClass`
--  on the entry itself for those).
-- @realm shared
function TPG.GetWeaponClass(category, id)
    local weapon = TPG.GetWeapon(category, id)
    return weapon and weapon.class
end

--- List weapons in a category, sorted by name with "None" always first.
-- @tparam string category "Primary", "Secondary", or "Special".
-- @tparam[opt=false] boolean includeDisabled When false (the default), an
--  entry that is currently disabled (base toggle or explicit per-weapon
--  toggle from @{TPG.Weapons.ApplyState}) is left out entirely.
-- @treturn {table,...} A list of `{ id, name, cost, enabled }`.
-- @realm shared
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

--- Sum the movement-speed bonus/penalty from a full loadout's three weapon slots.
-- An id that does not resolve to a known weapon (unknown category, unknown
-- id, a stale saved loadout referencing a removed weapon) contributes 0
-- silently rather than erroring or warning, so a broken loadout reference
-- shows up as a speed discrepancy, not as a visible failure.
-- @tparam string primaryId
-- @tparam string secondaryId
-- @tparam string specialId
-- @treturn number Combined speed bonus, added into the same sum as the armor
--  tier's `speedBonus` (see `TPG.Config.minSpeedPercent`).
-- @realm shared
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
