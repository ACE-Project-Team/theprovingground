--[[
    Player Loadout System
]]

TPG.Loadout = {}

--[[
    Premium picks (config/sh_gear.lua).

    A handful of items cost something to take -- points under the per-player
    economy, a personal cooldown otherwise. Both are charged HERE, at spawn,
    rather than in the loadout menu: the menu only records a preference, and
    charging on selection would bill players for kit they never got (menu open
    at round end, kicked before spawning, admin disabling the weapon in between).

    A denied pick silently becomes the free equivalent and says why in chat.
    Nobody spawns weaponless because they couldn't afford a Javelin.
]]
local function DenialMessage(ply, kind, id, reason, amount)
    local name = TPG.Gear.Name(kind, id)

    if reason == "cooldown" then
        TPG.Util.ChatMessage(ply, "[TPG] " .. name .. " is on cooldown for another " ..
            math.ceil(amount) .. "s.", Color(255, 200, 0))
    elseif reason == "afford" then
        TPG.Util.ChatMessage(ply, "[TPG] " .. name .. " costs " .. amount ..
            " pts and you have " .. (TPG.Economy and TPG.Economy.GetMoney(ply) or 0) .. ".",
            Color(255, 200, 0))
    end
end

-- Returns the weapon id the player actually gets. `fallback` must be free.
local function ResolveWeapon(ply, category, id, fallback)
    if not TPG.Gear.Claim then return id end   -- gear system absent; nothing is priced
    if not id or id == "none" then return id end

    -- Nothing to charge for a pick that wasn't going to be handed out anyway --
    -- GiveWeapon turns a missing or admin-disabled entry into nothing.
    local entry = TPG.GetWeapon(category, id)
    if not entry or entry.enabled == false then return id end

    local ok, reason, amount = TPG.Gear.Claim(ply, "weapon", id)
    if ok then return id end

    DenialMessage(ply, "weapon", id, reason, amount)
    return fallback
end

local function ResolveArmor(ply, armorId)
    if not TPG.Gear.Claim then return armorId end
    local ok, reason, amount = TPG.Gear.Claim(ply, "armor", armorId)
    if ok then return armorId end

    DenialMessage(ply, "armor", armorId, reason, amount)
    return TPG.Gear.FreeArmor
end

