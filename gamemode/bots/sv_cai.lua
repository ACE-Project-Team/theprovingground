--[[--
    Bridge between TPG's NPC bots (gamemode/bots/sv_bots.lua) and the optional
    Combat Intelligent AI addon (global `CAI`).

    Every Combat AI touch is guarded, so with the addon absent only the grenade
    danger hint below still runs:

      * Weapon archetypes: ACE class names are put at the front of
        `CAI.Config.WeaponPatterns`, so an ACE rifle, launcher or pistol gets
        its proper combat profile instead of falling through to "rifle".
      * Shots: ACE SWEPs never call FireBullets, so Combat AI's suppression
        never hears them. The `ACE_SWEPFired` hook is forwarded to that
        suppression handler by hand.
      * Wallbang: `tpg_bots_cai_wallbang` drives Combat AI's `cai_wallbang`.
      * Holding a point: `CAI.Nav.MoveTo` is wrapped. While sv_bots.lua marks
        a bot as taking a point (`TPG_HoldPoint`), any move Combat AI orders
        is pulled inside the capture radius, so the bot still fights its own
        way but does not step off the point.
      * Carrying home: a bot carrying the CTF flag has `npc.TPG_CarryHome` set (a
        position, by sv_bots.lua). Its moves go to that spot at a run, and
        sv_bots.lua re-issues the move while the bot has an enemy, so it keeps
        running home and still shoots. Fleeing a grenade keeps priority.
      * Firing range: Combat AI stops a bot firing past a fixed range per
        archetype (a rifle stops at 1800 units). `CAI.WeaponIntel.OwnRange` is
        wrapped so an ACE weapon uses its own `NPCMaxRange` instead.

      * Explosions: ACE damages with plain TakeDamage and plays its blast
        sounds client-side, so Combat AI never knew an ACE explosion happened.
        `ACE_OnExplosion` is forwarded to its explosion handler and its sound
        system by hand.
      * Grenades: Combat AI marks a grenade where it was thrown. A live
        `ace_grenade` instead sends the engine's danger hint, and updates
        Combat AI's dodge point, from where it is now.

    Those two wraps are the only places Combat AI code is replaced.

    @module tpg.bots.cai
    @realm server
]]

-- Exact ACE class names, grouped by the Combat AI archetype they should use.
local ARCHETYPES = {
    { archetype = "rocket",  classes = { "weapon_ace_at4", "weapon_ace_at4t", "weapon_ace_javelin", "weapon_ace_stinger", "weapon_ace_xm25", "weapon_ace_portablemortar" } },
    { archetype = "sniper",  classes = { "weapon_ace_scout", "weapon_ace_awp", "weapon_ace_amr" } },
    { archetype = "shotgun", classes = { "weapon_ace_m3super90", "weapon_ace_xm1014" } },
    { archetype = "smg",     classes = { "weapon_ace_tmp", "weapon_ace_ump45", "weapon_ace_p90" } },
    { archetype = "pistol",  classes = { "weapon_ace_glock", "weapon_ace_usp", "weapon_ace_p228", "weapon_ace_fiveseven", "weapon_ace_elite" } },
}

-- Set once the entries are in, so they are never inserted twice.
local patternsAdded = false

-- Shots reported to Combat AI are cut off at this distance, the same as a
-- FireBullets call with no Distance given.
local SHOT_DISTANCE = 8000

local cvWallbang = CreateConVar("tpg_bots_cai_wallbang", "1", { FCVAR_ARCHIVE },
    "Bots fire at an enemy's last known position through walls (Combat AI).")

