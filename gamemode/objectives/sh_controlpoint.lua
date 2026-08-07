--[[--
    Shared control point logic: the capture state scale and its helpers.

    A point's ownership is a single signed number rather than a team id, which
    is what makes capture progress work as one value: `progress` runs from
    `-maxProgress` (fully red) through 0 (neutral) to `+maxProgress` (fully
    green), and the sign of the number *is* the owner. Contesting a point
    therefore just moves that number, and a team pushing a point back through
    neutral is the same arithmetic as taking it the rest of the way.

    Shared because the HUD has to draw the same scale the server enforces.

    @module tpg.controlpoint
    @realm shared
]]

TPG.ControlPoint = {}

--- Capture states.
-- The sign convention above: green is positive, red negative, neutral zero.
-- @table States
-- @field STATE_NEUTRAL 0
-- @field STATE_GREEN 1
-- @field STATE_RED -1
-- @realm shared
TPG.ControlPoint.STATE_NEUTRAL = 0
TPG.ControlPoint.STATE_GREEN = 1
TPG.ControlPoint.STATE_RED = -1

--- The colour a point should draw at, given how far its capture has got.
-- Fades toward the owning team's colour as the capture completes, and back
-- through yellow as it is pushed to neutral, so the colour alone shows both who
-- holds it and how firmly.
-- @tparam number state One of the `STATE_*` values.
-- @tparam number progress Current capture progress, signed.
-- @tparam number maxProgress Progress needed for a full capture.
-- @treturn Color
-- @realm shared
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

--- The team that owns a capture state.
-- @tparam number state One of the `STATE_*` values.
-- @treturn number TEAM_GREEN, TEAM_RED, or TEAM_UNASSIGNED for neutral.
-- @realm shared
function TPG.ControlPoint.StateToTeam(state)
    if state == TPG.ControlPoint.STATE_GREEN then
        return TEAM_GREEN
    elseif state == TPG.ControlPoint.STATE_RED then
        return TEAM_RED
    end
    return TEAM_UNASSIGNED
end

--- The capture state a team owns a point in. Inverse of @{StateToTeam}.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @treturn number A `STATE_*` value; neutral for anything else.
-- @realm shared
function TPG.ControlPoint.TeamToState(teamId)
    if teamId == TEAM_GREEN then
        return TPG.ControlPoint.STATE_GREEN
    elseif teamId == TEAM_RED then
        return TPG.ControlPoint.STATE_RED
    end
    return TPG.ControlPoint.STATE_NEUTRAL
end

--- How fast a point captures, from who is standing on it.
-- The signed head-count difference, clamped to `TPG.Config.capMaxPlayers` in
-- both directions. Only the difference counts, so an evenly contested point
-- returns 0 and does not move at all no matter how many are on it; and the
-- clamp means stacking more than `capMaxPlayers` extra bodies buys nothing.
-- @tparam number greenCount Green players on the point.
-- @tparam number redCount Red players on the point.
-- @treturn number Signed speed; positive captures toward green.
-- @realm shared
function TPG.ControlPoint.CalculateCaptureSpeed(greenCount, redCount)
    local balance = greenCount - redCount
    return math.Clamp(balance, -TPG.Config.capMaxPlayers, TPG.Config.capMaxPlayers)
end