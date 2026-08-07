--[[--
    Registers every `TPG_*` network string and the server-to-client sync senders.

    Must load before anything that calls `net.Start` on one of these strings or
    `net.Receive`s them; `util.AddNetworkString` runs at file scope, so simply
    loading this file is enough. The individual `TPG.Net.Sync*` functions are
    the write side only, called from wherever the underlying state changes
    (rounds, scoring, voting); there is no periodic full sync except team
    positions, which is deliberately its own timer.

    @module tpg.net
    @realm server
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

--- Send the game type and both teams' scores. Sent to everyone at round setup,
-- or to a single joining client in response to `TPG_RequestState` (see the
-- `net.Receive` below).
-- @tparam ?Player target Recipient, or nil to broadcast.
-- @realm server
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

--- Broadcast just the two ticket totals. Cheaper than @{tpg.net.SyncState} and
-- meant to be called often, whenever a score changes.
-- @realm server
function TPG.Net.SyncScores()
    net.Start("TPG_SyncScores")
        net.WriteInt(math.floor(TPG.State.scores[TEAM_GREEN] or 300), 16)
        net.WriteInt(math.floor(TPG.State.scores[TEAM_RED] or 300), 16)
    net.Broadcast()
end

--[[--
    Broadcast both teams' current prop/weight/point usage and the max limits.

    Weight is sent in 500-unit steps (`math.ceil(weight / 500)`), not raw, to
    fit the 13-bit field; the client is expected to multiply back out. Points
    get 20 bits on the max-limits field specifically to cover up to 1,048,575,
    per the inline comment on that line.

    @realm server
]]
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

--- Broadcast the map vote candidate list, with each entry's display info and
-- point/weight/prop/objective budgets (via `TPG.Maps.GetVoteInfo`) so the
-- vote UI can show them without a separate lookup.
-- @tparam table maps List of `{ map = <filename>, category = <0-3> }`.
-- @realm server
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

--[[--
    Push each team its own members' live positions for the teammate HUD markers.

    Teammate map markers (`cl_hud` DrawTeammates) read positions clientside,
    but the engine only refreshes a player's networked position while they're
    in your PVS, a teammate across the map would otherwise sit frozen at their
    last-seen spot. This pushes each team its OWN members' live positions a few
    times a second so the markers track everywhere. Sent per-team only, so it
    never leaks enemy positions to the other side. Only alive members are
    included. Run on a `timer.Create("TPG_TeamPositions", 0.2, 0, ...)` below,
    not called elsewhere.

    @realm server
]]
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

--- Broadcast live vote counts per candidate. Each count is clamped to 255
-- (8-bit field) before sending, so a candidate can't overflow the field on a
-- very large server.
-- @tparam table counts List of vote counts, index-aligned with the candidate
--  list already sent via @{tpg.net.SyncMapVote}.
-- @realm server
function TPG.Net.SyncVoteTally(counts)
    net.Start("TPG_SyncVoteTally")
        net.WriteUInt(#counts, 4)
        for _, c in ipairs(counts) do
            net.WriteUInt(math.min(c, 255), 8)
        end
    net.Broadcast()
end