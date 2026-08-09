--[[--
    AFK detection and kick.

    Activity is tracked as a DEADLINE, not a timestamp: `ply._tpgLastActivity`
    holds the CurTime at which the player becomes kickable, so every refresh
    writes `CurTime() + afkKickTime` and the check is just
    `deadline - CurTime()`. Reading the field name as "when they last acted"
    will mislead you.

    **What counts as being there.** Three things, checked independently: a key
    press (`KeyPress`), a key currently HELD, and a change in where the player
    is looking. The last two are sampled on the same `Think` sweep that does
    the kicking, so they cost a comparison rather than a hook.

    All three exist because this is a vehicle-combat gamemode and its players
    can be extremely busy while pressing nothing new. A driver holds W for a
    minute at a time: one `KeyPress`, then silence. A gunner tracking a target
    across a ridge moves nothing but the mouse, and used to be warned and
    kicked mid-engagement. Aim is the strongest signal of the three, and the
    cheapest -- one angle compared against the last sample.

    Sitting in a vehicle is deliberately NOT activity by itself. Parking in a
    seat and walking away is the exact case the kick exists for: the seat's
    occupant holds a team slot, which is the only thing being reclaimed here.
    A player who is actually driving or shooting from that seat trips the
    input or aim check anyway, so occupancy adds no protection a real player
    needs.

    Players not on a playing team are exempt and get their deadline pushed
    forward every tick: they hold no team slot, so there is nothing to reclaim
    by kicking them. `TPG.AFK` is declared for namespace consistency and is
    otherwise empty; everything here is hooks.

    @module tpg.afk
    @realm server
]]

TPG.AFK = {}

-- Degrees of combined pitch+yaw movement between samples that counts as "still
-- at the keyboard". Small enough that tracking a distant target registers,
-- large enough that controller drift or a nudged mouse does not keep a truly
-- absent player alive forever.
local AIM_EPSILON = 1.5

-- Keys whose being HELD means the player is present. Movement, firing, use.
-- KeyPress covers the moment they go down; this covers the minute after.
local HELD_KEYS = {
    IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT,
    IN_ATTACK, IN_ATTACK2, IN_USE, IN_JUMP, IN_DUCK, IN_SPEED, IN_RELOAD,
}

--- Push the kick deadline out and, if they had been warned, say they are back.
local function Refresh(ply)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime

    if ply._tpgWarned then
        ply._tpgWarned = false
        TPG.Util.ChatMessage(ply, "[TPG] You are no longer AFK.", Color(0, 255, 0))
    end
end

--- Is the player holding any key that means they are present?
local function HoldingKey(ply)
    for _, key in ipairs(HELD_KEYS) do
        if ply:KeyDown(key) then return true end
    end
    return false
end

--[[
    Has the player's aim moved since the last sample?

    The stored sample is only replaced when the movement clears the threshold,
    so a slow drag across a target accumulates instead of being re-baselined
    into nothing every tick -- which is what a naive "compare with last frame"
    would do to precisely the careful, slow tracking this is here to notice.
]]
local function AimMoved(ply)
    local ang  = ply:EyeAngles()
    local last = ply._tpgLastAim

    if not last then
        ply._tpgLastAim = ang
        return false
    end

    local moved = math.abs(math.AngleDifference(ang.y, last.y))
                + math.abs(math.AngleDifference(ang.p, last.p))

    if moved < AIM_EPSILON then return false end

    ply._tpgLastAim = ang
    return true
end

--- Arms a joining player's AFK deadline and clears any warn state.
-- @realm server
-- @function TPG_AFK_Init
hook.Add("PlayerInitialSpawn", "TPG_AFK_Init", function(ply)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
    ply._tpgWarned = false
    ply._tpgLastAim = nil
end)

--- Any key press pushes the deadline out by the full `afkKickTime` and, if the
-- player had already been warned, tells them they are back.
-- @realm server
-- @function TPG_AFK_Activity
hook.Add("KeyPress", "TPG_AFK_Activity", function(ply)
    Refresh(ply)
end)

--[[--
    Samples activity, then warns and kicks teamed players whose deadline has run out.

    On a timer, not on `Think`. It used to be a full `player.GetAll()` sweep
    every tick -- 66 sweeps a second to move a deadline measured in whole
    minutes, and adding the held-key and aim samples would have multiplied
    that by the number of keys checked. Twice a second answers the same
    question: the shortest thing anyone is warned about is 20 seconds away,
    and no player holds a key or turns a turret for less than half a second.

    Held keys and aim movement are sampled here rather than on hooks of their
    own, which is the other half of the cost saving -- the sweep is already
    walking every player, and neither signal has an event to hang off.

    The warning fires once, at `afkWarningTime` seconds remaining, and goes to
    the centre of the screen as well as to chat: a chat line during a firefight
    is a line in a scrolling column nobody is reading. The kick fires when the
    deadline passes. Because the warn branch is checked first and sets
    `_tpgWarned`, a player who does nothing at all gets exactly one warning and
    then the kick.

    @realm server
    @function TPG_AFK_Check
]]
timer.Create("TPG_AFK_Check", 0.5, 0, function()
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

        -- Sampled before the deadline is read, so a player who is busy right
        -- now is never warned for what they were doing half a second ago.
        if HoldingKey(ply) or AimMoved(ply) then
            Refresh(ply)
        end

        local afkTime = ply._tpgLastActivity or (CurTime() + TPG.Config.afkKickTime)
        local timeLeft = afkTime - CurTime()

        if timeLeft <= TPG.Config.afkWarningTime and not ply._tpgWarned then
            local msg = "[TPG] AFK Warning: Move within " .. math.ceil(timeLeft) .. " seconds or be kicked."
            TPG.Util.ChatMessage(ply, msg, Color(255, 0, 0))
            ply:PrintMessage(HUD_PRINTCENTER, "AFK - move within " .. math.ceil(timeLeft) .. "s or be kicked")
            ply._tpgWarned = true
        elseif timeLeft <= 0 then
            ply:Kick("AFK")
        end
    end
end)
