--[[--
    Custom map points: admin-placed objective, spawn and flag points.

    Saved per map under `data/tpg/points/<map>.json` and overlaid onto the
    inline map config (@{tpg.maps}) every time it loads. This is what the point
    tool (`weapon_tpg_pointtool`) writes to at runtime, so an admin can lay out
    control points, a KOTH hill, the CTF flag home and team spawns without
    touching `_loader.lua` and restarting the server -- `tpg_points_reload`
    (below) rebuilds the round from whatever is on disk right now.

    Point record shape: `{ type = "cp"|"koth"|"ctf"|"spawn", team = <id|nil>,
    pos = {x,y,z}, name = <string|nil> }`. Positions are stored as plain
    `{x,y,z}` tables (JSON has no Vector type) and converted back on read.

    @module tpg.custompoints
    @realm server
]]

TPG.Maps = TPG.Maps or {}
TPG.Maps.Custom = TPG.Maps.Custom or {}   -- [mapName] = { points = {...} }

local DIR = "tpg/points"

local function path(mapName)
    return DIR .. "/" .. string.lower(mapName or game.GetMap()) .. ".json"
end

local function vToT(v) return { x = v.x, y = v.y, z = v.z } end
local function tToV(t) return Vector(t.x, t.y, t.z) end

--- Load a map's saved points from disk into `TPG.Maps.Custom`, replacing
-- whatever was cached for it. A missing file is not an error: it just means no
-- points have been placed yet, and yields an empty `{ points = {} }` record.
-- @tparam[opt] string mapName Defaults to the running map.
-- @treturn table The loaded (or freshly created) `{ points = {...} }` record.
-- @realm server
function TPG.Maps.LoadCustom(mapName)
    mapName = string.lower(mapName or game.GetMap())

    local p = path(mapName)
    if file.Exists(p, "DATA") then
        local data = util.JSONToTable(file.Read(p, "DATA") or "") or {}
        data.points = data.points or {}
        TPG.Maps.Custom[mapName] = data
    else
        TPG.Maps.Custom[mapName] = { points = {} }
    end

    return TPG.Maps.Custom[mapName]
end

-- The cached record for a map, loading it from disk on first use. Every
-- mutator and resolver in this file goes through this so a cold cache never
-- has to be special-cased at each call site.
local function getData(mapName)
    mapName = string.lower(mapName or game.GetMap())
    if not TPG.Maps.Custom[mapName] then TPG.Maps.LoadCustom(mapName) end
    return TPG.Maps.Custom[mapName]
end
--- Alias for the internal cache-or-load lookup used throughout this file.
-- @function TPG.Maps.GetCustomData
-- @tparam[opt] string mapName Defaults to the running map.
-- @treturn table The map's `{ points = {...} }` record.
-- @realm server
TPG.Maps.GetCustomData = getData

--- Write a map's current in-memory points back to `data/tpg/points/<map>.json`.
-- Called automatically by every mutator below; a caller only needs this
-- directly if it edited `TPG.Maps.Custom[mapName]` by hand.
-- @tparam[opt] string mapName Defaults to the running map.
-- @realm server
function TPG.Maps.SaveCustom(mapName)
    mapName = string.lower(mapName or game.GetMap())
    file.CreateDir(DIR)
    file.Write(path(mapName), util.TableToJSON(getData(mapName), true))
end

-- ── Mutators (used by the point tool) ───────────────────────────────────────

--- Append a point to the running map's list and save immediately.
-- No de-duplication: placing the same type/position twice yields two records,
-- which for `"ctf"` matters because @{TPG.Maps.GetCustomFlagPoint} always
-- returns the first one in list order (the first ever placed), silently
-- ignoring any later ones.
-- @tparam string ptype One of `"cp"`, `"koth"`, `"ctf"`, `"spawn"`.
-- @tparam ?number teamId Only meaningful for `"spawn"`; nil otherwise.
-- @tparam Vector pos World position.
-- @tparam ?string name Optional label; falls back to a generated one when read.
-- @realm server
function TPG.Maps.AddPoint(ptype, teamId, pos, name)
    local data = getData()
    table.insert(data.points, { type = ptype, team = teamId, pos = vToT(pos), name = name })
    TPG.Maps.SaveCustom()
end

--- Remove whichever placed point is closest to `pos`, within `radius`.
-- Used by the point tool's Reload (R) action to delete the point you're aiming
-- near. Ties are not resolved by placement order -- `<` only replaces the best
-- match on a strictly closer distance, so the first-seen point wins a tie.
-- @tparam Vector pos Search origin (typically an eye-trace hit).
-- @tparam[opt=250] number radius Search radius in units.
-- @treturn ?table The removed point record, or nil if nothing was in range.
-- @realm server
function TPG.Maps.RemoveNearest(pos, radius)
    local data = getData()
    local bestIdx, bestDist

    for i, pt in ipairs(data.points) do
        local d = tToV(pt.pos):Distance(pos)
        if d <= (radius or 250) and (not bestDist or d < bestDist) then
            bestDist, bestIdx = d, i
        end
    end

    if not bestIdx then return nil end

    local removed = data.points[bestIdx]
    table.remove(data.points, bestIdx)
    TPG.Maps.SaveCustom()
    return removed
