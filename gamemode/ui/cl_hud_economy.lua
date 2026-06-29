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
    local w, h    = 245, 46
    -- The team stats box spans y=12..107; sit a few px below it so the two
    -- boxes don't overlap.
    local x, y    = sw - 257, 113

    draw.RoundedBox(5, x, y, w, h, Color(0, 0, 0, 150))
    -- Header makes clear this is a PERSONAL budget (per-player economy mode),
    -- distinct from the shared team point budget shown in the box above.
    draw.SimpleText("PER-PLAYER ECONOMY", "DermaDefault",
        x + 12, y + 6, Color(120, 230, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText("Your Budget: " .. money .. " pts", "DermaDefaultBold",
        x + 12, y + 20, Color(255, 255, 255),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end)
