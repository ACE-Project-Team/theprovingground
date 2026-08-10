--[[--
    The five armor tiers, free spawn choice through the priciest premium pick.

    `TPG.Armor` is keyed 0-4 by armor id (used elsewhere as `armorId`). Each
    entry has:

        id          repeats the table key, for callers that only kept the entry
        name        display name, shown on the loadout menu and HUD
        health      base player health at this tier
        armor       base player armor pool at this tier
        speedBonus  added into the summed movement-speed percentage alongside
                    the weapon speed bonuses (see `TPG.Config.minSpeedPercent`
                    in `config/sh_config.lua` for why that sum has a floor)
        model       player model path; a literal `%d` placeholder means "pick
                    one of several numbered models at random" (see
                    @{TPG.GetArmorModel})
        canUseSeat  whether this armor tier fits in a vehicle seat at all;
                    only Juggernaut (id 4) is false, so taking the biggest
                    armor tier trades away vehicle crew slots entirely

    Costs and cooldowns for the paid tiers (Heavy, Juggernaut) live in
    `config/sh_gear.lua`, not here; this file only knows the tiers' stats.

    @module tpg.armor
    @realm shared
]]

TPG.Armor = {
    [0] = {
        id          = 0,
        name        = "None",
        health      = 30,
        armor       = 0,
        speedBonus  = 10,
        model       = "models/player/Group01/Male_0%d.mdl",
        canUseSeat  = true,
    },
    [1] = {
        id          = 1,
        name        = "Light",
        health      = 75,
        armor       = 50,
        speedBonus  = 0,
        model       = "models/player/Group03/Male_0%d.mdl",
        canUseSeat  = true,
    },
    [2] = {
        id          = 2,
        name        = "Medium",
        health      = 100,
        armor       = 120,
        speedBonus  = -10,
        model       = "models/player/barney.mdl",
        canUseSeat  = true,
    },
    [3] = {
        id          = 3,
        name        = "Heavy",
        health      = 150,
        armor       = 200,
        speedBonus  = -15,
        model       = "models/player/police.mdl",
        canUseSeat  = true,
    },
    [4] = {
        id          = 4,
        name        = "Juggernaut",
        health      = 750,
        -- 800, not 15000, and the reason is that ACE does not treat this as a
        -- pool at all. sv_acfbase.lua's SquishyDamage converts it to a
        -- THICKNESS in mm RHA -- `3 * (1 + Armor/100)` -- and refuses ALL
        -- damage from a round that does not out-penetrate it. The pool is never
        -- reached, so "enormous but sustained fire empties it" was not what
        -- 15000 bought. It bought 453mm of RHA, needing 454.9mm of penetration
        -- to do a single point of damage, and every infantry weapon on the
        -- server is below that -- measured, at the muzzle:
        --
        --   pistols / SMGs   23-27mm      AK/M16/FAMAS/SAW  26-30mm
        --   AWP 32mm         Scout 48mm   AT-4 244mm        AMR 356mm
        --
        -- So the Juggernaut was immune to the anti-materiel rifle and to the
        -- AT-4, not merely tough. 800 puts the wall at 27mm (threshold 28.9mm),
        -- which is a real armour profile instead of an accident: pistols and
        -- SMGs cannot hurt him at all, rifles chip him, and marksman rifles and
        -- anything anti-tank go through. The pool then does the rest of the
        -- work, and unlike before it is a pool that gets reached.
        --
        -- Health is up to compensate for the pool dropping ~19x. Together that
        -- is roughly 1500 damage to chew through, versus about 400 for Heavy.
        armor       = 800,
        speedBonus  = -40,
        model       = "models/player/combine_super_soldier.mdl",
        canUseSeat  = false,
    },
}

--- Look up an armor tier.
-- The fallback for an unknown id is Light (id 1), not None (id 0); a nil or
-- invalid `armorId` therefore does NOT come back as the unarmored tier, it
-- comes back as the cheapest actually-armored one.
-- @tparam number armorId
-- @treturn table The matching entry from `TPG.Armor`.
-- @realm shared
function TPG.GetArmor(armorId)
    return TPG.Armor[armorId] or TPG.Armor[1]
end

--- The player model to use for an armor tier, resolving any random variant.
-- Some tiers (currently None and Light) use a model path with a literal `%d`
-- placeholder for several numbered models (`Male_01.mdl` .. `Male_09.mdl`);
-- this picks one at random each call, so calling it twice for the same armor
-- can return different models. Tiers with a fixed model path return it
-- unchanged.
-- @tparam number armorId
-- @treturn string A concrete model path, ready to pass to SetModel.
-- @realm shared
function TPG.GetArmorModel(armorId)
    local armor = TPG.GetArmor(armorId)
    local model = armor.model

    if string.find(model, "%%d") then
        return string.format(model, math.random(1, 9))
    end

    return model
end

--- All armor tiers as a flat, id-sorted list for menus.
-- Unlike the weapon list, there is no enabled/disabled concept here; every
-- defined tier is always included regardless of its gear price.
-- @treturn {table,...} A list of `{ id = number, name = string }`, ascending
--  by id.
-- @realm shared
function TPG.GetArmorList()
    local list = {}
    for id, data in pairs(TPG.Armor) do
        table.insert(list, { id = id, name = data.name })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end