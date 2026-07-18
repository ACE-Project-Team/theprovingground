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

    -- Building tools (toolgun) -- given to everyone, including spectators, so
    -- non-combatants can build/tool freely alongside the physgun in Default.
    for _, class in ipairs(TPG.Weapons.TeamTools) do
        ply:Give(class)
    end

    local teamId = ply:Team()

    -- Not on a team, minimal loadout (default weapons + tools, no team kit)
    if not TPG.Util.IsOnTeam(ply) then
        return
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

    -- Bonus disposable AT: EVERY teamed player gets a free single-use tube on
    -- top of whatever they picked -- it's an extra, not a pick, because a chosen
    -- launcher can run dry and mines don't answer a tank at range. Given last,
    -- after the speed snapshot, so it doesn't override movement. Small chance to
    -- roll a real launcher (stinger/javelin) instead, which goes through
    -- GiveWeapon so it gets the Special ammo floor.
    local atClass = TPG.Config.disposableATClass
    if atClass and atClass ~= "" then
        local gaveUpgrade = false
        local upgrades = TPG.Config.disposableATUpgrades
        if upgrades and #upgrades > 0
            and math.random() < (TPG.Config.disposableATUpgradeChance or 0) then
            local pick = upgrades[math.random(#upgrades)]
            if weapons.GetStored(pick) and TPG.GetWeapon("Special", pick) then
                gaveUpgrade = TPG.Loadout.GiveWeapon(ply, "Special", pick)
            end
        end
        if not gaveUpgrade and weapons.GetStored(atClass) then
            ply:Give(atClass)
        end
    end

    -- Underdog perks: a free smoke to cover the retreat (or the push), plus a
    -- medkit to patch up between fights.
    if TPG.Underdog and TPG.Underdog.IsPlayerUnderdog and TPG.Underdog.IsPlayerUnderdog(ply) then
        local smoke = TPG.Config.underdogSmokeClass or "weapon_ace_smokegrenade"
        if weapons.GetStored(smoke) then
            ply:Give(smoke)
        end

        local medkit = TPG.Config.underdogMedkitClass
        if medkit and medkit ~= "" and weapons.GetStored(medkit) then
            ply:Give(medkit)
        end
    end

    -- Play equip sound
    TPG.Util.PlaySound(ply, "acf_extra/tankfx/gnomefather/rack.wav")
end

-- Raise the player's clip + reserve of a weapon's primary ammo to the total
-- configured in TPG.WeaponConfig.AmmoTopUp, or -- for any Special-slot weapon
-- without an explicit entry -- to the SpecialAmmoMin floor. Launchers commonly
-- ship with DefaultClip = 1, including ones from add-on packs we can't list by
-- class; the category floor catches those too.
local function TopUpAmmo(ply, category, class, wep)
    local cfg = TPG.WeaponConfig
    local target = cfg.AmmoTopUp and cfg.AmmoTopUp[class]
    if not target and category == "Special" then
        target = cfg.SpecialAmmoMin
    end
    if not target then return end

    -- Losing hard? The underdog carries a couple of extra rockets.
    if TPG.Underdog and TPG.Underdog.GetAmmoBonus and target > 1 then
        target = target + TPG.Underdog.GetAmmoBonus(ply)
    end

    if not IsValid(wep) then wep = ply:GetWeapon(class) end
    if not IsValid(wep) then return end

    local ammoType = wep:GetPrimaryAmmoType()
    if ammoType < 0 then return end

    local have = math.max(wep:Clip1(), 0) + ply:GetAmmoCount(ammoType)
    if have < target then
        ply:GiveAmmo(target - have, ammoType, true)
    end
end

-- Returns true if it actually handed the player a weapon (so callers can tell
-- an empty/"none"/disabled pick from a real one -- e.g. the bonus AT).
function TPG.Loadout.GiveWeapon(ply, category, weaponId)
    local weapon = TPG.GetWeapon(category, weaponId)
    if not weapon or weapon.enabled == false then return false end

    -- Single weapon
    if weapon.class then
        TopUpAmmo(ply, category, weapon.class, ply:Give(weapon.class))
        return true
    end

    -- Multiple weapons (e.g., mines)
    if weapon.multipleClasses then
        for _, class in ipairs(weapon.multipleClasses) do
            TopUpAmmo(ply, category, class, ply:Give(class))
        end
        return true
    end

    -- Fallback weapon (e.g., disposable AT when no special selected)
    if weapon.fallbackClass then
        TopUpAmmo(ply, category, weapon.fallbackClass, ply:Give(weapon.fallbackClass))
        return true
    end

    return false
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