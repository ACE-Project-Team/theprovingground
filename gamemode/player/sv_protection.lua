--[[--
    Safezones, spawn protection, build/noclip restrictions and the combat clock.

    Everything about a team's spawn area being safe: which players are in
    their own or the enemy's safezone, god mode timing, a noclip momentum
    brake so spawn noclip can't be used to slingshot across the map, killing
    players who linger in the enemy's spawn or drown, blocking building and
    SWEP spawning outside the safezone, and the "seconds since last real
    damage" clock that `core/sv_commands.lua`'s re-kit command reads to tell a
    legitimate loadout change from a combat escape.

    Most of this runs from one `Think` hook (`TPG_ProtectionThink`) that walks
    every player once a tick; the individual checks below are also exposed as
    functions because other systems (prep period, re-kit) need the same
    safezone answer outside that hook.

    @module tpg.protection
    @realm server
]]

TPG.Protection = {}

--- Is `ply` inside their own team's safezone?
-- A player off a team (spectator) is always considered safe. Before any round
-- has published spawns (map start, the pre-round wait), there is no
-- "outside" to be on the wrong side of, so this returns true for everyone,
-- rather than telling players their spawn protection just expired on a map
-- they can't even build on yet.
-- @tparam Player ply
-- @treturn boolean
-- @realm server
function TPG.Protection.IsInSafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return true end

    -- No round has published spawns yet (map start, during the wait-for-players
    -- window). There is no "outside" to be on the wrong side of, so treat the
    -- whole map as safe rather than telling everyone their spawn protection
    -- just ran out on a map they can't even build on yet.
    local spawn = TPG.State.GetSpawn(teamId)
    if not spawn then return true end

    return TPG.Util.IsWithinDistance(ply, spawn, TPG.Maps.GetSafezoneRadius())
end

--- Is `ply` inside the ENEMY team's safezone?
-- Off a team, or the enemy's spawn not published yet, returns false (there's
-- nothing to be "in"). Used by the protection Think loop to kill loitering
-- players; unlike @{IsInSafezone}, this is never a state a player should
-- passively sit in.
-- @tparam Player ply
-- @treturn boolean
-- @realm server
function TPG.Protection.IsInEnemySafezone(ply)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return false end

    local enemyTeam = TPG.GetEnemyTeam(teamId)
    local enemySpawn = TPG.State.GetSpawn(enemyTeam)
    if not enemySpawn then return false end

    return TPG.Util.IsWithinDistance(ply, enemySpawn, TPG.Maps.GetSafezoneRadius())
end

local function posInTeamZone(pos, teamId)
    local spawn = TPG.State.GetSpawn(teamId)
    if not spawn then return false end
    local r = TPG.Maps.GetSafezoneRadius()
    return pos:DistToSqr(spawn) < r * r
end

--- Which team's safezone contains this position, if any?
-- The position-based counterpart to @{IsInSafezone}: that one asks about a
-- player, this one about an arbitrary point, which is what the ACE damage
-- permission mode needs when it is handed a prop rather than a person.
--
-- Returns nil while no round has published spawns, which is the same "there is
-- no outside yet" state @{IsInSafezone} treats as safe -- callers that protect
-- on a hit should read nil as "no safezone applies", not "unprotected".
-- @tparam Vector pos
-- @treturn ?number TEAM_GREEN, TEAM_RED, or nil.
-- @realm server
function TPG.Protection.GetSafezoneTeam(pos)
    if posInTeamZone(pos, TEAM_GREEN) then return TEAM_GREEN end
    if posInTeamZone(pos, TEAM_RED)   then return TEAM_RED   end
    return nil
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

        -- Hand out / take back the repair torch. Lives here rather than in a
        -- Think of its own because this loop has already worked out who is
        -- alive, on a team, and inside their zone.
        if TPG.Repair and TPG.Repair.Update then
            TPG.Repair.Update(ply, inSafezone)
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
    noclipState[ply] = nil
end)

-- Disable noclip outside safezone
hook.Add("PlayerNoClip", "TPG_NoclipRestriction", function(ply)
    if ply:IsAdmin() then return true end
    return TPG.Protection.IsInSafezone(ply)
end)

-- Restrict spawning outside safezone. Shared by the three hooks below, so the
-- throttle key is shared too: a player who fires all three in a second is
-- being told one thing and should hear it once.
local function RestrictSpawning(ply, ent)
    if not TPG.Protection.IsInSafezone(ply) then
        if IsValid(ent) then ent:Remove() end
        TPG.Util.ChatMessageThrottled(ply, "spawnzone",
            "[TPG] Cannot spawn outside safezone.", Color(255, 0, 0))
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

--[[--
    "Am I in a fight right now?"

    Used by the loadout re-kit (core/sv_commands.lua) to decide whether a
    respawn-to-change-kit is a legitimate one or an escape from a fight that's
    going badly. Answered by the clock below rather than by proximity or line of
    sight, because taking fire is the thing that actually matters and it costs
    one timestamp to know.

    Never having been hit reads as "not in combat", which is the right answer
    for a fresh spawn and for anyone the round hasn't touched yet.

    @tparam Player ply
    @treturn number Seconds since `ply` last took damage that actually landed
     (stamped by the `EntityTakeDamage` hook below), or `math.huge` if they
     never have this life.
    @realm server
]]
function TPG.Protection.SecondsSinceDamage(ply)
    local last = TPG.State.GetPlayer(ply).lastDamaged
    if not last then return math.huge end
    return CurTime() - last
end

--[[
    Two jobs, one hook, in this order on purpose.

    First: spectators are non-combatants. They're in god mode (sv_spawning) and
    none of the damage they cause lands -- neither from their weapons directly
    nor from anything they own (a spectator test-tank's gun counts as theirs via
    CPPI).

    Then: stamp the combat clock. It runs AFTER those returns and checks god
    mode, so damage that was never going to land doesn't count as being in a
    fight. That matters for the safezone, which is god mode (see the Think hook
    above): without the check, a player being plinked at across their own spawn
    line would be locked out of changing kit by hits that did nothing.

    EntityTakeDamage is a hot hook, so the ordering is also the cheap ordering:
    everything below is behind a damage-is-actually-happening test.
]]
hook.Add("EntityTakeDamage", "TPG_SpectatorNoDamage", function(ent, dmg)
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

    if dmg:GetDamage() <= 0 or not IsValid(ent) then return end

    -- The player themselves, or the one sitting in the thing that got hit --
    -- being shelled inside a tank is being in a fight just as much as being
    -- shot on foot is.
    local hurt
    if ent:IsPlayer() then
        hurt = ent
    elseif ent.GetDriver then
        hurt = ent:GetDriver()
    end

    if IsValid(hurt) and hurt:IsPlayer() and not hurt:HasGodMode() then
        TPG.State.GetPlayer(hurt).lastDamaged = CurTime()
    end
end)