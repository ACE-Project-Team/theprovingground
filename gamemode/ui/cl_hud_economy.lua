--[[
    Economy HUD (BETA)
    Shows the local player's wallet, only while the per-player economy is active.
    Sits just under the team stats box (top-right).

    Every wallet change the server reports over TPG_MoneyDelta floats a small
    labelled +N / -N popup off the budget box (kill, income, point hold, vehicle,
    team kill), so you can see exactly what moved your budget and why.
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
    local sw    = ScrW()
    local w, h  = 245, 46
    -- The team stats box spans y=12..107; sit a few px below it so the two
    -- boxes don't overlap.
    local x, y  = sw - 257, 113

    draw.RoundedBox(5, x, y, w, h, Color(0, 0, 0, 150))
    -- Header makes clear this is a PERSONAL budget (per-player economy mode),
    -- distinct from the shared team point budget shown in the box above.
    draw.SimpleText("PER-PLAYER ECONOMY", "DermaDefault",
        x + 12, y + 6, Color(120, 230, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText("Your Budget: " .. money .. " pts", "DermaDefaultBold",
        x + 12, y + 20, Color(255, 255, 255),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

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
