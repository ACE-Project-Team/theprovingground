--[[--
    AFK detection and kick.

    Activity is tracked as a DEADLINE, not a timestamp: `ply._tpgLastActivity`
    holds the CurTime at which the player becomes kickable, so every refresh
    writes `CurTime() + afkKickTime` and the check is just
    `deadline - CurTime()`. Reading the field name as "when they last acted"
    will mislead you.

    Only `KeyPress` counts as activity. Mouse movement, aiming and firing a
    vehicle's weapons do not, so a player sitting in a gunner seat tracking
    targets with the mouse alone can still be warned and kicked.

    Players not on a playing team are exempt and get their deadline pushed
    forward every tick: they hold no team slot, so there is nothing to reclaim
    by kicking them. `TPG.AFK` is declared for namespace consistency and is
    otherwise empty; everything here is hooks.

    @module tpg.afk
    @realm server
]]

TPG.AFK = {}

--- Arms a joining player's AFK deadline and clears any warn state.
-- @realm server
-- @function TPG_AFK_Init
hook.Add("PlayerInitialSpawn", "TPG_AFK_Init", function(ply)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
    ply._tpgWarned = false
end)

--- Any key press pushes the deadline out by the full `afkKickTime` and, if the
-- player had already been warned, tells them they are back.
-- @realm server
-- @function TPG_AFK_Activity
hook.Add("KeyPress", "TPG_AFK_Activity", function(ply, key)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
    
    if ply._tpgWarned then
        ply._tpgWarned = false
        TPG.Util.ChatMessage(ply, "[TPG] You are no longer AFK.", Color(0, 255, 0))
    end
end)

--[[--
    Every tick, warns then kicks teamed players whose deadline has run out.

    Runs on `Think`, so this is a full `player.GetAll()` sweep per tick with no
    throttle. Skips anyone not connected or not fully authenticated. The warning
    fires once, at `afkWarningTime` seconds remaining; the kick fires when the
    deadline passes. Because the warn branch is checked first and sets
    `_tpgWarned`, a player who never presses a key gets exactly one warning and
    then the kick.

    @realm server
    @function TPG_AFK_Check
]]
hook.Add("Think", "TPG_AFK_Check", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:IsConnected() or not ply:IsFullyAuthenticated() then continue end

        -- Spectators (anyone not on a playing team) hold no team slot, so don't
        -- AFK-kick them -- they're allowed to just watch. Clear any pending warn
        -- state so they don't get kicked the instant they pick a side.
        if not TPG.Util.IsOnTeam(ply) then
            ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
            ply._tpgWarned = false
            continue
        end

        local afkTime = ply._tpgLastActivity or (CurTime() + TPG.Config.afkKickTime)
        local timeLeft = afkTime - CurTime()
        
        if timeLeft <= TPG.Config.afkWarningTime and not ply._tpgWarned then
            TPG.Util.ChatMessage(ply, "[TPG] AFK Warning: Move within " .. math.ceil(timeLeft) .. " seconds or be kicked.", Color(255, 0, 0))
            ply._tpgWarned = true
        elseif timeLeft <= 0 then
            ply:Kick("AFK")
        end
    end
end)