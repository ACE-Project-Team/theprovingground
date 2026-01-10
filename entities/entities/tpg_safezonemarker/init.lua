AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/hunter/misc/shell2x2.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    
    self.Scale = self.Scale or (TPG.Config.safezoneRadius * 2)
    
    local modelScale = self.Scale / 95.4 / 2
    self:SetModelScale(modelScale, 0)
    self:SetMaterial("models/props_combine/com_shield001a")
end

function ENT:Think()
end