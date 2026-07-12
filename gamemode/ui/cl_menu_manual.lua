--[[
    Field Manual (client)

    In-game explainer for TPG's mechanics: modes, tickets, building, economy,
    underdog bonuses, ranks, controls. Opened with tpg_menu_manual, or the
    MANUAL buttons in the F2 team menu and the profile screen.

    Content lives in the SECTIONS table below -- keep entries short; this is a
    crib sheet, not documentation.
]]

local COL = {
    bg      = Color(24, 26, 30),
    panel   = Color(34, 37, 43),
    panelHi = Color(44, 48, 56),
    line    = Color(70, 76, 86),
    text    = Color(225, 228, 232),
    textDim = Color(150, 156, 165),
    accent  = Color(245, 200, 70),
}

local SECTIONS = {
    {
        title = "THE BASICS",
        lines = {
            "Two teams, one map, everything is built by players. Pick a team (F2),",
            "pick a loadout (F3), then paste a vehicle with AdvDupe2 inside your",
            "safezone and drive it out. Your team's tickets are its life bar --",
            "first team at 0 tickets loses the round.",
        },
    },
    {
        title = "GAME MODES",
        lines = {
            "CONTROL POINTS - hold more points than the enemy; their tickets drain.",
            "KING OF THE HILL - same idea, one hill, faster drain.",
            "DEATHMATCH - deaths cost tickets. After 10 minutes OVERTIME starts and",
            "  both teams bleed tickets at a growing rate: hiding just loses slower.",
            "CAPTURE THE FLAG - a neutral flag sits on the hill. Carry it into your",
            "  own safezone to take a bite out of the enemy's tickets. Carrying it",
            "  too long returns it -- no hoarding.",
        },
    },
    {
        title = "BUILDING & LIMITS",
        lines = {
            "You can only spawn/paste inside your safezone. Your team shares a",
            "budget of ACE points, weight and props (top of the HUD). Heavier and",
            "pricier dupes put your duplicator on cooldown -- light vehicles skip it.",
            "The first round of a map waits for everyone to load in before starting.",
        },
    },
    {
        title = "PER-PLAYER ECONOMY (some rounds)",
        lines = {
            "Announced at round start. Instead of a shared team budget, YOU have a",
            "wallet: vehicles are purchases and destroyed ones are NOT refunded.",
            "Earn by playing -- kills (bigger targets pay more), standing on",
            "objectives, passive trickle, flag deliveries. No duplicator cooldown,",
            "but stock vehicles (jeep/airboat/APC) cost points too. Team kills fine you.",
        },
    },
    {
        title = "UNDERDOG BONUS",
        lines = {
            "Losing badly (tickets far behind) activates team-wide help: longer",
            "spawn protection, a free smoke grenade, extra launcher rockets and",
            "+25% economy income. It switches off once you claw back into the game.",
        },
    },
    {
        title = "RANKS & PROFILE",
        lines = {
            "Everything you do earns (or costs) lifetime rating: kills, captures,",
            "flag runs, round wins. Check your rank, stats and the server top 10",
            "under PROFILE in the F2 menu. Team scrambles use rating to build fair",
            "teams. The ladder runs from Traffic Cone to Global Proving Elite.",
        },
    },
    {
        title = "SPECTATORS",
        lines = {
            "Spectators can build and test freely: no budget, no cooldown, godmode,",
            "and their guns can't hurt anyone. Join with  tpg_team spec.",
        },
    },
    {
        title = "CONTROLS & COMMANDS",
        lines = {
            "F2 teams / profile / manual     F3 loadout     F4 enter nearest vehicle",
            "tpg_team green | red | spec  - switch team from console",
            "tpg_rtv  - vote to change map      tpg_scramble  - vote to scramble",
            "Everything is rebindable; the F-keys are GMod defaults.",
        },
    },
}

local function OpenManual()
    local W, H = 720, 560
    local frame = vgui.Create("DFrame")
    frame:SetSize(W, H)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(false)
    frame:ShowCloseButton(true)
    frame:MakePopup()

    frame.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, COL.bg)
        draw.RoundedBox(0, 0, 0, w, 64, COL.panel)
        draw.SimpleText("FIELD MANUAL", "DermaLarge", 24, 20, COL.text, TEXT_ALIGN_LEFT)
        draw.SimpleText("The Proving Ground, explained in one scroll", "DermaDefault",
            26, 44, COL.textDim, TEXT_ALIGN_LEFT)
        surface.SetDrawColor(COL.line)
        surface.DrawRect(0, 64, w, 1)
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(16, 76)
    scroll:SetSize(W - 32, H - 92)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    function sbar:Paint(w, h) draw.RoundedBox(3, 0, 0, w, h, COL.panel) end
    function sbar.btnGrip:Paint(w, h) draw.RoundedBox(3, 0, 0, w, h, COL.line) end
    sbar.btnUp.Paint, sbar.btnDown.Paint = function() end, function() end

    local LINE_H, PAD = 18, 14

    for _, section in ipairs(SECTIONS) do
        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:DockMargin(0, 0, 8, 10)
        panel:SetTall(PAD * 2 + 22 + #section.lines * LINE_H)
        panel.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, COL.panel)
            draw.SimpleText(section.title, "DermaDefaultBold", PAD, PAD, COL.accent, TEXT_ALIGN_LEFT)
            for i, line in ipairs(section.lines) do
                draw.SimpleText(line, "DermaDefault", PAD, PAD + 22 + (i - 1) * LINE_H,
                    COL.text, TEXT_ALIGN_LEFT)
            end
        end
    end
end

concommand.Add("tpg_menu_manual", OpenManual)
