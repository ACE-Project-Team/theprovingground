--[[
    Team Definitions
]]

-- Colours come from the palette (config/sh_palette.lua) so the team green here,
-- the score bar, the point markers and the logo are all literally the same
-- value -- previously this was Color(0,255,0) while the mark used #00FF21, and
-- the scoreboard was a slightly different green to everything else on screen.
TPG.Teams = {
    [TEAM_UNASSIGNED] = {
        name    = "Unassigned",
        color   = Color(255, 255, 255),
        vector  = Vector(1, 1, 1),
    },
    [TEAM_GREEN] = {
        name    = "The Green Terror",
        color   = TPG.Colors.Green,
        vector  = Vector(0, 1, 0),
    },
    [TEAM_RED] = {
        name    = "The Red Menace",
        color   = TPG.Colors.Red,
        vector  = Vector(1, 0, 0),
    },
}

function TPG.SetupTeams()
    TPG._ownTeams = TPG._ownTeams or {}

    for id, data in pairs(TPG.Teams) do
        -- Safety net: never clobber a team another addon already registered
        -- (e.g. ULX UTeam role-teams). We only ever overwrite IDs we set up
        -- ourselves; if something else holds this ID, skip and warn.
        if team.Valid(id) and not TPG._ownTeams[id] then
            ErrorNoHalt("[TPG] Team ID " .. id .. " is already in use by another addon; " ..
                "skipping to avoid overwriting roles. Adjust TEAM_* in shared.lua.\n")
        else
            team.SetUp(id, data.name, data.color)
            TPG._ownTeams[id] = true
        end
    end
end

function TPG.GetEnemyTeam(teamId)
    if teamId == TEAM_GREEN then return TEAM_RED end
    if teamId == TEAM_RED then return TEAM_GREEN end
    return TEAM_UNASSIGNED
end

function TPG.GetTeamData(teamId)
    return TPG.Teams[teamId] or TPG.Teams[TEAM_UNASSIGNED]
end

TPG.SetupTeams()