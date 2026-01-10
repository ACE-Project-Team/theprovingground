--[[
    Spawn Protection and Restrictions
]]

TPG.Protection = {}

function TPG.Protection.IsInSafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return true end
    
    local spawn = TPG.State.spawns[teamId]
    if not spawn then return false end
    
    return TPG.Util.IsWithinDistance(ply, spawn, TPG.Config.safezoneRadius)
end

function TPG.Protection.IsInEnemySafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return false end
    
    local enemyTeam = TPG.GetEnemyTeam(teamId)
    local enemySpawn = TPG.State.spawns[enemyTeam]
    if not enemySpawn then return false end
    
    return TPG.Util.IsWithinDistance(ply, enemySpawn, TPG.Config.safezoneRadius)
end

-- Track previous state for messaging
local playerSafezoneState = {}

hook.Add("Think", "TPG_ProtectionThink", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:Alive() then continue end
        if not TPG.Util.IsOnTeam(ply) then continue end
        
        local pState = TPG.State.GetPlayer(ply)
        local inSafezone = TPG.Protection.IsInSafezone(ply)
        local wasInSafezone = playerSafezoneState[ply]
        
        if inSafezone then
            -- Just entered safezone
            if wasInSafezone == false then
                TPG.Util.ChatMessage(ply, "[TPG] Entered safezone. Spawn protection active.", Color(0, 255, 0))
                TPG.Util.PlaySound(ply, "buttons/button9.wav")
            end
            
            ply:GodEnable()
            pState.spawnProtection = TPG.Config.spawnProtectionTime
            playerSafezoneState[ply] = true
        else
            -- Just left safezone
            if wasInSafezone == true then
                TPG.Util.ChatMessage(ply, "[TPG] Left safezone. " .. TPG.Config.spawnProtectionTime .. "s protection remaining.", Color(255, 255, 0))
            end
            
            playerSafezoneState[ply] = false
            
            -- Countdown protection
            if pState.spawnProtection > 0 then
                pState.spawnProtection = pState.spawnProtection - FrameTime()
                
                if pState.spawnProtection <= 0 then
                    pState.spawnProtection = 0
                    ply:GodDisable()
                    TPG.Util.ChatMessage(ply, "[TPG] Spawn protection ended. You can now take damage.", Color(255, 0, 0))
                end
            end
            
            -- Check enemy safezone
            if TPG.Protection.IsInEnemySafezone(ply) then
                ply:Kill()
                TPG.Util.ChatMessage(ply, "[TPG] Stay away from enemy spawn!", Color(255, 0, 0))
            end
            
            -- Check noclip outside safezone
            if ply:GetMoveType() == MOVETYPE_NOCLIP and not ply:IsAdmin() and not ply:InVehicle() then
                ply:Kill()
                TPG.Util.ChatMessage(ply, "[TPG] Cannot noclip outside spawn.", Color(255, 0, 0))
            end
        end
        
        -- Drowning check
        if not ply:InVehicle() and ply:WaterLevel() >= 2 then
            ply:Kill()
            TPG.Util.ChatMessage(ply, "[TPG] You drowned!", Color(255, 0, 0))
        end
        
        -- Reset exploits
        ply:SetColor(Color(255, 255, 255, 255))
        ply:SetMaterial("")
    end
end)

-- Clean up on disconnect
hook.Add("PlayerDisconnected", "TPG_CleanupSafezoneState", function(ply)
    playerSafezoneState[ply] = nil
end)

-- Disable noclip outside safezone
hook.Add("PlayerNoClip", "TPG_NoclipRestriction", function(ply)
    if ply:IsAdmin() then return true end
    return TPG.Protection.IsInSafezone(ply)
end)

-- Restrict spawning outside safezone
local function RestrictSpawning(ply, ent)
    if not TPG.Protection.IsInSafezone(ply) then
        if IsValid(ent) then ent:Remove() end
        TPG.Util.ChatMessage(ply, "[TPG] Cannot spawn outside safezone.", Color(255, 0, 0))
        return false
    end
end

hook.Add("PlayerSpawnedProp", "TPG_PropRestriction", function(ply, model, ent) RestrictSpawning(ply, ent) end)
hook.Add("PlayerSpawnedSENT", "TPG_SENTRestriction", function(ply, ent) RestrictSpawning(ply, ent) end)
hook.Add("PlayerSpawnedVehicle", "TPG_VehicleRestriction", function(ply, ent) RestrictSpawning(ply, ent) end)

hook.Add("PlayerGiveSWEP", "TPG_SWEPRestriction", function(ply)
    if not ply:IsAdmin() then
        TPG.Util.ChatMessage(ply, "[TPG] Only admins can spawn SWEPs.", Color(255, 0, 0))
        return false
    end
end)