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

-- Sync game state to all clients
function TPG.Net.SyncState()
    net.Start("TPG_SyncState")
        net.WriteUInt(TPG.State.gameType or GAMEMODE_CP, 4)
        net.WriteUInt(TPG.State.scores[TEAM_GREEN] or 300, 16)
        net.WriteUInt(TPG.State.scores[TEAM_RED] or 300, 16)
    net.Broadcast()
end

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

-- Live vote counts per candidate.
function TPG.Net.SyncVoteTally(counts)
    net.Start("TPG_SyncVoteTally")
        net.WriteUInt(#counts, 4)
        for _, c in ipairs(counts) do
            net.WriteUInt(math.min(c, 255), 8)
        end
    net.Broadcast()
end