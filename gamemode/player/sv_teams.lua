--[[--
    Team assignment, join balance and scramble.

    Everything that decides which of GREEN/RED a player ends up on: the
    voluntary join path (with its switch cooldown and balance check), the
    death-triggered autobalance safety net, and the full-roster scramble that
    the vote system and admin command both call into.

    @module tpg.playerteams
    @realm server
]]

TPG.PlayerTeams = TPG.PlayerTeams or {}

--[[--
    Move a player onto a team, subject to the switch cooldown and balance check.

    A no-op (returns true without touching the cooldown) if they are already on
    `teamId`. Otherwise: voluntary switches onto an actual team (not spectator)
    are throttled by `TPG.Config.teamSwitchCooldown`, which admins bypass and
    which only applies once the player has switched at least once before
    (`ply.tpgLastTeamSwitch` unset on first join). Leaving to spectator is
    always allowed and never stamps the cooldown. Passing the cooldown still
    requires @{CanJoin} to allow the move; either rejection sends a chat message
    and returns false without moving the player. On success this also respawns
    the player and applies team colour via the normal spawn path.

    @tparam Player ply
    @tparam number teamId TEAM_GREEN, TEAM_RED or TEAM_UNASSIGNED.
    @treturn boolean True if the player ended up on `teamId`.
    @realm server
]]
function TPG.PlayerTeams.AssignPlayer(ply, teamId)
    local currentTeam = ply:Team()

    -- Already there: nothing to do (and don't burn the cooldown on a no-op).
    if currentTeam == teamId then return true end

    -- Cooldown on voluntary switches onto a team. Blocks green<->red flipping
    -- to chase the winning side / dodge autobalance / double-dip budgets, and
    -- can't be side-stepped via spectator (the stamp only clears on a scramble).
    -- Admins bypass; leaving to spectator is always allowed; first join is free.
    local cd = TPG.Config.teamSwitchCooldown or 0
    local isAdmin = IsValid(ply) and ply:IsAdmin()
    if cd > 0 and teamId ~= TEAM_UNASSIGNED and not isAdmin and ply.tpgLastTeamSwitch then
        local remain = cd - (CurTime() - ply.tpgLastTeamSwitch)
        if remain > 0 then
            TPG.Util.ChatMessage(ply, "[TPG] Wait " .. math.ceil(remain) ..
                "s before switching teams again.", Color(255, 0, 0))
            return false
        end
    end

    -- Check balance
    if not TPG.PlayerTeams.CanJoin(ply, teamId) then
        TPG.Util.ChatMessage(ply, "[TPG] Teams cannot be unbalanced.", Color(255, 0, 0))
        return false
    end

    -- Set team
    ply:SetTeam(teamId)

    -- Respawn
    ply:Spawn()

    -- Stamp the cooldown when landing on an actual team (not when spectating).
    if teamId ~= TEAM_UNASSIGNED then
        ply.tpgLastTeamSwitch = CurTime()
    end

    -- Notify
    local teamData = TPG.GetTeamData(teamId)
    TPG.Util.ChatMessage(ply, "You have joined " .. teamData.name, Color(0, 255, 255))

    print("[TPG] " .. ply:Nick() .. " joined " .. teamData.name)

    return true
end

--- Would `ply` joining `targetTeam` leave the teams unbalanced?
-- Spectator is always allowed. Otherwise counts both teams, subtracts `ply`
-- from their current team if they are already on one (so switching teams
-- doesn't double-count them), and rejects a join that would make the target
-- team strictly larger than the other.
-- @tparam Player ply
-- @tparam number targetTeam TEAM_GREEN, TEAM_RED or TEAM_UNASSIGNED.
-- @treturn boolean
-- @realm server
function TPG.PlayerTeams.CanJoin(ply, targetTeam)
    if targetTeam == TEAM_UNASSIGNED then return true end
    
    local currentTeam = ply:Team()
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)
    
    -- Adjust for player leaving their current team
    if currentTeam == TEAM_GREEN then
        greenCount = greenCount - 1
    elseif currentTeam == TEAM_RED then
        redCount = redCount - 1
    end
    
    -- Check if joining would unbalance
    if targetTeam == TEAM_GREEN and greenCount > redCount then
        return false
    elseif targetTeam == TEAM_RED and redCount > greenCount then
        return false
    end
    
    return true
end

--- Force `ply` onto the weaker team if their own team outnumbers the other by
-- more than one. Called (via a small delay) after every death, so the swap
-- always lands between lives rather than mid-fight.
-- @tparam Player ply
-- @treturn boolean True if the player was moved.
-- @realm server
function TPG.PlayerTeams.Autobalance(ply)
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)
    local currentTeam = ply:Team()
    
    -- Check if autobalance needed
    if currentTeam == TEAM_GREEN and greenCount > redCount + 1 then
        ply:SetTeam(TEAM_RED)
        ply:Spawn()
        TPG.Util.ChatMessage(ply, "[TPG] You have been autobalanced.", Color(255, 255, 0))
        return true
    elseif currentTeam == TEAM_RED and redCount > greenCount + 1 then
        ply:SetTeam(TEAM_GREEN)
        ply:Spawn()
        TPG.Util.ChatMessage(ply, "[TPG] You have been autobalanced.", Color(255, 255, 0))
        return true
    end
    
    return false
