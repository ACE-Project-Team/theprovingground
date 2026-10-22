--[[--
    The map editor, client side: the in-world overlay and the `tpg_mapedit`
    panel.

    The server (@{tpg.mapedit}) sends admins the editor state whenever the
    layout changes; this file only draws it and sends edits back as
    `TPG_MapEditAction` messages, which the server checks for admin again.

    The overlay is on while the point tool is out or the panel is open. Every
    point is drawn where it is with its name, its capture circle (objectives)
    or safezone circle (spawns), and the Rush stages are joined in the order
    they play. Points the map ships with are drawn fainter and marked "map".

    The panel lists the same points, edits the per-map settings, previews the
    layout in any mode, and exports it as a `_loader.lua` block (to the
    console and the clipboard). Its two checkboxes are this admin's
    `tpg_mapedit_live` (edits go into play at once) and
    `tpg_pointtool_advanced` (the tool offers Rush stages and the CTF flag).

    @module tpg.mapedit.client
    @realm client
]]

TPG.MapEdit = TPG.MapEdit or {}

local TOOL = "weapon_tpg_pointtool"

-- Per admin, read by the server with GetInfoNum.
CreateClientConVar("tpg_mapedit_live", "1", true, true,
    "Map editor: put each edit in play at once by restarting the round as a preview (1), or only save it (0).", 0, 1)
CreateClientConVar("tpg_pointtool_advanced", "0", true, true,
    "Point tool: also offer Rush stages and the CTF flag when cycling types.", 0, 1)

local state      -- last state from the server, nil until subscribed
local frame      -- the open panel, if any
local selected   -- the row the panel has selected, for the overlay

local function send(action, args)
    net.Start("TPG_MapEditAction")
        net.WriteString(action)
        net.WriteTable(args or {})
    net.SendToServer()
end

local function typeByKey(key)
    for _, t in ipairs(TPG.Layout.Types) do
        if t.key == key then return t end
    end
end

-- What the server needs to find a row again: built-in rows have no idx.
local function rowRef(row)
    return { key = row.key, order = row.order, idx = row.idx }
end

local function sameRow(a, b)
    return a and b and a.key == b.key and a.order == b.order
end

local function holdingTool()
    local wep = LocalPlayer():GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() == TOOL
end

local function overlayOn()
    return state ~= nil and LocalPlayer():IsAdmin() and (IsValid(frame) or holdingTool())
end

-- ── Overlay ─────────────────────────────────────────────────────────────────

local UP = Vector(0, 0, 1)
local BEAM = 160

local function circle(pos, radius, col)
    local segs = math.Clamp(math.floor(radius / 12), 24, 96)
    local prev
    for i = 0, segs do
        local a = i / segs * math.pi * 2
        local p = pos + Vector(math.cos(a) * radius, math.sin(a) * radius, 4)
        if prev then render.DrawLine(prev, p, col, true) end
        prev = p
    end
end

local function rowRadius(row)
    local t = typeByKey(row.key)
    if t and t.id == "spawn" then return state.safezoneRadius end
    return state.capRadius
end

local function fade(col, builtin)
    return Color(col.r, col.g, col.b, builtin and 110 or 255)
end

