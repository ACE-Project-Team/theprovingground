--[[--
    The Proving Ground section in the sandbox Q-menu (Utilities tab).

    Two pages, so nothing needs a console command:

      * Player: join a team, open the team, loadout, profile, manual and vote
        menus, and toggle the compass, objective markers, economy wallet and
        friendly bot markers.
      * Admin: round controls, the map editor and its preview and export, and
        the server settings from the shared allow-list in
        `core/sh_admin_settings.lua`. Superadmin-only items are hidden for plain
        admins. The server checks everything again, so this page is a
        convenience, not the gate.

    Every button runs an existing concommand, so the server-side checks in
    `core/sv_commands.lua`, `maps/sv_mapedit.lua` and `core/sv_admin_settings.lua`
    still decide what happens. The one exception is "Give point tool", which
    sends the same `TPG_MapEditAction` message the map editor panel sends.

    Server settings are read over `TPG_AdminSettings` when the page opens. Edits
    are debounced 0.5 s per convar, then sent as `tpg_admin_set <convar> <value>`.

    @module tpg.qmenu
    @realm client
]]

-- Shows a line of help and a button that runs a concommand, or a function.
local function button(pnl, label, fn)
    local b = pnl:Button(label)
    b.DoClick = fn
    return b
end

-- Returns a click handler that runs a console command with fixed arguments.
local function run(cmd, ...)
    local args = { ... }
    return function() RunConsoleCommand(cmd, unpack(args)) end
end

-- ── Player page ─────────────────────────────────────────────────────────────

local function buildPlayer(pnl)
    pnl:Help("Pick a side, open a menu, or choose what the HUD shows.")

    pnl:Help("Team")
    button(pnl, "Join Green", run("tpg_team", "green"))
    button(pnl, "Join Red", run("tpg_team", "red"))
    button(pnl, "Spectate", run("tpg_team", "spec"))

    pnl:Help("Menus")
    button(pnl, "Team menu", run("tpg_menu_team"))
    button(pnl, "Loadout", run("tpg_menu_loadout"))
    if LocalPlayer():IsAdmin() then
        -- The weapon menu refuses non-admins, so it is only offered to them.
        button(pnl, "Weapons (admin)", run("tpg_menu_weapons"))
    end
    button(pnl, "Profile", run("tpg_menu_profile"))
    button(pnl, "Manual", run("tpg_menu_manual"))
    button(pnl, "Map vote", run("tpg_menu_mapvote"))

    pnl:Help("HUD")
    pnl:CheckBox("Compass", "tpg_hud_compass")
    pnl:CheckBox("Objective markers", "tpg_hud_objectives")
    pnl:CheckBox("Economy wallet", "tpg_hud_economy")
    pnl:CheckBox("Friendly bot markers", "tpg_hud_bots")
end

-- ── Admin page: settings ────────────────────────────────────────────────────

local holder             -- the panel the server settings are built into, while open
local populating = false -- true while controls are being filled, so setting them does not send

-- Empties a DForm-style list. DPanelList:Clear takes a delete flag.
local function clearList(p)
    if p.Clear then p:Clear(true) end
end

-- Debounce: a fresh change to the same convar restarts its 0.5 s timer.
local function queueSet(name, value)
    timer.Create("TPG_QMenu_Set_" .. name, 0.5, 1, function()
        RunConsoleCommand("tpg_admin_set", name, value)
    end)
end

local function buildControl(inner, entry, current)
    if entry.type == "bool" then
        local cb = inner:CheckBox(entry.label)
        cb:SetChecked(current == "1")
        cb.OnChange = function(_, checked)
            if populating then return end
            queueSet(entry.name, checked and "1" or "0")
        end
        return
    end

    local slider = vgui.Create("DNumSlider")
    slider:SetDark(true)
    slider:SetText(entry.label)
    slider:SetMin(entry.min)
    slider:SetMax(entry.max)
    slider:SetDecimals(entry.decimals)
    slider:SetValue(tonumber(current) or entry.min)
    slider.OnValueChanged = function(_, value)
        if populating then return end
        local out = entry.type == "int" and string.format("%d", math.Round(value)) or string.format("%g", value)
        queueSet(entry.name, out)
    end
    inner:AddItem(slider)
