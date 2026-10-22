--[[--
    `weapon_tpg_pointtool`: admin SWEP for laying out a map in game.

    Sits under "The Proving Ground" in the Q-menu Weapons tab. It places control
    points, KOTH hills, Rush stages, the CTF flag and both team spawns, saved
    per map by @{tpg.custompoints}. Everything else (names, order, budgets,
    previews, export) is in the map editor panel, `tpg_mapedit`.

        Left click     place the selected type at your aim; for a spawn or the
                       flag, move it there
        Right click    next type (Shift: previous); cancels a move. Rush
                       stages and the CTF flag are optional and only come
                       up with "Advanced types" ticked in the editor
        Reload (R)     remove the nearest placed point of the selected type
        Shift + R      open the map editor

    While it is out, every point in the layout is drawn in the world with its
    capture or safezone radius (`ui/cl_mapedit.lua`). Edits are saved at once
    and put in play a second later as a preview round (see @{tpg.mapedit}),
    without killing anyone or clearing builds.

    Every action is admin-gated server-side, and the server does the work in
    @{tpg.mapedit}. The selected type (`TPG_PtType`, an index into
    `TPG.Layout.Types`) is a plain NWInt, clamped on read.

    @module tpg.weapon.pointtool
    @realm shared
]]

if SERVER then AddCSLuaFile() end

SWEP.PrintName    = "TPG Point Tool"
SWEP.Author       = "RDC"
SWEP.Instructions = "LMB place  ·  RMB next type  ·  R remove  ·  Shift+R editor"
SWEP.Purpose      = "Lay out a map for TPG: points, flag and spawns."

-- Its own category: ACE rebuilds "ACE Tools" from weapon_ace_base weapons
-- only (weapon_ace_base/cl_ace_spawnmenu.lua), so a tool listed there never
-- shows up.
SWEP.Category       = "The Proving Ground"
SWEP.SubCategory    = "Admin"
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

--- The current point-type index, clamped into range regardless of what the
-- networked value actually holds.
-- @treturn number 1-based index into `TPG.Layout.Types`.
-- @realm shared
function SWEP:GetTypeIndex()
    return math.Clamp(self:GetNWInt("TPG_PtType", 1), 1, #TPG.Layout.Types)
end

--- The selected `TPG.Layout.Types` entry.
-- @treturn table
-- @realm shared
function SWEP:CurrentType()
    return TPG.Layout.Types[self:GetTypeIndex()]
end

--- Sets the revolver hold type and, server-side only, starts on the first
-- type (control point).
-- @realm shared
function SWEP:Initialize()
    self:SetHoldType("revolver")
    if SERVER then self:SetNWInt("TPG_PtType", 1) end
end

--- Sends the owner the current layout, so the overlay is up to date the
-- moment the tool comes out.
-- @treturn boolean true, to allow the deploy.
-- @realm shared
function SWEP:Deploy()
    if SERVER and TPG.MapEdit then TPG.MapEdit.Push(self:GetOwner()) end
    return true
end

-- Valid player + IsAdmin; there is no separate permission tier.
local function isAdmin(ply)
    return IsValid(ply) and ply:IsAdmin()
end

--- Places the selected type at the owner's aim, or drops the point being
-- moved there (see `TPG.MapEdit.DropMove`). A non-admin owner is refused.
-- @realm shared
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

    if TPG.MapEdit.GetMove(owner) then
        TPG.MapEdit.DropMove(owner, tr.HitPos)
    else
        TPG.MapEdit.Place(owner, self:CurrentType().key, tr.HitPos)
    end
    owner:EmitSound("buttons/button14.wav", 65, 120)
end

--- Cycles the type (Shift goes backwards), or cancels a move in progress.
-- @realm shared
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.2)
    local owner = self:GetOwner()

    if SERVER and IsValid(owner) then
        if TPG.MapEdit.GetMove(owner) then
            TPG.MapEdit.CancelMove(owner)
            owner:ChatPrint("[TPG] Move cancelled.")
            return
        end
        -- Rush stages and the CTF flag are optional (Rush shuffles the
        -- control points, the flag sits on the KOTH hill), so they are only
        -- offered with the admin's `tpg_pointtool_advanced 1`.
        local step = owner:KeyDown(IN_SPEED) and -1 or 1
        local advanced = owner:GetInfoNum("tpg_pointtool_advanced", 0) ~= 0
        local n = #TPG.Layout.Types
        local idx = self:GetTypeIndex()
        for _ = 1, n do
            idx = (idx - 1 + step) % n + 1
            local t = TPG.Layout.Types[idx]
            if advanced or (t.id ~= "rush" and t.id ~= "ctf") then break end
        end
        self:SetNWInt("TPG_PtType", idx)
        owner:EmitSound("ui/buttonrollover.wav", 50)
    end
