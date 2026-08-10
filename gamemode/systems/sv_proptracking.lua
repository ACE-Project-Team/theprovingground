--[[--
    Team prop/weight/point totals: the shared-budget side of the build limits.

    Recomputes each team's props, weight and ACE points every 2 seconds (a
    `Think` hook, not event-driven) and stores both the per-team sums
    (`TPG.State.limits`) and a per-player snapshot (`TPG.PropTracking.Players`)
    that other systems read via @{TPG.PropTracking.GetPlayerUsage} instead of
    recomputing it themselves.

    Only vehicles above `lightVehicleWeight`/`lightVehicleProps` count toward
    a team's total at all -- a player's snapshot in `.Players` always reflects
    their real build, but a genuinely light vehicle contributes nothing to the
    team limit it is checked against, which is why a fleet of light buggies
    does not visibly move the team's used points.

    Uses ACE/CFW's own tracking (@{tpg.ace}) when available, and otherwise
    falls back to a manual `ents.GetAll()` scan by owner with a synthetic
    points-from-weight formula -- the fallback path only exists for a server
    running without ACE/CFW loaded and is not what a normal TPG server uses.

    Point totals are the expensive read (ACE recalculates them lazily; see
    @{tpg.ace}), so forcing a fresh rebuild is throttled separately from the
    2-second prop/weight cadence by `tpg_points_refresh_interval` -- 0 means
    never force a rebuild, which is the first thing to try if a round is
    lagging.

    @module tpg.proptracking
    @realm server
]]

TPG.PropTracking = TPG.PropTracking or {}
TPG.PropTracking.Players = {}

--[[--
    Recompute every playing team's props/weight/points, and each player's own usage.

    `refreshPoints` forces ACE to rebuild stale point totals before reading
    them. Props and weight don't need it: CFW maintains `con.ents` and
    `con.totalMass` live, so those are just table reads. ACE points are the
    expensive one (lazy, rebuilt on demand), which is why the caller decides
    how often it's worth paying for -- see the `tpg_points_refresh_interval`
    convar below, which drives the periodic caller.

    Fully replaces `TPG.State.limits` and `TPG.PropTracking.Players` each
    call; nothing here is incremental. Syncs the result to clients via
    `TPG.Net.SyncLimits` if that exists.

    @tparam[opt=false] boolean refreshPoints Force ACE to rebuild point
     totals before reading them.
    @realm server
]]
function TPG.PropTracking.UpdateTeamTotals(refreshPoints)
    -- Reset team totals
    TPG.State.limits[TEAM_GREEN] = { props = 0, weight = 0, points = 0 }
    TPG.State.limits[TEAM_RED] = { props = 0, weight = 0, points = 0 }
    
    TPG.PropTracking.Players = {}
    
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        
        local teamId = ply:Team()
        if not TPG.Util.IsOnTeam(ply) then
            -- A player the AFK sweep benched to spectators left their build
            -- standing on the map, so it keeps costing the team it was built
            -- for. Otherwise going AFK would refund the team its budget while
            -- the tank is still sitting there being a tank. `_tpgAFKTeam` is
            -- cleared by `sv_afk.lua` the moment they are back on a team.
            teamId = ply._tpgAFKTeam
            if teamId ~= TEAM_GREEN and teamId ~= TEAM_RED then continue end
        end
        
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

--- Fallback prop/weight count for a player via a full entity scan, no ACE/CFW.
-- Only used when `TPG.CFWAvailable` is false; a normal server never takes
-- this path.
-- @tparam Player ply
-- @treturn number props
-- @treturn number weight
-- @realm server
function TPG.PropTracking.ManualCount(ply)
    local props = 0
    local weight = 0
    
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        
        if TPG.Util.GetOwner(ent) ~= ply then continue end
        
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

--- A player's last-computed props/weight/points, from the periodic team update.
-- This is a read of the snapshot @{TPG.PropTracking.UpdateTeamTotals} last
-- wrote, not a live recount -- it can be up to 2 seconds (or one
-- `tpg_points_refresh_interval` for the points figure) behind reality.
-- @tparam Player ply
-- @treturn table `{ props, weight, points }`; zeroed if the player has no
--  recorded usage yet.
-- @realm server
function TPG.PropTracking.GetPlayerUsage(ply)
    return TPG.PropTracking.Players[ply] or { props = 0, weight = 0, points = 0 }
end

--[[--
    Would spawning this add-on push the player's team over any shared limit.

    Not currently called anywhere in this codebase -- the actual spawn-time
    enforcement lives in `sv_duplication.lua`, split across two places that do
    not agree on the comparison:

      * its post-paste check (in the `AdvDupe_FinishPasting` handler) uses `>`,
        strictly over, for points, weight and props alike;
      * its `PlayerSpawnProp` gate uses `>=`, at-or-over, on props only.

    This function uses `>=` throughout, so if it is ever wired back in it will
    refuse a team at exactly the cap on all three axes, which matches the prop
    gate but is one build stricter than the paste check.

    @tparam Player ply
    @tparam[opt=0] number additionalWeight Weight the pending spawn would add.
    @treturn boolean
    @treturn ?string Reason it was refused, if it was.
    @realm server
]]
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