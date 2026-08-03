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

TPG.UI = TPG.UI or {}

--[[
    Resolution scaling.

    Every number in the HUD was a raw pixel count picked at 1920x1080. That is
    only correct at 1080p: on a 1440p or 4K monitor the whole thing shrinks into
    the top of the screen, and at 1280x720 the 750px score panel is more than
    half the screen wide and runs into the boxes either side of it.

    So all HUD geometry is authored at 1080p and passed through TPG.UI.S(), and
    the fonts are built at the matching size. Scale tracks HEIGHT, not width --
    an ultrawide monitor is not asking for a bigger HUD, it has more room beside
    the same one. Clamped at both ends so a tiny window still gets legible text
    and an 8K screen doesn't get a HUD you could read from the next room.
]]
local BASE_H = 1080

TPG.UI.scale = 1

--[[
    Authored at 1080p; rebuilt whenever the screen size changes.

    Two families, and the split is deliberate.

    Exo 2 is the brand face (it's what the logo and the point tool use) and it
    is a SEMI-CONDENSED display font: narrow letters, and a space barely wider
    than a stroke. That's exactly right for the things it's used for here --
    tickets, point letters, compass headings, headings -- single words and
    numbers, large, read at a glance.

    It is wrong for sentences. At 14-19px a line like "premium gear is paid for
    with a cooldown" closes its word gaps until it reads as one long word. So
    everything that forms a SENTENCE uses Roboto, which ships with the game and
    has normal spacing at small sizes.

    Every entry asks for weight 500 (normal) even where the face is bold,
    because the weight is already baked into the family name being requested.
    Asking for 800 on top makes the renderer synthesize more weight over an
    already extra-bold face: strokes fatten, sidebearings don't, and neighbours
    end up touching.
]]
local DISPLAY   = "Exo 2 ExtraBold"
local DISPLAYMD = "Exo 2 SemiBold"
-- Roboto ships with the game and is one family, so its bold comes from the
-- weight parameter rather than from a second family name -- the opposite of the
-- Exo faces above, and the reason the two are declared differently below.
local BODY      = "Roboto"

local FONTS = {
    -- Display: numbers, single words, glanceable.
    ["TPG.HUD.Big"]   = { font = DISPLAY,   size = 30, weight = 500 },
    ["TPG.HUD.Num"]   = { font = DISPLAY,   size = 22, weight = 500 },
    ["TPG.HUD.Pip"]   = { font = DISPLAY,   size = 16, weight = 500 },

    -- The compass gets its own pair rather than borrowing Label/Small. It's
    -- read at a glance while moving, from the middle of the screen, with the
    -- world behind it -- the same size that works for a docked panel label is
    -- too small out there.
    ["TPG.HUD.Compass"]    = { font = DISPLAY,   size = 27, weight = 500 },
    ["TPG.HUD.CompassNum"] = { font = DISPLAYMD, size = 19, weight = 500 },

    -- Body: anything that can be a phrase.
    ["TPG.HUD.Label"] = { font = BODY, size = 17, weight = 700 },
    ["TPG.HUD.Small"] = { font = BODY, size = 15, weight = 500 },

    -- Menus. Sized a step up from the HUD's: a HUD label is glanced at, menu
    -- text is read. Only the title is display -- it's one word.
    ["TPG.Menu.Title"] = { font = DISPLAY, size = 28, weight = 500 },
    ["TPG.Menu.Head"]  = { font = BODY,    size = 18, weight = 700 },
    ["TPG.Menu.Item"]  = { font = BODY,    size = 17, weight = 700 },
    ["TPG.Menu.Small"] = { font = BODY,    size = 16, weight = 500 },
    ["TPG.Menu.Tiny"]  = { font = BODY,    size = 14, weight = 500 },
}

--[[
    Exo 2 is already bundled and resource.AddFile'd for the point tool (see
    init.lua), so the HUD costs nothing extra to switch onto it and stops
    looking like stock Derma. Every font falls back to the system default if the
    download hasn't landed yet, so a first-join client still gets a HUD.
]]
function TPG.UI.BuildFonts()
    TPG.UI.scale = math.Clamp(ScrH() / BASE_H, 0.72, 2.25)

    for name, def in pairs(FONTS) do
        surface.CreateFont(name, {
            font      = def.font,
            size      = math.max(math.Round(def.size * TPG.UI.scale), 9),
            weight    = def.weight,
            extended  = true,
            antialias = true,
        })
    end
