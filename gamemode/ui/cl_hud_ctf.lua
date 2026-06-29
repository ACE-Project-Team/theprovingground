--[[
    CTF status HUD. Shows the single neutral flag's state (neutral / held by a
    team / dropped), only during a Capture the Flag round. Top-centre, under the
    score bar.
]]

local flagCache, lastCache = nil, 0

local function UpdateCache()
    if CurTime() - lastCache < 0.5 then return end
    lastCache = CurTime()
    flagCache = ents.FindByClass("tpg_flag")[1]
end

hook.Add("HUDPaint", "TPG_CTFHUD", function()
    if TPG.UI.State.gameType ~= GAMEMODE_CTF then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    UpdateCache()
    local flag = flagCache
    if not IsValid(flag) then return end

    local state = flag:GetFlagState()
    local status, sCol
    if state == flag.STATE_HOME then
        status, sCol = "NEUTRAL", Color(200, 200, 200)
    elseif state == flag.STATE_CARRIED then
        local td = TPG.GetTeamData(flag:GetPossessTeam())
        local c  = flag:GetCarrier()
        status = "HELD BY " .. (td and string.upper(td.name) or "?") ..
            (IsValid(c) and ("  (" .. c:Nick() .. ")") or "")
        sCol = (td and td.color) or Color(255, 200, 80)
    else
        status, sCol = "DROPPED", Color(255, 200, 80)
    end

    local sw = ScrW()
    local w, h = 360, 50
    local x, y = sw / 2 - w / 2, 118

    draw.RoundedBox(6, x, y, w, h, Color(0, 0, 0, 160))
    draw.SimpleText("CAPTURE THE FLAG", "DermaDefaultBold", x + w / 2, y + 14,
        Color(245, 245, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(status, "DermaDefaultBold", x + w / 2, y + 34,
        sCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
