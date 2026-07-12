--[[
    Underdog Comeback Bonuses (server)

    A team losing hard gets survivability and logistics help -- deliberately
    NOT raw combat power (no HP/speed buffs: speed would fight the ACE weapon
    speed system, HP changes time-to-kill mid-round).

    Underdog while: tickets <= underdogRatio * enemy tickets AND the absolute
    gap >= underdogMinGap. Bonuses (config/sh_config.lua):

        - spawn protection underdogProtectionTime (vs spawnProtectionTime)
        - a free smoke grenade on spawn
        - Special-slot ammo floor +underdogAmmoBonus
        - all economy income x underdogIncomeMult

    Consumers: sv_spawning / sv_protection (protection time), sv_loadout
    (smoke + ammo floor), sv_economy (income).
]]

TPG.Underdog = TPG.Underdog or {}

local state = { [TEAM_GREEN] = false, [TEAM_RED] = false }

function TPG.Underdog.IsUnderdog(teamId)
    return state[teamId] == true
end

function TPG.Underdog.IsPlayerUnderdog(ply)
    return IsValid(ply) and TPG.Util.IsOnTeam(ply) and state[ply:Team()] == true
end

-- Spawn protection duration for a player (base or boosted).
function TPG.Underdog.GetProtectionTime(ply)
    if TPG.Underdog.IsPlayerUnderdog(ply) then
        return TPG.Config.underdogProtectionTime or 8
    end
    return TPG.Config.spawnProtectionTime or 5
end

-- Extra rounds on top of the Special-slot ammo floor.
function TPG.Underdog.GetAmmoBonus(ply)
    return TPG.Underdog.IsPlayerUnderdog(ply) and (TPG.Config.underdogAmmoBonus or 2) or 0
end

-- Economy income multiplier.
function TPG.Underdog.GetIncomeMult(ply)
    return TPG.Underdog.IsPlayerUnderdog(ply) and (TPG.Config.underdogIncomeMult or 1.25) or 1
end

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
                TPG.Util.ChatTeam(teamId, "[TPG] UNDERDOG BONUS active: " ..
                    (TPG.Config.underdogProtectionTime or 8) .. "s spawn protection, " ..
                    "free smoke grenade, extra launcher ammo, +" ..
                    math.floor(((TPG.Config.underdogIncomeMult or 1.25) - 1) * 100) ..
                    "% income. Turn it around!", Color(255, 200, 60))
                TPG.Util.ChatBroadcast("[TPG] " .. td.name .. " is fighting from underdog position.",
                    Color(255, 200, 60))
            else
                TPG.Util.ChatTeam(teamId, "[TPG] Back in the fight -- underdog bonus ended.",
                    Color(160, 220, 160))
            end
        end
    end
end

timer.Create("TPG_UnderdogCheck", 2, 0, Evaluate)
