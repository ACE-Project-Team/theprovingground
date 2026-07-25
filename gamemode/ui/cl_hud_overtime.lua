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

    local sw = ScrW()

    if since < BANNER_TIME then
        -- Pulse it so it reads as an alert rather than another status box.
        local pulse = 0.75 + 0.25 * math.sin(CurTime() * 6)
        local fade  = math.Clamp((BANNER_TIME - since) / 1.5, 0, 1)
        local w, h  = 620, 78
        local x, y  = sw / 2 - w / 2, ScrH() * 0.30

        draw.RoundedBox(8, x, y, w, h, Color(0, 0, 0, 190 * fade))
        draw.RoundedBox(8, x, y, w, 4, Color(255, 120, 40, 255 * fade * pulse))

        draw.SimpleText("OVERTIME", "DermaLarge", x + w / 2, y + 26,
            Color(255, 140, 50, 255 * fade * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Capture time slashed -- points flip almost instantly", "DermaDefaultBold",
            x + w / 2, y + 50, Color(235, 235, 235, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Tickets are draining fast. Take the point and end it.", "DermaDefault",
            x + w / 2, y + 66, Color(200, 200, 200, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    -- Persistent reminder, small and out of the way.
    local pulse = 0.6 + 0.4 * math.sin(CurTime() * 3)
    draw.SimpleText("OVERTIME", "DermaDefaultBold", sw / 2, ScrH() * 0.10,
        Color(255, 140, 50, 255 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
