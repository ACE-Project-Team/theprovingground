--[[--
    Rush status HUD: which stage this is, and how the hold is going.

    Only draws during a Rush round (`TPG.UI.State.gameType == GAMEMODE_RUSH`).
    One small top-LEFT panel carrying the stage counter, the stage tally, and a
    progress bar for the live hold.

    It sat top-centre at first, under the compass, and was wrong twice over: it
    was far bigger than three numbers need, and the centre column is the busiest
    part of the screen -- ticket bars, point pips, compass, objective markers --
    so a banner there covered the map through the part of a stage where looking
    at the map is the whole job. Top-left is the quiet corner: it already holds
    the mode pills, this stacks under them, and nothing there is world-space.

    Reads the globals `objectives/sv_rush.lua` publishes (`TPG_RushStage`,
    `TPG_RushStages`, `TPG_RushGreen`, `TPG_RushRed`, `TPG_RushHoldTeam`,
    `TPG_RushHoldFrac`, `TPG_RushBreak`) rather than a net message of its own --
    they are small, change at most once a scoring step, and a late-joining
    client gets the current values for free.

    The bar is drawn in the HOLDING team's colour, not the local player's, so a
    bar filling up is unambiguously good or bad at a glance without reading the
    label -- which is what lets the label be as short as it is.

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

    local S = TPG.UI.S
    local L = TPG.UI.ComputeLayout()

    -- Stack under the mode pills that cl_hud.lua draws in this corner. The
    -- economy pill is conditional, so the anchor is read off whether it is
    -- there rather than assumed -- otherwise this floats in a gap on every
    -- team-budget round.
    local pillsBottom = GetGlobalBool("TPG_EconomyActive", false) and S(78) or S(48)

    local w, h = S(180), S(50)
    local x, y = L.margin, pillsBottom + S(8)

    -- Seconds until the next point appears; 0 whenever a stage is actually live.
    local brk = GetGlobalFloat("TPG_RushBreak", 0)

    draw.RoundedBox(S(4), x, y, w, h, Color(0, 0, 0, 150))

    -- On a break the stage counter reads forward, to the one about to start.
    -- Leaving it on the finished stage would put a countdown under a heading
    -- for something that is already over.
    local shown = (brk > 0) and math.min(stage + 1, stages) or stage
    draw.SimpleText(string.format("STAGE %d/%d", shown, stages), "TPG.HUD.Small",
        x + S(10), y + S(12), Color(245, 245, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Stage tally, hard right, each side in its own colour and on its own side
    -- of the dash, so which number belongs to you never needs working out.
    local green = TPG.GetTeamData(TEAM_GREEN)
    local red   = TPG.GetTeamData(TEAM_RED)
    draw.SimpleText(GetGlobalInt("TPG_RushRed", 0), "TPG.HUD.Small",
        x + w - S(10), y + S(12), (red and red.color) or Color(230, 110, 100),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText("-", "TPG.HUD.Small", x + w - S(20), y + S(12),
        Color(150, 150, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(GetGlobalInt("TPG_RushGreen", 0), "TPG.HUD.Small",
        x + w - S(28), y + S(12), (green and green.color) or Color(120, 220, 120),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    local barW, barH = w - S(20), S(6)
    local barX, barY = x + S(10), y + S(26)

    -- Between stages the bar has nothing to show -- there is no point to hold --
    -- so the countdown takes the whole lower half, and the panel keeps its size
    -- rather than collapsing and shoving the mode pills about.
    if brk > 0 then
        draw.SimpleText(string.format("NEXT POINT %d:%02d",
            math.floor(brk / 60), math.floor(brk % 60)), "TPG.HUD.Small",
            x + S(10), y + S(34), Color(255, 205, 40), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return
    end

    -- Hold bar. An empty track still draws when nobody holds the point: the gap
    -- between "contested" and "somebody is 90% of the way to taking this" is the
    -- whole tension of a stage, and a bar that vanishes when it hits zero hides
    -- the moment a hold gets broken.
    local holdTeam = GetGlobalInt("TPG_RushHoldTeam", 0)
    local frac     = math.Clamp(GetGlobalFloat("TPG_RushHoldFrac", 0), 0, 1)
    local td       = (holdTeam ~= 0) and TPG.GetTeamData(holdTeam) or nil

    draw.RoundedBox(S(2), barX, barY, barW, barH, Color(45, 45, 45, 220))
    if frac > 0 then
        draw.RoundedBox(S(2), barX, barY, barW * frac, barH,
            (td and td.color) or Color(255, 205, 40))
    end

    -- The bar's colour already says who is holding, so the label only has to
    -- carry the number the bar cannot: how long is left.
    local hold  = math.max(TPG.Config.rushHoldTime or 60, 1)
    local label = td and string.format("HOLDING - %ds", math.ceil(hold * (1 - frac)))
        or "CONTESTED"
    draw.SimpleText(label, "TPG.HUD.Small", x + S(10), y + S(41),
        (td and td.color) or Color(190, 190, 190), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
