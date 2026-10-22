--[[--
    NPC infantry: console-driven bots that play the ground game like players
    do, for testing without a full roster and, with `tpg_bots_fill`, for
    filling a thin server.

    Green bots are rebel citizens (npc_citizen), Red bots are Combine
    soldiers (npc_combine_s). They spawn at their team's spawn, fight the
    opposing team's players and NPCs, and, when nothing is shooting at them,
    walk to a control point to capture it or hold it.

    Combat is left to whichever AI is running. Stock NPC AI handles it by
    default. The optional Combat Intelligent AI addon (global `CAI`) is
    detected for the status line only; nothing here calls into it. A bot
    with an enemy is never given a movement order, so its combat logic runs
    unchanged.

    Round lifecycle: bots only exist during a live round (`TPG.State.round.active`).
    The brain removes them once the round ends, and keeps `TPG.Bots.perTeam` so
    the next round tops both teams back up. During the prep window
    (`TPG.Prep.IsConfining`) bots are spawned but given no movement orders, the
    same way players are held in their safezone.

    Roles (`TPG.Bots.Roles`): each bot is a rifleman, support or AT. SpawnOne
    picks whichever role keeps the team nearest its target mix: AT share from
    `tpg_bots_at_ratio`, support 15 percent, the rest riflemen. AT4 is
    single-shot, so an AT bot whose launcher is empty is stripped and given a
    fresh one after `REARM_DELAY` seconds. AT bots also carry an SMG sidearm
    and only switch to the launcher against armored vehicles.

    Safezones: a bot inside the enemy's safezone is killed, and one inside its
    own is protected, the same as a player. Spawn protection runs for
    `TPG.Config.spawnProtectionTime` after a spawn and after leaving home.

    Armored targets: a player in an armored vehicle (`gamemode/bots/sv_threat.lua`)
    is a target only for AT bots; rifles and support ignore it. Every other
    enemy player is a target for everyone, with AT bots ranking infantry lower.

    Planner: each brain tick plans each team once. Control points the team
    holds are the defend set, the rest the attack set. Attackers all push to
    the attack point nearest the team's spawn, so the push runs in order.
    Defenders are dealt round-robin over the held points, and their number
    scales with how many points the team holds. A team more than 20 percent
    behind on tickets halves its defenders. A goal is sticky for `GOAL_TIME`
    seconds, until the point changes hands or the goal entity is removed. DM
    pushes to the enemy spawn. CTF goes for the flag, falling back to the enemy
    spawn when there is no flag. Once a point is taken, its defenders spread
    over up to six cover spots around it, facing the enemy, instead of ringing
    the point. A defender whose point has an enemy within twice the capture
    radius goes back onto the point to block the capture. When the team holds
    every point, 40 percent of the bots defend and the rest push to just outside
    the enemy safezone.

    Fill mode: `tpg_bots_fill` tops each team up to that many fighters,
    counting players on the team, so a team of 5 humans with fill 8 gets 3 bots.
    When it is above 0 it overrides the count set by `tpg_bots_test`. Surplus
    bots are removed one per tick, preferring one with no enemy.

    Difficulty: `tpg_bots_difficulty` (0-4) sets weapon proficiency on spawn
    and on live bots.

    Map support: stock NPCs need the map's AI node graph, so bots only spawn
    where `TPG.Bots.MapSupported()` is true. A map with the Combat AI addon's
    navmesh counts as supported too.

    Rewards and kill feed: killing a bot fires `TPG_BotKilled` (npc, attacker,
    inflictor). The economy pays the attacker from it (sv_economy.lua), and
    nothing else reads it. Bots never count for stats or commendations, since
    the PlayerDeath hooks only ever see players. Stock death notices already
    cover bot kills, and `GM:GetDeathNoticeEntityName` names bots "Green AT"
    style.

    Team lookup is `TPG.Util.TeamOf` and `TPG.Util.Fighters` in
    `core/sh_utils.lua`, which is how control points count bots. Bots carry
    `npc.TPG_BotTeam` and the `TPG_BotTeam` network int. Damage between a bot
    and anything on its own team is blocked. TPG has no friendly fire setting,
    so this is unconditional.

    Test mode only: off by default, nothing persists across a restart or a
    round. The superadmin command `tpg_bots_test` sets a fixed count. The
    convars below are the settings panel's knobs.

    Convars: `tpg_bots_fill`, `tpg_bots_test` (command), `tpg_bots_difficulty`,
    `tpg_bots_at_ratio`, `tpg_bots_respawn_delay`, `tpg_bots_drops`,
    `tpg_bots_corpses`, `tpg_bots_friendly_fire` (this file),
    `tpg_bots_armor_points` (sv_threat.lua),
    `tpg_bots_reward_scale` (sv_economy.lua), `tpg_bots_cai_wallbang`
    (sv_cai.lua, Combat AI only), `tpg_bots_seat_grace` (sv_vehicles.lua).

    @module tpg.bots
    @realm server
]]

TPG.Bots = TPG.Bots or {}
TPG.Bots.perTeam = TPG.Bots.perTeam or 0
TPG.Bots.list = TPG.Bots.list or {}

-- What each role carries. One weapon is picked at random from `weapons`, the
-- ones GMod has stored; if none are, `fallback` is used. `antiArmor` marks
-- the role that goes after armored vehicles.
TPG.Bots.Roles = {
    rifleman = { weapons = { "weapon_ace_ak47", "weapon_ace_m16", "weapon_ace_galil" }, fallback = "weapon_smg1" },
    support  = { weapons = { "weapon_ace_m249saw" }, fallback = "weapon_ar2" },
    at       = { weapons = { "weapon_ace_at4" }, fallback = "weapon_rpg", antiArmor = true,
                 secondary = { "weapon_ace_mp5", "weapon_ace_ump45" }, secondaryFallback = "weapon_smg1" },
}

