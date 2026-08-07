--[[--
    CTF status HUD: a world-space marker over the flag, plus a status banner.

    Only draws during a Capture the Flag round (`TPG.UI.State.gameType ==
    GAMEMODE_CTF`). Two parts:

      1. A world-space marker over the flag, matching the `tpg_controlpoint`
         markers drawn by `cl_hud_objectives.lua`, so you can always see where
         it is on screen.
      2. A top-centre status banner -- but only while the flag is actually in
         play (carried or dropped). When it's sitting neutral at home there's
         no nag to "capture it"; the world marker is enough to find it.

    Exports nothing. Finds the single `tpg_flag` entity via
    `ents.FindByClass("tpg_flag")[1]` on a 0.5s cache and reads its networked
    `FlagState`/`PossessTeam`/`Carrier`/`CarryEnd` directly -- there is no net
    message specific to this file. The carry timer bar reads `CarryEnd`
    (a `CurTime()` deadline the entity networks) rather than counting down
    independently, so it stays correct even if this HUD element opens partway
    through a carry. Stacks itself under `TPG.UI.BelowOvertime` (falling back
    to `TPG.UI.BelowObjectives`), so it moves down automatically while the
    overtime tag is showing.

    @module tpg.hud.ctf
    @realm client
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

    -- Bottom of the centre stack, not a hardcoded y=118 -- that number was the
    -- pip row's neighbourhood, so the banner sat on the point letters, and it
    -- didn't move when the HUD scaled.
    local S  = TPG.UI.S
    local sw = ScrW()
    local w, h = math.min(S(360), sw * 0.9), S(50)
    if carrying then h = h + S(44) end   -- room for the prompt + carry-timer bar
    local x = sw / 2 - w / 2
    local y = (TPG.UI.BelowOvertime and TPG.UI.BelowOvertime() or TPG.UI.BelowObjectives()) + S(10)

    draw.RoundedBox(S(6), x, y, w, h, Color(0, 0, 0, 160))
    draw.SimpleText("CAPTURE THE FLAG", "TPG.HUD.Label", x + w / 2, y + S(14),
        Color(245, 245, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(TPG.UI.Truncate(status, "TPG.HUD.Small", w - S(20)), "TPG.HUD.Small",
        x + w / 2, y + S(34), sCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if carrying then
        draw.SimpleText("BRING IT TO YOUR SPAWN!", "TPG.HUD.Label", x + w / 2, y + S(54),
            Color(255, 230, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Carry timer: how long before the flag auto-returns (anti-hoarding). The
        -- bar drains and reddens as it runs out; it counts here in the HUD, not on
        -- the flag model.
        local total   = TPG.Config.ctfMaxCarryTime or 150
        local remain  = math.max(flag:GetCarryEnd() - CurTime(), 0)
        local frac    = math.Clamp(remain / total, 0, 1)
        local barW, barH = w - S(40), S(8)
        local barX, barY = x + S(20), y + S(68)
        local fill = frac > 0.33 and Color(120, 220, 120)
            or Color(240, 90, 70)

        draw.RoundedBox(S(3), barX - 1, barY - 1, barW + 2, barH + 2, Color(0, 0, 0, 200))
        draw.RoundedBox(S(3), barX, barY, barW, barH, Color(45, 45, 45, 220))
        draw.RoundedBox(S(3), barX, barY, barW * frac, barH, fill)
        draw.SimpleText(math.ceil(remain) .. "s", "TPG.HUD.Small", x + w / 2, barY + barH + S(8),
            Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)
