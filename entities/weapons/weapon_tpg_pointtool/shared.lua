--[[
    TPG Point Tool

    Admin weapon (sits under "ACE Tools" in the Q-menu, beside the torch) for
    placing gamemode points live: control points, KOTH hills, CTF flag homes and
    team spawns. Placements persist per map via maps/sv_custom_points.lua.

        Left click   place the selected point type at your aim
        Right click  cycle the point type
        Reload (R)   remove the nearest placed point

    After placing, run  tpg_points_reload  to rebuild the round with the new
    layout. Themed HUD uses TPG's red palette + Exo 2.
]]

if SERVER then AddCSLuaFile() end

SWEP.PrintName    = "TPG Point Tool"
SWEP.Author       = "RDC"
SWEP.Instructions = "LMB place  ·  RMB cycle type  ·  R remove nearest"
SWEP.Purpose      = "Place TPG gamemode points (control/KOTH/CTF/spawns)."

SWEP.Category       = "ACE Tools"     -- groups it with the torch in the Q-menu
SWEP.SubCategory    = "Tools"
SWEP.Spawnable      = true
SWEP.AdminOnly      = true
SWEP.AdminSpawnable = true

SWEP.Slot     = 1
SWEP.SlotPos  = 7

SWEP.Base       = "weapon_base"
SWEP.ViewModel  = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands   = true

SWEP.DrawCrosshair = true
SWEP.DrawAmmo      = false

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

-- Point types the tool can place, in cycle order.
SWEP.PointTypes = {
    { id = "cp",    label = "CONTROL POINT", team = nil,        tint = Color(245, 245, 245) },
    { id = "koth",  label = "KOTH HILL",     team = nil,        tint = Color(255, 210, 90) },
    { id = "ctf",   label = "CTF FLAG",      team = nil,        tint = Color(245, 245, 245) },
    { id = "spawn", label = "SPAWN · GREEN", team = TEAM_GREEN, tint = Color(60, 220, 95) },
    { id = "spawn", label = "SPAWN · RED",   team = TEAM_RED,   tint = Color(220, 70, 70) },
}

function SWEP:GetTypeIndex()
    return math.Clamp(self:GetNWInt("TPG_PtType", 1), 1, #self.PointTypes)
end

function SWEP:CurrentType()
    return self.PointTypes[self:GetTypeIndex()]
end

function SWEP:Initialize()
    self:SetHoldType("revolver")
    if SERVER then self:SetNWInt("TPG_PtType", 1) end
end

local function isAdmin(ply)
    return IsValid(ply) and ply:IsAdmin()
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    if not SERVER then return end

    local owner = self:GetOwner()
    if not isAdmin(owner) then
        if IsValid(owner) then owner:ChatPrint("[TPG] Point tool is admin-only.") end
        return
    end

    local tr = owner:GetEyeTrace()
    if not tr.Hit then return end

    local pt = self:CurrentType()
    TPG.Maps.AddPoint(pt.id, pt.team, tr.HitPos, nil)

    owner:EmitSound("buttons/button14.wav", 65, 120)
    owner:ChatPrint(string.format(
        "[TPG] Placed %s. (%d total) -- run tpg_points_reload to apply.",
        pt.label, TPG.Maps.CountPoints()))
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.2)

    if SERVER then
        local i = (self:GetTypeIndex() % #self.PointTypes) + 1
        self:SetNWInt("TPG_PtType", i)
    end
    if CLIENT then surface.PlaySound("ui/buttonrollover.wav") end
end

function SWEP:Reload()
    if not SERVER then return end
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 0.4

    local owner = self:GetOwner()
    if not isAdmin(owner) then return end

    local tr = owner:GetEyeTrace()
    local removed = TPG.Maps.RemoveNearest(tr.HitPos, 300)

    if removed then
        owner:EmitSound("buttons/button10.wav", 65, 90)
        owner:ChatPrint("[TPG] Removed nearest point (" .. tostring(removed.type) ..
            "). " .. TPG.Maps.CountPoints() .. " left.")
    else
        owner:ChatPrint("[TPG] No placed point within range.")
    end
end

-- ── Themed HUD (client) ─────────────────────────────────────────────────────
if CLIENT then
    -- TPG palette
    local COL_PRIMARY   = Color(200, 30, 30)    -- #C81E1E
    local COL_DARK      = Color(98, 15, 15)     -- #620F0F
    local COL_SECONDARY = Color(245, 245, 245)  -- #F5F5F5

    -- Exo 2 weights (400 body, 600 label, 700 sub, 800 headline). Falls back to
    -- a system font if Exo 2 isn't installed/shipped -- see notes on adding the
    -- TTF to resource/fonts.
    surface.CreateFont("TPG.Tool.Head",  { font = "Exo 2", size = 27, weight = 800, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Sub",   { font = "Exo 2", size = 21, weight = 700, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Label", { font = "Exo 2", size = 17, weight = 600, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Body",  { font = "Exo 2", size = 16, weight = 400, extended = true, antialias = true })

    local gradient = Material("gui/gradient")

    -- Diagonal-ish two-tone red panel (approximates the 135deg gradient).
    local function panel(x, y, w, h)
        draw.RoundedBox(8, x, y, w, h, COL_DARK)
        surface.SetDrawColor(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 255)
        surface.SetMaterial(gradient)
        surface.DrawTexturedRect(x + 2, y + 2, w - 4, h - 4)
        -- top accent line
        surface.SetDrawColor(COL_SECONDARY.r, COL_SECONDARY.g, COL_SECONDARY.b, 230)
        surface.DrawRect(x + 2, y + 2, w - 4, 2)
    end

    function SWEP:DrawHUD()
        local pt = self:CurrentType()
        local sw, sh = ScrW(), ScrH()
        local w, h = 360, 104
        local x, y = sw / 2 - w / 2, sh - h - 70

        panel(x, y, w, h)

        draw.SimpleText("POINT TOOL", "TPG.Tool.Head", x + 16, y + 12,
            COL_SECONDARY, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        draw.SimpleText("PLACING", "TPG.Tool.Label", x + 16, y + 44,
            Color(245, 245, 245, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(pt.label, "TPG.Tool.Sub", x + 16, y + 60,
            pt.tint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        draw.SimpleText("LMB place   RMB cycle   R remove", "TPG.Tool.Body",
            x + w - 16, y + h - 22, Color(245, 245, 245, 220),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end

    -- Ghost marker at the aim point so placement is precise.
    function SWEP:DrawWorldModel()
        self:DrawModel()
    end

    hook.Add("PostDrawTranslucentRenderables", "TPG_PointToolGhost", function(depth, sky)
        if depth or sky then return end
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_tpg_pointtool" then return end

        local tr = ply:GetEyeTrace()
        if not tr.Hit then return end

        local pt = wep.PointTypes[math.Clamp(wep:GetNWInt("TPG_PtType", 1), 1, #wep.PointTypes)]
        render.SetColorMaterial()
        render.DrawSphere(tr.HitPos, 12, 12, 12, ColorAlpha(pt.tint, 120))
        render.DrawLine(tr.HitPos, tr.HitPos + Vector(0, 0, 96), pt.tint, false)
    end)
end
