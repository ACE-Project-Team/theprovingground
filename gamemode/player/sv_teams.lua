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

-- Scramble by skill: snake-draft players over their persistent rating
-- (systems/sv_stats.lua) so both teams end up with comparable total skill,
-- instead of the old random shuffle. Spectators are left alone -- they chose
-- to watch (the old version force-drafted them onto teams).
function TPG.PlayerTeams.ScrambleAll()
    local pool = {}
    for _, ply in ipairs(player.GetAll()) do
        if TPG.Util.IsOnTeam(ply) then
            pool[#pool + 1] = ply
        end
    end

    if #pool == 0 then return end

    -- Best first; equal ratings get shuffled relative to each other so two
    -- scrambles in a row don't produce the identical split.
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    table.sort(pool, function(a, b)
        return (TPG.Stats and TPG.Stats.GetRating(a) or 1000)
             > (TPG.Stats and TPG.Stats.GetRating(b) or 1000)
    end)

    -- Snake draft: A B B A A B B A ... keeps the top players split evenly.
    local first = math.random() < 0.5 and TEAM_GREEN or TEAM_RED
    local second = TPG.GetEnemyTeam(first)
    local pattern = { first, second, second, first }

    for i, ply in ipairs(pool) do
        ply:SetTeam(pattern[(i - 1) % 4 + 1])
        ply:Spawn()
    end

    TPG.Util.ChatBroadcast("[TPG] Teams have been scrambled (balanced by rating)!", Color(255, 255, 0))
end

-- Check for autobalance on death
hook.Add("PlayerDeath", "TPG_DeathAutobalance", function(victim, inflictor, attacker)
    timer.Simple(0.1, function()
        if IsValid(victim) then
            TPG.PlayerTeams.Autobalance(victim)
        end
    end)
end)