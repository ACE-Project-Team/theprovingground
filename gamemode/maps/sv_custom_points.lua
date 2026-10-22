--[[--
    Custom map layouts: the points and settings an admin builds in game.

    Saved per map under `data/tpg/points/<map>.json` and overlaid onto the map
    config every time it loads (`TPG.Maps.BuildConfig`). The file format and
    the pure overlay live in @{tpg.layout}; this file owns the disk and the
    edits. The point tool and the map editor (`maps/sv_mapedit.lua`) are the
    only callers that change anything, and both go through the functions
    below so the file is saved after every change.

    Points are addressed by their index in the layout's `points` list. Indexes
    shift when a point is removed, so hold one only for the length of a single
    edit.

    A `cp`, `koth` or `rush` category in the layout replaces the map's own
    list for that mode wholesale. So the first edit to one of those categories
    copies the map's built-in points into the layout before it changes
    anything (@{TPG.Maps.ImportBuiltin}): adding a point to a configured map
    adds it to the points that are already there, instead of quietly
    replacing them all with the one you just placed.

    @module tpg.custompoints
    @realm server
]]

TPG.Maps = TPG.Maps or {}
TPG.Maps.Custom = TPG.Maps.Custom or {}   -- [mapName] = layout

local DIR = "tpg/points"

--- The DATA-folder path a map's saved layout is stored at. Shared with
-- @{tpg.collection.server}, which checks whether a map has a layout without
-- loading it.
-- @tparam[opt] string mapName Defaults to the running map.
-- @treturn string e.g. `"tpg/points/gm_construct.json"`.
-- @realm server
function TPG.Maps.LayoutPath(mapName)
    return DIR .. "/" .. string.lower(mapName or game.GetMap()) .. ".json"
end

local path = TPG.Maps.LayoutPath

local function vToT(v) return { x = v.x, y = v.y, z = v.z } end
local function tToV(t) return Vector(t.x, t.y, t.z) end

--- Load a map's saved layout from disk into `TPG.Maps.Custom`, replacing
-- whatever was cached for it. A missing file is not an error: it just means
-- nothing has been placed yet, and yields an empty layout. Files saved before
-- teams were stored by name are converted on read (see
-- @{TPG.Layout.Normalize}).
-- @tparam[opt] string mapName Defaults to the running map.
-- @treturn table The loaded (or freshly created) layout.
-- @realm server
function TPG.Maps.LoadCustom(mapName)
    mapName = string.lower(mapName or game.GetMap())

    local p = path(mapName)
    local raw = file.Exists(p, "DATA") and util.JSONToTable(file.Read(p, "DATA") or "") or nil
    TPG.Maps.Custom[mapName] = TPG.Layout.Normalize(raw)

    return TPG.Maps.Custom[mapName]
end

-- The cached layout for a map, loading it from disk on first use.
local function getData(mapName)
    mapName = string.lower(mapName or game.GetMap())
    if not TPG.Maps.Custom[mapName] then TPG.Maps.LoadCustom(mapName) end
    return TPG.Maps.Custom[mapName]
end

--- The cached layout for a map, loading it from disk on first use.
-- @function TPG.Maps.GetCustomData
-- @tparam[opt] string mapName Defaults to the running map.
-- @treturn table The map's layout (see @{tpg.layout}).
-- @realm server
TPG.Maps.GetCustomData = getData

--- Write a map's current in-memory layout back to `data/tpg/points/<map>.json`.
-- Called by every mutator below; a caller only needs this directly if it
-- edited `TPG.Maps.Custom[mapName]` by hand.
-- @tparam[opt] string mapName Defaults to the running map.
-- @realm server
function TPG.Maps.SaveCustom(mapName)
    mapName = string.lower(mapName or game.GetMap())
    file.CreateDir(DIR)
    file.Write(path(mapName), util.TableToJSON(getData(mapName), true))
end

local function countType(data, ptype)
    local n = 0
    for _, pt in ipairs(data.points) do
        if pt.type == ptype then n = n + 1 end
    end
    return n
end

--- Copy the map's built-in points for a category into the layout.
-- Does nothing if the layout already has points of that type, or if the map
-- has no entry in `TPG.Maps.Configs` (the generic defaults are not worth
-- copying: they are one point at the map origin). Only list types (`cp`,
-- `koth`, `rush`) have anything to copy.
-- @tparam string ptype `"cp"`, `"koth"` or `"rush"`.
-- @treturn number How many points were copied.
-- @realm server
function TPG.Maps.ImportBuiltin(ptype)
    local data = getData()
    local t = TPG.Layout.GetType(ptype)
    local authored = TPG.Maps.Configs[game.GetMap()]
    if not (t and t.mode and authored) or countType(data, ptype) > 0 then return 0 end

    local block = authored[t.mode]
    local n = 0
    for _, o in ipairs(block and block.objectives or {}) do
        table.insert(data.points, { type = ptype, pos = vToT(o.pos), name = o.name })
        n = n + 1
    end

    if n > 0 then TPG.Maps.SaveCustom() end
    return n
