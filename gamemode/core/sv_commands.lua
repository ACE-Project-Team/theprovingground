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
        TPG.Util.ChatMessage(ply, "[TPG] That weapon is not available.", Color(255, 0, 0))
        return
    end

    TPG.Util.SetPData(ply, key, class)
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
        " -- takes effect on the next map change.", Color(0, 255, 255))
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