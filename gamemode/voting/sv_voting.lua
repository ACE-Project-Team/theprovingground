--[[
    Voting System - RTV, Scramble, Map Vote
]]

TPG.Voting = TPG.Voting or {}

-- Map lists
TPG.Voting.MapLists = {
    Open = {
        "gm_emp_palmbay", "gm_emp_midbridge", "gm_greenchoke", "gm_emp_arid",
        "gm_baik_coast_03", "gm_baik_coast_03_night", "gm_baik_frontline",
        "gm_baik_trenches", "gm_baik_valley_split", "gm_diprip_village",
        "gm_emp_bush", "gm_greenland", "gm_islandrain_v3", "gm_pacific_island_a3",
        "gm_toysoldiers",
    },
    Urban = {
        "gm_emp_manticore", "gm_baik_stalingrad", "gm_bigcity_improved",
        "gm_diprip_refinery", "gm_emp_commandergrad", "gm_freedom_city",
        "gm_yanov", "gm_baik_construct_draft1", "gm_baik_citycentre_v3",
        "gm_de_port_opened_v2",
    },
}

function TPG.Voting.RockTheVote(ply)
    local pState = TPG.State.GetPlayer(ply)
    pState.votes.rtv = true
    
    TPG.Util.ChatMessage(ply, "[TPG] You voted to rock the vote.", Color(0, 255, 0))
    
    -- Count votes
    local voteCount = 0
    local totalPlayers = #player.GetAll()
    
    for _, p in ipairs(player.GetAll()) do
        local ps = TPG.State.GetPlayer(p)
        if ps.votes.rtv then
            voteCount = voteCount + 1
        end
    end
    
    local required = math.max(math.ceil(totalPlayers * TPG.Config.rtvPercentRequired), TPG.Config.rtvMinPlayers)
    
    if voteCount >= required then
        TPG.Util.ChatBroadcast("[TPG] RTV passed! Starting map vote.", Color(0, 255, 0))
        TPG.Voting.StartMapVote()
        
        -- Reset RTV votes
        for _, p in ipairs(player.GetAll()) do
            local ps = TPG.State.GetPlayer(p)
            ps.votes.rtv = false
        end
    else
        local needed = required - voteCount
        TPG.Util.ChatBroadcast("[TPG] " .. needed .. " more votes needed to change map.", Color(255, 255, 0))
    end
end

function TPG.Voting.VoteScramble(ply)
    local pState = TPG.State.GetPlayer(ply)
    pState.votes.scramble = true
    
    TPG.Util.ChatMessage(ply, "[TPG] You voted to scramble teams.", Color(0, 255, 0))
    
    -- Count votes
    local voteCount = 0
    local totalPlayers = #player.GetAll()
    
    for _, p in ipairs(player.GetAll()) do
        local ps = TPG.State.GetPlayer(p)
        if ps.votes.scramble then
            voteCount = voteCount + 1
        end
    end
    
    local required = math.max(math.ceil(totalPlayers * TPG.Config.scramblePercent), 2)
    
    if voteCount >= required then
        TPG.Util.ChatBroadcast("[TPG] Vote passed! Scrambling teams.", Color(0, 255, 0))
        TPG.PlayerTeams.ScrambleAll()
        
        -- Reset scramble votes
        for _, p in ipairs(player.GetAll()) do
            local ps = TPG.State.GetPlayer(p)
            ps.votes.scramble = false
        end
    else
        local needed = required - voteCount
        TPG.Util.ChatBroadcast("[TPG] " .. needed .. " more votes needed to scramble.", Color(255, 255, 0))
    end
end

function TPG.Voting.StartMapVote()
    TPG.State.voting.active = true
    TPG.State.voting.endTime = CurTime() + TPG.Config.mapVoteTime
    TPG.State.voting.votes = {}
    
    -- Generate map choices
    local maps = {}
    
    -- 2 open maps
    local openMaps = table.Copy(TPG.Voting.MapLists.Open)
    for i = 1, 2 do
        if #openMaps > 0 then
            local idx = math.random(1, #openMaps)
            table.insert(maps, openMaps[idx])
            table.remove(openMaps, idx)
        end
    end
    
    -- 1 urban map
    local urbanMaps = table.Copy(TPG.Voting.MapLists.Urban)
    if #urbanMaps > 0 then
        local idx = math.random(1, #urbanMaps)
        table.insert(maps, urbanMaps[idx])
        table.remove(urbanMaps, idx)
    end
    
    -- 1 bonus (random from either)
    local allMaps = table.Add(table.Copy(openMaps), table.Copy(urbanMaps))
    if #allMaps > 0 then
        local idx = math.random(1, #allMaps)
        table.insert(maps, allMaps[idx])
    end
    
    TPG.State.voting.maps = maps
    
    -- Sync to clients
    if TPG.Net and TPG.Net.SyncMapVote then
        TPG.Net.SyncMapVote(maps)
    end
    
    -- Open vote menu for all players
    for _, ply in ipairs(player.GetAll()) do
        ply:ConCommand("tpg_menu_mapvote")
    end
    
    TPG.Util.ChatBroadcast("[TPG] " .. TPG.Config.mapVoteTime .. " seconds to vote!", Color(0, 255, 255))
    
    -- Countdown messages
    timer.Simple(TPG.Config.mapVoteTime - 10, function()
        if TPG.State.voting.active then
            TPG.Util.ChatBroadcast("[TPG] 10 seconds to vote!", Color(0, 255, 255))
        end
    end)
    
    timer.Simple(TPG.Config.mapVoteTime - 5, function()
        if TPG.State.voting.active then
            TPG.Util.ChatBroadcast("[TPG] 5 seconds to vote!", Color(255, 0, 0))
        end
    end)
    
    -- End vote
    timer.Simple(TPG.Config.mapVoteTime + 1, function()
        TPG.Voting.TallyVotes()
    end)
end

function TPG.Voting.CastMapVote(ply, mapIndex)
    if not TPG.State.voting.active then return end
    if not TPG.State.voting.maps[mapIndex] then return end
    
    local pState = TPG.State.GetPlayer(ply)
    pState.votes.map = mapIndex
    
    TPG.Util.ChatBroadcast(
        "[TPG] " .. ply:Nick() .. " voted for " .. TPG.State.voting.maps[mapIndex],
        Color(0, 0, 255)
    )
end

function TPG.Voting.TallyVotes()
    TPG.State.voting.active = false
    
    local votes = {}
    for i = 1, #TPG.State.voting.maps do
        votes[i] = 0
    end
    
    for _, ply in ipairs(player.GetAll()) do
        local pState = TPG.State.GetPlayer(ply)
        local vote = pState.votes.map
        
        if vote and votes[vote] then
            votes[vote] = votes[vote] + 1
        end
    end
    
    -- Find winner
    local bestMap = 1
    local bestVotes = 0
    
    for i, voteCount in ipairs(votes) do
        if voteCount >= bestVotes then
            bestVotes = voteCount
            bestMap = i
        end
    end
    
    local winningMap = TPG.State.voting.maps[bestMap]
    
    TPG.Util.ChatBroadcast("[TPG] Changing to map: " .. winningMap, Color(0, 255, 0))
    
    timer.Simple(3, function()
        RunConsoleCommand("changelevel", winningMap)
    end)
end