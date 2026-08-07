--[[--
    Client-console autocomplete shim for server-only concommands.

    Console commands made visible and usable from a client console: admin
    commands plus everyday ones like `tpg_team`.

    The gameplay/admin concommands are registered server-side (`sv_commands.lua`,
    `sv_custom_points.lua`). Server-only concommands never appear in a CLIENT's
    console autocomplete, so an admin on a dedicated server "can't see" them and
    has to know the exact spelling. This module registers a matching client-side
    stub for each so it autocompletes, then forwards the call to the server over
    a net channel where the ORIGINAL server concommand runs (via
    `concommand.Run`), keeping its own admin/superadmin checks. Nothing about
    the server logic changes, this is purely a discoverability/forwarding shim.

    @{tpg.commands.List} is the single source of truth for which commands get
    this treatment; adding an admin concommand elsewhere and forgetting to list
    it here means it stays invisible in a client's autocomplete, though it
    still works if typed exactly.

    On the server this file installs an allow-list gate on the forwarding net
    message, so a crafted `TPG_ClientCmd` message can only invoke one of the
    listed commands, never an arbitrary server concommand; the commands' own
    admin/superadmin checks still apply on top, so this channel grants no extra
    privilege by itself. On the client it registers the stub concommands that
    forward into that channel.

    @module tpg.commands
    @realm shared
]]

TPG.Commands = TPG.Commands or {}

--- The commands surfaced in a client console via the forwarding shim above.
-- Each entry is `{ name = <concommand>, help = <shown in autocomplete> }`;
-- `name` must match the real server concommand exactly. This is the allow-list
-- consulted server-side, so a command left out here cannot be invoked through
-- this net channel at all, even by an admin who types it correctly, though
-- typing it directly still works if the client happens to be running on the
-- listen-server host.
-- @realm shared
TPG.Commands.List = {
    { name = "tpg_team",           help = "Join a team: tpg_team green | red | spec" },
    { name = "tpg_admin_restart",  help = "Admin: restart the current round." },
    { name = "tpg_admin_endround", help = "Admin: end the round (arg1 = winning team id)." },
    { name = "tpg_admin_scramble", help = "Admin: scramble the teams immediately (no vote)." },
    { name = "tpg_admin_stats_reset", help = "Superadmin: wipe lifetime stats and the leaderboard." },
    { name = "tpg_economy",        help = "Admin: toggle per-player economy (applies next map). No arg = status." },
    { name = "tpg_points_reload",  help = "Admin: apply placed custom points and restart the round." },
    { name = "tpg_points_clear",   help = "Superadmin: clear all custom points for this map." },
}

if SERVER then
    util.AddNetworkString("TPG_ClientCmd")

    -- Allow-list so a crafted net message can only invoke our own commands, never
    -- an arbitrary server concommand. The commands themselves still re-check
    -- admin/superadmin, so this channel grants no extra privilege.
    local allowed = {}
    for _, c in ipairs(TPG.Commands.List) do allowed[c.name] = true end

    net.Receive("TPG_ClientCmd", function(_, ply)
        if not IsValid(ply) then return end
        local name = net.ReadString()
        if not allowed[name] then return end

        local args = net.ReadTable() or {}
        concommand.Run(ply, name, args, table.concat(args, " "))
    end)
else
    for _, c in ipairs(TPG.Commands.List) do
        local name = c.name
        concommand.Add(name, function(_, _, args)
            net.Start("TPG_ClientCmd")
            net.WriteString(name)
            net.WriteTable(args or {})
            net.SendToServer()
        end, nil, c.help)
    end
end
