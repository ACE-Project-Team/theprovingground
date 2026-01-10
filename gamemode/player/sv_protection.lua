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

-- Process protection each think
hook.Add("Think", "TPG_ProtectionThink", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:Alive() then continue end
        if not TPG.Util.IsOnTeam(ply) then continue end
        
        local pState = TPG.State.GetPlayer(ply)
        local inSafezone = TPG.Protection.IsInSafezone(ply)
        
        if inSafezone then
            -- In safezone - enable god mode
            ply:GodEnable()
            pState.spawnProtection = TPG.Config.spawnProtectionTime
        else
            -- Out of safezone
            if pState.spawnProtection > 0 then
                pState.spawnProtection = pState.spawnProtection - FrameTime()
                
                if pState.spawnProtection <= 0 then
                    ply:GodDisable()
                    TPG.Util.ChatMessage(ply, "[TPG] Spawn protection ended.", Color(0, 255, 255))
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

-- Disable noclip outside safezone
hook.Add("PlayerNoClip", "TPG_NoclipRestriction", function(ply)
    if ply:IsAdmin() then return true end
    return TPG.Protection.IsInSafezone(ply)
end)

-- Disable spawn menu outside safezone
hook.Add("SpawnMenuOpen", "TPG_SpawnMenuRestriction", function()
    local ply = LocalPlayer()
    
    if not TPG.Protection.IsInSafezone(ply) then
        if not ply:IsAdmin() then
            chat.AddText(Color(255, 0, 0), "[TPG] Cannot open spawn menu outside spawn.")
            return false
        end
    end
end)

-- Restrict spawning outside safezone
local function RestrictSpawning(ply, ent)
    if not TPG.Protection.IsInSafezone(ply) then
        if IsValid(ent) then ent:Remove() end
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