--[[--
    Objective overtime banner: a big alert, then a small persistent tag.

    The server flips the global bool `TPG_ObjOvertime` when an objective round
    has run long enough that it starts closing itself out
    (`objectives/sv_objectives.lua`). Players need to know the rules changed
    under them -- a point that used to take ten seconds now flips almost on
    contact, and tickets are pouring out -- so this is a full pulsing banner
    for `BANNER_TIME` (8s) seconds after `TPG_ObjOvertimeStart`, then a small
    persistent tag for as long as overtime stays active, so nobody who joined
    late is left wondering why the hill is behaving strangely.

    Exports @{BelowOvertime}, which every element that stacks under the
    centre HUD column (currently the CTF banner) calls to find its own top
    rather than hardcoding a y-offset. Reads `TPG.UI.BelowCompass` (falling
    back to `TPG.UI.BelowObjectives` if the compass module hasn't loaded) to
    find where the stack already ends above it.

    @module tpg.hud.overtime
    @realm client
]]

local BANNER_TIME = 8

local function OvertimeSince()
    if not GetGlobalBool("TPG_ObjOvertime", false) then return nil end
    local started = GetGlobalFloat("TPG_ObjOvertimeStart", 0)
    if started <= 0 then return nil end
    return CurTime() - started
end

-- Height of the persistent tag, so the tag's own draw and the elements stacking
-- under it agree on one number.
local function TagMetrics()
    surface.SetFont("TPG.HUD.Small")
    local tw, th = surface.GetTextSize("OVERTIME")
    return tw, th + TPG.UI.S(7)
end

--[[--
    Bottom of the centre stack including the overtime tag, for anything that
    stacks below it (the CTF banner).

    Returns the compass bottom when overtime isn't showing a persistent tag
    (either not in overtime, or still within the first `BANNER_TIME` seconds
    where the big banner is drawn instead), so nothing leaves a hole waiting
    for a tag that may never appear.

    @treturn number Y coordinate in screen pixels.
    @realm client
]]
function TPG.UI.BelowOvertime()
    local base  = TPG.UI.BelowCompass and TPG.UI.BelowCompass() or TPG.UI.BelowObjectives()
    local since = OvertimeSince()
    if not since or since < BANNER_TIME then return base end

    local _, boxH = TagMetrics()
    return base + TPG.UI.S(8) + boxH
end

hook.Add("HUDPaint", "TPG_OvertimeHUD", function()
    local since = OvertimeSince()
    if not since then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local C  = TPG.Colors
    local sw = ScrW()

    if since < BANNER_TIME then
        -- Pulse it so it reads as an alert rather than another status box.
        local pulse = 0.75 + 0.25 * math.sin(CurTime() * 6)
        local fade  = math.Clamp((BANNER_TIME - since) / 1.5, 0, 1)
        local S     = TPG.UI.S
        local w, h  = math.min(S(620), sw * 0.9), S(82)
        local x, y  = sw / 2 - w / 2, ScrH() * 0.30

        draw.RoundedBox(S(8), x, y, w, h, Color(C.Panel.r, C.Panel.g, C.Panel.b, 235 * fade))
        draw.RoundedBox(0, x + S(8), y, w - S(16), math.max(S(3), 1),
            Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * fade * pulse))

        draw.SimpleText("OVERTIME", "TPG.HUD.Big", x + w / 2, y + S(28),
            Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * fade * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Capture time slashed - points flip almost instantly", "TPG.HUD.Label",
            x + w / 2, y + S(54), Color(C.Text.r, C.Text.g, C.Text.b, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Tickets are draining fast. Take the point and end it.", "TPG.HUD.Small",
            x + w / 2, y + S(72), Color(C.TextMuted.r, C.TextMuted.g, C.TextMuted.b, 255 * fade),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    --[[
        Persistent reminder. Sits at the BOTTOM of the centre stack, not at a
        fraction of screen height: ScrH() * 0.10 is 108px at 1080p, which landed
        right on the pip row and printed OVERTIME through the point letters.

        It goes under the compass rather than between the compass and the pips,
        because the compass is always there and overtime is not -- the element
        that comes and goes is the one that should move, so the permanent HUD
        never shifts under the player mid-round.
    ]]
    local S = TPG.UI.S
    local y = (TPG.UI.BelowCompass and TPG.UI.BelowCompass() or TPG.UI.BelowObjectives()) + S(8)
    local pulse = 0.6 + 0.4 * math.sin(CurTime() * 3)

    local tw, boxH = TagMetrics()
    draw.RoundedBox(S(4), sw / 2 - tw / 2 - S(10), y, tw + S(20), boxH, C.Panel)
    draw.SimpleText("OVERTIME", "TPG.HUD.Small", sw / 2, y + boxH / 2,
        Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
