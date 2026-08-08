--[[--
    Gameplay and admin console commands: team/loadout changes, re-kit, votes, admin actions.

    Pure hook/concommand registration, no exported API; every `concommand.Add`
    below is reachable directly from a server console, and (for the ones
    listed in `core/sh_commands.lua`) also from a client console through that
    file's forwarding shim. Each command re-checks its own admin/superadmin
    requirement, since the forwarding channel is only an allow-list, not a
    privilege grant.

    @module tpg.consolecommands
    @realm server
]]

-- Team change. Accepts friendly names and short numbers as well as raw team
-- ids -- the menu used to advertise "tpg_team 1/2", which the old numeric-id
-- check rejected (ids are 2001/2002), so the console path never worked.
local TEAM_ALIASES = {
    ["green"] = TEAM_GREEN, ["g"] = TEAM_GREEN, ["1"] = TEAM_GREEN,
    ["red"]   = TEAM_RED,   ["r"] = TEAM_RED,   ["2"] = TEAM_RED,
    ["spec"]  = TEAM_UNASSIGNED, ["spectate"] = TEAM_UNASSIGNED,
    ["spectator"] = TEAM_UNASSIGNED, ["0"] = TEAM_UNASSIGNED,
}

concommand.Add("tpg_team", function(ply, cmd, args)
    local arg = string.lower(tostring(args[1] or ""))
    local teamId = TEAM_ALIASES[arg] or tonumber(arg)

    if not teamId or not TPG.Teams[teamId] then
        TPG.Util.ChatMessage(ply, "[TPG] Invalid team. Use: tpg_team green | red | spec", Color(255, 0, 0))
        return
    end

    TPG.PlayerTeams.AssignPlayer(ply, teamId)
end)

