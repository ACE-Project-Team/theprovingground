--[[--
    Baseline rules for the loadout menu's weapon list: which bases are
    selectable, how discovered weapons are bucketed and tabbed, and the
    per-weapon overrides discovery can't infer on its own.

    The loadout weapon list is DISCOVERED at runtime from any installed SWEP
    whose SWEP.Base is listed in Bases, then bucketed into Primary/Secondary/
    Special by SWEP.Slot. Supporting a new weapon pack (e.g. ACE Weapons+) takes
    no code -- just make sure its base is in Bases.

    Admins can further toggle bases/weapons in-game; those choices are saved to
    data/tpg/weapons.json and layered on top of this file (see sv_weapons.lua).
    This file is only the baseline.

    @module tpg.weaponsconfig
    @realm shared
]]

TPG.WeaponConfig = {
    -- SWEP.Base values that count as selectable weapons. Add a base = support a pack.
    Bases = {
        ["weapon_ace_base"] = true,
    },

    -- SWEP.Slot -> loadout category. ACE: 1=pistol, 2=rifle, 3=sniper, 4=launcher.
    -- A slot not listed here is ignored (unless an Override forces a category).
    SlotCategory = {
        [1] = "Secondary",
        [2] = "Primary",
        [3] = "Primary",
        [4] = "Special",
    },

    --[[
        The loadout menu's tab strip. Manual, and deliberately so.

        SWEP.SubCategory is free text, and every pack spells it differently:
        "Submachine Guns" and "sub-machine guns", "Machine Gun" and "Machine
        Guns", "Pistol" and "Pistols". Taking those at face value gave a strip
        of near-duplicate tabs that split one kind of gun across two of them, so
        the tabs are now a CLOSED list -- SubCategoryTabs is every tab that can
        exist, in the order they appear, and nothing else gets one.

        SubCategoryAlias maps a pack's raw string onto one of those tabs.
        Matching is done on a normalised form (lowercased, punctuation and
        spaces removed, trailing "s" dropped -- see sh_weapons.lua), which is
        what collapses the dash/plural/capitalisation variants above onto a
        single key: "sub-machine guns", "Submachine Gun" and "SUBMACHINE GUNS"
        all arrive here as "submachinegun".

        An unlisted value gets NO tab. Those weapons still appear in the slot,
        under "All" -- they just don't invent a tab nobody asked for. Discovery
        prints anything it didn't recognise to the server console once, so a new
        pack's categories can be added here deliberately.
    ]]
    SubCategoryTabs = {
        -- Primary
        "Assault Rifles",
        "Submachine Guns",
        "Shotguns",
        "Sniper Rifles",
        "Machine Guns",
        -- Secondary
        "Pistols",
        "Grenades",
        "Equipment",
        -- Special
        "Anti-Tank",
        "Anti-Air",
        "Grenade Launchers",
        "Mines",
    },

    SubCategoryAlias = {
        -- Rifles
        ["assaultrifle"]       = "Assault Rifles",
        ["assaultriflesrifle"] = "Assault Rifles",   -- "Assault Rifles/Rifles"
        ["rifle"]              = "Assault Rifles",
        ["battlerifle"]        = "Assault Rifles",
        ["carbine"]            = "Assault Rifles",

        -- Submachine guns
        ["submachinegun"] = "Submachine Guns",
        ["smg"]           = "Submachine Guns",
        ["machinepistol"] = "Submachine Guns",

        -- Machine guns
        ["machinegun"]         = "Machine Guns",
        ["lightmachinegun"]    = "Machine Guns",
        ["lmg"]                = "Machine Guns",
        ["heavymachinegun"]    = "Machine Guns",
        ["hmg"]                = "Machine Guns",
        ["gpmg"]               = "Machine Guns",

        -- Shotguns / precision
        ["shotgun"]      = "Shotguns",
        ["sniperrifle"]  = "Sniper Rifles",
        ["sniper"]       = "Sniper Rifles",
        ["marksmanrifle"]= "Sniper Rifles",
        ["dmr"]          = "Sniper Rifles",

        -- Sidearms and kit
        ["pistol"]   = "Pistols",
        ["handgun"]  = "Pistols",
        ["sidearm"]  = "Pistols",
        ["revolver"] = "Pistols",

        ["grenade"]      = "Grenades",
        ["grenadesmine"] = "Grenades",   -- ACE's own "Grenades/Mines"
        ["explosive"]    = "Grenades",
        ["throwable"]    = "Grenades",

        ["equipment"] = "Equipment",
        ["gear"]      = "Equipment",
        ["utility"]   = "Equipment",

        -- Heavy
        ["antitank"]       = "Anti-Tank",
        ["at"]             = "Anti-Tank",
        ["launcher"]       = "Anti-Tank",
        ["rocketlauncher"] = "Anti-Tank",
        ["rpg"]            = "Anti-Tank",
        ["antimateriel"]   = "Anti-Tank",
        ["antimaterial"]   = "Anti-Tank",

        ["antiair"] = "Anti-Air",
        ["aa"]      = "Anti-Air",
        ["manpad"]  = "Anti-Air",
        ["sam"]     = "Anti-Air",

        ["grenadelauncher"] = "Grenade Launchers",
        ["gl"]              = "Grenade Launchers",

        ["mine"] = "Mines",

        --[[
            Explicitly no tab, so they don't turn up in the console's "didn't
            recognise this" note every map. ACE tags every launcher, the mortar
            and the AMR alike as "Special", which says nothing about any of
            them; the ones worth grouping get an explicit subCategory in
            Overrides below.
        ]]
        ["special"]     = false,
        ["tool"]        = false,
        ["publictest"]  = false,
        ["misc"]        = false,
        ["other"]       = false,
        ["uncategorized"] = false,
    },

    -- Baseline move-speed bonus per category (negative = slower). Overrides win.
    DefaultSpeed = {
        Primary   = -5,
        Secondary = 0,
        Special   = -10,
    },

    -- Speed bonus for the "None" option per category (no weapon = faster).
    NoneSpeed = {
        Primary   = 5,
        Secondary = 10,
        Special   = 20,
    },

    -- SWEP.SubCategory values to drop wholesale.
    --
    -- TPG offers exactly one mine option -- the virtual "Mines" entry below,
    -- which hands out the three ACE base mines as a set. Pack mines duplicate
    -- that for a Special slot pick, so a player picking "AT mine" from a pack
    -- got one mine where the ACE entry gives three, and the list filled up with
    -- near-identical names.
    --
    -- ACE's own mines are NOT caught by this: base ACE files them under
    -- "Grenades/Mines", and they're bundled into the virtual entry via the
    -- Exclude list below. Only packs using a bare "Mines" subcategory are hit,
    -- which is what ACE Weapons+ does.
    -- Keyed on the normalised form (see SubCategoryAlias above), so "Mines",
    -- "Mine" and "mines" are all the same rule.
    ExcludeSubCategories = {
        ["mine"] = true,
    },

    -- Lua patterns (matched against the lowercase class) for dev/test junk to
    -- hide, plus a name-based backstop for mines in packs that don't set a
    -- SubCategory at all. Ends in "mine" rather than contains, so
    -- weapon_ace_minedetector survives.
    ExcludePatterns = {
        "test$",
        "modtest",
        "abbaaaaaaab",

        "mine$",
        "mines$",
        "claymore",
    },

    -- Exact classes never offered. The ACE mine SWEPs are bundled into the
    -- virtual "Mines" entry below, so they're hidden as individual choices (see
    -- also the mine ExcludePatterns, which drop add-on packs' own mines). The
    -- disposable AT is never a menu pick either -- it's the consolation tube for
    -- anyone whose Special slot is empty (see sv_loadout.lua).
    Exclude = {
        ["weapon_ace_antipersonmine"] = true,
        ["weapon_ace_boundingmine"]   = true,
        ["weapon_ace_antitankmine"]   = true,
        ["disposableat"]              = true,
        -- ACE's safezone-authoring tool. It's a Slot 4 SWEP, so discovery filed
        -- it with the launchers, but it isn't a weapon at all -- it's a mapping
        -- tool, and taking it costs you your anti-tank slot.
        ["weapon_szcreator"]          = true,
    },

    --[[
        Per-weapon tuning, and the ONE place a realm split can be repaired.

        Any field overrides the discovered/default value: name, speedBonus,
        cost (economy), category (force a bucket), subCategory (which tab it
        shows under in the loadout menu).

        Discovery buckets by SWEP.Slot, but a SWEP is free to declare Slot inside
        `if CLIENT then` -- ACE does exactly that for its whole Grenades/Mines
        family. The client then sees Slot 4 while the server sees the base's
        Slot 2, so the two realms bucket the same weapon differently: the menu
        offered S.L.A.M. under Special, the server looked for it in Special,
        found nothing (it had it under Primary) and answered "that weapon is not
        available". A `category` override is shared code, so it forces both
        realms to the same answer -- which is why every client-only-Slot weapon
        below carries one.
    ]]
    Overrides = {
        -- grenades/binocular are Slot 4 in ACE but belong with sidearms
        ["weapon_ace_grenade"]      = { category = "Secondary", speedBonus = 0 },
        ["weapon_ace_smokegrenade"] = { category = "Secondary", speedBonus = 0 },
        ["weapon_ace_binocular"]    = { category = "Secondary", speedBonus = 8, subCategory = "Equipment" },
        -- S.L.A.M. is the third client-only-Slot weapon and the one that had no
        -- override, so it was the one that broke. It's a Special: a placed
        -- charge you take INSTEAD of a launcher, not a sidearm like the
        -- grenades. PrintName is client-only too, hence the explicit name --
        -- otherwise the server logs it as "ACE Base Weapon".
        ["weapon_ace_slam"]         = { category = "Special", name = "Mine-S.L.A.M.", speedBonus = 0, subCategory = "Mines" },
        -- ACE files the guided launchers and the mortar under Slot 3, the same
        -- slot as its sniper rifles, so discovery bucketed them as Primary --
        -- you could carry a Javelin AS your rifle and still take an AT-4 in the
        -- Special slot on top. They're launchers; put them in the launcher slot,
        -- where they compete with the other anti-tank options.
        ["weapon_ace_javelin"]        = { category = "Special", subCategory = "Anti-Tank" },
        ["weapon_ace_stinger"]        = { category = "Special", subCategory = "Anti-Air" },
        ["weapon_ace_portablemortar"] = { category = "Special", subCategory = "Grenade Launchers" },
        -- ACE Weapons+ makes the same mistake with its two MANPADS and the M32
        -- revolver grenade launcher -- all three are Slot 3. Its RPGs are
        -- correctly Slot 4 and need no override.
        ["weapon_ace_9k32"]  = { category = "Special", subCategory = "Anti-Air" },
        ["weapon_ace_9k38"]  = { category = "Special", subCategory = "Anti-Air" },
        ["weapon_ace_m32gl"] = { category = "Special", subCategory = "Grenade Launchers" },

        --[[
            Tab placement for the weapons ACE files under its catch-all
            "Special" subcategory (see SubCategoryAlias). These are the ones
            worth finding by group: the anti-tank tube you take to answer a
            tank, and the airburst launcher you take to answer infantry in
            cover.

            The anti-materiel rifle is here because it's the odd one out -- it's
            a PRIMARY, so it never sat with the launchers, and a player looking
            for something that hurts vehicles has no reason to expect it filed
            under "Special" among the rifles.
        ]]
        ["weapon_ace_amr"]   = { subCategory = "Anti-Tank" },
        ["weapon_ace_at4"]   = { subCategory = "Anti-Tank" },
        ["weapon_ace_at4t"]  = { subCategory = "Anti-Tank" },
        ["weapon_ace_xm25"]  = { subCategory = "Grenade Launchers" },
        ["weapon_ace_flaregun"]     = { subCategory = "Equipment" },
        ["weapon_ace_minedetector"] = { subCategory = "Equipment" },
        -- heavy weapons slow you down more
        ["weapon_ace_m249saw"] = { speedBonus = -15 },
        ["weapon_ace_m60"]     = { speedBonus = -15 },
        ["weapon_ace_pkm"]     = { speedBonus = -15 },
        ["weapon_ace_mg36"]    = { speedBonus = -15 },
        ["weapon_ace_rpk"]     = { speedBonus = -7 },
        ["weapon_ace_rpk74"]   = { speedBonus = -7 },
    },

    -- Reserve-ammo top-ups, applied when the loadout weapon is given: the
    -- player's clip + reserve of the weapon's primary ammo is raised to this
    -- total. The AT-4-likes ship with DefaultClip = 1 (a single rocket ever),
    -- which is uselessly low for a vehicle-combat round.
    AmmoTopUp = {
        ["weapon_ace_at4"]     = 6,
        ["weapon_ace_at4t"]    = 6,
        ["weapon_ace_javelin"] = 6,
    },

    -- Floor for EVERY Special-slot weapon, so launchers from add-on packs (ACE
    -- Weapons+, etc.) are covered without listing their classes: any Special
    -- weapon spawning with fewer total rounds than this is topped up to it.
    -- Weapons already above the floor (stinger 12, mortar 16, mines 12) are
    -- untouched, as are ammo-less tools (their ammo type is "none").
    SpecialAmmoMin = 6,

    -- "Virtual" entries that aren't a single discoverable SWEP (multi-item or
    -- fallback). Keyed by a stable sentinel id.
    Virtual = {
        Primary   = {},
        Secondary = {},
        Special   = {
            ["ace_mines"] = {
                name        = "Mines",
                subCategory = "Mines",
                speedBonus  = 0,
                multipleClasses = {
                    "weapon_ace_antipersonmine",
                    "weapon_ace_boundingmine",
                    "weapon_ace_antitankmine",
                },
                --[[
                    The set used to arrive with 33 mines. Each of the three
                    SWEPs ships DefaultClip 11, and they all draw from ONE ammo
                    pool ("CombineHeavyCannon"), so giving all three stacked
                    their clips into a single shared reserve.

                    That shared pool is also why this is a single total rather
                    than 6 anti-tank / 3 bounding / 10 anti-personnel: nothing
                    distinguishes whose rounds are whose once they're in it, and
                    per-type counts would need the ACE SWEPs themselves changed
                    to use separate ammo types. 19 is the requested split's
                    total, spent however the player likes.
                ]]
                exactAmmo = 19,
            },
        },
    },

    -- Fresh-player default loadout (must be a discovered class or "none";
    -- falls back to "none" if the class isn't available).
    DefaultLoadout = {
        Primary   = "weapon_ace_m16",
        Secondary = "weapon_ace_glock",
        Special   = "none",
    },

    -- Always given, regardless of loadout.
    AlwaysGive = {
        "weapon_physgun",
        "gmod_camera",
        "weapon_crowbar",
    },

    -- Given when a player joins a team.
    TeamTools = {
        "gmod_tool",
    },
}
