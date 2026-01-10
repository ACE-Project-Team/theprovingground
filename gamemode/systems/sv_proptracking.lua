--[[
    Prop and Weight Tracking
]]

TPG.PropTracking = TPG.PropTracking or {}

-- Per-player tracking
TPG.PropTracking.Players = {}

function TPG.PropTracking.UpdateTeamTotals()
    -- Reset team totals
    TPG.State.limits[TEAM_GREEN] = { props = 0, weight = 0, points = 0 }
    TPG.State.limits[TEAM_RED] = { props = 0, weight = 0, points = 0 }
    
    -- Reset player tracking
    TPG.PropTracking.Players = {}
    
    -- Count all props
    for _, ent in ipairs(ents.FindByClass("prop_*")) do
        if not IsValid(ent) then continue end
        
        local owner = ent:CPPIGetOwner()
        if not IsValid(owner) or not owner:IsPlayer() then continue end
        
        local teamId = owner:Team()
        if not TPG.Util.IsOnTeam(owner) then continue end
        
        -- Init player tracking
        if not TPG.PropTracking.Players[owner] then
            TPG.PropTracking.Players[owner] = { props = 0, weight = 0, points = 0 }
        end
        
        local phys = ent:GetPhysicsObject()
        local mass = IsValid(phys) and phys:GetMass() or 0
        local points = ent._tpgPoints or (mass / 1000 * 100)
        
        -- Add to player
        TPG.PropTracking.Players[owner].props = TPG.PropTracking.Players[owner].props + 1
        TPG.PropTracking.Players[owner].weight = TPG.PropTracking.Players[owner].weight + mass
        TPG.PropTracking.Players[owner].points = TPG.PropTracking.Players[owner].points + points
    end
    
    -- Sum up team totals
    for owner, data in pairs(TPG.PropTracking.Players) do
        if not IsValid(owner) then continue end
        
        local teamId = owner:Team()
        
        -- Only count if vehicle is substantial
        if data.weight > TPG.Config.lightVehicleWeight or data.props > TPG.Config.lightVehicleProps then
            TPG.State.limits[teamId].props = TPG.State.limits[teamId].props + data.props
            TPG.State.limits[teamId].weight = TPG.State.limits[teamId].weight + data.weight
            TPG.State.limits[teamId].points = TPG.State.limits[teamId].points + data.points
        end
    end
    
    -- Sync to clients (with nil check)
    if TPG.Net and TPG.Net.SyncLimits then
        TPG.Net.SyncLimits()
    end
end

-- Get player's current usage
function TPG.PropTracking.GetPlayerUsage(ply)
    return TPG.PropTracking.Players[ply] or { props = 0, weight = 0, points = 0 }
end

-- Check if player can spawn more
function TPG.PropTracking.CanSpawn(ply, additionalWeight)
    local teamId = ply:Team()
    if not TPG.Util.IsOnTeam(ply) then return false, "Not on a team" end
    
    local teamLimits = TPG.State.limits[teamId] or {}
    local maxLimits = TPG.State.maxLimits or {}
    
    if (teamLimits.props or 0) >= (maxLimits.props or 300) then
        return false, "Team prop limit reached"
    end
    
    if (teamLimits.weight or 0) + (additionalWeight or 0) >= (maxLimits.weight or 100000) then
        return false, "Team weight limit reached"
    end
    
    if TPG.Config.useACEPoints and (teamLimits.points or 0) >= (maxLimits.points or 5000) then
        return false, "Team point limit reached"
    end
    
    return true
end

-- Periodic update
local updateTick = 0
hook.Add("Think", "TPG_PropTrackingUpdate", function()
    updateTick = updateTick + 1
    if updateTick < (TPG.Config.propUpdateInterval or 100) then return end
    updateTick = 0
    
    TPG.PropTracking.UpdateTeamTotals()
end)