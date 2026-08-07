--[[--
    Objective management: the control points, and the scoring that runs off
    them.

    @{ProcessScoring} is where the gamemode's central rule actually lives. Every
    control point reports an ownership value; those are summed, and the sign of
    the total says which side is ahead, so the loser's ticket pool drains in
    proportion. One team holding everything drains fast, a split map barely
    drains at all, and a mode that scores some other way (CTF, deathmatch) sets
    its cap multiplier to zero and does its own accounting.

    Because that drain is the only pressure in an objective mode, a stalemate
    where neither side can hold a point produces a round that never ends. That
    is what overtime exists for; see @{GetOvertime}.

    Called from the `Think` in @{tpg.rounds} on a fixed step, not per tick.

    @module tpg.objectives
    @realm server
]]

TPG.Objectives = TPG.Objectives or {}

--- Remove the current control points and spawn this round's set.
-- Clears `TPG.State.objectives` first, so it is safe to call on a live round.
-- An empty or missing list leaves the round with no objectives at all, which in
-- most modes means one that can never end -- a map with no block for the
-- current game type is the usual cause.
-- @tparam table objectiveList Entries of `{ pos = Vector, name = string }`, as
--  returned by `TPG.Maps.GetObjectives`. Names default to "Point N".
-- @realm server
function TPG.Objectives.SpawnAll(objectiveList)
    -- Clear existing objectives
    TPG.State.objectives = TPG.State.objectives or {}
    
    for _, obj in pairs(TPG.State.objectives) do
        if IsValid(obj) then obj:Remove() end
    end
    TPG.State.objectives = {}
    
    -- Spawn new objectives
    if not objectiveList or #objectiveList == 0 then
        print("[TPG] No objectives to spawn")
        return
    end
    
    for i, objData in ipairs(objectiveList) do
        local ent = ents.Create("tpg_controlpoint")
        
        if IsValid(ent) then
            ent:SetPos(objData.pos)
            ent:Spawn()
            
            -- Set point data
            ent.PointID = i
            ent.PointName = objData.name or ("Point " .. i)
            
            -- Network to clients
            ent:SetupNetworking()
            
            TPG.State.objectives[i] = ent
            
            print("[TPG] Spawned objective " .. i .. ": " .. ent.PointName)
        end
    end
    
    print("[TPG] Spawned " .. #objectiveList .. " objectives")
end

--- Put a coloured marker on each team's spawn.
-- Visual only; the protection itself is in `player/sv_protection.lua`. A team
-- whose spawn hasn't been published yet gets no marker rather than one at the
-- map origin -- see @{tpg.state.GetSpawn}.
-- @realm server
function TPG.Objectives.SpawnSafezones()
    -- Green safezone
    local greenSpawn = TPG.State.GetSpawn(TEAM_GREEN)
    if greenSpawn then
        local greenMarker = ents.Create("tpg_safezonemarker")
        if IsValid(greenMarker) then
            greenMarker:SetPos(greenSpawn)
            greenMarker:Spawn()
            greenMarker:SetColor(Color(0, 255, 0, 100))
        end
    end
    
    -- Red safezone
    local redSpawn = TPG.State.GetSpawn(TEAM_RED)
    if redSpawn then
        local redMarker = ents.Create("tpg_safezonemarker")
        if IsValid(redMarker) then
            redMarker:SetPos(redSpawn)
            redMarker:Spawn()
            redMarker:SetColor(Color(255, 0, 0, 100))
        end
    end
end

-- Overtime announcement latch, keyed to the round it fired for.
local overtimeAnnouncedFor = 0
local objOvertimeAnnouncedFor = 0

--[[--
    How far into objective overtime the round is (CP / KOTH / CTF).

    Objective modes have no self-resolving pressure: if neither side can hold
    the point, nobody's tickets move and the round runs until people give up on
    it. Past the start threshold this ramps two dials over the ramp duration:

        capture times  ->  collapse toward instant (applied inside
                           tpg_controlpoint), so a point can flip under fire
                           instead of needing an uncontested ten seconds
                           nobody ever gets
        ticket drain   ->  multiplied up, so holding it actually ends the round

    Both thresholds can be set per game type
    (`TPG.Config.objOvertimeStartByType` / `objOvertimeRampByType`) and fall
    back to the global `objOvertimeStart` / `objOvertimeRamp`. CP waits much
    longer and ramps more slowly than KOTH, because several points already
    resolve rounds on their own.

    Deathmatch is excluded here -- it has its own bleed, applied at the bottom
    of @{ProcessScoring}.

    @treturn number 0 to 1, how far through the ramp. 0 means not in overtime,
     including whenever no round is active.
    @realm server
]]
function TPG.Objectives.GetOvertime()
    if not TPG.State.round.active then return 0 end

    local gameType = TPG.GetGameType(TPG.State.gameType)
    if gameType.useDeathTickets then return 0 end

    -- Per-gametype timing wins over the global default (see sh_config.lua):
    -- CP's multiple points already resolve rounds on their own, so it waits
    -- much longer and ramps more slowly than a single-point KOTH.
    local byType = TPG.Config.objOvertimeStartByType or {}
    local start  = byType[TPG.State.gameType] or TPG.Config.objOvertimeStart or 900

    local rampByType = TPG.Config.objOvertimeRampByType or {}
    local ramp = rampByType[TPG.State.gameType] or TPG.Config.objOvertimeRamp or 300

    local elapsed = CurTime() - TPG.State.round.startTime
    local over    = elapsed - start
    if over <= 0 then return 0 end

    return math.Clamp(over / math.max(ramp, 1), 0, 1)
end

--- Scale factor for anything that drains tickets while overtime is running.
-- Ramps from 1 at the start of overtime to `TPG.Config.objOvertimeDrainMul`
-- (default 4) at the end of the ramp.
-- @treturn number 1 when not in overtime.
-- @realm server
function TPG.Objectives.GetOvertimeDrainMul()
    local ot = TPG.Objectives.GetOvertime()
    if ot <= 0 then return 1 end
    return 1 + ot * ((TPG.Config.objOvertimeDrainMul or 4) - 1)
end

--[[--
    Advance scoring by one step: drain the losing side, and handle overtime.

    Sums every live point's `CapOwnership`, picks the cap multiplier (map config
    first, then the game type's default, with KOTH forced to
    `TPG.Config.kothCapMul` so one knob tunes every KOTH map), scales it by
    overtime if that has opened, and drains the team that is behind. A total of
    zero -- an even split, or a mode with no points -- drains nobody.

    Deathmatch is handled separately at the end: deaths are its only drain, so a
    passive round never ended. Past `dmOvertimeStart` *both* teams bleed at a
    rate that steps up over time, and whoever still holds more tickets when one
    side hits zero takes the round.

    Called once per fixed score step from the `Think` in @{tpg.rounds}, so the
    drain rate does not depend on tickrate. Both overtime announcements are
    latched to the round start time, so they fire once per round.

    @realm server
]]
function TPG.Objectives.ProcessScoring()
    local totalCapValue = 0

    TPG.State.objectives = TPG.State.objectives or {}

    for _, obj in pairs(TPG.State.objectives) do
        if IsValid(obj) and obj.CapOwnership then
            totalCapValue = totalCapValue + obj.CapOwnership
        end
    end

    local mapConfig = TPG.Maps.Get()
    local gameTypeConfig = mapConfig[TPG.State.gameType] or {}
    local gameType = TPG.GetGameType(TPG.State.gameType)
    local capMul = gameTypeConfig.capMultiplier or gameType.defaultCapMul or 0.02

    -- KOTH: force the global drain knob over whatever the map hardcoded (they
    -- all ship 0.15, which ended rounds in ~2.5 min). One place to tune every
    -- KOTH map to a ~20 min hold. See TPG.Config.kothCapMul for the math.
    if TPG.State.gameType == GAMEMODE_KOTH and TPG.Config.kothCapMul then
        capMul = TPG.Config.kothCapMul
    end

    -- Objective overtime: ramp the drain, and tell everyone the moment it opens
    -- (the capture-time half is applied inside tpg_controlpoint).
    local overtime = TPG.Objectives.GetOvertime()
    if overtime > 0 then
        capMul = capMul * TPG.Objectives.GetOvertimeDrainMul()

        if objOvertimeAnnouncedFor ~= TPG.State.round.startTime then
            objOvertimeAnnouncedFor = TPG.State.round.startTime
            SetGlobalBool("TPG_ObjOvertime", true)
            SetGlobalFloat("TPG_ObjOvertimeStart", CurTime())
            TPG.Util.ChatBroadcast(
                "[TPG] OVERTIME! Capture times are being cut to almost nothing and tickets " ..
                "are draining fast - take the point and end it.", Color(255, 120, 40))
        end
    end

    if totalCapValue < 0 then
        -- Red owns more points, drain green
        TPG.State.AddScore(TEAM_GREEN, totalCapValue * capMul)
    elseif totalCapValue > 0 then
        -- Green owns more points, drain red
        TPG.State.AddScore(TEAM_RED, -totalCapValue * capMul)
    end

    -- DM overtime: deaths are DM's only drain, so a passive round never ended.
    -- Past dmOvertimeStart both teams bleed at a ramping rate; whoever holds
    -- more tickets when someone hits zero wins (see CheckWinCondition).
    if gameType.useDeathTickets then
        local overtime = (CurTime() - TPG.State.round.startTime) - (TPG.Config.dmOvertimeStart or 600)
        if overtime > 0 then
            if overtimeAnnouncedFor ~= TPG.State.round.startTime then
                overtimeAnnouncedFor = TPG.State.round.startTime
                TPG.Util.ChatBroadcast(
                    "[TPG] OVERTIME! Both teams are now bleeding tickets - force the fight!",
                    Color(255, 120, 40))
            end

            local rate = math.min(
                (TPG.Config.dmOvertimeBleed or 0.2)
                    + math.floor(overtime / (TPG.Config.dmOvertimeRampEvery or 120))
                    * (TPG.Config.dmOvertimeRamp or 0.2),
                TPG.Config.dmOvertimeBleedMax or 2)

            local step = TPG.Config.scoreStep or 0.075
            TPG.State.AddScore(TEAM_GREEN, -rate * step)
            TPG.State.AddScore(TEAM_RED, -rate * step)
        end
    end
end

--- Credit a capture to everyone who was standing on the point.
-- Called by `tpg_controlpoint` when a point finishes flipping. Pays the
-- round-local capture stat (for commendations) and the lifetime one via
-- @{tpg.stats.OnCapture}, to every player of the capturing team within
-- `TPG.Config.capDistanceMeters` of the point -- so a contested cap rewards
-- everyone who held it, not just whoever arrived first.
-- @tparam Entity obj The control point.
-- @tparam number teamId The team that captured it.
-- @realm server
function TPG.Objectives.OnCapture(obj, teamId)
    if not IsValid(obj) then return end
    
    local capRadius = TPG.Util.MetersToUnits(TPG.Config.capDistanceMeters or 5)
    
    for _, ply in ipairs(team.GetPlayers(teamId)) do
        local dist = ply:GetPos():Distance(obj:GetPos())
        
        if dist < capRadius then
            local pState = TPG.State.GetPlayer(ply)
            pState.stats.captures = (pState.stats.captures or 0) + 1

            if TPG.Stats and TPG.Stats.OnCapture then
                TPG.Stats.OnCapture(ply)
            end
        end
    end
end