end

-- Fills the settings panel from the server's reply. Superadmin entries are
-- skipped for plain admins, and entries whose convar the server did not send
-- are skipped too.
local function fillSettings(panel, superadmin, values)
    clearList(panel)
    populating = true

    for _, groupName in ipairs(TPG.AdminSettings.Groups) do
        local shown = {}
        for _, entry in ipairs(TPG.AdminSettings.List) do
            if entry.group == groupName and values[entry.name] ~= nil
                and (superadmin or entry.rank ~= "superadmin") then
                shown[#shown + 1] = entry
            end
        end

        if #shown > 0 then
            -- A DForm is already a collapsible category, so it carries the
            -- group name itself.
            local inner = vgui.Create("DForm")
            inner:SetName(groupName)
            for _, entry in ipairs(shown) do
                buildControl(inner, entry, values[entry.name])
            end
            panel:AddItem(inner)
        end
    end

    populating = false
end

net.Receive("TPG_AdminSettings", function()
    local superadmin = net.ReadBool()
    local count = net.ReadUInt(8)
    local values = {}
    for _ = 1, count do
        local name = net.ReadString()
        values[name] = net.ReadString()
    end

    if not IsValid(holder) then return end
    fillSettings(holder, superadmin, values)
end)

-- ── Admin page ──────────────────────────────────────────────────────────────

local function buildAdmin(pnl)
    if not LocalPlayer():IsAdmin() then
        pnl:Help("Admins only.")
        return
    end

    pnl:Help("Round")
    button(pnl, "Restart round", run("tpg_admin_restart"))
    button(pnl, "End round - Green wins", run("tpg_admin_endround", tostring(TEAM_GREEN)))
    button(pnl, "End round - Red wins", run("tpg_admin_endround", tostring(TEAM_RED)))
    button(pnl, "Scramble teams", run("tpg_admin_scramble"))

    pnl:Help("Map editor")
    button(pnl, "Open map editor", function()
        if TPG.MapEdit and TPG.MapEdit.OpenPanel then TPG.MapEdit.OpenPanel() end
    end)
    button(pnl, "Give point tool", function()
        net.Start("TPG_MapEditAction")
            net.WriteString("tool")
            net.WriteTable({})
        net.SendToServer()
    end)
    button(pnl, "Preview CP", run("tpg_points_reload", "cp"))
    button(pnl, "Preview KOTH", run("tpg_points_reload", "koth"))
    button(pnl, "Preview CTF", run("tpg_points_reload", "ctf"))
    button(pnl, "Preview Rush", run("tpg_points_reload", "rush"))
    button(pnl, "Preview DM", run("tpg_points_reload", "dm"))
    button(pnl, "Export", run("tpg_mapedit_export"))
    pnl:CheckBox("Apply edits live", "tpg_mapedit_live")
    pnl:CheckBox("Advanced point tool", "tpg_pointtool_advanced")

    pnl:Help("Server settings")
    holder = vgui.Create("DForm")
    holder:Help("Loading settings...")
    pnl:AddItem(holder)
    net.Start("TPG_AdminSettings")
    net.SendToServer()

    if LocalPlayer():IsSuperAdmin() then
        pnl:Help("Superadmin")
        button(pnl, "Map collection", run("tpg_collection"))
        button(pnl, "Reset lifetime stats", function()
            Derma_Query(
                "Wipe all lifetime stats and the leaderboard? This cannot be undone.",
                "Reset lifetime stats",
                "Reset", function() RunConsoleCommand("tpg_admin_stats_reset") end,
                "Cancel", function() end
            )
        end)
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

hook.Add("AddToolMenuCategories", "TPG_QMenu", function()
    spawnmenu.AddToolCategory("Utilities", "The Proving Ground", "The Proving Ground")
end)

hook.Add("PopulateToolMenu", "TPG_QMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "The Proving Ground", "tpg_player", "Player", "", "", buildPlayer)
    spawnmenu.AddToolMenuOption("Utilities", "The Proving Ground", "tpg_admin", "Admin", "", "", buildAdmin)
end)
