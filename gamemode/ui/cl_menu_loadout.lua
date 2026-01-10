--[[
    Loadout Selection Menu
]]

local function OpenLoadoutMenu()
    local frame = vgui.Create("DFrame")
    frame:SetSize(280, 380)
    frame:Center()
    frame:SetTitle("Loadout")
    frame:SetDraggable(false)
    frame:ShowCloseButton(true)
    frame:MakePopup()
    
    local yPos = 40
    
    -- Primary weapon
    local primaryCombo = vgui.Create("DComboBox", frame)
    primaryCombo:SetPos(50, yPos)
    primaryCombo:SetSize(180, 30)
    primaryCombo:SetValue("Primary Weapon")
    
    for _, wep in ipairs(TPG.GetWeaponList("Primary")) do
        primaryCombo:AddChoice(wep.name, wep.id)
    end
    
    primaryCombo.OnSelect = function(self, index, value, data)
        RunConsoleCommand("tpg_loadout", 1, data)
    end
    
    yPos = yPos + 50
    
    -- Secondary weapon
    local secondaryCombo = vgui.Create("DComboBox", frame)
    secondaryCombo:SetPos(50, yPos)
    secondaryCombo:SetSize(180, 30)
    secondaryCombo:SetValue("Secondary Weapon")
    
    for _, wep in ipairs(TPG.GetWeaponList("Secondary")) do
        secondaryCombo:AddChoice(wep.name, wep.id)
    end
    
    secondaryCombo.OnSelect = function(self, index, value, data)
        RunConsoleCommand("tpg_loadout", 2, data)
    end
    
    yPos = yPos + 50
    
    -- Special weapon
    local specialCombo = vgui.Create("DComboBox", frame)
    specialCombo:SetPos(50, yPos)
    specialCombo:SetSize(180, 30)
    specialCombo:SetValue("Special Weapon")
    
    for _, wep in ipairs(TPG.GetWeaponList("Special")) do
        specialCombo:AddChoice(wep.name, wep.id)
    end
    
    specialCombo.OnSelect = function(self, index, value, data)
        RunConsoleCommand("tpg_loadout", 3, data)
    end
    
    yPos = yPos + 50
    
    -- Armor
    local armorCombo = vgui.Create("DComboBox", frame)
    armorCombo:SetPos(50, yPos)
    armorCombo:SetSize(180, 30)
    armorCombo:SetValue("Armor")
    
    for _, armor in ipairs(TPG.GetArmorList()) do
        armorCombo:AddChoice(armor.name, armor.id)
    end
    
    armorCombo.OnSelect = function(self, index, value, data)
        if data == 4 then
            chat.AddText(Color(255, 0, 0), "[TPG] Warning: Juggernaut armor cannot use vehicle seats!")
        end
        RunConsoleCommand("tpg_loadout", 4, data)
    end
    
    yPos = yPos + 70
    
    -- Respawn button
    local respawnBtn = vgui.Create("DButton", frame)
    respawnBtn:SetPos(50, yPos)
    respawnBtn:SetSize(180, 50)
    respawnBtn:SetText("Respawn")
    respawnBtn.DoClick = function()
        LocalPlayer():EmitSound("common/wpn_hudoff.wav")
        RunConsoleCommand("kill")
        frame:Close()
    end
end

concommand.Add("tpg_menu_loadout", OpenLoadoutMenu)