--[[
    Map Vote Menu

    Shows a card per candidate map: preview image, display name + category,
    point/weight/prop budgets and objective count, and a live vote tally with a
    countdown bar. Click a card to (re)cast your vote.
]]

local CATEGORY_NAMES = { [0] = "Map", [1] = "Open Map", [2] = "Urban Map", [3] = "Bonus Map" }

local function OpenMapVoteMenu()
    local maps = TPG.UI.State.mapVote or {}
    if #maps == 0 then return end

    local cardW, cardH, pad = 230, 300, 12
    local count = #maps
    local frameW = math.min(count * cardW + (count + 1) * pad, ScrW() - 40)
    local frameH = cardH + 96

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetPos((ScrW() - frameW) / 2, ScrH() / 2 - frameH / 2)
    frame:SetTitle("Vote for Next Map")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()

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
            draw.RoundedBox(6, 0, 0, w, h, Color(25, 25, 30, 255))

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
            draw.RoundedBox(4, 6, h - 36, w - 12, 28, Color(40, 40, 50))
            draw.SimpleText("Votes: " .. votes, "DermaDefaultBold", w / 2, h - 22,
                Color(120, 230, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        card.DoClick = function()
            LocalPlayer():EmitSound("common/weapon_select.wav")
            RunConsoleCommand("tpg_votemap", i)
        end
    end

    -- Auto-close shortly after the vote ends.
    frame.Think = function(self)
        if (TPG.UI.State.voteEnd or 0) > 0 and CurTime() > TPG.UI.State.voteEnd + 3 then
            self:Close()
        end
    end
end

concommand.Add("tpg_menu_mapvote", OpenMapVoteMenu)
