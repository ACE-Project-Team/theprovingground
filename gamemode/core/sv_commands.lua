--[[
    Console Commands
]]

-- Team change
concommand.Add("tpg_team", function(ply, cmd, args)
    local teamId = tonumber(args[1])
    
    if not teamId or not TPG.Teams[teamId] then
        TPG.Util.ChatMessage(ply, "[TPG] Invalid team.", Color(255, 0, 0))
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