end

-- ── Mutators (used by the point tool and the map editor) ───────────────────

--[[--
    Add a point to the running map's layout and save.

    A single type (the CTF flag, and each team's spawn) has one point per map,
    so placing another MOVES the existing one instead of adding a second. A
    list type gets the map's built-in points copied in first, if it has none
    of its own yet (@{TPG.Maps.ImportBuiltin}).

    @tparam string ptype A @{TPG.Layout.Types} id.
    @param[opt] team For spawns: `"green"`, `"red"`, `TEAM_GREEN` or `TEAM_RED`.
    @tparam Vector pos World position.
    @tparam[opt] string name Label; a default one is used when it is read.
    @treturn ?number The point's index, or nil for an unknown type.
    @treturn number How many built-in points were copied in first.
    @realm server
]]
function TPG.Maps.AddPoint(ptype, team, pos, name)
    local t = TPG.Layout.GetType(ptype, team)
    if not t then return nil, 0 end

    local data = getData()
    local record = { type = ptype, team = t.team, pos = vToT(pos), name = name }

    if t.single then
        for i, pt in ipairs(data.points) do
            if pt.type == ptype and pt.team == t.team then
                data.points[i] = record
                TPG.Maps.SaveCustom()
                return i, 0
            end
        end
    end

    local imported = t.single and 0 or TPG.Maps.ImportBuiltin(ptype)
    table.insert(data.points, record)
    TPG.Maps.SaveCustom()
    return #data.points, imported
end

--- Remove the point at an index and save.
-- @tparam number index
-- @treturn ?table The removed record, or nil if there was none.
-- @realm server
function TPG.Maps.RemovePoint(index)
    local data = getData()
    local removed = data.points[index]
    if not removed then return nil end

    table.remove(data.points, index)
    TPG.Maps.SaveCustom()
    return removed
end

--- The index of the placed point closest to `pos`, within `radius`.
-- @tparam Vector pos Search origin (typically an eye-trace hit).
-- @tparam[opt=250] number radius Search radius in units.
-- @tparam[opt] string ptype Only consider this type.
-- @param[opt] team With `ptype = "spawn"`, only this team's spawn.
-- @treturn ?number nil if nothing matching is in range.
-- @realm server
function TPG.Maps.FindNearest(pos, radius, ptype, team)
    local teamName = TPG.Layout.TeamName(team)
    local bestIdx, bestDist

    for i, pt in ipairs(getData().points) do
        if (not ptype or pt.type == ptype) and (not teamName or pt.team == teamName) then
            local d = tToV(pt.pos):Distance(pos)
            if d <= (radius or 250) and (not bestDist or d < bestDist) then
                bestDist, bestIdx = d, i
            end
        end
    end

    return bestIdx
end

--- Remove whichever placed point is closest to `pos`, within `radius`.
-- @tparam Vector pos Search origin.
-- @tparam[opt=250] number radius Search radius in units.
-- @tparam[opt] string ptype Only remove a point of this type.
-- @param[opt] team With `ptype = "spawn"`, only this team's spawn.
-- @treturn ?table The removed record, or nil if nothing matching was in range.
-- @realm server
function TPG.Maps.RemoveNearest(pos, radius, ptype, team)
    local idx = TPG.Maps.FindNearest(pos, radius, ptype, team)
    return idx and TPG.Maps.RemovePoint(idx) or nil
end

--- Move the point at an index and save.
-- @tparam number index
-- @tparam Vector pos
-- @treturn boolean false if there is no such point.
-- @realm server
function TPG.Maps.MovePoint(index, pos)
    local pt = getData().points[index]
    if not pt then return false end

    pt.pos = vToT(pos)
    TPG.Maps.SaveCustom()
    return true
end

--- Rename the point at an index and save. An empty name goes back to the
-- default one.
-- @tparam number index
-- @tparam ?string name
-- @treturn boolean false if there is no such point.
-- @realm server
function TPG.Maps.RenamePoint(index, name)
    local pt = getData().points[index]
    if not pt then return false end

    name = isstring(name) and string.Trim(name) or ""
    pt.name = name ~= "" and string.sub(name, 1, 40) or nil
    TPG.Maps.SaveCustom()
    return true
end

--- Swap a point with the previous (`dir = -1`) or next (`dir = 1`) point of
-- the same type, and save. Order matters for Rush, which plays an authored
-- list in order, and for the default "Point N" names.
-- @tparam number index
-- @tparam number dir -1 or 1.
-- @treturn ?number The point's new index, or nil if it could not move.
-- @realm server
function TPG.Maps.ShiftPoint(index, dir)
    local points = getData().points
    local pt = points[index]
    if not pt then return nil end

    local j = index + dir
    while points[j] and points[j].type ~= pt.type do j = j + dir end
    if not points[j] then return nil end

    points[index], points[j] = points[j], points[index]
    TPG.Maps.SaveCustom()
    return j
end

--[[--
    Set one per-map setting and save. nil (or an empty string) clears it, so
    the map's own value applies again.

    Numbers are clamped to the range the setting allows, and anything that
    does not fit the setting's kind is refused rather than saved.

    @tparam string key A @{TPG.Layout.Settings} key.
    @param value
    @treturn boolean false if the key is unknown or the value does not fit.
    @realm server
]]
function TPG.Maps.SetSetting(key, value)
    local def = TPG.Layout.GetSetting(key)
    if not def then return false end

    if value == "" then value = nil end
    if value ~= nil then
        if def.kind == "number" then
            value = tonumber(value)
            if not value then return false end
            value = math.Clamp(value, def.min or -math.huge, def.max or math.huge)
        elseif def.kind == "choice" then
            if not table.HasValue(def.choices, value) then return false end
        else
            value = string.sub(tostring(value), 1, 40)
        end
    end

    getData().settings[key] = value
    TPG.Maps.SaveCustom()
    return true
end

--- Delete placed points for the running map and save. Settings are kept.
-- @tparam[opt] string ptype Only this type; nil deletes every point.
-- @param[opt] team With `ptype = "spawn"`, only this team's spawn.
-- @realm server
function TPG.Maps.ClearPoints(ptype, team)
    local data = getData()
    local teamName = TPG.Layout.TeamName(team)

    if not ptype then
        data.points = {}
    else
        for i = #data.points, 1, -1 do
            local pt = data.points[i]
            if pt.type == ptype and (not teamName or pt.team == teamName) then
                table.remove(data.points, i)
            end
        end
    end

    TPG.Maps.SaveCustom()
end

--- Delete the running map's whole layout, points and settings.
-- @realm server
function TPG.Maps.ClearLayout()
    TPG.Maps.Custom[string.lower(game.GetMap())] = TPG.Layout.Normalize(nil)
    TPG.Maps.SaveCustom()
end

--- How many points are placed on the running map.
-- @treturn number
-- @realm server
function TPG.Maps.CountPoints()
    return #getData().points
end

-- ── Resolvers ───────────────────────────────────────────────────────────────

--- The placed CTF flag point, if there is one.
-- @treturn ?Vector
-- @realm server
function TPG.Maps.GetCustomFlagPoint()
    for _, pt in ipairs(getData().points) do
        if pt.type == "ctf" then return tToV(pt.pos) end
    end
end

--- A team's placed spawn, if there is one.
-- @param team `TEAM_GREEN`, `TEAM_RED`, `"green"` or `"red"`.
-- @treturn ?Vector
-- @realm server
function TPG.Maps.GetCustomSpawn(team)
    local teamName = TPG.Layout.TeamName(team)
    for _, pt in ipairs(getData().points) do
        if pt.type == "spawn" and pt.team == teamName then return tToV(pt.pos) end
    end
end

--- Overlay a map's layout onto a freshly merged map config, in place.
-- Called from `TPG.Maps.BuildConfig`; the rules are @{TPG.Layout.Apply}'s.
-- @tparam table config The merged map config to mutate.
-- @tparam[opt] string mapName Defaults to the running map.
-- @realm server
function TPG.Maps.ApplyCustomPoints(config, mapName)
    TPG.Layout.Apply(config, getData(mapName))
end

--- Maps with a saved layout that asks to be in the map vote.
-- Reads every file in `data/tpg/points/`, so it is for the vote, not a hot
-- path.
-- @treturn table `{ open = {map,...}, urban = {map,...} }`.
-- @realm server
function TPG.Maps.LayoutVoteMaps()
    local out = { open = {}, urban = {} }
    for _, f in ipairs(file.Find(DIR .. "/*.json", "DATA") or {}) do
        local mapName = string.StripExtension(f)
        local list = getData(mapName).settings.voteList
        if out[list] then table.insert(out[list], mapName) end
    end
    return out
end
