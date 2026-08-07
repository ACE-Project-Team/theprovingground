--[[--
    Dupe-paste and prop-spawn enforcement: restricted entities, team/economy limits, cooldowns.

    Where a pasted contraption or spawned entity gets checked against
    everything TPG cares about: the wait-for-players window, restricted
    entity classes (@{tpg.entrestrictions}), the team weight/prop/point
    budget OR the per-player economy wallet (@{tpg.economy}, whichever mode
    is active), and the duplicator cooldown.

    The point/economy check happens on a `timer.Simple(0.5)` after the paste,
    not synchronously in the paste hook -- ACE's point calculation runs on its
    own `timer.Simple(0)` and needs to have actually settled before
    `TPG.PropTracking.UpdateTeamTotals()` reads a real number. Pasting under
    the economy is a TRUE PURCHASE charged exactly once at this point; a
    contraption that fails any OTHER limit check (weight, props) is deleted
    before the economy charge happens, so a rejected build is never billed.

    Two independent, non-stacking pacing mechanisms exist depending on mode:
    under the shared team budget, spawning a heavy build starts a duplicator
    cooldown (`pState.dupeCooldown`, driven by whichever of weight or points
    is larger); under the economy, there is no cooldown at all, because
    spending the wallet down is itself the pacing.

    @module tpg.duplication
    @realm server
]]

TPG.Duplication = TPG.Duplication or {}

