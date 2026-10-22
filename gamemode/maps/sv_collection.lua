--[[--
    The official TPG map collection hint.

    A server with only a handful of TPG-ready maps installed plays a thin
    rotation. This file counts the installed maps that TPG supports (a built-in
    config in `TPG.Maps.Configs`, or a saved layout under `data/tpg/points/`),
    and when there are fewer than `tpg_collection_min_maps` of them it points
    the people who can fix it at the official map collection: a console notice
    at startup, and a popup for superadmins and the listen-server host.

    The client half is @{tpg.collection} (`ui/cl_collection.lua`).

    @module tpg.collection.server
    @realm server
]]

TPG.Maps = TPG.Maps or {}
TPG.Maps.CollectionId = "3645840394"

util.AddNetworkString("TPG_CollectionHint")

local cvMin = CreateConVar("tpg_collection_min_maps", "4", FCVAR_ARCHIVE,
    "Remind admins about the TPG map collection when fewer supported maps than this are installed (0 = never)")

local CACHE_SECONDS = 60
local cache, cacheAt = nil, 0

local function scan()
    local found, seen = {}, {}

    for _, f in ipairs(file.Find("maps/*.bsp", "GAME") or {}) do
        local name = string.lower(string.StripExtension(f))
        local supported = TPG.Maps.Configs[name] ~= nil
            or file.Exists(TPG.Maps.LayoutPath(name), "DATA")

        if supported and not seen[name] then
            seen[name] = true
            table.insert(found, name)
        end
    end

    table.sort(found)
    return found
end

--- The installed maps TPG supports, sorted by name. The result is cached for
-- 60 seconds so joins do not rescan the disk; treat the table as read-only.
-- @treturn table Array of lowercase map names.
-- @realm server
function TPG.Maps.SupportedInstalled()
    if not cache or SysTime() - cacheAt > CACHE_SECONDS then
        cache = scan()
        cacheAt = SysTime()
    end

    return cache
end

--- Whether the server is below the `tpg_collection_min_maps` threshold.
-- @treturn boolean False when the convar is 0 (never remind).
-- @realm server
function TPG.Maps.NeedsCollection()
    local min = cvMin:GetInt()
    return min > 0 and #TPG.Maps.SupportedInstalled() < min
end

-- Send one player the hint. Counts are clamped to what a UInt8 can carry.
local function sendHint(ply)
    local count = math.Clamp(#TPG.Maps.SupportedInstalled(), 0, 255)
    local min = math.Clamp(cvMin:GetInt(), 0, 255)

    net.Start("TPG_CollectionHint")
        net.WriteUInt(count, 8)
        net.WriteUInt(min, 8)
        net.WriteString(TPG.Maps.CollectionId)
    net.Send(ply)
end

hook.Add("InitPostEntity", "TPG_CollectionNotice", function()
    timer.Simple(5, function()
        if not TPG.Maps.NeedsCollection() then return end

        local count = #TPG.Maps.SupportedInstalled()
        MsgC(Color(255, 200, 60), "[TPG] Only " .. count .. " supported map(s) installed, the server wants " .. cvMin:GetInt() .. ".\n")
        MsgC(Color(255, 200, 60), "[TPG] Get the official TPG map collection: https://steamcommunity.com/sharedfiles/filedetails/?id=" .. TPG.Maps.CollectionId .. "\n")
        MsgC(Color(255, 200, 60), "[TPG] Set tpg_collection_min_maps 0 to silence this notice.\n")
    end)
end)

hook.Add("PlayerInitialSpawn", "TPG_CollectionHint", function(ply)
    timer.Simple(8, function()
        if not IsValid(ply) then return end
        if not (ply:IsSuperAdmin() or ply:IsListenServerHost()) then return end
        if not TPG.Maps.NeedsCollection() then return end

        sendHint(ply)
    end)
end)

concommand.Add("tpg_collection", function(ply)
    local valid = IsValid(ply)

    if valid and not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Superadmin only.\n")
        return
    end

    local function out(line)
        if valid then
            ply:PrintMessage(HUD_PRINTCONSOLE, line .. "\n")
        else
            print(line)
        end
    end

    local supported = TPG.Maps.SupportedInstalled()
    out("[TPG] " .. #supported .. " supported map(s) installed (threshold " .. cvMin:GetInt() .. "):")
    for _, name in ipairs(supported) do
        out("  " .. name)
    end

    if valid then sendHint(ply) end
end, nil, "Superadmin: list installed TPG maps and show the map collection hint.")
