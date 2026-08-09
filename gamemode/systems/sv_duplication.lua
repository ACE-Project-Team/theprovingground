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
    under the shared team budget, spawning an expensive build starts a
    duplicator cooldown (`pState.dupeCooldown`, driven by the build's ACE
    point cost); under the economy, there is no cooldown at all, because
    spending the wallet down is itself the pacing.

    @module tpg.duplication
    @realm server
]]

TPG.Duplication = TPG.Duplication or {}

-- ── Paste grace period ─────────────────────────────────────────────────────

--[[
    A paste that has not committed you to anything yet.

    For a short window after a paste, losing the build costs you nothing: the
    price comes back and the duplicator cooldown clears. HOW you lost it is
    deliberately not asked. You deleted it because it landed clipped into the
    ground; it got shot to pieces the moment it appeared; the round ended
    under it -- all the same answer.

    That indifference is the mechanic, not a gap in it. The case it exists for
    is spawn camping: a player pastes, someone parked on the spawn kills it
    before it can move, and without this they have paid full price for a
    vehicle they never got to drive AND are locked out of pasting another.
    A rule that voided grace on damage would protect exactly the wrong person.

    Grace is per CONTRAPTION: stamped at paste time on each unique contraption
    the paste produced, alongside the `TPG_BilledPoints` baseline the economy
    already keeps, which is what makes "give back what was paid for THIS
    build" answerable without a second ledger. The owner is stamped with it
    because by the time the refund fires there are no entities left to ask.
]]

--[[--
    The grace window for the current map, in seconds.

    Reads the map config first so a map can override it, then
    `TPG.Config.dupeGracePeriod`. 0 (from either) disables the mechanic.

    Note the override actually takes effect, which is not true of every key a
    map block can carry: `safezoneRadius` is authored in every map in
    `maps/_loader.lua` and read by nobody -- all three consumers go to
    `TPG.Config.safezoneRadius` -- so setting it per map silently does
    nothing. Copying that pattern here would have produced the same dead knob.

    @treturn number Seconds; 0 if disabled.
    @realm server
]]
function TPG.Duplication.GetGracePeriod()
    local cfg = TPG.Maps and TPG.Maps.Get and TPG.Maps.Get() or nil
    local mapValue = cfg and cfg.dupeGracePeriod
    if mapValue then return mapValue end
    return TPG.Config.dupeGracePeriod or 0
end

--- Run `fn(con)` once per unique contraption in a spawned entity list.
local function forEachContraption(entList, fn)
    local seen = {}
    for _, ent in pairs(entList or {}) do
        if IsValid(ent) and ent.CFW_GetContraption then
            local con = ent:CFW_GetContraption()
            if con and not seen[con] then
                seen[con] = true
                fn(con)
            end
        end
    end
end

--- Seconds of grace left on this contraption, 0 if it has none or is out of it.
local function graceRemaining(con)
    local pasted = con.TPG_PasteTime
    if not pasted then return 0 end

    local window = TPG.Duplication.GetGracePeriod()
    if window <= 0 then return 0 end

    return math.max(0, (pasted + window) - CurTime())
end

--[[--
    A graced build has gone: hand the price back and clear the cooldown.

    Fires off CFW's `cfw.contraption.removed`, which runs when the LAST entity
    leaves a contraption and it was not merged into another one. That single
    event covers every way a build can end -- the player deleting it, the enemy
    reducing it to nothing, a cleanup -- which is precisely why the refund is
    hung here rather than on a command or on `PlayerDeath`. It cannot tell
    those apart, and it does not need to.

    A build that is merely wrecked is not removed: a turretless hull is still a
    contraption, and keeps its purchase. Only a build that is entirely gone
    inside the window refunds.

    The refund is `con.TPG_BilledPoints`, the running total actually paid --
    initial purchase plus any post-spawn edits already billed -- so a player
    who pasted and then bolted on a second gun gets both back. Outside the
    economy there is nothing to refund, the team budget frees itself as the
    props vanish, and clearing the cooldown is the whole effect.

    @realm server
    @function TPG_DupeGraceRefund
]]
hook.Add("cfw.contraption.removed", "TPG_DupeGraceRefund", function(con)
    if graceRemaining(con) <= 0 then return end

    -- Stamped at paste time: by now there is not an entity left to ask.
    local ply = con.TPG_GraceOwner
    con.TPG_PasteTime, con.TPG_GraceOwner = nil, nil
    if not (IsValid(ply) and ply:IsPlayer()) then return end

    local econ   = TPG.Economy
    local refund = con.TPG_BilledPoints or 0
    con.TPG_BilledPoints = nil

    if econ and econ.Active and refund > 0 then
        econ.SetMoney(ply, econ.GetMoney(ply) + refund)
        if econ.Notify then econ.Notify(ply, refund, "dupe grace") end
    else
        refund = 0
    end

    local hadCooldown = CurTime() < (TPG.State.GetPlayer(ply).dupeCooldown or 0)
    TPG.State.GetPlayer(ply).dupeCooldown = 0

    local msg = "[TPG] Build lost inside the grace period."
    if refund > 0 then msg = msg .. " Refunded " .. math.ceil(refund) .. " pts." end
    if hadCooldown then msg = msg .. " Duplicator cooldown cleared." end
    TPG.Util.ChatMessage(ply, msg, Color(0, 255, 255))

    timer.Simple(0.1, function() TPG.PropTracking.UpdateTeamTotals() end)
end)

