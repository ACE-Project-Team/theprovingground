--[[
    Economy HUD (BETA)
    Shows the local player's wallet, only while the per-player economy is active.
    Sits just under the team stats box (top-right).
]]

hook.Add("HUDPaint", "TPG_EconomyHUD", function()
    if not GetGlobalBool("TPG_EconomyActive", false) then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local money  = ply:GetNWInt("TPG_Money", 0)
    local sw      = ScrW()
    local w, h    = 245, 34
    local x, y    = sw - 257, 90  -- directly below the team stats box

    draw.RoundedBox(5, x, y, w, h, Color(0, 0, 0, 150))
    draw.SimpleText("Points: " .. money, "DermaDefaultBold",
        x + 12, y + h / 2, Color(120, 230, 120),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
