--[[--
    Rush status HUD: which stage this is, and how the hold is going.

    Only draws during a Rush round (`TPG.UI.State.gameType == GAMEMODE_RUSH`).
    One top-centre banner carrying the stage counter, the stage tally, and a
    progress bar for the live hold.

    Reads the globals `objectives/sv_rush.lua` publishes (`TPG_RushStage`,
    `TPG_RushStages`, `TPG_RushGreen`, `TPG_RushRed`, `TPG_RushHoldTeam`,
    `TPG_RushHoldFrac`, `TPG_RushBreak`) rather than a net message of its own --
    they are small, change at most once a scoring step, and a late-joining
    client gets the current values for free.

    The bar is drawn in the HOLDING team's colour, not the local player's, so a
    bar filling up is unambiguously good or bad at a glance without reading the
    label. Stacks under `TPG.UI.BelowOvertime` the same way the CTF banner does.

    Between stages the hold bar is replaced by a countdown, and the header
    counts the stage that is COMING rather than the one just finished. There is
    deliberately no hint of where the next point will be: the client is not told,
    because the server has not placed it yet.

    Exports nothing.

    @module tpg.hud.rush
    @realm client
]]

hook.Add("HUDPaint", "TPG_RushHUD", function()
    if TPG.UI.State.gameType ~= GAMEMODE_RUSH then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local stage  = GetGlobalInt("TPG_RushStage", 0)
    local stages = GetGlobalInt("TPG_RushStages", 0)
    if stage <= 0 or stages <= 0 then return end

    local S  = TPG.UI.S
    local sw = ScrW()
    local w, h = math.min(S(360), sw * 0.9), S(66)
    local x = sw / 2 - w / 2
    local y = (TPG.UI.BelowOvertime and TPG.UI.BelowOvertime() or TPG.UI.BelowObjectives()) + S(10)

    -- Seconds until the next point appears; 0 whenever a stage is actually live.
    local brk = GetGlobalFloat("TPG_RushBreak", 0)

    draw.RoundedBox(S(6), x, y, w, h, Color(0, 0, 0, 160))

    -- On a break the stage counter reads forward, to the one about to start.
    -- Leaving it on the finished stage would put a countdown under a heading
    -- for something that is already over.
    local shown = (brk > 0) and math.min(stage + 1, stages) or stage
    draw.SimpleText(string.format("STAGE %d OF %d", shown, stages), "TPG.HUD.Label",
        x + w / 2, y + S(14), Color(245, 245, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Stage tally, each side in its own colour and on its own side of the dash,
    -- so which number belongs to you never needs working out.
    local green = TPG.GetTeamData(TEAM_GREEN)
    local red   = TPG.GetTeamData(TEAM_RED)
    draw.SimpleText(GetGlobalInt("TPG_RushGreen", 0), "TPG.HUD.Small",
        x + w / 2 - S(14), y + S(34), (green and green.color) or Color(120, 220, 120),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("-", "TPG.HUD.Small", x + w / 2, y + S(34),
        Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(GetGlobalInt("TPG_RushRed", 0), "TPG.HUD.Small",
        x + w / 2 + S(14), y + S(34), (red and red.color) or Color(230, 110, 100),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Between stages the bar has nothing to show -- there is no point to hold --
    -- so the countdown takes its place in the same strip, and the banner keeps
    -- its size rather than collapsing and shoving the rest of the HUD about.
    if brk > 0 then
        draw.SimpleText(string.format("NEXT POINT IN %d:%02d",
            math.floor(brk / 60), math.floor(brk % 60)), "TPG.HUD.Small",
            x + w / 2, y + S(52), Color(255, 205, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    -- Hold bar. An empty track still draws when nobody holds the point: the gap
    -- between "contested" and "somebody is 90% of the way to taking this" is the
    -- whole tension of a stage, and a bar that vanishes when it hits zero hides
    -- the moment a hold gets broken.
    local holdTeam = GetGlobalInt("TPG_RushHoldTeam", 0)
    local frac     = math.Clamp(GetGlobalFloat("TPG_RushHoldFrac", 0), 0, 1)
    local td       = (holdTeam ~= 0) and TPG.GetTeamData(holdTeam) or nil

    local barW, barH = w - S(40), S(8)
    local barX, barY = x + S(20), y + S(48)
    draw.RoundedBox(S(3), barX - 1, barY - 1, barW + 2, barH + 2, Color(0, 0, 0, 200))
    draw.RoundedBox(S(3), barX, barY, barW, barH, Color(45, 45, 45, 220))

    if frac > 0 then
        draw.RoundedBox(S(3), barX, barY, barW * frac, barH,
            (td and td.color) or Color(255, 205, 40))
    end

    local hold   = math.max(TPG.Config.rushHoldTime or 60, 1)
    local label  = td and string.format("%s HOLDING - %ds LEFT",
        string.upper(td.name), math.ceil(hold * (1 - frac)))
        or "POINT CONTESTED"
    draw.SimpleText(label, "TPG.HUD.Small", x + w / 2, barY + barH + S(8),
        (td and td.color) or Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
