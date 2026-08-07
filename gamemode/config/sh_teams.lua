--[[--
    The two playing teams, plus the display entry for unassigned/spectators.

    `TPG.Teams` is keyed by the `TEAM_*` constants from @{tpg} (shared.lua):
    `TEAM_UNASSIGNED`, `TEAM_GREEN`, `TEAM_RED`. Each entry has:

        name    display name, used on the scoreboard and in chat/HUD text
        color   Color, used for scoreboard rows, score bars, point markers
        vector  a unit-ish Vector version of the colour, used wherever a
                system wants the team colour as a Vector rather than a Color
                (e.g. shader/material params)

    Colours come from the palette (`config/sh_palette.lua`) so the team green
    here, the score bar, the point markers and the logo are all literally the
    same value; previously this was `Color(0,255,0)` while the mark used
    `#00FF21`, and the scoreboard was a slightly different green to everything
    else on screen.

    `TPG.SetupTeams()` runs once at the bottom of this file to register these
    with the engine's `team` library, and again from other code if teams need
    to be rebuilt.

    Keyed entries: `TEAM_UNASSIGNED` is white, for no team picked yet or a
    spectator; `TEAM_GREEN` is "The Green Terror" in the palette's brand
    green; `TEAM_RED` is "The Red Menace" in the palette's brand red.

    @module tpg.teams
    @realm shared
]]
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

--[[--
    Register `TPG.Teams` with the engine's `team` library.

    Safety net: never clobber a team another addon already registered (e.g.
    ULX UTeam role-teams). This only ever overwrites an ID it set up itself;
    if `team.Valid(id)` is already true and `TPG._ownTeams[id]` is not set,
    that means something else holds this ID, so it skips that entry and warns
    instead of stomping it.

    That check only bites on the FIRST call for a given ID: once TPG has
    registered a team, `TPG._ownTeams[id]` stays true, so a later call (e.g.
    a hot reload) re-runs `team.SetUp` for it unconditionally rather than
    tripping the "already in use" branch again. Runs once automatically at
    the bottom of this file; safe to call again if teams ever need rebuilding.

    @realm shared
]]
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

--- The opposing playing team.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @treturn number TEAM_RED for TEAM_GREEN, TEAM_GREEN for TEAM_RED, and
--  TEAM_UNASSIGNED for anything else (spectators included; there is no
--  "enemy" of a team that isn't playing).
-- @realm shared
function TPG.GetEnemyTeam(teamId)
    if teamId == TEAM_GREEN then return TEAM_RED end
    if teamId == TEAM_RED then return TEAM_GREEN end
    return TEAM_UNASSIGNED
end

--- Look up a team's display entry.
-- Never returns nil: an unrecognised id falls back to the TEAM_UNASSIGNED
-- entry, so callers can read `.name`/`.color` off the result without guarding.
-- @tparam number teamId
-- @treturn table The matching entry from `TPG.Teams`.
-- @realm shared
function TPG.GetTeamData(teamId)
    return TPG.Teams[teamId] or TPG.Teams[TEAM_UNASSIGNED]
end

TPG.SetupTeams()