end

--- Delete every placed point for the running map and save the empty list.
-- @realm server
function TPG.Maps.ClearPoints()
    getData().points = {}
    TPG.Maps.SaveCustom()
end

--- How many points are placed on the running map.
-- @treturn number
-- @realm server
function TPG.Maps.CountPoints()
    return #getData().points
end

-- ── Resolvers ───────────────────────────────────────────────────────────────

--- The single neutral CTF flag point, if an admin placed one.
-- First placed wins: if more than one `"ctf"` point was ever added (see the
-- de-duplication note on @{TPG.Maps.AddPoint}), every one after the first is
-- silently ignored. Consumed by `tpg.ctf`'s `GetFlagPoint`/`RollFlagPoint`,
-- which treat a custom point as an override that always beats the roll.
-- @treturn ?Vector nil if no CTF point has been placed.
-- @realm server
function TPG.Maps.GetCustomFlagPoint()
    for _, pt in ipairs(getData().points) do
        if pt.type == "ctf" then return tToV(pt.pos) end
    end
end

--- A team's custom spawn point, if an admin placed one for that team.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @treturn ?Vector nil if no spawn was placed for that team.
-- @realm server
function TPG.Maps.GetCustomSpawn(teamId)
    for _, pt in ipairs(getData().points) do
        if pt.type == "spawn" and pt.team == teamId then return tToV(pt.pos) end
    end
end

--[[--
    Overlay a map's admin-placed points onto a freshly-loaded map config.

    Called from `tpg.maps`' `Load` right after it merges the map's inline
    config over the defaults, so placed points always win over what is
    authored in `_loader.lua`. Mutates `config` in place; returns nothing.

    Each category is independent and only touched if something was placed for
    it: a map with only custom spawns leaves `config[GAMEMODE_CP]` and
    `config[GAMEMODE_KOTH]` exactly as the inline config or defaults left them.
    When there ARE placed `"cp"` or `"koth"` points, the whole objective list
    for that mode is replaced wholesale (not merged) with the placed ones.

    @tparam table config The merged map config to mutate (`TPG.Maps.Current`).
    @tparam[opt] string mapName Defaults to the running map.
    @realm server
]]
function TPG.Maps.ApplyCustomPoints(config, mapName)
    local data = getData(mapName)
    if not data or #data.points == 0 then return end

    -- Spawns
    local gs, rs = TPG.Maps.GetCustomSpawn(TEAM_GREEN), TPG.Maps.GetCustomSpawn(TEAM_RED)
    if gs then config.spawns[TEAM_GREEN] = gs end
    if rs then config.spawns[TEAM_RED]  = rs end

    -- Control-point / KOTH objective lists
    local cps, koths = {}, {}
    for _, pt in ipairs(data.points) do
        if pt.type == "cp" then
            cps[#cps + 1] = { pos = tToV(pt.pos), name = pt.name or ("Point " .. (#cps + 1)) }
        elseif pt.type == "koth" then
            koths[#koths + 1] = { pos = tToV(pt.pos), name = pt.name or "The Hill" }
        end
    end

    if #cps > 0 then
        config[GAMEMODE_CP] = config[GAMEMODE_CP] or {}
        config[GAMEMODE_CP].objectives = cps
    end
    if #koths > 0 then
        config[GAMEMODE_KOTH] = config[GAMEMODE_KOTH] or {}
        config[GAMEMODE_KOTH].objectives = koths
    end
end

-- ── Admin: apply placed points to a live round ──────────────────────────────

-- Reload this map's points from disk and restart the round with them applied.
-- Admin-gated when run by a player; a valid `ply` that fails IsAdmin is
-- refused, but an invalid `ply` (server console) always passes, since there is
-- no player to check.
concommand.Add("tpg_points_reload", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[TPG] Admin only.")
        return
    end

    TPG.Maps.LoadCustom()
    TPG.Maps.Load()
    if TPG.Rounds and TPG.Rounds.Setup then TPG.Rounds.Setup() end

    local msg = "[TPG] Reloaded custom points and restarted the round (" ..
        TPG.Maps.CountPoints() .. " placed)."
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)

-- Wipe every placed point for the running map. Superadmin-gated the same way
-- tpg_points_reload is admin-gated: only a valid non-superadmin player is
-- refused, console is always allowed. Does NOT restart the round -- points
-- already applied to TPG.Maps.Current stay in effect until the next reload.
concommand.Add("tpg_points_clear", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[TPG] Superadmin only.")
        return
    end
    TPG.Maps.ClearPoints()
    local msg = "[TPG] Cleared all custom points for " .. game.GetMap() .. "."
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)
