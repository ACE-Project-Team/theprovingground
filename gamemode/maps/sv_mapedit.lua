--[[--
    The map editor, server side: what admins see, and every edit they make.

    The layout itself is stored by @{tpg.custompoints}; this file is the admin
    interface on top of it. Two ways in:

      * the point tool (`weapon_tpg_pointtool`), for placing, moving and
        removing points by aiming at the world;
      * the editor panel (`tpg_mapedit`, `ui/cl_mapedit.lua`), for everything
        else: renaming, reordering, the per-map settings, previews and export.

    Both send their edits here, every edit is saved at once, and every admin
    is sent the new state (@{TPG.MapEdit.Push}) so the in-world overlay and
    the panel never show a stale layout. Each edit is then put in play: the
    round restarts as a preview (`tpg_points_reload [mode]`, nobody killed,
    builds kept) a second after the last edit, in the mode of the point that
    changed. An admin who sets `tpg_mapedit_live 0` gets the command to type
    instead.

    The state an admin is sent lists the layout as it will play: the map's
    built-in points for any category the layout does not override, marked as
    such, and the layout's own points for the rest. Editing a built-in point
    copies it into the layout first, so built-in and placed points can be
    treated the same from the panel.

    @module tpg.mapedit
    @realm server
]]

TPG.MapEdit = TPG.MapEdit or {}

util.AddNetworkString("TPG_MapEdit")         -- server -> client: editor state
util.AddNetworkString("TPG_MapEditAction")   -- client -> server: one edit
util.AddNetworkString("TPG_MapEditExport")   -- server -> client: exported Lua

local TOOL = "weapon_tpg_pointtool"

local MODES = {
    cp = GAMEMODE_CP, koth = GAMEMODE_KOTH, ctf = GAMEMODE_CTF,
    rush = GAMEMODE_RUSH, dm = GAMEMODE_DM,
}

local function isAdmin(ply)
    return IsValid(ply) and ply:IsAdmin()
end

local function say(ply, msg, col)
    if IsValid(ply) then
        TPG.Util.ChatMessage(ply, "[TPG] " .. msg, col or Color(120, 200, 255))
    else
        print("[TPG] " .. msg)
    end
end

local function typeByKey(key)
    for _, t in ipairs(TPG.Layout.Types) do
        if t.key == key then return t end
    end
end

local function typeOf(pt)
    return TPG.Layout.GetType(pt.type, pt.team)
end

local function toVector(t)
    return Vector(t.x, t.y, t.z)
end

-- The value a setting has in a merged config.
local function settingValue(config, key)
    local limits = config.limits or {}
    if key == "points" or key == "weight" or key == "props" then return limits[key] end
    if key == "capCP" then return config[GAMEMODE_CP] and config[GAMEMODE_CP].capMultiplier end
    if key == "capKOTH" then return config[GAMEMODE_KOTH] and config[GAMEMODE_KOTH].capMultiplier end
    if key == "winsToMapVote" then return config.winsToMapVote or TPG.Config.winsToMapVote end
    if key == "voteList" then
        local map = game.GetMap()
        if table.HasValue(TPG.Voting.MapLists.Open, map) then return "open" end
        if table.HasValue(TPG.Voting.MapLists.Urban, map) then return "urban" end
        return nil
    end
    return config[key]
end