--[[--
    Validate and (if the economy is active) charge for a just-pasted dupe.

    Runs, in order: the wait-for-players guard (the whole build is deleted,
    no partial credit); `TPG.Restrictions.StripBlocked` to yank any smuggled
    restricted entity out of the dupe; a spectator bypass (no team, no
    budget, no charge -- their sandbox is for testing builds between
    matches); the team-budget duplicator cooldown, checked BEFORE the
    (slower) point settle so an on-cooldown paste is rejected immediately
    without waiting on ACE.

    After a 0.5s settle, re-derives team totals and checks, in order: the
    economy wallet (if active) or the team point budget (if
    `TPG.Config.useACEPoints` and the economy is not active), then the team
    weight limit, then the team prop limit. Any failure deletes the whole
    build and refreshes team totals; passing all of them charges the economy
    wallet if applicable, stamps the paid price onto the contraption via
    `TPG.Economy.MarkContraptionsBilled` (done in BOTH modes, so post-spawn
    edits have a baseline to re-bill against either way), and then -- only
    outside the economy -- computes and applies the duplicator cooldown,
    skipping it entirely for a build under
    `TPG.Config.lightVehicleWeight`/`lightVehicleProps`.

    @realm server
    @function TPG_DupeFinished
]]
hook.Add("AdvDupe_FinishPasting", "TPG_DupeFinished", function(data)
    if not istable(data) or table.IsEmpty(data) then return end
    
    local ents = data[1] and data[1].CreatedEntities
    local ply = data[1] and data[1].Player
    
    if not ents or not IsValid(ply) then return end
    
    -- Nobody builds before the first round begins (wait-for-players window):
    -- the whole point is that no one gets a budget head start.
    if TPG.State.waitingForPlayers then
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load - the round hasn't started yet.", Color(255, 200, 0))
        return
    end

    -- A saved dupe is the other way a restricted entity gets into the world
    -- (a health kit or a mine bolted to the hull). Pull them back out before
    -- anything else looks at this build. Applies to spectators too -- their
    -- sandbox is for testing vehicles, not for smuggling pickups in.
    if TPG.Restrictions and TPG.Restrictions.StripBlocked then
        local stripped = TPG.Restrictions.StripBlocked(ents, ply)
        if stripped > 0 then
            TPG.Util.ChatMessage(ply, "[TPG] Removed " .. stripped ..
                " restricted entit" .. (stripped == 1 and "y" or "ies") ..
                " from that dupe.", Color(255, 150, 100))
        end
    end

    local teamId = ply:Team()

    -- Spectators may build freely: no team budget, no cooldown, no economy
    -- charge. They're godmoded and their damage is nulled (sv_protection), so
    -- it's a pure sandbox for testing builds between matches.
    if not TPG.Util.IsOnTeam(ply) then
        return
    end

    local pState = TPG.State.GetPlayer(ply)

    -- Under the per-player economy the wallet IS the pacing mechanism (a
    -- destroyed vehicle isn't refunded), so no duplicator cooldown on top.
    local econActive = TPG.Economy and TPG.Economy.Active

    -- Check cooldown FIRST
    if not econActive and CurTime() < (pState.dupeCooldown or 0) then
        local remaining = math.ceil(pState.dupeCooldown - CurTime())
        TPG.Util.ChatMessage(ply, "[TPG] Duplicator on cooldown for " .. remaining .. "s. Removed.", Color(255, 0, 0))
        for _, ent in pairs(ents) do
            if IsValid(ent) then ent:Remove() end
        end
        return
    end
    
    -- Wait for ACE to calculate points, then check limits
    -- ACE hooks run on timer.Simple(0), so we wait a bit longer
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        
        -- Recount everything
        TPG.PropTracking.UpdateTeamTotals()
        
        local usage = TPG.PropTracking.GetPlayerUsage(ply)
        local teamLimits = TPG.State.limits[teamId] or {}
        local maxLimits = TPG.State.maxLimits or {}
        
        local overLimit = false
        local reason = ""
        
        -- Points / economy check.
        -- When the per-player economy is active it REPLACES the shared team
        -- point budget: the player buys this contraption from their own wallet.
        local econCharge = nil
        if TPG.Economy and TPG.Economy.Active then
            econCharge = TPG.Economy.GetContraptionCost(ents)
            if not TPG.Economy.CanAfford(ply, econCharge) then
                overLimit = true
                reason = "Not enough points: costs " .. math.ceil(econCharge) ..
                    ", you have " .. TPG.Economy.GetMoney(ply)
            end
        elseif TPG.Config.useACEPoints then
            if (teamLimits.points or 0) > (maxLimits.points or 100000) then
                overLimit = true
                reason = "Team point limit exceeded (" .. math.ceil(teamLimits.points) .. "/" .. maxLimits.points .. ")"
            end
        end
        
        -- Check weight limit
        if (teamLimits.weight or 0) > (maxLimits.weight or 100000) then
            overLimit = true
            reason = "Team weight limit exceeded (" .. math.ceil(teamLimits.weight/1000) .. "T/" .. math.ceil(maxLimits.weight/1000) .. "T)"
        end
        
        -- Check prop limit
        if (teamLimits.props or 0) > (maxLimits.props or 300) then
            overLimit = true
            reason = "Team prop limit exceeded (" .. teamLimits.props .. "/" .. maxLimits.props .. ")"
        end
        
        if overLimit then
            TPG.Util.ChatMessage(ply, "[TPG] " .. reason .. ". Contraption removed.", Color(255, 0, 0))
            
            for _, ent in pairs(ents) do
                if IsValid(ent) then ent:Remove() end
            end
            
            -- Update counts after removal
            timer.Simple(0.1, function()
                TPG.PropTracking.UpdateTeamTotals()
            end)
            return
        end

        -- Passed all checks. Under the economy, charge the wallet now
        -- (true purchase -- a destroyed vehicle is not refunded).
        if econCharge then
            TPG.Economy.Charge(ply, econCharge, "vehicle")
            TPG.Util.ChatMessage(ply, "[TPG] Purchased for " .. math.ceil(econCharge) ..
                " pts. Balance: " .. TPG.Economy.GetMoney(ply), Color(0, 255, 0))
        end

        -- Baseline the paid cost onto the contraption so later edits re-bill
        -- against it (both economy and shared-budget modes; see sv_economy.lua).
        if TPG.Economy and TPG.Economy.MarkContraptionsBilled then
            TPG.Economy.MarkContraptionsBilled(ents)
        end

        -- Calculate weight for cooldown
        local totalWeight = 0
        for _, ent in pairs(ents) do
            if IsValid(ent) then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    totalWeight = totalWeight + phys:GetMass()
                end
            end
        end
        
        -- No cooldown at all under the economy (the purchase was the cost).
        if econActive then return end

        -- Light vehicles bypass cooldown
        local lightWeight = TPG.Config.lightVehicleWeight or 5000
        local lightProps = TPG.Config.lightVehicleProps or 140
        local propCount = table.Count(ents)

        if totalWeight <= lightWeight and propCount <= lightProps then
            TPG.Util.ChatMessage(ply, "[TPG] Light vehicle spawned. No cooldown.", Color(0, 255, 255))
            return
        end
        
        -- Apply cooldown. Two drivers, whichever is longer:
        --   weight -> (tons * dupeCooldownPerTon), the old heavy-rig penalty
        --   points -> (kpoints * dupeCooldownPer1kPoints), so a pricey high-point
        --             build also costs more cooldown even if it isn't heavy.
        local points    = (TPG.Economy and TPG.Economy.GetContraptionCost
                            and TPG.Economy.GetContraptionCost(ents)) or 0
        local weightCd  = (totalWeight / 1000) * (TPG.Config.dupeCooldownPerTon or 2)
        local pointCd   = (points / 1000) * (TPG.Config.dupeCooldownPer1kPoints or 3)
        local cooldown  = math.max(weightCd, pointCd)
        pState.dupeCooldown = CurTime() + cooldown
        
        TPG.Util.ChatMessage(ply, "[TPG] Contraption spawned. Duplicator on cooldown for " .. math.ceil(cooldown) .. "s.", Color(0, 255, 0))
    end)
end)

