--[[--
    Crediting vehicle kills that never produce a player death.

    Every kill reward in TPG rides `PlayerDeath`: tickets, economy, rating.
    So the oldest exploit in the book -- undo or delete your tank while it is
    dying -- costs the attacker everything and the owner nothing. The tank was
    already dead; it just never made it to a PlayerDeath.

    This file keeps a small per-contraption damage ledger and marks a
    contraption DOOMED once it has lost at least `vehicleKillMassFrac` of its
    peak mass within `conKillWindow` seconds of taking enemy fire. When a
    doomed contraption ends -- whether the enemy finished it or the owner
    pressed undo, used the remover, or an admin cleaned it -- the kill is
    credited exactly once through `hook.Run("TPG_VehicleKilled")`. There is no
    need to distinguish "combat removal" from "owner removal": doom already
    requires recent enemy damage, and a tank that was literally dead counts
    the same either way. Removing a healthy tank still does nothing, because
    no enemy damage means no ledger and no doom.

    Performance shape: everything is event-driven -- no timers, no Think. The
    damage hook rides `EntityTakeDamage` (one CFW lookup + a few table writes,
    same hook TPG already uses for the combat clock); the CFW contraption
    events (`entityRemoved`, `entityAdded`, `split`, `merged`, `removed`) do a
    nil check and return early for undamaged builds. Doom accounting is a
    sum of removed-entity mass (`ent._mass`, CFW's own cached figure), not a
    read of `con.totalMass`, because `entityRemoved` fires mid-teardown with
    the total still being subtracted. ACE point totals are the expensive lazy
    read, so the kill value comes from the same per-player usage snapshot the
    player-kill ticket drain already uses -- never a forced rebuild.

    Ledger fields live on the contraption object: `TPG_VK` (shared across split
    fragments so the kill can only be paid once per fight), `TPG_VKPeak`
    (per-contraption peak mass), `TPG_VKMassLost` (per-contraption sum of
    removed mass) and `TPG_VKDoomAt` (per-contraption doom timestamp, cleared
    if the mass is ever rebuilt).

    Credit: the top enemy contributor takes the kill. Other contributors who
    dealt at least `vehicleKillAssistFrac` of the total enemy damage ride
    along as assists on the same `TPG_VehicleKilled` call (5th argument) --
    they bank a session assist and `vehicleKillAssistPay` of the kill reward,
    so a two-man takedown doesn't leave the second gun empty-handed.

    @module tpg.vehiclekill
    @realm server
]]

TPG.VehicleKill = {}

--- Seconds an enemy hit stays "fresh" for: doom can only be set while the last
-- enemy hit is this recent, and the kill is only paid within the same window
-- of the doom timestamp. Deleting a wreck half a minute after the fight is
-- cleanup, not kill-dodging.
-- @tparam number s
local function KillWindow() return TPG.Config.conKillWindow or 30 end

--- Fraction of peak mass lost that counts as "literally dead".
local function DoomFrac() return TPG.Config.vehicleKillMassFrac or 0.5 end

-- ── Debug trace (temporary; for in-game testing) ─────────────────────────────

local cvDebug = CreateConVar("tpg_vk_debug", "0", { FCVAR_ARCHIVE },
    "Trace the vehicle-kill ledger: hits, doom evals, ammo bands and credit.")

-- Console-only line for per-event spam (every damage event, every removal).
local function Dbg(fmt, ...)
    if not cvDebug:GetBool() then return end
    print(string.format("[VK] " .. fmt, ...))
end

-- Decision-level line: console AND chat, so it is visible without the console.
local function DbgChat(fmt, ...)
    if not cvDebug:GetBool() then return end
    local msg = string.format("[VK] " .. fmt, ...)
    print(msg)
    if TPG.Util and TPG.Util.ChatBroadcast then
        TPG.Util.ChatBroadcast(msg, Color(140, 220, 255))
    end
end

-- Find an NPC in the damage chain, walking the same owner hops the player
-- resolver does: npc gun -> npc -> (nothing). Used by the debug tally so an
-- NPC firing a gun it owns still gets named.
local function ResolveNpc(dmg)
    local att = dmg:GetAttacker()
    for _ = 1, 3 do
        if not IsValid(att) then
            att = dmg:GetInflictor()
            if not IsValid(att) then return nil end
        end
        if att.IsNPC and att:IsNPC() then return att end
        if att.IsPlayer and att:IsPlayer() then return nil end

        local owner = TPG.Util.GetOwner(att)
        if owner then
            att = owner
        elseif att.GetOwner and IsValid(att:GetOwner()) then
            att = att:GetOwner()
        else
            return nil
        end
    end
    return nil
end

-- The same reward curve the economy applies, recomputed from its config so
-- the debug quote matches the real payout.
local function DbgKillReward(value)
    local c = (TPG.Economy and TPG.Economy.Config) or {}
    return math.min((c.killRewardBase or 360) + (value or 0) * (c.killRewardVehFrac or 0.072),
                    c.killRewardMax or 3600)
end

-- What each NPC that shot this contraption would have been paid, had it been
-- a player: top contributor takes the kill, >=15% share riders take assists.
local function DbgNpcOutcome(con, value)
    if not cvDebug:GetBool() or not con.TPG_VKNpc then return end

    local rows, total = {}, 0
    for npc, dmg in pairs(con.TPG_VKNpc) do
        rows[#rows + 1] = { npc = npc, dmg = dmg }
        total = total + dmg
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b) return a.dmg > b.dmg end)

    local killPay = DbgKillReward(value)
    local assistPay = killPay * (TPG.Config.vehicleKillAssistPay or 0.25)
    local minShare = (TPG.Config.vehicleKillAssistFrac or 0.15) * total

    for i, r in ipairs(rows) do
        local name = IsValid(r.npc) and r.npc:GetClass() or "npc(gone)"
        if i == 1 then
            DbgChat("npc %s dealt %.0f (%.0f%%) - would take the kill: +%d pts",
                name, r.dmg, 100 * r.dmg / total, killPay)
        elseif r.dmg >= minShare then
            DbgChat("npc %s dealt %.0f (%.0f%%) - would assist: +%d pts",
                name, r.dmg, 100 * r.dmg / total, assistPay)
        else
            Dbg("npc %s dealt %.0f (%.0f%%) - below assist share, nothing",
                name, r.dmg, 100 * r.dmg / total)
        end
    end
