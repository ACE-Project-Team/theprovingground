--[[--
    tpg_controlpoint (client): the model draw only.

    All status (name, capture progress, colour) is drawn as HUD overlay
    elsewhere (`gamemode/ui/cl_hud.lua`, `cl_hud_objectives.lua`), read off this
    entity's networked vars -- this file has nothing of its own to add beyond
    the model, which already picks up the server-set `Color` automatically via
    DrawModel.

    The point model is TF2's `cap_point_base.mdl`. A player without TF2 mounted
    would see a floating ERROR there, so they get a flat base-game disc in the
    point's colour instead.

    @module tpg.ent.controlpoint.client
    @realm client
]]
include("shared.lua")

local FALLBACK_MODEL = "models/hunter/tubes/circle4x4.mdl"
local FALLBACK_SCALE = Vector(1.5, 1.5, 0.5)

--- Draws the model, or the fallback disc when the model isn't installed.
-- @realm client
function ENT:Draw()
    if util.IsValidModel(self:GetModel()) then
        self:DrawModel()
        return
    end

    if not IsValid(self.FallbackModel) then
        self.FallbackModel = ClientsideModel(FALLBACK_MODEL, RENDERGROUP_OPAQUE)
        if not IsValid(self.FallbackModel) then return end
        self.FallbackModel:SetNoDraw(true)
        local m = Matrix()
        m:Scale(FALLBACK_SCALE)
        self.FallbackModel:EnableMatrix("RenderMultiply", m)
        -- A missing model has no bounds, so the point would cull itself.
        self:SetRenderBounds(Vector(-150, -150, -10), Vector(150, 150, 30))
    end

    local disc = self.FallbackModel
    disc:SetPos(self:GetPos())
    disc:SetAngles(self:GetAngles())

    local col = self:GetColor()
    render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
    disc:DrawModel()
    render.SetColorModulation(1, 1, 1)
end

--- Frees the fallback disc.
-- @realm client
function ENT:OnRemove()
    if IsValid(self.FallbackModel) then self.FallbackModel:Remove() end
end
