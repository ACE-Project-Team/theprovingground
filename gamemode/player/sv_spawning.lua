--[[
    Player Spawning
]]

function GM:PlayerSpawn(ply)
    self.BaseClass:PlayerSpawn(ply)
    
    local teamId = ply:Team()
    
    if TPG.Util.IsOnTeam(ply) then
        -- Set spawn position
        local spawnPos = TPG.State.spawns[teamId]
        if spawnPos then
            ply:SetPos(spawnPos)
        end
        
        -- Apply team colors
        local teamData = TPG.GetTeamData(teamId)
        ply:SetPlayerColor(teamData.vector)
        ply:SetWeaponColor(teamData.vector)
        
        -- Enable spawn protection
        local pState = TPG.State.GetPlayer(ply)
        pState.spawnProtection = TPG.Config.spawnProtectionTime
        ply:GodEnable()
    end
    
    -- Apply loadout
    TPG.Loadout.Apply(ply)
end

function GM:PlayerSetModel(ply)
    local armorId = TPG.Util.GetPData(ply, "Armor", 1)
    local model = TPG.GetArmorModel(armorId)
    ply:SetModel(model)
end

-- Initial spawn
hook.Add("PlayerInitialSpawn", "TPG_InitialSpawn", function(ply)
    -- Auto-assign to team
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)
    
    if greenCount < redCount then
        ply:SetTeam(TEAM_GREEN)
    elseif redCount < greenCount then
        ply:SetTeam(TEAM_RED)
    else
        ply:SetTeam(TEAM_UNASSIGNED)
        ply:ConCommand("tpg_menu_team")
    end
    
    TPG.Util.ChatMessage(ply, "[TPG] Press F2 for teams, F3 for loadout, F4 to enter vehicle.", Color(0, 255, 0))
    TPG.Util.PlaySound(ply, "garrysmod/save_load1.wav")
end)