--[[
    Hold every ACE weapon the player carries to the speed the loadout set.

    weapon_ace_base's Think force-sets its owner's walk/run speed every tick
    from SWEP.NormalPlayerWalkSpeed / NormalPlayerRunSpeed (shared.lua Think).
    The base fills those in from the owner's real speed in its Deploy -- but
    Deploy is just a method, and several ACE weapons define their own without
    ever calling the base's: weapon_ace_grenade, weapon_ace_smokegrenade and
    weapon_ace_slam all do. Those inherit the speed-forcing Think and keep the
    SWEP table's fallbacks, a flat 200 walk / 400 run (shared.lua:72).

    So pulling out a grenade -- which every loadout carries -- pinned the player
    to 200/400 on the SERVER for as long as it was out, and left them there.
    Most armour tiers sit near enough to those numbers to pass unnoticed; a
    Juggernaut is meant to move at 60/89 and instead sprinted at over three
    times its speed. Setting the speed before handing out weapons doesn't help,
    because these weapons never read it.

    Stamping the real numbers onto the weapons makes ACE's own Think arrive at
    the right answer whether or not the weapon ever snapshotted anything. Its
    CarrySpeedMul still applies on top, so per-weapon weight penalties (the
    SLAM's 0.6, say) survive.
]]
function TPG.Loadout.StampSpeed(ply)
    if not IsValid(ply) or not ply:Alive() then return end

    -- Set by Apply, below. Zero means no loadout has run for this player yet.
    local walk = ply:GetNWInt("TPG_WalkSpeed", 0)
    if walk <= 0 then return end
    local run = ply:GetNWInt("TPG_RunSpeed", walk)

    for _, wep in ipairs(ply:GetWeapons()) do
        if wep.NormalPlayerWalkSpeed then
            wep.NormalPlayerWalkSpeed = walk
            wep.NormalPlayerRunSpeed  = run
        end
    end

    ply:SetWalkSpeed(walk)
    ply:SetRunSpeed(run)
end

--[[
    Re-stamp whenever the held weapon changes.

    Two things need it. A weapon that arrives outside Apply (the underdog smoke,
    a pickup) is unstamped until now. And the base's own Deploy re-snapshots
    GetWalkSpeed() -- which by then is the PREVIOUS weapon's already-multiplied
    speed -- so switching back and forth between two weapons with a
    CarrySpeedMul below 1 ratchets the player slower on every swap. Restoring
    the true speed here, before the incoming weapon deploys, fixes that snapshot
    too.

    PlayerSwitchWeapon fires only on an actual switch, and SWEP:Think only runs
    for the active weapon, so this is the one moment that matters -- no per-tick
    cost.
]]
hook.Add("PlayerSwitchWeapon", "TPG_StampSpeed", function(ply)
    TPG.Loadout.StampSpeed(ply)
end)

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

    -- Charge for the premium picks first: a denial swaps in a different item,
    -- and the swap changes the speed maths below.
    primaryId   = ResolveWeapon(ply, "Primary",   primaryId,   dl.Primary)
    secondaryId = ResolveWeapon(ply, "Secondary", secondaryId, dl.Secondary)
    specialId   = ResolveWeapon(ply, "Special",   specialId,   "none")
    armorId     = ResolveArmor(ply, armorId)

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
    local walkSpeed = math.Round(TPG.Config.baseWalkSpeed * speedPercent * 2)
    local runSpeed  = math.Round(TPG.Config.baseRunSpeed * speedPercent * 1.7)
    ply:SetWalkSpeed(walkSpeed)
    ply:SetRunSpeed(runSpeed)

    --[[
        Publish the same two numbers to the client, which needs them to predict
        movement correctly -- see player/cl_movement.lua. Without this a
        Juggernaut felt like it was sprinting even though the server had it
        crawling, because the client was predicting against ACE's fallback
        speeds instead of the ones set here.
    ]]
    ply:SetNWInt("TPG_WalkSpeed", walkSpeed)
    ply:SetNWInt("TPG_RunSpeed", runSpeed)

    -- Give weapons
    TPG.Loadout.GiveWeapon(ply, "Primary", primaryId)
    TPG.Loadout.GiveWeapon(ply, "Secondary", secondaryId)
    local gaveSpecial = TPG.Loadout.GiveWeapon(ply, "Special", specialId)

    -- Consolation disposable AT: only for players whose Special slot came up
    -- EMPTY -- no pick, or a pick that's been disabled by an admin. Nobody
    -- should be completely unable to answer a tank, but handing a free tube to
    -- someone who already chose a launcher just made the Special slot a
    -- formality: everyone had AT regardless, so the pick cost nothing to skip
    -- and the fast "none" loadout was strictly better. Given last, after the
    -- speed snapshot, so it doesn't override movement. Small chance to roll a
    -- real launcher (stinger/javelin) instead, which goes through GiveWeapon so
    -- it gets the Special ammo floor.
    local atClass = TPG.Config.disposableATClass
    if not gaveSpecial and atClass and atClass ~= "" then
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

    local pState = TPG.State.GetPlayer(ply)

    --[[
        What this player is ACTUALLY carrying, as opposed to what they've got
        selected in the menu. The two differ whenever a pick was made since the
        last spawn -- or when a premium pick was denied above and quietly became
        the free one -- and the menu needs to know which, so it can say "equipped"
        on the thing in your hands and "on respawn" on the thing that isn't.
    ]]
    pState.liveLoadout = {
        Primary   = primaryId,
        Secondary = secondaryId,
        Special   = specialId,
        Armor     = armorId,
    }

    -- The re-kit flag covers exactly one death-and-respawn (core/sv_commands.lua
    -- sets it, the stats and gear systems read it on the death). Cleared here,
    -- at the end of the spawn it was set for, so the NEXT death is a real one.
    pState.rekit = nil

    -- Last, once every weapon is in hand: hold them all to the speed set above.
    -- See StampSpeed -- grenades and mines would otherwise force 200/400.
    TPG.Loadout.StampSpeed(ply)

    -- Refresh the menu's cooldown countdowns with whatever this spawn just
    -- started (or didn't).
    if TPG.Gear.Sync then TPG.Gear.Sync(ply) end

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

--[[
    Set a shared ammo pool to an exact total, rather than raising it to a floor.

    The three ACE mines all draw from one ammo type ("CombineHeavyCannon"), and
    each ships DefaultClip 11, so handing out the set stacked 33 mines into that
    single pool. TopUpAmmo can't fix that -- it only ever raises -- so this
    clears the pool and refills it to the configured total.

    `loaded` is subtracted because each mine arrives with one round already in
    its clip, and those count towards what the player is carrying.
]]
local function SetExactAmmo(ply, wep, total, loaded)
    if not IsValid(wep) then return end

    local ammoType = wep:GetPrimaryAmmoType()
    if ammoType < 0 then return end

    ply:RemoveAmmo(ply:GetAmmoCount(ammoType), ammoType)
    ply:GiveAmmo(math.max(total - (loaded or 0), 0), ammoType, true)
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
        local first
        for _, class in ipairs(weapon.multipleClasses) do
            local given = ply:Give(class)
            if not IsValid(first) then first = given end

            -- An exact total replaces the top-up entirely: topping each class up
            -- first and then trimming the pool would just be the same arithmetic
            -- done twice.
            if not weapon.exactAmmo then
                TopUpAmmo(ply, category, class, given)
            end
        end

        if weapon.exactAmmo then
            SetExactAmmo(ply, first, weapon.exactAmmo, #weapon.multipleClasses)
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