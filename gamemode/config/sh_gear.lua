--[[--
    Prices and cooldowns for the handful of items strong enough to be gated.

    Most of the kit is free: everyone can field an AT-4, mines and medium armor
    every single life, forever. This file lists the handful of items that are
    strong enough that having one every spawn distorts the round, and what it
    costs to take one.

    There are two prices, and which one you pay depends on the round:

    TEAM BUDGET (the normal round), you pay in LIVES, and then in TIME. Take
    the item and you keep it for a run of lives -- `lives`, or
    `TPG.Config.gearCooldownLives` when the entry does not say -- one spent per
    life you actually spawn with it. When the last one is gone the `cooldown`
    timer starts, and until it runs out you spawn with the free equivalent
    instead. There is no wallet in this mode, and charging the shared team
    budget for a personal rifle would just let one player spend the round's
    tickets, so a personal price is the only one that lands on the person who
    actually chose it.

    It was a bare timer at first, deliberately: seconds of real time meant
    dying repeatedly could never shorten the wait. What that missed is that
    one death then cost you the whole timer, so a single bad life took your
    launcher away for minutes of a round you were still playing. Spending
    lives first fixes that from the other end and keeps the same property --
    a suicide burns one of your own charges, so killing yourself is a way to
    reach the wait sooner, never to skip it.

    PER-PLAYER ECONOMY (the secondary mode), you pay in POINTS, out of the
    same wallet you buy vehicles from. No cooldown: if you can afford it every
    life, that's a legitimate way to spend a wallet that isn't buying a tank.

    Costs are sized against ECON.Config: you start a round with 3,000 and a
    good modern tank runs about 6,000. Nothing here should ever be the reason
    you can't field a vehicle; the most expensive item is a fifth of a tank.

    Cooldowns are in seconds of real time once they start, so waiting one out
    does not depend on how the round is going. Which price is active right now
    is a single shared answer (@{TPG.Gear.EconomyActive}), not a per-item
    choice.

    @module tpg.gear
    @realm shared
]]

TPG.Gear = TPG.Gear or {}

-- Armor the game falls back to when a premium pick is denied. The best free
-- tier, so a denied Heavy still leaves you with a fightable loadout.
TPG.Gear.FreeArmor = 2   -- Medium

-- [weapon class] = { cost = economy points, cooldown = seconds, lives = n }
--
-- `lives` is optional and defaults to `TPG.Config.gearCooldownLives` (6): how
-- many lives you get out of one take before the `cooldown` timer starts. Set it
-- per weapon where six is the wrong number -- `lives = 3` on something that
-- should come round twice as often, `lives = 10` on something that should be
-- close to a once-a-round decision. The timer is what it costs AFTER that run,
-- so the two knobs are independent: `lives` sets how long you keep it, and
-- `cooldown` sets how long you go without.
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

    -- The anti-materiel rifle is the one PRIMARY worth pricing: everything else
    -- in that slot trades range for rate of fire against infantry, while this
    -- one puts holes in vehicles from a ridge with ten rounds to do it. Priced
    -- under the launchers because it still costs you your rifle to carry, and it
    -- can't kill a tank the way a tandem warhead can.
    ["weapon_ace_amr"]           = { cost = 350,  cooldown = 120 },

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

--- Stable identifier for one item, used as the cooldown key on both realms.
-- @tparam string kind `"armor"` or `"weapon"` (anything else is treated as a
--  weapon).
-- @tparam string|number id Armor id or weapon class/virtual id.
-- @treturn string `"armor:<id>"` for armor, `tostring(id)` otherwise.
-- @realm shared
function TPG.Gear.Key(kind, id)
    if kind == "armor" then return "armor:" .. tostring(id) end
    return tostring(id)
end

-- Points-per-second of cooldown, used to fill in the price an admin didn't set.
-- Derived from the hand-tuned pairs above (250/90, 700/240, 1200/300), so a
-- cost typed into the weapon panel lands in the same ballpark as this file.
local COST_PER_COOLDOWN_SEC = 3