hook.Add("PostDrawTranslucentRenderables", "TPG_MapEditOverlay", function(depth, sky)
    if depth or sky or not overlayOn() then return end
    render.SetColorMaterial()

    local rush = {}
    for _, row in ipairs(state.rows) do
        local t = typeByKey(row.key)
        if t then
            local col = fade(t.tint, row.builtin)
            local hot = sameRow(row, selected)
            render.DrawSphere(row.pos + UP * 12, hot and 18 or 12, 12, 12, col)
            render.DrawBeam(row.pos, row.pos + UP * BEAM, hot and 6 or 3, 0, 1, col)
            circle(row.pos, rowRadius(row), col)
            if hot then circle(row.pos, rowRadius(row) + 8, col) end
            if row.key == "rush" then rush[#rush + 1] = row end
        end
    end

    for i = 2, #rush do
        render.DrawBeam(rush[i - 1].pos + UP * 40, rush[i].pos + UP * 40, 4, 0, 1, Color(110, 190, 255, 160))
    end

    -- Where the tool would place the selected type.
    local wep = LocalPlayer():GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == TOOL and wep.CurrentType then
        local tr = LocalPlayer():GetEyeTrace()
        if tr.Hit then
            local t = wep:CurrentType()
            local radius = t.id == "spawn" and state.safezoneRadius or state.capRadius
            local col = Color(t.tint.r, t.tint.g, t.tint.b, 170)
            render.DrawSphere(tr.HitPos + UP * 12, 10, 10, 10, col)
            circle(tr.HitPos, radius, col)
        end
    end
end)

hook.Add("HUDPaint", "TPG_MapEditLabels", function()
    if not overlayOn() then return end

    local eye = LocalPlayer():EyePos()
    local stage = 0
    for _, row in ipairs(state.rows) do
        local t = typeByKey(row.key)
        if row.key == "rush" then stage = stage + 1 end
        local top = row.pos + UP * (BEAM + 16)
        local scr = top:ToScreen()
        if t and scr.visible and eye:DistToSqr(top) < 12000 * 12000 then
            local col = fade(t.tint, row.builtin)
            local title = row.name
            if row.key == "rush" and state.rushOrdered then title = stage .. ". " .. title end
            draw.SimpleTextOutlined(title, "TPG.HUD.Label", scr.x, scr.y, col,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
            local sub = (t.single and "" or (t.label .. "  ")) .. (row.builtin and "map" or "layout")
                .. "  " .. math.Round(eye:Distance(row.pos) / 52.49) .. " m"
            draw.SimpleTextOutlined(sub, "TPG.HUD.Small", scr.x, scr.y, Color(245, 245, 245, row.builtin and 120 or 220),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
        end
    end
end)

-- ── Panel ───────────────────────────────────────────────────────────────────

local function settingText(v)
    if v == nil then return "" end
    if isnumber(v) then return tostring(math.Round(v, 3)) end
    return tostring(v)
end

local function fill()
    if not IsValid(frame) or not state then return end
    frame:SetTitle("TPG Map Editor - " .. state.map .. (state.configured and "" or "  (no built-in config)"))

    -- Points
    local list = frame.points
    local keep = selected
    selected = nil
    list:Clear()
    for _, row in ipairs(state.rows) do
        local t = typeByKey(row.key)
        local line = list:AddLine(t and t.label or row.key, t and t.single and "" or row.order, row.name, row.builtin and "map" or "layout")
        line.row = row
        if sameRow(row, keep) then
            list:SelectItem(line)
            selected = row
        end
    end

    -- Settings
    for key, entry in pairs(frame.settings) do
        local own = state.settings[key]
        if not entry:HasFocus() then entry:SetValue(settingText(own)) end
        entry:SetPlaceholderText(settingText(state.base[key]) ~= "" and ("map: " .. settingText(state.base[key])) or "map default")
        local note = frame.notes[key]
        if note then
            local inPlay = state.inPlay[key]
            note:SetText(inPlay and ("in play: " .. settingText(inPlay)) or "")
        end
    end
    local choice = frame.voteList
    if IsValid(choice) then
        choice:SetValue(state.values.voteList or "not in the vote")
    end

    -- Warnings
    local warn = frame.warnings
    warn:Clear()
    if #state.warnings == 0 then
        warn:AddLine("No problems found.")
    else
        for _, w in ipairs(state.warnings) do warn:AddLine(w) end
    end
end

local function button(parent, text, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText(text)
    b.DoClick = fn
    return b
end

-- A row of evenly sized buttons docked to the top of a parent.
local function buttonRow(parent, defs)
    local bar = vgui.Create("DPanel", parent)
    bar:Dock(TOP)
    bar:DockMargin(0, 4, 0, 0)
    bar:SetTall(26)
    bar:SetPaintBackground(false)
    bar.PerformLayout = function(self, w)
        local kids = self:GetChildren()
        local bw = (w - (#kids - 1) * 4) / #kids
        for i, k in ipairs(kids) do
            k:SetPos((i - 1) * (bw + 4), 0)
            k:SetSize(bw, self:GetTall())
        end
    end
    for _, d in ipairs(defs) do button(bar, d[1], d[2]) end
    return bar
end

local function withSelected(fn)
    return function()
        if not selected then
            chat.AddText(Color(255, 200, 80), "[TPG] Select a point first.")
            return
        end
        fn(selected)
    end
end

local function buildPointsTab(parent)
    local list = vgui.Create("DListView", parent)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("Type"):SetFixedWidth(120)
    list:AddColumn("#"):SetFixedWidth(28)
    list:AddColumn("Name")
    list:AddColumn("From"):SetFixedWidth(56)
    list.OnRowSelected = function(_, _, line) selected = line.row end
    list.DoDoubleClick = function(_, _, line) send("teleport", { row = line.row }) end
    frame.points = list

    local bottom = vgui.Create("DPanel", parent)
    bottom:Dock(BOTTOM)
    bottom:SetTall(120)
    bottom:SetPaintBackground(false)

    buttonRow(bottom, {
        { "Go to", withSelected(function(row) send("teleport", { row = row }) end) },
        { "Move with tool", withSelected(function(row) send("move", { row = rowRef(row) }) end) },
        { "Rename", withSelected(function(row)
            Derma_StringRequest("Rename point", "New name (empty for the default):", row.name, function(text)
                send("rename", { row = rowRef(row), name = text })
            end)
        end) },
        { "Up", withSelected(function(row)
            send("shift", { row = rowRef(row), dir = -1 })
            selected = { key = row.key, order = math.max(row.order - 1, 1) }
        end) },
        { "Down", withSelected(function(row)
            send("shift", { row = rowRef(row), dir = 1 })
            selected = { key = row.key, order = row.order + 1 }
        end) },
        { "Delete", withSelected(function(row)
            send("remove", { row = rowRef(row) })
            selected = nil
        end) },
    })

    -- Place a type where the admin is aiming.
    local place = vgui.Create("DPanel", bottom)
    place:Dock(TOP)
    place:DockMargin(0, 4, 0, 0)
    place:SetTall(26)
    place:SetPaintBackground(false)

    local combo = vgui.Create("DComboBox", place)
    combo:Dock(LEFT)
    combo:SetWide(200)
    for i, t in ipairs(TPG.Layout.Types) do combo:AddChoice(t.label, t.key, i == 1) end

    local go = button(place, "Place at my aim", function()
        local _, key = combo:GetSelected()
        if key then send("place", { key = key }) end
    end)
    go:Dock(LEFT)
    go:DockMargin(4, 0, 0, 0)
    go:SetWide(130)

    local clr = button(place, "Clear this type", function()
        local label, key = combo:GetSelected()
        if not key then return end
        Derma_Query("Delete every placed " .. string.lower(label) .. "? The map's own come back.", "Clear",
            "Clear", function() send("clear", { key = key }) end, "Cancel")
    end)
    clr:Dock(LEFT)
    clr:DockMargin(4, 0, 0, 0)
    clr:SetWide(110)

    local opts = vgui.Create("DPanel", bottom)
    opts:Dock(TOP)
    opts:DockMargin(0, 4, 0, 0)
    opts:SetTall(20)
    opts:SetPaintBackground(false)

    local live = vgui.Create("DCheckBoxLabel", opts)
    live:Dock(LEFT)
    live:SetWide(330)
    live:SetText("Put edits in play at once (restarts the round as a preview)")
    live:SetConVar("tpg_mapedit_live")

    local adv = vgui.Create("DCheckBoxLabel", opts)
    adv:Dock(LEFT)
    adv:DockMargin(12, 0, 0, 0)
    adv:SetWide(260)
    adv:SetText("Advanced types in the tool (Rush, CTF flag)")
    adv:SetConVar("tpg_pointtool_advanced")

    buttonRow(bottom, {
        { "Give point tool", function() send("tool") end },
        { "Copy map's points into layout", function() send("import") end },
        { "Clear whole layout", function()
            Derma_Query("Delete this map's whole layout, points and settings? (superadmin)", "Clear layout",
                "Clear", function() send("clear", {}) end, "Cancel")
        end },
    })
end

local function buildSettingsTab(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)

    local hint = vgui.Create("DLabel", scroll)
    hint:Dock(TOP)
    hint:DockMargin(4, 4, 4, 8)
    hint:SetWrap(true)
    hint:SetAutoStretchVertical(true)
    hint:SetText("Empty uses the map's value (shown faded). Budgets are as written in a map config; "
        .. "\"in play\" is after the server-wide multipliers. Press Enter to save a field.")

    frame.settings, frame.notes = {}, {}
    for _, s in ipairs(TPG.Layout.Settings) do
        local rowPanel = vgui.Create("DPanel", scroll)
        rowPanel:Dock(TOP)
        rowPanel:DockMargin(4, 0, 4, 4)
        rowPanel:SetTall(24)
        rowPanel:SetPaintBackground(false)

        local label = vgui.Create("DLabel", rowPanel)
        label:Dock(LEFT)
        label:SetWide(180)
        label:SetText(s.label)

        if s.kind == "choice" then
            local combo = vgui.Create("DComboBox", rowPanel)
            combo:Dock(LEFT)
            combo:SetWide(160)
            for _, c in ipairs(s.choices) do combo:AddChoice(c) end
            combo:AddChoice("map default", "")
            combo.OnSelect = function(_, _, value, data)
                send("setting", { key = s.key, value = data == "" and "" or value })
            end
            frame.voteList = combo
        else
            local entry = vgui.Create("DTextEntry", rowPanel)
            entry:Dock(LEFT)
            entry:SetWide(160)
            entry:SetNumeric(s.kind == "number")
            entry.OnEnter = function(self)
                send("setting", { key = s.key, value = self:GetValue() })
            end
            frame.settings[s.key] = entry

            local note = vgui.Create("DLabel", rowPanel)
            note:Dock(FILL)
            note:DockMargin(8, 0, 0, 0)
            note:SetText("")
            frame.notes[s.key] = note
        end
    end
end

local function buildWarnings(parent)
    local box = vgui.Create("DPanel", parent)
    box:Dock(BOTTOM)
    box:DockMargin(0, 6, 0, 0)
    box:SetTall(118)
    box:SetPaintBackground(false)

    local warn = vgui.Create("DListView", box)
    warn:Dock(FILL)
    warn:AddColumn("Problems with this layout")
    frame.warnings = warn

    buttonRow(box, {
        { "Preview CP",   function() send("preview", { mode = "cp" }) end },
        { "Preview KOTH", function() send("preview", { mode = "koth" }) end },
        { "Preview CTF",  function() send("preview", { mode = "ctf" }) end },
        { "Preview Rush", function() send("preview", { mode = "rush" }) end },
        { "Preview DM",   function() send("preview", { mode = "dm" }) end },
        { "Export",       function() send("export") end },
    }):Dock(BOTTOM)
end

--- Open the map editor panel (admins only). The console command is
-- `tpg_mapedit`; Shift+R with the point tool opens it too.
-- @realm client
function TPG.MapEdit.OpenPanel()
    if not LocalPlayer():IsAdmin() then
        chat.AddText(Color(255, 120, 120), "[TPG] The map editor is admin-only.")
        return
    end
    if IsValid(frame) then frame:MakePopup() return end

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() - 40, 820), math.min(ScrH() - 40, 640))
    frame:Center()
    frame:SetTitle("TPG Map Editor")
    frame:SetSizable(true)
    frame:SetMinWidth(640)
    frame:SetMinHeight(480)
    frame:MakePopup()
    frame.OnClose = function() selected = nil end

    buildWarnings(frame)

    local sheet = vgui.Create("DPropertySheet", frame)
    sheet:Dock(FILL)

    local points = vgui.Create("DPanel", sheet)
    points:SetPaintBackground(false)
    buildPointsTab(points)
    sheet:AddSheet("Points", points, "icon16/flag_blue.png")

    local settings = vgui.Create("DPanel", sheet)
    settings:SetPaintBackground(false)
    buildSettingsTab(settings)
    sheet:AddSheet("Map settings", settings, "icon16/cog.png")

    send("subscribe")
    fill()
end

concommand.Add("tpg_mapedit", function() TPG.MapEdit.OpenPanel() end, nil,
    "Admin: open the TPG map editor (points, map settings, preview, export).")

-- ── Net ─────────────────────────────────────────────────────────────────────

net.Receive("TPG_MapEdit", function()
    state = net.ReadTable()
    fill()
end)

net.Receive("TPG_MapEditExport", function()
    local text, path = net.ReadString(), net.ReadString()
    print(text)
    SetClipboardText(text)
    chat.AddText(Color(120, 200, 255), "[TPG] Exported " .. (state and state.map or "the map")
        .. " - copied to your clipboard, printed in the console, and saved on the server as " .. path .. ".")
end)