end

--[[
    Walk the damage up to a player. `dmg:GetAttacker` for ACE fire is often the
    gun or the bullet entity, so ownership is chased through CPPI first (the
    prop-protection authority TPG trusts everywhere) and `:GetOwner()` as a
    fallback. Three hops covers gun -> owner and bullet -> gun -> owner; a
    deeper chain is somebody's exploit attempt and can stay uncredited.
]]
local function ResolveAttacker(dmg)
    local att = dmg:GetAttacker()

    for _ = 1, 3 do
        if not IsValid(att) then return nil end
        if att:IsPlayer() then return att end

        local owner = TPG.Util.GetOwner(att)
        if owner then
            att = owner
        elseif att.GetOwner and IsValid(att:GetOwner()) then
            att = att:GetOwner()
        else
            return nil
        end
    end

    return nil
end

-- Who owns this contraption, best effort: ACE asks the baseplate's CPPI owner;
-- the fallback is the entity that just took the hit.
local function ConOwner(con, fallbackEnt)
    if ACE.GetContraptionOwner then
        local owner = ACE.GetContraptionOwner(con)
        if IsValid(owner) then return owner end
    end
    return TPG.Util.GetOwner(fallbackEnt)
end

-- Mass of an entity for the ledger. `ent._mass` is CFW's own cached value
-- (set by its entityAdded mass tracking, the same number its SubMass uses);
-- the physics object is the fallback before that cache exists.
local function EntMass(ent)
    if not ent then return 0 end
    -- `_mass` survives invalidation: it is cached on the entity table itself.
    if ent._mass then return ent._mass end
    if not IsValid(ent) then return 0 end
    local phys = ent:GetPhysicsObject()
    return IsValid(phys) and phys:GetMass() or 0
end

