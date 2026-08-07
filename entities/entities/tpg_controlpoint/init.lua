--[[--
    tpg_controlpoint (server): capture accumulation and ownership.

    See the module header in `shared.lua` for the shared capture-state scale.
    Spawned by @{tpg.objectives.SpawnAll}, which sets `.PointID`/`.PointName`
    and then calls `SetupNetworking`.

    @module tpg.ent.controlpoint.server
    @realm server
]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--- Sets up the (initially unowned/unnamed) point: physics, capture-progress
-- state and the real-time capture accumulator. The spawner must still call
-- @{ENT:SetupNetworking} after setting `.PointID`/`.PointName`, or the HUD
-- will show "Unnamed Point" and pip letter "?" forever.
-- @realm server
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

--- Objectives must exist on every client from the moment they join: the HUD
-- markers find them with ents.FindByClass clientside, so under default PVS
-- networking a point across the map simply didn't exist for you (no marker)
-- until you'd physically been near it once.
-- @treturn number TRANSMIT_ALWAYS
-- @realm server
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

--- Publish `.PointID`/`.PointName` to the networked vars the client and HUD
-- read. Call this after setting those two fields (typically right after
-- spawning); nothing else calls it automatically.
-- @realm server
function ENT:SetupNetworking()
    self:SetNWInt("PointID", self.PointID)
    self:SetNWString("PointName", self.PointName)
end

--- Drives the fixed-step capture accumulator (see @{ENT:CaptureStep}).
-- Runs every server tick but only advances gameplay in whole `captureStep`
-- (default 0.075s) increments, capped at 8 catch-up steps per call so a lag
-- spike cannot dump a huge burst of capture progress into a single frame.
-- @realm server
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
        self:CaptureStep(step)
    end

    return true
end

--[[--
    One fixed-size step of capture math: count who's standing on the point,
    move `CapProgress` toward whichever side outnumbers the other, and flip
    `CapOwnership` when it crosses `timeNeutral`/`-timeNeutral`.

    `dt` is the wall-clock duration of this step (seconds, defaulting to
    `TPG.Config.captureStep`). Progress is tracked in seconds, so
    `capTimeNeutral`/`capTimeMax` are real seconds regardless of tickrate or
    step size -- the old code added a whole `balance` per step instead, which
    made a point flip in ~0.75s no matter what `capTimeNeutral` said.

    Objective overtime (`TPG.Objectives.GetOvertime`) shrinks both time
    thresholds toward instant, and the SHRUNK ceiling (`timeMax`, stashed as
    `self.EffectiveCapTimeMax`) is what @{ENT:UpdateColor} divides by -- using
    the configured, un-shrunk `CapTimeMax` there was a real bug this file
    documents fixing: a fully-held point in overtime read as ~10% progress and
    rendered near-black.

    An unbalanced point tops up toward the ceiling at a flat 0.5/second when
    nobody is contesting it; a neutral (0-owner), empty point decays
    exponentially toward zero (`* 0.5^dt`, ~halves per second) rather than
    holding still.

    @tparam number dt Step duration in seconds.
    @realm server
]]
function ENT:CaptureStep(dt)
    dt = dt or (TPG.Config.captureStep or 0.075)
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
    
    -- Objective overtime shrinks capture times toward instant so a stalemated
    -- round can actually be broken (objectives/sv_objectives.lua). Outside
    -- overtime the factor is 1 and these are the configured times.
    local overtime = (TPG.Objectives and TPG.Objectives.GetOvertime
                      and TPG.Objectives.GetOvertime()) or 0
    local capScale = 1 - overtime * (1 - (TPG.Config.objOvertimeCapMul or 0.1))
    local timeNeutral = math.max(self.CapTimeNeutral * capScale, 0.5)
    local timeMax     = math.max(self.CapTimeMax * capScale, timeNeutral + 0.25)

    -- UpdateColor scales brightness by how close CapProgress is to its ceiling,
    -- so it needs the ceiling actually in force, not the configured one.
    self.EffectiveCapTimeMax = timeMax

    -- Calculate capture balance
    local maxPlayers = TPG.Config.capMaxPlayers or 3
    local balance = math.Clamp(greenOnPoint - redOnPoint, -maxPlayers, maxPlayers)

    if balance ~= 0 then
        -- One net player moves progress one second per real second.
        self.CapProgress = self.CapProgress + balance * dt

        if self.CapProgress > timeNeutral then
            self.CapProgress = math.min(self.CapProgress, timeMax)
            self.CapOwnership = (balance < -1) and 0 or 1
        elseif self.CapProgress < -timeNeutral then
            self.CapProgress = math.max(self.CapProgress, -timeMax)
            self.CapOwnership = (balance > 1) and 0 or -1
        else
            self.CapOwnership = 0
        end
    else
        -- Empty point: held points slowly top up to the max bonus; a contested
        -- (neutral) point bleeds progress back toward zero. Both rates are
        -- per-second, scaled by dt.
        if self.CapOwnership == 1 then
            self.CapProgress = math.min(self.CapProgress + 0.5 * dt, timeMax)
        elseif self.CapOwnership == -1 then
            self.CapProgress = math.max(self.CapProgress - 0.5 * dt, -timeMax)
        else
            self.CapProgress = self.CapProgress * (0.5 ^ dt)  -- ~halves per second
            if math.abs(self.CapProgress) < 0.01 then self.CapProgress = 0 end
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

local MIN_OWNED = 0.45

--[[--
    Point colour: team hue, brightness = how firmly it's held.

    Two things were wrong here in overtime. The ratio divided CapProgress by the
    CONFIGURED CapTimeMax while overtime clamps CapProgress to a much smaller
    effective ceiling (down to a tenth of it), so a fully-held point read as
    ratio ~0.1 and rendered as near-black -- you couldn't tell who owned it,
    which is exactly when it matters most. It divides by the ceiling actually in
    force now.

    Second, brightness ran all the way to 0 even outside overtime, so a point
    that was owned but freshly flipped was almost black too. Ownership is
    information, not decoration: MIN_OWNED keeps a held point unmistakably its
    team's colour, and the ratio only modulates the top of the range.

    Sets the entity's networked `Color` directly; there is no separate
    colour-sync net message.
    @realm server
]]
function ENT:UpdateColor()
    local ceiling = math.max(self.EffectiveCapTimeMax or self.CapTimeMax, 0.01)
    local ratio   = math.Clamp(math.abs(self.CapProgress) / ceiling, 0, 1)

    if self.CapOwnership == 1 then
        self:SetColor(Color(0, 255 * (MIN_OWNED + (1 - MIN_OWNED) * ratio), 0, 255))
    elseif self.CapOwnership == -1 then
        self:SetColor(Color(255 * (MIN_OWNED + (1 - MIN_OWNED) * ratio), 0, 0, 255))
    else
        -- Neutral: yellow, dimming as someone works it toward a capture. Floored
        -- too, so a contested point stays visible rather than fading to black.
        local neutral = MIN_OWNED + (1 - MIN_OWNED) * (1 - ratio)
        self:SetColor(Color(255 * neutral, 255 * neutral, 0, 255))
    end
end

--- Fires whenever `CapOwnership` actually changes value (checked once per
-- @{ENT:CaptureStep} call, not once per Think). Plays a sound, broadcasts a
-- chat line and, on an actual capture (not a return to neutral), calls
-- `TPG.Objectives.OnCapture(self, capTeam)` if that function exists.
-- @realm server
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
                TPG.Util.PlaySound(ply, "friends/friend_online.wav")
            else
                TPG.Util.PlaySound(ply, "friends/friend_offline.wav")
            end
        end
        
        -- Track capture for commendations
        if TPG.Objectives and TPG.Objectives.OnCapture then
            TPG.Objectives.OnCapture(self, capTeam)
        end
    end
end