local BRAIN_TIMER    = "TPG_BotsBrain"
local BRAIN_INTERVAL = 2
local ZONE_TIMER     = "TPG_BotsZones"
local ZONE_INTERVAL  = 0.5
local RELATION_EVERY = 5
local SPAWN_GAP      = 3
local MAX_PER_TEAM   = 16
local SPAWN_SPREAD   = 200
local DEFEND_SPREAD  = 120
local GOAL_TIME      = 30
local REARM_DELAY    = 8
local SUPPORT_SHARE  = 0.15
-- Within this distance a bot counts as having reached the flag. The flag's own
-- pickup radius (tpg_flag, PICKUP_RADIUS) is 100 units.
local FLAG_REACH    = 60

local TEAMS      = { TEAM_GREEN, TEAM_RED }
local ROLE_ORDER = { "at", "support", "rifleman" }
local ROLE_LABEL = { rifleman = "Rifleman", support = "Support", at = "AT" }
local TEAM_TAG   = { [TEAM_GREEN] = "Green", [TEAM_RED] = "Red" }

-- Kill feed name for a bot, e.g. "Green AT". Players and everything else keep
-- the stock name.
local function botName(npc)
    local label = ROLE_LABEL[npc.TPG_BotRole] or "Infantry"
    return (TEAM_TAG[npc.TPG_BotTeam] or "Bot") .. " " .. label
end

-- Index is the difficulty level, 0 to 4.
local PROFICIENCY = {
    WEAPON_PROFICIENCY_POOR,
    WEAPON_PROFICIENCY_AVERAGE,
    WEAPON_PROFICIENCY_GOOD,
    WEAPON_PROFICIENCY_VERY_GOOD,
    WEAPON_PROFICIENCY_PERFECT,
}

local cvFill = CreateConVar("tpg_bots_fill", "0", { FCVAR_ARCHIVE },
    "Fill each team up to this many fighters with bots (0 = off).")
local cvDifficulty = CreateConVar("tpg_bots_difficulty", "2", { FCVAR_ARCHIVE },
    "Bot weapon proficiency: 0 poor, 1 average, 2 good, 3 very good, 4 perfect.")
local cvATRatio = CreateConVar("tpg_bots_at_ratio", "0.25", { FCVAR_ARCHIVE },
    "Share of each team's bots that carry AT4 launchers, 0 to 1.")
local cvRespawn = CreateConVar("tpg_bots_respawn_delay", "10", { FCVAR_ARCHIVE },
    "Seconds before a dead bot is replaced.")
local cvDrops = CreateConVar("tpg_bots_drops", "0", { FCVAR_ARCHIVE },
    "Dead bots drop their weapons.")
local cvCorpses = CreateConVar("tpg_bots_corpses", "0", { FCVAR_ARCHIVE },
    "Dead bots leave ragdolls that stay.")
local cvFriendly = CreateConVar("tpg_bots_friendly_fire", "0", { FCVAR_ARCHIVE },
    "Players can hurt the bots on their own team.")

local nextSpawn     = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }
local nextRelations = 0
local warnedNoNodes = false

-- Random point in a disc around the origin, flat on the ground plane.
local function randomOffset(radius)
    local angle = math.Rand(0, math.pi * 2)
    local dist  = math.Rand(0, radius)
    return Vector(math.cos(angle) * dist, math.sin(angle) * dist, 0)
end

local function caiPresent()
    return istable(CAI)
end

local function isAlive(npc)
    return IsValid(npc) and npc:Health() > 0
end

local function enemyTeam(teamId)
    if teamId == TEAM_GREEN then return TEAM_RED end
    return TEAM_GREEN
end

