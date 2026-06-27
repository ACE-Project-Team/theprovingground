--[[
    ULX / UTeam compatibility

    ULX's "Manage Teams" (UTeam, ulx/modules/uteam.lua) binds usergroups to GMod
    teams and FORCES group members onto them on every spawn:

        hook.Add("PlayerSpawn", "UTeamSpawnAuth", assignTeam, HOOK_MONITOR_HIGH)
        hook.Add("UCLAuthed",   "UTeamAuth",      assignTeam, HOOK_MONITOR_HIGH)

    In a team gamemode that fights TPG's own GREEN/RED assignment -- e.g. a
    superadmin keeps getting yanked onto their "superadmin" team, so TPG reports
    "not on a team". We strip those enforcement hooks while TPG is active. The
    teams themselves stay registered (rank scoreboards still colour correctly),
    UTeam just stops reassigning players. This file only loads under TPG, so
    UTeam behaves normally again under sandbox.
]]

function TPG.DisableExternalTeamForcing()
    -- ULX UTeam
    hook.Remove("PlayerSpawn", "UTeamSpawnAuth")
    hook.Remove("UCLAuthed",  "UTeamAuth")
end

-- UTeam installs its hooks during the "Initialize" hook (MONITOR_HIGH) and on
-- every team refresh. InitPostEntity runs after Initialize, so strip there for
-- map start; round starts re-strip as a safety net against mid-match team edits.
hook.Add("InitPostEntity", "TPG_DisableUTeamForcing", TPG.DisableExternalTeamForcing)

-- Extra insurance if Initialize already fired before this loaded (Lua refresh).
timer.Simple(5, TPG.DisableExternalTeamForcing)
