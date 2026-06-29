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

function ENT:SetHome(pos)
    self.HomePos = pos
    self:SetPos(pos)
end

function ENT:ReturnHome(reason)
    self:SetFlagState(self.STATE_HOME)
    self:SetPossessTeam(0)
    self:SetCarrier(NULL)
    self:SetPos(self.HomePos)
    TPG.Util.ChatBroadcast("[CTF] The flag reset" ..
        (reason and (" (" .. reason .. ")") or "") .. ".", Color(230, 230, 230))
end

function ENT:PickUp(ply)
    self:SetFlagState(self.STATE_CARRIED)
    self:SetPossessTeam(ply:Team())
    self:SetCarrier(ply)

    self:EmitSound("ambient/alarms/warningbell1.wav", 90, 110)
    local td = TPG.GetTeamData(ply:Team())
    TPG.Util.ChatBroadcast("[CTF] " .. ply:Nick() .. " grabbed the flag for " ..
        td.name .. "!", td.color)
end

function ENT:Drop()
    local c   = self:GetCarrier()
    local pos = (IsValid(c) and (c:GetPos() + Vector(0, 0, 10))) or self:GetPos()

    self:SetFlagState(self.STATE_DROPPED)
    self:SetPossessTeam(0)
    self:SetCarrier(NULL)
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
            self:SetPos(self:GetCarrier():GetPos() + Vector(0, 0, 72))
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

        -- Possession drains the enemy's tickets (a mobile hill). The round's
        -- normal win check (RoundThink) resolves CTF wins from this.
        local enemy = TPG.GetEnemyTeam(c:Team())
        local drain = (TPG.Config.ctfHoldDrainPerSec or 4) * STEP
        TPG.State.AddScore(enemy, -drain)

        if TPG.Economy and TPG.Economy.Reward then
            TPG.Economy.Reward(c, (TPG.Config.ctfHoldRewardPerSec or 15) * STEP, "ctf_hold")
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
