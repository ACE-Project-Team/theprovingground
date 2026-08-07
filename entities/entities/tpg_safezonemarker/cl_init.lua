--[[--
    tpg_safezonemarker (client): model draw only.

    The sphere shape, scale and transparency are all set server-side in
    `init.lua` and simply networked through the model/colour/scale the engine
    already syncs -- nothing here.

    @module tpg.ent.safezonemarker.client
    @realm client
]]
include("shared.lua")

--- Draws the model, nothing else.
-- @realm client
function ENT:Draw()
    self:DrawModel()
end