--[[
    (Re)evaluate doom for one contraption: enough of its peak mass lost, and
    the loss happened while enemy damage is still fresh. Rebuilds clear the
    flag because the lost mass is paid back on `entityAdded`.

    Doom is measured by ACCUMULATED removed mass (`TPG_VKMassLost`), never by
    reading `con.totalMass` during teardown: CFW fires `entityRemoved` once
    per entity with `totalMass` still mid-update, so a contraption dissolving
    presents a shrinking fragment mass that reads as near-total loss. Summing
    what actually left is immune to that ordering.
]]
local function EvalDoom(con)
    local led = con.TPG_VK
    local peak = con.TPG_VKPeak
    if not led or not peak or peak <= 0 then return end

    local frac = (con.TPG_VKMassLost or 0) / peak
    if frac < DoomFrac() then
        if con.TPG_VKDoomAt then
            DbgChat("mass restored (%.0f%% lost) - doom cleared", frac * 100)
        else
            Dbg("mass eval: %.0f%% lost < %.0f%% - no doom", frac * 100, DoomFrac() * 100)
        end
        con.TPG_VKDoomAt = nil
        return
    end

    if not led.lastHit or (CurTime() - led.lastHit) > KillWindow() then
        DbgChat("%.0f%% mass lost but last enemy hit is stale - no doom", frac * 100)
        con.TPG_VKDoomAt = nil
        return
    end

    if not con.TPG_VKDoomAt then
        con.TPG_VKDoomAt = CurTime()
        DbgChat("%.0f%% mass lost, enemy hit fresh - DOOMED", frac * 100)
    end
end

--[[
    Ammo doom. A contraption that loses its ammunition cannot fight, so main-
    ammo death credits the kill immediately -- it does not wait for the wreck
    to be removed. Calibers are ACE's crate values (cm), compared in mm.

    Three bands: big (main guns), mid (autocannons/secondaries), small (coax
    MGs). The band a contraption's doom rides on is its own LARGEST ammo:
    a light vehicle whose biggest rack is 20mm still dies with that rack,
    while the same 20mm on an MBT is a secondary worth an assist, not a kill.
    Small ammo never dooms unless it was the only ammo aboard.
]]
local function BigCal() return TPG.Config.vehicleAmmoBigCal or 50 end
local function MidCal() return TPG.Config.vehicleAmmoMidCal or 15 end

-- Crate caliber in mm.
local function AmmoCaliber(ent)
    local bd = ent.BulletData
    return (((istable(bd) and bd.Caliber) or ent.Caliber or 0) * 10)
end

-- Ammo that is gone or going: removed, cooking off, or marked for it. A crate
-- mid-cookoff is dead ammunition even while the entity still burns.
local function AmmoDead(ent)
    if not IsValid(ent) then return true end
    if ent.IsMarkedForDeletion and ent:IsMarkedForDeletion() then return true end
    if ent.Exploding or ent.CookoffActive then return true end
    return false
end

-- Live ammo on the contraption, bucketed by band; `ents` is CFW-maintained.
local function AmmoBands(con)
    local bands = { big = 0, mid = 0, small = 0, max = 0 }
    for e in pairs(con.ents or {}) do
        if IsValid(e) and e.GetClass and e:GetClass() == "acf_ammo" and not AmmoDead(e) then
            local cal = AmmoCaliber(e)
            if cal > bands.max then bands.max = cal end
            if cal >= BigCal() then bands.big = bands.big + 1
            elseif cal >= MidCal() then bands.mid = bands.mid + 1
            else bands.small = bands.small + 1 end
        end
    end
    return bands
end

-- Entity -> owning player, same chain the damage resolver walks.
local function ResolvePlayer(ent)
    for _ = 1, 3 do
        if not IsValid(ent) then return nil end
        if ent.IsPlayer and ent:IsPlayer() then return ent end

        local owner = TPG.Util.GetOwner(ent)
        if owner then
            ent = owner
        elseif ent.GetOwner and IsValid(ent:GetOwner()) then
            ent = ent:GetOwner()
        else
            return nil
        end
    end
    return nil
end

-- Defined below; forward reference for the ammo evaluator.
local Credit

