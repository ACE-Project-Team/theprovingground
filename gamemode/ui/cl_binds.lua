--[[
    Key Bindings
]]

hook.Add("PlayerBindPress", "TPG_Binds", function(ply, bind, pressed)
    if not pressed then return end
    
    if bind == "gm_showteam" then
        RunConsoleCommand("tpg_menu_team")
        return true
    end
    
    if bind == "gm_showspare1" then
        RunConsoleCommand("tpg_menu_loadout")
        return true
    end
    
    if bind == "gm_showspare2" then
        RunConsoleCommand("tpg_easyentry")
        return true
    end
end)