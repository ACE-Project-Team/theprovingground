--[[
    Team Definitions
]]

TPG.Teams = {
    [TEAM_UNASSIGNED] = {
        name    = "Unassigned",
        color   = Color(255, 255, 255),
        vector  = Vector(1, 1, 1),
    },
    [TEAM_GREEN] = {
        name    = "The Green Terror",
        color   = Color(0, 255, 0),
        vector  = Vector(0, 1, 0),
    },
    [TEAM_RED] = {
        name    = "The Red Menace",
        color   = Color(255, 0, 0),
        vector  = Vector(1, 0, 0),
    },
}

function TPG.SetupTeams()
    for id, data in pairs(TPG.Teams) do
        team.SetUp(id, data.name, data.color)
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