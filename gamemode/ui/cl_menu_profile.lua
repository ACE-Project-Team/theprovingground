--[[--
    Player profile and rankings screen: lifetime stats, rank progress and a
    server top-10 leaderboard.

    Exports nothing. Opened with `tpg_menu_profile` or the PROFILE button in
    the F2 team menu; `OpenProfile` re-requests fresh data every time it opens
    by sending an empty `TPG_ProfileData` message to the server and rendering
    with whatever is cached from the previous reply in the meantime, so the
    frame never blocks on the round trip. The reply's `net.Receive` handler
    reads a fixed sequence of unsigned ints (rating, kills, deaths, teamkills,
    caps, flags, wins, rounds) followed by up to 15 leaderboard entries
    (`net.ReadUInt(4)` count, capped by that 4-bit width) -- the read order
    here must exactly match whatever `systems/sv_stats.lua` writes, since
    net messages carry no field names. An open profile window repaints from
    the shared `profile` table every frame, so a reply that lands after the
    menu is already open just makes the numbers update in place.

    The right-hand column carries the server top-10 above the full rank ladder,
    which is built from `TPG.Ranks` (`config/sh_ranks.lua`) and so always shows
    this server's tiers and thresholds rather than a copy of them. It is a
    scroll panel because the ladder is longer than the space and gets longer
    when an operator adds tiers; the rows are created once at open and read
    `profile` live in their `Paint`, so the "you are here" highlight appears on
    its own when the reply lands.

    @module tpg.menu.profile
    @realm client
]]

local COL = {
    bg      = Color(24, 26, 30),
    panel   = Color(34, 37, 43),
    panelHi = Color(44, 48, 56),
    line    = Color(70, 76, 86),
    text    = Color(225, 228, 232),
    textDim = Color(150, 156, 165),
    accent  = Color(245, 200, 70),
    green   = Color(60, 180, 75),
}

local profile = nil   -- last received payload

net.Receive("TPG_ProfileData", function()
    profile = {
        rating    = net.ReadUInt(16),
        kills     = net.ReadUInt(24),
        deaths    = net.ReadUInt(24),
        teamkills = net.ReadUInt(16),
        caps      = net.ReadUInt(16),
        flags     = net.ReadUInt(16),
        wins      = net.ReadUInt(16),
        rounds    = net.ReadUInt(16),
        top       = {},
    }
    local n = net.ReadUInt(4)
    for i = 1, n do
        profile.top[i] = { name = net.ReadString(), rating = net.ReadUInt(16) }
    end
    -- An open profile window repaints from this table live; nothing to poke.
end)

