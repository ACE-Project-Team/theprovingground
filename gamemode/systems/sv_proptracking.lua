--[[
    Prop and Weight Tracking
    Uses ACE/CFW data when available
]]

TPG.PropTracking = TPG.PropTracking or {}
TPG.PropTracking.Players = {}

-- `refreshPoints` forces ACE to rebuild stale point totals before we read them.
-- Props and weight don't need it -- CFW maintains con.ents and con.totalMass for
-- us, so those are just table reads. ACE points are the expensive one (lazy,
-- rebuilt on demand), which is why the caller decides how often it's worth it.
function TPG.PropTracking.UpdateTeamTotals(refreshPoints)
    -- Reset team totals
    TPG.State.limits[TEAM_GREEN] = { props = 0, weight = 0, points = 0 }
    TPG.State.limits[TEAM_RED] = { props = 0, weight = 0, points = 0 }
    
    TPG.PropTracking.Players = {}
    
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        
        local teamId = ply:Team()
        if not TPG.Util.IsOnTeam(ply) then continue end
        
        local props, weight, points
        
        if TPG.CFWAvailable and TPG.ACE then
            -- Use ACE/CFW tracking
            props = TPG.ACE.GetPlayerPropCount(ply)
            weight = TPG.ACE.GetPlayerMass(ply)
            points = TPG.ACE.GetPlayerPoints(ply, refreshPoints)
        else
            -- Fallback
            props, weight = TPG.PropTracking.ManualCount(ply)
            points = weight / 1000 * 100
        end
        
        TPG.PropTracking.Players[ply] = {
            props = props,
            weight = weight,
            points = points,
        }
        
        -- Only count substantial vehicles
        local lightWeight = TPG.Config.lightVehicleWeight or 5000
        local lightProps = TPG.Config.lightVehicleProps or 140
        
        if weight > lightWeight or props > lightProps then
            TPG.State.limits[teamId].props = TPG.State.limits[teamId].props + props
            TPG.State.limits[teamId].weight = TPG.State.limits[teamId].weight + weight
            TPG.State.limits[teamId].points = TPG.State.limits[teamId].points + points
        end
    end
    
    if TPG.Net and TPG.Net.SyncLimits then
        TPG.Net.SyncLimits()
    end
end

function TPG.PropTracking.ManualCount(ply)
    local props = 0
    local weight = 0
    
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        
        local owner = ent:CPPIGetOwner()
        if owner ~= ply then continue end
        
        if ent:GetClass() == "prop_physics" then
            props = props + 1
        end
        
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            weight = weight + phys:GetMass()
        end
    end
    
    return props, weight
end

function TPG.PropTracking.GetPlayerUsage(ply)
    return TPG.PropTracking.Players[ply] or { props = 0, weight = 0, points = 0 }
end

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
    
    if TPG.Config.useACEPoints and (teamLimits.points or 0) >= (maxLimits.points or 100000) then
        return false, "Team point limit reached"
    end
    
    return true
end

-- How often the tracker is allowed to force ACE to rebuild point totals. The
-- prop/weight side still updates every 2s regardless -- it's cheap. This only
-- governs the expensive part.
--
-- Set to 0 to never force a rebuild: point numbers then only move when
-- something else in ACE recalculates them, which is the cheapest the server can
-- possibly be. That's the setting to try first if the round is lagging, since
-- it takes TPG's periodic ACE work to zero without touching anything else.
local cvarRefresh = CreateConVar("tpg_points_refresh_interval", "10",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Seconds between forced ACE point rebuilds for team budget tracking. 0 = never force.")

-- Update every 2 seconds
local lastUpdate = 0
local lastPointsRefresh = 0
hook.Add("Think", "TPG_PropTrackingUpdate", function()
    if CurTime() - lastUpdate < 2 then return end
    lastUpdate = CurTime()

    local interval = cvarRefresh:GetFloat()
    local refreshPoints = interval > 0 and (CurTime() - lastPointsRefresh) >= interval
    if refreshPoints then lastPointsRefresh = CurTime() end

    TPG.PropTracking.UpdateTeamTotals(refreshPoints)
end)