--[[--
    Block an individual prop spawn (not a dupe paste) if the team is already at its prop cap.

    Checks ONLY the team prop count against `maxLimits.props`; it does not
    check weight, points, or the economy wallet, so a single spawned prop is
    never charged under the economy -- only props that arrive as part of an
    ACE contraption via a dupe paste (`AdvDupe_FinishPasting` above) get
    billed. This hook can return `false` to actually block the spawn, unlike
    the SENT check below.

    @tparam Player ply
    @tparam string model
    @treturn ?boolean false to block the spawn; nil/true to allow.
    @realm server
    @function TPG_PropLimitCheck
]]
hook.Add("PlayerSpawnProp", "TPG_PropLimitCheck", function(ply, model)
    if TPG.State.waitingForPlayers then
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load - the round hasn't started yet.", Color(255, 200, 0))
        return false
    end

    -- Spectators build outside the team limit system entirely.
    if not TPG.Util.IsOnTeam(ply) then
        return
    end

    local teamId = ply:Team()
    local teamLimits = TPG.State.limits[teamId] or {}
    local maxLimits = TPG.State.maxLimits or {}
    
    if (teamLimits.props or 0) >= (maxLimits.props or 300) then
        TPG.Util.ChatMessage(ply, "[TPG] Team prop limit reached.", Color(255, 0, 0))
        return false
    end
end)

--[[--
    Warn (but do NOT block) when spawning a SENT pushes the team over its point limit.

    Point limits are advisory here. The only thing this hook ever blocks is a
    spawn attempted before the round has started (`waitingForPlayers`); past
    that, it always allows the spawn and the actual point check happens 0.5s
    LATER, in a timer, purely to send a chat warning when
    `TPG.Config.useACEPoints` is on and the team is over its cap. Contrast
    @{TPG_PropLimitCheck} above, which refuses the spawn outright. A single
    spawned ACE entity is therefore always allowed through no matter how far
    over the team already is. Also unrelated to restricted-class blocking,
    which is a separate hook on the same event in `sv_entrestrictions.lua`.

    @tparam Player ply
    @tparam string class
    @treturn ?boolean false to block for the wait-for-players case; otherwise
     always allows.
    @realm server
    @function TPG_SENTLimitCheck
]]
hook.Add("PlayerSpawnSENT", "TPG_SENTLimitCheck", function(ply, class)
    if TPG.State.waitingForPlayers then
        TPG.Util.ChatMessage(ply, "[TPG] Waiting for players to load - the round hasn't started yet.", Color(255, 200, 0))
        return false
    end

    -- Spectators build outside the team limit system entirely.
    if not TPG.Util.IsOnTeam(ply) then
        return
    end

    -- Allow spawning but check limits after
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        TPG.PropTracking.UpdateTeamTotals()
        
        local teamId = ply:Team()
        local teamLimits = TPG.State.limits[teamId] or {}
        local maxLimits = TPG.State.maxLimits or {}
        
        if TPG.Config.useACEPoints and (teamLimits.points or 0) > (maxLimits.points or 100000) then
            TPG.Util.ChatMessage(ply, "[TPG] Warning: Team is over point limit!", Color(255, 255, 0))
        end
    end)
end)