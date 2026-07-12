--[[
    Objective Management
]]

TPG.Objectives = TPG.Objectives or {}

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

function TPG.Objectives.SpawnSafezones()
    -- Green safezone
    local greenSpawn = TPG.State.spawns[TEAM_GREEN]
    if greenSpawn then
        local greenMarker = ents.Create("tpg_safezonemarker")
        if IsValid(greenMarker) then
            greenMarker:SetPos(greenSpawn)
            greenMarker:Spawn()
            greenMarker:SetColor(Color(0, 255, 0, 100))
        end
    end
    
    -- Red safezone
    local redSpawn = TPG.State.spawns[TEAM_RED]
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
                    "[TPG] OVERTIME! Both teams are now bleeding tickets -- force the fight!",
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

-- Track captures for commendations
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