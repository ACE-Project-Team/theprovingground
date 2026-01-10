--[[
    Team Assignment and Autobalance
]]

TPG.PlayerTeams = TPG.PlayerTeams or {}

function TPG.PlayerTeams.AssignPlayer(ply, teamId)
    local currentTeam = ply:Team()
    
    -- Check balance
    if not TPG.PlayerTeams.CanJoin(ply, teamId) then
        TPG.Util.ChatMessage(ply, "[TPG] Teams cannot be unbalanced.", Color(255, 0, 0))
        return false
    end
    
    -- Set team
    ply:SetTeam(teamId)
    
    -- Respawn
    ply:Spawn()
    
    -- Notify
    local teamData = TPG.GetTeamData(teamId)
    TPG.Util.ChatMessage(ply, "You have joined " .. teamData.name, Color(0, 255, 255))
    
    print("[TPG] " .. ply:Nick() .. " joined " .. teamData.name)
    
    return true
end

function TPG.PlayerTeams.CanJoin(ply, targetTeam)
    if targetTeam == TEAM_UNASSIGNED then return true end
    
    local currentTeam = ply:Team()
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)
    
    -- Adjust for player leaving their current team
    if currentTeam == TEAM_GREEN then
        greenCount = greenCount - 1
    elseif currentTeam == TEAM_RED then
        redCount = redCount - 1
    end
    
    -- Check if joining would unbalance
    if targetTeam == TEAM_GREEN and greenCount > redCount then
        return false
    elseif targetTeam == TEAM_RED and redCount > greenCount then
        return false
    end
    
    return true
end

function TPG.PlayerTeams.Autobalance(ply)
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)
    local currentTeam = ply:Team()
    
    -- Check if autobalance needed
    if currentTeam == TEAM_GREEN and greenCount > redCount + 1 then
        ply:SetTeam(TEAM_RED)
        ply:Spawn()
        TPG.Util.ChatMessage(ply, "[TPG] You have been autobalanced.", Color(255, 255, 0))
        return true
    elseif currentTeam == TEAM_RED and redCount > greenCount + 1 then
        ply:SetTeam(TEAM_GREEN)
        ply:Spawn()
        TPG.Util.ChatMessage(ply, "[TPG] You have been autobalanced.", Color(255, 255, 0))
        return true
    end
    
    return false
end

function TPG.PlayerTeams.ScrambleAll()
    -- Put everyone unassigned first
    for _, ply in ipairs(player.GetAll()) do
        ply:SetTeam(TEAM_UNASSIGNED)
    end
    
    -- Reassign randomly but balanced
    local players = player.GetAll()
    
    for _, ply in ipairs(players) do
        local greenCount = team.NumPlayers(TEAM_GREEN)
        local redCount = team.NumPlayers(TEAM_RED)
        
        if greenCount <= redCount then
            ply:SetTeam(TEAM_GREEN)
        else
            ply:SetTeam(TEAM_RED)
        end
        
        ply:Spawn()
    end
    
    TPG.Util.ChatBroadcast("[TPG] Teams have been scrambled!", Color(255, 255, 0))
end

-- Check for autobalance on death
hook.Add("PlayerDeath", "TPG_DeathAutobalance", function(victim, inflictor, attacker)
    timer.Simple(0.1, function()
        if IsValid(victim) then
            TPG.PlayerTeams.Autobalance(victim)
        end
    end)
end)