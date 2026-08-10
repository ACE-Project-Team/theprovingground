--[[--
    tpg_safezonemarker (server): the visible spawn-safezone dome.

    Purely visual; the protection itself lives in `player/sv_protection.lua`.
    Spawned by @{tpg.objectives.SpawnSafezones}.

    @module tpg.ent.safezonemarker.server
    @realm server
]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--- Scales the `shell2x2` prop so its sphere silhouette matches
-- `TPG.Maps.GetSafezoneRadius()` exactly -- the same value `sv_protection.lua`
-- enforces, per-map with a config fallback -- and sets the shield material
-- plus a fixed semi-transparent white tint.
-- @realm server
function ENT:Initialize()
    self:SetModel("models/hunter/misc/shell2x2.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)

    -- The shell2x2 model has a base diameter of approximately 94-96 units
    -- We want the sphere to match safezoneRadius exactly
    local baseModelDiameter = 95
    local desiredDiameter = TPG.Maps.GetSafezoneRadius() * 2

    local scale = desiredDiameter / baseModelDiameter
    self:SetModelScale(scale, 0)

    self:SetMaterial("models/props_combine/com_shield001a")

    -- Make it semi-transparent
    self:SetColor(Color(255, 255, 255, 100))

    print("[TPG] Safezone marker spawned - Radius: " .. TPG.Maps.GetSafezoneRadius() .. ", Scale: " .. scale)
end

--- Slowly spins the sphere for visual effect; no gameplay purpose.
-- @realm server
function ENT:Think()
    -- Slowly rotate for visual effect
    local ang = self:GetAngles()
    ang.y = ang.y + FrameTime() * 5
    self:SetAngles(ang)

    self:NextThink(CurTime())
    return true
end