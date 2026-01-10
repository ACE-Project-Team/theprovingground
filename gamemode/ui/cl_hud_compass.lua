--[[
    Compass HUD Element
]]

local compassDirections = {
    { angle = 0,   label = "N" },
    { angle = 45,  label = "NE" },
    { angle = 90,  label = "E" },
    { angle = 135, label = "SE" },
    { angle = 180, label = "S" },
    { angle = 225, label = "SW" },
    { angle = 270, label = "W" },
    { angle = 315, label = "NW" },
}

hook.Add("HUDPaint", "TPG_Compass", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local sw = ScrW()
    local yaw = ply:EyeAngles().y
    
    -- Normalize to 0-360
    local lookAngle = (yaw + 180) % 360
    
    -- Draw compass directions
    for _, dir in ipairs(compassDirections) do
        local diff = dir.angle - lookAngle
        
        -- Wrap around
        if diff > 180 then diff = diff - 360 end
        if diff < -180 then diff = diff + 360 end
        
        -- Only show if within view
        if math.abs(diff) < 50 then
            local xPos = sw / 2 + diff * 7.3
            draw.SimpleText(dir.label, "CloseCaption_Normal", xPos, 60, Color(255, 255, 0), TEXT_ALIGN_CENTER)
        end
    end
    
    -- Bearing number
    draw.SimpleText(tostring(math.floor(lookAngle)), "CloseCaption_Normal", sw / 2, 80, Color(255, 255, 0), TEXT_ALIGN_CENTER)
end)