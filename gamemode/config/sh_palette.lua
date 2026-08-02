--[[
    TPG Palette + HUD theme (shared)

    One source of truth for the gamemode's colours, taken from the logo
    (icon.svg / logo.svg, themselves sampled off the original icon24.png):

        purple  #5818A7   the frame -- becomes the HUD's chrome
        green   #00FF21   green team
        red     #FF0000   red team
        cyan    #0094FF   the TPG lettering -- becomes the accent/info colour

    Two of those are unusable as-is for large areas of HUD. Pure #00FF21 and
    #FF0000 at panel size vibrate against a dark background and make white text
    on top unreadable, which is exactly how the old team-stats box looked. So
    the saturated pair stays reserved for the things that MEAN a team -- score
    bars, point ownership, markers -- and everything structural is built from
    the purple, darkened into near-black chrome with a violet cast.

    That keeps the logo's identity (you can tell it's TPG by the colour of the
    frame) without painting the screen in neon.
]]

TPG.Colors = TPG.Colors or {}
local C = TPG.Colors

-- ── Brand ──────────────────────────────────────────────────────────────────
C.Purple      = Color(88, 24, 167)
C.PurpleLight = Color(132, 78, 220)
C.Accent      = Color(0, 148, 255)     -- logo cyan
C.AccentDim   = Color(0, 108, 190)

-- ── Chrome (purple, darkened -- panels, troughs, borders) ─────────────────
C.Panel       = Color(19, 11, 32, 220)  -- standard panel fill
C.PanelSolid  = Color(19, 11, 32, 255)
C.Trough      = Color(44, 27, 74, 235)  -- empty half of a bar
C.Border      = Color(88, 24, 167, 255)
C.Shadow      = Color(0, 0, 0, 190)

-- ── Text ───────────────────────────────────────────────────────────────────
C.Text        = Color(240, 238, 246)
C.TextMuted   = Color(170, 158, 190)
C.TextDark    = Color(16, 10, 26)

-- ── Teams ──────────────────────────────────────────────────────────────────
-- Bar/marker colours keep the logo's saturation. The *Text variants are lifted
-- toward white so a team name stays readable as text, where full-saturation
-- red on dark is muddy and full-saturation green glares.
C.Green       = Color(0, 255, 33)
C.GreenText   = Color(110, 255, 130)
C.Red         = Color(255, 0, 0)
C.RedText     = Color(255, 110, 110)

-- ── Status ─────────────────────────────────────────────────────────────────
-- Overtime deliberately does NOT use a brand colour: it has to read as "the
-- rules changed", which means not matching anything else on screen.
C.Warn        = Color(255, 140, 50)
C.Neutral     = Color(255, 214, 64)     -- uncaptured point
C.Good        = Color(120, 230, 120)

function C.Team(teamId)
    if teamId == TEAM_GREEN then return C.Green end
    if teamId == TEAM_RED   then return C.Red end
    return C.TextMuted
end

function C.TeamText(teamId)
    if teamId == TEAM_GREEN then return C.GreenText end
    if teamId == TEAM_RED   then return C.RedText end
    return C.TextMuted
end

-- Black or white, whichever survives on top of the given fill.
function C.Contrast(bg)
    local lum = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) / 255
    return lum > 0.55 and C.TextDark or C.Text
end

if not CLIENT then return end

--[[
    Fonts. Exo 2 is already bundled and resource.AddFile'd for the point tool
    (see init.lua), so the HUD costs nothing extra to switch onto it and stops
    looking like stock Derma. Every font falls back to the system default if
    the download hasn't landed yet, so a first-join client still gets a HUD.
]]
surface.CreateFont("TPG.HUD.Big",   { font = "Exo 2 ExtraBold", size = 30, weight = 800, extended = true, antialias = true })
surface.CreateFont("TPG.HUD.Num",   { font = "Exo 2 ExtraBold", size = 22, weight = 800, extended = true, antialias = true })
surface.CreateFont("TPG.HUD.Label", { font = "Exo 2 SemiBold",  size = 17, weight = 600, extended = true, antialias = true })
surface.CreateFont("TPG.HUD.Small", { font = "Exo 2",           size = 15, weight = 500, extended = true, antialias = true })
surface.CreateFont("TPG.HUD.Pip",   { font = "Exo 2 ExtraBold", size = 16, weight = 800, extended = true, antialias = true })

TPG.UI = TPG.UI or {}

-- Standard panel: dark violet fill with a thin brand-purple top rule, which is
-- what visually ties every HUD box back to the logo's frame.
function TPG.UI.Panel(x, y, w, h, accent)
    draw.RoundedBox(6, x, y, w, h, C.Panel)
    draw.RoundedBox(0, x + 6, y, w - 12, 2, accent or C.Purple)
end

--[[
    A panel sized to its own label, returning the width it used.

    Fixed-width pills don't survive contact with real strings: 132px fits
    "Control Points" and clips "King of the Hill", and the economy tag was
    wider than its box on the first render. Measuring means the box is right
    for whatever mode name or font the client actually ends up with.
]]
function TPG.UI.Pill(text, font, x, y, h, accent, color, padX)
    padX = padX or 14
    surface.SetFont(font)
    local tw = surface.GetTextSize(text)
    local w  = tw + padX * 2

    TPG.UI.Panel(x, y, w, h, accent)
    TPG.UI.TextInBox(text, font, x, y, w, h, color or C.Text)
    return w
end

--[[
    Draw text centred in a box.

    The old point pips passed TEXT_ALIGN_CENTER for both axes and looked
    slightly high in their tiles. The math wasn't wrong: SimpleText centres the
    font's LINE BOX, ascender to descender. A lone capital letter has no
    descender, so the empty descender space all sits below it and pushes the
    visible glyph up by about half of it.

    GMod can't measure a glyph's actual bounding box (surface.GetTextSize
    returns the line height, not the ink), so this applies a fixed optical
    correction instead: nudge down by OPTICAL_DESCENDER of the line height.
    0.09 is half a typical ~18% descender, which lands capitals on the centre
    of the tile. Text with real descenders (a "g", a "p") sits a hair low as a
    result, which is why this is used for the pips and not for body text.
]]
local OPTICAL_DESCENDER = 0.09

function TPG.UI.TextInBox(text, font, x, y, w, h, color)
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    draw.SimpleText(text, font,
        x + (w - tw) / 2,
        y + (h - th) / 2 + th * OPTICAL_DESCENDER,
        color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end
