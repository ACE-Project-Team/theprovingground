--[[--
    tpg_controlpoint (client): the model draw only.

    All status (name, capture progress, colour) is drawn as HUD overlay
    elsewhere (`gamemode/ui/cl_hud.lua`, `cl_hud_objectives.lua`), read off this
    entity's networked vars -- this file has nothing of its own to add beyond
    the model, which already picks up the server-set `Color` automatically via
    DrawModel.

    @module tpg.ent.controlpoint.client
    @realm client
]]
include("shared.lua")

--- Draws the model, nothing else.
-- @realm client
function ENT:Draw()
    self:DrawModel()
end