-- Rows for the panel and the overlay: the layout as it will play.
local function buildRows(data, base)
    local rows = {}

    for _, t in ipairs(TPG.Layout.Types) do
        local own = {}
        for i, pt in ipairs(data.points) do
            if typeOf(pt) == t then own[#own + 1] = { idx = i, pt = pt } end
        end

        if #own > 0 then
            for n, entry in ipairs(own) do
                rows[#rows + 1] = {
                    key = t.key, order = n, idx = entry.idx,
                    pos = toVector(entry.pt.pos),
                    name = entry.pt.name or (t.single and t.label or TPG.Layout.DefaultName(t.id, n)),
                }
            end
        elseif t.id == "spawn" then
            local pos = base.spawns and base.spawns[TPG.Layout.TeamId(t.team)]
            if isvector(pos) then
                rows[#rows + 1] = { key = t.key, order = 1, pos = pos, name = t.label, builtin = true }
            end
        elseif t.id == "ctf" then
            if isvector(base.ctfFlag) then
                rows[#rows + 1] = { key = t.key, order = 1, pos = base.ctfFlag, name = t.label, builtin = true }
            end
        else
            local block = base[t.mode]
            for n, o in ipairs(block and block.objectives or {}) do
                rows[#rows + 1] = {
                    key = t.key, order = n, pos = o.pos,
                    name = o.name or TPG.Layout.DefaultName(t.id, n), builtin = true,
                }
            end
        end
    end

    return rows
end

-- What the player-sized box at a point would hit, in words, or nil.
local HULL_MINS, HULL_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)

local function worldProblem(pos)
    if not util.IsInWorld(pos + Vector(0, 0, 16)) then return "is outside the map" end

    local start = pos + Vector(0, 0, 8)
    local inside = util.TraceHull({ start = start, endpos = start, mins = HULL_MINS, maxs = HULL_MAXS, mask = MASK_PLAYERSOLID_BRUSHONLY })
    if inside.StartSolid then return "is inside a wall or the floor" end

    local down = util.TraceLine({ start = start, endpos = start - Vector(0, 0, 512), mask = MASK_PLAYERSOLID_BRUSHONLY })
    if not down.Hit then return "is floating - nothing under it for 512 units" end
end

--[[--
    Everything wrong with a layout that the editor can spot.

    @{TPG.Layout.Check}'s position checks, plus the ones that need the world:
    a point outside the map, inside a wall or the floor, or with nothing under
    it. The world checks test a player-sized box, since every point here is
    somewhere a player has to stand.

    @tparam table config A merged map config (see `TPG.Maps.BuildConfig`).
    @treturn {string,...} Player-facing warnings; empty when nothing is wrong.
    @realm server
]]
function TPG.MapEdit.Validate(config)
    local warnings = TPG.Layout.Check(config)

    local function check(pos, what)
        if not isvector(pos) then return end
        local problem = worldProblem(pos)
        if problem then warnings[#warnings + 1] = what .. " " .. problem .. "." end
    end

    check(config.spawns and config.spawns[TEAM_GREEN], "The Green spawn")
    check(config.spawns and config.spawns[TEAM_RED], "The Red spawn")
    for _, entry in ipairs({ { GAMEMODE_CP, "Control point" }, { GAMEMODE_KOTH, "KOTH hill" }, { GAMEMODE_RUSH, "Rush stage" } }) do
        local block = config[entry[1]]
        for i, o in ipairs(block and block.objectives or {}) do
            check(o.pos, string.format("%s %d (%s)", entry[2], i, o.name or "?"))
        end
    end
    check(config.ctfFlag, "The CTF flag")

    if TPG.Bots and not TPG.Bots.MapSupported() then
        warnings[#warnings + 1] = "No AI nodes on this map - bots won't spawn here."
    end

    return warnings
end

--[[--
    The editor state for the running map, as sent to admins.

    `rows` is the layout as it will play (see the module summary), each row
    `{ key, order, idx, pos, name, builtin }`; `idx` is the point's index in
    the saved layout, nil for a built-in point. `settings` holds what the
    layout sets, `values` what is in effect with the layout, `base` what the
    map has without it, and `inPlay` the budgets after `TPG.Maps.LimitMult`.

    @treturn table
    @realm server
]]
function TPG.MapEdit.BuildState()
    local map    = game.GetMap()
    local data   = TPG.Maps.GetCustomData()
    local base   = TPG.Maps.BuildConfig(map, false)
    local config = TPG.Maps.BuildConfig(map)

    local values, baseValues = {}, {}
    for _, s in ipairs(TPG.Layout.Settings) do
        values[s.key]     = settingValue(config, s.key)
        baseValues[s.key] = settingValue(base, s.key)
    end
    if data.settings.voteList then values.voteList = data.settings.voteList end

    local info = TPG.Maps.GetVoteInfo(map)

    return {
        map        = map,
        configured = TPG.Maps.Configs[map] ~= nil,
        rows       = buildRows(data, base),
        settings   = table.Copy(data.settings),
        values     = values,
        base       = baseValues,
        inPlay     = { points = info.points, weight = info.weight, props = info.props },
        capRadius  = TPG.Util.MetersToUnits(TPG.Config.capDistanceMeters or 5),
        safezoneRadius = config.safezoneRadius or TPG.Config.safezoneRadius,
        rushOrdered = config[GAMEMODE_RUSH] ~= nil and #(config[GAMEMODE_RUSH].objectives or {}) > 0,
        warnings   = TPG.MapEdit.Validate(config),
    }
end

--- Send the editor state to one admin, or to every admin.
-- @tparam[opt] Player target nil sends to every admin on the server.
-- @realm server
function TPG.MapEdit.Push(target)
    local recipients = {}
    if IsValid(target) then
        if isAdmin(target) then recipients[1] = target end
    else
        for _, ply in ipairs(player.GetAll()) do
            if isAdmin(ply) then recipients[#recipients + 1] = ply end
        end
    end
    if #recipients == 0 then return end

    net.Start("TPG_MapEdit")
        net.WriteTable(TPG.MapEdit.BuildState())
    net.Send(recipients)
end

-- The saved index a panel row refers to, copying the built-in point into the
-- layout first if the row is one. nil if the row no longer matches.
local function resolve(ref)
    local t = istable(ref) and typeByKey(ref.key)
    if not t then return nil end

    local data = TPG.Maps.GetCustomData()
    if isnumber(ref.idx) then
        local pt = data.points[ref.idx]
        return (pt and typeOf(pt) == t) and ref.idx or nil
    end

    if t.single then
        local base = TPG.Maps.BuildConfig(game.GetMap(), false)
        local pos = t.id == "spawn" and base.spawns[TPG.Layout.TeamId(t.team)] or base.ctfFlag
        if not isvector(pos) then return nil end
        return (TPG.Maps.AddPoint(t.id, t.team, pos))
    end

    TPG.Maps.ImportBuiltin(t.id)
    local n = 0
    for i, pt in ipairs(data.points) do
        if typeOf(pt) == t then
            n = n + 1
            if n == ref.order then return i end
        end
    end
end

local function pointLabel(idx)
    local pt = TPG.Maps.GetCustomData().points[idx]
    if not pt then return "point" end
    local t = typeOf(pt)
    if t.single then return t.label end

    local n = 0
    for i, other in ipairs(TPG.Maps.GetCustomData().points) do
        if other.type == pt.type then n = n + 1 end
        if i == idx then break end
    end
    return string.format("%s %d (%s)", t.label, n, pt.name or TPG.Layout.DefaultName(pt.type, n))
end

local function changed()
    TPG.MapEdit.Push()
end

-- The mode a point type is played in, as a Preview mode name. Spawns and
-- settings show in whatever is playing now.
local function modeFor(key)
    local t = key and typeByKey(key)
    if t and t.id ~= "spawn" then return t.id end
    for name, id in pairs(MODES) do
        if id == TPG.State.gameType then return name end
    end
    return "cp"
end

-- An edit was saved: tell every admin, then put it in play. With live apply
-- on (the admin's `tpg_mapedit_live`, default 1) the round restarts as a
-- preview a second after the last edit, in the edited point's mode, so a run
-- of placements restarts it once. With it off the admin is told the command.
local function edited(ply, key)
    changed()

    local mode = modeFor(key)
    -- GetInfo, not GetInfoNum: a client that never sent the convar reads
    -- "" and GetInfoNum turns that into 0, which would mean off.
    if IsValid(ply) and ply:GetInfo("tpg_mapedit_live") == "0" then
        say(ply, "Saved. To play it now: tpg_points_reload " .. mode)
        return
    end

    timer.Create("TPG_MapEditLive", 1, 1, function()
        TPG.MapEdit.Preview(IsValid(ply) and ply or nil, mode)
    end)
end

--- Place a point of a type at a position, for an admin. Placing a spawn or
-- the CTF flag moves the existing one. Tells the admin what happened and
-- sends everyone the new state.
-- @tparam Player ply
-- @tparam string key A @{TPG.Layout.Types} key.
-- @tparam Vector pos
-- @realm server
function TPG.MapEdit.Place(ply, key, pos)
    local t = typeByKey(key)
    if not t then return end

    local hadOne = t.single and TPG.Maps.FindNearest(pos, math.huge, t.id, t.team) ~= nil
    local idx, imported = TPG.Maps.AddPoint(t.id, t.team, pos)
    if not idx then return end

    if imported > 0 then
        say(ply, string.format("Copied the map's %d built-in %s point(s) into the layout first, so this one adds to them.",
            imported, string.lower(t.label)))
    end
    say(ply, (hadOne and "Moved " or "Placed ") .. pointLabel(idx) .. ".")
    edited(ply, key)
end

--- Remove the placed point of a type nearest a position (within 300 units),
-- for an admin.
-- @tparam Player ply
-- @tparam string key A @{TPG.Layout.Types} key; only points of this type go.
-- @tparam Vector pos
-- @realm server
function TPG.MapEdit.RemoveNearest(ply, key, pos)
    local t = typeByKey(key)
    if not t then return end

    local idx = TPG.Maps.FindNearest(pos, 300, t.id, t.team)
    if not idx then
        say(ply, "No placed " .. string.lower(t.label) .. " within range. Built-in points are removed from the editor (tpg_mapedit).", Color(255, 200, 80))
        return
    end

    local label = pointLabel(idx)
    TPG.Maps.RemovePoint(idx)
    say(ply, "Removed " .. label .. ".")
    edited(ply, key)
end

--- The point an admin is moving with the tool, if any.
-- @tparam Player ply
-- @treturn ?number The point's index in the saved layout.
-- @realm server
function TPG.MapEdit.GetMove(ply)
    local move = ply.TPG_MapEditMove
    if not move then return nil end

    local pt = TPG.Maps.GetCustomData().points[move.idx]
    if pt and pt.type == move.type and pt.team == move.team then return move.idx end

    TPG.MapEdit.CancelMove(ply)
end

--- Stop moving a point with the tool.
-- @tparam Player ply
-- @realm server
function TPG.MapEdit.CancelMove(ply)
    ply.TPG_MapEditMove = nil
    ply:SetNWString("TPG_MapEditMove", "")
end

--- Drop the point an admin is moving at a position.
-- @tparam Player ply
-- @tparam Vector pos
-- @realm server
function TPG.MapEdit.DropMove(ply, pos)
    local idx = TPG.MapEdit.GetMove(ply)
    TPG.MapEdit.CancelMove(ply)
    if not idx then return end

    TPG.Maps.MovePoint(idx, pos)
    say(ply, "Moved " .. pointLabel(idx) .. ".")
    edited(ply, typeOf(TPG.Maps.GetCustomData().points[idx]).key)
end

local function giveTool(ply)
    if not ply:HasWeapon(TOOL) then ply:Give(TOOL) end
    ply:SelectWeapon(TOOL)
end

--[[--
    Restart the round on the saved layout without disturbing anyone.

    Reloads the layout from disk and sets up a preview round (see
    `TPG.Rounds.Setup`): builds stay, nobody is killed or moved, and there is
    no prep window. Refuses CTF and Rush on a map that cannot host them yet,
    rather than starting a round with nothing in it.

    @tparam[opt] Player ply Who asked; nil for the server console.
    @tparam[opt] string modeName `cp`, `koth`, `ctf`, `rush` or `dm`; nil rolls one.
    @realm server
]]
function TPG.MapEdit.Preview(ply, modeName)
    local mode = modeName and MODES[string.lower(modeName)]
    if modeName and modeName ~= "" and not mode then
        say(ply, "Unknown mode \"" .. modeName .. "\" - use cp, koth, ctf, rush or dm.", Color(255, 120, 120))
        return
    end

    TPG.Maps.LoadCustom()
    TPG.Maps.Load()

    if mode == GAMEMODE_CTF and not TPG.CTF.IsSupported() then
        say(ply, "CTF needs a KOTH hill or a CTF flag point on this map.", Color(255, 120, 120))
        return
    end
    if mode == GAMEMODE_RUSH and not TPG.Rush.IsSupported() then
        say(ply, "Rush needs control points or Rush stages on this map.", Color(255, 120, 120))
        return
    end

    TPG.Rounds.Setup(true, { preview = true, gameType = mode })
    say(ply, "Previewing " .. TPG.GetGameType(TPG.State.gameType).name .. " on the saved layout ("
        .. TPG.Maps.CountPoints() .. " placed points).")
end

--- Write the running map's config, layout included, as a `_loader.lua`
-- block: to `data/tpg/export/<map>.txt`, and to the admin who asked (their
-- console and clipboard).
-- @tparam[opt] Player ply nil for the server console, which gets it printed.
-- @realm server
function TPG.MapEdit.Export(ply)
    local map  = game.GetMap()
    local data = TPG.Maps.GetCustomData()
    local text = TPG.Layout.Export(map, TPG.Maps.BuildConfig(map), data.settings.voteList)

    file.CreateDir("tpg/export")
    local out = "tpg/export/" .. string.lower(map) .. ".txt"
    file.Write(out, text)

    if IsValid(ply) then
        net.Start("TPG_MapEditExport")
            net.WriteString(text)
            net.WriteString("data/" .. out)
        net.Send(ply)
    else
        print(text)
        print("[TPG] Also written to data/" .. out)
    end
end

-- Copy every built-in point the layout does not override yet.
local function importAll()
    local n = 0
    local base = TPG.Maps.BuildConfig(game.GetMap(), false)
    for _, t in ipairs(TPG.Layout.Types) do
        if t.single then
            local pos = t.id == "spawn" and base.spawns[TPG.Layout.TeamId(t.team)] or base.ctfFlag
            if isvector(pos) and not TPG.Maps.FindNearest(pos, math.huge, t.id, t.team) then
                TPG.Maps.AddPoint(t.id, t.team, pos)
                n = n + 1
            end
        else
            n = n + TPG.Maps.ImportBuiltin(t.id)
        end
    end
    return n
end

local ACTIONS = {}

function ACTIONS.subscribe(ply)
    TPG.MapEdit.Push(ply)
end

function ACTIONS.tool(ply)
    giveTool(ply)
end

function ACTIONS.place(ply, args)
    local tr = ply:GetEyeTrace()
    if tr.Hit then TPG.MapEdit.Place(ply, args.key, tr.HitPos) end
end

function ACTIONS.remove(ply, args)
    local idx = resolve(args.row)
    if not idx then return end
    local label = pointLabel(idx)
    TPG.Maps.RemovePoint(idx)
    say(ply, "Removed " .. label .. ".")
    edited(ply, args.row.key)
end

function ACTIONS.move(ply, args)
    local idx = resolve(args.row)
    if not idx then return end
    local pt = TPG.Maps.GetCustomData().points[idx]
    ply.TPG_MapEditMove = { idx = idx, type = pt.type, team = pt.team }
    ply:SetNWString("TPG_MapEditMove", pointLabel(idx))
    giveTool(ply)
    say(ply, "Moving " .. pointLabel(idx) .. " - aim and left click to drop it, right click to cancel.")
    changed()
end

function ACTIONS.rename(ply, args)
    local idx = resolve(args.row)
    if idx and TPG.Maps.RenamePoint(idx, args.name) then edited(ply, args.row.key) end
end

function ACTIONS.shift(ply, args)
    local idx = resolve(args.row)
    if idx and TPG.Maps.ShiftPoint(idx, args.dir == -1 and -1 or 1) then edited(ply, args.row.key) end
end

function ACTIONS.setting(ply, args)
    if TPG.Maps.SetSetting(args.key, args.value) then
        edited(ply)
    else
        say(ply, "That value doesn't fit " .. tostring(args.key) .. ".", Color(255, 120, 120))
    end
end

function ACTIONS.import(ply)
    local n = importAll()
    say(ply, n > 0 and ("Copied " .. n .. " built-in point(s) into the layout.") or "The layout already covers every built-in point.")
    if n > 0 then edited(ply) end
end

function ACTIONS.clear(ply, args)
    local t = args.key and typeByKey(args.key)
    if t then
        TPG.Maps.ClearPoints(t.id, t.team)
        say(ply, "Cleared the placed " .. string.lower(t.label) .. " points - the map's own apply again.")
    elseif ply:IsSuperAdmin() then
        TPG.Maps.ClearLayout()
        say(ply, "Cleared the whole layout for " .. game.GetMap() .. ".")
    else
        say(ply, "Clearing the whole layout is superadmin only.", Color(255, 120, 120))
        return
    end
    edited(ply, t and t.key)
end

function ACTIONS.preview(ply, args)
    TPG.MapEdit.Preview(ply, args.mode)
end

function ACTIONS.export(ply)
    TPG.MapEdit.Export(ply)
end

function ACTIONS.teleport(ply, args)
    local row = args.row
    if istable(row) and isvector(row.pos) then
        if ply:InVehicle() then ply:ExitVehicle() end
        ply:SetPos(row.pos + Vector(0, 0, 8))
    end
end

net.Receive("TPG_MapEditAction", function(_, ply)
    if not isAdmin(ply) then return end

    local action = net.ReadString()
    local args   = net.ReadTable() or {}
    local fn = ACTIONS[action]
    if fn then fn(ply, args) end
end)

-- ── Console commands ────────────────────────────────────────────────────────

-- Preview the saved layout: `tpg_points_reload [cp|koth|ctf|rush|dm]`. A
-- valid ply that fails IsAdmin is refused; the server console always passes.
concommand.Add("tpg_points_reload", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then
        say(ply, "Admin only.", Color(255, 120, 120))
        return
    end
    TPG.MapEdit.Preview(ply, args[1])
end)

-- Wipe the running map's whole layout, points and settings. Superadmin, or
-- the server console. Does not restart the round.
concommand.Add("tpg_points_clear", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        say(ply, "Superadmin only.", Color(255, 120, 120))
        return
    end
    TPG.Maps.ClearLayout()
    say(ply, "Cleared the whole layout for " .. game.GetMap() .. ".")
    edited(ply)
end)

-- Export the running map as a `_loader.lua` block.
concommand.Add("tpg_mapedit_export", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        say(ply, "Admin only.", Color(255, 120, 120))
        return
    end
    TPG.MapEdit.Export(ply)
end)
