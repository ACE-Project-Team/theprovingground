--[[
    Map Vote Menu
]]

local function OpenMapVoteMenu()
    local maps = TPG.UI.State.mapVote
    
    if #maps == 0 then
        maps = {"Map 1", "Map 2", "Map 3", "Map 4"}
    end
    
    local frame = vgui.Create("DFrame")
    frame:SetSize(220, 400)
    frame:SetPos(30, ScrH() / 2 - 200)
    frame:SetTitle("Vote for Next Map")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    
    local yPos = 40
    local categories = {"Open Map", "Open Map", "Urban Map", "Bonus Map"}
    
    for i, mapName in ipairs(maps) do
        local label = vgui.Create("DLabel", frame)
        label:SetPos(40, yPos)
        label:SetText(categories[i] or "Map")
        label:SizeToContents()
        
        yPos = yPos + 20
        
        local btn = vgui.Create("DButton", frame)
        btn:SetPos(30, yPos)
        btn:SetSize(160, 50)
        btn:SetText(mapName)
        btn.DoClick = function()
            LocalPlayer():EmitSound("common/weapon_select.wav")
            RunConsoleCommand("tpg_votemap", i)
            frame:Close()
        end
        
        yPos = yPos + 70
    end
end

concommand.Add("tpg_menu_mapvote", OpenMapVoteMenu)