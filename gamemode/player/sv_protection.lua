--[[
    Spawn Protection and Restrictions
]]

TPG.Protection = {}

function TPG.Protection.IsInSafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return true end

    -- No round has published spawns yet (map start, during the wait-for-players
    -- window). There is no "outside" to be on the wrong side of, so treat the
    -- whole map as safe rather than telling everyone their spawn protection
    -- just ran out on a map they can't even build on yet.
    local spawn = TPG.State.GetSpawn(teamId)
    if not spawn then return true end

    return TPG.Util.IsWithinDistance(ply, spawn, TPG.Config.safezoneRadius)
end

function TPG.Protection.IsInEnemySafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return false end

    local enemyTeam = TPG.GetEnemyTeam(teamId)
    local enemySpawn = TPG.State.GetSpawn(enemyTeam)
    if not enemySpawn then return false end

    return TPG.Util.IsWithinDistance(ply, enemySpawn, TPG.Config.safezoneRadius)
end

--[[
    Spawn-zone noclip momentum brake.

    Noclip is allowed inside your own safezone so you can get around your build.
    Noclip also ignores friction and the on-foot speed cap, so you could wind
    yourself up to a few thousand u/s inside spawn, drop noclip on the way out,
    and slingshot across the map on the leftover velocity.

    So: watch for the noclip -> on-foot transition of a noclip session that
    happened in the safezone, and for BRAKE_TIME afterwards clamp the player's
    speed back to a normal on-foot speed. It's a clamp over a short window
    rather than a freeze or a punishment precisely so it can't misfire -- you
    cannot reach the clamp by running, so a player who wasn't exploiting never
    feels it, and one second is long enough that there's no momentum left to
    coast on.
]]
local BRAKE_TIME  = 1
local BRAKE_SPEED = 1.5   -- x baseRunSpeed: the ceiling we clamp back down to

local noclipState = {}    -- [ply] = { fromZone = bool, brakeUntil = time }

local function NoclipBrake(ply, inSafezone)
    if ply:IsAdmin() then return end

    local st = noclipState[ply]
    if not st then st = {}; noclipState[ply] = st end

    if ply:GetMoveType() == MOVETYPE_NOCLIP then
        -- Remember that this noclip session touched the safezone; that's the
        -- only kind we brake (the "only spawnzone" rule).
        if inSafezone then st.fromZone = true end
        return
    end

    -- Falling edge: they just went back to walking.
    if st.fromZone then
        st.fromZone   = nil
        st.brakeUntil = CurTime() + BRAKE_TIME
    end

    if not st.brakeUntil then return end
    if CurTime() >= st.brakeUntil then st.brakeUntil = nil return end
    if ply:InVehicle() then return end

    local cap = (TPG.Config.baseRunSpeed or 350) * BRAKE_SPEED
    local vel = ply:GetVelocity()
    if vel:LengthSqr() > cap * cap then
        -- SetLocalVelocity assigns; Player:SetVelocity would only add to it.
        ply:SetLocalVelocity(vel:GetNormalized() * cap)
    end
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
            pState.spawnProtection = (TPG.Underdog and TPG.Underdog.GetProtectionTime)
                and TPG.Underdog.GetProtectionTime(ply)
                or TPG.Config.spawnProtectionTime
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
        
        -- Bleed off spawn-zone noclip momentum (runs in and out of the zone --
        -- the whole point is that they leave the zone carrying it).
        NoclipBrake(ply, inSafezone)

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
    noclipState[ply] = nil
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

-- Weapons come from the loadout menu, never from the spawn menu. Both routes
-- are blocked: PlayerGiveSWEP is "give me one", PlayerSpawnSWEP is "drop one on
-- the ground for anyone to pick up" -- only the first was covered before.
local function RestrictSWEP(ply)
    if not ply:IsAdmin() then
        TPG.Util.ChatMessage(ply, "[TPG] Only admins can spawn SWEPs. Use the loadout menu.", Color(255, 0, 0))
        return false
    end
end

hook.Add("PlayerGiveSWEP",  "TPG_SWEPRestriction",      RestrictSWEP)
hook.Add("PlayerSpawnSWEP", "TPG_SWEPSpawnRestriction", RestrictSWEP)

-- Spectators are non-combatants: they're in god mode (sv_spawning) and none of
-- the damage they cause lands -- neither from their weapons directly nor from
-- anything they own (a spectator test-tank's gun counts as theirs via CPPI).
hook.Add("EntityTakeDamage", "TPG_SpectatorNoDamage", function(_, dmg)
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and not TPG.Util.IsOnTeam(attacker) then
        return true
    end

    local inflictor = dmg:GetInflictor()
    if IsValid(inflictor) and not inflictor:IsPlayer() and inflictor.CPPIGetOwner then
        local owner = inflictor:CPPIGetOwner()
        if IsValid(owner) and owner:IsPlayer() and not TPG.Util.IsOnTeam(owner) then
            return true
        end
    end
end)