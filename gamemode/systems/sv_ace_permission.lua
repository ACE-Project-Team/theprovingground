--[[--
    TPG's ACE damage-permission mode.

    ACE decides whether one of its shells is allowed to hurt a given entity by
    asking the *active permission mode* -- a single function registered with
    `ACE.Permissions.RegisterMode`. TPG never registered one, so ACE ran its
    stock `none` mode, which is literally `return true`: damage everything.
    That, and not a missing feature, is why a vehicle parked in spawn could be
    shelled from outside while its owner standing next to it could not be hurt.
    Players survive through a separate, un-gated path (`sv_acfbase.lua`'s
    `canDamagePlayer`), which is the whole asymmetry.

    Two switches have to be on for any of this to matter, and neither was:

      * the `ace_enable_dp` convar, which defaults to 0 in ACE, and
      * an actual permission mode, which defaults to `none`.

    A 2x2x2 sweep of convar x mode x godmode confirmed exactly one combination
    protects a prop, so this module sets both and registers the mode below.

    Why a mode and not a `GM:EntityTakeDamage` hook: ACE decrements
    `Entity.ACF.Health` itself (`sv_acfdamage.lua`) and only incidentally calls
    `Entity:TakeDamage()`. Blocking the engine damage event leaves the ACE
    health pool draining anyway, so the vehicle still dies. The permission mode
    is the only layer that actually stops it.

    Requires a CPPI provider. ACE consumes CPPI and does not supply it; without
    one, `ACE.Permissions.CanDamage` returns "allowed" before any mode is
    consulted, and there is nothing a mode can do about it. See the startup
    check at the bottom.

    @module tpg.ace_permission
    @realm server
]]

TPG.ACEPermission = {}

local MODE_NAME = "tpg"
local MODE_DESC = "TPG: entities are protected inside their owner's team safezone, "
               .. "and while their owner's spawn protection is running."

-- ACE loads from addons/, TPG from gamemodes/, and the order between them is
-- not guaranteed. Rather than guess, retry for a bounded window and say so
-- clearly if ACE never turns up.
local REGISTER_RETRY   = 1
local REGISTER_ATTEMPTS = 15

--[[
    The protection rule itself, in one place.

    Two separate ACE paths have to answer this same question -- damage, and
    kinetic shove -- and when they each carried their own copy they disagreed:
    the shove path only knew about the safezone box, so a build out in the field
    under its owner's spawn protection took no damage and still got flung across
    the map. One predicate, two callers.

    This deliberately reads the TARGET's owner and nothing else. The attacker's
    own state is never consulted, which is what makes protection one-way: while
    your countdown is running you can shoot an enemy and they cannot shoot back.
    That mirrors how player protection already behaves -- `GodEnable` in
    sv_protection.lua blocks incoming damage without touching outgoing.
]]
local function isProtected(owner, ent)
    -- Before a round publishes spawns there is no "outside" to be on the wrong
    -- side of, so nothing is fair game yet. This matches what
    -- TPG.Protection.IsInSafezone does for players during the wait window --
    -- otherwise the two disagree and props are the only thing you can destroy
    -- while the server is waiting for players.
    local greenSpawn = TPG.State.GetSpawn(TEAM_GREEN)
    local redSpawn   = TPG.State.GetSpawn(TEAM_RED)
    if not greenSpawn and not redSpawn then return true end

    -- Protected inside your own team's safezone. Deliberately the ENTITY's
    -- position, not the owner's: the point is that a build parked in spawn is
    -- safe whether or not its owner is standing next to it.
    local zoneTeam = TPG.Protection.GetSafezoneTeam(ent:GetPos())
    if zoneTeam and zoneTeam == owner:Team() then return true end

    -- Protected while the owner's spawn-protection countdown is running, so a
    -- vehicle keeps cover for exactly as long as its driver does on the way out
    -- of spawn. No separate vehicle timer and no new state -- it reads the same
    -- pState.spawnProtection that sv_protection.lua already counts down.
    local pState = TPG.State.GetPlayer(owner)
    if pState and (pState.spawnProtection or 0) > 0 then return true end

    return false
end

