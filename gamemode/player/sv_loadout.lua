--[[
    Player Loadout System
]]

TPG.Loadout = {}

function TPG.Loadout.Apply(ply)
    -- Strip existing weapons
    ply:StripWeapons()
    
    -- Always give default weapons
    for _, class in ipairs(TPG.Weapons.Default) do
        ply:Give(class)
    end
    
    local teamId = ply:Team()
    
    -- Not on a team, minimal loadout
    if not TPG.Util.IsOnTeam(ply) then
        return
    end
    
    -- Give team tools
    for _, class in ipairs(TPG.Weapons.TeamTools) do
        ply:Give(class)
    end
    
    -- Get loadout from PData
    local primaryId = TPG.Util.GetPData(ply, "Primary", 1)
    local secondaryId = TPG.Util.GetPData(ply, "Secondary", 0)
    local specialId = TPG.Util.GetPData(ply, "Special", 1)
    local armorId = TPG.Util.GetPData(ply, "Armor", 1)
    
    -- Give weapons
    TPG.Loadout.GiveWeapon(ply, "Primary", primaryId)
    TPG.Loadout.GiveWeapon(ply, "Secondary", secondaryId)
    TPG.Loadout.GiveWeapon(ply, "Special", specialId)
    
    -- Apply armor stats
    TPG.Loadout.ApplyArmor(ply, armorId)
    
    -- Calculate and apply speed
    local speedBonus = TPG.CalculateSpeedBonus(primaryId, secondaryId, specialId)
    local armor = TPG.GetArmor(armorId)
    speedBonus = speedBonus + armor.speedBonus
    
    local speedPercent = (TPG.Config.baseSpeedPercent + speedBonus) / 100
    ply:SetWalkSpeed(TPG.Config.baseWalkSpeed * speedPercent * 2)
    ply:SetRunSpeed(TPG.Config.baseRunSpeed * speedPercent * 1.7)
    
    -- Play equip sound
    TPG.Util.PlaySound(ply, "acf_extra/tankfx/gnomefather/rack.wav")
end

function TPG.Loadout.GiveWeapon(ply, category, weaponId)
    local weapon = TPG.GetWeapon(category, weaponId)
    if not weapon then return end
    
    -- Single weapon
    if weapon.class then
        ply:Give(weapon.class)
        return
    end
    
    -- Multiple weapons (e.g., mines)
    if weapon.multipleClasses then
        for _, class in ipairs(weapon.multipleClasses) do
            ply:Give(class)
        end
        return
    end
    
    -- Fallback weapon (e.g., disposable AT when no special selected)
    if weapon.fallbackClass then
        ply:Give(weapon.fallbackClass)
    end
end

function TPG.Loadout.ApplyArmor(ply, armorId)
    local armor = TPG.GetArmor(armorId)
    
    -- Set model
    local model = TPG.GetArmorModel(armorId)
    ply:SetModel(model)
    
    -- Set health/armor
    ply:SetHealth(armor.health)
    ply:SetMaxHealth(armor.health)
    ply:SetArmor(armor.armor)
end