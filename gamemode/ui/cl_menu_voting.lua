--[[--
    Map vote menu: a card per candidate, opened automatically at the end of a
    round or after a successful Rock the Vote.

    Exports nothing; `OpenLoadoutMenu`'s sibling here is `OpenMapVoteMenu`,
    bound to the `tpg_menu_mapvote` concommand that `tpg.voting`'s
    `StartMapVote` runs on every client (see `TPG.State.voting` in
    `gamemode/voting/sv_voting.lua`). Reads candidate data from
    `TPG.UI.State.mapVote` (populated by the `TPG_SyncMapVote` net message in
    `cl_hud.lua`) and live counts from `TPG.UI.State.voteTally`
    (`TPG_SyncVoteTally`) -- both are pushed by the server, this file never
    computes a tally itself. Each card shows a preview image loaded from
    `materials/maps/<mapname>.png`, falling back to a "No Preview" placeholder
    when that material doesn't exist or fails to load.

    Clicking a card runs the `tpg_votemap <index>` concommand, which the
    server resolves via `TPG.Voting.CastMapVote` -- the click sends only the
    card's position in the candidate list, not the map name, so a stale or
    reordered `TPG.UI.State.mapVote` would vote for the wrong map without any
    error. A "stay on this map" card rides at the end as index 0. Voting marks
    the chosen card and closes the menu a moment later, so the player sees
    their pick land and then gets the game back; the close button is there for
    anyone who would rather not vote at all. While the vote is still live the
    menu reopens through `tpg_rtv` (F2 menu button or `!rtv` in chat), which
    also lets a player change their pick. The menu refuses to open once
    `TPG.UI.State.voteEnd` has passed.

    @module tpg.menu.voting
    @realm client
]]

local CATEGORY_NAMES = { [0] = "Map", [1] = "Open Map", [2] = "Urban Map", [3] = "Bonus Map" }

