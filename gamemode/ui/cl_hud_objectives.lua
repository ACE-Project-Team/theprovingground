--[[
    Objective Markers
]]

local objectiveCache = {}
local lastUpdate = 0

-- Get contrasting text color based on background
local function GetContrastColor(bgColor)
    -- Calculate luminance
    local luminance = (0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b) / 255
    
    -- If light background, use dark text; if dark, use white
    if luminance > 0.5 then
        return Color(0, 0, 0)  -- Black text
    else
        return Color(255, 255, 255)  -- White text
    end
end

hook.Add("HUDPaint", "TPG_ObjectiveMarkers", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    -- Update cache periodically
    if CurTime() - lastUpdate > 0.5 then
        objectiveCache = ents.FindByClass("tpg_controlpoint")
        lastUpdate = CurTime()
    end
    
    for i, obj in ipairs(objectiveCache) do
        if not IsValid(obj) then continue end
        
        local pos = obj:GetPos() + obj:OBBCenter() + Vector(0, 0, 100)
        local screenPos = pos:ToScreen()
        
        if not screenPos.visible then continue end
        
        -- Get networked data
        local pointName = obj:GetNWString("PointName", "Point " .. i)
        local pointColor = obj:GetColor()
        local textColor = GetContrastColor(pointColor)
        
        -- Draw marker circle with outline
        draw.RoundedBox(10, screenPos.x - 8, screenPos.y - 8, 18, 18, Color(0, 0, 0, 200))  -- Outline
        draw.RoundedBox(10, screenPos.x - 6, screenPos.y - 6, 14, 14, pointColor)
        
        -- Draw point name with shadow
        draw.SimpleText(pointName, "DermaDefaultBold", screenPos.x + 1, screenPos.y - 19, Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(pointName, "DermaDefaultBold", screenPos.x, screenPos.y - 20, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Draw capture progress bar
        local capProgress = obj:GetNWFloat("CapProgress", 0)
        local capOwnership = obj:GetNWInt("CapOwnership", 0)
        
        if capOwnership == 0 and math.abs(capProgress) > 0.5 then
            local barWidth = 50
            local barHeight = 6
            local capTimeNeutral = TPG.Config.capTimeNeutral or 10
            local progress = math.abs(capProgress) / capTimeNeutral
            progress = math.Clamp(progress, 0, 1)
            
            local barX = screenPos.x - barWidth / 2
            local barY = screenPos.y + 15
            
            -- Background
            draw.RoundedBox(2, barX - 1, barY - 1, barWidth + 2, barHeight + 2, Color(0, 0, 0, 200))
            draw.RoundedBox(2, barX, barY, barWidth, barHeight, Color(50, 50, 50, 200))
            
            -- Progress fill
            local fillColor = capProgress > 0 and Color(0, 255, 0) or Color(255, 0, 0)
            draw.RoundedBox(2, barX, barY, barWidth * progress, barHeight, fillColor)
        end
    end
end)