--[[
    deadCal is the caliber of the crate that just died/cooked (nil = rescan
    only). Runs the band rules: main-ammo death dooms and credits on the spot;
    a mid-band wiped on a big-ammo contraption pays a single assist to whoever
    touched the rack off (self.Inflictor, falling back to the last damager).
]]
local function EvalAmmo(con, deadCal, instigator)
    local led = con.TPG_VK
    if not led then
        con.TPG_VKAmmoEvent = true
        con.TPG_VKAmmoCal = math.max(con.TPG_VKAmmoCal or 0, deadCal or 0)
        Dbg("ammo %smm died before any ledger - stashed", tostring(deadCal))
        return
    end
    if not led.lastHit or (CurTime() - led.lastHit) > KillWindow() then
        Dbg("ammo %smm died but last enemy hit is stale - ignored", tostring(deadCal))
        return
    end

    led.ammoPeak = math.max(led.ammoPeak or 0, deadCal or 0)
    local bands = AmmoBands(con)
    led.ammoPeak = math.max(led.ammoPeak, bands.max)

    local bigDead = bands.big == 0
    local midDead = bands.mid == 0
    local allDead = bigDead and midDead and bands.small == 0

    Dbg("ammo eval: dead=%s live={big:%d mid:%d small:%d} peak=%.0fmm",
        tostring(deadCal), bands.big, bands.mid, bands.small, led.ammoPeak)

    local doomed
    if led.ammoPeak >= BigCal() then
        doomed = bigDead
    elseif led.ammoPeak >= MidCal() then
        doomed = midDead                 -- mid was this build's main armament
    else
        doomed = allDead                 -- coax-only: only when nothing is left
    end

    if doomed and not led.credited then
        con.TPG_VKDoomAt = con.TPG_VKDoomAt or CurTime()
        DbgChat("main ammo destroyed - DOOMED, crediting now")
        Credit(con)
        return
    end

    -- A wiped mid band on a still-armed big contraption: an assist, once.
    if not led.midPaid and midDead and not bigDead and led.ammoPeak >= BigCal()
        and deadCal and deadCal >= MidCal() and deadCal < BigCal() then
        led.midPaid = true

        local payer = ResolvePlayer(instigator) or led.lastAttacker
        local victim = IsValid(led.owner) and led.owner or nil
        if IsValid(payer) and victim and payer:Team() == TPG.GetEnemyTeam(victim:Team()) then
            local value = TPG.PropTracking.GetPlayerUsage(victim).points or 0
            if TPG.Economy and TPG.Economy.VehicleKillAssistReward then
                TPG.Economy.VehicleKillAssistReward(payer, value)
            end
            TPG.State.GetPlayer(payer).stats.assists = (TPG.State.GetPlayer(payer).stats.assists or 0) + 1
            DbgChat("secondary ammo wiped - assist to %s", payer:Nick())
            TPG.Util.ChatMessage(payer, "[TPG] Secondary ammo destroyed - assist credited.", Color(255, 200, 0))
        else
            Dbg("mid band wiped but no valid enemy payer - assist skipped")
        end
    end
end

