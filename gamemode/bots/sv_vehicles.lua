--[[--
    Bot seats: NPC bots riding in a player's own vehicle.

    A player marks seats on a vehicle they own (E2 or Starfall, through the
    tpg_e2sf addon). A bot on the same team whose goal is far away boards a
    free marked seat nearby, rides inside the vehicle, and gets out near its
    goal, or when a player takes the seat and stays in it for
    `tpg_bots_seat_grace` seconds. A bot boards at the seat's exit point, so
    the exit point is also the vehicle's door.

    The riding bot itself and its weapon are hidden; a look-alike prop with
    the matching player model sits in the seat instead (`TPG_Lookalike` on the
    bot).
    Damage to the seat reaches the rider, as it reaches a seated player.

    A riding bot gets no movement orders: sv_bots.lua and sv_cai.lua skip it,
    and TPG.Util.Fighters leaves it out of control point counts.

    State on the vehicle: `TPG_BotSeat` (marked), `TPG_BotExit` (exit point as
    a local offset from the seat, or nil), `TPG_Rider` (the bot riding it),
    `TPG_SeatTeam` (the owner's team when marked), `TPG_ClaimAt` (when a player
    sat down in a seat that had a rider).

    State on the bot: `TPG_Riding` (the seat it rides in), `TPG_BoardingSeat`
    (the seat it is walking to), `TPG_BoardPos` (the spot it is walking to),
    `TPG_HiddenWeapon` (its weapon while riding), and `TPG_DismountReason`
    (why it got out last).

    A timer, `TPG_BotsVehicles`, runs the boarding and dismount checks every
    half second.

    Convars: `tpg_bots_seat_grace`.

    @module tpg.bots.vehicles
    @realm server
]]

TPG.Bots = TPG.Bots or {}
TPG.Bots.Vehicles = TPG.Bots.Vehicles or {}

local cvGrace = CreateConVar("tpg_bots_seat_grace", "3", { FCVAR_ARCHIVE },
    "Seconds a player must stay in a bot seat before the bot riding it gets out.")

local TIMER         = "TPG_BotsVehicles"
local TICK          = 0.5
local MAX_EXIT      = 250   -- exit offsets are clamped to this length
local TRIP_MIN      = 3000  -- a goal further away than this is worth a ride
local BOARD_RANGE   = 700   -- seats this close to the bot can be boarded
local BOARD_REACH   = 90    -- the bot mounts once this close to its seat or the seat's exit spot
local BOARD_TIMEOUT = 20    -- give up walking to a seat after this many seconds
local BOARD_RESEND  = 2     -- how often the walk to a seat is re-issued
local ARRIVE_RANGE  = 1500  -- an exit this close to the goal counts as arrived
local ARRIVE_SPEED  = 150   -- and the vehicle must be slower than this
local EXIT_RANGE    = 260   -- exit spots must be this close to the seat
local EXIT_RING     = 100   -- radius of the fallback ring around the seat
local EXIT_PROTECT  = 1     -- seconds of spawn protection after getting out

local HULL_MINS = Vector(-16, -16, 0)
local HULL_MAXS = Vector(16, 16, 72)

-- Every marked seat, as a set. Weak keys, so a removed seat never lingers.
local marked = setmetatable({}, { __mode = "k" })

local function alive(npc)
    return IsValid(npc) and npc:Health() > 0
end

local function isPlayingTeam(t)
    return t == TEAM_GREEN or t == TEAM_RED
end

-- Only the chip owner of a vehicle, on a playing team, may mark its seats.
local function mayControl(owner, seat)
    if not (IsValid(owner) and owner:IsPlayer()) then return false end
    if not (IsValid(seat) and seat:IsVehicle()) then return false end
    if not isfunction(seat.CPPIGetOwner) then return false end
    if seat:CPPIGetOwner() ~= owner then return false end
    return isPlayingTeam(owner:Team())
end

