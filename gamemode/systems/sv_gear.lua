--[[--
    Premium gear: charging for loadout picks and reporting what a player can take.

    Charges for the items listed in `config/sh_gear.lua` and tells the client
    what it's allowed to take. Nothing here decides what an item costs --
    that's the config -- this only enforces it and reports it.

    Two entirely different payment models apply depending on whether the
    per-player economy (@{tpg.economy}) is running, and @{TPG.Gear.Claim}
    switches between them by checking `TPG.Economy.Active` at claim time:

        - Economy active: pay points, no cooldown. A destroyed loadout pick
          is not refunded any more than a destroyed vehicle is.
        - Economy inactive (the shared team-budget mode): pay lives, then
          time. Taking the item opens a run of `price.lives` lives; each
          spawn with it spends one, and the death that spends the last one
          starts the `price.cooldown` timer.

    Both halves live in one per-player table, `pState.gearCooldowns`, keyed by
    @{TPG.Gear.Key}:

        charges   lives left in this run; 0 means the next death starts the timer
        expires   CurTime the timer runs out, or 0 while none is running
        cooldown  seconds to put on the timer, copied from the price when the
                  run opened so @{TPG_GearLifeEnd} does not have to work back
                  from the key to an item to look the price up again

    The timer starts on the DEATH that ends the last charged life, not on the
    spawn that spends the last charge -- otherwise the wait would run down
    underneath a player who is still holding the thing, and the last life of
    the run would be worth less than the five before it.

    Timers run on `CurTime` and are stashed across a reconnect in
    `core/sv_gamestate.lua`, so dropping out isn't a way to clear one. Neither
    half is reset between rounds: this is a rate limit on a strong item, and a
    round boundary landing mid-run shouldn't hand everyone a free Javelin.

    Separately, `pState.gearPaidThisLife` tracks what the CURRENT life has
    already paid for, so re-opening the loadout menu and respawning to change
    an unrelated slot does not charge again for an item already bought this
    life -- see @{TPG.Gear.Claim} for the incident that made this necessary.
    That table is cleared on a real death, but deliberately not on a re-kit.

    @module tpg.gearsystem
    @realm server
]]

TPG.Gear = TPG.Gear or {}

util.AddNetworkString("TPG_GearState")     -- server -> client (cooldowns)
util.AddNetworkString("TPG_GearRequest")   -- client -> server (menu opened)

-- The live entry for one item, or nil if this player has never taken it (or has
-- taken it and finished the whole run).
local function entryFor(ply, kind, id)
    if not IsValid(ply) then return nil end
    local cds = TPG.State.GetPlayer(ply).gearCooldowns
    return cds and cds[TPG.Gear.Key(kind, id)] or nil
end

--- Seconds left on an item's cooldown timer, or 0 if no timer is running.
-- 0 does NOT mean the item is free to take right now in every sense -- it is
-- also what a player mid-run sees, with lives still to spend. Only meaningful
-- under the team-budget payment model; the economy model never opens a run in
-- the first place.
-- @tparam Player ply
-- @tparam string kind
-- @tparam string id
-- @treturn number
-- @realm server
function TPG.Gear.Remaining(ply, kind, id)
    local st = entryFor(ply, kind, id)
    if not st then return 0 end
    return math.max((st.expires or 0) - CurTime(), 0)
end

--- Lives left in this item's current run, before its cooldown timer starts.
-- An item never taken reports its full allowance rather than 0, so the menu can
-- show "6 lives" on something untouched without special-casing it.
-- @tparam Player ply
-- @tparam string kind
-- @tparam string id
-- @treturn number
-- @realm server
function TPG.Gear.ChargesLeft(ply, kind, id)
    local st = entryFor(ply, kind, id)
    if st then return math.max(st.charges or 0, 0) end

    local price = TPG.Gear.Price(kind, id)
    return price and price.lives or 0
end

