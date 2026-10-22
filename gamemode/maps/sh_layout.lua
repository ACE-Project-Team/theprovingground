--[[--
    Map layouts: the point types the editor places, the settings it edits, and
    the pure functions that turn a saved layout into map config and back.

    A layout is what an admin builds in game with the point tool and the map
    editor (`tpg_mapedit`). It is saved per map by `maps/sv_custom_points.lua`
    as `data/tpg/points/<map>.json`:

        version   2
        points    list of { type, team, pos = {x,y,z}, name }
        settings  { points, weight, props, safezoneRadius, winsToMapVote,
                    capCP, capKOTH, displayName, voteList }

    `type` is one of the ids in @{TPG.Layout.Types}. `team` is `"green"` or
    `"red"` and only means something on a spawn. Teams are stored as names, not
    as `TEAM_GREEN`'s number: those numbers changed once already (1/2 became
    2001/2002 with the ULX fix), and a file keyed by the old ones silently
    stopped working. Old files are still read; see @{TPG.Layout.Normalize}.

    Every setting is optional, and an absent one leaves the map's own value in
    place. They are AUTHORED values, the same numbers `_loader.lua` holds, so
    the budget multipliers in `TPG.Maps.LimitMult` still apply on top and an
    exported layout pastes into `_loader.lua` unchanged.

    Shared so the client editor reads the same type and setting lists as the
    server, and so the offline tests can reach the pure parts.

    @module tpg.layout
    @realm shared
]]

TPG.Layout = TPG.Layout or {}

--- The point types the tool cycles through and the editor lists, in order.
-- Each is `{ key, id, team, label, mode, single, tint }`. `key` is unique per
-- entry (the two spawns share the id `"spawn"`). A `single` type has one point
-- per map (per team, for spawns): placing another moves it. The others are
-- lists, and `mode` is the game type whose objectives they become.
-- @realm shared
TPG.Layout.Types = {
    { key = "cp",        id = "cp",    label = "CONTROL POINT", mode = GAMEMODE_CP,   tint = Color(245, 245, 245) },
    { key = "koth",      id = "koth",  label = "KOTH HILL",     mode = GAMEMODE_KOTH, tint = Color(255, 210, 90) },
    { key = "rush",      id = "rush",  label = "RUSH STAGE",    mode = GAMEMODE_RUSH, tint = Color(110, 190, 255) },
    { key = "ctf",       id = "ctf",   label = "CTF FLAG",      single = true,        tint = Color(255, 140, 60) },
    { key = "spawn_green", id = "spawn", team = "green", label = "SPAWN - GREEN", single = true, tint = Color(60, 220, 95) },
    { key = "spawn_red",   id = "spawn", team = "red",   label = "SPAWN - RED",   single = true, tint = Color(220, 70, 70) },
}

--- The per-map settings the editor can change, in display order.
-- Each is `{ key, label, kind, min, max }`, `kind` being `"number"`, `"text"`
-- or `"choice"` (with `choices`). Limits are authored values, before
-- `TPG.Maps.LimitMult`.
-- @realm shared
TPG.Layout.Settings = {
    { key = "displayName",    label = "Name on the vote screen", kind = "text" },
    { key = "points",         label = "Point budget",            kind = "number", min = 0, max = 1000000 },
    { key = "weight",         label = "Weight limit (t)",        kind = "number", min = 0, max = 100000 },
    { key = "props",          label = "Prop limit",              kind = "number", min = 0, max = 10000 },
    { key = "safezoneRadius", label = "Safezone radius",         kind = "number", min = 100, max = 10000 },
    { key = "capCP",          label = "CP capture speed",        kind = "number", min = 0, max = 10 },
    { key = "capKOTH",        label = "KOTH capture speed",      kind = "number", min = 0, max = 10 },
    { key = "winsToMapVote",  label = "Rounds before map vote",  kind = "number", min = 1, max = 100 },
    { key = "voteList",       label = "In the map vote",         kind = "choice", choices = { "open", "urban" } },
}

local TEAM_NAMES = { green = true, red = true }

