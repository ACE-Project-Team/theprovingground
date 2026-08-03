--[[
    Console Commands
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

    Rate-limited because it is, mechanically, a suicide: without the limit it
    would be a free escape from a losing fight.
]]
local REKIT_INTERVAL = 20

concommand.Add("tpg_rekit", function(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not TPG.Util.IsOnTeam(ply) then return end

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