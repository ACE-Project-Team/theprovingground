--[[
    Armor Type Definitions
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
        health      = 500,
        armor       = 999999,
        speedBonus  = -40,
        model       = "models/player/combine_super_soldier.mdl",
        canUseSeat  = false,
    },
}

function TPG.GetArmor(armorId)
    return TPG.Armor[armorId] or TPG.Armor[1]
end

function TPG.GetArmorModel(armorId)
    local armor = TPG.GetArmor(armorId)
    local model = armor.model
    
    if string.find(model, "%%d") then
        return string.format(model, math.random(1, 9))
    end
    
    return model
end

function TPG.GetArmorList()
    local list = {}
    for id, data in pairs(TPG.Armor) do
        table.insert(list, { id = id, name = data.name })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end