--[[--
    Take an item, paying whatever this round's price is.

    Free items (no `TPG.Gear.Price` entry) always succeed and cost nothing, so
    callers can run every pick through here without checking first.

    Already bought this life? Then it's yours, and re-spawning to change a
    different slot doesn't buy it again. This is what makes the loadout
    menu's respawn button safe to press: it used to charge once per SPAWN,
    which meant tweaking your sidearm and respawning billed you a second time
    for the Javelin you'd bought and never fired -- and in a team-budget round
    it denied the Javelin outright, because the cooldown it had started ten
    seconds earlier was still running. `pState.gearPaidThisLife` is what
    fixes that; it's cleared on a real death (see the `PlayerDeath` hook
    below), so it only ever covers the life actually paid for.

    @tparam Player ply
    @tparam string kind
    @tparam string id
    @treturn boolean True on success.
    @treturn ?string Failure reason, `"cooldown"` or `"afford"` (also
     `"invalid"` for an invalid player), absent on success.
    @treturn ?number The number that goes with the reason: seconds left, or
     the cost, so the caller can say something useful instead of "denied".
    @realm server
]]
function TPG.Gear.Claim(ply, kind, id)
    if not IsValid(ply) then return false, "invalid", 0 end

    local price = TPG.Gear.Price(kind, id)
    if not price then return true end

    local pState = TPG.State.GetPlayer(ply)
    local key    = TPG.Gear.Key(kind, id)

    --[[
        Already bought this life? Then it's yours, and re-spawning to change a
        different slot doesn't buy it again.

        This is what makes the menu's respawn button safe to press: it charged
        once per SPAWN before, so tweaking your sidearm and respawning billed
        you a second time for the Javelin you'd bought and never fired -- and in
        a team-budget round it denied the Javelin outright, because the cooldown
        it had started ten seconds earlier was still running.

        The list is cleared on a real death (below), so this only ever covers
        the life you actually paid for.
    ]]
    if pState.gearPaidThisLife and pState.gearPaidThisLife[key] then
        return true
    end

    local function record()
        pState.gearPaidThisLife = pState.gearPaidThisLife or {}
        pState.gearPaidThisLife[key] = true
    end

    -- Per-player economy: pay points, no cooldown.
    if TPG.Economy and TPG.Economy.Active then
        local cost = price.cost or 0
        if cost <= 0 then return true end
        if not TPG.Economy.Charge(ply, cost, "gear") then
            return false, "afford", cost
        end
        record()
        return true
    end

    -- Team budget: spend a life, and only once they run out, time.
    local cooldown = price.cooldown or 0
    if cooldown <= 0 then return true end

    pState.gearCooldowns = pState.gearCooldowns or {}
    local st = pState.gearCooldowns[key]

    -- A timer still running is the only refusal. Nothing else here can say no:
    -- an open run always has at least one life left in it, because the spawn
    -- that took the last one closed the run out (below).
    if st and (st.expires or 0) > CurTime() then
        return false, "cooldown", st.expires - CurTime()
    end

    --[[
        A finished run is cleared rather than topped up, so waiting a timer out
        gives back the full allowance. Anything else would mean the second run
        of a session is shorter than the first, for no reason a player could
        see.
    ]]
    if st and (st.expires or 0) > 0 then st = nil end

    if not st then
        st = { charges = price.lives, expires = 0, cooldown = cooldown }
        pState.gearCooldowns[key] = st
    end

    -- This life is one of the run's. The timer does NOT start here even when
    -- that was the last charge; TPG_GearLifeEnd starts it on the death that
    -- ends this life, so the last life is worth as much as the first.
    st.charges = math.max((st.charges or 0) - 1, 0)
    st.cooldown = cooldown   -- re-read, in case an admin retuned it mid-run

    record()
    return true
end

