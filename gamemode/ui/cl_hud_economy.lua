--[[--
    Per-player economy HUD (BETA): the local player's wallet and a floating
    feed of what changed it and why.

    Only draws while the global bool `TPG_EconomyActive` is true, and sits just
    under the team stats box (top-right), anchored to
    `TPG.UI.ComputeLayout()`'s `sideY + sideH` rather than a hardcoded y so it
    never overlaps that box regardless of whether it's showing the ACE-points
    row. Reads the wallet balance straight off the local player's networked
    `TPG_Money` int.

    Every wallet change the server reports over the `TPG_MoneyDelta` net
    message (sent by `systems/sv_economy.lua`) floats a small labelled +N / -N
    popup off the budget box (kill, income, point hold, vehicle, team kill),
    so a player can see exactly what moved their budget and why. Popups are
    capped at 6 in flight (`while #popups > 6 do popups[#popups] = nil end`,
    dropping the OLDEST) and each lives `POPUP_LIFE` (2.2s) with an ease-out
    fade and upward drift; an unrecognised reason code falls back to the raw
    code as its label and a colour chosen only from the delta's sign.

    Exports nothing.

    @module tpg.hud.economy
    @realm client
]]

-- Friendly label + colour per reason code (sent by systems/sv_economy.lua).
local REASONS = {
    kill     = { "kill",       Color(120, 230, 120) },
    income   = { "income",     Color(120, 230, 120) },
    hold     = { "point hold", Color(150, 235, 150) },
    passive  = { "income",     Color(120, 230, 120) },
    vehicle  = { "vehicle",    Color(255, 120, 120) },
    purchase = { "purchase",   Color(255, 120, 120) },
    teamkill = { "team kill",  Color(255, 120, 120) },
}

local POPUP_LIFE = 2.2   -- seconds each popup lives (rise + fade)
local popups = {}        -- { amount, label, color, born }

net.Receive("TPG_MoneyDelta", function()
    local delta  = net.ReadInt(20)
    local reason = net.ReadString()
    if delta == 0 then return end

    local info  = REASONS[reason]
    local label = info and info[1] or reason
    local color = info and info[2] or (delta > 0 and Color(120, 230, 120) or Color(255, 120, 120))

    table.insert(popups, 1, { amount = delta, label = label, color = color, born = CurTime() })
    -- Cap the stack so a burst can't pile up forever.
    while #popups > 6 do popups[#popups] = nil end
end)

hook.Add("HUDPaint", "TPG_EconomyHUD", function()
    if not GetGlobalBool("TPG_EconomyActive", false) then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local money = ply:GetNWInt("TPG_Money", 0)
    local C     = TPG.Colors
    local S     = TPG.UI.S
    local L     = TPG.UI.ComputeLayout()
    local sw    = ScrW()

    -- Anchored to the team stats box rather than to y=113: that constant assumed
    -- the box's 1080p height AND that it always shows the ACE points row, so the
    -- two overlapped whenever either changed.
    local w, h = L.sideW, S(46)
    local x, y = sw - w - L.margin, L.sideY + L.sideH + S(6)

    TPG.UI.Panel(x, y, w, h, C.Good)
    -- Header makes clear this is a PERSONAL budget (per-player economy mode),
    -- distinct from the shared team point budget shown in the box above.
    draw.SimpleText("PER-PLAYER ECONOMY", "TPG.HUD.Small",
        x + S(12), y + S(7), C.Good, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText("Your Budget: " .. money .. " pts", "TPG.HUD.Label",
        x + S(12), y + S(23), C.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- Floating +N / -N popups, drawn to the LEFT of the box so they don't cover
    -- the running total. Newest sits at the box, older ones drift up and fade.
    local now     = CurTime()
    local popupX  = x - 10
    local baseY   = y + 22
    for i = #popups, 1, -1 do
        local p   = popups[i]
        local age = now - p.born
        if age >= POPUP_LIFE then
            table.remove(popups, i)
        else
            local frac  = age / POPUP_LIFE
            local alpha = 255 * (1 - frac * frac)              -- ease-out fade
            local rise  = 26 * frac                            -- drift upward
            local stack = (i - 1) * 16                         -- separate entries
            local txt   = (p.amount > 0 and "+" or "") .. p.amount .. "  " .. p.label
            local col   = Color(p.color.r, p.color.g, p.color.b, alpha)

            draw.SimpleText(txt, "DermaDefaultBold", popupX, baseY - rise - stack,
                Color(0, 0, 0, alpha * 0.6), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(txt, "DermaDefaultBold", popupX - 1, baseY - rise - stack - 1,
                col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end)
