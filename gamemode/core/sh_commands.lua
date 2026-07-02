--[[
    Admin console commands, made visible + usable from a client console.

    The gameplay/admin concommands are registered server-side (sv_commands.lua,
    sv_custom_points.lua). Server-only concommands never appear in a CLIENT's
    console autocomplete, so an admin on a dedicated server "can't see" them and
    has to know the exact spelling. This module registers a matching client-side
    stub for each so it autocompletes, then forwards the call to the server over a
    net channel where the ORIGINAL server concommand runs (via concommand.Run),
    keeping its own admin/superadmin checks. Nothing about the server logic
    changes -- this is purely a discoverability/forwarding shim.
]]

TPG.Commands = TPG.Commands or {}

-- The commands worth surfacing in a client console. Names must match the
-- server concommands exactly. `help` is shown in autocomplete.
TPG.Commands.List = {
    { name = "tpg_admin_restart",  help = "Admin: restart the current round." },
    { name = "tpg_admin_endround", help = "Admin: end the round (arg1 = winning team id)." },
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