--[[
    The mode function. ACE calls this for every entity a shell could hurt.

    Contract (ACE's, not ours): return TRUE to allow the damage, FALSE to
    protect the entity. Getting this backwards makes the map indestructible,
    which is a quieter failure than it sounds, so it is worth restating here.

    ACE only calls this once it has resolved `owner` and `attacker` to real
    players -- entities with no player owner never reach a mode.
]]
local function tpgPermission(owner, attacker, ent)
    if not IsValid(ent) then return false end

    -- People and NPCs are somebody else's problem: player damage runs through
    -- ACE's separate canDamagePlayer path, and TPG's own god mode already
    -- governs it. Answering here would double up on that.
    if ent:IsPlayer() or ent:IsNPC() then return true end

    return not isProtected(owner, ent)
end

--[[
    ACE's own AABB safezones, loaded per map from data/acf/safezones/<map>.txt,
    do not line up with TPG's spherical ones. TPG's mode never consults them, so
    they cannot change who takes damage -- but ACE draws them for players
    (`visualizeSafeZones`), and a visible box that is not the safezone anyone is
    actually protected by is worse than no box at all. Clear them in memory so
    there is one safezone system in play rather than two disagreeing ones.

    The data files are never touched. A server that stops running TPG gets its
    safezones back, unmodified, on the next boot.

    Timing matters here and cost a bug the first time: ACE loads these in its
    own `Initialize` hook, which fires well after this file is included, so
    suppressing once at install time silently no-ops. ACE only ever populates
    them from that one hook (the CleanUpMap path re-draws but does not reload),
    so a bounded retry that stops on the first success is enough.
]]
local function suppressACESafezones()
    local perms = ACE and ACE.Permissions
    if not perms then return false end

    -- ACE's "no safezones" sentinel is `false`, not nil (sv_acfpermission.lua:11),
    -- and it lazily creates an empty table at :197. Neither is anything to
    -- suppress, so test for actual contents rather than truthiness.
    local sz = perms.Safezones
    if not sz or not next(sz) then return false end

    TPG.ACEPermission.SuppressedSafezones = sz
    perms.Safezones = false   -- back to ACE's own sentinel, not nil
    print("[TPG] Suppressed ACE's map safezones in memory; TPG's spawn radius governs instead.")
    return true
end

--- Register TPG's permission mode with ACE and make it the active one.
-- Idempotent, and safe to call before ACE has finished loading -- it retries.
-- @treturn boolean True once the mode is registered and active.
-- @realm server
function TPG.ACEPermission.Install()
    local perms = ACE and ACE.Permissions
    if not perms or not perms.RegisterMode then return false end
    if perms.Modes and perms.Modes[MODE_NAME] and perms.DamagePermission == perms.Modes[MODE_NAME] then
        return true
    end

    -- The last argument ACE calls `defaultaction` is what CanDamage falls back
    -- to for entities with no player owner -- map brushes, world props, debris.
    -- True keeps those destructible, which is the behaviour everyone expects;
    -- false would quietly armour the map.
    perms.RegisterMode(tpgPermission, MODE_NAME, MODE_DESC, false, nil, true, false)

    -- RegisterMode only activates a mode if it was registered as the default
    -- or the map has it saved in data/acf/permissions/. Neither is true here,
    -- and TPG should not be writing to ACE's data directory to arrange it, so
    -- set the active mode directly.
    perms.DamagePermission = perms.Modes[MODE_NAME]
    perms.DefaultPermission = MODE_NAME

    -- Without this the mode is never consulted: CanDamage returns "allowed"
    -- on the convar check before it reaches any mode at all.
    local dp = GetConVar("ace_enable_dp")
    if dp then dp:SetInt(1) end

    if perms.ResendPermissionsOnChanged then perms.ResendPermissionsOnChanged() end

    print("[TPG] ACE damage permission mode \"" .. MODE_NAME .. "\" registered and active (ace_enable_dp 1).")

    if not CPPI then
        print("[TPG] ================================================================")
        print("[TPG] WARNING: no CPPI prop-protection addon is installed.")
        print("[TPG] ACE cannot resolve who owns a prop, so it allows all damage")
        print("[TPG] before TPG's permission mode is ever consulted - safezone")
        print("[TPG] protection for vehicles will NOT work. Install NadmodPP, FPP")
        print("[TPG] or SPP. Player spawn protection is unaffected.")
        print("[TPG] ================================================================")
    end

    return true
end

do
    local attempts = 0
    timer.Create("TPG_ACEPermissionInstall", REGISTER_RETRY, REGISTER_ATTEMPTS, function()
        attempts = attempts + 1
        if TPG.ACEPermission.Install() then
            timer.Remove("TPG_ACEPermissionInstall")
        elseif attempts >= REGISTER_ATTEMPTS then
            print("[TPG] ERROR: ACE.Permissions never appeared; vehicles are unprotected in safezones.")
        end
    end)

    -- Separate from the install retry above because it has a different finish
    -- line: the mode is active almost immediately, while the safezones do not
    -- exist until ACE's Initialize runs. A map with no safezone file never
    -- satisfies this one, which is fine -- it just runs out its attempts.
    timer.Create("TPG_ACESafezoneSuppress", REGISTER_RETRY, REGISTER_ATTEMPTS, function()
        if suppressACESafezones() then timer.Remove("TPG_ACESafezoneSuppress") end
    end)
end

--[[
    Blocking the damage is only half of it. ACE applies kinetic shove
    separately and does not route it through the permission system, so without
    this a shell that does no damage to a protected build still throws it
    across the map.

    `ACE.KEShove` and the global `ACE_KEShove` are the same function (the ACE
    table aliases dotted names onto the underscored globals), and it is the real
    HE/kinetic push path -- sv_acfdamage.lua calls it at :347, :371 and :978
    with the firing player as the inflictor. So this hook does sit on live
    enemy fire, not just on the recoil call.

    Same rule as the damage mode, one difference: KEShove hands us the target
    and the inflictor rather than a resolved owner, so ownership is looked up
    here.
]]
hook.Add("ACE_KEShove", "TPG_SafezoneNoShove", function(target, _, _, _, inflictor)
    if not IsValid(target) then return end
    if target:IsPlayer() then return end

    local owner = target.CPPIGetOwner and target:CPPIGetOwner() or nil
    if not (IsValid(owner) and owner:IsPlayer()) then return end
    if not isProtected(owner, target) then return end

    -- A gun's own recoil (acf_gun/init.lua:848) is a shove with no inflictor
    -- argument at all -- it is the one caller that omits it. "Nobody pushed
    -- this" therefore means self-inflicted, and blocking it would freeze your
    -- own recoil while you sat in spawn.
    if not IsValid(inflictor) then return end

    -- Likewise a shove that traces back to the owner themselves.
    local shooter = inflictor:IsPlayer() and inflictor
        or (inflictor.CPPIGetOwner and inflictor:CPPIGetOwner() or nil)
    if IsValid(shooter) and shooter == owner then return end

    return false
end)