-- Whoever owns the seat is still on the team it was marked for.
local function ownerStillOnTeam(seat)
    if not isfunction(seat.CPPIGetOwner) then return false end
    local owner = seat:CPPIGetOwner()
    return IsValid(owner) and owner:IsPlayer() and owner:Team() == seat.TPG_SeatTeam
end

-- The top of a vehicle's parent chain, which is what moves and carries velocity.
local function rootOf(ent)
    local root, n = ent, 0
    while IsValid(root:GetParent()) and n < 32 do
        root = root:GetParent()
        n = n + 1
    end
    return root
end

-- Is `ent` the root or anything parented under it? A nil root matches nothing.
local function isUnder(ent, root)
    if not root or not IsValid(ent) then return false end
    local cur, n = ent, 0
    while IsValid(cur) and n < 32 do
        if cur == root then return true end
        cur = cur:GetParent()
        n = n + 1
    end
    return false
end

-- The contraption a vehicle belongs to, or nil for a stock vehicle.
local function contraptionOf(seat)
    if not isfunction(seat.CFW_GetContraption) then return nil end
    local con = seat:CFW_GetContraption()
    return istable(con) and con or nil
end

-- Can this bot board this seat right now? `range` caps the distance from the
-- bot, or nil for no cap. A seat another bot is already walking to is taken.
local function boardable(seat, npc, range)
    if not (IsValid(seat) and seat.TPG_BotSeat) then return false end
    if IsValid(seat.TPG_Rider) then return false end
    if IsValid(seat:GetDriver()) then return false end
    if seat.TPG_SeatTeam ~= npc.TPG_BotTeam then return false end
    if not ownerStillOnTeam(seat) then return false end
    if range and seat:GetPos():Distance(npc:GetPos()) > range then return false end

    for _, other in ipairs(TPG.Bots.list) do
        if IsValid(other) and other ~= npc and other.TPG_BoardingSeat == seat then
            return false
        end
    end
    return true
end

-- The boardable seat nearest the bot on the most armored vehicle.
local function bestSeat(npc)
    local best, bestArmor, bestDist
    for seat in pairs(marked) do
        if boardable(seat, npc, BOARD_RANGE) then
            local con = contraptionOf(seat)
            local armor = (con and con.ACEArmorPoints) or 0
            local d = seat:GetPos():DistToSqr(npc:GetPos())
            if not best or armor > bestArmor or (armor == bestArmor and d < bestDist) then
                best, bestArmor, bestDist = seat, armor, d
            end
        end
    end
    return best
end

-- Where a bot is heading: its goal entity if that is still valid, else its goal position.
local function goalOf(npc)
    if IsValid(npc.TPG_Goal) then return npc.TPG_Goal:GetPos() end
    return npc.TPG_GoalPos
end

-- Is this bot's goal far enough away to be worth a ride?
local function wantsRide(npc)
    local goal = goalOf(npc)
    return goal ~= nil and goal:Distance(npc:GetPos()) > TRIP_MIN
end

-- Has the bot's vehicle reached its goal? It must be near the goal and slow.
local function arrived(npc, seat)
    local goal = goalOf(npc)
    if not goal then return false end
    if seat:GetPos():Distance(goal) > ARRIVE_RANGE then return false end
    return rootOf(seat):GetVelocity():Length() < ARRIVE_SPEED
end