-- Loadout change. Weapons are addressed by class string (validated against the
-- enabled, discovered set so a crafted command can't hand out arbitrary SWEPs);
-- armor stays numeric.
concommand.Add("tpg_loadout", function(ply, cmd, args)
    local category = tonumber(args[1])
    if not category then return end

    if category == 4 then
        local armorId = tonumber(args[2])
        if armorId and TPG.Armor[armorId] then
            TPG.Util.SetPData(ply, "Armor", armorId)
        end
        return
    end

    local key = ({ [1] = "Primary", [2] = "Secondary", [3] = "Special" })[category]
    if not key then return end

    local class = args[2]
    if not class or class == "" then return end

    local weapon = TPG.GetWeapon(key, class)
    if not weapon or weapon.enabled == false then
        --[[
            Two very different failures used to share one message.

            An admin-disabled weapon is a real "no". A weapon the server has in
            a DIFFERENT category is a bug: the client offered it under one slot
            because the SWEP declares Slot inside `if CLIENT`, so the two realms
            disagree about where it lives (see sh_weapons_config's Overrides).
            Nobody could tell those apart from the chat line, and the second one
            left no trace at all -- so it says so, and names the fix in the
            server console where an operator will actually see it.
        ]]
        if weapon then
            TPG.Util.ChatMessage(ply, "[TPG] That weapon has been disabled by an admin.", Color(255, 0, 0))
            return
        end

        for _, other in ipairs({ "Primary", "Secondary", "Special" }) do
            if other ~= key and TPG.GetWeapon(other, class) then
                ErrorNoHalt("[TPG] " .. class .. " was picked as " .. key ..
                    " but the server has it under " .. other .. ". The SWEP most likely " ..
                    "sets SWEP.Slot inside `if CLIENT`; add a category override for it " ..
                    "in config/sh_weapons_config.lua.\n")
                break
            end
        end

        TPG.Util.ChatMessage(ply, "[TPG] That weapon is not available.", Color(255, 0, 0))
        return
    end

    TPG.Util.SetPData(ply, key, class)
end)

--[[
    Fallback change: what a slot resolves to when its pick is refused.

    Separate from tpg_loadout rather than a fifth category on it, because the
    two are validated against different rules -- a pick may be priced, a
    fallback may not (@{TPG.Gear.FallbackAllowed}) -- and folding them together
    would mean one command whose second argument means different things
    depending on the first.
]]
local FALLBACK_KEYS = { [1] = "Primary", [2] = "Secondary", [3] = "Special" }

concommand.Add("tpg_fallback", function(ply, cmd, args)
    local key = FALLBACK_KEYS[tonumber(args[1] or "")]
    if not key then return end

    local class = args[2]
    if not class or class == "" then return end

    local ok, why = TPG.Gear.FallbackAllowed(key, class)
    if not ok then
        TPG.Util.ChatMessage(ply, "[TPG] " .. (why or "That cannot be a fallback."),
            Color(255, 0, 0))
        return
    end

    TPG.Util.SetPData(ply, "Fallback" .. key, class)
end)

--[[
    Respawn to apply a loadout change.

    The menu used to run plain `kill` for this, which made a loadout tweak cost
    the same as being shot: a death on your record, and -- under the per-player
    economy -- a second charge for premium gear you had already bought and never
    got to fire. Neither is a thing the player did wrong.

    So it's its own command. It flags the death as a re-kit, which the stats
    system skips (systems/sv_stats.lua) and the gear system reads as "keep what
    this life already paid for" (systems/sv_gear.lua). Picking something you
    HAVEN'T paid for still charges normally, so this isn't a way to shop for
    free -- it only stops you being billed twice for the same item.

    Mechanically this IS a suicide, and the thing worth preventing is using it
    as a free escape from a losing fight -- press it as the tank rounds the
    corner and you reappear at spawn, at full health, having lost nothing.

    So the gate is combat, not geography. Inside your own spawn it's always
    allowed (there is nothing to escape from, and IsInSafezone treats a map with
    no published spawns as all-safe, so the button works during the pre-round
    wait). Outside, it's allowed once you've gone COMBAT_WINDOW seconds without
    taking damage -- long enough that you can't use it to dodge the shot that
    was already on its way, short enough that walking out to the wrong loadout
    doesn't mean a hike back to spawn.

    "Taking damage" deliberately means damage that LANDED: see
    sv_protection.lua, where the clock is stamped. Someone under spawn
    protection or otherwise in god mode isn't in a fight in any sense that
    matters here, and shouldn't be locked out by hits that did nothing.

    Still rate-limited on top of all that, purely so a held-down bind can't
    respawn a player every frame.
]]
local REKIT_INTERVAL = 5
local COMBAT_WINDOW  = 8

concommand.Add("tpg_rekit", function(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not TPG.Util.IsOnTeam(ply) then return end

    if TPG.Protection and TPG.Protection.IsInSafezone
        and not TPG.Protection.IsInSafezone(ply) then
        local since = TPG.Protection.SecondsSinceDamage(ply)
        if since < COMBAT_WINDOW then
            TPG.Util.ChatMessage(ply, "[TPG] You're in a fight. Wait " ..
                math.ceil(COMBAT_WINDOW - since) ..
                "s without taking damage, or head back to your spawn zone.",
                Color(255, 200, 0))
            return
        end
    end

    local pState = TPG.State.GetPlayer(ply)
    local ready  = (pState.lastRekit or -math.huge) + REKIT_INTERVAL

    if CurTime() < ready then
        TPG.Util.ChatMessage(ply, "[TPG] Wait " .. math.ceil(ready - CurTime()) ..
            "s before respawning again.", Color(255, 200, 0))
        return
    end

    pState.lastRekit = CurTime()
    pState.rekit     = true
    ply:Kill()
end)

-- Easy vehicle entry
concommand.Add("tpg_easyentry", function(ply, cmd, args)
    if TPG.Vehicles and TPG.Vehicles.EasyEntry then
        TPG.Vehicles.EasyEntry(ply)
    end
end)

-- RTV
concommand.Add("tpg_rtv", function(ply, cmd, args)
    if TPG.Voting and TPG.Voting.RockTheVote then
        TPG.Voting.RockTheVote(ply)
    end
end)

-- Vote scramble
concommand.Add("tpg_scramble", function(ply, cmd, args)
    if TPG.Voting and TPG.Voting.VoteScramble then
        TPG.Voting.VoteScramble(ply)
    end
end)

-- Map vote
concommand.Add("tpg_votemap", function(ply, cmd, args)
    local mapIndex = tonumber(args[1])
    if mapIndex and TPG.Voting and TPG.Voting.CastMapVote then
        TPG.Voting.CastMapVote(ply, mapIndex)
    end
end)

-- Economy toggle (admin). The underlying state is the server convar
-- tpg_economy_enabled, which a connected admin can't see/set from their client
-- on a dedicated server -- only at the server console. This concommand runs
-- server-side, so any admin can flip it in-game. Latched, so it applies on the
-- NEXT map change (matching the convar's behaviour).
concommand.Add("tpg_economy", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        TPG.Util.ChatMessage(ply, "[TPG] Admins only.", Color(255, 0, 0))
        return
    end

    local cv = GetConVar("tpg_economy_enabled")
    if not cv then
        TPG.Util.ChatMessage(ply, "[TPG] Economy system not loaded.", Color(255, 0, 0))
        return
    end

    -- No argument = report current state; otherwise set 0/1.
    if args[1] == nil or args[1] == "" then
        local msg = "[TPG] Per-player economy is " .. (cv:GetBool() and "ENABLED" or "DISABLED") ..
            " (active this map: " .. ((TPG.Economy and TPG.Economy.Active) and "yes" or "no") ..
            "). Use tpg_economy 1/0; applies next map."
        TPG.Util.ChatMessage(ply, msg, Color(0, 255, 255))
        return
    end

    local on = tobool(args[1])
    cv:SetBool(on)
    TPG.Util.ChatBroadcast("[TPG] Per-player economy " .. (on and "ENABLED" or "DISABLED") ..
        " - takes effect on the next map change.", Color(0, 255, 255))
end)

-- Admin commands
concommand.Add("tpg_admin_restart", function(ply, cmd, args)
    if not ply:IsAdmin() then return end
    TPG.Rounds.Setup()
end)

concommand.Add("tpg_admin_endround", function(ply, cmd, args)
    if not ply:IsAdmin() then return end
    local winner = tonumber(args[1]) or TEAM_GREEN
    TPG.Rounds.EndRound(winner)
end)

-- Immediate team scramble, no vote (the player-initiated tpg_scramble is the
-- voted path).
concommand.Add("tpg_admin_scramble", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    TPG.Util.ChatBroadcast("[TPG] An admin scrambled the teams.", Color(0, 255, 255))
    TPG.PlayerTeams.ScrambleAll()
end)

-- Wipe the lifetime stats/leaderboard. Destructive, so superadmin-only; useful
-- for clearing corrupted test data (e.g. phantom listen-server-host records).
concommand.Add("tpg_admin_stats_reset", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        TPG.Util.ChatMessage(ply, "[TPG] Superadmins only.", Color(255, 0, 0))
        return
    end
    if TPG.Stats and TPG.Stats.ResetAll then
        TPG.Stats.ResetAll()
        TPG.Util.ChatBroadcast("[TPG] Lifetime stats and the leaderboard have been reset.", Color(0, 255, 255))
    end
end)