--[[--
    Underdog comeback bonuses.

    A team losing hard gets survivability and logistics help, deliberately
    NOT raw combat power: no HP or speed buffs, since speed would fight ACE's
    own weapon-speed system and HP changes time-to-kill mid-round in a way
    that is hard to reason about.

    A team is underdog while its tickets are `<= underdogRatio * enemy
    tickets` AND the absolute gap is `>= underdogMinGap` -- both conditions,
    so a close 1-tickets-apart game where the ratio still trips does not
    trigger it. Re-evaluated every 2 seconds by a timer, not event-driven, so
    the state can lag a ticket change by up to that long. Bonuses
    (`config/sh_config.lua`):

        - spawn protection: underdogProtectionTime instead of spawnProtectionTime
        - a free smoke grenade on spawn
        - Special-slot ammo floor +underdogAmmoBonus
        - all economy income x underdogIncomeMult

    The income bonus does NOT stack with the economy's own "losing team"
    multiplier (@{tpg.economy}) -- sv_economy takes the max of the two, and
    the announcement here is written to match: it reports whichever
    multiplier will actually apply and says nothing about income at all when
    the economy is off, rather than promising a bonus with no effect.

    Consumers: sv_spawning / sv_protection (protection time), sv_loadout
    (smoke + ammo floor), sv_economy (income).

    @module tpg.underdog
    @realm server
]]

TPG.Underdog = TPG.Underdog or {}

local state = { [TEAM_GREEN] = false, [TEAM_RED] = false }

--- Is this team currently underdog.
-- Reads the state last computed by the 2-second evaluation timer, so it can
-- be briefly stale after a ticket change.
-- @tparam number teamId TEAM_GREEN or TEAM_RED.
-- @treturn boolean
-- @realm server
function TPG.Underdog.IsUnderdog(teamId)
    return state[teamId] == true
end

--- Is this player's team currently underdog.
-- False for anyone not on a playing team (spectators, unassigned).
-- @tparam Player ply
-- @treturn boolean
-- @realm server
function TPG.Underdog.IsPlayerUnderdog(ply)
    return IsValid(ply) and TPG.Util.IsOnTeam(ply) and state[ply:Team()] == true
end

--- Spawn protection duration for a player, base or underdog-boosted.
-- @tparam Player ply
-- @treturn number Seconds.
-- @realm server
function TPG.Underdog.GetProtectionTime(ply)
    if TPG.Underdog.IsPlayerUnderdog(ply) then
        return TPG.Config.underdogProtectionTime or 8
    end
    return TPG.Config.spawnProtectionTime or 5
end

--- Extra rounds on top of the Special-slot ammo floor.
-- 0 for a non-underdog player.
-- @tparam Player ply
-- @treturn number
-- @realm server
function TPG.Underdog.GetAmmoBonus(ply)
    return TPG.Underdog.IsPlayerUnderdog(ply) and (TPG.Config.underdogAmmoBonus or 2) or 0
end

--- Economy income multiplier for a player: underdogIncomeMult, or 1 if not underdog.
-- Does not itself compare against the economy's losing-team multiplier; see
-- @{tpg.economy} for how the two combine.
-- @tparam Player ply
-- @treturn number
-- @realm server
function TPG.Underdog.GetIncomeMult(ply)
    return TPG.Underdog.IsPlayerUnderdog(ply) and (TPG.Config.underdogIncomeMult or 1.25) or 1
end

-- Recompute both teams' underdog state from the current ticket scores, and
-- announce any change. Round-inactive always clears both teams' state.
local function Evaluate()
    if not TPG.State.round.active then
        state[TEAM_GREEN], state[TEAM_RED] = false, false
        return
    end

    local ratio  = TPG.Config.underdogRatio or 0.6
    local minGap = TPG.Config.underdogMinGap or 60

    for _, teamId in ipairs({ TEAM_GREEN, TEAM_RED }) do
        local enemy = TPG.GetEnemyTeam(teamId)
        local own   = TPG.State.scores[teamId] or 0
        local their = TPG.State.scores[enemy] or 0

        local shouldBe = (their - own) >= minGap and own <= their * ratio

        if shouldBe ~= state[teamId] then
            state[teamId] = shouldBe
            local td = TPG.GetTeamData(teamId)
            if shouldBe then
                -- Income only actually changes under the per-player economy, and
                -- even then this bonus's multiplier doesn't stack with the
                -- separate "losing team" multiplier (sv_economy takes the max of
                -- the two) -- so report whichever one will actually apply,
                -- and say nothing about income at all when the economy is off.
                local incomeLine = ""
                if TPG.Economy and TPG.Economy.Active then
                    local mult = TPG.Config.underdogIncomeMult or 1.25
                    if TPG.Economy.Config and TPG.Economy.Config.losingIncomeMult then
                        mult = math.max(mult, TPG.Economy.Config.losingIncomeMult)
                    end
                    incomeLine = ", +" .. math.floor((mult - 1) * 100) .. "% income"
                end
                TPG.Util.ChatTeam(teamId, "[TPG] UNDERDOG BONUS active: " ..
                    (TPG.Config.underdogProtectionTime or 8) .. "s spawn protection, " ..
                    "free smoke grenade, extra launcher ammo" .. incomeLine ..
                    ". Turn it around!", Color(255, 200, 60))
                TPG.Util.ChatBroadcast("[TPG] " .. td.name .. " is fighting from underdog position.",
                    Color(255, 200, 60))
            else
                TPG.Util.ChatTeam(teamId, "[TPG] Back in the fight - underdog bonus ended.",
                    Color(160, 220, 160))
            end
        end
    end
end

timer.Create("TPG_UnderdogCheck", 2, 0, Evaluate)
