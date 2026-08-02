--[[
    Premium Gear (shared)

    Most of the kit is free: everyone can field an AT-4, mines and medium armor
    every single life, forever. This file lists the handful of items that are
    strong enough that having one every spawn distorts the round, and what it
    costs to take one.

    There are two prices, and which one you pay depends on the round:

      TEAM BUDGET (the normal round) -- you pay in TIME. Take the item and it
      goes on a personal cooldown; until that runs out you spawn with the free
      equivalent instead. There is no wallet in this mode, and charging the
      shared team budget for a personal rifle would just let one player spend
      the round's tickets, so a cooldown is the only price that lands on the
      person who actually chose it.

      PER-PLAYER ECONOMY (the secondary mode) -- you pay in POINTS, out of the
      same wallet you buy vehicles from. No cooldown: if you can afford it every
      life, that's a legitimate way to spend a wallet that isn't buying a tank.

    Costs are sized against ECON.Config: you start a round with 3,000 and a good
    modern tank runs about 6,000. Nothing here should ever be the reason you
    can't field a vehicle -- the most expensive item is a fifth of a tank.

    Cooldowns are in seconds of real time, not lives, so dying repeatedly never
    speeds up the next Javelin.
]]

TPG.Gear = TPG.Gear or {}

-- Armor the game falls back to when a premium pick is denied. The best free
-- tier, so a denied Heavy still leaves you with a fightable loadout.
TPG.Gear.FreeArmor = 2   -- Medium

-- [weapon class] = { cost = economy points, cooldown = seconds }
--
-- Anything not listed here is free and always available. The AT-4 is the
-- deliberate free baseline for anti-tank: every player can answer a tank every
-- life without paying anything, and the paid launchers are bought for range,
-- guidance or penetration rather than for the ability to fight back at all.
TPG.Gear.Weapons = {
    -- Anti-tank, cheapest first.
    ["weapon_ace_at4t"]          = { cost = 250,  cooldown = 90 },   -- AT-4 Proto: a better AT-4
    ["weapon_ace_stinger"]       = { cost = 500,  cooldown = 180 },  -- guided, but anti-air
    ["weapon_ace_javelin"]       = { cost = 700,  cooldown = 240 },  -- fire-and-forget top attack

    -- Infantry support.
    ["weapon_ace_xm25"]          = { cost = 500,  cooldown = 150 },  -- airburst, ignores cover
    ["weapon_ace_portablemortar"] = { cost = 400, cooldown = 180 },  -- indirect fire from safety

    --[[
        ACE Weapons+ launchers (RPG-28 and friends) belong here too, priced
        above the AT-4 Proto and below the Javelin. They are NOT listed yet
        because that pack isn't installed on this machine and inventing class
        names would silently price nothing at all -- an entry whose class never
        matches a real SWEP is indistinguishable from a free weapon.

        Until the classes are known, any pack launcher is free. Admins can gate
        one immediately without a code change through the weapon panel, which
        can set a per-weapon cost override.
    ]]
}

-- [armor id] = { cost, cooldown }. See config/sh_armor.lua for the tiers.
-- None / Light / Medium are free; Medium is the free ceiling on purpose, so the
-- default loadout is never the one you have to pay for.
TPG.Gear.Armor = {
    [3] = { cost = 300,  cooldown = 90 },    -- Heavy
    [4] = { cost = 1200, cooldown = 300 },   -- Juggernaut (and it can't use seats)
}

-- Stable identifier for one item, used as the cooldown key on both realms.
function TPG.Gear.Key(kind, id)
    if kind == "armor" then return "armor:" .. tostring(id) end
    return tostring(id)
end

-- Points-per-second of cooldown, used to fill in the price an admin didn't set.
-- Derived from the hand-tuned pairs above (250/90, 700/240, 1200/300), so a
-- cost typed into the weapon panel lands in the same ballpark as this file.
local COST_PER_COOLDOWN_SEC = 3

-- Price table for an item, or nil if it's free. Weapon entries can be retuned
-- live by an admin (the cost override in the weapon panel), so the discovered
-- entry wins over the baseline in this file when it carries one.
--
-- An admin-set cost gets a matching cooldown for free. Without that, gating a
-- weapon through the panel would do nothing at all in a normal round -- the
-- cost only bites under the economy, which most rounds aren't.
function TPG.Gear.Price(kind, id)
    if kind == "armor" then
        return TPG.Gear.Armor[tonumber(id) or -1]
    end

    local base = TPG.Gear.Weapons[id]

    for _, cat in ipairs({ "Primary", "Secondary", "Special" }) do
        local entry = TPG.Weapons and TPG.Weapons[cat] and TPG.Weapons[cat][id]
        if entry and (entry.cost or 0) > 0 then
            return {
                cost     = entry.cost,
                cooldown = entry.cooldown
                    or (base and base.cooldown)
                    or math.Round(entry.cost / COST_PER_COOLDOWN_SEC),
            }
        end
    end

    return base
end

-- Display name for chat/menu messages, whichever kind it is.
function TPG.Gear.Name(kind, id)
    if kind == "armor" then
        local armor = TPG.GetArmor and TPG.GetArmor(tonumber(id))
        return armor and armor.name or ("Armor " .. tostring(id))
    end

    for _, cat in ipairs({ "Primary", "Secondary", "Special" }) do
        local entry = TPG.Weapons and TPG.Weapons[cat] and TPG.Weapons[cat][id]
        if entry then return entry.name end
    end
    return tostring(id)
end

-- Which price is in force right now. Kept in one place so the menu and the
-- spawn code can never disagree about what a player is about to be charged.
function TPG.Gear.EconomyActive()
    return GetGlobalBool("TPG_EconomyActive", false)
end
