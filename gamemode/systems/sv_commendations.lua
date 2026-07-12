--[[
    End-of-Round Commendations
]]

TPG.Commendations = TPG.Commendations or {}

TPG.Commendations.Types = {
    { key = "kills",          name = "Most Kills",            pdataKey = "Medal_Kills" },
    { key = "killsPerTon",    name = "Most Kills Per Ton",    pdataKey = "Medal_KPT" },
    { key = "objectiveKills", name = "Most Objective Kills",  pdataKey = "Medal_ObjKills" },
    { key = "captures",       name = "Most Captures",         pdataKey = "Medal_Captures" },
}

function TPG.Commendations.Award()
    for _, commType in ipairs(TPG.Commendations.Types) do
        local bestPlayer = nil
        local bestValue = -1
        
        for ply, pState in pairs(TPG.State.players) do
            if not IsValid(ply) then continue end
            
            local value = pState.stats[commType.key] or 0
            if value > bestValue then
                bestValue = value
                bestPlayer = ply
            end
        end
        
        if bestPlayer and bestValue >= 0 then
            -- Increment medal count
            local medals = TPG.Util.GetPData(bestPlayer, commType.pdataKey, 0) + 1
            TPG.Util.SetPData(bestPlayer, commType.pdataKey, medals)
            
            -- Announce
            local teamData = TPG.GetTeamData(bestPlayer:Team())
            TPG.Util.ChatBroadcast(
                "[TPG] " .. bestPlayer:Nick() .. " - " .. commType.name .. " (" .. math.floor(bestValue * 100) / 100 .. ") - Medal #" .. medals,
                teamData.color
            )
        end
    end
end

-- Track kills
hook.Add("PlayerDeath", "TPG_TrackKills", function(victim, inflictor, attacker)
    if victim == attacker then return end
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    
    local aState = TPG.State.GetPlayer(attacker)
    
    -- Basic kill
    aState.stats.kills = (aState.stats.kills or 0) + 1
    
    -- Kills per ton
    local playerUsage = TPG.PropTracking.GetPlayerUsage(attacker)
    local tons = math.max((playerUsage.weight or 0) / 1000, 1)
    aState.stats.killsPerTon = (aState.stats.killsPerTon or 0) + (1 / tons)
    
    -- Objective kills (near a control point)
    local nearObjective = false
    TPG.State.objectives = TPG.State.objectives or {}
    
    for _, obj in pairs(TPG.State.objectives) do
        if IsValid(obj) then
            local dist = victim:GetPos():Distance(obj:GetPos())
            if dist < 2000 then
                nearObjective = true
                break
            end
        end
    end
    
    if nearObjective then
        aState.stats.objectiveKills = (aState.stats.objectiveKills or 0) + 1
    end
    
    -- Check for safezone killing (not allowed)
    if TPG.Protection and TPG.Protection.IsInSafezone and TPG.Protection.IsInSafezone(attacker) then
        TPG.Util.ChatMessage(attacker, "[TPG] Do not kill from safezone!", Color(255, 0, 0))
        attacker:Kill()
    end
    
    -- Per-kill ticket drain. DM lives entirely on this (frac 1). CTF adds a
    -- SMALLER version on top of flag captures, so fighting matters between flag
    -- runs while the flag stays the decisive scoring. Every other mode: none.
    local gameType = TPG.GetGameType(TPG.State.gameType)
    local killFrac = gameType.useDeathTickets and 1
        or (TPG.State.gameType == GAMEMODE_CTF and (TPG.Config.ctfKillTicketFrac or 0)) or 0

    if killFrac > 0 then
        local victimTeam = victim:Team()
        local victimUsage = TPG.PropTracking.GetPlayerUsage(victim)

        -- Base loss scales with the tonnage the victim was fielding (the
        -- "weight kill" rule): killing a 40T tank drains far more than a buggy.
        local baseLoss = math.max((victimUsage.weight or 0) / 2000, 1)

        -- Dynamic, player-based scaling: the fewer players on the teams, the
        -- more each kill is worth, so a 4-player round doesn't crawl. Capped at
        -- dmTicketMaxMult so it never gets punishing.
        local active = #team.GetPlayers(TEAM_GREEN) + #team.GetPlayers(TEAM_RED)
        local refPlayers = TPG.Config.dmTicketRefPlayers or 8
        local maxMult    = TPG.Config.dmTicketMaxMult or 2.0
        local mult       = math.Clamp(refPlayers / math.max(active, 1), 1, maxMult)

        TPG.State.AddScore(victimTeam, -math.max(math.ceil(baseLoss * mult * killFrac), 1))
    end
end)