--[[
    Shared Control Point Logic
    Constants and helper functions used by both client and server
]]

TPG.ControlPoint = {}

-- Capture states
TPG.ControlPoint.STATE_NEUTRAL = 0
TPG.ControlPoint.STATE_GREEN = 1
TPG.ControlPoint.STATE_RED = -1

-- Get color for capture state
function TPG.ControlPoint.GetStateColor(state, progress, maxProgress)
    local ratio = math.abs(progress / maxProgress)
    
    if state == TPG.ControlPoint.STATE_GREEN then
        return Color(0, 255 * ratio, 0, 255)
    elseif state == TPG.ControlPoint.STATE_RED then
        return Color(255 * ratio, 0, 0, 255)
    else
        local neutralRatio = 1 - ratio
        return Color(255 * neutralRatio, 255 * neutralRatio, 0, 255)
    end
end

-- Get team from state
function TPG.ControlPoint.StateToTeam(state)
    if state == TPG.ControlPoint.STATE_GREEN then
        return TEAM_GREEN
    elseif state == TPG.ControlPoint.STATE_RED then
        return TEAM_RED
    end
    return TEAM_UNASSIGNED
end

-- Get state from team
function TPG.ControlPoint.TeamToState(teamId)
    if teamId == TEAM_GREEN then
        return TPG.ControlPoint.STATE_GREEN
    elseif teamId == TEAM_RED then
        return TPG.ControlPoint.STATE_RED
    end
    return TPG.ControlPoint.STATE_NEUTRAL
end

-- Calculate capture speed based on player counts
function TPG.ControlPoint.CalculateCaptureSpeed(greenCount, redCount)
    local balance = greenCount - redCount
    return math.Clamp(balance, -TPG.Config.capMaxPlayers, TPG.Config.capMaxPlayers)
end