-- Drop entries whose NPC has been removed.
local function pruneList()
    local kept = {}
    for _, npc in ipairs(TPG.Bots.list) do
        if IsValid(npc) then kept[#kept + 1] = npc end
    end
    TPG.Bots.list = kept
end

local function aliveBots(teamId)
    local out = {}
    for _, npc in ipairs(TPG.Bots.list) do
        if npc.TPG_BotTeam == teamId and isAlive(npc) then out[#out + 1] = npc end
    end
    return out
end

local function countAlive(teamId)
    return #aliveBots(teamId)
end

local function proficiency()
    local level = TPG.Util.Clamp(cvDifficulty:GetInt(), 0, 4)
    return PROFICIENCY[level + 1]
end

-- How many bots a team should have right now. Fill mode counts the players
-- already on the team; otherwise it is the fixed test count.
local function targetFor(teamId)
    local fill = cvFill:GetInt()
    if fill > 0 then
        return TPG.Util.Clamp(fill - team.NumPlayers(teamId), 0, MAX_PER_TEAM)
    end
    return TPG.Bots.perTeam
end

-- Can bots spawn on this map right now? Logs once when fill mode is asking
-- for bots on a map that cannot host them.
local function canSpawn()
    if TPG.Bots.MapSupported() then return true end

    if cvFill:GetInt() > 0 and not warnedNoNodes then
        warnedNoNodes = true
        print("[TPG] tpg_bots_fill is on, but this map has no AI nodes, so no bots will spawn.")
    end
    return false
end

-- Relationships: bots of the same team are allies, other bots and every
-- player on the other team are hostile, and spectators or unassigned players
-- are neutral. Bot-to-bot pairs are set in both directions.
--
-- Toward an enemy player in an armored vehicle, AT bots are hostile and the
-- rest ignore them. Toward an unarmored enemy, everyone is hostile, with AT
-- bots ranking infantry lower.
local function applyRelations(npc)
    if not IsValid(npc) then return end

    local myTeam = npc.TPG_BotTeam
    local isAT   = npc.TPG_BotRole == "at"

    for _, other in ipairs(TPG.Bots.list) do
        if other ~= npc and IsValid(other) then
            local disp = (other.TPG_BotTeam == myTeam) and D_LI or D_HT
            npc:AddEntityRelationship(other, disp, 99)
            other:AddEntityRelationship(npc, disp, 99)
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        local disp, prio = D_NU, 99

        if ply:Team() == myTeam then
            disp = D_LI
        elseif TPG.Util.IsOnTeam(ply) then
            if TPG.Bots.IsArmoredTarget(ply) then
                disp = isAT and D_HT or D_NU
            else
                disp = D_HT
                prio = isAT and 50 or 99
            end
        end

        npc:AddEntityRelationship(ply, disp, prio)
    end
end

-- Spectators are nobody's target. Bots already hold them neutral, but CAI
-- keeps anyone it hears who is not an ally in its enemy memory and engages
-- from there, so a spectator also gets FL_NOTARGET while off a team. A player
-- inside their own safezone cannot be hurt, so they get it too. Only a flag
-- set here is cleared here.
local function applyNoTarget()
    for _, ply in ipairs(player.GetAll()) do
        if TPG.Protection.IsInSafezone(ply) then
            if not ply:IsFlagSet(FL_NOTARGET) then
                ply:AddFlags(FL_NOTARGET)
                ply.TPG_SpecNoTarget = true
            end
        elseif ply.TPG_SpecNoTarget then
            ply:RemoveFlags(FL_NOTARGET)
            ply.TPG_SpecNoTarget = nil
        end
    end
end

local function applyAll()
    pruneList()
    applyNoTarget()
    for _, npc in ipairs(TPG.Bots.list) do
        applyRelations(npc)
    end
end

--- Refresh every bot's relations now, instead of waiting for the next
-- relations pass. Called when a player enters or leaves a vehicle.
-- @realm server
function TPG.Bots.RefreshRelations()
    applyAll()
end

-- Owner team of a control point. The entity stores ownership as 1 (Green),
-- -1 (Red) or 0 (neutral), not as a team id.
local function pointOwnerTeam(pt)
    local owner = pt:GetNWInt("CapOwnership", 0)
    if owner == 1 then return TEAM_GREEN end
    if owner == -1 then return TEAM_RED end
    return 0
end

-- ── Planner ─────────────────────────────────────────────────────────────────

-- A goal is an entity (a control point or the flag), a bare position (an enemy
-- spawn), or both. `TPG_GoalOwner` is only set for control points, so a point
-- that changes hands drops its goal.
local function setGoal(npc, ent, pos, owner, now)
    npc.TPG_GoalStand = nil
    npc.TPG_Goal      = ent
    npc.TPG_GoalPos   = pos
    npc.TPG_GoalOwner = owner
    npc.TPG_GoalUntil = now + GOAL_TIME
end

-- Where the bot is heading now: the goal entity if it still exists, else the
-- position it was given.
local function goalPos(npc)
    local ent = npc.TPG_Goal
    if IsValid(ent) then
        if npc.TPG_GoalStand then return npc.TPG_GoalStand end
        return ent:GetPos()
    end
    return npc.TPG_GoalPos
end

-- Is this bot's current goal still in force?
local function goalHeld(npc, now)
    if now >= (npc.TPG_GoalUntil or 0) then return false end
    if not goalPos(npc) then return false end

    local ent = npc.TPG_Goal
    if ent and not IsValid(ent) then return false end
    if ent and npc.TPG_GoalOwner ~= nil and pointOwnerTeam(ent) ~= npc.TPG_GoalOwner then
        return false
    end
    return true
end

-- Give every bot without a held goal the same goal.
local function orderAll(bots, ent, pos, now)
    if not pos then return end
    for _, npc in ipairs(bots) do
        if not goalHeld(npc, now) then setGoal(npc, ent, pos, nil, now) end
    end
end

-- The point in `list` with the fewest bots already sent to it, so attackers
-- spread over every point they don't hold. Ties go to the one nearest `pos`.
local function leastAttacked(list, load, pos)
    local best, bestLoad, bestDist
    for _, pt in ipairs(list) do
        local n = load[pt] or 0
        local d = pos and pt:GetPos():DistToSqr(pos) or 0
        if not best or n < bestLoad or (n == bestLoad and d < bestDist) then
            best, bestLoad, bestDist = pt, n, d
        end
    end
    return best
end

-- A spot just outside the enemy safezone, on the side facing this team's
-- spawn. Bots die inside the enemy zone, so this is as far as a push goes.
local function outsideEnemyZone(teamId)
    local theirs = TPG.State.GetSpawn(enemyTeam(teamId))
    if not theirs then return nil end

    local ours = TPG.State.GetSpawn(teamId) or Vector(0, 0, 0)
    local dir = ours - theirs
    dir.z = 0
    if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) end
    dir:Normalize()

    local pos = theirs + dir * (TPG.Maps.GetSafezoneRadius() + 300)
    local tr = util.TraceLine({
        start  = pos + Vector(0, 0, 512),
        endpos = pos - Vector(0, 0, 2048),
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit and tr.HitPos or pos
end

-- Stand spots per control point and team, refreshed every 15 seconds.
local spotCache = {}

-- Up to six ground positions around an owned point where a defender can take
-- cover facing the enemy. Cover toward the enemy scores highest, then a clear
-- line back to the point. Results are cached per point and team.
local function defenseSpots(pt, teamId)
    local now = CurTime()
    for p in pairs(spotCache) do
        if not IsValid(p) then spotCache[p] = nil end
    end

    local byTeam = spotCache[pt] or {}
    spotCache[pt] = byTeam
    local cached = byTeam[teamId]
    if cached and now < cached.expires then return cached.spots end

    local ptPos = pt:GetPos()

    -- Face the nearest point this team does not own, else the enemy spawn.
    local nearest, nearestDist
    for _, other in ipairs(ents.FindByClass("tpg_controlpoint")) do
        if other ~= pt and pointOwnerTeam(other) ~= teamId then
            local d = other:GetPos():DistToSqr(ptPos)
            if not nearest or d < nearestDist then nearest, nearestDist = other, d end
        end
    end

    local target
    if nearest then
        target = nearest:GetPos()
    else
        target = TPG.State.GetSpawn(enemyTeam(teamId))
    end

    local dir = target and (target - ptPos) or Vector(1, 0, 0)
    dir.z = 0
    if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) end
    dir:Normalize()

    local candidates = {}
    for _, dist in ipairs({ 250, 450, 650 }) do
        for _, yaw in ipairs({ -60, -30, 0, 30, 60 }) do
            local fwd = (dir:Angle() + Angle(0, yaw, 0)):Forward()
            local cand = ptPos + fwd * dist

            local tr = util.TraceLine({
                start  = cand + Vector(0, 0, 256),
                endpos = cand - Vector(0, 0, 1024),
                mask   = MASK_SOLID_BRUSHONLY,
            })

            if tr.Hit then
                local ground = tr.HitPos
                local room = util.TraceHull({
                    start  = ground + Vector(0, 0, 4),
                    endpos = ground + Vector(0, 0, 4),
                    mins   = Vector(-16, -16, 0),
                    maxs   = Vector(16, 16, 72),
                    mask   = MASK_NPCSOLID,
                })

                if not room.Hit and TPG.Protection.GetSafezoneTeam(ground) == nil then
                    local score = 0

                    local cover = util.TraceLine({
                        start  = ground + Vector(0, 0, 40),
                        endpos = ground + Vector(0, 0, 40) + dir * 120,
                        mask   = MASK_SOLID,
                    })
                    if cover.Hit then score = score + 2 end

                    local los = util.TraceLine({
                        start  = ground + Vector(0, 0, 64),
                        endpos = ptPos + Vector(0, 0, 40),
                        mask   = MASK_SOLID_BRUSHONLY,
                    })
                    if not los.Hit then score = score + 1 end

                    if score > 0 then
                        candidates[#candidates + 1] = { pos = ground, score = score, dist = ptPos:Distance(ground) }
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.dist < b.dist
    end)

    local spots = {}
    for i = 1, math.min(6, #candidates) do
        spots[i] = candidates[i].pos
    end

    byTeam[teamId] = { expires = now + 15, spots = spots }
    return spots
end

-- The first stand spot of `pt` not already taken this planning pass, or nil.
-- Taken spots are recorded in `claimed`, keyed by point.
local function freeStand(pt, teamId, claimed)
    local taken = claimed[pt] or {}
    claimed[pt] = taken

    for _, spot in ipairs(defenseSpots(pt, teamId)) do
        local used = false
        for _, t in ipairs(taken) do
            if t:DistToSqr(spot) < 16 then used = true end
        end
        if not used then
            taken[#taken + 1] = spot
            return spot
        end
    end
    return nil
end

-- Work out where one team's bots go this tick. Bots with a goal still in force
-- keep it, and the rest are dealt out.
local function planTeam(teamId, bots, now)
    if #bots == 0 then return end

    local enemy  = enemyTeam(teamId)
    local mode   = TPG.State.gameType
    local points = ents.FindByClass("tpg_controlpoint")

    -- Only the carrier is marked below, so a bot that dropped the flag, or a
    -- round that moved on, loses the mark on this same pass.
    for _, npc in ipairs(bots) do npc.TPG_CarryHome = nil end

    if mode == GAMEMODE_CTF then
        local flag = ents.FindByClass("tpg_flag")[1]
        if IsValid(flag) then
            -- A bot carrying the flag runs it home itself, and the rest escort it.
            -- setGoal replaces the carrier's goal outright, so a stale flag goal
            -- is overwritten here and goalHeld cannot keep it on the flag.
            local carrier = flag:GetCarrier()
            if not (IsValid(carrier) and carrier:IsNPC() and TPG.Util.TeamOf(carrier) == teamId) then
                carrier = nil
            end

            local escorts = {}
            for _, npc in ipairs(bots) do
                if npc == carrier then
                    local home = TPG.State.GetSpawn(teamId)
                    if home then
                        setGoal(npc, nil, home, nil, now)
                        npc.TPG_CarryHome = home
                    end
                else
                    escorts[#escorts + 1] = npc
                end
            end
            return orderAll(escorts, flag, flag:GetPos(), now)
        end
    end

    if mode == GAMEMODE_DM or mode == GAMEMODE_CTF or #points == 0 then
        return orderAll(bots, nil, outsideEnemyZone(teamId), now)
    end

    local owned, attack = {}, {}
    for _, pt in ipairs(points) do
        if pointOwnerTeam(pt) == teamId then
            owned[#owned + 1] = pt
        else
            attack[#attack + 1] = pt
        end
    end

    local defenders = math.floor(#bots * 0.5 * #owned / #points)
    local mine  = TPG.State.scores[teamId] or 0
    local their = TPG.State.scores[enemy] or 0
    if mine < their * 0.8 then defenders = math.floor(defenders / 2) end
    if #owned == 0 then defenders = 0 end

    local home = TPG.State.GetSpawn(teamId)

    -- With every point held there is nothing to attack, so most bots push out
    -- toward the enemy instead of crowding the points.
    local target, push = defenders, nil
    if #attack == 0 then
        target = math.max(1, math.ceil(#bots * 0.4))
        push = outsideEnemyZone(teamId)
    end

    -- How many bots are already heading for each point this team attacks.
    local load, claimed = {}, {}
    local defending, free = 0, {}
    for _, npc in ipairs(bots) do
        if goalHeld(npc, now) then
            if npc.TPG_GoalOwner == teamId then
                defending = defending + 1
                if npc.TPG_GoalStand and IsValid(npc.TPG_Goal) then
                    local taken = claimed[npc.TPG_Goal] or {}
                    taken[#taken + 1] = npc.TPG_GoalStand
                    claimed[npc.TPG_Goal] = taken
                end
            elseif IsValid(npc.TPG_Goal) then
                load[npc.TPG_Goal] = (load[npc.TPG_Goal] or 0) + 1
            end
        else
            free[#free + 1] = npc
        end
    end

    local slot = 0
    for _, npc in ipairs(free) do
        -- With nothing to push to, every free bot defends, as it always did.
        local wantDefend = #owned > 0 and (defending < target or (#attack == 0 and not push))
        if wantDefend then
            slot = slot % #owned + 1
            local pt = owned[slot]
            defending = defending + 1
            setGoal(npc, pt, pt:GetPos(), teamId, now)
            npc.TPG_GoalStand = freeStand(pt, teamId, claimed)
        elseif #attack > 0 then
            local pt = leastAttacked(attack, load, home)
            load[pt] = (load[pt] or 0) + 1
            setGoal(npc, pt, pt:GetPos(), pointOwnerTeam(pt), now)
        elseif push then
            setGoal(npc, nil, push, nil, now)
        end
    end
end

-- ── Roles ───────────────────────────────────────────────────────────────────

local function isATWeapon(class)
    local def = TPG.Bots.Roles.at
    if class == def.fallback then return true end
    for _, c in ipairs(def.weapons) do
        if c == class then return true end
    end
    return false
end

-- A random class from `list` that GMod has stored, else `fallback`.
local function pickFrom(list, fallback)
    local choices = {}
    for _, class in ipairs(list) do
        if weapons.GetStored(class) then choices[#choices + 1] = class end
    end
    if #choices == 0 then return fallback end
    return choices[math.random(#choices)]
end

-- A weapon for a role: random among the ones GMod has, else the fallback.
local function pickWeapon(role)
    local def = TPG.Bots.Roles[role]
    return pickFrom(def.weapons, def.fallback)
end

-- The role that brings the team closest to its target mix.
local function pickRole(teamId)
    local counts, total = {}, 0
    for _, npc in ipairs(aliveBots(teamId)) do
        if npc.TPG_BotRole then
            counts[npc.TPG_BotRole] = (counts[npc.TPG_BotRole] or 0) + 1
            total = total + 1
        end
    end

    local at = TPG.Util.Clamp(cvATRatio:GetFloat(), 0, 1)
    local shares = { at = at, support = SUPPORT_SHARE, rifleman = math.max(0, 1 - at - SUPPORT_SHARE) }

    local best, bestDeficit
    for _, role in ipairs(ROLE_ORDER) do
        local deficit = shares[role] * (total + 1) - (counts[role] or 0)
        if not bestDeficit or deficit > bestDeficit then best, bestDeficit = role, deficit end
    end
    return best
end

-- The launcher an AT bot was given, or the active weapon if it is an AT class
-- and the stored one is gone.
local function launcherOf(npc)
    local wep = npc.TPG_Launcher and npc:GetWeapon(npc.TPG_Launcher)
    if IsValid(wep) then return wep end

    local active = npc:GetActiveWeapon()
    if IsValid(active) and isATWeapon(active:GetClass()) then return active end
    return nil
end

-- AT4 is single-shot. An AT bot out of rounds loses the launcher and gets a
-- fresh one after the delay, so it is never left holding an empty tube. The
-- sidearm is never touched.
local function rearmAT(npc, now)
    if npc.TPG_NextRearm then
        if now >= npc.TPG_NextRearm then
            npc.TPG_NextRearm = nil
            npc.TPG_Launcher = pickWeapon("at")
            npc:Give(npc.TPG_Launcher)
            npc:SetCurrentWeaponProficiency(proficiency())
        end
        return
    end

    local wep = launcherOf(npc)
    if wep and wep:Clip1() == 0 then
        -- StripWeapon is player-only; removing the weapon is how an NPC drops it.
        wep:Remove()
        npc.TPG_NextRearm = now + REARM_DELAY
    end
end

-- An AT bot holds its launcher for armored targets and its sidearm for
-- everything else. Runs each brain tick, after rearmAT. A launcher that is
-- being reloaded, or stripped, falls back to the sidearm.
local function pickATWeapon(npc)
    local enemy = npc:GetEnemy()
    local wantLauncher = IsValid(enemy) and (TPG.Bots.IsArmoredTarget(enemy)
        or enemy:IsVehicle() or (enemy:IsPlayer() and enemy:InVehicle()))

    local class = wantLauncher and npc.TPG_Launcher or npc.TPG_Sidearm
    if class and not IsValid(npc:GetWeapon(class)) then class = npc.TPG_Sidearm end
    if not class or not IsValid(npc:GetWeapon(class)) then return end

    local active = npc:GetActiveWeapon()
    if IsValid(active) and active:GetClass() == class then return end
    npc:SelectWeapon(class)
end

-- ── Brain ───────────────────────────────────────────────────────────────────

local brain

-- Safezone check for every live bot. Home is protected, and the grace period
-- after leaving home runs from the last tick spent there. The enemy's zone is
-- lethal. The kill is flagged so the spawn-protection check lets it through.
-- A bot taking a point has to stay inside the capture radius, but once it is
-- fighting the combat AI moves it freely and it can step off mid-capture.
-- Only a bot that has reached the point is held. One still on its way keeps
-- fighting normally.
--
-- `TPG_HoldPoint` tells sv_cai.lua to keep Combat AI's moves on the point.
-- Engine schedules such as taking cover can still carry the bot off, so a bot
-- found outside is also sent back, at most once a second.
local function holdOnPoint(npc, capRadius, now)
    npc.TPG_HoldPoint = nil
    if npc.TPG_Riding then return end
    if now < (npc.TPG_FleeUntil or 0) then return end -- running from a grenade

    local pt = npc.TPG_Goal
    if not IsValid(pt) or pt:GetClass() ~= "tpg_controlpoint" then return end
    if pointOwnerTeam(pt) == npc.TPG_BotTeam then return end

    local hold = capRadius * 0.8
    local d = npc:GetPos():Distance(pt:GetPos())
    if d > capRadius * 2 then return end

    npc.TPG_HoldPoint  = pt
    npc.TPG_HoldRadius = hold
    if d <= hold or now < (npc.TPG_HoldSentAt or 0) + 1 then return end

    npc.TPG_HoldSentAt = now
    npc:SetLastPosition(pt:GetPos() + randomOffset(math.min(DEFEND_SPREAD, hold)))
    npc:SetSchedule(SCHED_FORCED_GO_RUN)
end

-- Combat AI stops a bot to shoot once it has an enemy, and it only moves a
-- bot again through its own schedules. A flag carrier with an enemy is
-- therefore given a fresh move on every zone tick, and sv_cai.lua sends that
-- move to TPG_CarryHome. combatMoveAt is kept current so Combat AI's
-- stop-and-shoot burst does not cut the run short.
local function driveCarrier(npc)
    if not npc.TPG_CarryHome or not IsValid(npc:GetEnemy()) then return end
    if not istable(CAI) or not istable(CAI.Manager) or not isfunction(CAI.Manager.All) then return end
    if not istable(CAI.Nav) or not isfunction(CAI.Nav.MoveTo) then return end
    local data = CAI.Manager.All()[npc]
    if not data then return end

    data.combatMoveAt = CurTime()
    CAI.Nav.MoveTo(data, npc.TPG_CarryHome, "run")
end

local function zoneTick()
    local now = CurTime()
    local grace = TPG.Config.spawnProtectionTime or 5
    local capRadius = TPG.Util.MetersToUnits(TPG.Config.capDistanceMeters or 5)

    -- Players walk in and out of their safezone faster than the relations pass.
    applyNoTarget()

    for _, npc in ipairs(TPG.Bots.list) do
        if isAlive(npc) and not npc.TPG_Riding then
            local zone = TPG.Protection.GetSafezoneTeam(npc:GetPos())
            if zone == npc.TPG_BotTeam then
                npc.TPG_ProtectedUntil = now + grace
            elseif zone ~= nil then
                local d = DamageInfo()
                d:SetDamage(npc:Health() + 1000)
                d:SetDamageType(DMG_GENERIC)
                d:SetAttacker(game.GetWorld())
                d:SetInflictor(game.GetWorld())
                npc.TPG_ZoneKill = true
                npc:TakeDamageInfo(d)
                npc.TPG_ZoneKill = nil
            end

            if isAlive(npc) then
                holdOnPoint(npc, capRadius, now)
                driveCarrier(npc)
            end
        end
    end
end

local function startBrain()
    -- An error inside a repeating timer removes it, which would leave the bots
    -- standing with no respawns, so each tick reports its error and carries on.
    timer.Create(BRAIN_TIMER, BRAIN_INTERVAL, 0, function() ProtectedCall(brain) end)
    timer.Create(ZONE_TIMER, ZONE_INTERVAL, 0, function() ProtectedCall(zoneTick) end)
end

-- Every stop goes through here, so the zone timer never outlives the brain.
local function stopBrain()
    timer.Remove(BRAIN_TIMER)
    timer.Remove(ZONE_TIMER)
end

-- Is an enemy fighter near the owned point this bot is defending? Such a bot
-- goes back onto the point to block the capture instead of holding its spot.
local function pointContested(npc, capRadius)
    local pt = npc.TPG_Goal
    if not IsValid(pt) or pt:GetClass() ~= "tpg_controlpoint" then return false end
    if pointOwnerTeam(pt) ~= npc.TPG_BotTeam then return false end

    local range = capRadius * 2
    for _, fighter in ipairs(TPG.Util.Fighters(enemyTeam(npc.TPG_BotTeam))) do
        if IsValid(fighter) and fighter:GetPos():DistToSqr(pt:GetPos()) <= range * range then
            return true
        end
    end
    return false
end

-- Fill mode only: drop one surplus bot, one that has no enemy if possible.
local function removeOne(teamId)
    local pick
    for _, npc in ipairs(aliveBots(teamId)) do
        if not IsValid(npc:GetEnemy()) then
            pick = npc
            break
        end
        pick = pick or npc
    end
    if not pick then return end

    -- Remove() is deferred to the end of the frame, so drop it from the list now.
    for i, npc in ipairs(TPG.Bots.list) do
        if npc == pick then
            table.remove(TPG.Bots.list, i)
            break
        end
    end
    pick:Remove()
end

brain = function()
    if TPG.Bots.perTeam <= 0 and cvFill:GetInt() <= 0 then
        stopBrain()
        TPG.Bots.RemoveAll()
        return
    end

    pruneList()

    -- Bots only live through a round. EndRound has no hook, but it sets
    -- round.active to false, so the first brain tick after the round ends
    -- clears them. perTeam is kept, and the top-up refills at the next round.
    if not TPG.State.round.active then
        if #TPG.Bots.list > 0 then TPG.Bots.RemoveAll() end
        return
    end

    local now = CurTime()
    if now >= nextRelations then
        nextRelations = now + RELATION_EVERY
        applyAll()
    end

    for _, teamId in ipairs(TEAMS) do
        planTeam(teamId, aliveBots(teamId), now)
    end

    -- During prep, bots stand in their spawn like players do. Spawning and
    -- relations still run, so they are present when the prep ends.
    local prepping = TPG.Prep and TPG.Prep.IsConfining and TPG.Prep.IsConfining()
    local capRadius = TPG.Util.MetersToUnits(TPG.Config.capDistanceMeters or 5)
    local holdRadius = capRadius * 0.8

    for _, npc in ipairs(TPG.Bots.list) do
        -- An enemy means combat AI owns this bot; leave it alone.
        if not prepping and isAlive(npc) and not npc.TPG_Riding and not npc.TPG_BoardingSeat and not IsValid(npc:GetEnemy()) and goalHeld(npc, now) then
            local stand = npc.TPG_GoalStand
            if stand and not pointContested(npc, capRadius) then
                -- A defender at its cover spot. Tolerance is looser than the hold radius.
                if npc:GetPos():Distance(stand) > 60 then
                    npc:SetLastPosition(stand)
                    npc:SetSchedule(SCHED_FORCED_GO_RUN)
                end
            else
                local pos = IsValid(npc.TPG_Goal) and npc.TPG_Goal:GetPos() or goalPos(npc)
                -- A bot sent for the flag must get within the flag's pickup
                -- radius, which is tighter than the hold radius, so it heads
                -- straight onto the flag instead of stopping short of it.
                local onFlag = IsValid(npc.TPG_Goal) and npc.TPG_Goal:GetClass() == "tpg_flag"
                if onFlag then
                    if npc:GetPos():Distance(pos) > FLAG_REACH then
                        npc:SetLastPosition(pos)
                        npc:SetSchedule(SCHED_FORCED_GO_RUN)
                    end
                elseif npc:GetPos():Distance(pos) > holdRadius then
                    npc:SetLastPosition(pos + randomOffset(DEFEND_SPREAD))
                    npc:SetSchedule(SCHED_FORCED_GO_RUN)
                end
            end
        end

        if npc.TPG_BotRole == "at" and isAlive(npc) then
            rearmAT(npc, now)
            pickATWeapon(npc)
        end
    end

    for _, teamId in ipairs(TEAMS) do
        local target = targetFor(teamId)
        local alive  = countAlive(teamId)

        if cvFill:GetInt() > 0 and alive > target then
            removeOne(teamId)
        elseif alive < target and now >= nextSpawn[teamId] and canSpawn() then
            nextSpawn[teamId] = now + SPAWN_GAP
            TPG.Bots.SpawnOne(teamId)
        end
    end
end

-- Spawn bots up to each team's target right now, without waiting for the brain.
local function topUp()
    if not TPG.State.round.active then return end
    if not canSpawn() then return end

    for _, teamId in ipairs(TEAMS) do
        local missing = targetFor(teamId) - countAlive(teamId)
        for _ = 1, missing do
            TPG.Bots.SpawnOne(teamId)
        end
    end
end

--- Spawn one infantry NPC for a team at its spawn point.
-- Does nothing if the team has no spawn published this round. The role is
-- chosen by @{pickRole}, and the weapon by @{pickWeapon}.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @treturn ?Entity The new NPC, or nil.
-- @realm server
function TPG.Bots.SpawnOne(teamId)
    local base = TPG.State.GetSpawn(teamId)
    if not base then return nil end

    -- Scatter the spawn a little, then drop it onto the ground beneath.
    local xy  = base + randomOffset(SPAWN_SPREAD)
    local tr  = util.TraceLine({
        start  = xy + Vector(0, 0, 64),
        endpos = xy + Vector(0, 0, -256),
        mask   = MASK_SOLID_BRUSHONLY,
    })
    local pos = (tr.Hit and tr.HitPos or xy) + Vector(0, 0, 8)

    local className = (teamId == TEAM_GREEN) and "npc_citizen" or "npc_combine_s"
    local npc = ents.Create(className)
    if not IsValid(npc) then return nil end

    if teamId == TEAM_GREEN then
        npc:SetKeyValue("citizentype", "3") -- rebel
    end

    -- Spawnflags have to be set before Spawn. Both bits default to off, so a
    -- bot drops its gun and leaves a corpse that fades unless the convars ask.
    local flags = 0
    if not cvDrops:GetBool() then flags = flags + 8192 end   -- SF_NPC_NO_WEAPON_DROP
    if not cvCorpses:GetBool() then flags = flags + 512 end  -- SF_NPC_FADE_CORPSE
    if flags ~= 0 then npc:SetKeyValue("spawnflags", tostring(flags)) end

    npc:SetPos(pos)
    npc:Spawn()
    npc:Activate()

    local role = pickRole(teamId)
    npc.TPG_BotRole = role
    if role == "at" then
        local def = TPG.Bots.Roles.at
        npc.TPG_Sidearm = pickFrom(def.secondary, def.secondaryFallback)
        npc:Give(npc.TPG_Sidearm)
        npc.TPG_Launcher = pickWeapon("at")
        npc:Give(npc.TPG_Launcher)
    else
        npc:Give(pickWeapon(role))
    end

    npc.TPG_ProtectedUntil = CurTime() + (TPG.Config.spawnProtectionTime or 5)
    npc.TPG_BotTeam = teamId
    npc:SetNWInt("TPG_BotTeam", teamId)
    npc:SetNWString("TPG_BotName", botName(npc))
    -- The fade spawnflag only reaches server ragdolls; bots/cl_corpses.lua
    -- fades the client-side ones.
    npc:SetNWBool("TPG_FadeCorpse", not cvCorpses:GetBool())
    npc:SetCurrentWeaponProficiency(proficiency())

    TPG.Bots.list[#TPG.Bots.list + 1] = npc
    applyRelations(npc)

    return npc
end

--- Remove every test NPC.
-- @realm server
function TPG.Bots.RemoveAll()
    for _, npc in ipairs(TPG.Bots.list) do
        if IsValid(npc) then npc:Remove() end
    end
    TPG.Bots.list = {}
end

--- Set bots per team. 0 removes every bot and stops the brain, unless fill
-- mode (`tpg_bots_fill`) is on, which takes precedence. Anything else starts
-- the brain and fills both teams up to that count.
-- @tparam number n Bots per team, clamped to 0..16.
-- @realm server
function TPG.Bots.SetCount(n)
    n = TPG.Util.Clamp(math.floor(tonumber(n) or 0), 0, MAX_PER_TEAM)
    TPG.Bots.perTeam = n

    if n == 0 and cvFill:GetInt() <= 0 then
        stopBrain()
        TPG.Bots.RemoveAll()
        return
    end

    startBrain()
    topUp()
end

--- Can bots on this map path anywhere? Stock NPCs need the map's AI node
-- graph (`maps/graphs/<map>.ain`), and without one they stand still. The
-- Combat AI addon brings its own navmesh, so a loaded navmesh counts too.
-- @treturn boolean
-- @realm server
function TPG.Bots.MapSupported()
    if file.Exists("maps/graphs/" .. game.GetMap() .. ".ain", "GAME") then return true end
    return istable(CAI) and navmesh ~= nil and isfunction(navmesh.IsLoaded) and navmesh.IsLoaded() == true
end

--- A bot's display name, its team and role, such as "Green AT".
-- @tparam Entity npc A TPG bot.
-- @treturn string
-- @realm server
function TPG.Bots.Name(npc) return botName(npc) end

--- Kill feed name for an entity. Overrides the stock gamemode method: a bot
-- gets its team and role ("Green AT") instead of its class, which the death
-- notice takes as a plain string. Everything else goes to the stock method.
-- @tparam Entity|string ent
-- @treturn ?string
-- @realm server
function GM:GetDeathNoticeEntityName(ent)
    if not isstring(ent) and IsValid(ent) and ent.TPG_BotTeam then
        return botName(ent)
    end
    return self.BaseClass.GetDeathNoticeEntityName(self, ent)
end

-- Fire the start-up state, so a server that boots with fill on runs the
-- brain without waiting for a convar change.
if cvFill:GetInt() > 0 then startBrain() end

cvars.AddChangeCallback("tpg_bots_fill", function(_, _, new)
    if (tonumber(new) or 0) > 0 then
        startBrain()
    elseif TPG.Bots.perTeam <= 0 then
        stopBrain()
        TPG.Bots.RemoveAll()
    end
end, "TPG_BotsFill")

cvars.AddChangeCallback("tpg_bots_difficulty", function()
    local prof = proficiency()
    for _, npc in ipairs(TPG.Bots.list) do
        if IsValid(npc) then npc:SetCurrentWeaponProficiency(prof) end
    end
end, "TPG_BotsDifficulty")

hook.Add("PlayerSpawn", "TPG_Bots", function()
    timer.Simple(0, applyAll)
end)

-- Player:SetTeam runs this before the new team is stored, so the refresh
-- waits a tick to see it.
hook.Add("PlayerChangedTeam", "TPG_Bots", function()
    timer.Simple(0, applyAll)
end)

-- Round reset. Only fires on the spectator-keep cleanup path; the plain
-- game.CleanUpMap path skips it, and the brain tops teams up regardless.
hook.Add("PostCleanupMap", "TPG_Bots", function()
    TPG.Bots.list = {}
    nextSpawn = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }

    timer.Simple(0.5, function()
        if TPG.Bots.perTeam > 0 or cvFill:GetInt() > 0 then topUp() end
    end)
end)

-- Same-team damage is blocked whenever a bot is either side of it, except a
-- player hurting a bot on their own team while `tpg_bots_friendly_fire` is on.
-- A bot never hurts its own team. A bot shooting a player on the other team
-- is untouched.
hook.Add("EntityTakeDamage", "TPG_BotsFriendlyFire", function(victim, dmg)
    -- Spawn protection: a bot inside its grace period takes no damage, from
    -- anyone. The zone kill is the one exception, so it can still land.
    if victim.TPG_BotTeam and not victim.TPG_ZoneKill and (victim.TPG_ProtectedUntil or 0) > CurTime() then
        return true
    end

    local attacker = dmg:GetAttacker()
    if victim == attacker or not IsValid(victim) or not IsValid(attacker) then return end
    if not (victim.TPG_BotTeam or attacker.TPG_BotTeam) then return end

    local side = TPG.Util.TeamOf(victim)
    if side ~= nil and side == TPG.Util.TeamOf(attacker) then
        if cvFriendly:GetBool() and victim.TPG_BotTeam and attacker:IsPlayer() then return end
        return true
    end
end)

-- Fires for every death; bots only. The economy pays a player's kill from
-- this (systems/sv_economy.lua).
hook.Add("OnNPCKilled", "TPG_Bots", function(npc, attacker, inflictor)
    if not IsValid(npc) or not npc.TPG_BotTeam then return end

    -- The replacement waits out the respawn delay. topUp() ignores this, so the
    -- initial fill still goes straight out.
    local team = npc.TPG_BotTeam
    nextSpawn[team] = math.max(nextSpawn[team] or 0, CurTime() + cvRespawn:GetFloat())

    hook.Run("TPG_BotKilled", npc, attacker, inflictor)
end)

-- With ai_serverragdolls on (sandbox's Keep Corpses), an NPC's corpse is a
-- server ragdoll, and Source leaves those in place even with
-- SF_NPC_FADE_CORPSE set. Fade a bot's out here, after the same delay as
-- the client-side ones in bots/cl_corpses.lua.
local CORPSE_FADE_DELAY = 5

hook.Add("CreateEntityRagdoll", "TPG_BotCorpses", function(owner, rag)
    if not IsValid(owner) or not owner.TPG_BotTeam or cvCorpses:GetBool() then return end

    timer.Simple(CORPSE_FADE_DELAY, function()
        if IsValid(rag) then rag:Fire("FadeAndRemove", "1") end
    end)
end)

local function report(ply, text)
    if IsValid(ply) then TPG.Util.ChatMessage(ply, text) end
    print(text)
end

concommand.Add("tpg_bots_test", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        TPG.Util.ChatMessage(ply, "[TPG] Superadmin only.", Color(255, 0, 0))
        return
    end

    local want = tonumber(args[1]) or 4

    if want > 0 and not TPG.Bots.MapSupported() then
        TPG.Bots.SetCount(0)
        report(ply, "[TPG] This map has no AI nodes, so bots can't move. Not spawning any.")
        return
    end

    TPG.Bots.SetCount(want)

    local fill = cvFill:GetInt()
    if fill > 0 then
        report(ply, string.format("[TPG] NPC test mode: fill mode is on (tpg_bots_fill %d), which overrides the count of %d",
            fill, TPG.Bots.perTeam))
        return
    end

    local n = TPG.Bots.perTeam

    if n == 0 then
        report(ply, "[TPG] NPC test mode: off")
        return
    end

    local ai = caiPresent() and "Combat AI addon detected" or "stock AI"
    report(ply, string.format("[TPG] NPC test mode: %d per team (%s)", n, ai))

    if caiPresent() and navmesh and navmesh.IsLoaded and not navmesh.IsLoaded() then
        report(ply, "[TPG] Warning: the Combat AI addon needs a navmesh, and this map has none.")
    end
end)
