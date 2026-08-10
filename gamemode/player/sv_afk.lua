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

    **Benching, not kicking.** When the deadline passes the player is moved to
    spectators rather than dropped, and only kicked if the server is at least
    `TPG.Config.afkKickAtLoad` full. Everything the kick was for is achieved by
    the move: the team slot is released, the roster rebalances, nobody is
    waiting on a seat this player is not using. The kick only adds the costs --
    a lost round, a lost build, a player who has to reconnect and re-paste to
    come back -- and those buy nothing on a server with room in it. Above the
    load threshold the seat is genuinely contended and the kick returns.

    Benched players are the one kind of spectator this file keeps watching.
    Ordinary spectators are exempt outright (they hold no team slot), but a
    benched one is still idle, still holding a *server* slot, and has to be
    reachable if the server fills up later -- so they keep being sampled, and
    the first sign of life puts them back on their team.

    A benched player's build stays on the map, so `sv_proptracking.lua` keeps
    charging it to `_tpgAFKTeam`. Without that, going AFK would hand your team
    its budget back while your tank sat there.

    `TPG.AFK` is declared for namespace consistency and is otherwise empty;
    everything here is hooks.

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

-- Forward declaration: Refresh() ends a bench, and Unbench() is written below
-- it because it is the longer half of the pair.
local Unbench

--- Push the kick deadline out and, if they had been warned, say they are back.
local function Refresh(ply)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime

    if ply._tpgWarned then
        ply._tpgWarned = false
        TPG.Util.ChatMessage(ply, "[TPG] You are no longer AFK.", Color(0, 255, 0))
    end

    if ply._tpgAFKBenched then Unbench(ply) end
end

--- How full the server is, 0-1. The AFK kick is priced against this.
local function ServerLoad()
    local max = game.MaxPlayers()
    if max <= 0 then return 1 end
    return player.GetCount() / max
end

--- Is the server full enough that an idle player's slot is worth taking?
local function SlotIsContended()
    local at = TPG.Config.afkKickAtLoad or 0.75
    if at <= 0 then return true end
    if at >= 1 then return false end
    return ServerLoad() >= at
end

--[[
    Move an expired player to spectators instead of kicking them.

    `_tpgAFKTeam` is what makes the move reversible and keeps it from being an
    exploit: it is what @{Unbench} sends them back to, and what
    `sv_proptracking.lua` charges their abandoned build to in the meantime.

    The deadline is deliberately NOT pushed out here. A benched player stays
    expired, so the sweep can kick them the moment the server does fill up
    without waiting out another `afkKickTime`.
]]
local function Bench(ply)
    ply._tpgAFKTeam = ply:Team()
    ply._tpgAFKBenched = true
    ply._tpgWarned = false

    ply:SetTeam(TEAM_UNASSIGNED)
    ply:Spawn()

    -- The respawn snaps their view somewhere else, and the aim check cannot
    -- tell that from a player turning their head. Left alone, every bench
    -- un-benched itself on the very next sweep half a second later. Drop the
    -- baseline so the next sample re-takes it instead of measuring the jump.
    ply._tpgLastAim = nil

    TPG.Util.ChatMessage(ply, "[TPG] Moved to spectators for being AFK - move to rejoin.", Color(255, 200, 0))
    print("[TPG] " .. ply:Nick() .. " benched to spectators (AFK).")
end

--[[
    Put a benched player back where they were, if the roster still allows it.

    Declared as a forward local above @{Refresh} because the two call each
    other: any activity refreshes, and a refresh from a benched player is what
    ends the bench.

    Deliberately not @{TPG.PlayerTeams.AssignPlayer}: that applies the
    voluntary switch cooldown, which is the wrong guard here. The cooldown
    exists to stop players flipping sides to chase the winning team, and this
    player did not choose to leave -- TPG moved them. Routing the return
    through it means anyone who happened to switch teams in the half minute
    before going idle comes back to a refusal, for a move they never made. The
    balance check is kept, because that one is about the roster rather than
    about intent, and the switch stamp is deliberately not written.

    A rejoin can still be refused: someone took the slot while they were away.
    That is not a failure to retry -- they are awake now and can pick a side
    themselves. `_tpgAFKTeam` survives the refusal so their build keeps
    counting against that team until they actually land on one.
]]
function Unbench(ply)
    ply._tpgAFKBenched = nil

    local back = ply._tpgAFKTeam
    if back and TPG.PlayerTeams.CanJoin(ply, back) then
        ply:SetTeam(back)
        ply:Spawn()
        ply._tpgAFKTeam = nil
        ply._tpgLastAim = nil
        TPG.Util.ChatMessage(ply, "[TPG] Welcome back - returned to your team.", Color(0, 255, 0))
        return
    end

    TPG.Util.ChatMessage(ply, "[TPG] Welcome back - your old team is full, pick a side.", Color(255, 200, 0))
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
    ply._tpgAFKBenched = nil
    ply._tpgAFKTeam = nil
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

        if not TPG.Util.IsOnTeam(ply) then
            -- Benched by this system and still idle. Keep sampling: any sign of
            -- life sends them back to their team, and if the server fills up
            -- while they are gone the slot stops being free and they go.
            if ply._tpgAFKBenched then
                if HoldingKey(ply) or AimMoved(ply) then
                    Refresh(ply)
                elseif SlotIsContended() then
                    ply:Kick("AFK - server full")
                end
                continue
            end

            -- An ordinary spectator holds no team slot, so there is nothing to
            -- reclaim -- they're allowed to just watch. Clear any pending warn
            -- state so they don't get kicked the instant they pick a side.
            ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
            ply._tpgWarned = false
            continue
        end

        -- On a team under their own power: whatever the bench recorded is spent.
        ply._tpgAFKTeam = nil

        -- Sampled before the deadline is read, so a player who is busy right
        -- now is never warned for what they were doing half a second ago.
        if HoldingKey(ply) or AimMoved(ply) then
            Refresh(ply)
        end

        local afkTime = ply._tpgLastActivity or (CurTime() + TPG.Config.afkKickTime)
        local timeLeft = afkTime - CurTime()

        if timeLeft <= TPG.Config.afkWarningTime and not ply._tpgWarned then
            -- Say which one it will be. "Or be kicked" on a half-empty server
            -- is a threat the gamemode does not carry out, and a player who
            -- learns that stops reading the warning at all.
            local fate = SlotIsContended() and "be kicked" or "be moved to spectators"
            local secs = math.ceil(timeLeft)

            TPG.Util.ChatMessage(ply, "[TPG] AFK Warning: Move within " .. secs ..
                " seconds or " .. fate .. ".", Color(255, 0, 0))
            ply:PrintMessage(HUD_PRINTCENTER, "AFK - move within " .. secs .. "s or " .. fate)
            ply._tpgWarned = true
        elseif timeLeft <= 0 then
            if SlotIsContended() then
                ply:Kick("AFK")
            else
                Bench(ply)
            end
        end
    end
end)