local function OpenProfile()
    -- Ask for fresh data every open; render with what we have meanwhile.
    net.Start("TPG_ProfileData")
    net.SendToServer()

    local W, H = 780, 620
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
        draw.SimpleText("SERVICE RECORD", "DermaLarge", 24, 20, COL.text, TEXT_ALIGN_LEFT)
        draw.SimpleText(LocalPlayer():Nick(), "DermaDefault", 26, 44, COL.textDim, TEXT_ALIGN_LEFT)
        surface.SetDrawColor(COL.line)
        surface.DrawRect(0, 64, w, 1)
    end

    local pad = 24

    -- ── Left: own rank + stats ───────────────────────────────────────────
    local left = vgui.Create("DPanel", frame)
    left:SetPos(pad, 84)
    left:SetSize(430, H - 84 - 76)
    left.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, COL.panel)

        if not profile then
            draw.SimpleText("Fetching your record...", "DermaDefaultBold", w / 2, h / 2,
                COL.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local rank, _ = TPG.GetRank(profile.rating)
        local prog, nextRank = TPG.GetRankProgress(profile.rating)

        draw.SimpleText("RANK", "DermaDefaultBold", 20, 18, COL.textDim, TEXT_ALIGN_LEFT)
        draw.SimpleText(rank.name, "DermaLarge", 20, 38, rank.color, TEXT_ALIGN_LEFT)
        draw.SimpleText(profile.rating .. " RP", "DermaDefaultBold", w - 20, 44,
            COL.text, TEXT_ALIGN_RIGHT)

        -- Progress bar to next rank
        local barY = 84
        draw.RoundedBox(4, 20, barY, w - 40, 10, COL.panelHi)
        if nextRank then
            draw.RoundedBox(4, 20, barY, (w - 40) * prog, 10, rank.color)
            draw.SimpleText("next: " .. nextRank.name .. " (" .. nextRank.min .. ")",
                "DermaDefault", w - 20, barY + 20, COL.textDim, TEXT_ALIGN_RIGHT)
        else
            draw.RoundedBox(4, 20, barY, w - 40, 10, rank.color)
            draw.SimpleText("top of the ladder", "DermaDefault", w - 20, barY + 20,
                COL.textDim, TEXT_ALIGN_RIGHT)
        end

        -- Stats grid
        local kd = profile.deaths > 0 and string.format("%.2f", profile.kills / profile.deaths)
            or tostring(profile.kills)
        local wr = profile.rounds > 0 and (math.Round(profile.wins / profile.rounds * 100) .. "%")
            or "-"

        local rows = {
            { "Kills",          profile.kills },
            { "Deaths",         profile.deaths },
            { "K/D",            kd },
            { "Round wins",     profile.wins .. " / " .. profile.rounds .. "  (" .. wr .. ")" },
            { "Point captures", profile.caps },
            { "Flags delivered", profile.flags },
            { "Team kills",     profile.teamkills },
        }

        local y = 140
        for _, row in ipairs(rows) do
            draw.SimpleText(row[1], "DermaDefaultBold", 20, y, COL.textDim, TEXT_ALIGN_LEFT)
            draw.SimpleText(tostring(row[2]), "DermaDefaultBold", w - 20, y, COL.text, TEXT_ALIGN_RIGHT)
            y = y + 28
        end

        draw.SimpleText("Rating: kills (+value of what you killed), captures,",
            "DermaDefault", 20, h - 44, COL.textDim, TEXT_ALIGN_LEFT)
        draw.SimpleText("flag runs and round wins. Deaths and teamkills cost you.",
            "DermaDefault", 20, h - 28, COL.textDim, TEXT_ALIGN_LEFT)
    end

    -- ── Right: leaderboard over the rank ladder ──────────────────────────
    local rightX = pad + 430 + 16
    local rightW = W - pad * 2 - 430 - 16
    local topH   = 260                          -- leaderboard height
    local ladderY = 84 + topH + 12
    local ladderH = (84 + (H - 84 - 76)) - ladderY

    local right = vgui.Create("DPanel", frame)
    right:SetPos(rightX, 84)
    right:SetSize(rightW, topH)
    right.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, COL.panel)
        draw.SimpleText("SERVER TOP 10", "DermaDefaultBold", 16, 14, COL.accent, TEXT_ALIGN_LEFT)

        if not profile then return end

        local y = 44
        for i, e in ipairs(profile.top) do
            local rank = TPG.GetRank(e.rating)
            draw.SimpleText("#" .. i, "DermaDefaultBold", 16, y, COL.textDim, TEXT_ALIGN_LEFT)
            draw.SimpleText(e.name, "DermaDefaultBold", 44, y, COL.text, TEXT_ALIGN_LEFT)
            draw.SimpleText(e.rating .. "  " .. rank.name, "DermaDefault", w - 14, y + 1,
                rank.color, TEXT_ALIGN_RIGHT)
            y = y + 26
            if y > h - 20 then break end
        end
    end

    -- ── Right, lower: this server's rank ladder ──────────────────────────
    local ladder = vgui.Create("DPanel", frame)
    ladder:SetPos(rightX, ladderY)
    ladder:SetSize(rightW, ladderH)
    ladder.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, COL.panel)
        draw.SimpleText("RANK LADDER", "DermaDefaultBold", 16, 12, COL.accent, TEXT_ALIGN_LEFT)
    end

    local scroll = vgui.Create("DScrollPanel", ladder)
    scroll:SetPos(10, 34)
    scroll:SetSize(rightW - 20, ladderH - 44)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    function sbar:Paint(w, h) draw.RoundedBox(3, 0, 0, w, h, COL.bg) end
    function sbar.btnGrip:Paint(w, h) draw.RoundedBox(3, 0, 0, w, h, COL.line) end
    sbar.btnUp.Paint, sbar.btnDown.Paint = function() end, function() end

    -- Highest tier at the top, so the ladder reads as something above you.
    -- Each row resolves "is this mine?" in its own Paint instead of being told
    -- at build time: the profile reply can land after this panel exists.
    local rows = {}
    for i = #TPG.Ranks, 1, -1 do
        local entry = TPG.Ranks[i]

        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:DockMargin(0, 0, 6, 4)
        row:SetTall(24)
        row.Paint = function(_, w, h)
            local mine = profile ~= nil and select(2, TPG.GetRank(profile.rating)) == i
            draw.RoundedBox(4, 0, 0, w, h, mine and COL.panelHi or COL.bg)
            if mine then
                surface.SetDrawColor(entry.color)
                surface.DrawRect(0, 0, 3, h)
            end
            draw.SimpleText(entry.name, "DermaDefault", 10, h / 2, entry.color,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(entry.min, "DermaDefault", w - 8, h / 2,
                mine and COL.text or COL.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        rows[i] = row
    end

    -- Scroll to the player's own tier the first frame there is a rating to
    -- place them by, which may be this frame (cached) or several later.
    local placed = false
    frame.Think = function()
        if placed or not profile then return end
        placed = true

        local _, idx = TPG.GetRank(profile.rating)
        local row = rows[idx]
        if not IsValid(row) then return end

        scroll:InvalidateLayout(true)
        scroll:ScrollToChild(row)
    end

    -- ── Bottom: manual shortcut ──────────────────────────────────────────
    local manual = vgui.Create("DButton", frame)
    manual:SetText("")
    manual:SetPos(pad, H - 60)
    manual:SetSize(W - pad * 2, 40)
    manual.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and COL.line or COL.panelHi)
        draw.SimpleText("FIELD MANUAL - how everything works", "DermaDefaultBold",
            w / 2, h / 2, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    manual.DoClick = function()
        frame:Close()
        RunConsoleCommand("tpg_menu_manual")
    end
end

concommand.Add("tpg_menu_profile", OpenProfile)
