AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local PICKUP_RADIUS = 100
local STEP          = 0.1   -- real-time gameplay step (tickrate-independent)

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

-- The flag's HUD marker looks it up clientside, so it must be networked to
-- everyone regardless of PVS (same as tpg_controlpoint).
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:SetHome(pos)
    self.HomePos = pos
    self:SetPos(pos)
end

function ENT:ReturnHome(reason)
    -- Re-roll the home spot on every reset so the flag moves around the map over
    -- a round (KOTH point vs. the CP points) instead of living wherever it first
    -- rolled at spawn. RollFlagPoint returns a fixed custom point if an admin
    -- placed one, so overridden maps still stay put.
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

function ENT:Drop()
    local c    = self:GetCarrier()
    local base = (IsValid(c) and c:GetPos()) or self:GetPos()

    -- Snap the drop down to the ground below. A carrier killed in the air (in an
    -- aircraft, off a cliff, rocket-jumping) would otherwise leave the flag
    -- floating at head height with a 100u pickup radius nobody on the ground can
    -- reach -- it'd just sit there until the return timer. Trace straight down
    -- through world + props/vehicles (but not players) and drop it onto whatever
    -- surface is beneath; fall back to the old head-height spot if nothing's hit.
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

function ENT:CarrierStillValid()
    local c = self:GetCarrier()
    return IsValid(c) and c:IsPlayer() and c:Alive() and TPG.Util.IsOnTeam(c)
end

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
