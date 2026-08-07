local CP = nil

describe("control points: the state scale")

it("uses a signed scale with neutral at zero", function()
    CP = TPG.ControlPoint
    expect.eq(CP.STATE_NEUTRAL, 0)
    expect.eq(CP.STATE_GREEN, 1)
    expect.eq(CP.STATE_RED, -1)
    expect.eq(CP.STATE_GREEN, -CP.STATE_RED,
        "the sign of the number is supposed to BE the owner")
end)

describe("control points: state and team")

it("maps each state to its team", function()
    CP = TPG.ControlPoint
    expect.eq(CP.StateToTeam(CP.STATE_GREEN), TEAM_GREEN)
    expect.eq(CP.StateToTeam(CP.STATE_RED), TEAM_RED)
    expect.eq(CP.StateToTeam(CP.STATE_NEUTRAL), TEAM_UNASSIGNED)
end)

it("maps each team back to its state", function()
    CP = TPG.ControlPoint
    expect.eq(CP.TeamToState(TEAM_GREEN), CP.STATE_GREEN)
    expect.eq(CP.TeamToState(TEAM_RED), CP.STATE_RED)
    expect.eq(CP.TeamToState(TEAM_UNASSIGNED), CP.STATE_NEUTRAL)
end)

it("round-trips both ways", function()
    CP = TPG.ControlPoint
    for _, state in ipairs({ CP.STATE_GREEN, CP.STATE_RED, CP.STATE_NEUTRAL }) do
        expect.eq(CP.TeamToState(CP.StateToTeam(state)), state)
    end
    for _, id in ipairs({ TEAM_GREEN, TEAM_RED, TEAM_UNASSIGNED }) do
        expect.eq(CP.StateToTeam(CP.TeamToState(id)), id)
    end
end)

it("treats an unknown team as neutral", function()
    CP = TPG.ControlPoint
    expect.eq(CP.TeamToState(999), CP.STATE_NEUTRAL)
    expect.eq(CP.TeamToState(nil), CP.STATE_NEUTRAL)
end)

describe("control points: capture speed")

it("is the signed head-count difference", function()
    CP = TPG.ControlPoint
    expect.eq(CP.CalculateCaptureSpeed(1, 0), 1)
    expect.eq(CP.CalculateCaptureSpeed(0, 1), -1)
    expect.eq(CP.CalculateCaptureSpeed(3, 1), 2)
    expect.eq(CP.CalculateCaptureSpeed(1, 3), -2)
end)

it("stalls completely on an evenly contested point", function()
    CP = TPG.ControlPoint
    -- Only the difference counts, so a twelve-a-side brawl on the point moves
    -- it exactly as much as an empty point: not at all.
    for n = 0, 12 do
        expect.eq(CP.CalculateCaptureSpeed(n, n), 0, n .. " vs " .. n .. " should not move")
    end
end)

it("clamps in both directions at capMaxPlayers", function()
    CP = TPG.ControlPoint
    local cap = TPG.Config.capMaxPlayers
    expect.eq(CP.CalculateCaptureSpeed(cap + 10, 0), cap)
    expect.eq(CP.CalculateCaptureSpeed(0, cap + 10), -cap)
end)

it("buys nothing by stacking bodies past the cap", function()
    CP = TPG.ControlPoint
    local cap = TPG.Config.capMaxPlayers
    expect.eq(CP.CalculateCaptureSpeed(cap, 0), CP.CalculateCaptureSpeed(cap + 50, 0))
end)

describe("control points: the display colour")

it("fades toward the owner's colour as the capture completes", function()
    CP = TPG.ControlPoint
    local partial = CP.GetStateColor(CP.STATE_GREEN, 5, 10)
    local full    = CP.GetStateColor(CP.STATE_GREEN, 10, 10)

    expect.eq(partial.r, 0)
    expect.eq(partial.b, 0)
    expect.truthy(full.g > partial.g, "a completed capture should read stronger than a half one")
    expect.eq(full.g, 255)
end)

it("uses the sign of the progress, not just the state", function()
    CP = TPG.ControlPoint
    local red = CP.GetStateColor(CP.STATE_RED, -10, 10)
    expect.eq(red.r, 255)
    expect.eq(red.g, 0)
end)

it("shows a neutral point as yellow, fading out as it is taken", function()
    CP = TPG.ControlPoint
    local untouched = CP.GetStateColor(CP.STATE_NEUTRAL, 0, 10)
    expect.eq(untouched.r, 255)
    expect.eq(untouched.g, 255)
    expect.eq(untouched.b, 0)

    local halfTaken = CP.GetStateColor(CP.STATE_NEUTRAL, 5, 10)
    expect.truthy(halfTaken.r < untouched.r, "yellow should dim as the point is pushed off neutral")
end)

it("gives a fully opaque colour whatever the state", function()
    CP = TPG.ControlPoint
    for _, state in ipairs({ CP.STATE_GREEN, CP.STATE_RED, CP.STATE_NEUTRAL }) do
        expect.eq(CP.GetStateColor(state, 3, 10).a, 255)
    end
end)
