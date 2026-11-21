--[[--
    ACE wearable armor (helmet, vest, heavy helmet) issued with the loadout.

    Optional integration: everything here no-ops when the mounted ACE lacks
    `ACE.Wearables` (it lives on a separate ACE branch), so the gamemode runs
    unchanged on stable ACE.

    Issue rules at spawn, applied by @{TPG.Loadout.Apply}:

      - Juggernaut (armor 4) always wears the heavy helmet -- that is its
        armour fantasy, and it never gets the plain one.
      - The no-armour tier (armor 0) gets the standard helmet free, since it
        has nothing else over its head.
      - Underdog team's players all get the vest free while their team is
        losing.
      - A bought suit (@{TPG.Wearables.BuySuit} / `tpg_suit`) adds helmet +
        vest for its run of rounds regardless of tier. Deaths inside the run
        don't spend it; stripping on death is ACE's own job.

    The heavy helmet uses the same model as the base one; the skin + tint is
    what tells them apart at a glance.

    @module tpg.wearables
    @realm server
]]

TPG.Wearables = TPG.Wearables or {}

-- White skin is the tintable one (olive, skin 0, would swallow the colour).
local HEAVY_SKIN = 1
local HEAVY_TINT = Color(90, 95, 115) -- dark steel blue, vs the base helmet's olive

--- Whether the mounted ACE provides the wearables API.
-- @treturn boolean
-- @realm server
function TPG.Wearables.Available()
    return ACE ~= nil and ACE.Wearables ~= nil and ACE.Wearables.SetWearing ~= nil
end

--- Rounds left on the player's suit purchase; 0 when there is no active suit.
-- @tparam Player ply
-- @treturn number
-- @realm server
function TPG.Wearables.SuitRoundsLeft(ply)
    local pState = TPG.State.GetPlayer(ply)
    return (pState and pState.suitRounds) or 0
end

--- Put this life's wearables on a spawned player.
-- Called from @{TPG.Loadout.Apply} once the resolved armor tier is known.
-- @tparam Player ply
-- @tparam number armorId The tier that survived gear claims.
-- @realm server
function TPG.Wearables.ApplyFor(ply, armorId)
    if not TPG.Wearables.Available() then return end
    if not TPG.Util.IsOnTeam(ply) then return end

    local suit = TPG.Wearables.SuitRoundsLeft(ply) > 0
    local underdog = TPG.Underdog and TPG.Underdog.IsPlayerUnderdog
        and TPG.Underdog.IsPlayerUnderdog(ply)

    -- Every slot is decided explicitly, not only "set when wanted": the slots
    -- a life does NOT grant are switched off, so a re-apply (re-kit edge, or
    -- a just-expired suit) can never layer last life's wearables under this
    -- one's.
    local heavy = armorId == 4
    ACE.Wearables.SetWearing(ply, "helmet_heavy", heavy, HEAVY_SKIN, HEAVY_TINT)
    ACE.Wearables.SetWearing(ply, "helmet", not heavy and (armorId == 0 or suit))
    ACE.Wearables.SetWearing(ply, "vest", suit or underdog or false)
end

--- Buy the full suit (vest + helmet) for `TPG.Gear.Suit.rounds` rounds.
-- One charge, not a per-spawn fee; deaths inside the run are free.
-- @tparam Player ply
-- @treturn boolean bought
-- @treturn ?string Failure reason for chat.
-- @realm server
function TPG.Wearables.BuySuit(ply)
    if not TPG.Wearables.Available() then
        return false, "Wearables are not available on this server."
    end
    if not TPG.Util.IsOnTeam(ply) then
        return false, "Join a team first."
    end
    if not (TPG.Economy and TPG.Economy.Active) then
        return false, "The suit needs the per-player economy."
    end

    local suit = TPG.Gear.Suit
    local left = TPG.Wearables.SuitRoundsLeft(ply)
    if left > 0 then
        return false, "Your suit still has " .. left .. " round(s) left."
    end
    if not TPG.Economy.Charge(ply, suit.cost, "suit") then
        return false, "Not enough points - the suit costs " .. suit.cost .. "."
    end

    TPG.State.GetPlayer(ply).suitRounds = suit.rounds
    return true
end

--- Tick one round off every active suit. Called from @{TPG.Rounds.EndRound}.
-- @realm server
function TPG.Wearables.OnRoundEnd()
    for _, ply in ipairs(player.GetAll()) do
        local pState = TPG.State.GetPlayer(ply)
        if pState and (pState.suitRounds or 0) > 0 then
            pState.suitRounds = pState.suitRounds - 1
        end
    end
end
