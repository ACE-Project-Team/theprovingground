--[[
    Weapon System Configuration (defaults)

    The loadout weapon list is DISCOVERED at runtime from any installed SWEP
    whose SWEP.Base is listed in Bases, then bucketed into Primary/Secondary/
    Special by SWEP.Slot. Supporting a new weapon pack (e.g. ACE Weapons+) takes
    no code -- just make sure its base is in Bases.

    Admins can further toggle bases/weapons in-game; those choices are saved to
    data/tpg/weapons.json and layered on top of this file (see sv_weapons.lua).
    This file is only the baseline.
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

    -- Lua patterns (matched against the lowercase class) for dev/test junk to hide.
    ExcludePatterns = {
        "test$",
        "modtest",
        "abbaaaaaaab",
    },

    -- Exact classes never offered. The mine SWEPs are bundled into the virtual
    -- "Mines" entry below, so they're hidden as individual choices.
    Exclude = {
        ["weapon_ace_antipersonmine"] = true,
        ["weapon_ace_boundingmine"]   = true,
        ["weapon_ace_antitankmine"]   = true,
    },

    -- Per-weapon tuning. Any field overrides the discovered/default value:
    --   name, speedBonus, cost (economy), category (force a bucket).
    Overrides = {
        -- grenades/binocular are Slot 4 in ACE but belong with sidearms
        ["weapon_ace_grenade"]      = { category = "Secondary", speedBonus = 0 },
        ["weapon_ace_smokegrenade"] = { category = "Secondary", speedBonus = 0 },
        ["weapon_ace_binocular"]    = { category = "Secondary", speedBonus = 8 },
        -- heavy weapons slow you down more
        ["weapon_ace_m249saw"] = { speedBonus = -15 },
        ["weapon_ace_m60"]     = { speedBonus = -15 },
        ["weapon_ace_pkm"]     = { speedBonus = -15 },
        ["weapon_ace_mg36"]    = { speedBonus = -15 },
        ["weapon_ace_rpk"]     = { speedBonus = -7 },
        ["weapon_ace_rpk74"]   = { speedBonus = -7 },
    },

    -- "Virtual" entries that aren't a single discoverable SWEP (multi-item or
    -- fallback). Keyed by a stable sentinel id.
    Virtual = {
        Primary   = {},
        Secondary = {},
        Special   = {
            ["ace_mines"] = {
                name       = "Mines",
                speedBonus = 0,
                multipleClasses = {
                    "weapon_ace_antipersonmine",
                    "weapon_ace_boundingmine",
                    "weapon_ace_antitankmine",
                },
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
