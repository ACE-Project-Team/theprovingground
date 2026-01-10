--[[
    Objective Markers
]]

local objectiveCache = {}
local lastUpdate = 0

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
        
        -- Draw marker
        draw.RoundedBox(10, screenPos.x - 5, screenPos.y - 5, 13, 13, obj:GetColor())
        
        -- Draw name
        local name = obj.PointName or ("Point " .. i)
        draw.SimpleText(name, "Default", screenPos.x, screenPos.y - 15, color_white, TEXT_ALIGN_CENTER)
    end
end)