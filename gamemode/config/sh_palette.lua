--[[--
    One source of truth for the gamemode's colours, plus the client HUD theme.

    Colours are taken from the logo (icon.svg / logo.svg, themselves sampled
    off the original icon24.png):

        purple  #5818A7   the frame, becomes the HUD's chrome
        green   #00FF21   green team
        red     #FF0000   red team
        cyan    #0094FF   the TPG lettering, becomes the accent/info colour

    Two of those are unusable as-is for large areas of HUD. Pure #00FF21 and
    #FF0000 at panel size vibrate against a dark background and make white
    text on top unreadable, which is exactly how the old team-stats box
    looked. So the saturated pair stays reserved for the things that MEAN a
    team (score bars, point ownership, markers) and everything structural is
    built from the purple, darkened into near-black chrome with a violet cast.

    That keeps the logo's identity (you can tell it's TPG by the colour of the
    frame) without painting the screen in neon.

    `TPG.Colors` (the `C` table used throughout this file) and its three
    lookup functions run on both realms. Everything from `TPG.UI` onward is
    CLIENT ONLY: the file returns early on the server after defining the
    colour table, so `TPG.UI` does not exist server-side at all.

    @module tpg.palette
    @realm shared
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

--- The saturated bar/marker colour for a team.
-- @tparam number teamId TEAM_GREEN, TEAM_RED, or anything else.
-- @treturn Color `C.Green`/`C.Red` for the two playing teams, else
--  `C.TextMuted` (covers TEAM_UNASSIGNED and any unrecognised id).
-- @realm shared
function C.Team(teamId)
    if teamId == TEAM_GREEN then return C.Green end
    if teamId == TEAM_RED   then return C.Red end
    return C.TextMuted
end

--- The readable-as-text variant of a team's colour, lifted toward white.
-- @tparam number teamId TEAM_GREEN, TEAM_RED, or anything else.
-- @treturn Color `C.GreenText`/`C.RedText` for the two playing teams, else
--  `C.TextMuted`.
-- @realm shared
function C.TeamText(teamId)
    if teamId == TEAM_GREEN then return C.GreenText end
    if teamId == TEAM_RED   then return C.RedText end
    return C.TextMuted
end

--- Black or white, whichever survives on top of the given fill.
-- Standard luminance-weighted formula; ignores `bg.a`, so a translucent panel
-- fill is judged as if it were opaque against whatever it actually sits on.
-- @tparam Color bg The fill colour text will be drawn over.
-- @treturn Color `C.TextDark` on light backgrounds, `C.Text` on dark ones.
-- @realm shared
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

--[[
    Cap-height centring correction, per face, read off the font's own metrics.

    TextInBox centres the LINE BOX, and a line box is not symmetrical around the
    capitals: it runs from the ascender line to the descender line, and neither
    matches where a lone "T" actually sits. The correction below is the fraction
    of the line height a capital has to move for its own middle to land on the
    middle of the box, worked out from the ttf as

        0.5 - ascent/lineHeight + capHeight/(2 * lineHeight)

    using the WINDOWS metrics (usWinAscent/usWinDescent), because that is what
    GDI reports as the font height and therefore what surface.GetTextSize
    returns.

    The two faces are wildly different, which is why one shared constant could
    never be right for both:

        Roboto   ascent 0.950em, descent 0.250em, cap 0.711em  ->  +0.004
        Exo 2    ascent 1.158em, descent 0.311em, cap 0.690em  ->  -0.053

    Exo 2 reserves more than a full em ABOVE the baseline (accents on capitals),
    so its line box has a large empty band over the letters and a capital
    centred in that box sits visibly low -- about 3px low at the point-pip size.
    That, not the rasteriser, is what kept the pip letters looking off.
]]
local CAP_MID = {
    [DISPLAY]   = -0.053,
    [DISPLAYMD] = -0.053,
    [BODY]      =  0.004,
}

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
-- Font name -> its face's cap-centring correction, so TextInBox can look it up
-- by the name it was handed without knowing which family is behind it.
TPG.UI.CapMid = TPG.UI.CapMid or {}

--[[--
    (Re)create every named HUD/menu font at the current screen scale.

    Recomputes `TPG.UI.scale` from the screen height first, then rebuilds
    every entry in the local `FONTS` table via `surface.CreateFont`, and
    records each one's cap-centring correction into `TPG.UI.CapMid` (see
    @{TPG.UI.TextInBox}) keyed by the SAME font name, so a caller that only
    has the font name string can still look up its correction.

    Runs once at load and again on `OnScreenSizeChanged`, so a font name is
    valid to use in `surface.SetFont` immediately after either of those, but
    NOT before the first run has happened.

    @realm client
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
        TPG.UI.CapMid[name] = CAP_MID[def.font] or 0
    end
end

TPG.UI.BuildFonts()
hook.Add("OnScreenSizeChanged", "TPG_UIRescale", TPG.UI.BuildFonts)

--- Convert a 1080p-authored pixel value to this screen's pixels.
-- Rounded, because a half-pixel panel edge draws as a blurry seam.
-- @tparam number v A pixel value as authored at 1920x1080.
-- @treturn number The scaled, rounded pixel value for the current screen.
-- @realm client
function TPG.UI.S(v)
    return math.Round(v * TPG.UI.scale)
end

--- Draw the standard HUD panel: dark violet fill with a thin brand-purple top rule.
-- What visually ties every HUD box back to the logo's frame.
-- @tparam number x
-- @tparam number y
-- @tparam number w
-- @tparam number h
-- @tparam[opt] Color accent Top-rule colour; defaults to `C.Purple`.
-- @realm client
function TPG.UI.Panel(x, y, w, h, accent)
    local inset = TPG.UI.S(6)
    draw.RoundedBox(TPG.UI.S(6), x, y, w, h, C.Panel)
    draw.RoundedBox(0, x + inset, y, w - inset * 2, math.max(TPG.UI.S(2), 1), accent or C.Purple)
end

--[[--
    Draw a panel sized to its own label text, returning the width it used.

    Fixed-width pills don't survive contact with real strings: 132px fits
    "Control Points" and clips "King of the Hill", and the economy tag was
    wider than its box on the first render. Measuring means the box is right
    for whatever mode name or font the client actually ends up with.

    @tparam string text
    @tparam string font A font name already created by @{TPG.UI.BuildFonts}.
    @tparam number x
    @tparam number y
    @tparam number h
    @tparam[opt] Color accent Passed through to @{TPG.UI.Panel}.
    @tparam[opt] Color color Text colour; defaults to `C.Text`.
    @tparam[opt] number padX Horizontal padding on each side of the text;
     defaults to `TPG.UI.S(14)`.
    @treturn number The pill's total width, so the caller can lay out what
     comes next.
    @realm client
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

--[[--
    Draw text centred in a box, correcting for capital-letter line-box bias.

    The old point pips passed TEXT_ALIGN_CENTER for both axes and looked
    slightly high in their tiles. The math wasn't wrong: SimpleText centres
    the font's LINE BOX, ascender to descender. A lone capital letter has no
    descender, so the empty descender space all sits below it and pushes the
    visible glyph up by about half of it.

    GMod can't measure a glyph's actual bounding box (`surface.GetTextSize`
    returns the line height, not the ink), so the shift comes from the FACE's
    published metrics instead, via `TPG.UI.CapMid` (built in
    @{TPG.UI.BuildFonts}). It's per-font because the two families here
    disagree by a tenth of a line height, which at pip size is around three
    pixels: a single number tuned until Roboto looked right left Exo 2 sitting
    low, and vice versa.

    Text with real descenders (a "g", a "p") sits a hair low as a result,
    which is why this is used for pips, badges and button captions (short,
    capital, centred things) and not for body text.

    Both coordinates are ROUNDED. Centring produces a half-pixel offset
    whenever the box and the glyph differ by an odd number of pixels, and a
    glyph rasterised on a half-pixel is blurred asymmetrically; it reads as
    being nudged up and to the left, which is exactly what the point pips
    looked like.

    @tparam string text
    @tparam string font A font name already created by @{TPG.UI.BuildFonts}
     (its `CapMid` entry must exist; an unknown font name falls back to 0
     correction, i.e. plain line-box centring).
    @tparam number x
    @tparam number y
    @tparam number w
    @tparam number h
    @tparam Color color
    @realm client
]]
function TPG.UI.TextInBox(text, font, x, y, w, h, color)
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    draw.SimpleText(text, font,
        math.Round(x + (w - tw) / 2),
        math.Round(y + (h - th) / 2 + th * (TPG.UI.CapMid[font] or 0)),
        color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

--[[--
    Fit text to a width, ending in an ellipsis if it does not fit.

    Weapon names come from whatever packs are installed ("Carl Gustaf M2
    (HEDP 502)" is a real one) so no box width is safe on its own. Clipping
    with a render scissor would hide the overflow but leave a word cut
    mid-glyph with no sign anything is missing; an ellipsis says "there is
    more name here" and the full one is in the tooltip.

    Trims from the end one character at a time. Names are short enough that a
    binary search would only save a few string compares per frame, and this
    stays correct for multi-byte names (it steps back over UTF-8 continuation
    bytes rather than splitting a codepoint in half).

    @tparam string text
    @tparam string font A font name already created by @{TPG.UI.BuildFonts}.
    @tparam number maxW Maximum width in pixels.
    @treturn string `text` unchanged if it already fits; otherwise a prefix of
     it plus `"..."`; a bare `"..."` if even that does not fit `maxW`.
    @realm client
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

--[[--
    Break text into lines that each fit a width, splitting between words.

    @{TPG.UI.Truncate} is the right answer for a NAME: one line, an ellipsis,
    the full text a tooltip away. It is the wrong answer for a SENTENCE. The
    loadout menu's slot descriptions explain what a cooldown actually costs
    you, and a single line cut them at "until it runs out you spawn with the
    fre...", the setup with the answer missing, and nowhere else to read it.

    A word wider than the whole box gets a clipped line of its own (via
    Truncate) rather than being dropped or looping forever; a weapon pack is
    free to ship one.

    `maxLines` caps the block, because this text sits above a grid and a long
    description must not be able to push the grid off the panel. Everything
    past the cap is folded back onto the last line kept, so the ellipsis lands
    where the text really stops rather than at the end of a line that happened
    to fit.

    @tparam string text
    @tparam string font A font name already created by @{TPG.UI.BuildFonts}.
    @tparam number maxW Maximum width per line, in pixels.
    @tparam[opt] number maxLines If given, caps the number of lines returned;
     the tail is folded onto the last line and truncated with an ellipsis.
    @treturn {string,...} At least one line, even for an empty/nil `text`
     (returns `{ "" }`).
    @realm client
]]
function TPG.UI.Wrap(text, font, maxW, maxLines)
    surface.SetFont(font)

    local lines, line = {}, ""

    for word in string.gmatch(text or "", "%S+") do
        local candidate = (line == "") and word or (line .. " " .. word)

        if surface.GetTextSize(candidate) <= maxW then
            line = candidate
        elseif line == "" then
            lines[#lines + 1] = TPG.UI.Truncate(word, font, maxW)
        else
            lines[#lines + 1] = line
            line = word
        end
    end

    if line ~= "" then lines[#lines + 1] = line end
    if #lines == 0 then lines[1] = "" end

    if maxLines and #lines > maxLines then
        local tail = table.concat(lines, " ", maxLines, #lines)
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
        lines[maxLines] = TPG.UI.Truncate(tail, font, maxW)
    end

    return lines
end

--- Height of one line in a font.
-- Measures the sample string `"Ag"`, which has both an ascender and a
-- descender, so the result can never come back short the way a string with
-- neither (e.g. all-caps or all-lowercase-no-descender text) could.
-- @tparam string font A font name already created by @{TPG.UI.BuildFonts}.
-- @treturn number Line height in pixels.
-- @realm client
function TPG.UI.LineHeight(font)
    surface.SetFont(font)
    return select(2, surface.GetTextSize("Ag"))
end
