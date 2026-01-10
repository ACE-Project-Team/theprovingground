--[[
    Team Selection Menu
]]

local function OpenTeamMenu()
    local frame = vgui.Create("DFrame")
    frame:SetSize(600, 300)
    frame:Center()
    frame:SetTitle("Select Team")
    frame:SetDraggable(false)
    frame:ShowCloseButton(true)
    frame:MakePopup()
    
    -- Green team button
    local greenBtn = vgui.Create("DButton", frame)
    greenBtn:SetPos(50, 60)
    greenBtn:SetSize(150, 100)
    greenBtn:SetText("The Green Terror")
    greenBtn:SetTextColor(Color(0, 180, 0))
    greenBtn.DoClick = function()
        LocalPlayer():EmitSound("doors/doorstop1.wav")
        RunConsoleCommand("tpg_team", TEAM_GREEN)
        frame:Close()
    end
    
    -- Red team button
    local redBtn = vgui.Create("DButton", frame)
    redBtn:SetPos(400, 60)
    redBtn:SetSize(150, 100)
    redBtn:SetText("The Red Menace")
    redBtn:SetTextColor(Color(255, 0, 0))
    redBtn.DoClick = function()
        LocalPlayer():EmitSound("doors/doorstop1.wav")
        RunConsoleCommand("tpg_team", TEAM_RED)
        frame:Close()
    end
    
    -- Unassigned button
    local unassignedBtn = vgui.Create("DButton", frame)
    unassignedBtn:SetPos(225, 60)
    unassignedBtn:SetSize(150, 100)
    unassignedBtn:SetText("Spectate")
    unassignedBtn.DoClick = function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_team", TEAM_UNASSIGNED)
        frame:Close()
    end
    
    -- RTV button
    local rtvBtn = vgui.Create("DButton", frame)
    rtvBtn:SetPos(80, 200)
    rtvBtn:SetSize(180, 50)
    rtvBtn:SetText("Rock The Vote")
    rtvBtn.DoClick = function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_rtv")
        frame:Close()
    end
    
    -- Scramble button
    local scrambleBtn = vgui.Create("DButton", frame)
    scrambleBtn:SetPos(340, 200)
    scrambleBtn:SetSize(180, 50)
    scrambleBtn:SetText("Vote Scramble")
    scrambleBtn.DoClick = function()
        LocalPlayer():EmitSound("common/weapon_select.wav")
        RunConsoleCommand("tpg_scramble")
        frame:Close()
    end
end

concommand.Add("tpg_menu_team", OpenTeamMenu)