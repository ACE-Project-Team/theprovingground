--[[--
    Small shared helpers: chat, unit conversion, team counting, per-player
    storage.

    Everything here is used from more than one system and has no state of its
    own. If a helper only makes sense to one system, it belongs in that
    system's file rather than here.

    @module tpg.util
    @realm shared
]]

TPG.Util = {}

-- ── Messaging ───────────────────────────────────────────────────────────────
-- Server only: these all end up sending a net message, and the client is the
-- end of that trip, not the start of it.
if SERVER then
    --- Send a chat line to one player.
    -- @tparam Player ply Recipient.
    -- @tparam string message Text to send.
    -- @tparam[opt=white] Color color Colour to print it in.
    -- @realm server
    function TPG.Util.ChatMessage(ply, message, color)
        color = color or color_white

        net.Start("TPG_ChatMessage")
            net.WriteColor(color)
            net.WriteString(message)
        net.Send(ply)
    end

    -- Last time each player was told about a given thing. Weak-keyed on the
    -- player so a disconnect drops the entry without a cleanup hook.
    local lastTold = setmetatable({}, { __mode = "k" })

    --[[--
        Send a chat line, at most once every `interval` seconds per player.

        For messages driven by an event the player can fire dozens of times in
        a tick: a spawn-menu click held down, a paste of thirty props refused
        one prop at a time. Without this the refusal is technically correct and
        completely unreadable, and the useful line above it is gone from the
        chat box.

        `key` is what gets rate limited, not the text, so a message whose body
        carries a changing count still collapses to one line per interval.
        Different keys never suppress each other, so an unrelated warning
        arriving in the same second still gets through.

        @tparam Player ply Recipient.
        @tparam string key Groups messages that should suppress one another.
        @tparam string message Text to send.
        @tparam[opt=white] Color color Colour to print it in.
        @tparam[opt=2] number interval Seconds of silence after a send.
        @treturn boolean Whether the line was actually sent.
        @realm server
    ]]
    function TPG.Util.ChatMessageThrottled(ply, key, message, color, interval)
        if not IsValid(ply) then return false end

        local told = lastTold[ply]
        if not told then
            told = {}
            lastTold[ply] = told
        end

        if (told[key] or 0) > CurTime() then return false end
        told[key] = CurTime() + (interval or 2)

        TPG.Util.ChatMessage(ply, message, color)
        return true
    end

    --- Send a chat line to everyone on the server.
    -- @tparam string message Text to send.
    -- @tparam[opt=white] Color color Colour to print it in.
    -- @realm server
    function TPG.Util.ChatBroadcast(message, color)
        color = color or color_white

        net.Start("TPG_ChatMessage")
            net.WriteColor(color)
            net.WriteString(message)
        net.Broadcast()
    end

    --- Send a chat line to every player on one team.
    -- @tparam number teamId TEAM_GREEN or TEAM_RED.
    -- @tparam string message Text to send.
    -- @tparam[opt] Color color Defaults to that team's own colour.
    -- @realm server
    function TPG.Util.ChatTeam(teamId, message, color)
        color = color or TPG.GetTeamData(teamId).color

        for _, ply in ipairs(team.GetPlayers(teamId)) do
            TPG.Util.ChatMessage(ply, message, color)
        end
    end

    --- Play a sound on one player's client.
    -- @tparam Player ply Who hears it.
    -- @tparam string soundPath Sound file, as EmitSound takes it.
    -- @realm server
    function TPG.Util.PlaySound(ply, soundPath)
        ply:SendLua(string.format("LocalPlayer():EmitSound(%q)", soundPath))
    end

    --- Play a sound on every connected client.
    -- @tparam string soundPath Sound file, as EmitSound takes it.
    -- @realm server
    function TPG.Util.PlaySoundAll(soundPath)
        for _, ply in ipairs(player.GetAll()) do
            TPG.Util.PlaySound(ply, soundPath)
        end
    end
end

-- ── Ownership ───────────────────────────────────────────────────────────────

