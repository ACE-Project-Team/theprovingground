--[[
    Weapon Definitions - ACE Weapons
]]

TPG.Weapons = {
    Primary = {
        [0]  = { id = 0,  name = "None",        class = nil,                        speedBonus = 15 },
        [1]  = { id = 1,  name = "M16",         class = "weapon_ace_m16",           speedBonus = 0 },
        [2]  = { id = 2,  name = "AK-47",       class = "weapon_ace_ak47",          speedBonus = 0 },
        [3]  = { id = 3,  name = "Galil",       class = "weapon_ace_galil",         speedBonus = 0 },
        [4]  = { id = 4,  name = "FAMAS",       class = "weapon_ace_famas",         speedBonus = 0 },
        [5]  = { id = 5,  name = "AUG",         class = "weapon_ace_aug",           speedBonus = 0 },
        [6]  = { id = 6,  name = "SG552",       class = "weapon_ace_sg552",         speedBonus = 0 },
        [7]  = { id = 7,  name = "M3 Super90",  class = "weapon_ace_m3super90",     speedBonus = 0 },
        [8]  = { id = 8,  name = "XM1014",      class = "weapon_ace_xm1014",        speedBonus = 0 },
        [9]  = { id = 9,  name = "P90",         class = "weapon_ace_p90",           speedBonus = 0 },
        [10] = { id = 10, name = "UMP-45",      class = "weapon_ace_ump45",         speedBonus = 0 },
        [11] = { id = 11, name = "MP5",         class = "weapon_ace_mp5",           speedBonus = 0 },
        [12] = { id = 12, name = "TMP",         class = "weapon_ace_tmp",           speedBonus = 0 },
        [13] = { id = 13, name = "MAC-10",      class = "weapon_ace_mac10",         speedBonus = 0 },
        [14] = { id = 14, name = "Scout",       class = "weapon_ace_scout",         speedBonus = 0 },
        [15] = { id = 15, name = "AWP",         class = "weapon_ace_awp",           speedBonus = 0 },
        [16] = { id = 16, name = "M249 SAW",    class = "weapon_ace_m249saw",       speedBonus = -5 },
    },
    
    Secondary = {
        [0] = { id = 0, name = "None",          class = nil,                        speedBonus = 10 },
        [1] = { id = 1, name = "Glock",         class = "weapon_ace_glock",         speedBonus = 0 },
        [2] = { id = 2, name = "Five-Seven",    class = "weapon_ace_fiveseven",     speedBonus = 0 },
        [3] = { id = 3, name = "P228",          class = "weapon_ace_p228",          speedBonus = 0 },
        [4] = { id = 4, name = "USP",           class = "weapon_ace_usp",           speedBonus = 0 },
        [5] = { id = 5, name = "Desert Eagle",  class = "weapon_ace_deagle",        speedBonus = 0 },
        [6] = { id = 6, name = "Dual Elites",   class = "weapon_ace_elite",         speedBonus = 0 },
        [7] = { id = 7, name = "Grenade",       class = "weapon_ace_grenade",       speedBonus = 0 },
        [8] = { id = 8, name = "Smoke Grenade", class = "weapon_ace_smokegrenade",  speedBonus = 0 },
    },
    
    Special = {
        [0] = { 
            id = 0, 
            name = "None", 
            class = nil, 
            speedBonus = 20,
            fallbackClass = "weapon_ace_at4",  -- Light disposable AT
        },
        [1] = { id = 1, name = "AT-4",          class = "weapon_ace_at4",           speedBonus = 0 },
        [2] = { id = 2, name = "AT-4 Tandem",   class = "weapon_ace_at4t",          speedBonus = 0 },
        [3] = { id = 3, name = "AMR",           class = "weapon_ace_amr",           speedBonus = 0 },
        [4] = { id = 4, name = "XM25",          class = "weapon_ace_xm25",          speedBonus = 0 },
        [5] = { id = 5, name = "Javelin",       class = "weapon_ace_javelin",       speedBonus = -5 },
        [6] = { id = 6, name = "Stinger",       class = "weapon_ace_stinger",       speedBonus = 0 },
        [7] = {
            id = 7,
            name = "Mines",
            class = nil,
            speedBonus = 0,
            multipleClasses = {
                "weapon_ace_antipersonmine",
                "weapon_ace_boundingmine",
                "weapon_ace_antitankmine",
            },
        },
        [8] = { id = 8, name = "Mortar",        class = "weapon_ace_portablemortar", speedBonus = -10 },
    },
    
    -- Always given regardless of loadout
    Default = {
        "weapon_physgun",
        "gmod_camera",
        "weapon_crowbar",
    },
    
    -- Given when player joins a team
    TeamTools = {
        "gmod_tool",
    },
}

function TPG.GetWeapon(category, weaponId)
    local cat = TPG.Weapons[category]
    if not cat then return nil end
    return cat[weaponId]
end

function TPG.GetWeaponClass(category, weaponId)
    local weapon = TPG.GetWeapon(category, weaponId)
    return weapon and weapon.class
end

function TPG.GetWeaponList(category)
    local cat = TPG.Weapons[category]
    if not cat then return {} end
    
    local list = {}
    for id, data in pairs(cat) do
        if type(id) == "number" then
            table.insert(list, { id = id, name = data.name })
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function TPG.CalculateSpeedBonus(primaryId, secondaryId, specialId)
    local bonus = 0
    
    local primary = TPG.GetWeapon("Primary", primaryId)
    local secondary = TPG.GetWeapon("Secondary", secondaryId)
    local special = TPG.GetWeapon("Special", specialId)
    
    if primary then bonus = bonus + (primary.speedBonus or 0) end
    if secondary then bonus = bonus + (secondary.speedBonus or 0) end
    if special then bonus = bonus + (special.speedBonus or 0) end
    
    return bonus
end