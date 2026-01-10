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
            ent.PointID = i
            ent.PointName = objData.name or ("Point " .. i)
            
            TPG.State.objectives[i] = ent
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
            greenMarker.Scale = (TPG.Config.safezoneRadius or 750) * 2
            greenMarker:Spawn()
            greenMarker:SetColor(TPG.GetTeamData(TEAM_GREEN).color)
        end
    end
    
    -- Red safezone
    local redSpawn = TPG.State.spawns[TEAM_RED]
    if redSpawn then
        local redMarker = ents.Create("tpg_safezonemarker")
        if IsValid(redMarker) then
            redMarker:SetPos(redSpawn)
            redMarker.Scale = (TPG.Config.safezoneRadius or 750) * 2
            redMarker:Spawn()
            redMarker:SetColor(TPG.GetTeamData(TEAM_RED).color)
        end
    end
end

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
        -- Green owns more points, drain red
        TPG.State.AddScore(TEAM_RED, totalCapValue * capMul)
    elseif totalCapValue > 0 then
        -- Red owns more points, drain green
        TPG.State.AddScore(TEAM_GREEN, -totalCapValue * capMul)
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
        end
    end
end