local function OpenMapVoteMenu()
    local maps = TPG.UI.State.mapVote or {}
    if #maps == 0 then return end
    -- The candidate list stays cached after the window closes, so without
    -- this check a late `tpg_menu_mapvote` would reopen a dead vote.
    if CurTime() >= (TPG.UI.State.voteEnd or 0) then return end

    local cardW, cardH, pad = 230, 300, 12
    local count = #maps + 1 -- the "stay on this map" card rides at the end
    local frameW = math.min(count * cardW + (count + 1) * pad, ScrW() - 40)
    local frameH = cardH + 96

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetPos((ScrW() - frameW) / 2, ScrH() / 2 - frameH / 2)
    frame:SetTitle("Vote for Next Map")
    frame:SetDraggable(false)
    -- Voting used to be a mouse trap: no close button, and the only exit was
    -- the auto-close three seconds after the vote ended. A player who had
    -- already voted sat behind a popup for the rest of the countdown.
    frame:ShowCloseButton(true)
    frame:MakePopup()

    -- Which card this player picked, so the click has visible feedback in the
    -- moment before the menu goes away.
    local voted = nil

    -- Countdown bar (bottom)
    local bar = vgui.Create("DPanel", frame)
    bar:Dock(BOTTOM)
    bar:DockMargin(pad, 4, pad, 8)
    bar:SetTall(18)
    bar.Paint = function(_, w, h)
        local total = (TPG.Config and TPG.Config.mapVoteTime) or 20
        local remain = math.max((TPG.UI.State.voteEnd or CurTime()) - CurTime(), 0)
        local frac = math.Clamp(remain / total, 0, 1)
        draw.RoundedBox(3, 0, 0, w, h, Color(0, 0, 0, 160))
        draw.RoundedBox(3, 0, 0, w * frac, h, Color(80, 200, 80))
        draw.SimpleText(math.ceil(remain) .. "s", "DermaDefaultBold", w / 2, h / 2,
            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local canvas = vgui.Create("DPanel", frame)
    canvas:Dock(FILL)
    canvas:DockMargin(pad, 4, pad, 0)
    canvas.Paint = function() end

    for i, m in ipairs(maps) do
        local mat = Material("maps/" .. m.map .. ".png")
        local hasImg = mat and not mat:IsError()

        local card = vgui.Create("DButton", canvas)
        card:SetText("")
        card:SetSize(cardW, cardH)
        card:SetPos((i - 1) * (cardW + pad), 0)

        card.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, voted == i and Color(30, 45, 32) or Color(25, 25, 30, 255))
            if voted == i then
                surface.SetDrawColor(120, 230, 120)
                surface.DrawOutlinedRect(0, 0, w, h, 2)
            end

            -- Preview image
            if hasImg then
                surface.SetDrawColor(255, 255, 255)
                surface.SetMaterial(mat)
                surface.DrawTexturedRect(6, 6, w - 12, 120)
            else
                draw.RoundedBox(4, 6, 6, w - 12, 120, Color(50, 50, 60))
                draw.SimpleText("No Preview", "DermaDefault", w / 2, 66,
                    Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            draw.SimpleText(CATEGORY_NAMES[m.category] or "Map", "DermaDefault", 10, 132, Color(255, 220, 80))
            draw.SimpleText(m.displayName, "DermaDefaultBold", 10, 148, color_white)

            -- Budgets
            local y = 176
            local function stat(label, value)
                draw.SimpleText(label, "DermaDefault", 12, y, Color(170, 170, 170))
                draw.SimpleText(value, "DermaDefaultBold", w - 12, y, color_white, TEXT_ALIGN_RIGHT)
                y = y + 18
            end
            stat("Point budget", string.Comma(m.points))
            stat("Weight cap", m.weight .. "t")
            stat("Prop cap", tostring(m.props))
            stat("Objectives", tostring(m.objectives))

            -- Live votes
            local votes = (TPG.UI.State.voteTally or {})[i] or 0
            draw.RoundedBox(4, 6, h - 36, w - 12, 28, voted == i and Color(50, 80, 50) or Color(40, 40, 50))
            draw.SimpleText(voted == i and ("Your vote - " .. votes) or ("Votes: " .. votes),
                "DermaDefaultBold", w / 2, h - 22,
                Color(120, 230, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        card.DoClick = function()
            if voted then return end
            voted = i

            LocalPlayer():EmitSound("common/weapon_select.wav")
            RunConsoleCommand("tpg_votemap", i)

            -- Long enough for the marked card to register as feedback, short
            -- enough that nobody feels held there. The tally is broadcast to
            -- everyone anyway, so there is nothing left to watch here.
            timer.Simple(0.4, function()
                if IsValid(frame) then frame:Close() end
            end)
        end
    end

    -- "Stay" card: index 0 on the wire, same feedback shape as a map card but
    -- no preview or budgets - it just keeps the current map.
    local stay = vgui.Create("DButton", canvas)
    stay:SetText("")
    stay:SetSize(cardW, cardH)
    stay:SetPos(#maps * (cardW + pad), 0)

    stay.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, voted == 0 and Color(30, 45, 32) or Color(25, 25, 30, 255))
        if voted == 0 then
            surface.SetDrawColor(120, 230, 120)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end

        draw.RoundedBox(4, 6, 6, w - 12, 120, Color(40, 45, 40))
        draw.SimpleText("STAY", "DermaLarge", w / 2, 66,
            Color(160, 220, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("Keep", "DermaDefault", 10, 132, Color(255, 220, 80))
        draw.SimpleText(game.GetMap(), "DermaDefaultBold", 10, 148, color_white)
        draw.SimpleText("Same map, same layout,", "DermaDefault", 10, 176, Color(170, 170, 170))
        draw.SimpleText("no changelevel.", "DermaDefault", 10, 194, Color(170, 170, 170))

        local votes = (TPG.UI.State.voteTally or {})[0] or 0
        draw.RoundedBox(4, 6, h - 36, w - 12, 28, voted == 0 and Color(50, 80, 50) or Color(40, 40, 50))
        draw.SimpleText(voted == 0 and ("Your vote - " .. votes) or ("Votes: " .. votes),
            "DermaDefaultBold", w / 2, h - 22,
            Color(120, 230, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    stay.DoClick = function()
        if voted then return end
        voted = 0

        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_votemap", 0)

        timer.Simple(0.4, function()
            if IsValid(frame) then frame:Close() end
        end)
    end

end

concommand.Add("tpg_menu_mapvote", OpenMapVoteMenu)