-- A standing spot at `pos`: it must be within range of the seat, outside every
-- safezone, on the ground, and with room for a standing NPC. Returns the spot
-- or nil.
local function standingSpot(pos, center, root, npc)
    if pos:Distance(center) > EXIT_RANGE then return nil end
    if TPG.Protection.GetSafezoneTeam(pos) ~= nil then return nil end

    local down = util.TraceLine({
        start  = pos + Vector(0, 0, 32),
        endpos = pos - Vector(0, 0, 512),
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if not down.Hit or down.StartSolid then return nil end

    local ground = down.HitPos + Vector(0, 0, 2)
    local hull = util.TraceHull({
        start  = ground,
        endpos = ground,
        mins   = HULL_MINS,
        maxs   = HULL_MAXS,
        mask   = MASK_NPCSOLID,
        filter = function(ent) return not (ent == npc or isUnder(ent, root)) end, -- true = hit
    })
    if hull.Hit or hull.StartSolid then return nil end
    return ground
end

-- Where a bot gets out: the seat's exit point, then eight spots on a ring
-- around the seat, then straight above the seat. If the seat is already gone,
-- the bot's last known seat position is the centre.
local function findExit(seat, npc)
    local live   = IsValid(seat)
    local center = live and seat:GetPos() or (npc.TPG_LastSeatPos or npc:GetPos())
    local root   = live and rootOf(seat) or nil

    local first
    if live and seat.TPG_BotExit then
        first = seat:LocalToWorld(seat.TPG_BotExit)
    else
        first = center + (live and seat:GetRight() or Vector(1, 0, 0)) * 80
    end

    local spot = standingSpot(first, center, root, npc)
    if spot then return spot end

    for i = 0, 7 do
        local a = math.rad(i * 45)
        local p = center + Vector(math.cos(a), math.sin(a), 0) * EXIT_RING
        spot = standingSpot(p, center, root, npc)
        if spot then return spot end
    end

    return center + Vector(0, 0, 100)
end

-- ── Look-alike ──────────────────────────────────────────────────────────────
-- NPC models have no seated pose, so the hidden bot is shown by a prop with
-- the matching player model, sitting the way a player in that seat would.

local FEET_ATTACHMENT = "vehicle_feet_passenger0"
local REBEL_MODEL     = "models/player/group03/male_07.mdl"
local COMBINE_MODEL   = "models/player/combine_soldier.mdl"

-- The player model for a bot: its citizen or Combine model under models/player/.
local function lookalikeModel(npc)
    local mdl = string.lower(npc:GetModel() or "")
    local candidates = {
        (string.gsub(mdl, "^models/humans/", "models/player/")),
        "models/player/" .. (string.match(mdl, "([^/]+)$") or ""),
    }
    for _, path in ipairs(candidates) do
        if path ~= mdl and util.IsValidModel(path) then return path end
    end
    return npc:GetClass() == "npc_combine_s" and COMBINE_MODEL or REBEL_MODEL
end

-- The sequence a player would play in this seat, picked the way the base
-- gamemode's HandlePlayerDriving does.
local function sitSequence(dummy, seat)
    local entry = isfunction(seat.GetVehicleClass) and list.Get("Vehicles")[seat:GetVehicleClass()]
    local handle = entry and entry.Members and entry.Members.HandleAnimation
    if isfunction(handle) then
        local ok, seq = pcall(handle, seat, dummy)
        if ok and isnumber(seq) and seq >= 0 then return seq end
    end

    local class = seat:GetClass()
    if class == "prop_vehicle_jeep" then return dummy:LookupSequence("drive_jeep") end
    if class == "prop_vehicle_airboat" then return dummy:LookupSequence("drive_airboat") end
    if class == "prop_vehicle_prisoner_pod" and seat:GetModel() == "models/vehicles/prisoner_pod_inner.mdl" then
        return dummy:LookupSequence("drive_pd")
    end
    return dummy:LookupSequence("sit_rollercoaster")
end

local function removeLookalike(npc)
    if IsValid(npc.TPG_Lookalike) then npc.TPG_Lookalike:Remove() end
    npc.TPG_Lookalike = nil
end

-- Sit a look-alike of the bot in the seat. It is parented to the seat's feet
-- attachment, which is where the engine puts a seated player.
local function addLookalike(npc, seat)
    removeLookalike(npc)

    local dummy = ents.Create("prop_dynamic")
    if not IsValid(dummy) then return end
    dummy:SetModel(lookalikeModel(npc))
    dummy:SetKeyValue("solid", "0")
    local seq = sitSequence(dummy, seat)
    if seq and seq >= 0 then dummy:SetKeyValue("DefaultAnim", dummy:GetSequenceName(seq)) end
    dummy:Spawn()
    dummy:SetSolid(SOLID_NONE)
    dummy:SetSkin(npc:GetSkin())

    local att = seat:LookupAttachment(FEET_ATTACHMENT)
    if att and att > 0 then
        dummy:SetParent(seat, att)
        dummy:SetLocalAngles(angle_zero)
    else
        dummy:SetParent(seat)
        dummy:SetLocalAngles(Angle(0, 90, 0))
    end
    dummy:SetLocalPos(vector_origin)
    if seq and seq >= 0 then dummy:ResetSequence(seq) end

    -- Not part of the vehicle: no dupes, no tools, no physgun.
    dummy.DoNotDuplicate = true
    dummy.PhysgunDisabled = true
    dummy.m_tblToolsAllowed = {}
    dummy.TPG_LookalikeOf = npc

    seat:DeleteOnRemove(dummy)
    npc.TPG_Lookalike = dummy
end

-- Clear a bot's ride state and unparent it. Returns the seat it rode in.
local function release(npc)
    local seat = npc.TPG_Riding
    npc.TPG_Riding = nil
    npc.TPG_BoardingSeat = nil
    if IsValid(seat) and seat.TPG_Rider == npc then seat.TPG_Rider = nil end
    removeLookalike(npc)

    npc:SetParent()
    npc:SetNoDraw(false)
    npc:SetNotSolid(false)
    npc:SetMoveType(MOVETYPE_STEP)
    npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
    npc:RemoveFlags(FL_NOTARGET)
    if IsValid(npc.TPG_HiddenWeapon) then npc.TPG_HiddenWeapon:SetNoDraw(false) end
    npc.TPG_HiddenWeapon = nil
    return seat
end

-- Hide a bot inside a seat.
local function mount(npc, seat)
    npc.TPG_BoardingSeat = nil
    npc.TPG_BoardPos = nil
    npc.TPG_Riding = seat
    seat.TPG_Rider = npc

    npc:SetPos(seat:GetPos())
    npc:SetParent(seat)
    npc:SetNoDraw(true)
    npc:SetNotSolid(true)
    npc:SetMoveType(MOVETYPE_NONE)
    npc:AddEFlags(EFL_NO_THINK_FUNCTION)
    npc:SetSchedule(SCHED_IDLE_STAND)
    npc:AddFlags(FL_NOTARGET)
    addLookalike(npc, seat)

    -- The weapon is drawn on its own and would float where a standing NPC holds it.
    local wep = npc:GetActiveWeapon()
    if IsValid(wep) then
        wep:SetNoDraw(true)
        npc.TPG_HiddenWeapon = wep
    end
end

--- Put a riding bot out of its seat, at the seat's exit point where it can
-- stand. Does nothing for a bot that is not riding.
-- @tparam Entity npc
-- @tparam ?string reason Why it got out, kept on the bot as `TPG_DismountReason`.
-- @treturn boolean True if the bot was riding.
-- @realm server
function TPG.Bots.Vehicles.Dismount(npc, reason)
    if not IsValid(npc) or not npc.TPG_Riding then return false end

    local spot = findExit(npc.TPG_Riding, npc)
    release(npc)
    npc:SetPos(spot)
    npc.TPG_ProtectedUntil = CurTime() + EXIT_PROTECT
    npc.TPG_DismountReason = reason
    return true
end

--- Is this bot riding in a bot seat?
-- @tparam Entity npc
-- @treturn boolean
-- @realm server
function TPG.Bots.Vehicles.IsRiding(npc)
    return IsValid(npc) and IsValid(npc.TPG_Riding)
end

--- Where bots walk to board this seat: the standing spot they would get out
-- at, which is the seat's exit point when it has a usable one.
-- @tparam Entity seat
-- @treturn ?Vector The spot, or nil for an invalid seat.
-- @realm server
function TPG.Bots.Vehicles.BoardPos(seat)
    if not IsValid(seat) then return nil end
    return findExit(seat, nil)
end

--- The bot walking to this seat to board it, if any. At most one bot heads
-- for a seat at a time.
-- @tparam Entity seat
-- @treturn ?Entity The bot, or nil.
-- @realm server
function TPG.Bots.Vehicles.Boarder(seat)
    if not IsValid(seat) then return nil end
    for _, npc in ipairs(TPG.Bots.list) do
        if IsValid(npc) and npc.TPG_BoardingSeat == seat then return npc end
    end
    return nil
end

--- Mark or unmark a seat on the owner's vehicle as a bot seat. Unmarking
-- gets out whatever bot is riding in it.
-- @tparam Player owner The chip owner.
-- @tparam Entity seat A vehicle the owner owns.
-- @tparam boolean enabled True to mark, false to unmark.
-- @treturn boolean True if the request was allowed.
-- @realm server
function TPG.Bots.Vehicles.SetSeat(owner, seat, enabled)
    if not mayControl(owner, seat) then return false end

    if enabled then
        seat.TPG_BotSeat = true
        seat.TPG_SeatTeam = owner:Team()
        marked[seat] = true
        return true
    end

    local rider = seat.TPG_Rider
    seat.TPG_BotSeat = nil
    seat.TPG_SeatTeam = nil
    seat.TPG_ClaimAt = nil
    marked[seat] = nil
    if IsValid(rider) then TPG.Bots.Vehicles.Dismount(rider, "unmarked") end
    return true
end

--- Set where a bot gets out of a seat, as an offset from the seat. The offset
-- is clamped to 250 units, so a bot can never be sent far away.
-- @tparam Player owner The chip owner.
-- @tparam Entity seat A vehicle the owner owns.
-- @tparam Vector offset Local offset from the seat.
-- @treturn boolean True if the request was allowed.
-- @realm server
function TPG.Bots.Vehicles.SetExit(owner, seat, offset)
    if not mayControl(owner, seat) then return false end
    if not isvector(offset) then return false end

    local len = offset:Length()
    if len > MAX_EXIT then offset = offset * (MAX_EXIT / len) end
    seat.TPG_BotExit = Vector(offset.x, offset.y, offset.z)
    return true
end

-- Drop seats that were removed from the set.
local function pruneMarked()
    for seat in pairs(marked) do
        if not IsValid(seat) then marked[seat] = nil end
    end
end

-- Get riders out when their ride is over: the round ended, the seat was
-- unmarked, a player has held the seat past the grace period, or the vehicle
-- has reached the rider's goal.
local function ridersTick(now, active)
    local grace = cvGrace:GetFloat()

    for seat in pairs(marked) do
        local rider = seat.TPG_Rider
        if rider and not IsValid(rider) then
            seat.TPG_Rider = nil
        elseif IsValid(rider) then
            local reason
            if not active then
                reason = "round ended"
            elseif not seat.TPG_BotSeat then
                reason = "unmarked"
            elseif seat.TPG_ClaimAt and IsValid(seat:GetDriver()) and now - seat.TPG_ClaimAt >= grace then
                reason = "claimed"
            end

            if reason then
                TPG.Bots.Vehicles.Dismount(rider, reason)
            else
                rider.TPG_LastSeatPos = seat:GetPos()
                if arrived(rider, seat) then TPG.Bots.Vehicles.Dismount(rider, "arrived") end
            end
        end
    end
end

-- Walk a bot to a boardable seat, and mount it once it is close enough.
local function boarderTick(npc, now)
    if IsValid(npc:GetEnemy()) or not wantsRide(npc) then
        npc.TPG_BoardingSeat = nil
        npc.TPG_BoardPos = nil
        return
    end

    local seat = npc.TPG_BoardingSeat
    local stillGood = seat ~= nil
        and now - (npc.TPG_BoardStart or now) <= BOARD_TIMEOUT
        and boardable(seat, npc, BOARD_RANGE * 1.5)

    if not stillGood then
        seat = bestSeat(npc)
        npc.TPG_BoardingSeat = seat
        npc.TPG_BoardStart = now
        npc.TPG_BoardSentAt = nil
        npc.TPG_BoardPos = nil
    end
    if not seat then return end

    -- A seat deep inside a contraption cannot be walked up to, so the bot
    -- heads for the spot it would get out at and boards from there. The spot
    -- is worked out again with each walk order, as the vehicle may move.
    local pos = npc:GetPos()
    local door = npc.TPG_BoardPos
    if pos:Distance(seat:GetPos()) <= BOARD_REACH or (door and pos:Distance(door) <= BOARD_REACH) then
        mount(npc, seat)
    elseif now >= (npc.TPG_BoardSentAt or 0) + BOARD_RESEND then
        door = findExit(seat, npc)
        npc.TPG_BoardPos = door
        npc.TPG_BoardSentAt = now
        npc:SetLastPosition(door)
        npc:SetSchedule(SCHED_FORCED_GO_RUN)
    end
end

local function tick()
    pruneMarked()

    local now = CurTime()
    local active = TPG.State.round.active and true or false
    ridersTick(now, active)

    for _, npc in ipairs(TPG.Bots.list) do
        if IsValid(npc) and not npc.TPG_Riding then
            if active and alive(npc) then
                boarderTick(npc, now)
            else
                npc.TPG_BoardingSeat = nil
            end
        end
    end
end

-- An error inside a repeating timer removes it, so each tick reports its error and carries on.
timer.Create(TIMER, TICK, 0, function() ProtectedCall(tick) end)

-- A player sitting down in a seat that has a rider starts the grace period.
hook.Add("PlayerEnteredVehicle", "TPG_BotsVehicleEnter", function(_, veh)
    if marked[veh] and IsValid(veh.TPG_Rider) then
        veh.TPG_ClaimAt = CurTime()
    end
end)

hook.Add("PlayerLeaveVehicle", "TPG_BotsVehicleLeave", function(_, veh)
    if IsValid(veh) then veh.TPG_ClaimAt = nil end
end)

-- A rider that dies lets go of its seat, so the seat can be boarded again.
hook.Add("OnNPCKilled", "TPG_BotsVehicleDeath", function(npc)
    if IsValid(npc) and npc.TPG_Riding then release(npc) end
end)

-- Hurting the seat hurts its rider, the way it hurts a seated player. For an
-- ACE hit, ACE.VehicleDamage hurts the driver by 40 times the seat's damage
-- and kills them when the seat is destroyed; a rider gets the same. The
-- damage goes through TakeDamage, so friendly fire and spawn protection
-- still apply.
local ACE_DRIVER_DAMAGE = 40

hook.Add("ACE_OnDamage", "TPG_BotsSeatDamage", function(ent, _, _, _, inflictor, _, gun, _, hitRes)
    if not marked[ent] or not istable(hitRes) or hitRes.KineticThresholdFailed then return end
    local rider = ent.TPG_Rider
    if not alive(rider) then return end

    local attacker = IsValid(inflictor) and inflictor or game.GetWorld()
    gun = IsValid(gun) and gun or attacker
    if hitRes.Kill then
        rider:TakeDamage(math.max(rider:Health(), 1) * 10, attacker, gun)
    elseif (hitRes.Damage or 0) > 0 then
        rider:TakeDamage(hitRes.Damage * ACE_DRIVER_DAMAGE, attacker, gun)
    end
end)

-- Anything else that hurts the seat (bullets, explosions) is passed on as is.
hook.Add("EntityTakeDamage", "TPG_BotsSeatDamage", function(ent, dmg)
    if not marked[ent] then return end
    local rider = ent.TPG_Rider
    if not alive(rider) or dmg:GetDamage() <= 0 then return end
    rider:TakeDamage(dmg:GetDamage(), dmg:GetAttacker(), dmg:GetInflictor())
end)

-- A removed seat gets its rider out where it was last seen. A removed bot frees its seat.
hook.Add("EntityRemoved", "TPG_BotsVehicleRemoved", function(ent)
    if marked[ent] then
        marked[ent] = nil
        local rider = ent.TPG_Rider
        if IsValid(rider) then TPG.Bots.Vehicles.Dismount(rider, "seat removed") end
    end

    local seat = ent.TPG_Riding
    if IsValid(seat) and seat.TPG_Rider == ent then seat.TPG_Rider = nil end
end)
