AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_gameplay/cap_point_base.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end
    
    -- These will be set after spawn by sv_objectives.lua
    self.PointID = 0
    self.PointName = "Unnamed Point"
    
    self.CapProgress = 0
    self.CapOwnership = 0  -- -1 = Red, 0 = Neutral, 1 = Green
    self.LastCapState = 0
    
    self.CapTimeNeutral = TPG.Config.capTimeNeutral or 10
    self.CapTimeMax = TPG.Config.capTimeMax or 15

    -- Capture logic runs on a fixed real-time cadence (see ENT:Think) so it
    -- isn't tied to server tickrate.
    self.LastCapStep = CurTime()
    self.CapAccum    = 0
end

-- Call this after setting PointID and PointName
function ENT:SetupNetworking()
    self:SetNWInt("PointID", self.PointID)
    self:SetNWString("PointName", self.PointName)
end

function ENT:Think()
    self:NextThink(CurTime())

    -- Advance capture progress at a fixed wall-clock step instead of every N
    -- ticks, so a 33-tick server captures at the same speed as a 66-tick one.
    -- The catch-up loop is clamped so a lag spike can't dump a huge burst of
    -- progress in a single frame.
    local step = TPG.Config.captureStep or 0.075
    self.CapAccum = self.CapAccum + (CurTime() - self.LastCapStep)
    self.LastCapStep = CurTime()

    local steps = 0
    while self.CapAccum >= step and steps < 8 do
        self.CapAccum = self.CapAccum - step
        steps = steps + 1
        self:CaptureStep()
    end

    return true
end

function ENT:CaptureStep()
    local greenOnPoint = 0
    local redOnPoint = 0
    local capRadius = TPG.Util.MetersToUnits(TPG.Config.capDistanceMeters or 5)
    
    -- Count players on point
    for _, ply in ipairs(player.GetAll()) do
        if not ply:Alive() or ply:InVehicle() then continue end
        
        local dist = ply:GetPos():Distance(self:GetPos())
        if dist > capRadius then continue end
        
        local teamId = ply:Team()
        if teamId == TEAM_GREEN then
            greenOnPoint = greenOnPoint + 1
        elseif teamId == TEAM_RED then
            redOnPoint = redOnPoint + 1
        end
    end
    
    -- Calculate capture balance
    local maxPlayers = TPG.Config.capMaxPlayers or 3
    local balance = math.Clamp(greenOnPoint - redOnPoint, -maxPlayers, maxPlayers)
    
    if balance ~= 0 then
        self.CapProgress = self.CapProgress + balance
        
        if self.CapProgress > self.CapTimeNeutral then
            self.CapProgress = math.min(self.CapProgress, self.CapTimeMax)
            self.CapOwnership = (balance < -1) and 0 or 1
        elseif self.CapProgress < -self.CapTimeNeutral then
            self.CapProgress = math.max(self.CapProgress, -self.CapTimeMax)
            self.CapOwnership = (balance > 1) and 0 or -1
        else
            self.CapOwnership = 0
        end
    else
        -- Decay towards current owner
        if self.CapOwnership == 1 then
            self.CapProgress = math.min(self.CapProgress + 0.5, self.CapTimeMax)
        elseif self.CapOwnership == -1 then
            self.CapProgress = math.max(self.CapProgress - 0.5, -self.CapTimeMax)
        else
            self.CapProgress = self.CapProgress * 0.5
        end
    end
    
    -- Update color and network state
    self:UpdateColor()
    self:SetNWInt("CapOwnership", self.CapOwnership)
    self:SetNWFloat("CapProgress", self.CapProgress)
    
    -- Check for capture state change
    if self.CapOwnership ~= self.LastCapState then
        self:OnCaptureStateChanged()
        self.LastCapState = self.CapOwnership
    end
end

function ENT:UpdateColor()
    local ratio = math.abs(self.CapProgress / self.CapTimeMax)
    
    if self.CapOwnership == 1 then
        self:SetColor(Color(0, 255 * ratio, 0, 255))
    elseif self.CapOwnership == -1 then
        self:SetColor(Color(255 * ratio, 0, 0, 255))
    else
        local neutralRatio = 1 - math.abs(self.CapProgress / self.CapTimeMax)
        self:SetColor(Color(255 * neutralRatio, 255 * neutralRatio, 0, 255))
    end
end

function ENT:OnCaptureStateChanged()
    if self.CapOwnership == 0 then
        -- Neutralized
        self:EmitSound("ambient/energy/whiteflash.wav", 100, 100, 1)
        TPG.Util.ChatBroadcast("[" .. self.PointName .. "] has been neutralized!", Color(255, 255, 0))
    else
        -- Captured
        self:EmitSound("ambient/alarms/warningbell1.wav", 100, 100, 1)
        
        local capTeam = (self.CapOwnership == 1) and TEAM_GREEN or TEAM_RED
        local teamData = TPG.GetTeamData(capTeam)
        
        TPG.Util.ChatBroadcast("[" .. self.PointName .. "] captured by " .. teamData.name .. "!", teamData.color)
        
        -- Play sounds and track captures
        for _, ply in ipairs(player.GetAll()) do
            if ply:Team() == capTeam then
                TPG.Util.PlaySound(ply, "Announcer.Success")
            else
                TPG.Util.PlaySound(ply, "Announcer.Failure")
            end
        end
        
        -- Track capture for commendations
        if TPG.Objectives and TPG.Objectives.OnCapture then
            TPG.Objectives.OnCapture(self, capTeam)
        end
    end
end