--[[--
    Price table for an item, or nil if it is free.

    For armor, this is a straight lookup into `TPG.Gear.Armor` (the price table
    in this file, not `TPG.Armor` in `sh_armor.lua`); ids not listed there
    (None/Light/Medium) come back nil, meaning free.

    For a weapon, this first checks whether the id's DISCOVERED entry (in
    `TPG.Weapons.Primary/Secondary/Special`) carries a positive `cost`. That
    field is only ever non-zero when an admin has set a per-weapon cost
    override in the weapon panel (`config/sh_weapons_config.lua`'s static
    `Overrides` can also seed it) -- it is NOT populated from this file's
    `Weapons` table, so the normal case is that discovered `cost` is 0 and
    this falls through to `base`, the static entry below. When an admin
    override IS present, it wins outright over the baseline in this file.

    An admin-set cost gets a matching cooldown for free, computed as
    `entry.cooldown or (base and base.cooldown) or cost/COST_PER_COOLDOWN_SEC`.
    In practice `entry.cooldown` is never populated anywhere in
    `config/sh_weapons.lua` (discovery never sets it and neither does
    `TPG.Weapons.ApplyState`), so that first branch is currently always nil
    and the real fallback is the static baseline's cooldown, or the derived
    one if there is no baseline entry at all. Without a cooldown here, gating
    a weapon through the panel would do nothing at all in a normal round; the
    cost only bites under the economy, which most rounds aren't.

    @tparam string kind `"armor"` or `"weapon"`.
    @tparam string|number id Armor id or weapon class/virtual id.
    @treturn ?table `{ cost, cooldown, lives }`, or nil if the item is free.
     `lives` is always filled in, from the entry or from
     `TPG.Config.gearCooldownLives`, so callers never have to default it.
    @realm shared
]]
function TPG.Gear.Price(kind, id)
    local price
    if kind == "armor" then
        price = TPG.Gear.Armor[tonumber(id) or -1]
    else
        local base = TPG.Gear.Weapons[id]
        price = base

        for _, cat in ipairs({ "Primary", "Secondary", "Special" }) do
            local entry = TPG.Weapons and TPG.Weapons[cat] and TPG.Weapons[cat][id]
            if entry and (entry.cost or 0) > 0 then
                price = {
                    cost     = entry.cost,
                    cooldown = entry.cooldown
                        or (base and base.cooldown)
                        or math.Round(entry.cost / COST_PER_COOLDOWN_SEC),
                    lives    = entry.lives or (base and base.lives),
                }
                break
            end
        end
    end

    if not price then return nil end

    --[[
        `lives` is defaulted on the way out rather than written into every
        entry, so the config only ever says the number when it disagrees with
        the global one -- and so raising TPG.Config.gearCooldownLives moves
        every item that never had an opinion.

        A copy, because the entry itself is the shared config table: filling
        the field in place would write the default INTO the config, and the
        next read could no longer tell "the admin set 6" from "6 is just the
        default", which is exactly the distinction the line above depends on.
    ]]
    return {
        cost     = price.cost,
        cooldown = price.cooldown,
        lives    = math.max(math.floor(price.lives or TPG.Config.gearCooldownLives or 6), 1),
    }
end

--- Display name for chat/menu messages, whichever kind it is.
-- @tparam string kind `"armor"` or `"weapon"`.
-- @tparam string|number id Armor id or weapon class/virtual id.
-- @treturn string The armor tier's name, the weapon entry's name, or
--  `tostring(id)` as a last resort if nothing matches (e.g. an id from a
--  weapon pack that has since been removed).
-- @realm shared
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

--- Which price is in force right now: per-player economy, or the team-budget cooldown.
-- Kept in one place so the menu and the spawn code can never disagree about
-- what a player is about to be charged.
-- @treturn boolean True when the per-player economy mode is running.
-- @realm shared
function TPG.Gear.EconomyActive()
    return GetGlobalBool("TPG_EconomyActive", false)
end
