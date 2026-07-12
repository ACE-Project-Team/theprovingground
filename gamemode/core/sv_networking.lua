--[[
    Network Strings and Sync
]]

-- Initialize namespace FIRST
TPG.Net = TPG.Net or {}

-- Register all net strings
util.AddNetworkString("TPG_ChatMessage")
util.AddNetworkString("TPG_SyncState")
util.AddNetworkString("TPG_SyncScores")
util.AddNetworkString("TPG_SyncLimits")
util.AddNetworkString("TPG_SyncMapVote")
util.AddNetworkString("TPG_SyncVoteTally")
util.AddNetworkString("TPG_RequestState")
util.AddNetworkString("TPG_TeamPositions")

-- Sync game state to all clients, or to one player when given.
function TPG.Net.SyncState(target)
    net.Start("TPG_SyncState")
        net.WriteUInt(TPG.State.gameType or GAMEMODE_CP, 4)
        net.WriteUInt(TPG.State.scores[TEAM_GREEN] or 300, 16)
        net.WriteUInt(TPG.State.scores[TEAM_RED] or 300, 16)
    if target then net.Send(target) else net.Broadcast() end
end

-- Late joiners: TPG_SyncState is otherwise only broadcast at round setup, so a
-- player connecting mid-round kept the client default gametype ("CP") on their
-- HUD no matter what was actually running. The client asks for the state once
-- its HUD is up (InitPostEntity), which also guarantees it's ready to receive.
net.Receive("TPG_RequestState", function(_, ply)
    if not IsValid(ply) then return end
    TPG.Net.SyncState(ply)
    TPG.Net.SyncLimits()
end)

-- Sync scores only (frequent)
function TPG.Net.SyncScores()
    net.Start("TPG_SyncScores")
        net.WriteInt(math.floor(TPG.State.scores[TEAM_GREEN] or 300), 16)
        net.WriteInt(math.floor(TPG.State.scores[TEAM_RED] or 300), 16)
    net.Broadcast()
end

-- Sync team limits (current usage AND max limits)
function TPG.Net.SyncLimits()
    local greenLimits = TPG.State.limits[TEAM_GREEN] or {}
    local redLimits = TPG.State.limits[TEAM_RED] or {}
    local maxLimits = TPG.State.maxLimits or {}
    
    net.Start("TPG_SyncLimits")
        -- Current usage
        net.WriteUInt(greenLimits.props or 0, 12)
        net.WriteUInt(redLimits.props or 0, 12)
        net.WriteUInt(math.ceil((greenLimits.weight or 0) / 500), 13)
        net.WriteUInt(math.ceil((redLimits.weight or 0) / 500), 13)
        net.WriteUInt(math.ceil(greenLimits.points or 0), 16)
        net.WriteUInt(math.ceil(redLimits.points or 0), 16)
        
        -- Max limits
        net.WriteUInt(maxLimits.props or 300, 12)
        net.WriteUInt(math.ceil((maxLimits.weight or 100000) / 500), 13)
        net.WriteUInt(math.ceil(maxLimits.points or 5000), 20)  -- 20 bits for up to 1,048,575
    net.Broadcast()
end

-- Sync map vote options (with per-map display info + budgets).
-- `maps` is a list of { map = <filename>, category = <0-3> }.
function TPG.Net.SyncMapVote(maps)
    net.Start("TPG_SyncMapVote")
        net.WriteUInt(#maps, 4)
        net.WriteUInt(TPG.Config.mapVoteTime or 20, 8)
        for _, entry in ipairs(maps) do
            local info = TPG.Maps.GetVoteInfo(entry.map)
            net.WriteString(entry.map)
            net.WriteString(info.displayName)
            net.WriteUInt(entry.category or 0, 2)
            net.WriteUInt(math.min(info.points, 1048575), 20)
            net.WriteUInt(math.min(info.weight, 8191), 13)
            net.WriteUInt(math.min(info.props, 4095), 12)
            net.WriteUInt(math.min(info.objectives, 15), 4)
        end
    net.Broadcast()
end

-- Teammate map markers (cl_hud DrawTeammates) read positions clientside, but
-- the engine only refreshes a player's networked position while they're in your
-- PVS -- a teammate across the map would otherwise sit frozen at their last-seen
-- spot. Push each team its OWN members' live positions a few times a second so
-- the markers track everywhere. Sent per-team only, so it never leaks enemy
-- positions to the other side.
function TPG.Net.SyncTeamPositions()
    for _, teamId in ipairs({ TEAM_GREEN, TEAM_RED }) do
        local members = team.GetPlayers(teamId)
        if #members > 0 then
            local alive = {}
            for _, ply in ipairs(members) do
                if ply:Alive() then alive[#alive + 1] = ply end
            end

            net.Start("TPG_TeamPositions")
                net.WriteUInt(#alive, 7)   -- up to 127 teammates
                for _, ply in ipairs(alive) do
                    net.WriteUInt(ply:EntIndex(), 12)
                    net.WriteVector(ply:GetPos())
                end
            net.Send(members)
        end
    end
end

timer.Create("TPG_TeamPositions", 0.2, 0, TPG.Net.SyncTeamPositions)

-- Live vote counts per candidate.
function TPG.Net.SyncVoteTally(counts)
    net.Start("TPG_SyncVoteTally")
        net.WriteUInt(#counts, 4)
        for _, c in ipairs(counts) do
            net.WriteUInt(math.min(c, 255), 8)
        end
    net.Broadcast()
end