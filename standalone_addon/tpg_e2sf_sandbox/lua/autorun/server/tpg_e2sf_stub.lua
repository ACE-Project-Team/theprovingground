--[[
    TPG E2/SF Sandbox Test Stub

    The E2/SF functions in this same addon (core/custom/tpg.lua, libs_sv/tpg.lua)
    read TEAM_GREEN/TEAM_RED, TPG.GetTeamData and the engine team roster -- all
    of which are normally set up by the TPG gamemode itself. That's fine while
    TPG is running, but this folder is a REAL addon (mounted regardless of
    active gamemode) specifically so those chip functions are reachable in
    plain sandbox too, where none of that setup ever runs.

    So: if the real gamemode is already up (TPG.State exists), get out of the
    way entirely -- this stub must never shadow real match data. Otherwise, set
    up just enough of a fake team so a chip can be pointed at tpgTeamCount() /
    tpg.getRoster() etc. and see it return something, via tpg_test_team.
]]

if TPG and TPG.State then return end

TEAM_GREEN = TEAM_GREEN or 2001
TEAM_RED   = TEAM_RED or 2002

TPG = TPG or {}
TPG.GetTeamData = TPG.GetTeamData or function(t)
    if t == TEAM_GREEN then return { name = "GREEN (test)", color = Color(100, 255, 100) } end
    if t == TEAM_RED   then return { name = "RED (test)",   color = Color(255, 100, 100) } end
    return { name = "", color = color_white }
end

if team.GetName(TEAM_GREEN) == "Unknown" then
    team.SetUp(TEAM_GREEN, "GREEN (test)", Color(100, 255, 100))
    team.SetUp(TEAM_RED,   "RED (test)",   Color(255, 100, 100))
end

concommand.Add("tpg_test_team", function(ply, _, args)
    if not IsValid(ply) then return end
    if TPG and TPG.State then
        ply:ChatPrint("[TPG test] TPG is actually running -- use the real team menu (F2), not this.")
        return
    end

    local want = string.lower(args[1] or "")
    local t = (want == "green" and TEAM_GREEN) or (want == "red" and TEAM_RED) or 0
    ply:SetTeam(t)
    ply:ChatPrint("[TPG test] Fake team set to " .. (want ~= "" and want or "none") ..
        " -- for wiring up tpgTeamCount()/tpg.getRoster() etc. in sandbox. Not the real gamemode.")
end, nil, "TPG E2/SF sandbox testing: fake your team so tpg* E2/SF/SF functions return non-empty data. Usage: tpg_test_team <green|red|none>")