-- Pay the kill once: top enemy contributor wins, last damager as fallback.
Credit = function(con)
    local led = con.TPG_VK
    if not led or led.credited then return end
    led.credited = true

    local victim = IsValid(led.owner) and led.owner or nil
    local victimTeam = victim and victim:Team() or TEAM_UNASSIGNED
    local enemyTeam = TPG.GetEnemyTeam(victimTeam)

    -- Rank enemy contributors so the heaviest hitter takes the kill and
    -- meaningful helpers are visible as assists rather than vanishing into
    -- the notepad. Damage is ranked, not just summed, so a 70/30 split pays
    -- differently from a 51/49 one.
    local contributors, totalDamage = {}, 0
    for att, dmg in pairs(led.dmg) do
        if IsValid(att) and att:Team() == enemyTeam then
            contributors[#contributors + 1] = { ply = att, dmg = dmg }
            totalDamage = totalDamage + dmg
        end
    end
    table.sort(contributors, function(a, b) return a.dmg > b.dmg end)

    local killer = contributors[1] and contributors[1].ply
    if not killer and IsValid(led.lastAttacker) and led.lastAttacker:Team() == enemyTeam then
        killer = led.lastAttacker
    end
    if not killer then
        DbgChat("doomed but no enemy contributor found - nobody to credit")
        DbgNpcOutcome(con, 0)
        return
    end

    local assists = {}
    local minShare = (TPG.Config.vehicleKillAssistFrac or 0.15) * totalDamage
    for i = 2, #contributors do
        if contributors[i].dmg >= minShare then
            assists[#assists + 1] = contributors[i].ply
        end
    end

    -- The same number a real death would have read: the victim's fielded
    -- points from the periodic snapshot. Free, and consistent with the
    -- player-kill ticket drain.
    local value = victim and TPG.PropTracking.GetPlayerUsage(victim).points or 0

    if cvDebug:GetBool() then
        for i, c in ipairs(contributors) do
            Dbg("contributor %d: %s %.0f dmg (%.0f%%)",
                i, c.ply:Nick(), c.dmg, totalDamage > 0 and 100 * c.dmg / totalDamage or 0)
        end
        DbgChat("CREDIT: %s takes the kill (value %d, +%d pts), %d assist(s)",
            killer:Nick(), value, DbgKillReward(value), #assists)
        DbgNpcOutcome(con, value)
    end

    hook.Run("TPG_VehicleKilled", killer, victim, value, con, assists)
end

--[[
    The ledger. Enemy damage only: the victim's own team shooting the tank is
    grief, not a kill to protect. `TPG_VKPeak` tracks the most mass the con has
    held since the ledger started so "half the tank is gone" is measured
    against its fighting weight, not its spawn weight.
]]
hook.Add("EntityTakeDamage", "TPG_VehicleKillLedger", function(ent, dmg)
    if dmg:GetDamage() <= 0 or not IsValid(ent) then return end
    if not ACE or not ACE.GetContraptionFromEntity then return end

    local con = ACE.GetContraptionFromEntity(ent)
    if not con then return end

    local attacker = ResolveAttacker(dmg)
    if not attacker then
        -- Not a player. If an NPC dealt it, keep a shadow tally (debug only)
        -- so testing bots' damage still reports what it would have earned.
        if cvDebug:GetBool() then
            local npc = ResolveNpc(dmg)
            if npc then
                con.TPG_VKNpc = con.TPG_VKNpc or {}
                con.TPG_VKNpc[npc] = (con.TPG_VKNpc[npc] or 0) + dmg:GetDamage()
                Dbg("npc %s hit %s for %.0f (npc total %.0f)",
                    npc:GetClass(), ent:GetClass(), dmg:GetDamage(), con.TPG_VKNpc[npc])
            else
                Dbg("hit on %s: attacker %s does not resolve to a player or npc",
                    ent:GetClass(), tostring(dmg:GetAttacker()))
            end
        end
        return
    end
    if not TPG.Util.IsOnTeam(attacker) then
        Dbg("hit on %s: %s is not on a team - ignored", ent:GetClass(), attacker:Nick())
        return
    end

    -- Enemy check runs before the ledger exists: friendly fire and world
    -- damage must not spawn a bookkeeping table on every prop they scratch.
    local led = con.TPG_VK
    local owner = led and led.owner
    if not IsValid(owner) then
        owner = ConOwner(con, ent)
        if led then led.owner = owner end
    end

    local ownerTeam = owner and owner:Team() or TEAM_UNASSIGNED
    if attacker:Team() ~= TPG.GetEnemyTeam(ownerTeam) then
        Dbg("hit on %s: %s vs owner %s - friendly/wrong team, ignored",
            ent:GetClass(), attacker:Nick(), IsValid(owner) and owner:Nick() or "?")
        return
    end

    if not led then
        led = { dmg = {} }
        con.TPG_VK = led
        con.TPG_VKPeak = con.totalMass or 0
        DbgChat("ledger opened: %s hit %s's con (peak %.0f)",
            attacker:Nick(), IsValid(owner) and owner:Nick() or "?", con.TPG_VKPeak)
    end
    -- Owner is refreshed every hit: the CPPI answer is authoritative and the
    -- lookup is cheap on a damage event.
    led.owner = owner

    led.dmg[attacker] = (led.dmg[attacker] or 0) + dmg:GetDamage()
    led.lastAttacker = attacker
    led.lastHit = CurTime()
    Dbg("recorded %.0f from %s (their total %.0f)", dmg:GetDamage(), attacker:Nick(), led.dmg[attacker])

    -- An ammo cook-off can precede the ledger (same hit, hook order). If one
    -- was recorded before the ledger existed, evaluate it now that it does.
    if con.TPG_VKAmmoEvent then
        local cal = con.TPG_VKAmmoCal
        con.TPG_VKAmmoEvent = nil
        con.TPG_VKAmmoCal = nil
        EvalAmmo(con, cal)
    end
end)

--[[
    Re-evaluate doom whenever the con's mass changes. `entityRemoved` covers
    both combat destruction and owner deletion; `entityAdded` catches repairs.

    Only a DEPARTED entity counts, and `IsMarkedForDeletion` is what tells
    them from the survivors: when a contraption disbands, CFW ejects its
    still-living members through the same hook, and `ent:IsValid` stays true
    for the deleted one until the engine sweeps anyway. Deletion-marked ents
    are destruction (combat, undo, remover, admin cleanup alike -- that last
    mile is the point); ejected survivors are not. A prop unwelded mid-fight
    leaves unmarked and so is not counted -- it was never destroyed, the
    contraption just keeps fighting at its new weight.
]]
hook.Add("cfw.contraption.entityRemoved", "TPG_VehicleKillRemovedEnt", function(con, ent)
    local marked = ent.IsMarkedForDeletion and ent:IsMarkedForDeletion()
    if marked and con.TPG_VK then
        con.TPG_VKMassLost = (con.TPG_VKMassLost or 0) + EntMass(ent)
    end
    if cvDebug:GetBool() and marked then
        Dbg("%s left con (marked, mass %.0f, total lost %.0f)%s",
            tostring(ent), EntMass(ent), con.TPG_VKMassLost or 0,
            con.TPG_VK and "" or " - no ledger, nothing tracked")
    end
    if not con.TPG_VK or not marked then return end
    EvalDoom(con)

    if ent.GetClass and ent:GetClass() == "acf_ammo" then
        EvalAmmo(con, AmmoCaliber(ent))
    end
end)

hook.Add("cfw.contraption.entityAdded", "TPG_VehicleKillAddedEnt", function(con, ent)
    if not con.TPG_VK then return end

    -- Rebuilding pays the lost mass back; mass added beyond what was lost is
    -- growth and raises the fighting-weight peak.
    local added = EntMass(ent)
    local lost  = con.TPG_VKMassLost or 0
    con.TPG_VKMassLost = math.max(0, lost - added)
    con.TPG_VKPeak = (con.TPG_VKPeak or 0) + math.max(0, added - lost)
    Dbg("added %.0f mass - lost now %.0f, peak %.0f", added, con.TPG_VKMassLost, con.TPG_VKPeak)

    -- Newly welded ammo raises the armament peak the doom bands measure.
    if ent.GetClass and ent:GetClass() == "acf_ammo" then
        local led = con.TPG_VK
        led.ammoPeak = math.max(led.ammoPeak or 0, AmmoCaliber(ent))
    end

    EvalDoom(con)
end)

--[[
    Combat splits: the fragment inherits the parent's ledger (shared table --
    whichever fragment ends last pays the single kill), but starts with its own
    mass baseline so a surviving fragment that keeps fighting isn't born dead.
]]
hook.Add("cfw.contraption.split", "TPG_VehicleKillSplit", function(parent, child)
    if parent.TPG_VK then
        child.TPG_VK = parent.TPG_VK
        child.TPG_VKPeak = child.totalMass or 0
        child.TPG_VKMassLost = 0
    end
end)

-- Merge folds the smaller ledger in: damage totals combine, freshest hit wins.
-- The surviving con keeps the more damaged fragment's loss figure (a damaged
-- half merging into a healthy con does not become fresh) and the bigger peak.
hook.Add("cfw.contraption.merged", "TPG_VehicleKillMerged", function(con, mergedInto)
    local led = con.TPG_VK
    if not led then return end

    mergedInto.TPG_VKMassLost = math.max(mergedInto.TPG_VKMassLost or 0, con.TPG_VKMassLost or 0)
    mergedInto.TPG_VKPeak = math.max(mergedInto.TPG_VKPeak or mergedInto.totalMass or 0,
                                    con.TPG_VKPeak or 0)

    local into = mergedInto.TPG_VK
    if not into then
        mergedInto.TPG_VK = led
        return
    end

    for att, dmg in pairs(led.dmg) do
        into.dmg[att] = (into.dmg[att] or 0) + dmg
    end
    if led.lastHit and (not into.lastHit or led.lastHit > into.lastHit) then
        into.lastHit = led.lastHit
        into.lastAttacker = led.lastAttacker
    end
    if IsValid(led.owner) then into.owner = led.owner end
    if led.credited then into.credited = true end
end)

--[[
    Ammo cook-off, the combat-caused kind. ACE fires this from inside the
    crate's damage path, which can run before this file's EntityTakeDamage has
    opened the ledger -- EvalAmmo stashes the event for the next hit in that
    case. Only fires for kill-severity damage; quiet removals of ammo crates
    reach EvalAmmo through the entityRemoved hook instead.
]]
hook.Add("ACE_AmmoExplode", "TPG_VehicleKillAmmo", function(ent)
    if not ACE or not ACE.GetContraptionFromEntity then return end
    local con = ACE.GetContraptionFromEntity(ent)
    if not con then
        Dbg("ACE_AmmoExplode on %s but no contraption", tostring(ent))
        return
    end

    DbgChat("cook-off: %.0fmm ammo on con", AmmoCaliber(ent))
    EvalAmmo(con, AmmoCaliber(ent), ent.Inflictor)
end)

-- Payday. `con.removed` fires when the last entity leaves the contraption --
-- the final bullet fragment or the last undo step, it doesn't matter which.
hook.Add("cfw.contraption.removed", "TPG_VehicleKillRemoved", function(con)
    local led = con.TPG_VK
    if not led then
        Dbg("con removed - no ledger, nothing to credit")
        local owner = ConOwner(con, nil)
        local value = IsValid(owner) and TPG.PropTracking.GetPlayerUsage(owner).points or 0
        DbgNpcOutcome(con, value)
        return
    end
    if led.credited then
        Dbg("con removed - already credited, done")
        return
    end
    if not con.TPG_VKDoomAt then
        Dbg("con removed with a ledger but no doom - tank died healthy, no credit")
        local value = IsValid(led.owner) and TPG.PropTracking.GetPlayerUsage(led.owner).points or 0
        DbgNpcOutcome(con, value)
        return
    end
    if (CurTime() - con.TPG_VKDoomAt) > KillWindow() then
        Dbg("con removed %.0fs after doom (> %ds window) - stale, no credit",
            CurTime() - con.TPG_VKDoomAt, KillWindow())
        return
    end

    DbgChat("doomed con removed - crediting")
    Credit(con)
end)

-- ── What a vehicle kill pays ────────────────────────────────────────────────

-- Kill feed: a line in chat, same surface as the rest of TPG's notices.
hook.Add("TPG_VehicleKilled", "TPG_VehicleKillFeed", function(killer, victim, _value, _con, assists)
    local vname = victim and victim:Nick() or "someone"
    local line = "[TPG] " .. killer:Nick() .. " destroyed " .. vname .. "'s vehicle."
    if assists and #assists > 0 then
        local names = {}
        for _, ply in ipairs(assists) do names[#names + 1] = ply:Nick() end
        line = line .. " (assisted by " .. table.concat(names, ", ") .. ")"
    end
    TPG.Util.ChatBroadcast(line, Color(255, 200, 0))
end)

-- The kill counts toward the killer's session stats like any other; helpers
-- bank an assist instead.
hook.Add("TPG_VehicleKilled", "TPG_VehicleKillStats", function(killer, _victim, _value, _con, assists)
    local aState = TPG.State.GetPlayer(killer)
    aState.stats.kills = (aState.stats.kills or 0) + 1
    aState.stats.vehicleKills = (aState.stats.vehicleKills or 0) + 1
    for _, ply in ipairs(assists or {}) do
        local s = TPG.State.GetPlayer(ply).stats
        s.assists = (s.assists or 0) + 1
    end
end)

-- Ticket drain, identical math to the player-death drain: the victim's
-- fielded value scaled by the mode's per-kill fraction.
hook.Add("TPG_VehicleKilled", "TPG_VehicleKillTickets", function(_killer, victim, value)
    if not IsValid(victim) or not TPG.Util.IsOnTeam(victim) then return end
    if TPG.Commendations and TPG.Commendations.DrainKillTickets then
        TPG.Commendations.DrainKillTickets(victim, value)
    end
end)

-- Economy payout rides the same killReward curve as a frag; assists get a
-- share of it rather than the whole kill priced twice.
hook.Add("TPG_VehicleKilled", "TPG_VehicleKillEconomy", function(killer, _victim, value, _con, assists)
    if not TPG.Economy then return end
    if TPG.Economy.VehicleKillReward then
        TPG.Economy.VehicleKillReward(killer, value)
    end
    if TPG.Economy.VehicleKillAssistReward then
        for _, ply in ipairs(assists or {}) do
            TPG.Economy.VehicleKillAssistReward(ply, value)
        end
    end
end)
