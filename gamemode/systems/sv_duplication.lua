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
    
    -- Nobody builds before the first round begins (wait-for-players window):
    -- the whole point is that no one gets a budget head start.
    if TPG.State.waitingForPlayers then
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load -- the round hasn't started yet.", Color(255, 200, 0))
        return
    end

    local teamId = ply:Team()

    -- Spectators may build freely: no team budget, no cooldown, no economy
    -- charge. They're godmoded and their damage is nulled (sv_protection), so
    -- it's a pure sandbox for testing builds between matches.
    if not TPG.Util.IsOnTeam(ply) then
        return
    end

    local pState = TPG.State.GetPlayer(ply)

    -- Under the per-player economy the wallet IS the pacing mechanism (a
    -- destroyed vehicle isn't refunded), so no duplicator cooldown on top.
    local econActive = TPG.Economy and TPG.Economy.Active

    -- Check cooldown FIRST
    if not econActive and CurTime() < (pState.dupeCooldown or 0) then
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
        
        -- Points / economy check.
        -- When the per-player economy is active it REPLACES the shared team
        -- point budget: the player buys this contraption from their own wallet.
        local econCharge = nil
        if TPG.Economy and TPG.Economy.Active then
            econCharge = TPG.Economy.GetContraptionCost(ents)
            if not TPG.Economy.CanAfford(ply, econCharge) then
                overLimit = true
                reason = "Not enough points: costs " .. math.ceil(econCharge) ..
                    ", you have " .. TPG.Economy.GetMoney(ply)
            end
        elseif TPG.Config.useACEPoints then
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

        -- Passed all checks. Under the economy, charge the wallet now
        -- (true purchase -- a destroyed vehicle is not refunded).
        if econCharge then
            TPG.Economy.Charge(ply, econCharge, "vehicle")
            TPG.Util.ChatMessage(ply, "[TPG] Purchased for " .. math.ceil(econCharge) ..
                " pts. Balance: " .. TPG.Economy.GetMoney(ply), Color(0, 255, 0))
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
        
        -- No cooldown at all under the economy (the purchase was the cost).
        if econActive then return end

        -- Light vehicles bypass cooldown
        local lightWeight = TPG.Config.lightVehicleWeight or 5000
        local lightProps = TPG.Config.lightVehicleProps or 140
        local propCount = table.Count(ents)

        if totalWeight <= lightWeight and propCount <= lightProps then
            TPG.Util.ChatMessage(ply, "[TPG] Light vehicle spawned. No cooldown.", Color(0, 255, 255))
            return
        end
        
        -- Apply cooldown. Two drivers, whichever is longer:
        --   weight -> (tons * dupeCooldownPerTon), the old heavy-rig penalty
        --   points -> (kpoints * dupeCooldownPer1kPoints), so a pricey high-point
        --             build also costs more cooldown even if it isn't heavy.
        local points    = (TPG.Economy and TPG.Economy.GetContraptionCost
                            and TPG.Economy.GetContraptionCost(ents)) or 0
        local weightCd  = (totalWeight / 1000) * (TPG.Config.dupeCooldownPerTon or 2)
        local pointCd   = (points / 1000) * (TPG.Config.dupeCooldownPer1kPoints or 3)
        local cooldown  = math.max(weightCd, pointCd)
        pState.dupeCooldown = CurTime() + cooldown
        
        TPG.Util.ChatMessage(ply, "[TPG] Contraption spawned. Duplicator on cooldown for " .. math.ceil(cooldown) .. "s.", Color(0, 255, 0))
    end)
end)

-- Also check when spawning individual props
hook.Add("PlayerSpawnProp", "TPG_PropLimitCheck", function(ply, model)
    if TPG.State.waitingForPlayers then
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load -- the round hasn't started yet.", Color(255, 200, 0))
        return false
    end

    -- Spectators build outside the team limit system entirely.
    if not TPG.Util.IsOnTeam(ply) then
        return
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
    if TPG.State.waitingForPlayers then
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load -- the round hasn't started yet.", Color(255, 200, 0))
        return false
    end

    -- Spectators build outside the team limit system entirely.
    if not TPG.Util.IsOnTeam(ply) then
        return
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