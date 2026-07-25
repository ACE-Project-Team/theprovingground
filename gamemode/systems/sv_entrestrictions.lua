--[[
    Entity / Weapon Spawn Restrictions (server)

    TPG is a vehicle-combat gamemode. The only things a player should be putting
    into the world are props, ACE components and vehicles. Everything else the
    sandbox spawn menu offers is either a free power-up that sidesteps the whole
    damage model (health kits, suit batteries, the bouncy ball's heal-on-touch)
    or a way to hurt people outside the vehicle fight (combine mines, NPCs, hand
    weapons lying on the ground). None of it was ever meant to be reachable --
    it just was, because sandbox's spawn menu is wide open.

    Blocked on every path we can see:
        PlayerSpawnSENT / PlayerSpawnNPC / PlayerSpawnSWEP / PlayerGiveSWEP
        the *Spawned* variants (belt and braces, in case something spawns an
            entity without asking first)
        dupe pastes (TPG.Restrictions.StripBlocked, called from sv_duplication)

    Admins bypass everything -- they need the tools to run an event.
]]

TPG.Restrictions = TPG.Restrictions or {}
local R = TPG.Restrictions

-- Class-name patterns (matched lowercase). These are broad on purpose: the
-- server runs whatever addons are installed, so naming the individual bad
-- entities is a losing game -- naming the bad FAMILIES is not.
R.BlockedPatterns = {
    ["^item_"]   = "pickups (health, armour and ammo) are not part of this gamemode",
    ["^npc_"]    = "NPCs are not part of this gamemode",
    ["^weapon_"] = "weapons can't be spawned into the world",
}

-- Exact classes that don't fall into a family above.
R.Blocked = {
    ["sent_ball"]        = "the bouncy ball heals whoever touches it",
    ["combine_mine"]     = "it damages players outside the vehicle fight",
    ["sent_miniturret"]  = "it damages players outside the vehicle fight",
    ["env_explosion"]    = "it damages players outside the vehicle fight",
    ["env_fire"]         = "it damages players outside the vehicle fight",
    ["item_suitcharger"] = "pickups (health, armour and ammo) are not part of this gamemode",
    ["item_healthcharger"] = "pickups (health, armour and ammo) are not part of this gamemode",
}

-- Returns nil if the class is fine, or the reason string if it's blocked.
function R.BlockReason(class)
    if not isstring(class) then return nil end
    class = string.lower(class)

    local exact = R.Blocked[class]
    if exact then return exact end

    for pattern, reason in pairs(R.BlockedPatterns) do
        if string.match(class, pattern) then return reason end
    end

    return nil
end

function R.IsBlocked(class)
    return R.BlockReason(class) ~= nil
end

-- Shared gate. Returns false (blocking the spawn) when the class is restricted.
local lastTold = {}
local function Gate(ply, class)
    if not IsValid(ply) or ply:IsAdmin() then return end

    local reason = R.BlockReason(class)
    if not reason then return end

    -- The spawn menu can fire a hook per click; don't carpet the chat.
    if (lastTold[ply] or 0) < CurTime() then
        lastTold[ply] = CurTime() + 2
        TPG.Util.ChatMessage(ply, "[TPG] " .. class .. " is restricted -- " .. reason .. ".",
            Color(255, 100, 100))
    end
    return false
end

-- SWEPs (both "give me one" and "put one on the ground") are handled by the
-- blanket admin-only rule in player/sv_protection.lua -- no class list needed.
hook.Add("PlayerSpawnSENT", "TPG_RestrictSENT", function(ply, class) return Gate(ply, class) end)
hook.Add("PlayerSpawnNPC",  "TPG_RestrictNPC",  function(ply, class) return Gate(ply, class) end)

-- If something slipped past the gate (an addon spawning on its own, a tool, a
-- stale hook order), take it back out. This is the last line, not the first.
local function Sweep(ply, ent)
    if not IsValid(ent) then return end
    if IsValid(ply) and ply:IsAdmin() then return end
    if R.IsBlocked(ent:GetClass()) then ent:Remove() end
end

hook.Add("PlayerSpawnedSENT", "TPG_RestrictSweepSENT", Sweep)
hook.Add("PlayerSpawnedNPC",  "TPG_RestrictSweepNPC",  Sweep)
hook.Add("PlayerSpawnedSWEP", "TPG_RestrictSweepSWEP", Sweep)

-- Dupes are the other way in: a saved contraption can carry a health kit or a
-- mine bolted to the hull. Called from sv_duplication on paste. Returns how
-- many entities were pulled out so the caller can tell the player.
function R.StripBlocked(entList, ply)
    if IsValid(ply) and ply:IsAdmin() then return 0 end

    local removed = 0
    for _, ent in pairs(entList or {}) do
        if IsValid(ent) and R.IsBlocked(ent:GetClass()) then
            ent:Remove()
            removed = removed + 1
        end
    end
    return removed
end

hook.Add("PlayerDisconnected", "TPG_RestrictCleanup", function(ply)
    lastTold[ply] = nil
end)
