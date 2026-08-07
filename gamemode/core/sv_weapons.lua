--[[--
    Weapon-enable state persistence: admin picks survive map changes and restarts.

    Loads/saves admin weapon choices (which bases and weapons are enabled) to
    `data/tpg/weapons.json` so they survive map changes and restarts, applies
    them on top of the discovered list via `TPG.Weapons.ApplyState`
    (`config/sh_weapons.lua`), and syncs them to clients so loadout menus
    match. Edited via the admin panel (`ui/cl_menu_weapons.lua`).

    Load order matters: this file calls `TPG.Weapons.ApplyState` at file scope,
    below, in addition to from the `InitPostEntity` hook, so
    `config/sh_weapons.lua` (which defines `TPG.Weapons` and `ApplyState`)
    must already have loaded, or that call errors.

    @module tpg.weaponrules
    @realm server
]]

util.AddNetworkString("TPG_WeaponState")     -- server -> client (current state)
util.AddNetworkString("TPG_WeaponStateSet")  -- client(admin) -> server (save)

local STATE_PATH = "tpg/weapons.json"

-- Read the saved state from data/tpg/weapons.json. Returns an empty table
-- (not nil) both when the file has never been written and when it exists but
-- fails to parse, so callers never need a separate nil check.
local function loadState()
    if not file.Exists(STATE_PATH, "DATA") then return {} end
    local raw = file.Read(STATE_PATH, "DATA")
    return (raw and util.JSONToTable(raw)) or {}
end

-- Persist `state` to data/tpg/weapons.json, creating the data/tpg directory
-- first if this is the first save on this server.
local function saveState(state)
    file.CreateDir("tpg")
    file.Write(STATE_PATH, util.TableToJSON(state, true))
end

-- Push the current TPG.Weapons.ServerState to one player, or everyone when
-- `ply` is nil/invalid.
local function sendState(ply)
    net.Start("TPG_WeaponState")
        net.WriteString(util.TableToJSON(TPG.Weapons.ServerState or {}))
    if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

-- Load + apply on map start.
local function applyAndBroadcast()
    TPG.Weapons.ServerState = loadState()
    TPG.Weapons.ApplyState(TPG.Weapons.ServerState)
    sendState(nil)
end

TPG.Weapons.ServerState = loadState()
TPG.Weapons.ApplyState(TPG.Weapons.ServerState)
hook.Add("InitPostEntity", "TPG_WeaponStateApply", applyAndBroadcast)

-- New players get the current state (a couple seconds after spawn, once their
-- client-side weapon list has been discovered).
hook.Add("PlayerInitialSpawn", "TPG_WeaponStateSync", function(ply)
    timer.Simple(2, function()
        if IsValid(ply) then sendState(ply) end
    end)
end)

-- Admin saves new settings from the panel.
net.Receive("TPG_WeaponStateSet", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local state = util.JSONToTable(net.ReadString() or "") or {}
    state.bases     = state.bases     or {}
    state.weapons   = state.weapons   or {}
    state.overrides = state.overrides or {}

    TPG.Weapons.ServerState = state
    saveState(state)
    TPG.Weapons.ApplyState(state)
    sendState(nil)  -- live-update everyone's menus

    TPG.Util.ChatMessage(ply, "[TPG] Weapon settings saved (persists across maps).", Color(0, 255, 0))
end)