-- Every number TEAM_GREEN/TEAM_RED has ever been, so files saved before the
-- team ids moved still load.
local LEGACY_TEAMS = { [1] = "green", [2] = "red", [2001] = "green", [2002] = "red" }

--- A team as the layout stores it.
-- @param team `"green"`, `"red"`, `TEAM_GREEN`, `TEAM_RED`, or a pre-2001 id.
-- @treturn ?string `"green"`, `"red"`, or nil for anything else.
-- @realm shared
function TPG.Layout.TeamName(team)
    if team == TEAM_GREEN then return "green" end
    if team == TEAM_RED then return "red" end
    if isstring(team) and TEAM_NAMES[string.lower(team)] then return string.lower(team) end
    if isnumber(team) then return LEGACY_TEAMS[team] end
end

--- The team id for a stored team name.
-- @tparam ?string name `"green"` or `"red"`.
-- @treturn ?number `TEAM_GREEN`, `TEAM_RED`, or nil.
-- @realm shared
function TPG.Layout.TeamId(name)
    name = TPG.Layout.TeamName(name)
    if name == "green" then return TEAM_GREEN end
    if name == "red" then return TEAM_RED end
end

--- The @{TPG.Layout.Types} entry for a point type and team.
-- @tparam string id A type id.
-- @param[opt] team Only used for spawns; any form @{TPG.Layout.TeamName} takes.
-- @treturn ?table nil for an unknown id, or a spawn with no team.
-- @realm shared
function TPG.Layout.GetType(id, team)
    local teamName = TPG.Layout.TeamName(team)
    for _, t in ipairs(TPG.Layout.Types) do
        if t.id == id and (t.team == nil or t.team == teamName) then return t end
    end
end

--- The @{TPG.Layout.Settings} entry for a key.
-- @tparam string key
-- @treturn ?table
-- @realm shared
function TPG.Layout.GetSetting(key)
    for _, s in ipairs(TPG.Layout.Settings) do
        if s.key == key then return s end
    end
end

local function toVector(p)
    if isvector(p) then return p end
    if istable(p) and isnumber(p.x) and isnumber(p.y) and isnumber(p.z) then
        return Vector(p.x, p.y, p.z)
    end
end

--- Clean up a layout read from disk, in place.
-- Drops points of unknown types and spawns without a valid team, turns any
-- numeric team into its name, makes sure `points` and `settings` exist, and
-- stamps version 2. Safe on a table that is already clean.
-- @tparam ?table data The decoded JSON, or nil.
-- @treturn table The same table, or a new empty layout for nil.
-- @realm shared
function TPG.Layout.Normalize(data)
    data = istable(data) and data or {}

    local points = {}
    for _, pt in ipairs(istable(data.points) and data.points or {}) do
        local team = istable(pt) and TPG.Layout.TeamName(pt.team) or nil
        if istable(pt) and toVector(pt.pos) and TPG.Layout.GetType(pt.type, team) then
            points[#points + 1] = {
                type = pt.type,
                team = (pt.type == "spawn") and team or nil,
                pos  = pt.pos,
                name = isstring(pt.name) and pt.name ~= "" and pt.name or nil,
            }
        end
    end

    data.points   = points
    data.settings = istable(data.settings) and data.settings or {}
    data.version  = 2
    return data
end

--- The default name for the `n`th point of a type.
-- @tparam string id A type id.
-- @tparam number n 1-based position among points of that type.
-- @treturn string
-- @realm shared
function TPG.Layout.DefaultName(id, n)
    if id == "koth" then return n == 1 and "The Hill" or ("Hill " .. n) end
    if id == "rush" then return "Stage " .. n end
    return "Point " .. n
end

