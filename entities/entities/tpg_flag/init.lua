--[[--
    tpg_flag (server): all gameplay, meaning pickup, carry, drop, return and
    delivery, lives in this file.

    See the module header in `shared.lua` for the spawn contract:
    @{tpg.ctf.SpawnFlags} must set `HomePos`, call `Spawn`, then `SetHome`.

    @module tpg.ent.flag.server
    @realm server
]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local PICKUP_RADIUS = 100
local STEP          = 0.1   -- real-time gameplay step (tickrate-independent)

--- Resets flag state to STATE_HOME/no possessor. `self.HomePos` is only
-- initialised here if not already set by the spawner (`TPG.CTF.SpawnFlags`
-- normally sets it first), so a flag created any other way still gets a
-- sane home rather than nil.
-- @realm server
function ENT:Initialize()
    self:SetModel("models/props_gameplay/cap_point_base.mdl")
    self:PhysicsInit(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:DrawShadow(false)

    self.HomePos   = self.HomePos or self:GetPos()
    self.DroppedAt = 0
    self.LastStep  = CurTime()

    self:SetFlagState(self.STATE_HOME)
    self:SetPossessTeam(0)
    self:SetCarrier(NULL)
end

--- The flag's HUD marker looks it up clientside, so it must be networked to
-- everyone regardless of PVS (same as `tpg_controlpoint`).
-- @treturn number TRANSMIT_ALWAYS
-- @realm server
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

--- Sets `.HomePos` and teleports the flag there. Called by the spawner right
-- after `:Spawn()`; also usable to relocate a live flag directly (bypassing
-- the reset/broadcast that @{ENT:ReturnHome} does).
-- @tparam Vector pos
-- @realm server
function ENT:SetHome(pos)
    self.HomePos = pos
    self:SetPos(pos)
end

--[[--
    Reset the flag to STATE_HOME with no possessor, broadcast why, and
    teleport it to a freshly-rolled home spot.

    Re-rolls the home spot on every reset (via `TPG.CTF.RollFlagPoint`) rather
    than returning to a fixed position, so the flag moves around the map over
    a round (KOTH point vs. the CP points) instead of living wherever it first
    rolled at spawn. `RollFlagPoint` returns a fixed custom point if an admin
    placed one, so overridden maps still stay put. Called after a capture
    (from `TPG.CTF.OnCapture`), after a carry timeout, and after a
    drop-return timeout -- `reason` is only used for the chat line, it does
    not change any behaviour.

    @tparam ?string reason Shown in the broadcast, e.g. `"captured"`,
     `"carried too long"`, `"timed out"`. Omit for a bare reset message.
    @realm server
]]
function ENT:ReturnHome(reason)
    if TPG.CTF and TPG.CTF.RollFlagPoint then
        local pt = TPG.CTF.RollFlagPoint()
        if pt then self.HomePos = pt + Vector(0, 0, 5) end
    end

    self:SetFlagState(self.STATE_HOME)
    self:SetPossessTeam(0)
    self:SetCarrier(NULL)
    self:SetCarryEnd(0)
    self:SetPos(self.HomePos)
    TPG.Util.ChatBroadcast("[CTF] The flag reset" ..
        (reason and (" (" .. reason .. ")") or "") .. ".", Color(230, 230, 230))
end

--- Enters STATE_CARRIED for `ply`, starts the carry clock and networks
-- `CarryEnd` (`CurTime() + TPG.Config.ctfMaxCarryTime`) so the carrier's HUD
-- can count it down independently.
-- @tparam Player ply
-- @realm server
function ENT:PickUp(ply)
    self:SetFlagState(self.STATE_CARRIED)
    self:SetPossessTeam(ply:Team())
    self:SetCarrier(ply)
    self.CarryStart = CurTime()
    -- Networked so the carrier's HUD can count the carry timer down (cl_hud_ctf).
    self:SetCarryEnd(CurTime() + (TPG.Config.ctfMaxCarryTime or 150))

    self:EmitSound("ambient/alarms/warningbell1.wav", 90, 110)
    local td = TPG.GetTeamData(ply:Team())
    TPG.Util.ChatBroadcast("[CTF] " .. ply:Nick() .. " grabbed the flag for " ..
        td.name .. "!", td.color)
end

--[[--
    Enter STATE_DROPPED at (roughly) the carrier's last position, tracing
    straight down to land it on solid ground rather than floating.

    A carrier killed in the air (in an aircraft, off a cliff, rocket-jumping)
    would otherwise leave the flag floating at head height with a 100u pickup
    radius nobody on the ground can reach -- it'd just sit there until the
    return timer. The trace runs through world + props/vehicles (but not
    players, and not the ex-carrier) and drops it onto whatever surface is
    beneath; falls back to the old head-height spot if nothing's hit
    (`tr.Hit` false, or the trace went out to the skybox).

    @realm server
]]
function ENT:Drop()
    local c    = self:GetCarrier()
    local base = (IsValid(c) and c:GetPos()) or self:GetPos()

    local tr = util.TraceLine({
        start  = base + Vector(0, 0, 16),
        endpos = base - Vector(0, 0, 16384),
        filter = function(e) return e ~= c and not e:IsPlayer() end,
        mask   = MASK_SOLID,
    })
    local pos = (tr.Hit and not tr.HitSky) and (tr.HitPos + Vector(0, 0, 10))
        or (base + Vector(0, 0, 10))

    self:SetFlagState(self.STATE_DROPPED)
    self:SetPossessTeam(0)
    self:SetCarrier(NULL)
    self:SetCarryEnd(0)
    self:SetPos(pos)
    self.DroppedAt = CurTime()

    TPG.Util.ChatBroadcast("[CTF] The flag was dropped!", Color(255, 200, 80))
end

--- Whether the current carrier is still a legitimate holder: valid, a player,
-- alive, and on a team. Used by @{ENT:Think} to decide whether to drop the
-- flag every tick -- a carrier who disconnects, dies, or gets moved to
-- spectate all fail this the same way.
-- @treturn boolean
-- @realm server
function ENT:CarrierStillValid()
    local c = self:GetCarrier()
    return IsValid(c) and c:IsPlayer() and c:Alive() and TPG.Util.IsOnTeam(c)
end

--- Runs every server tick: rides the flag above an invalidated-or-not carrier
-- (dropping it the instant @{ENT:CarrierStillValid} fails), and throttles the
-- rest of gameplay (@{ENT:GameplayStep}) to a fixed `STEP` (0.1s) real-time
-- cadence so it isn't tied to tickrate.
-- @realm server
function ENT:Think()
    self:NextThink(CurTime())

    -- Carried flag rides above the carrier.
    if self:GetFlagState() == self.STATE_CARRIED then
        if not self:CarrierStillValid() then
            self:Drop()
        else
            self:SetPos(self:GetCarrier():GetPos() + Vector(0, 0, 50))
        end
    end

    if CurTime() - self.LastStep < STEP then return true end
    self.LastStep = CurTime()
    self:GameplayStep()

    return true
end

--[[--
    Per-state gameplay for one `STEP`: carry-timeout and delivery checks while
    carried, drop-timeout while dropped, and pickup scanning while home or
    dropped.

    Delivery is judged by `TPG.Protection.IsInSafezone(c)` when that module is
    loaded, falling back to a flat-radius check (`ctfDeliverRadius`, default
    500) against `TPG.State.spawns[c:Team()]` otherwise -- the fallback path
    exists so this still works if load order ever puts this file ahead of
    `TPG.Protection`, but it uses a DIFFERENT radius/shape than the real
    safezone, so a flag near the safezone edge could read as delivered under
    one path and not the other depending on which is active.

    Pickup: the FIRST alive, teamed player found within `PICKUP_RADIUS` in
    `player.GetAll()` iteration order grabs it -- not the nearest one -- so if
    two teammates are both in range on the same tick, which one gets credited
    depends on `player.GetAll()`'s ordering, not proximity.

    @realm server
]]
function ENT:GameplayStep()
    local state = self:GetFlagState()

    if state == self.STATE_CARRIED then
        local c = self:GetCarrier()
        if not IsValid(c) then return end

        -- Anti-hoarding: a single carry can't last forever.
        if self.CarryStart and CurTime() - self.CarryStart > (TPG.Config.ctfMaxCarryTime or 150) then
            self:ReturnHome("carried too long")
            return
        end

        -- Deliver by getting the flag into your own safezone. This matches where
        -- you actually gain spawn protection, instead of a tighter inner radius
        -- that forced you to walk deep past the safezone edge to score.
        local delivered = false
        if TPG.Protection and TPG.Protection.IsInSafezone then
            delivered = TPG.Protection.IsInSafezone(c)
        else
            local home = TPG.State.spawns[c:Team()]
            delivered = home and c:GetPos():Distance(home) < (TPG.Config.ctfDeliverRadius or 500)
        end

        if delivered then
            TPG.CTF.OnCapture(self, c)
        end
        return
    end

    if state == self.STATE_DROPPED then
        if CurTime() - self.DroppedAt > (TPG.Config.ctfReturnTime or 25) then
            self:ReturnHome("timed out")
            return
        end
    end

    -- Home or dropped: first alive teamed player in range grabs it.
    for _, ply in ipairs(player.GetAll()) do
        if not (IsValid(ply) and ply:Alive() and TPG.Util.IsOnTeam(ply)) then continue end
        if ply:GetPos():Distance(self:GetPos()) < PICKUP_RADIUS then
            self:PickUp(ply)
            return
        end
    end
end
