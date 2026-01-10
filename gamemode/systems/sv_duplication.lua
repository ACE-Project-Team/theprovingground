--[[
    Duplication Handling
]]

TPG.Duplication = {}

hook.Add("AdvDupe_FinishPasting", "TPG_DupeFinished", function(data)
    if not istable(data) or table.IsEmpty(data) then return end
    
    local ents = data[1] and data[1].CreatedEntities
    local ply = data[1] and data[1].Player
    
    if not ents or not IsValid(ply) then return end
    
    local totalProps = 0
    local totalWeight = 0
    
    for _, ent in pairs(ents) do
        if not IsValid(ent) then continue end
        
        local class = ent:GetClass()
        
        -- Skip refill ammo crates
        if class == "acf_ammo" and ent.BulletData and ent.BulletData.Type == "Refill" then
            continue
        end
        
        if class == "prop_physics" then
            totalProps = totalProps + 1
        end
        
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            totalWeight = totalWeight + phys:GetMass()
        end
    end
    
    -- Check limits
    local pState = TPG.State.GetPlayer(ply)
    
    -- Check max weight
    if totalWeight > TPG.Config.maxDupeWeight then
        TPG.Util.ChatMessage(ply, "[TPG] Contraption exceeds " .. (TPG.Config.maxDupeWeight/1000) .. "T limit. Removed.", Color(255, 0, 0))
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        return
    end
    
    -- Check team limits
    local canSpawn, reason = TPG.PropTracking.CanSpawn(ply, totalWeight)
    if not canSpawn then
        TPG.Util.ChatMessage(ply, "[TPG] " .. reason .. ". Contraption removed.", Color(255, 0, 0))
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        return
    end
    
    -- Check cooldown
    if CurTime() < pState.dupeCooldown then
        local remaining = math.ceil(pState.dupeCooldown - CurTime())
        TPG.Util.ChatMessage(ply, "[TPG] Duplicator on cooldown for " .. remaining .. "s. Removed.", Color(255, 0, 0))
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        return
    end
    
    -- Light vehicles bypass cooldown
    if totalWeight <= TPG.Config.lightVehicleWeight and totalProps <= TPG.Config.lightVehicleProps then
        TPG.Util.ChatMessage(ply, "[TPG] Light vehicle spawned. No cooldown.", Color(0, 255, 255))
        TPG.PropTracking.UpdateTeamTotals()
        return
    end
    
    -- Apply grace period then cooldown
    TPG.Util.ChatMessage(ply, "[TPG] " .. TPG.Config.dupeGracePeriod .. "s grace period started.", Color(0, 255, 0))
    
    timer.Simple(TPG.Config.dupeGracePeriod, function()
        if not IsValid(ply) then return end
        
        -- Recalculate weight (may have changed)
        local finalWeight = 0
        for _, ent in pairs(ents) do
            if IsValid(ent) then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    finalWeight = finalWeight + phys:GetMass()
                end
            end
        end
        
        local cooldown = (finalWeight / 1000) * TPG.Config.dupeCooldownPerTon
        local newCooldownEnd = CurTime() + cooldown
        
        if newCooldownEnd > pState.dupeCooldown then
            pState.dupeCooldown = newCooldownEnd
        end
        
        TPG.Util.ChatMessage(ply, "[TPG] Duplicator on cooldown for " .. math.ceil(cooldown) .. "s.", Color(0, 255, 255))
    end)
    
    TPG.PropTracking.UpdateTeamTotals()
end)