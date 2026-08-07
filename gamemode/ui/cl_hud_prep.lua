--[[--
    Preparation-period countdown banner.

    While the round's prep window is confining players to spawn
    (`core/sv_prep.lua` sets the global float `TPG_PrepEnd`), shows a centred
    countdown so everyone knows how long until they can move out. Exports
    nothing; a single `HUDPaint` hook that reads `GetGlobalFloat("TPG_PrepEnd",
    0)` directly rather than a net message, so it stays correct for a client
    that joins mid-prep with no extra sync step. Only draws for players
    actually on a team (`TPG.Util.IsOnTeam`), so spectators never see it.

    @module tpg.hud.prep
    @realm client
]]

hook.Add("HUDPaint", "TPG_PrepHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if not TPG.Util or not TPG.Util.IsOnTeam or not TPG.Util.IsOnTeam(ply) then return end

    local prepEnd = GetGlobalFloat("TPG_PrepEnd", 0)
    local remain  = prepEnd - CurTime()
    if remain <= 0 then return end

    local sw = ScrW()
    local w, h = 300, 60
    local x, y = sw / 2 - w / 2, ScrH() * 0.22

    draw.RoundedBox(8, x, y, w, h, Color(0, 0, 0, 170))
    draw.SimpleText("PREPARATION", "DermaLarge", x + w / 2, y + 20,
        Color(255, 200, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Stay in spawn - moving out in " .. math.ceil(remain) .. "s",
        "DermaDefaultBold", x + w / 2, y + 44,
        Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
