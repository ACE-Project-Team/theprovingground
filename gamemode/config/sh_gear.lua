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
        ACE Weapons+ (github.com/OrangeFox861/ACE-Weapons-).

        Its launchers are graded off the AT-4 as the free baseline, exactly like
        the ACE ones above. Anything in the AT-4's class -- single-shot, single
        HEAT warhead, no guidance -- stays free, so taking the pack never costs
        you the ability to fight armour. What costs points is a tandem warhead,
        a reload, or guidance.

        The free ones are listed as comments rather than zero-cost entries: an
        entry here means "priced", and a 0 would sit in the table looking like
        an oversight. Absent IS the free state.

            weapon_ace_m72law     LAW, lighter than an AT-4
            weapon_ace_rpg26      disposable light HEAT
            weapon_ace_rpg7       PG-7VL, the baseline RPG-7
            weapon_ace_rshg2      thermobaric, anti-personnel not anti-armour
    ]]
    ["weapon_ace_rpg7v2"]        = { cost = 150,  cooldown = 60 },   -- reloadable RPG-7
    ["weapon_ace_carlgustafhe"]  = { cost = 300,  cooldown = 100 },  -- HEDP, reloadable
    ["weapon_ace_shmel"]         = { cost = 300,  cooldown = 120 },  -- RPO-A thermobaric
    ["weapon_ace_carlgustaf"]    = { cost = 350,  cooldown = 110 },  -- HEAT 551C, reloadable
    ["weapon_ace_matador"]       = { cost = 350,  cooldown = 110 },  -- RGW-90
    ["weapon_ace_m32gl"]         = { cost = 450,  cooldown = 150 },  -- 6-shot revolver GL
    ["weapon_ace_panzerfaust3"]  = { cost = 450,  cooldown = 140 },  -- heavy HEAT
    ["weapon_ace_rpg7v2t"]       = { cost = 500,  cooldown = 150 },  -- PG-7VR tandem
    ["weapon_ace_9k32"]          = { cost = 450,  cooldown = 170 },  -- Strela-2, anti-air
    ["weapon_ace_9k38"]          = { cost = 550,  cooldown = 190 },  -- Igla, better anti-air
    ["weapon_ace_rpg29"]         = { cost = 600,  cooldown = 190 },  -- Vampir, tandem
    ["weapon_ace_rpg28"]         = { cost = 650,  cooldown = 220 },  -- heaviest tandem
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