-- ── Concurrent pastes ──────────────────────────────────────────────────────

--[[
    Pastes that have landed in the world but have not been judged yet.

    Six players pasting in the same tick used to lose all six builds. Every
    check runs half a second after its own paste, all six landed inside that
    window, and each check read a team total that already contained all six --
    so a cap of 25 props saw 30 and deleted 30, including the builds that fit.
    The check was all-or-nothing per paste with no ordering, and the two pastes
    that would have been admitted on their own were destroyed by the third.

    A paste is registered here when it is accepted for checking and dropped
    when it resolves. A check subtracts the OTHER still-pending pastes from its
    team's totals, so it is judged against the world as it stood before its
    rivals landed, plus itself. Pastes are then admitted in the order they are
    checked and only the one that genuinely crosses the cap is rejected.

    A rejected paste is held in the ledger for a moment longer rather than
    dropped on the spot: `Entity:Remove` does not take effect until the end of
    the frame, so a same-tick rival recounting the team would otherwise still
    see the props of a build that is already condemned.

    What is subtracted is never the raw contents of a pending paste. Team
    totals are aggregated per player through the light-vehicle gate
    (`sv_proptracking`), and the tracker can be a moment behind the world, so
    taking a paste's own props back out of a total that does not contain them
    yet would wave every build through. Each pending paste is therefore
    measured against its owner's tracked usage: nothing at all if that owner is
    under the gate, and never more than the tracker actually counts them for.
]]
local pendingPastes = {}
local nextToken     = 0

--- Props, weight and ACE points one paste is currently putting into the world.
local function measurePaste(entList)
    local props, weight = 0, 0

    for _, ent in pairs(entList or {}) do
        if IsValid(ent) then
            props = props + 1
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then weight = weight + phys:GetMass() end
        end
    end

    local points = (TPG.Economy and TPG.Economy.GetContraptionCost
                        and TPG.Economy.GetContraptionCost(entList)) or 0

    return props, weight, points
end

--- How much of a team's total one pending paste is responsible for.
-- Zero when its owner is under the light-vehicle gate (the total never
-- included them), and capped by what the tracker counts that owner for (the
-- paste may not have reached it yet).
local function pendingContribution(paste)
    if not IsValid(paste.ply) then return 0, 0, 0 end

    local usage       = TPG.PropTracking.GetPlayerUsage(paste.ply)
    local lightWeight = TPG.Config.lightVehicleWeight or 5000
    local lightProps  = TPG.Config.lightVehicleProps or 140

    if not ((usage.weight or 0) > lightWeight or (usage.props or 0) > lightProps) then
        return 0, 0, 0
    end

    local props, weight, points = measurePaste(paste.ents)

    return math.min(props,  usage.props  or 0),
           math.min(weight, usage.weight or 0),
           math.min(points, usage.points or 0)
end

--- A team's totals with every OTHER pending paste taken back out of them.
local function teamTotalsExcludingPending(teamId, token)
    local totals = TPG.State.limits[teamId] or {}
    local props  = totals.props  or 0
    local weight = totals.weight or 0
    local points = totals.points or 0

    for other, paste in pairs(pendingPastes) do
        if other ~= token and paste.team == teamId then
            local p, w, pts = pendingContribution(paste)
            props, weight, points = props - p, weight - w, points - pts
        end
    end

    return {
        props  = math.max(0, props),
        weight = math.max(0, weight),
        points = math.max(0, points),
    }
end