-- Put the ACE entries at the front of Combat AI's pattern list, once.
local function addWeaponPatterns()
    if patternsAdded then return end
    if not istable(CAI) or not istable(CAI.Config) or not istable(CAI.Config.WeaponPatterns) then return end
    patternsAdded = true

    local entries = {}
    for _, group in ipairs(ARCHETYPES) do
        for _, class in ipairs(group.classes) do
            entries[#entries + 1] = { pattern = class, archetype = group.archetype }
        end
    end

    -- Insert last-to-first at position 1 so the list keeps the order above.
    for i = #entries, 1, -1 do
        table.insert(CAI.Config.WeaponPatterns, 1, entries[i])
    end
end

-- Wrap CAI.Nav.MoveTo once. A bot running from a grenade goes only to its
-- flee spot. A flag carrier goes only to its home spot, at a run. A bot taking
-- a point keeps Combat AI's chosen direction, but the destination is kept
-- within the hold radius.
local function wrapMoveTo()
    if not istable(CAI) or not istable(CAI.Nav) or not isfunction(CAI.Nav.MoveTo) then return end
    if CAI.Nav.TPG_MoveToWrapped then return end

    local moveTo = CAI.Nav.MoveTo
    CAI.Nav.MoveTo = function(data, pos, mode)
        local npc = istable(data) and data.ent
        if IsValid(npc) and npc.TPG_Riding then return false end -- riding in a bot seat (sv_vehicles.lua)
        if IsValid(npc) and isvector(npc.TPG_FleePos) and CurTime() < (npc.TPG_FleeUntil or 0) then
            return moveTo(data, npc.TPG_FleePos, "run")
        end
        if IsValid(npc) and isvector(npc.TPG_CarryHome) then
            return moveTo(data, npc.TPG_CarryHome, "run")
        end

        local pt = IsValid(npc) and npc.TPG_HoldPoint
        if IsValid(pt) and isvector(pos) then
            local center = pt:GetPos()
            local offset = pos - center
            offset.z = 0
            local radius = npc.TPG_HoldRadius or 150
            if offset:Length() > radius then
                pos = center + offset:GetNormalized() * radius
            end
        end
        return moveTo(data, pos, mode)
    end
    CAI.Nav.TPG_MoveToWrapped = true
end

-- Wrap CAI.WeaponIntel.OwnRange once, so an ACE weapon's NPCMaxRange wins
-- over Combat AI's archetype table.
local function wrapOwnRange()
    if not istable(CAI) or not istable(CAI.WeaponIntel) or not isfunction(CAI.WeaponIntel.OwnRange) then return end
    if CAI.WeaponIntel.TPG_OwnRangeWrapped then return end

    local ownRange = CAI.WeaponIntel.OwnRange
    CAI.WeaponIntel.OwnRange = function(npc)
        local wep = IsValid(npc) and npc:GetActiveWeapon()
        if IsValid(wep) and isnumber(wep.NPCMaxRange) then return wep.NPCMaxRange end
        return ownRange(npc)
    end
    CAI.WeaponIntel.TPG_OwnRangeWrapped = true
end

--- Push TPG's Combat AI settings into the addon. Does nothing without the
-- addon, since the `cai_wallbang` convar is only created by Combat AI.
-- @realm server
function TPG.Bots.ApplyCAISettings()
    if not GetConVar("cai_wallbang") then return end
    RunConsoleCommand("cai_wallbang", cvWallbang:GetString())
end

-- Stopgap: Combat AI has no public way to report a shot, so this calls its
-- EntityFireBullets suppression handler directly. Replace it with the public
-- call once Combat AI offers one.
hook.Add("ACE_SWEPFired", "TPG_CAIShots", function(_wep, owner, bulletData)
    if not istable(CAI) then return end
    if not IsValid(owner) or not istable(bulletData) then return end
    if not isvector(bulletData.Pos) or not isvector(bulletData.Flight) then return end

    local hooks = hook.GetTable().EntityFireBullets
    local fn = hooks and hooks.CAI_Suppression
    if not fn then return end

    fn(owner, {
        Src      = bulletData.Pos,
        Dir      = bulletData.Flight:GetNormalized(),
        Distance = SHOT_DISTANCE,
    })
end)

-- How far an ACE explosion is heard, the same as Combat AI's own explosion
-- sounds. Grenade warnings reach as far as Combat AI's own grenade watch.
local BLAST_HEARING  = 2500
local GRENADE_WARN   = 600
local GRENADE_DANGER = 400
local GRENADE_TICK   = 0.25
local GRENADE_FLEE   = 550 -- how far from the grenade a bot inside the danger radius runs to

-- Stopgap, as with shots: Combat AI's explosion reaction only runs from
-- EntityTakeDamage with blast damage, so its handler is called directly with
-- a blast DamageInfo at the explosion.
hook.Add("ACE_OnExplosion", "TPG_CAIExplosions", function(pos, _radius, inflictor)
    if not istable(CAI) or not isvector(pos) then return end

    local hooks = hook.GetTable().EntityTakeDamage
    local fn = hooks and hooks.CAI_MoraleExplosions
    if fn then
        local dmg = DamageInfo()
        dmg:SetDamageType(DMG_BLAST)
        dmg:SetDamagePosition(pos)
        fn(game.GetWorld(), dmg)
    end

    if istable(CAI.Sound) and isfunction(CAI.Sound.Emit) then
        CAI.Sound.Emit(pos, "explosion", BLAST_HEARING, IsValid(inflictor) and inflictor or nil)
    end
end)

local grenades = {}

-- Combat AI's own dodge only nudges a bot's next move by 200 units, so a bot
-- already walking somewhere keeps going. This sends it straight out of the
-- blast instead, and wrapMoveTo keeps it on that spot until the order lapses.
local function flee(npc, data, nadePos)
    local away = npc:GetPos() - nadePos
    away.z = 0
    if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end

    local spot = nadePos + away:GetNormalized() * GRENADE_FLEE
    spot.z = npc:GetPos().z
    npc.TPG_FleePos = spot
    npc.TPG_FleeUntil = CurTime() + GRENADE_TICK * 3
    CAI.Nav.MoveTo(data, spot, "run")
end

hook.Add("OnEntityCreated", "TPG_GrenadeWatch", function(ent)
    if ent:GetClass() == "ace_grenade" then grenades[ent] = true end
end)

-- Every live ACE grenade warns from where it is now: the engine's danger hint
-- for any NPC, and Combat AI's dodge point for bots it manages.
timer.Create("TPG_GrenadeWatch", GRENADE_TICK, 0, function()
    for nade in pairs(grenades) do
        if not IsValid(nade) then
            grenades[nade] = nil
        else
            local pos = nade:GetPos()
            sound.EmitHint(SOUND_DANGER, pos, GRENADE_DANGER, GRENADE_TICK * 2, nade)

            if istable(CAI) and istable(CAI.Manager) and isfunction(CAI.Manager.All)
                and istable(CAI.Memory) and isfunction(CAI.Memory.AddDanger)
                and istable(CAI.Nav) and isfunction(CAI.Nav.MoveTo) then
                for npc, data in pairs(CAI.Manager.All()) do
                    if IsValid(npc) and npc:GetPos():DistToSqr(pos) < GRENADE_WARN * GRENADE_WARN then
                        data.reflex = data.reflex or {}
                        data.reflex.grenadePos = pos
                        data.reflex.grenadeUntil = CurTime() + GRENADE_TICK * 2
                        CAI.Memory.AddDanger(data, pos, GRENADE_DANGER, "grenade")
                        if npc:GetPos():DistToSqr(pos) < GRENADE_DANGER * GRENADE_DANGER then
                            flee(npc, data, pos)
                        end
                    end
                end
            end
        end
    end
end)

hook.Add("InitPostEntity", "TPG_CAISetup", function()
    addWeaponPatterns()
    wrapMoveTo()
    wrapOwnRange()
    TPG.Bots.ApplyCAISettings()
end)

cvars.AddChangeCallback("tpg_bots_cai_wallbang", function()
    TPG.Bots.ApplyCAISettings()
end, "TPG_BotsCAIWallbang")

-- The file may load after Combat AI has already set up its config, so try now too.
addWeaponPatterns()
wrapMoveTo()
wrapOwnRange()
