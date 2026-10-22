--[[--
    Grenades for TPG's NPC bots (gamemode/bots/sv_bots.lua).

    Combine soldiers' own HL2 grenades are switched off (while ACE grenades
    are in use), so a Red bot never
    throws a frag grenade. Every bot instead lobs an ACE grenade (`ace_grenade`)
    at its enemy now and then, on a ballistic arc. Smoke grenades are never
    thrown. Bots already run from live ACE grenades (sv_cai.lua), so no dodge
    code lives here.

    @module tpg.bots.grenades
    @realm server
]]

local cvEnabled = CreateConVar("tpg_bots_grenades", "1", { FCVAR_ARCHIVE },
    "Bots throw ACE grenades.")
local cvCooldown = CreateConVar("tpg_bots_grenade_cooldown", "12", { FCVAR_ARCHIVE },
    "Seconds between one bot's grenade throws.")

local MIN_RANGE        = 300   -- closest enemy (horizontal units) worth a grenade
local MAX_RANGE        = 1200  -- farthest enemy (horizontal units) worth a grenade
local HORIZONTAL_SPEED = 600   -- constant horizontal speed of the grenade
local THROW_CHANCE     = 0.35  -- chance per check that an eligible bot throws
local TICK             = 1     -- seconds between checks

-- Lob an ACE grenade from the bot's head toward the enemy on a ballistic arc.
local function throwAt(npc, enemy)
    local start = npc:GetShootPos() + Vector(0, 0, -7)
    local toTarget = enemy:WorldSpaceCenter() - start
    local horizontal = Vector(toTarget.x, toTarget.y, 0)
    local dist = horizontal:Length()
    local flightTime = dist / HORIZONTAL_SPEED
    local gravity = physenv.GetGravity()
    local vz = (toTarget.z - 0.5 * gravity.z * flightTime * flightTime) / flightTime
    local velocity = horizontal:GetNormalized() * HORIZONTAL_SPEED + Vector(0, 0, vz)

    local ent = ents.Create("ace_grenade")
    if not IsValid(ent) then return end

    ent:SetPos(start)
    ent:SetAngles(velocity:Angle())
    ent:Spawn()
    if CPPI then ent:CPPISetOwner(Entity(0)) end
    ent.DamageOwner = npc

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:SetVelocity(velocity) end

    npc:EmitSound("weapons/slam/throw.wav")
end

-- The bot list, or nothing while TPG.Bots is not set up.
local function botList()
    return TPG.Bots and TPG.Bots.list or {}
end

-- One check for one bot: throws when it is alive, free, in range and can see its enemy.
local function checkBot(npc, now)
    if not IsValid(npc) or npc:Health() <= 0 then return end
    if npc.TPG_Riding then return end
    if now < (npc.TPG_FleeUntil or 0) then return end -- running from a grenade
    if now < (npc.TPG_NextGrenade or 0) then return end

    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then return end

    local horizontal = enemy:GetPos() - npc:GetPos()
    horizontal.z = 0
    local dist = horizontal:Length()
    if dist < MIN_RANGE or dist > MAX_RANGE then return end
    if not npc:Visible(enemy) then return end

    if math.random() < THROW_CHANCE then
        throwAt(npc, enemy)
        npc.TPG_NextGrenade = now + cvCooldown:GetFloat()
    else
        npc.TPG_NextGrenade = now + TICK * 3
    end
end

timer.Create("TPG_BotGrenades", TICK, 0, function()
    if not cvEnabled:GetBool() then return end
    -- ACE is optional; without its grenade class there is nothing to throw.
    if scripted_ents.GetStored("ace_grenade") == nil then return end

    local now = CurTime()
    for _, npc in ipairs(botList()) do
        checkBot(npc, now)
    end
end)

-- Keep Combine bots out of their own HL2 grenades, so they only throw the ACE
-- ones above. Combat AI hands them grenades again on register and on every
-- squad plan, so a one-off zero at spawn doesn't hold; check every tick.
hook.Add("Think", "TPG_BotNoNativeGrenades", function()
    if not cvEnabled:GetBool() then return end
    if scripted_ents.GetStored("ace_grenade") == nil then return end

    for _, npc in ipairs(botList()) do
        if IsValid(npc) and npc:GetClass() == "npc_combine_s"
            and (npc:GetInternalVariable("m_iNumGrenades") or 0) > 0 then
            npc:SetSaveValue("m_iNumGrenades", 0)
        end
    end
end)