end

--- Removes the nearest placed point of the selected type within 300 units.
-- With Shift held it opens the map editor instead. Server side only, since
-- singleplayer never runs Reload on the client. Throttled to once per 0.4s.
-- @realm shared
function SWEP:Reload()
    if CLIENT then return end
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 0.4

    local owner = self:GetOwner()
    if not isAdmin(owner) then return end

    if owner:KeyDown(IN_SPEED) then
        owner:ConCommand("tpg_mapedit")
        return
    end

    TPG.MapEdit.RemoveNearest(owner, self:CurrentType().key, owner:GetEyeTrace().HitPos)
    owner:EmitSound("buttons/button10.wav", 65, 90)
end

-- ── Themed HUD (client) ─────────────────────────────────────────────────────
if CLIENT then
    -- TPG palette
    local COL_PRIMARY   = Color(200, 30, 30)    -- #C81E1E
    local COL_DARK      = Color(98, 15, 15)     -- #620F0F
    local COL_SECONDARY = Color(245, 245, 245)  -- #F5F5F5

    -- Exo 2 (shipped in resource/fonts). The weights register under different
    -- family names, so each face is targeted by name:
    --   400 -> "Exo 2" Regular, 700 -> "Exo 2" Bold,
    --   600 -> "Exo 2 SemiBold", 800 -> "Exo 2 ExtraBold".
    surface.CreateFont("TPG.Tool.Head",  { font = "Exo 2 ExtraBold", size = 27, weight = 800, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Sub",   { font = "Exo 2",           size = 21, weight = 700, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Label", { font = "Exo 2 SemiBold",  size = 17, weight = 600, extended = true, antialias = true })
    surface.CreateFont("TPG.Tool.Body",  { font = "Exo 2",           size = 16, weight = 400, extended = true, antialias = true })

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

    --- Draws the bottom-centre "POINT TOOL" panel in TPG's red theme: what LMB
    -- will place (or which point is being moved) and the controls.
    -- @realm client
    function SWEP:DrawHUD()
        local pt = self:CurrentType()
        local moving = LocalPlayer():GetNWString("TPG_MapEditMove", "")
        local sw, sh = ScrW(), ScrH()
        local w, h = 420, 104
        local x, y = sw / 2 - w / 2, sh - h - 70

        panel(x, y, w, h)

        draw.SimpleText("POINT TOOL", "TPG.Tool.Head", x + 16, y + 12,
            COL_SECONDARY, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        if moving ~= "" then
            draw.SimpleText("MOVING", "TPG.Tool.Label", x + 16, y + 44,
                Color(245, 245, 245, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(moving, "TPG.Tool.Sub", x + 16, y + 60,
                Color(255, 230, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("LMB drop   RMB cancel", "TPG.Tool.Body",
                x + w - 16, y + h - 22, Color(245, 245, 245, 220),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            return
        end

        draw.SimpleText(pt.single and "PLACING (MOVES THE CURRENT ONE)" or "PLACING", "TPG.Tool.Label", x + 16, y + 44,
            Color(245, 245, 245, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(pt.label, "TPG.Tool.Sub", x + 16, y + 60,
            pt.tint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        draw.SimpleText("LMB place   RMB type   R remove   Shift+R editor", "TPG.Tool.Body",
            x + w - 16, y + h - 22, Color(245, 245, 245, 220),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end

    --- Plain world model; the layout overlay and the aim marker are drawn by
    -- `ui/cl_mapedit.lua`.
    -- @realm client
    function SWEP:DrawWorldModel()
        self:DrawModel()
    end
end