--[[--
    Overlay a layout onto a map config, in place.

    Settings first, then points. Every part is independent and only touched
    when the layout has something for it:

      * a spawn replaces that team's spawn;
      * any `cp`, `koth` or `rush` point replaces that mode's whole objective
        list with the layout's, in the layout's order (Rush plays an authored
        list in order instead of shuffling it, see `TPG.Rush.BuildStages`);
      * a `ctf` point becomes `config.ctfFlag`, the flag's fixed home.

    @tparam table config A merged map config, before `TPG.Maps.LimitMult`.
    @tparam table data A layout, as returned by @{TPG.Layout.Normalize}.
    @realm shared
]]
function TPG.Layout.Apply(config, data)
    local s = data.settings or {}

    config.limits = config.limits or {}
    if isnumber(s.points) then config.limits.points = s.points end
    if isnumber(s.weight) then config.limits.weight = s.weight end
    if isnumber(s.props)  then config.limits.props  = s.props end
    if isnumber(s.safezoneRadius) then config.safezoneRadius = s.safezoneRadius end
    if isnumber(s.winsToMapVote)  then config.winsToMapVote  = s.winsToMapVote end
    if isstring(s.displayName) and s.displayName ~= "" then config.displayName = s.displayName end
    if isnumber(s.capCP) then
        config[GAMEMODE_CP] = config[GAMEMODE_CP] or { objectives = {} }
        config[GAMEMODE_CP].capMultiplier = s.capCP
    end
    if isnumber(s.capKOTH) then
        config[GAMEMODE_KOTH] = config[GAMEMODE_KOTH] or { objectives = {} }
        config[GAMEMODE_KOTH].capMultiplier = s.capKOTH
    end

    local lists = { cp = {}, koth = {}, rush = {} }
    config.spawns = config.spawns or {}

    for _, pt in ipairs(data.points or {}) do
        local pos = toVector(pt.pos)
        if pt.type == "spawn" then
            local teamId = TPG.Layout.TeamId(pt.team)
            if teamId then config.spawns[teamId] = pos end
        elseif pt.type == "ctf" then
            config.ctfFlag = pos
        elseif lists[pt.type] then
            local list = lists[pt.type]
            list[#list + 1] = { pos = pos, name = pt.name or TPG.Layout.DefaultName(pt.type, #list + 1) }
        end
    end

    for id, list in pairs(lists) do
        if #list > 0 then
            local mode = TPG.Layout.GetType(id).mode
            config[mode] = config[mode] or {}
            config[mode].objectives = list
        end
    end
end

local function vec(v)
    return string.format("Vector(%d, %d, %d)", math.Round(v.x), math.Round(v.y), math.Round(v.z))
end

local function num(n)
    return string.format("%.10g", n)
end

local function objectiveBlock(lines, mode, block, withCap)
    lines[#lines + 1] = string.format("    [%s] = {", mode)
    if withCap then
        lines[#lines + 1] = "        capMultiplier = " .. num(block.capMultiplier or 0) .. ","
    end
    lines[#lines + 1] = "        objectives = {"
    for _, o in ipairs(block.objectives or {}) do
        lines[#lines + 1] = string.format("            { pos = %s, name = %q },", vec(o.pos), o.name or "")
    end
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "    },"
end

--[[--
    A map config as a block ready to paste into `TPG.Maps.Configs` in
    `maps/_loader.lua`.

    Writes spawns, limits, safezone, the optional per-map keys that are set,
    and the CP, KOTH, Rush and DM blocks. Positions are rounded to whole units.
    A map meant for the vote also needs adding to `TPG.Voting.MapLists`, which
    the header comment says.

    @tparam string mapName
    @tparam table config A merged map config, BEFORE `TPG.Maps.LimitMult`, so
     the limits written are authored values.
    @tparam[opt] string voteList `"open"` or `"urban"`, for the header comment.
    @treturn string
    @realm shared
]]
function TPG.Layout.Export(mapName, config, voteList)
    local lines = {}
    lines[#lines + 1] = "-- Exported by the TPG map editor. Paste into TPG.Maps.Configs in gamemode/maps/_loader.lua."
    if voteList == "open" or voteList == "urban" then
        lines[#lines + 1] = string.format("-- For the map vote, also add %q to TPG.Voting.MapLists.%s in gamemode/voting/sv_voting.lua.",
            mapName, voteList == "open" and "Open" or "Urban")
    end
    lines[#lines + 1] = string.format("[%q] = {", mapName)
    if config.displayName then
        lines[#lines + 1] = string.format("    displayName = %q,", config.displayName)
    end
    lines[#lines + 1] = "    spawns = {"
    lines[#lines + 1] = "        [TEAM_GREEN] = " .. vec(config.spawns[TEAM_GREEN]) .. ","
    lines[#lines + 1] = "        [TEAM_RED]   = " .. vec(config.spawns[TEAM_RED]) .. ","
    lines[#lines + 1] = "    },"

    local l = config.limits or {}
    lines[#lines + 1] = "    limits = {"
    lines[#lines + 1] = "        weight = " .. num(l.weight or 0) .. ","
    lines[#lines + 1] = "        props = " .. num(l.props or 0) .. ","
    lines[#lines + 1] = "        points = " .. num(l.points or 0) .. ","
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    safezoneRadius = " .. num(config.safezoneRadius or 750) .. ","
    if config.winsToMapVote then
        lines[#lines + 1] = "    winsToMapVote = " .. num(config.winsToMapVote) .. ","
    end
    if config.ctfFlag then
        lines[#lines + 1] = "    ctfFlag = " .. vec(config.ctfFlag) .. ","
    end
    lines[#lines + 1] = ""

    objectiveBlock(lines, "GAMEMODE_CP", config[GAMEMODE_CP] or {}, true)
    objectiveBlock(lines, "GAMEMODE_KOTH", config[GAMEMODE_KOTH] or {}, true)
    local rush = config[GAMEMODE_RUSH]
    if rush and rush.objectives and #rush.objectives > 0 then
        objectiveBlock(lines, "GAMEMODE_RUSH", rush, false)
    end
    lines[#lines + 1] = "    [GAMEMODE_DM] = {"
    lines[#lines + 1] = "        capMultiplier = 0,"
    lines[#lines + 1] = "        objectives = {},"
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "},"

    return table.concat(lines, "\n")
end

local function teamLabel(teamId)
    return teamId == TEAM_GREEN and "Green" or "Red"
end

--[[--
    Layout problems that can be found from positions alone.

    Missing spawns, safezones that overlap, objectives or the CTF flag inside
    either safezone (a capture nobody can contest), and a map with no control
    points. The checks that need the world (inside a wall, out of the map,
    floating) are server-side, in `maps/sv_mapedit.lua`.

    @tparam table config A merged map config.
    @treturn {string,...} Player-facing warnings; empty when nothing is wrong.
    @realm shared
]]
function TPG.Layout.Check(config)
    local warnings = {}
    local radius = config.safezoneRadius or TPG.Config.safezoneRadius or 750
    local spawns = config.spawns or {}

    for _, teamId in ipairs({ TEAM_GREEN, TEAM_RED }) do
        local s = spawns[teamId]
        if not isvector(s) or s == Vector(0, 0, 0) then
            warnings[#warnings + 1] = teamLabel(teamId) .. " has no spawn."
        end
    end

    local g, r = spawns[TEAM_GREEN], spawns[TEAM_RED]
    if isvector(g) and isvector(r) and g:Distance(r) < radius * 2 then
        warnings[#warnings + 1] = string.format(
            "The safezones overlap - the spawns are %d units apart, they need %d.",
            math.Round(g:Distance(r)), radius * 2)
    end

    local function inSafezone(pos, what)
        for _, teamId in ipairs({ TEAM_GREEN, TEAM_RED }) do
            local s = spawns[teamId]
            if isvector(s) and pos:Distance(s) < radius then
                warnings[#warnings + 1] = what .. " is inside the " .. teamLabel(teamId) .. " safezone."
            end
        end
    end

    for _, entry in ipairs({ { GAMEMODE_CP, "Control point" }, { GAMEMODE_KOTH, "KOTH hill" }, { GAMEMODE_RUSH, "Rush stage" } }) do
        local block = config[entry[1]]
        for i, o in ipairs(block and block.objectives or {}) do
            inSafezone(o.pos, string.format("%s %d (%s)", entry[2], i, o.name or "?"))
        end
    end
    if isvector(config.ctfFlag) then inSafezone(config.ctfFlag, "The CTF flag") end

    local cp = config[GAMEMODE_CP]
    if not (cp and cp.objectives and #cp.objectives > 0) then
        warnings[#warnings + 1] = "No control points - Control Points and Rush rounds have nothing to capture."
    end

    return warnings
end
