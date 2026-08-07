--[[--
    `weapon_tpg_pointtool`: admin SWEP for placing gamemode points live.

    Sits under "ACE Tools" in the Q-menu, beside the torch, for placing
    control points, KOTH hills, the CTF flag home and team spawns without
    editing `_loader.lua`. Placements persist per map via
    @{tpg.custompoints} (`gamemode/maps/sv_custom_points.lua`).

        Left click   place the selected point type at your aim
        Right click  cycle the point type
        Reload (R)   remove the nearest placed point

    After placing, run `tpg_points_reload` to rebuild the round with the new
    layout -- this weapon only writes to the saved point list, it does not
    itself restart the round or touch the currently-loaded config.

    Every action (fire, secondary, reload) is admin-gated server-side via the
    local `isAdmin(owner)` helper, which just checks `ply:IsAdmin()` -- there
    is no separate permission tier, any admin can place or remove any point.
    The point-type cycle state (`TPG_PtType`, an index into `PointTypes`) is a
    plain NWInt with no validation on read beyond a `math.Clamp`, so it is
    safe even if desynced.

    Themed HUD (`SWEP:DrawHUD`, client-only) uses TPG's red palette + the Exo 2
    font family, and a `PostDrawTranslucentRenderables` hook draws a ghost
    sphere + line at the aim point matching the currently-selected type's tint
    -- purely a client-side preview, it has no effect on where a placement
    actually lands (that is always the owner's live eye-trace at fire time).

    This single file covers both realms: the HUD/ghost-marker code near the
    bottom is wrapped in `if CLIENT then ... end` rather than split into a
    separate client file.

    @module tpg.weapon.pointtool
    @realm shared
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

-- Weapons defined in a GAMEMODE's entities/weapons folder are registered as
-- usable weapons but are NOT auto-added to the spawnmenu's "Weapon" list (only
-- lua/weapons/ autoloads into it). Without this the torch shows under "ACE
-- Tools" but this tool doesn't. Register it manually so it appears beside it.
list.Set("Weapon", "weapon_tpg_pointtool", {
    PrintName      = SWEP.PrintName,
    ClassName      = "weapon_tpg_pointtool",
    Category       = SWEP.Category,
    Spawnable      = SWEP.Spawnable,
    AdminOnly      = SWEP.AdminOnly,
    AdminSpawnable = SWEP.AdminSpawnable,
})

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

--- The current point-type index, clamped into range regardless of what the
-- networked value actually holds.
-- @treturn number 1-based index into `self.PointTypes`.
-- @realm shared
function SWEP:GetTypeIndex()
    return math.Clamp(self:GetNWInt("TPG_PtType", 1), 1, #self.PointTypes)
end

--- The point-type table entry currently selected (`{ id, label, team, tint }`).
-- @treturn table
-- @realm shared
function SWEP:CurrentType()
    return self.PointTypes[self:GetTypeIndex()]
end

--- Sets the revolver hold type and, server-side only, initialises the type
-- cycle to index 1 (control point).
-- @realm shared
function SWEP:Initialize()
    self:SetHoldType("revolver")
    if SERVER then self:SetNWInt("TPG_PtType", 1) end
end

-- Shared admin gate for every action below: valid player + IsAdmin, no
-- separate permission tier.
local function isAdmin(ply)
    return IsValid(ply) and ply:IsAdmin()
end

--- Places the currently-selected point type at the owner's eye-trace hit
-- position, via `TPG.Maps.AddPoint`. Admin-gated server-side; a non-admin
-- owner is refused with a chat message and nothing is placed. Does nothing
-- if the trace didn't hit anything.
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

    local pt = self:CurrentType()
    TPG.Maps.AddPoint(pt.id, pt.team, tr.HitPos, nil)

    owner:EmitSound("buttons/button14.wav", 65, 120)
    owner:ChatPrint(string.format(
        "[TPG] Placed %s. (%d total) - run tpg_points_reload to apply.",
        pt.label, TPG.Maps.CountPoints()))
end

--- Cycles to the next point type (wrapping), server-side, and plays a UI
-- rollover sound client-side. Not admin-gated on its own -- cycling the type
-- is harmless without a place/remove action, so any holder can do it, though
-- only an admin owner will ever be holding this weapon in practice
-- (`AdminOnly = true`, `AdminSpawnable = true`).
-- @realm shared
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.2)

    if SERVER then
        local i = (self:GetTypeIndex() % #self.PointTypes) + 1
        self:SetNWInt("TPG_PtType", i)
    end
    if CLIENT then surface.PlaySound("ui/buttonrollover.wav") end
end

--- Removes whichever placed point is nearest the owner's eye-trace hit, within
-- 300 units (via `TPG.Maps.RemoveNearest`). Throttled to once per 0.4s by
-- `self.NextReload` and admin-gated; a non-admin's Reload silently does
-- nothing (no chat message, unlike @{SWEP:PrimaryAttack}'s refusal).
-- @realm shared
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

    --- Draws the bottom-centre "POINT TOOL / PLACING <type>" panel in TPG's
    -- red theme, plus the LMB/RMB/R hint line.
    -- @realm client
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

    --- Ghost marker at the aim point so placement is precise. World-model draw
    -- is unmodified (plain `DrawModel`); the actual ghost is the sphere+line
    -- drawn by the `PostDrawTranslucentRenderables` hook just below.
    -- @realm client
    function SWEP:DrawWorldModel()
        self:DrawModel()
    end

    -- Draws a tinted ghost sphere + vertical line at the LOCAL player's own
    -- eye-trace hit, but only while they are actively holding this weapon --
    -- it re-derives everything from LocalPlayer() each frame rather than
    -- reading anything off a specific SWEP instance's state.
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
