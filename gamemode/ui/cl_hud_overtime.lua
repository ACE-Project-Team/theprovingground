--[[
    Objective overtime banner (client)

    The server flips TPG_ObjOvertime when an objective round has run long enough
    that it starts closing itself out (objectives/sv_objectives.lua). Players
    need to know the rules changed under them -- a point that used to take ten
    seconds now flips almost on contact, and tickets are pouring out -- so this
    is a full banner for BANNER_TIME, then a small persistent tag so nobody who
    joined late is left wondering why the hill is behaving strangely.
]]

local BANNER_TIME = 8

local function OvertimeSince()
    if not GetGlobalBool("TPG_ObjOvertime", false) then return nil end
    local started = GetGlobalFloat("TPG_ObjOvertimeStart", 0)
    if started <= 0 then return nil end
    return CurTime() - started
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
        local w, h  = 620, 82
        local x, y  = sw / 2 - w / 2, ScrH() * 0.30

        draw.RoundedBox(8, x, y, w, h, Color(C.Panel.r, C.Panel.g, C.Panel.b, 235 * fade))
        draw.RoundedBox(0, x + 8, y, w - 16, 3, Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * fade * pulse))

        draw.SimpleText("OVERTIME", "TPG.HUD.Big", x + w / 2, y + 28,
            Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * fade * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Capture time slashed - points flip almost instantly", "TPG.HUD.Label",
            x + w / 2, y + 54, Color(C.Text.r, C.Text.g, C.Text.b, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Tickets are draining fast. Take the point and end it.", "TPG.HUD.Small",
            x + w / 2, y + 72, Color(C.TextMuted.r, C.TextMuted.g, C.TextMuted.b, 255 * fade),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    --[[
        Persistent reminder. Sits BELOW the point pips, not at a fraction of
        screen height: ScrH() * 0.10 is 108px at 1080p, which landed right on
        the pip row and printed OVERTIME through the point letters. Asking the
        main HUD where its centre stack ends means this can't collide with it
        at any resolution, or if the pip row appears/disappears mid-round.
    ]]
    local y = (TPG.UI and TPG.UI.BelowObjectives and TPG.UI.BelowObjectives() or 110) + 10
    local pulse = 0.6 + 0.4 * math.sin(CurTime() * 3)

    surface.SetFont("TPG.HUD.Small")
    local tw = surface.GetTextSize("OVERTIME")
    draw.RoundedBox(4, sw / 2 - tw / 2 - 10, y, tw + 20, 22, C.Panel)
    draw.SimpleText("OVERTIME", "TPG.HUD.Small", sw / 2, y + 11,
        Color(C.Warn.r, C.Warn.g, C.Warn.b, 255 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