end

--[[--
    Rebuild both teams from scratch, balanced by rating AND objective play.

    Two things have to come out even, not one. Rating splits the players who
    win fights; it does NOT split the players who stand on points, draft
    purely on rating often enough and one side ends up with every capper on the
    server while the scoreboard says the teams are even. So the pool is split
    into cappers and everyone else (by lifetime captures+flags per round,
    `systems/sv_stats.lua`) and each bucket is drafted separately, which forces
    the objective players to alternate.

    Within a bucket the next-best player goes to whichever team is currently
    weaker by total rating, with team sizes never allowed to differ by more than
    one. That balances totals better than a fixed snake pattern.

    Ratings are jittered by `TPG.Config.scrambleJitter` first. Without it the
    same roster produces the same two teams every single scramble, which is
    exactly the "we keep playing the same match" complaint; the jitter is small
    enough that it only ever reorders players who were close anyway.

    Spectators are left alone, they chose to watch. Anyone actually moved has
    their duplicator cooldown cleared and, under the per-player economy, any
    active purchase refunded (the vehicle is removed as part of that refund) so
    the scramble costs them nothing.

    @realm server
]]
function TPG.PlayerTeams.ScrambleAll()
    local pool = {}
    for _, ply in ipairs(player.GetAll()) do
        if TPG.Util.IsOnTeam(ply) then
            pool[#pool + 1] = ply
        end
    end

    if #pool == 0 then return end

    local jitter = TPG.Config.scrambleJitter or 0.08
    local score, isCapper = {}, {}
    for _, ply in ipairs(pool) do
        local rating = (TPG.Stats and TPG.Stats.GetRating(ply)) or 1000
        score[ply] = rating * (1 + math.Rand(-jitter, jitter))
        isCapper[ply] = ((TPG.Stats and TPG.Stats.GetObjectiveRate(ply)) or 0)
                        >= (TPG.Config.scrambleCapperRate or 0.5)
    end

    local cappers, others = {}, {}
    for _, ply in ipairs(pool) do
        table.insert(isCapper[ply] and cappers or others, ply)
    end

    local size  = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }
    local total = { [TEAM_GREEN] = 0, [TEAM_RED] = 0 }
    local assigned = {}

    local function Draft(list)
        table.sort(list, function(a, b) return score[a] > score[b] end)
        for _, ply in ipairs(list) do
            local pick
            if size[TEAM_GREEN] > size[TEAM_RED] then
                pick = TEAM_RED
            elseif size[TEAM_RED] > size[TEAM_GREEN] then
                pick = TEAM_GREEN
            else
                pick = total[TEAM_GREEN] <= total[TEAM_RED] and TEAM_GREEN or TEAM_RED
            end

            size[pick]  = size[pick] + 1
            total[pick] = total[pick] + score[ply]
            assigned[ply] = pick
        end
    end

    Draft(cappers)
    Draft(others)

    for ply, teamId in pairs(assigned) do
        local moved = ply:Team() ~= teamId

        ply:SetTeam(teamId)
        ply:Spawn()
        -- A scramble overrides the switch cooldown but re-stamps it, so nobody
        -- can immediately flip back and undo the forced move.
        ply.tpgLastTeamSwitch = CurTime()

        -- Being moved isn't the player's doing, so it shouldn't cost them the
        -- round: they're now spawning on the far side of the map, away from
        -- whatever they just paid for and built. Clear the duplicator cooldown
        -- and (under the per-player economy) hand back what they spent on any
        -- vehicle still standing -- that vehicle is removed as part of the
        -- refund, so it's a relocation, not free money.
        if moved then
            TPG.State.GetPlayer(ply).dupeCooldown = 0

            if TPG.Economy and TPG.Economy.RefundActivePurchases then
                local refunded = TPG.Economy.RefundActivePurchases(ply)
                if refunded > 0 then
                    TPG.Util.ChatMessage(ply, "[TPG] Scrambled: your vehicle was recalled and " ..
                        refunded .. " pts refunded. Rebuild on your new team.", Color(120, 230, 120))
                else
                    TPG.Util.ChatMessage(ply, "[TPG] Scrambled: duplicator cooldown cleared.",
                        Color(120, 230, 120))
                end
            else
                TPG.Util.ChatMessage(ply, "[TPG] Scrambled: duplicator cooldown cleared.",
                    Color(120, 230, 120))
            end
        end
    end

    TPG.Util.ChatBroadcast("[TPG] Teams have been scrambled (balanced by rating and objective play)!",
        Color(255, 255, 0))
end

-- Check for autobalance on death
hook.Add("PlayerDeath", "TPG_DeathAutobalance", function(victim, inflictor, attacker)
    timer.Simple(0.1, function()
        if IsValid(victim) then
            TPG.PlayerTeams.Autobalance(victim)
        end
    end)
end)