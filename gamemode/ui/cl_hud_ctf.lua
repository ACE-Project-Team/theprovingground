--[[
    CTF status HUD. Two parts, only during a Capture the Flag round:

      1. A world-space marker over the flag (like control points get), so you can
         always see where it is on screen.
      2. A top-centre status banner -- but only while the flag is actually in play
         (carried or dropped). When it's sitting neutral at home there's no nag to
         "capture it"; the world marker is enough to find it.
]]

local flagCache, lastCache = nil, 0

local function UpdateCache()
    if CurTime() - lastCache < 0.5 then return end
    lastCache = CurTime()
    flagCache = ents.FindByClass("tpg_flag")[1]
end

-- Colour/label for a flag state, shared by the marker and the banner.
local function StateInfo(flag)
    local state = flag:GetFlagState()
    if state == flag.STATE_HOME then
        -- Marker uses the same yellow as an uncaptured control point.
        return "NEUTRAL", Color(255, 255, 0), state
    elseif state == flag.STATE_CARRIED then
        local td = TPG.GetTeamData(flag:GetPossessTeam())
        local c  = flag:GetCarrier()
        local label = "HELD BY " .. (td and string.upper(td.name) or "?") ..
            (IsValid(c) and ("  (" .. c:Nick() .. ")") or "")
        return label, (td and td.color) or Color(255, 205, 40), state
    end
    return "DROPPED", Color(255, 200, 80), state
end

hook.Add("HUDPaint", "TPG_CTFHUD", function()
    if TPG.UI.State.gameType ~= GAMEMODE_CTF then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    UpdateCache()
    local flag = flagCache
    if not IsValid(flag) then return end

    local status, sCol, state = StateInfo(flag)

    -- (1) World-space marker over the flag, matching the control-point markers.
    local markerPos = flag:GetPos() + Vector(0, 0, 150)
    local scr = markerPos:ToScreen()
    if scr.visible then
        draw.RoundedBox(8, scr.x - 8, scr.y - 8, 18, 18, Color(0, 0, 0, 200))
        draw.RoundedBox(8, scr.x - 6, scr.y - 6, 14, 14, sCol)
        draw.SimpleText("FLAG", "DermaDefaultBold", scr.x + 1, scr.y - 19,
            Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("FLAG", "DermaDefaultBold", scr.x, scr.y - 20,
            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- (2) Top-centre banner only while the flag is in play. No banner when it's
    -- neutral at home -- nothing to prompt the player to do yet.
    if state == flag.STATE_HOME then return end

    local carrying = (state == flag.STATE_CARRIED and flag:GetCarrier() == ply)

    local sw = ScrW()
    local w, h = 360, 50
    if carrying then h = h + 18 end
    local x, y = sw / 2 - w / 2, 118

    draw.RoundedBox(6, x, y, w, h, Color(0, 0, 0, 160))
    draw.SimpleText("CAPTURE THE FLAG", "DermaDefaultBold", x + w / 2, y + 14,
        Color(245, 245, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(status, "DermaDefaultBold", x + w / 2, y + 34,
        sCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if carrying then
        draw.SimpleText("BRING IT TO YOUR SPAWN!", "DermaDefaultBold", x + w / 2, y + 54,
            Color(255, 230, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)
