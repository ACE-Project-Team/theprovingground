--[[
    Main HUD
]]

TPG.UI = TPG.UI or {}
TPG.UI.State = {
    scores = { [TEAM_GREEN] = 300, [TEAM_RED] = 300 },
    limits = { [TEAM_GREEN] = {}, [TEAM_RED] = {} },
    maxLimits = { props = 300, weight = 100000, points = 100000 },  -- Default max limits
    gameType = GAMEMODE_CP,
    objectives = {},
    mapVote = {},
}

-- Receive state sync
net.Receive("TPG_SyncState", function()
    TPG.UI.State.gameType = net.ReadUInt(4)
    TPG.UI.State.scores[TEAM_GREEN] = net.ReadUInt(16)
    TPG.UI.State.scores[TEAM_RED] = net.ReadUInt(16)
end)

net.Receive("TPG_SyncScores", function()
    TPG.UI.State.scores[TEAM_GREEN] = net.ReadInt(16)
    TPG.UI.State.scores[TEAM_RED] = net.ReadInt(16)
end)

net.Receive("TPG_SyncLimits", function()
    -- Current usage
    TPG.UI.State.limits[TEAM_GREEN].props = net.ReadUInt(12)
    TPG.UI.State.limits[TEAM_RED].props = net.ReadUInt(12)
    TPG.UI.State.limits[TEAM_GREEN].weight = net.ReadUInt(13) * 500
    TPG.UI.State.limits[TEAM_RED].weight = net.ReadUInt(13) * 500
    TPG.UI.State.limits[TEAM_GREEN].points = net.ReadUInt(16)
    TPG.UI.State.limits[TEAM_RED].points = net.ReadUInt(16)
    
    -- Max limits
    TPG.UI.State.maxLimits.props = net.ReadUInt(12)
    TPG.UI.State.maxLimits.weight = net.ReadUInt(13) * 500
    TPG.UI.State.maxLimits.points = net.ReadUInt(20)
end)

net.Receive("TPG_SyncMapVote", function()
    local count = net.ReadUInt(4)
    TPG.UI.State.mapVote = {}
    for i = 1, count do
        TPG.UI.State.mapVote[i] = net.ReadString()
    end
end)

net.Receive("TPG_ChatMessage", function()
    local color = net.ReadColor()
    local message = net.ReadString()
    chat.AddText(color, message)
end)

-- Objective cache
local objectiveCache = {}
local lastCacheUpdate = 0

local function UpdateObjectiveCache()
    if CurTime() - lastCacheUpdate < 0.5 then return end
    lastCacheUpdate = CurTime()
    objectiveCache = ents.FindByClass("tpg_controlpoint")
end

-- Main HUD paint
hook.Add("HUDPaint", "TPG_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local teamId = ply:Team()
    local teamData = TPG.GetTeamData(teamId)
    local teamColor = teamData.color
    
    local limits = TPG.UI.State.limits[teamId] or {}
    local maxLimits = TPG.UI.State.maxLimits
    
    local sw, sh = ScrW(), ScrH()
    
    -- Game type indicator
    draw.RoundedBox(5, 20, 14, 100, 40, Color(0, 0, 0, 100))
    draw.SimpleText(
        TPG.GetGameTypeName(TPG.UI.State.gameType),
        "CloseCaption_Normal",
        70, 34,
        Color(255, 255, 0),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
    )
    
    -- Team stats box
    draw.RoundedBox(5, sw - 257, 12, 245, 95, Color(0, 0, 0, 100))
    draw.RoundedBox(5, sw - 250, 20, 230, 80, teamColor)
    
    draw.SimpleText(
        "Props: " .. (limits.props or 0) .. "/" .. maxLimits.props,
        "DermaDefaultBold",
        sw - 240, 30,
        color_white,
        TEXT_ALIGN_LEFT
    )
    draw.SimpleText(
        "Weight: " .. math.floor((limits.weight or 0) / 1000) .. "T/" .. math.floor(maxLimits.weight / 1000) .. "T",
        "DermaDefaultBold",
        sw - 240, 50,
        color_white,
        TEXT_ALIGN_LEFT
    )
    
    if TPG.Config.useACEPoints then
        draw.SimpleText(
            "Points: " .. (limits.points or 0) .. "/" .. maxLimits.points,
            "DermaDefaultBold",
            sw - 240, 70,
            color_white,
            TEXT_ALIGN_LEFT
        )
    end
    
    -- Score bar
    draw.RoundedBox(5, sw / 2 - 375, 10, 750, 100, Color(0, 0, 0, 100))
    
    local greenScore = TPG.UI.State.scores[TEAM_GREEN] or 300
    local redScore = TPG.UI.State.scores[TEAM_RED] or 300
    local maxScore = TPG.Config.startingTickets
    
    -- Green bar
    local greenWidth = math.max((greenScore / maxScore) * 365, 1)
    draw.RoundedBox(5, sw / 2 - 370, 15, greenWidth, 40, Color(0, 255, 0, 255))
    
    -- Red bar
    local redWidth = math.max((redScore / maxScore) * 365, 1)
    draw.RoundedBox(5, sw / 2 + 370 - redWidth, 15, redWidth, 40, Color(255, 0, 0, 255))
    
    -- Score text
    draw.SimpleText(tostring(math.floor(greenScore)), "DermaDefaultBold", sw / 2 - 200, 28, color_white)
    draw.SimpleText(tostring(math.floor(redScore)), "DermaDefaultBold", sw / 2 + 180, 28, color_white)
    
    -- Objective indicators
    UpdateObjectiveCache()
    
    local pointCount = #objectiveCache
    if pointCount > 0 then
        local startX = sw / 2 - (pointCount * 30) / 2
        
        for i, obj in ipairs(objectiveCache) do
            if IsValid(obj) then
                local pointColor = obj:GetColor()
                local pointName = obj:GetNWString("PointName", "?")
                local initial = string.upper(string.sub(pointName, 1, 1))
                
                local boxX = startX + ((i - 1) * 30) + 5
                local boxY = 115
                
                -- Calculate contrast color for text
                local luminance = (0.299 * pointColor.r + 0.587 * pointColor.g + 0.114 * pointColor.b) / 255
                local textColor = luminance > 0.5 and Color(0, 0, 0) or Color(255, 255, 255)
                
                -- Draw outline
                draw.RoundedBox(4, boxX - 1, boxY - 1, 22, 22, Color(0, 0, 0, 200))
                
                -- Draw colored box
                draw.RoundedBox(3, boxX, boxY, 20, 20, pointColor)
                
                -- Draw initial letter with proper contrast
                draw.SimpleText(initial, "DermaDefaultBold", boxX + 10, boxY + 10, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end
    
    -- Draw teammates
    TPG.UI.DrawTeammates(ply, teamId, teamColor)
end)

function TPG.UI.DrawTeammates(ply, teamId, teamColor)
    for _, teammate in ipairs(team.GetPlayers(teamId)) do
        if teammate == ply then continue end
        
        local pos = teammate:GetPos() + teammate:OBBCenter()
        local screenPos = pos:ToScreen()
        
        if screenPos.visible then
            surface.SetDrawColor(teamColor)
            surface.DrawRect(screenPos.x - 3, screenPos.y - 3, 6, 6)
            draw.SimpleText(teammate:Nick(), "Default", screenPos.x, screenPos.y + 10, color_white, TEXT_ALIGN_CENTER)
        end
    end
end

-- Hide default HUD elements
local hideElements = {
    ["CHudBattery"] = true,
}

hook.Add("HUDShouldDraw", "TPG_HideHUD", function(name)
    if hideElements[name] then return false end
end)