--[[--
    A life ends: what that life paid for stops carrying over, and any run that
    has spent its last charge starts its cooldown timer.

    This is the only place a timer ever starts. Doing it here rather than in
    @{TPG.Gear.Claim} is what makes the last life of a run a whole life: the
    wait begins when the player stops holding the thing, not when they picked
    it up for the last time.

    A re-kit (`core/sv_commands.lua`) is deliberately not a life ending --
    that's the whole point of it -- so it keeps the paid list, leaves every run
    alone, and only clears the flag. That also means a re-kit cannot be used to
    burn through charges: `gearPaidThisLife` already stops the re-spawn from
    spending a second one.

    A suicide, on the other hand, IS a life ending and is left to count. Under
    the old bare timer that would have been a way to wait out a cooldown while
    doing something else; here it spends one of your own charges to reach the
    wait sooner, which is a cost rather than an exploit, so it needs no guard.

    @realm server
    @function TPG_GearLifeEnd
]]
hook.Add("PlayerDeath", "TPG_GearLifeEnd", function(victim)
    if not IsValid(victim) then return end

    local pState = TPG.State.GetPlayer(victim)
    if pState.rekit then return end
    pState.gearPaidThisLife = nil

    for _, st in pairs(pState.gearCooldowns or {}) do
        if (st.charges or 0) <= 0 and (st.expires or 0) <= 0 then
            st.expires = CurTime() + (st.cooldown or 0)
        end
    end
end)

--[[--
    Push a player's gear state to their own client, over `TPG_GearState`.

    Sends the player's live runs and timers, the picks the server actually has on
    record (so the menu shows what they're really set to rather than what
    they last clicked in this session), and what they're carrying RIGHT
    NOW -- which is how the menu can tell "equipped" apart from "you still
    have to respawn for this". Runs whose timer has finished are dropped on the
    way out -- they mean exactly what no entry at all means -- which is also the
    only cleanup that table ever needs.

    Called on `TPG_GearRequest` (menu opened) and wherever else the server
    needs to push a fresh state.

    @tparam Player ply
    @realm server
]]
function TPG.Gear.Sync(ply)
    if not IsValid(ply) then return end

    local pState = TPG.State.GetPlayer(ply)
    local cds    = pState.gearCooldowns or {}
    local live   = {}

    for key, st in pairs(cds) do
        local expires = st.expires or 0
        -- Finished: the timer ran out, so the run is over and the item is back
        -- to untouched. Mid-run entries (expires == 0) are kept however long
        -- they sit there -- the charges are the state.
        if expires > 0 and expires <= CurTime() then
            cds[key] = nil
        else
            live[key] = st
        end
    end

    local dl = TPG.WeaponConfig.DefaultLoadout

    local function pick(key, default)
        local v = TPG.Util.GetPData(ply, key, default)
        return isstring(v) and v or default
    end

    -- Nothing carried yet (never spawned this map, or waiting on a respawn) is
    -- sent as empty ids, which the menu reads as "none of this is live yet".
    local carried = pState.liveLoadout or {}

    net.Start("TPG_GearState")
        net.WriteUInt(table.Count(live), 8)
        for key, st in pairs(live) do
            net.WriteString(key)
            net.WriteUInt(math.Clamp(st.charges or 0, 0, 255), 8)
            -- Relative, not absolute: client clocks differ. 0 means no timer is
            -- running, which for a mid-run item is the normal state.
            net.WriteFloat(math.max((st.expires or 0) - CurTime(), 0))
        end

        net.WriteString(pick("Primary",   dl.Primary))
        net.WriteString(pick("Secondary", dl.Secondary))
        net.WriteString(pick("Special",   dl.Special))
        net.WriteUInt(math.Clamp(tonumber(TPG.Util.GetPData(ply, "Armor", 1)) or 1, 0, 255), 8)

        net.WriteString(carried.Primary   or "")
        net.WriteString(carried.Secondary or "")
        net.WriteString(carried.Special   or "")
        net.WriteInt(carried.Armor and math.Clamp(carried.Armor, -1, 255) or -1, 9)
    net.Send(ply)
end

net.Receive("TPG_GearRequest", function(_, ply)
    TPG.Gear.Sync(ply)
end)
