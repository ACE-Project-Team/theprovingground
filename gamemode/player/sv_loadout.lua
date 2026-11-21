--[[--
    Applying a player's chosen weapons and armor at spawn.

    Reads the loadout picks stored as PData by `core/sv_commands.lua`
    (`tpg_loadout`), charges for any premium picks (config/sh_gear.lua) through
    `TPG.Gear.Claim`, computes and sets movement speed from the armor/weapon
    penalties, hands out the actual weapons and ammo, and re-stamps a couple of
    ACE quirks (see @{tpg.loadout.StampSpeed}) that would otherwise silently
    override the speed just set. `TPG.Loadout.Apply` is the entry point, called
    once per spawn from `GM:PlayerSpawn` (player/sv_spawning.lua), last, after
    positioning.

    @module tpg.loadout
    @realm server
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
local function DenialMessage(ply, kind, id, reason, amount, category, fallback)
    local name = TPG.Gear.Name(kind, id)

    -- Say what they got INSTEAD, not just what they didn't get. A player who
    -- has set a fallback needs to know it fired; one who hasn't needs to know
    -- the setting exists, and the only place they'd find that out is here.
    local got = ""
    if category and fallback then
        if fallback ~= "none" then
            got = " Falling back to " .. TPG.Gear.Name("weapon", fallback) ..
                " (change it in the loadout menu's FALLBACK tab)."
        elseif category == "Special" then
            -- "none" in Special is not nothing: an empty Special is what earns
            -- the bonus tube further down Apply.
            got = " Falling back to the free AT tube."
        else
            got = " That slot will be empty - set a fallback in the loadout menu."
        end
    end

    if reason == "cooldown" then
        -- "You've used your run of these" rather than a bare number of seconds:
        -- the wait is the second half of the price, and a player who only ever
        -- sees the timer has no idea the lives were the first half.
        TPG.Util.ChatMessage(ply, "[TPG] " .. name .. ": you've used up your lives with it. " ..
            math.ceil(amount) .. "s until you can take another." .. got, Color(255, 200, 0))
    elseif reason == "afford" then
        TPG.Util.ChatMessage(ply, "[TPG] " .. name .. " costs " .. amount ..
            " pts and you have " .. (TPG.Economy and TPG.Economy.GetMoney(ply) or 0) .. "." .. got,
            Color(255, 200, 0))
    end
end

--[[
    What this player wants a slot to resolve to when its pick is refused.

    Chosen in the loadout menu's FALLBACK mode and saved as PData; falls back in
    turn to `TPG.WeaponConfig.FallbackLoadout`. Re-validated here rather than
    trusted from the save: the free/enabled set changes when an admin retunes a
    weapon or a pack is uninstalled, and a save made when the choice was legal
    would otherwise keep handing out something that no longer is.
]]
local function FallbackFor(ply, category)
    local saved = TPG.Util.GetPData(ply, "Fallback" .. category, nil)
    if isstring(saved) and TPG.Gear.FallbackAllowed(category, saved) then
        return saved
    end
    return TPG.Gear.DefaultFallback(category)
end

-- Returns the weapon id the player actually gets. The fallback is always free,
-- so a refusal resolves in one step and never cascades.
local function ResolveWeapon(ply, category, id)
    if not TPG.Gear.Claim then return id end   -- gear system absent; nothing is priced
    if not id or id == "none" then return id end

    -- Nothing to charge for a pick that wasn't going to be handed out anyway --
    -- GiveWeapon turns a missing or admin-disabled entry into nothing.
    local entry = TPG.GetWeapon(category, id)
    if not entry or entry.enabled == false then return id end

    local ok, reason, amount = TPG.Gear.Claim(ply, "weapon", id)
    if ok then return id end

    local fallback = FallbackFor(ply, category)
    DenialMessage(ply, "weapon", id, reason, amount, category, fallback)
    return fallback
end

local function ResolveArmor(ply, armorId)
    if not TPG.Gear.Claim then return armorId end
    local ok, reason, amount = TPG.Gear.Claim(ply, "armor", armorId)
    if ok then return armorId end

    DenialMessage(ply, "armor", armorId, reason, amount)
    return TPG.Gear.FreeArmor
end

--[[--
    Hold every ACE weapon the player carries to the speed the loadout set.

    weapon_ace_base's Think force-sets its owner's walk/run speed every tick
    from SWEP.NormalPlayerWalkSpeed / NormalPlayerRunSpeed (shared.lua Think).
    The base fills those in from the owner's real speed in its Deploy, but
    Deploy is just a method, and several ACE weapons define their own without
    ever calling the base's: weapon_ace_grenade, weapon_ace_smokegrenade and
    weapon_ace_slam all do. Those inherit the speed-forcing Think and keep the
    SWEP table's fallbacks, a flat 200 walk / 400 run (shared.lua:72).

    So pulling out a grenade, which every loadout carries, pinned the player
    to 200/400 on the SERVER for as long as it was out, and left them there.
    Most armour tiers sit near enough to those numbers to pass unnoticed; a
    Juggernaut is meant to move at 60/89 and instead sprinted at over three
    times its speed. Setting the speed before handing out weapons doesn't help,
    because these weapons never read it.

    Stamping the real numbers onto the weapons makes ACE's own Think arrive at
    the right answer whether or not the weapon ever snapshotted anything. Its
    CarrySpeedMul still applies on top, so per-weapon weight penalties (the
    SLAM's 0.6, say) survive.

    A no-op until @{tpg.loadout.Apply} has run at least once for this player
    (walk speed networked as 0 means "no loadout yet") and while the player is
    dead.

    @tparam Player ply
    @realm server
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

--[[--
    Strip and re-kit a player: weapons, armor, movement speed and ammo.

    Not on a team (spectator): only the default weapons and building tools, no
    team kit, no speed changes. On a team: reads the saved Primary/Secondary/
    Special/Armor PData picks (a legacy non-string save falls back to the
    default loadout), charges premium picks through `TPG.Gear.Claim` if that
    system is loaded (a denial swaps in the free equivalent and messages why),
    applies armor stats, computes and sets walk/run speed from the resulting
    armor + weapon penalties BEFORE handing out any weapon (ACE's weapon base
    snapshots the owner's speed on Deploy, so setting it after would let a
    weapon deploy against the stale pre-loadout speed), then gives the actual
    weapons, tops up their ammo, and hands out a consolation disposable AT only
    if the Special slot came up empty. Underdog perks (smoke, medkit) are added
    last. Finishes by publishing `pState.liveLoadout` (what the player is
    actually carrying, which can differ from the PData picks after a denial),
    clearing the `rekit` flag, restamping speed via @{tpg.loadout.StampSpeed}
    for weapons that never got a fresh Deploy snapshot, and syncing the gear
    menu's cooldowns.

    @tparam Player ply
    @realm server
]]
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
    primaryId   = ResolveWeapon(ply, "Primary",   primaryId)
    secondaryId = ResolveWeapon(ply, "Secondary", secondaryId)
    specialId   = ResolveWeapon(ply, "Special",   specialId)
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

    --[[
        Floor the total before it becomes a speed.

        Armour and weapon penalties are summed, and only one tier is heavy
        enough to reach the bottom: a Juggernaut (-40) with an ordinary kit
        (Primary -5, Special -10) landed on exactly 55 - 55 = 0, and an LMG
        (-15) took it negative. That is not "can't move" -- Source only clamps
        movement to max speed when max speed is above zero, so a walk speed of 0
        or less means NO limit and the player falls back to sv_maxspeed (320).
        The slowest thing in the game was the fastest, no matter what it held.

        Clamping the percentage rather than the two speeds keeps walk and run in
        proportion to each other.
    ]]
    local speedPercent = (TPG.Config.baseSpeedPercent + speedBonus) / 100
    speedPercent = math.max(speedPercent, (TPG.Config.minSpeedPercent or 15) / 100)

    local walkSpeed = math.max(math.Round(TPG.Config.baseWalkSpeed * speedPercent * 2), 1)
    local runSpeed  = math.max(math.Round(TPG.Config.baseRunSpeed * speedPercent * 1.7), 1)
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

    -- The resupply floors for this life get rebuilt by the giving code below;
    -- drop last life's (possibly different loadout, possibly different NPC
    -- count) so a stale pool can't be topped up by Resupply.
    TPG.State.GetPlayer(ply).ammoFull = nil

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

    -- ACE wearables (helmet/vest/suit) once the armor tier is final -- it
    -- decides which helmet, if any, goes on.
    if TPG.Wearables and TPG.Wearables.ApplyFor then
        TPG.Wearables.ApplyFor(ply, armorId)
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

--[[
    Extra rounds when the field is full of NPCs.

    A rifleman burns through his spawn load killing bots long before the round
    ends. Each live bot adds npcAmmoBonus of the weapon's "full" total on top
    of it, capped at npcAmmoBonusMax: with the defaults (0.05 / 0.6) a dozen
    bots means carrying 60% more of everything. Both the spawn top-up and the
    base resupply read the same number, so the recorded "full" already includes
    the bonus -- resupply never needs to recompute it.
]]
local function NpcAmmoBonus(ply, base)
    local bots = TPG.Bots and TPG.Bots.list and #TPG.Bots.list or 0
    if bots <= 0 or base <= 0 then return 0 end

    local frac = math.min(bots * (TPG.Config.npcAmmoBonus or 0),
        TPG.Config.npcAmmoBonusMax or 0)
    return math.ceil(base * frac)
end

--[[
    Remember the per-ammo-type "full" total a spawn handed out.

    Resupply tops the player back up to this later -- the configured floor for
    classes that have one, otherwise whatever the weapon actually shipped with
    (plus the NPC bonus). Recorded per ammo TYPE, not per weapon, because ammo
    pools are shared: the three ACE mines all draw from one pool, and refilling
    each class separately would triple it.
]]
local function RecordAmmoFull(ply, wep, total)
    if not IsValid(wep) then return end
    local ammoType = wep:GetPrimaryAmmoType()
    if ammoType < 0 then return end

    local pState = TPG.State.GetPlayer(ply)
    if not pState.ammoFull then pState.ammoFull = {} end
    pState.ammoFull[ammoType] = math.max(pState.ammoFull[ammoType] or 0, total)
end

-- Raise the player's clip + reserve of a weapon's primary ammo to the total
-- configured in TPG.WeaponConfig.AmmoTopUp, or -- for any Special-slot weapon
-- without an explicit entry -- to the SpecialAmmoMin floor. Launchers commonly
-- ship with DefaultClip = 1, including ones from add-on packs we can't list by
-- class; the category floor catches those too. Returns the rounds actually
-- given so the resupply bookkeeping can report a real top-up.
--[[
    Give a weapon and measure how much ammo the give actually shipped.

    `ply:Give` leaves the engine to grant the SWEP's default clip + reserve,
    and GetAmmoCount AFTER the give also counts whatever reserve the player
    still carried from a previous life -- StripWeapons does not clear the ammo
    inventory. Reading the post-give total as "what this weapon ships with"
    therefore compounds leftovers into every re-apply (the recorded "full"
    crept upward every respawn until this was measured live). The shipped
    figure is the DELTA across the give, plus the loaded magazine.
]]
local function GiveMeasured(ply, class)
    local stored   = weapons.GetStored(class)
    local ammoName = stored and stored.Primary and stored.Primary.Ammo
    local ammoType = ammoName and game.GetAmmoID(ammoName) or -1
    local before   = ammoType >= 0 and ply:GetAmmoCount(ammoType) or 0

    local wep = ply:Give(class)
    if not IsValid(wep) then return wep, 0 end

    local shipped = 0
    if ammoType >= 0 then
        shipped = math.max(wep:Clip1(), 0) + (ply:GetAmmoCount(ammoType) - before)
    end
    return wep, shipped
end

local function TopUpAmmo(ply, category, class, wep, shipped)
    local cfg = TPG.WeaponConfig
    local target = cfg.AmmoTopUp and cfg.AmmoTopUp[class]
    if not target and category == "Special" then
        target = cfg.SpecialAmmoMin
    end

    if not IsValid(wep) then wep = ply:GetWeapon(class) end
    if not IsValid(wep) then return 0 end

    local ammoType = wep:GetPrimaryAmmoType()
    if ammoType < 0 then return 0 end

    -- Losing hard? The underdog carries a couple of extra rockets.
    if target and TPG.Underdog and TPG.Underdog.GetAmmoBonus and target > 1 then
        target = target + TPG.Underdog.GetAmmoBonus(ply)
    end

    --[[
        "Full" is whatever the weapon ships with or the floor, whichever is
        bigger, grown by the NPC bonus. Floored classes get the same treatment
        as everything else: a 6-round AT-4 floor with a dozen bots on the map
        becomes 9-10. Weapons with no floor at all (every primary) still get
        the bonus on their shipped load -- infantry ammo is exactly the thing
        that runs out against NPCs.
    ]]
    local base = math.max(shipped or 0, target or 0)
    local full = base + NpcAmmoBonus(ply, base)

    if full <= 0 then return 0 end
    RecordAmmoFull(ply, wep, full)

    -- Top UP to the recorded total: a reserve the player still carries from a
    -- previous life counts toward it, so the give may shrink to nothing.
    local have = math.max(wep:Clip1(), 0) + ply:GetAmmoCount(ammoType)
    local given = math.max(full - have, 0)
    if given > 0 then
        ply:GiveAmmo(given, ammoType, true)
    end
    return given
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

    -- The exact total scales with NPC presence like any floor does.
    total = total + NpcAmmoBonus(ply, total)
    RecordAmmoFull(ply, wep, total)

    ply:RemoveAmmo(ply:GetAmmoCount(ammoType), ammoType)
    ply:GiveAmmo(math.max(total - (loaded or 0), 0), ammoType, true)
end

--- Give `ply` the weapon(s) behind `weaponId` in `category`, topping up ammo
-- to the configured floor (or, for `exactAmmo` entries like the ACE mines, to
-- an exact pool total rather than merely raising it).
-- @tparam Player ply
-- @tparam string category "Primary", "Secondary" or "Special".
-- @tparam string weaponId Looked up via `TPG.GetWeapon`.
-- @treturn boolean True if it actually handed over a weapon, so callers can
--  tell an empty/"none"/disabled pick from a real one, e.g. the bonus AT logic
--  in @{tpg.loadout.Apply} that only fires when this returns false.
-- @realm server
function TPG.Loadout.GiveWeapon(ply, category, weaponId)
    local weapon = TPG.GetWeapon(category, weaponId)
    if not weapon or weapon.enabled == false then return false end

    -- Single weapon
    if weapon.class then
        TopUpAmmo(ply, category, weapon.class, GiveMeasured(ply, weapon.class))
        return true
    end

    -- Multiple weapons (e.g., mines)
    if weapon.multipleClasses then
        local first
        for _, class in ipairs(weapon.multipleClasses) do
            local given, shipped = GiveMeasured(ply, class)
            if not IsValid(first) then first = given end

            -- An exact total replaces the top-up entirely: topping each class up
            -- first and then trimming the pool would just be the same arithmetic
            -- done twice.
            if not weapon.exactAmmo then
                TopUpAmmo(ply, category, class, given, shipped)
            end
        end

        if weapon.exactAmmo then
            SetExactAmmo(ply, first, weapon.exactAmmo, #weapon.multipleClasses)
        end
        return true
    end

    -- Fallback weapon (e.g., disposable AT when no special selected)
    if weapon.fallbackClass then
        TopUpAmmo(ply, category, weapon.fallbackClass, GiveMeasured(ply, weapon.fallbackClass))
        return true
    end

    return false
end

--- Set `ply`'s model, health and armor from the `armorId` tier's stats
-- (`TPG.GetArmor`). Sets both current and max health to the tier's value, so
-- an armor change also resets the health pool rather than merely capping it.
-- @tparam Player ply
-- @tparam number armorId
-- @realm server
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
--[[--
    Refill a player's carried ammo to the "full" totals this life spawned
    with.

    Walks the held weapons, reads each one's primary ammo type, and tops the
    pool up to `pState.ammoFull` (recorded by the giving code: configured floor
    or shipped load, whichever was bigger, plus the NPC bonus). Weapon lookups
    are avoided entirely -- one `GetWeapons` call, one ammo read per weapon --
    and the whole thing only runs when `ResupplyTick` decides it's due, so the
    cost is a few table reads every resupplyTime seconds per parked player,
    not per tick.

    Weapons that weren't part of the recorded loadout (pickups, tools,
    grenades, the consolation AT tube) have no recorded full and are skipped,
    which also keeps resupply from minting ammo for things the loadout never
    issued.

    @tparam Player ply
    @treturn number Rounds actually given (0 when already full).
    @realm server
]]
function TPG.Loadout.Resupply(ply)
    local pState = TPG.State.GetPlayer(ply)
    local full = pState.ammoFull
    if not full then return 0 end

    local given = 0
    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) then
            local ammoType = wep:GetPrimaryAmmoType()
            local total = ammoType >= 0 and full[ammoType]
            if total then
                local have = math.max(wep:Clip1(), 0) + ply:GetAmmoCount(ammoType)
                if have < total then
                    ply:GiveAmmo(total - have, ammoType, true)
                    given = given + total - have
                end
            end
        end
    end
    return given
end

--[[--
    Accumulate time-in-safezone and fire the resupply when it's due.

    Called every tick from `TPG_ProtectionThink`, which already knows the
    player is alive, on a team, and inside their own zone -- the expensive part
    is shared. Inside the zone this is one table read and one field write per
    tick; `Resupply` itself only runs when the wait elapses. Leaving the zone
    for a tick resets the clock.

    @tparam Player ply
    @tparam boolean inSafezone Whether the player is in their team's zone.
    @realm server
]]
function TPG.Loadout.ResupplyTick(ply, inSafezone)
    local pState = TPG.State.GetPlayer(ply)
    if not inSafezone then
        if pState.resupplyFor then pState.resupplyFor = nil end
        return
    end

    local waited = (pState.resupplyFor or 0) + FrameTime()
    if waited < (TPG.Config.resupplyTime or 15) then
        pState.resupplyFor = waited
        return
    end

    pState.resupplyFor = nil
    if TPG.Loadout.Resupply(ply) > 0 then
        TPG.Util.ChatMessage(ply, "[TPG] Resupplied ammo.", Color(0, 255, 0))
        TPG.Util.PlaySound(ply, "items/ammo_pickup.wav")
    end
end
