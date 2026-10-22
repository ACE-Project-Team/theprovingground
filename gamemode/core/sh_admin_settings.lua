--[[--
    Shared allow-list of server convars the Q-menu settings panel may change.

    One table, read by both realms, so the client's controls and the server's
    validation cannot drift apart: a name, type, limits, label and group are
    written here once. Nothing in this file is applied by itself. The server
    side (`core/sv_admin_settings.lua`) is the only place a value is written, and
    the client (`ui/cl_qmenu.lua`) only builds controls from this list.

    Each entry is `{ name, type, label, group, rank, min, max, decimals }`:

      * `type` is `"bool"`, `"int"` or `"number"`.
      * `rank` is `"admin"` or `"superadmin"`. The server checks it on every
        change; the client uses it only to hide entries.
      * `min`, `max` and `decimals` exist for numeric types.

    Adding a setting means one line here and nothing else. The convar must
    still be created by its own system; an entry whose convar does not exist is
    skipped, not created.

    @module tpg.adminsettings
    @realm shared
]]

TPG.AdminSettings = TPG.AdminSettings or {}

--- Group order used by the Q-menu panel.
-- @realm shared
TPG.AdminSettings.Groups = { "Economy", "Gameplay", "Bots", "Server" }

--- Every server convar the panel may change.
-- @realm shared
TPG.AdminSettings.List = {
    { name = "tpg_economy_enabled",         type = "bool",   group = "Economy",  rank = "superadmin", label = "Economy always on" },
    { name = "tpg_economy_random",          type = "bool",   group = "Economy",  rank = "admin",      label = "Economy in random rounds" },
    { name = "tpg_economy_rebill",          type = "bool",   group = "Economy",  rank = "admin",      label = "Charge for vehicle changes" },

    { name = "tpg_points_refresh_interval", type = "number", group = "Gameplay", rank = "admin",      label = "Point rebuild interval (s)", min = 0, max = 600, decimals = 2 },
    { name = "tpg_weapons_base_only",       type = "bool",   group = "Gameplay", rank = "admin",      label = "ACE weapons only" },

    { name = "tpg_bots_fill",               type = "int",    group = "Bots",     rank = "superadmin", label = "Fighters per team", min = 0, max = 16, decimals = 0 },
    { name = "tpg_bots_difficulty",         type = "int",    group = "Bots",     rank = "superadmin", label = "Difficulty", min = 0, max = 4, decimals = 0 },
    { name = "tpg_bots_at_ratio",           type = "number", group = "Bots",     rank = "superadmin", label = "Anti-tank share", min = 0, max = 1, decimals = 2 },
    { name = "tpg_bots_armor_points",       type = "int",    group = "Bots",     rank = "superadmin", label = "Armor points", min = 0, max = 100000, decimals = 0 },
    { name = "tpg_bots_reward_scale",       type = "number", group = "Bots",     rank = "superadmin", label = "Bot kill reward share", min = 0, max = 1, decimals = 2 },
    { name = "tpg_bots_respawn_delay",      type = "number", group = "Bots",     rank = "superadmin", label = "Bot respawn delay (s)", min = 0, max = 120, decimals = 0 },
    { name = "tpg_bots_drops",              type = "bool",   group = "Bots",     rank = "superadmin", label = "Bots drop weapons" },
    { name = "tpg_bots_corpses",            type = "bool",   group = "Bots",     rank = "superadmin", label = "Bot corpses stay" },
    { name = "tpg_bots_friendly_fire",      type = "bool",   group = "Bots",     rank = "superadmin", label = "Players can hurt teammate bots" },
    { name = "tpg_bots_cai_wallbang",       type = "bool",   group = "Bots",     rank = "superadmin", label = "Bots shoot through walls (Combat AI)" },

    { name = "tpg_collection_min_maps",     type = "int",    group = "Server",   rank = "superadmin", label = "Map collection reminder below", min = 0, max = 64, decimals = 0 },
}

--- Find the allow-list entry for a convar name.
-- @tparam string name Convar name, exact match.
-- @treturn table|nil The entry, or nil if the name is not allow-listed.
-- @realm shared
function TPG.AdminSettings.Find(name)
    for _, entry in ipairs(TPG.AdminSettings.List) do
        if entry.name == name then return entry end
    end
    return nil
end

--- Whether a player may change an allow-listed entry.
-- Superadmin entries need a superadmin. Everything else needs an admin, and
-- every superadmin is also an admin.
-- @tparam table entry An entry from @{TPG.AdminSettings.List}.
-- @tparam Player ply The player asking.
-- @treturn boolean
-- @realm shared
function TPG.AdminSettings.Allowed(entry, ply)
    if not IsValid(ply) then return false end
    if entry.rank == "superadmin" then return ply:IsSuperAdmin() end
    return ply:IsAdmin()
end

--- Validate and clamp a raw value for an allow-listed entry.
-- Returns the string to hand to the convar, or nil and a reason. Bools accept
-- 1/0, true/false, yes/no and on/off. Numbers are clamped to the entry's
-- limits, and ints are rounded first.
-- @tparam table entry An entry from @{TPG.AdminSettings.List}.
-- @tparam string raw The value as typed or sent.
-- @treturn string|nil The value to set, or nil.
-- @treturn string|nil Why it was refused, when the first result is nil.
-- @treturn boolean Whether the value was clamped to a limit.
-- @realm shared
function TPG.AdminSettings.Clamp(entry, raw)
    if raw == nil or raw == "" then return nil, "No value given." end

    if entry.type == "bool" then
        local v = string.lower(tostring(raw))
        if v == "1" or v == "true" or v == "yes" or v == "on" then return "1", nil, false end
        if v == "0" or v == "false" or v == "no" or v == "off" then return "0", nil, false end
        return nil, "Use 1 or 0 for " .. entry.name .. "."
    end

    local n = tonumber(raw)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil, "Not a number: " .. tostring(raw) .. "."
    end

    if entry.type == "int" then n = math.Round(n) end

    local clamped = false
    if n < entry.min then n, clamped = entry.min, true end
    if n > entry.max then n, clamped = entry.max, true end

    if entry.type == "int" then
        return string.format("%d", n), nil, clamped
    end
    return string.format("%g", n), nil, clamped
end
