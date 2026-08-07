--[[--
    Maps a few default GMod key binds onto TPG's own menus.

    Exports nothing; it is a single `PlayerBindPress` hook. `gm_showteam`,
    `gm_showspare1` and `gm_showspare2` are the sandbox-gamemode binds for the
    default F2/F3/F4 keys (rebindable under Options > Keyboard), repointed here
    at the team menu, the loadout menu and easy-entry respectively. Returning
    `true` from the hook suppresses GMod's own handling of that bind, which is
    what stops the default spawn menus these binds normally open.

    @module tpg.binds
    @realm client
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