--[[
    Duplication Handling
    Enforces limits AFTER ACE calculates points
]]

TPG.Duplication = TPG.Duplication or {}

hook.Add("AdvDupe_FinishPasting", "TPG_DupeFinished", function(data)
    if not istable(data) or table.IsEmpty(data) then return end
    
    local ents = data[1] and data[1].CreatedEntities
    local ply = data[1] and data[1].Player
    
    if not ents or not IsValid(ply) then return end
    
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then
        -- Not on a team, remove everything
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        TPG.Util.ChatMessage(ply, "[TPG] Join a team before spawning.", Color(255, 0, 0))
        return
    end
    
    local pState = TPG.State.GetPlayer(ply)
    
    -- Check cooldown FIRST
    if CurTime() < (pState.dupeCooldown or 0) then
        local remaining = math.ceil(pState.dupeCooldown - CurTime())
        TPG.Util.ChatMessage(ply, "[TPG] Duplicator on cooldown for " .. remaining .. "s. Removed.", Color(255, 0, 0))
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        return
    end
    
    -- Wait for ACE to calculate points, then check limits
    -- ACE hooks run on timer.Simple(0), so we wait a bit longer
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        
        -- Recount everything
        TPG.PropTracking.UpdateTeamTotals()
        
        local usage = TPG.PropTracking.GetPlayerUsage(ply)
        local teamLimits = TPG.State.limits[teamId] or {}
        local maxLimits = TPG.State.maxLimits or {}
        
        local overLimit = false
        local reason = ""
        
        -- Check points limit
        if TPG.Config.useACEPoints then
            if (teamLimits.points or 0) > (maxLimits.points or 100000) then
                overLimit = true
                reason = "Team point limit exceeded (" .. math.ceil(teamLimits.points) .. "/" .. maxLimits.points .. ")"
            end
        end
        
        -- Check weight limit
        if (teamLimits.weight or 0) > (maxLimits.weight or 100000) then
            overLimit = true
            reason = "Team weight limit exceeded (" .. math.ceil(teamLimits.weight/1000) .. "T/" .. math.ceil(maxLimits.weight/1000) .. "T)"
        end
        
        -- Check prop limit
        if (teamLimits.props or 0) > (maxLimits.props or 300) then
            overLimit = true
            reason = "Team prop limit exceeded (" .. teamLimits.props .. "/" .. maxLimits.props .. ")"
        end
        
        if overLimit then
            TPG.Util.ChatMessage(ply, "[TPG] " .. reason .. ". Contraption removed.", Color(255, 0, 0))
            
            for _, ent in pairs(ents) do
                if IsValid(ent) then ent:Remove() end
            end
            
            -- Update counts after removal
            timer.Simple(0.1, function()
                TPG.PropTracking.UpdateTeamTotals()
            end)
            return
        end
        
        -- Calculate weight for cooldown
        local totalWeight = 0
        for _, ent in pairs(ents) do
            if IsValid(ent) then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    totalWeight = totalWeight + phys:GetMass()
                end
            end
        end
        
        -- Light vehicles bypass cooldown
        local lightWeight = TPG.Config.lightVehicleWeight or 5000
        local lightProps = TPG.Config.lightVehicleProps or 140
        local propCount = table.Count(ents)
        
        if totalWeight <= lightWeight and propCount <= lightProps then
            TPG.Util.ChatMessage(ply, "[TPG] Light vehicle spawned. No cooldown.", Color(0, 255, 255))
            return
        end
        
        -- Apply cooldown
        local cooldown = (totalWeight / 1000) * (TPG.Config.dupeCooldownPerTon or 2)
        pState.dupeCooldown = CurTime() + cooldown
        
        TPG.Util.ChatMessage(ply, "[TPG] Contraption spawned. Duplicator on cooldown for " .. math.ceil(cooldown) .. "s.", Color(0, 255, 0))
    end)
end)

-- Also check when spawning individual props
hook.Add("PlayerSpawnProp", "TPG_PropLimitCheck", function(ply, model)
    if not TPG.Util.IsOnTeam(ply) then
        return false
    end
    
    local teamId = ply:Team()
    local teamLimits = TPG.State.limits[teamId] or {}
    local maxLimits = TPG.State.maxLimits or {}
    
    if (teamLimits.props or 0) >= (maxLimits.props or 300) then
        TPG.Util.ChatMessage(ply, "[TPG] Team prop limit reached.", Color(255, 0, 0))
        return false
    end
end)

-- Check when spawning SENTs (ACE entities, etc.)
hook.Add("PlayerSpawnSENT", "TPG_SENTLimitCheck", function(ply, class)
    if not TPG.Util.IsOnTeam(ply) then
        return false
    end
    
    -- Allow spawning but check limits after
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        TPG.PropTracking.UpdateTeamTotals()
        
        local teamId = ply:Team()
        local teamLimits = TPG.State.limits[teamId] or {}
        local maxLimits = TPG.State.maxLimits or {}
        
        if TPG.Config.useACEPoints and (teamLimits.points or 0) > (maxLimits.points or 100000) then
            TPG.Util.ChatMessage(ply, "[TPG] Warning: Team is over point limit!", Color(255, 255, 0))
        end
    end)
end)