--[[--
    Validate and (if the economy is active) charge for a just-pasted dupe.

    Runs, in order: the wait-for-players guard (the whole build is deleted,
    no partial credit); `TPG.Restrictions.StripBlocked` to yank any smuggled
    restricted entity out of the dupe; a spectator bypass (no team, no
    budget, no charge -- their sandbox is for testing builds between
    matches); the team-budget duplicator cooldown, checked BEFORE the
    (slower) point settle so an on-cooldown paste is rejected immediately
    without waiting on ACE.

    After a 0.5s settle, re-derives team totals -- minus every OTHER paste
    still waiting to be judged, see the pending ledger above, which is what
    stops a tickful of simultaneous pastes from deleting each other -- and
    checks ALL of: the
    economy wallet (if active) or the team point budget (if
    `TPG.Config.useACEPoints` and the economy is not active), the per-player
    point cap and the single-dupe tonnage cap (both `0`/off by default), the
    team weight limit and the team prop limit. Every violation is collected
    and reported together rather than only the last one checked, so a build
    that is over on two counts does not send the player back to trim one of
    them and hit the other. Any failure deletes the whole
    build and refreshes team totals; passing all of them charges the economy
    wallet if applicable, stamps the paid price onto the contraption via
    `TPG.Economy.MarkContraptionsBilled` (done in BOTH modes, so post-spawn
    edits have a baseline to re-bill against either way), and then -- only
    outside the economy -- computes and applies the duplicator cooldown from
    the build's point cost, skipping it entirely for a build under
    `TPG.Config.lightVehiclePoints`/`lightVehicleProps`.

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
    
    -- Claimed here, not inside the timer: the paste is in the world from this
    -- moment, so every rival check that runs before this one resolves has to
    -- be able to see it and take it back out of their own arithmetic.
    nextToken = nextToken + 1
    local token = nextToken
    pendingPastes[token] = { team = teamId, ents = ents, ply = ply }

    local function release()      pendingPastes[token] = nil end
    -- A condemned paste keeps its place in the ledger until its entities have
    -- actually gone (end of frame), so a same-tick rival does not count them.
    local function releaseLater() timer.Simple(1, release) end

    -- Wait for ACE to calculate points, then check limits
    -- ACE hooks run on timer.Simple(0), so we wait a bit longer
    timer.Simple(0.5, function()
        if not IsValid(ply) then release() return end

        -- Recount everything
        TPG.PropTracking.UpdateTeamTotals()

        local usage = TPG.PropTracking.GetPlayerUsage(ply)
        local teamLimits = teamTotalsExcludingPending(teamId, token)
        local maxLimits = TPG.State.maxLimits or {}
        
        -- Every limit this build breaks, not just the last one checked. A
        -- build that is both too heavy and too many props used to report only
        -- "prop limit", so trimming props and re-pasting hit the weight wall
        -- the player was never told about.
        local reasons = {}

        -- Mass of THIS paste. Needed twice: the per-dupe tonnage cap below and
        -- the cooldown further down.
        local pasteWeight = 0
        for _, ent in pairs(ents) do
            if IsValid(ent) then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    pasteWeight = pasteWeight + phys:GetMass()
                end
            end
        end

        -- Points / economy check.
        -- When the per-player economy is active it REPLACES the shared team
        -- point budget: the player buys this contraption from their own wallet.
        local econCharge = nil
        if TPG.Economy and TPG.Economy.Active then
            econCharge = TPG.Economy.GetContraptionCost(ents)
            if not TPG.Economy.CanAfford(ply, econCharge) then
                reasons[#reasons + 1] = "not enough points (costs " .. math.ceil(econCharge) ..
                    ", you have " .. TPG.Economy.GetMoney(ply) .. ")"
            end
        elseif TPG.Config.useACEPoints then
            if (teamLimits.points or 0) > (maxLimits.points or 100000) then
                reasons[#reasons + 1] = "team point limit (" ..
                    math.ceil(teamLimits.points) .. "/" .. maxLimits.points .. ")"
            end
        end

        -- Per-player share of the point budget. Off by default: the team
        -- budget is per-map and this is a flat number, so any value picked
        -- here is wrong on most maps. An operator who wants one sets it
        -- against their own budget. See sh_config.lua.
        local playerPoints = TPG.Config.playerPointLimit or 0
        if playerPoints > 0 and (usage.points or 0) > playerPoints then
            reasons[#reasons + 1] = "your personal point limit (" ..
                math.ceil(usage.points) .. "/" .. playerPoints .. ")"
        end

        -- Check weight limit
        if (teamLimits.weight or 0) > (maxLimits.weight or 100000) then
            reasons[#reasons + 1] = "team weight limit (" ..
                math.ceil(teamLimits.weight/1000) .. "T/" .. math.ceil(maxLimits.weight/1000) .. "T)"
        end

        -- Tonnage cap on a SINGLE dupe, as opposed to the team total above:
        -- one player cannot land a battleship even on an empty team budget.
        -- Off by default, same reasoning as playerPointLimit.
        local dupeWeightCap = TPG.Config.maxDupeWeight or 0
        if dupeWeightCap > 0 and pasteWeight > dupeWeightCap then
            reasons[#reasons + 1] = "single dupe too heavy (" ..
                math.ceil(pasteWeight/1000) .. "T/" .. math.ceil(dupeWeightCap/1000) .. "T)"
        end

        -- Check prop limit
        if (teamLimits.props or 0) > (maxLimits.props or 300) then
            reasons[#reasons + 1] = "team prop limit (" ..
                teamLimits.props .. "/" .. maxLimits.props .. ")"
        end

        if #reasons > 0 then
            TPG.Util.ChatMessage(ply, "[TPG] Contraption removed - " ..
                table.concat(reasons, "; ") .. ".", Color(255, 0, 0))

            for _, ent in pairs(ents) do
                if IsValid(ent) then ent:Remove() end
            end
            releaseLater()

            -- Update counts after removal
            timer.Simple(0.1, function()
                TPG.PropTracking.UpdateTeamTotals()
            end)
            return
        end

        -- Passed all checks. Under the economy, charge the wallet now
        -- (true purchase -- a destroyed vehicle is not refunded).
        --
        -- Charge re-checks affordability and can refuse: half a second has
        -- passed since CanAfford said yes, and the player may have bought
        -- something else in it. Taking the return seriously is what stops a
        -- refused charge from handing out a free contraption while printing
        -- "Purchased".
        if econCharge then
            if not TPG.Economy.Charge(ply, econCharge, "vehicle") then
                TPG.Util.ChatMessage(ply, "[TPG] Contraption removed - could not pay " ..
                    math.ceil(econCharge) .. " pts (balance " ..
                    TPG.Economy.GetMoney(ply) .. ").", Color(255, 0, 0))

                for _, ent in pairs(ents) do
                    if IsValid(ent) then ent:Remove() end
                end
                releaseLater()
                timer.Simple(0.1, function()
                    TPG.PropTracking.UpdateTeamTotals()
                end)
                return
            end

            TPG.Util.ChatMessage(ply, "[TPG] Purchased for " .. math.ceil(econCharge) ..
                " pts. Balance: " .. TPG.Economy.GetMoney(ply), Color(0, 255, 0))
        end

        -- Admitted. It counts against the team from here on, so it stops being
        -- something the next check has to subtract.
        release()

        -- Baseline the paid cost onto the contraption so later edits re-bill
        -- against it (both economy and shared-budget modes; see sv_economy.lua).
        if TPG.Economy and TPG.Economy.MarkContraptionsBilled then
            TPG.Economy.MarkContraptionsBilled(ents)
        end

        -- Start the grace clock. The window runs from the paste finishing, not
        -- from leaving spawn -- this is the point where the build exists and
        -- its price is known, so it is the honest zero. Stamped after the
        -- baseline above so a refundable contraption always carries the
        -- TPG_BilledPoints figure the refund hands back, and even outside the
        -- economy, where the refund is zero and the cooldown clear is the point.
        local window = TPG.Duplication.GetGracePeriod()
        if window > 0 then
            forEachContraption(ents, function(con)
                con.TPG_PasteTime  = CurTime()
                con.TPG_GraceOwner = ply
            end)
            TPG.Util.ChatMessage(ply, "[TPG] Grace period: " .. math.floor(window) ..
                "s. Lose this build now, deleted or destroyed, and you get the " ..
                "points back with no cooldown.", Color(150, 200, 255))
        end

        -- No cooldown at all under the economy (the purchase was the cost).
        if econActive then return end

        -- What the build is WORTH is the whole basis of the cooldown, so it is
        -- also the basis of the exemption from it. Weight used to drive both
        -- and no longer drives either: a light build can be expensive and a
        -- heavy one cheap, and it was the tonnage that made hauling armour
        -- around cost more than the guns bolted to it.
        local points = (TPG.Economy and TPG.Economy.GetContraptionCost
                            and TPG.Economy.GetContraptionCost(ents)) or 0

        local lightPoints = TPG.Config.lightVehiclePoints or 2000
        local lightProps  = TPG.Config.lightVehicleProps or 140
        local propCount   = table.Count(ents)

        if points <= lightPoints and propCount <= lightProps then
            TPG.Util.ChatMessage(ply, "[TPG] Light vehicle spawned. No cooldown.", Color(0, 255, 255))
            return
        end

        -- One driver: (kpoints * dupeCooldownPer1kPoints). A pricier build
        -- costs more cooldown, and nothing else does.
        local cooldown = (points / 1000) * (TPG.Config.dupeCooldownPer1kPoints or 30)
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
        -- Throttled: the spawn menu fires this once per prop, so a player
        -- holding the button down at the cap gets one line instead of thirty.
        TPG.Util.ChatMessageThrottled(ply, "proplimit",
            "[TPG] Team prop limit reached (" .. teamLimits.props .. "/" ..
            (maxLimits.props or 300) .. ").", Color(255, 0, 0))
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