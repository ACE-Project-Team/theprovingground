--[[--
    Compass HUD element: a heading ladder (N/NE/E/.../NW) and a bearing number,
    centred under the main HUD's score panel.

    Two things were wrong with the old one, and they had the same root cause:
    bare text drawn straight onto the world at a hardcoded y=60/80.

      1. Those constants predate the point pips, which land at y=76 -- so the
         ladder and the bearing printed through the point letters. It asks the
         main HUD where its centre stack ended instead, which stays correct when
         the point count changes mid-round, when the mode has no points at all,
         and at any resolution.

      2. A 1px drop shadow guarantees nothing: yellow on a bright skybox has
         almost no contrast, which is what made it hard to read. It keeps the
         look it always had -- plain yellow letters floating over the world, no
         chrome -- and gets its contrast from a real outline instead. An outline
         surrounds every edge of every glyph, so the letters hold up over sky,
         concrete and muzzle flash alike without a panel behind them.

    Exports @{CompassY} and @{BelowCompass}, which
    `cl_hud_overtime.lua` and `cl_hud_ctf.lua` use to stack themselves under
    this element instead of guessing its height.

    @module tpg.hud.compass
    @realm client
]]

local compassDirections = {
    { angle = 0,   label = "N" },
    { angle = 45,  label = "NE" },
    { angle = 90,  label = "E" },
    { angle = 135, label = "SE" },
    { angle = 180, label = "S" },
    { angle = 225, label = "SW" },
    { angle = 270, label = "W" },
    { angle = 315, label = "NW" },
}

local FOV_DEGREES = 50   -- how far either side of the crosshair the ladder runs

-- Yellow, as it always was. The palette's neutral amber is close enough to
-- belong to the same HUD but is reserved for "uncaptured point" one row above
-- this, so the compass keeps its own pure yellow and can't be mistaken for it.
local COMPASS_COLOR = Color(255, 255, 0)
local OUTLINE       = Color(0, 0, 0, 230)

-- One place that decides the compass block's box, so its own draw and anything
-- stacking under it can't disagree.
local function CompassBox()
    local S = TPG.UI.S
    local L = TPG.UI.ComputeLayout()

    surface.SetFont("TPG.HUD.Compass")
    local _, labelH = surface.GetTextSize("N")
    surface.SetFont("TPG.HUD.CompassNum")
    local _, bearH = surface.GetTextSize("0")

    local h = labelH + bearH + S(4)

    -- As wide as the score bar above it. The earlier 0.62 was chosen to sit
    -- inside a backing panel; without the panel there's nothing to sit inside,
    -- and a narrow ladder squeezes 50 degrees of heading into a span too short
    -- to turn against, which is what made it feel smaller than the old one.
    local w = math.min(L.scoreW, ScrW() * 0.62)

    return ScrW() / 2 - w / 2, TPG.UI.BelowObjectives() + S(8), w, h, labelH
end

--- Top of the compass block, in screen pixels.
-- @treturn number
-- @realm client
function TPG.UI.CompassY()
    local _, y = CompassBox()
    return y
end

--- Bottom of the compass block, for anything that stacks below it.
-- @treturn number
-- @realm client
function TPG.UI.BelowCompass()
    local _, y, _, h = CompassBox()
    return y + h
end

hook.Add("HUDPaint", "TPG_Compass", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local S   = TPG.UI.S
    local yaw = ply:EyeAngles().y

    -- Normalize to 0-360
    local lookAngle = (yaw + 180) % 360

    local x, y, w, _, labelH = CompassBox()
    local cx = x + w / 2

    -- Spread the ladder across the block rather than a magic pixels-per-degree,
    -- so it keeps its shape on every resolution.
    local perDegree = (w * 0.5) / FOV_DEGREES
    local outlineW  = math.max(S(1), 1)

    for _, dir in ipairs(compassDirections) do
        local diff = dir.angle - lookAngle

        -- Wrap around
        if diff > 180 then diff = diff - 360 end
        if diff < -180 then diff = diff + 360 end

        if math.abs(diff) < FOV_DEGREES then
            -- Fade toward the ends so the edges don't compete with the heading
            -- you're actually on. The floor stays high because the outline is
            -- doing the legibility work, not a backing panel.
            local alpha = 255 * (1 - (math.abs(diff) / FOV_DEGREES) * 0.4)

            draw.SimpleTextOutlined(dir.label, "TPG.HUD.Compass", math.Round(cx + diff * perDegree), y,
                Color(COMPASS_COLOR.r, COMPASS_COLOR.g, COMPASS_COLOR.b, alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, outlineW,
                Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, OUTLINE.a * (alpha / 255)))
        end
    end

    -- Bearing number, always dead centre under the ladder.
    draw.SimpleTextOutlined(string.format("%03d", math.floor(lookAngle)), "TPG.HUD.CompassNum",
        math.Round(cx), y + labelH + S(4), COMPASS_COLOR,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, outlineW, OUTLINE)
end)
