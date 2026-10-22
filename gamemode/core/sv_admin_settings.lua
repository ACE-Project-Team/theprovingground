--[[--
    Server side of the Q-menu settings panel.

    Two entry points, both gated by the allow-list in
    `core/sh_admin_settings.lua`:

      * `tpg_admin_set <convar> <value>` (concommand). Clients reach it through
        the forwarding shim in `core/sh_commands.lua`, and the server console
        reaches it directly. A value is validated and clamped, and only then
        written with `RunConsoleCommand`. Anything not on the list is refused.
      * `TPG_AdminSettings` (net). An admin client sends an empty request and
        gets back every allow-listed convar that exists, as name and string
        value, plus whether the sender is a superadmin. Requests are limited to
        one per second per player.

    Nothing here changes what the convars do; each system still owns its own
    convar and reads it as before.

    @module tpg.adminsettings.server
    @realm server
]]

util.AddNetworkString("TPG_AdminSettings")

-- Reply to whoever ran the command: chat for a player, console for the server.
local function reply(ply, msg, col)
    if IsValid(ply) then
        TPG.Util.ChatMessage(ply, "[TPG] " .. msg, col or Color(0, 255, 255))
    else
        print("[TPG] " .. msg)
    end
end

concommand.Add("tpg_admin_set", function(ply, _cmd, args)
    args = args or {}
    local name = tostring(args[1] or "")

    local entry = TPG.AdminSettings.Find(name)
    if not entry then
        reply(ply, "Not a settings convar: " .. (name ~= "" and name or "(none given)") .. ".", Color(255, 120, 120))
        return
    end

    if IsValid(ply) and not TPG.AdminSettings.Allowed(entry, ply) then
        reply(ply, entry.rank == "superadmin" and "Superadmins only." or "Admins only.", Color(255, 120, 120))
        return
    end

    local cv = GetConVar(entry.name)
    if not cv then
        reply(ply, entry.name .. " is not loaded on this server.", Color(255, 120, 120))
        return
    end

    local value, why, clamped = TPG.AdminSettings.Clamp(entry, args[2])
    if value == nil then
        reply(ply, why, Color(255, 120, 120))
        return
    end

    RunConsoleCommand(entry.name, value)

    local msg = entry.name .. " set to " .. value .. "."
    if clamped then msg = msg .. " (clamped to the allowed range)" end
    reply(ply, msg)
end)

local requestGap = 1
local lastRequest = setmetatable({}, { __mode = "k" })

net.Receive("TPG_AdminSettings", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local now = CurTime()
    if lastRequest[ply] and now - lastRequest[ply] < requestGap then return end
    lastRequest[ply] = now

    local rows = {}
    for _, entry in ipairs(TPG.AdminSettings.List) do
        local cv = GetConVar(entry.name)
        if cv then rows[#rows + 1] = { entry.name, cv:GetString() } end
    end

    net.Start("TPG_AdminSettings")
        net.WriteBool(ply:IsSuperAdmin())
        net.WriteUInt(#rows, 8)
        for _, row in ipairs(rows) do
            net.WriteString(row[1])
            net.WriteString(row[2])
        end
    net.Send(ply)
end)