end

TPG.UI.BuildFonts()
hook.Add("OnScreenSizeChanged", "TPG_UIRescale", TPG.UI.BuildFonts)

-- 1080p-authored pixels -> this screen's pixels. Rounded, because a half-pixel
-- panel edge draws as a blurry seam.
function TPG.UI.S(v)
    return math.Round(v * TPG.UI.scale)
end

-- Standard panel: dark violet fill with a thin brand-purple top rule, which is
-- what visually ties every HUD box back to the logo's frame.
function TPG.UI.Panel(x, y, w, h, accent)
    local inset = TPG.UI.S(6)
    draw.RoundedBox(TPG.UI.S(6), x, y, w, h, C.Panel)
    draw.RoundedBox(0, x + inset, y, w - inset * 2, math.max(TPG.UI.S(2), 1), accent or C.Purple)
end

--[[
    A panel sized to its own label, returning the width it used.

    Fixed-width pills don't survive contact with real strings: 132px fits
    "Control Points" and clips "King of the Hill", and the economy tag was
    wider than its box on the first render. Measuring means the box is right
    for whatever mode name or font the client actually ends up with.
]]
function TPG.UI.Pill(text, font, x, y, h, accent, color, padX)
    padX = padX or TPG.UI.S(14)
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
    0.06 lands capitals on the centre of the tile. Text with real descenders (a
    "g", a "p") sits a hair low as a result, which is why this is used for the
    pips and not for body text.

    Both coordinates are ROUNDED. Centring produces a half-pixel offset whenever
    the box and the glyph differ by an odd number of pixels, and a glyph
    rasterised on a half-pixel is blurred asymmetrically -- it reads as being
    nudged up and to the left, which is exactly what the point pips looked like.
]]
local OPTICAL_DESCENDER = 0.06

function TPG.UI.TextInBox(text, font, x, y, w, h, color)
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    draw.SimpleText(text, font,
        math.Round(x + (w - tw) / 2),
        math.Round(y + (h - th) / 2 + th * OPTICAL_DESCENDER),
        color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

--[[
    Fit text to a width, ending in an ellipsis if it doesn't.

    Weapon names come from whatever packs are installed -- "Carl Gustaf M2
    (HEDP 502)" is a real one -- so no box width is safe on its own. Clipping
    with a render scissor would hide the overflow but leave a word cut mid-glyph
    with no sign anything is missing; an ellipsis says "there is more name here"
    and the full one is in the tooltip.

    Trims from the end one character at a time. Names are short enough that a
    binary search would only save a few string compares per frame, and this
    stays correct for multi-byte names (it steps back over UTF-8 continuation
    bytes rather than splitting a codepoint in half).
]]
function TPG.UI.Truncate(text, font, maxW)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= maxW then return text end

    local ellipsis = "..."
    local budget   = maxW - surface.GetTextSize(ellipsis)
    if budget <= 0 then return ellipsis end

    local cut = string.len(text)
    while cut > 0 do
        -- Never cut inside a multi-byte character.
        while cut > 0 and bit.band(string.byte(text, cut) or 0, 0xC0) == 0x80 do
            cut = cut - 1
        end
        cut = cut - 1
        if cut <= 0 then break end
        if surface.GetTextSize(string.sub(text, 1, cut)) <= budget then
            return string.sub(text, 1, cut) .. ellipsis
        end
    end
    return ellipsis
end
