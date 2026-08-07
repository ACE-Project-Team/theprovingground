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
-- `TPG.Config.safezoneRadius` exactly (see the module header's accuracy note:
-- this is the GLOBAL config value, not any per-map override), and sets the
-- shield material + a fixed semi-transparent white tint.
-- @realm server
function ENT:Initialize()
    self:SetModel("models/hunter/misc/shell2x2.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)

    -- The shell2x2 model has a base diameter of approximately 94-96 units
    -- We want the sphere to match safezoneRadius exactly
    local baseModelDiameter = 95
    local desiredDiameter = TPG.Config.safezoneRadius * 2

    local scale = desiredDiameter / baseModelDiameter
    self:SetModelScale(scale, 0)

    self:SetMaterial("models/props_combine/com_shield001a")

    -- Make it semi-transparent
    self:SetColor(Color(255, 255, 255, 100))

    print("[TPG] Safezone marker spawned - Radius: " .. TPG.Config.safezoneRadius .. ", Scale: " .. scale)
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