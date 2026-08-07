--[[--
    World-space markers over every `tpg_controlpoint` on the map, plus a
    capture-progress bar under any point actively being contested.

    Exports nothing; it is a single `HUDPaint` hook. Re-scans
    `ents.FindByClass("tpg_controlpoint")` on a 0.5s cache rather than every
    frame, and reads each point's networked `PointName`, `CapProgress` and
    `CapOwnership` (set by the entity's own `tpg_controlpoint/init.lua`) --
    this file has no server-side counterpart and does no capture math itself.
    The progress bar only draws while `CapOwnership == 0` (a point mid-flip
    from one team toward the other, or being pushed back to neutral) and
    `abs(CapProgress) > 0.5`, so a point sitting untouched at neutral shows no
    bar at all.

    This is distinct from the point PIPS drawn in `cl_hud.lua` (the small
    lettered boxes in the top-centre score stack) -- this file draws the
    in-world marker and name tag that floats over the point itself.

    @module tpg.hud.objectives
    @realm client
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