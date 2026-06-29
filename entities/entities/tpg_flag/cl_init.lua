include("shared.lua")

--[[
    AAS-style waving flag, adapted for TPG: a pole with a cloth that waves on a
    sine, plus a 3D2D status billboard. Tinted by the carrying team, grey while
    neutral.
]]

local POLE_H      = 92
local SEGS        = 8
local SEGW        = 8
local SEGH        = 26
local RENDER_DIST = 4000 ^ 2

local NEUTRAL = Color(150, 150, 150)   -- solid grey (opaque, not the faded look from before)
local DARK    = Color(35, 35, 35)

local function possessColor(teamId)
    if teamId == TEAM_RED   then return Color(200, 45, 45) end
    if teamId == TEAM_GREEN then return Color(45, 200, 80) end
    return NEUTRAL
end

function ENT:Initialize()
    -- We draw the pole/cloth manually and skip the model, so give the entity
    -- generous render bounds or the engine culls it by the (undrawn) model.
    self:SetRenderBounds(Vector(-80, -80, 0), Vector(80, 80, POLE_H + 60))
end

function ENT:DrawCloth(top, fwd, right, col)
    local t = CurTime() * 5
    local prevTop, prevBot = top, top - Vector(0, 0, SEGH)

    for i = 1, SEGS do
        local wave = math.sin(t + i * 0.7) * (i / SEGS) * 6
        local nTop = top + (fwd * (SEGW * i)) + (right * wave) + Vector(0, 0, wave * 0.15)
        local nBot = nTop - Vector(0, 0, SEGH)

        render.DrawQuad(prevTop, nTop, nBot, prevBot, col)
        render.DrawQuad(prevBot, nBot, nTop, prevTop, col)

        prevTop, prevBot = nTop, nBot
    end
end

function ENT:Draw()
    -- Intentionally NOT DrawModel(): the underlying prop is a cap-point base
    -- platform, which read as "capture this point" and looked wrong floating
    -- over a carrier's head. We render just the pole + cloth ourselves.
    local col   = possessColor(self:GetPossessTeam())
    local state = self:GetFlagState()
    local pos   = self:GetPos()

    local yaw   = Angle(0, self:GetAngles().y, 0)
    local fwd   = yaw:Forward()
    local right = yaw:Right()
    local top   = pos + Vector(0, 0, POLE_H)

    render.SetColorMaterial()
    render.DrawBeam(pos, top, 2.5, 0, 1, DARK)
    render.DrawSphere(top, 4, 10, 10, col)

    if pos:DistToSqr(EyePos()) < RENDER_DIST then
        self:DrawCloth(top - Vector(0, 0, 4), fwd, right, col)
    end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local status, sCol
    if state == self.STATE_HOME then
        status, sCol = "NEUTRAL", NEUTRAL
    elseif state == self.STATE_CARRIED then
        local c = self:GetCarrier()
        local td = TPG.GetTeamData(self:GetPossessTeam())
        status = "HELD" .. (IsValid(c) and (": " .. c:Nick()) or "")
        sCol = (td and td.color) or col
    else
        status, sCol = "DROPPED", Color(255, 200, 80)
    end

    local face = Angle(0, lp:EyeAngles().y - 90, 90)
    cam.Start3D2D(pos + Vector(0, 0, POLE_H + 26), face, 0.18)
        draw.SimpleTextOutlined("FLAG", "Trebuchet24", 0, -14, col,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        draw.SimpleTextOutlined(status, "Trebuchet24", 0, 12, sCol,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
    cam.End3D2D()
end
