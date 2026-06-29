--[[
    Custom Map Points (server)

    Admin-placed objective / spawn / flag points, saved per map under
    data/tpg/points/<map>.json and overlaid on the inline map config at load.
    This is what the point tool (weapon_tpg_pointtool) writes to.

    Point record: { type = "cp"|"koth"|"ctf"|"spawn", team = <id|nil>,
                    pos = {x,y,z}, name = <string|nil> }
]]

TPG.Maps = TPG.Maps or {}
TPG.Maps.Custom = TPG.Maps.Custom or {}   -- [mapName] = { points = {...} }

local DIR = "tpg/points"

local function path(mapName)
    return DIR .. "/" .. string.lower(mapName or game.GetMap()) .. ".json"
end

local function vToT(v) return { x = v.x, y = v.y, z = v.z } end
local function tToV(t) return Vector(t.x, t.y, t.z) end

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

local function getData(mapName)
    mapName = string.lower(mapName or game.GetMap())
    if not TPG.Maps.Custom[mapName] then TPG.Maps.LoadCustom(mapName) end
    return TPG.Maps.Custom[mapName]
end
TPG.Maps.GetCustomData = getData

function TPG.Maps.SaveCustom(mapName)
    mapName = string.lower(mapName or game.GetMap())
    file.CreateDir(DIR)
    file.Write(path(mapName), util.TableToJSON(getData(mapName), true))
end

-- ── Mutators (used by the point tool) ───────────────────────────────────────
function TPG.Maps.AddPoint(ptype, teamId, pos, name)
    local data = getData()
    table.insert(data.points, { type = ptype, team = teamId, pos = vToT(pos), name = name })
    TPG.Maps.SaveCustom()
end

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

function TPG.Maps.ClearPoints()
    getData().points = {}
    TPG.Maps.SaveCustom()
end

function TPG.Maps.CountPoints()
    return #getData().points
end

-- ── Resolvers ───────────────────────────────────────────────────────────────
-- The single neutral CTF flag point (first placed wins).
function TPG.Maps.GetCustomFlagPoint()
    for _, pt in ipairs(getData().points) do
        if pt.type == "ctf" then return tToV(pt.pos) end
    end
end

function TPG.Maps.GetCustomSpawn(teamId)
    for _, pt in ipairs(getData().points) do
        if pt.type == "spawn" and pt.team == teamId then return tToV(pt.pos) end
    end
end

-- Overlay custom points onto a freshly-loaded map config. Anything placed wins
-- over the inline config; untouched categories keep their defaults.
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

concommand.Add("tpg_points_clear", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[TPG] Superadmin only.")
        return
    end
    TPG.Maps.ClearPoints()
    local msg = "[TPG] Cleared all custom points for " .. game.GetMap() .. "."
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)
