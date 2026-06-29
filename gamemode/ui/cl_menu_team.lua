--[[
    Team Selection Menu

    This is the first screen a player sees, so besides picking a side it doubles
    as a quick-start tutorial: it spells out the default control binds and the
    basic flow (pick team -> pick loadout -> spawn/enter a vehicle).
]]

-- ── Palette ────────────────────────────────────────────────────────────────
local COL = {
    bg       = Color(24, 26, 30),
    panel    = Color(34, 37, 43),
    panelHi  = Color(44, 48, 56),
    line     = Color(70, 76, 86),
    text     = Color(225, 228, 232),
    textDim  = Color(150, 156, 165),
    green    = Color(60, 180, 75),
    greenHi  = Color(80, 210, 95),
    red      = Color(210, 60, 60),
    redHi    = Color(235, 80, 80),
    spec     = Color(120, 128, 140),
    specHi   = Color(150, 158, 170),
    accent   = Color(245, 200, 70),
}

-- Styled flat button with a colored fill, hover lift, and optional sub-label.
local function StyleButton(parent, label, sub, base, hi, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.Paint = function(self, w, h)
        local c = self:IsHovered() and hi or base
        draw.RoundedBox(6, 0, 0, w, h, c)
        if self:IsHovered() then
            surface.SetDrawColor(255, 255, 255, 20)
            surface.DrawRect(0, 0, w, h)
        end
        draw.SimpleText(label, "DermaLarge", w / 2, sub and h / 2 - 12 or h / 2,
            COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if sub then
            draw.SimpleText(sub, "DermaDefault", w / 2, h / 2 + 16,
                Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    btn.DoClick = onClick
    return btn
end

local function OpenTeamMenu()
    local W, H = 760, 520

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
        draw.SimpleText("THE PROVING GROUND", "DermaLarge", 24, 20, COL.text, TEXT_ALIGN_LEFT)
        draw.SimpleText("Choose your side", "DermaDefault", 26, 44, COL.textDim, TEXT_ALIGN_LEFT)
        surface.SetDrawColor(COL.line)
        surface.DrawRect(0, 64, w, 1)
    end

    -- ── Team buttons ─────────────────────────────────────────────────────
    local btnY, btnH = 90, 130
    local pad        = 24
    local colW       = (W - pad * 4) / 3

    local g = StyleButton(frame, "GREEN TERROR", "Click or  tpg_team 1", COL.green, COL.greenHi, function()
        LocalPlayer():EmitSound("doors/doorstop1.wav")
        RunConsoleCommand("tpg_team", TEAM_GREEN)
        frame:Close()
    end)
    g:SetPos(pad, btnY)
    g:SetSize(colW, btnH)

    local s = StyleButton(frame, "SPECTATE", "Watch / undecided", COL.spec, COL.specHi, function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_team", TEAM_UNASSIGNED)
        frame:Close()
    end)
    s:SetPos(pad * 2 + colW, btnY)
    s:SetSize(colW, btnH)

    local r = StyleButton(frame, "RED MENACE", "Click or  tpg_team 2", COL.red, COL.redHi, function()
        LocalPlayer():EmitSound("doors/doorstop1.wav")
        RunConsoleCommand("tpg_team", TEAM_RED)
        frame:Close()
    end)
    r:SetPos(pad * 3 + colW * 2, btnY)
    r:SetSize(colW, btnH)

    -- ── Tutorial / controls panel ────────────────────────────────────────
    local tut = vgui.Create("DPanel", frame)
    tut:SetPos(pad, btnY + btnH + 20)
    tut:SetSize(W - pad * 2, 200)
    tut.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, COL.panel)
        draw.SimpleText("HOW TO PLAY", "DermaDefaultBold", 16, 14, COL.accent, TEXT_ALIGN_LEFT)

        -- Control binds (GMod defaults; players can rebind in Options).
        local rows = {
            { "F2", "Open this team menu" },
            { "F3", "Loadout: pick weapons & armor" },
            { "F4", "Enter the nearest vehicle you own" },
            { "AdvDupe2", "Paste a saved vehicle to field it" },
        }
        local y = 44
        for _, row in ipairs(rows) do
            draw.RoundedBox(4, 16, y, 84, 24, COL.panelHi)
            draw.SimpleText(row[1], "DermaDefaultBold", 58, y + 12, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(row[2], "DermaDefault", 112, y + 12, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            y = y + 32
        end

        draw.SimpleText("Tip: keys are the defaults - rebind them under Options > Keyboard if needed.",
            "DermaDefault", 16, h - 22, COL.textDim, TEXT_ALIGN_LEFT)
    end

    -- ── RTV / Scramble ───────────────────────────────────────────────────
    local botY = H - 70
    local rtv = StyleButton(frame, "ROCK THE VOTE", nil, COL.panelHi, COL.line, function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_rtv")
        frame:Close()
    end)
    rtv:SetPos(pad, botY)
    rtv:SetSize((W - pad * 3) / 2, 46)

    local scr = StyleButton(frame, "VOTE SCRAMBLE", nil, COL.panelHi, COL.line, function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_scramble")
        frame:Close()
    end)
    scr:SetPos(pad * 2 + (W - pad * 3) / 2, botY)
    scr:SetSize((W - pad * 3) / 2, 46)
end

concommand.Add("tpg_menu_team", OpenTeamMenu)
