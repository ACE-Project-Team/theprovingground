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
    
    -- Get loadout from PData. Ids are weapon class strings now; a legacy
    -- numeric save (from the old index-based system) falls back to the default.
    local dl = TPG.WeaponConfig.DefaultLoadout
    local function loadoutId(key, default)
        local v = TPG.Util.GetPData(ply, key, default)
        if type(v) ~= "string" then return default end
        return v
    end

    local primaryId   = loadoutId("Primary",   dl.Primary)
    local secondaryId = loadoutId("Secondary", dl.Secondary)
    local specialId   = loadoutId("Special",   dl.Special)
    local armorId     = TPG.Util.GetPData(ply, "Armor", 1)
    
    -- Apply armor stats
    TPG.Loadout.ApplyArmor(ply, armorId)

    -- Calculate and apply speed BEFORE giving weapons. The ACE weapon base
    -- snapshots the owner's speed on Deploy and then force-holds it every Think
    -- (weapon_ace_base init.lua:160 / shared.lua Think); if a weapon deploys
    -- first, it snapshots the STALE pre-loadout speed and pins the player to it,
    -- overriding the armor penalty -- a Juggernaut ended up sprinting at default
    -- speed. Setting the speed first makes the snapshot correct.
    local speedBonus = TPG.CalculateSpeedBonus(primaryId, secondaryId, specialId)
    local armor = TPG.GetArmor(armorId)
    speedBonus = speedBonus + armor.speedBonus

    local speedPercent = (TPG.Config.baseSpeedPercent + speedBonus) / 100
    ply:SetWalkSpeed(TPG.Config.baseWalkSpeed * speedPercent * 2)
    ply:SetRunSpeed(TPG.Config.baseRunSpeed * speedPercent * 1.7)

    -- Give weapons
    TPG.Loadout.GiveWeapon(ply, "Primary", primaryId)
    TPG.Loadout.GiveWeapon(ply, "Secondary", secondaryId)
    TPG.Loadout.GiveWeapon(ply, "Special", specialId)
    
    -- Play equip sound
    TPG.Util.PlaySound(ply, "acf_extra/tankfx/gnomefather/rack.wav")
end

-- Raise the player's clip + reserve of a weapon's primary ammo to the total
-- configured in TPG.WeaponConfig.AmmoTopUp (launchers ship with DefaultClip = 1).
local function TopUpAmmo(ply, class, wep)
    local target = TPG.WeaponConfig.AmmoTopUp and TPG.WeaponConfig.AmmoTopUp[class]
    if not target then return end
    if not IsValid(wep) then wep = ply:GetWeapon(class) end
    if not IsValid(wep) then return end

    local ammoType = wep:GetPrimaryAmmoType()
    if ammoType < 0 then return end

    local have = math.max(wep:Clip1(), 0) + ply:GetAmmoCount(ammoType)
    if have < target then
        ply:GiveAmmo(target - have, ammoType, true)
    end
end

function TPG.Loadout.GiveWeapon(ply, category, weaponId)
    local weapon = TPG.GetWeapon(category, weaponId)
    if not weapon or weapon.enabled == false then return end

    -- Single weapon
    if weapon.class then
        TopUpAmmo(ply, weapon.class, ply:Give(weapon.class))
        return
    end

    -- Multiple weapons (e.g., mines)
    if weapon.multipleClasses then
        for _, class in ipairs(weapon.multipleClasses) do
            TopUpAmmo(ply, class, ply:Give(class))
        end
        return
    end

    -- Fallback weapon (e.g., disposable AT when no special selected)
    if weapon.fallbackClass then
        TopUpAmmo(ply, weapon.fallbackClass, ply:Give(weapon.fallbackClass))
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