--[[--
    Who owns this entity, according to the prop-protection addon.

    Ownership comes from CPPI, which is an INTERFACE, not an addon: whichever
    prop protection is installed (NADMOD, FPP, SPP) provides it, and a server
    running none of them has no `CPPIGetOwner` at all. Calling it unguarded is
    an error on exactly the servers least able to debug it, so every read of
    an owner in this gamemode goes through here.

    A missing provider is reported as "nobody owns anything" rather than as a
    failure, because that is what it means: with nothing tracking ownership
    there is no answer to give. Callers already handle the no-owner case, and
    the systems that care loudly about a missing provider say so once at
    startup (see `systems/sv_ace_permission.lua`) instead of at every call.

    @tparam Entity ent
    @treturn ?Player The owner, or nil for an invalid entity, no provider, or
     genuinely unowned. World-owned entities come back nil too.
    @realm shared
]]
function TPG.Util.GetOwner(ent)
    if not IsValid(ent) or not ent.CPPIGetOwner then return nil end

    local owner = ent:CPPIGetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return nil end

    return owner
end

-- ── Math ────────────────────────────────────────────────────────────────────

--- Clamp a number to a range.
-- @tparam number val
-- @tparam number min
-- @tparam number max
-- @treturn number val, held between min and max.
function TPG.Util.Clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

--- Source units to metres.
-- Source units are roughly an inch, so this is the divisor everything that
-- shows a player a distance goes through -- the compass and the objective HUD
-- both read in metres because that is what the vehicles are scaled to.
-- @tparam number units
-- @treturn number Metres.
function TPG.Util.UnitsToMeters(units)
    return units / 39.37
end

--- Metres to Source units.
-- @tparam number meters
-- @treturn number Units.
function TPG.Util.MetersToUnits(meters)
    return meters * 39.37
end

-- ── Team helpers ────────────────────────────────────────────────────────────

--- Is this player on one of the two playing teams?
-- False for spectators and for anyone who hasn't picked yet, which is why it
-- is the guard in front of anything that scores or awards.
-- @tparam Player ply
-- @treturn boolean
function TPG.Util.IsOnTeam(ply)
    local t = ply:Team()
    return t == TEAM_GREEN or t == TEAM_RED
end

--- How lopsided the teams are, as green minus red.
-- @treturn number Positive means green has more players.
function TPG.Util.GetTeamDifference()
    return team.NumPlayers(TEAM_GREEN) - team.NumPlayers(TEAM_RED)
end

--- Which team is short of players.
-- @treturn ?number TEAM_GREEN, TEAM_RED, or nil when the teams are even.
function TPG.Util.GetUndermannedTeam()
    local diff = TPG.Util.GetTeamDifference()
    if diff > 0 then return TEAM_RED end
    if diff < 0 then return TEAM_GREEN end
    return nil
end

-- ── Distance ────────────────────────────────────────────────────────────────

--- Is a player within a radius of a point?
-- Compares squared distances, so it is safe to call every tick.
-- @tparam Player ply
-- @tparam Vector point
-- @tparam number distance Radius in Source units.
-- @treturn boolean
function TPG.Util.IsWithinDistance(ply, point, distance)
    return ply:GetPos():DistToSqr(point) < (distance * distance)
end

--- Distance between two points, in metres.
-- @tparam Vector pos1
-- @tparam Vector pos2
-- @treturn number Metres.
function TPG.Util.GetDistanceMeters(pos1, pos2)
    return TPG.Util.UnitsToMeters(pos1:Distance(pos2))
end

-- ── Per-player storage ──────────────────────────────────────────────────────

--[[--
    Read a persistent per-player value.

    This is GMod's PData, so it lives in the server's sv.db keyed by SteamID
    and survives map changes and restarts. It is where a player's own choices
    go -- their loadout, their armor -- as opposed to their lifetime record,
    which is a file so that a leaderboard can see players who aren't connected
    (see @{tpg.stats}).

    Every key is prefixed with `TPG_` so the gamemode can never collide with
    another addon's PData on the same server.

    PData stores strings. The value comes back as a number if it looks like
    one, which is what lets the callers store an armor id and get an armor id
    back rather than "3".

    @tparam Player ply
    @tparam string key Key, without the TPG_ prefix.
    @tparam[opt] any default Returned when nothing is stored.
    @treturn any The stored value as a number where possible, else a string,
     else `default`.
    @realm server
]]
function TPG.Util.GetPData(ply, key, default)
    local val = ply:GetPData("TPG_" .. key, default)
    if val == nil then return default end
    return tonumber(val) or val
end

--- Write a persistent per-player value.
-- @tparam Player ply
-- @tparam string key Key, without the TPG_ prefix.
-- @tparam any value Stored as a string; see @{TPG.Util.GetPData}.
-- @realm server
function TPG.Util.SetPData(ply, key, value)
    ply:SetPData("TPG_" .. key, value)
end