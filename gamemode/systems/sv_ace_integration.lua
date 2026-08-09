--[[--
    The gamemode's read side of Armored Combat Extended: contraption lookup and point totals.

    TPG runs on top of the ACE vehicle-combat addon, which lives outside this
    repo. ACE (via CFW, the underlying contraption/constraint framework)
    already tracks which entities belong to which contraption and maintains
    running point/mass totals on the contraption object itself
    (`con.ACEPoints`, `con.totalMass`, `con.ACEPointsPerType`, `con.ents`).
    This file does not reimplement any of that -- it only walks ACE's own
    data to answer "what does this player have, and what is it worth."

    Every accessor here goes through @{TPG.ACE.GetPlayerContraptions}, which
    is backed by an owner-to-contraptions map rebuilt at most once per engine
    tick (`engine.TickCount()`) by walking CFW's own `CFW.Contraptions` /
    `con.ents` membership. That is what keeps N callers per update cycle
    (props, mass, points, for every player) from turning into a full
    `ents.GetAll()` sweep each -- see the comment above `ContraptionMap` for
    the before/after. Because the cache is keyed to the tick, it can never
    observe a stale ownership state within that tick, but it also means
    calling this twice in one tick with a contraption change in between (there
    is no such caller today) would not see the change.

    ACE's point system is deliberately LAZY: a split, merge, armor edit or
    linked component only marks a contraption dirty and bumps a generation
    counter, it does not recompute `ACEPoints` until something forces a
    rebuild. Reading it raw can return a stale pre-edit value. Every reader
    here takes a `refresh` argument for exactly this reason -- see the long
    comment on @{TPG.ACE.GetPlayerPoints} for why it defaults to off and what
    forcing it costs.

    @module tpg.ace
    @realm server
]]

TPG.ACE = TPG.ACE or {}

-- Owner -> contraptions, built in ONE pass over CFW's own membership.
--
-- This used to be a full ents.GetAll() sweep per player, per reader. A single
-- PropTracking update asks for props + mass + points on every player, so with
-- N players that was 3N complete entity scans (each with a CPPIGetOwner and a
-- GetContraption on every entity) every 2 seconds. Sweep once and let all the
-- readers share it instead.
--
-- Then the sweep itself went: `CFW.Contraptions` and `con.ents` ARE the index,
-- maintained incrementally by CFW as constraints form and break, so there is
-- nothing here to rebuild. Walking them visits only entities that are in a
-- contraption -- on a busy round that is the vehicles, not the map's props,
-- ragdolls, weapons and gibs as well.
--
-- Owners are still resolved per rebuild rather than cached alongside
-- membership. Ownership is CPPI's and changes without CFW hearing about it:
-- a paste is attributed a moment after the entities exist, and a disconnect
-- can hand a build to nobody. An index that recorded the owner at
-- `entityAdded` time would be wrong for exactly the freshly pasted builds the
-- budget checks care most about.
--
-- The cache is scoped to a single tick, so it can never go stale: a purchase
-- check that runs on the same tick as a spawn still sees the truth. Ownership
-- attribution is unchanged -- a contraption is still credited to every player
-- who owns at least one entity in it, deduped per owner.
local mapTick, mapCache = -1, {}

local function ContraptionMap()
    if mapTick == engine.TickCount() then return mapCache end
    if not CFW or not CFW.Contraptions then return {} end

    local byOwner = {}
    local seen = {}

    for contraption in pairs(CFW.Contraptions) do
        for ent in pairs(contraption.ents or {}) do
            local owner = TPG.Util.GetOwner(ent)

            if owner then
                local seenForOwner = seen[owner]
                if not seenForOwner then
                    seenForOwner = {}
                    seen[owner] = seenForOwner
                    byOwner[owner] = {}
                end

                if not seenForOwner[contraption] then
                    seenForOwner[contraption] = true
                    table.insert(byOwner[owner], contraption)
                end
            end
        end
    end

    mapTick, mapCache = engine.TickCount(), byOwner
    return byOwner
end

--- All contraptions with at least one entity owned by this player.
-- Backed by the per-tick `ContraptionMap` cache; ownership is per-owner
-- entity, deduped, so a contraption with entities owned by two different
-- players is credited to both.
-- @tparam Player ply
-- @treturn table List of contraption objects; empty if the player is invalid
--  or owns nothing.
-- @realm server
function TPG.ACE.GetPlayerContraptions(ply)
    if not IsValid(ply) then return {} end

    return ContraptionMap()[ply] or {}
end

-- ACE's dev point system is lazy: a spawn, a crate link, or any dupe edit only
-- marks the contraption dirty and bumps a generation -- con.ACEPoints is NOT
-- recomputed until someone forces a rebuild. Reading it raw returns a stale
-- pre-edit value (this is why linking GBUs post-spawn didn't move the number).
-- Force the same rebuild the economy path already uses before reading.
local function EnsureConPoints(con)
    if _G.ACE_EnsureContraptionPoints then
        ACE_EnsureContraptionPoints(con, con.GetACEBaseplate and con:GetACEBaseplate() or nil)
    end
end

--[[--
    Total ACE points across everything a player owns.

    `refresh` decides whether we force ACE to bring its numbers up to date
    first. Leave it off for anything periodic. ACE's point system is
    deliberately lazy: a split, merge, armor change or vehicle unfreeze only
    marks the contraption dirty, and nothing rebuilds until a reader actually
    needs the value. Polling it on a timer defeats that design -- it turns
    "rebuild when someone asks" into "rebuild everything, forever" -- and
    combat re-dirties contraptions constantly (every destroyed component
    splits one), so the rebuild is rarely a no-op while a fight is happening.
    Each rebuild also fires `ACE_OnContraptionPointsRecalculated`, which runs
    TPG's own re-bill listener (@{tpg.economy}).

    This is the one thing TPG asks of ACE that plain sandbox+ACE never does,
    which makes it the first suspect for "same tanks, but only laggy under
    TPG."

    @tparam Player ply
    @tparam[opt=false] boolean refresh Force a rebuild before reading.
    @treturn number
    @realm server
]]
function TPG.ACE.GetPlayerPoints(ply, refresh)
    local total = 0

    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- ACE stores this on the contraption object
        if refresh then EnsureConPoints(con) end
        total = total + (con.ACEPoints or 0)
    end

    return total
end

--- Total mass across everything a player owns.
-- CFW keeps `con.totalMass` up to date automatically as entities are
-- added/removed, so unlike points this never needs a forced refresh.
-- @tparam Player ply
-- @treturn number
-- @realm server
function TPG.ACE.GetPlayerMass(ply)
    local total = 0
    
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- CFW stores totalMass on the contraption
        -- It's updated automatically when entities are added/removed
        total = total + (con.totalMass or 0)
    end
    
    return total
end

--- Points broken down by category (Armor, Engines, Firepower, Fuel, Ammo, Crew, Electronics).
-- See @{TPG.ACE.GetPlayerPoints} for what `refresh` costs.
-- @tparam Player ply
-- @tparam[opt=false] boolean refresh Force a rebuild before reading.
-- @treturn table Category name to point total. The seven categories above are
--  always present, even at 0; any other category ACE reports on
--  `con.ACEPointsPerType` is also summed in and appears as an extra key.
-- @realm server
function TPG.ACE.GetPlayerPointsByType(ply, refresh)
    local totals = {
        Armor = 0,
        Engines = 0,
        Firepower = 0,
        Fuel = 0,
        Ammo = 0,
        Crew = 0,
        Electronics = 0,
    }
    
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        if refresh then EnsureConPoints(con) end
        local breakdown = con.ACEPointsPerType
        if breakdown then
            for category, points in pairs(breakdown) do
                totals[category] = (totals[category] or 0) + (points or 0)
            end
        end
    end
    
    return totals
end

--- Count of `prop_physics` entities across everything a player owns.
-- Only counts the `prop_physics` class -- other entity types in the
-- contraption (wheels, thrusters, ACE components that aren't plain props)
-- are not included.
-- @tparam Player ply
-- @treturn number
-- @realm server
function TPG.ACE.GetPlayerPropCount(ply)
    local count = 0
    
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- CFW stores all entities in con.ents
        if con.ents then
            for ent in pairs(con.ents) do
                if IsValid(ent) then
                    local class = ent:GetClass()
                    if class == "prop_physics" then
                        count = count + 1
                    end
                end
            end
        end
    end
    
    return count
end

--- Print a player's contraptions, points, mass and prop count to console.
-- Debug aid, wired to the `tpg_debug_ace` concommand below. Reads points
-- without forcing a refresh, so a value can look stale immediately after an
-- edit.
-- @tparam Player ply
-- @realm server
function TPG.ACE.DebugPlayer(ply)
    print("=== TPG ACE Debug for " .. ply:Nick() .. " ===")
    
    for i, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        print("Contraption " .. i .. ":")
        print("  ACEPoints: " .. (con.ACEPoints or "nil"))
        print("  totalMass: " .. (con.totalMass or "nil"))
        
        if con.ACEPointsPerType then
            print("  Points by type:")
            for k, v in pairs(con.ACEPointsPerType) do
                print("    " .. k .. ": " .. v)
            end
        end
        
        if con.ents then
            local entCount = 0
            for _ in pairs(con.ents) do entCount = entCount + 1 end
            print("  Entity count: " .. entCount)
        end
    end
    
    print("Total Mass: " .. TPG.ACE.GetPlayerMass(ply))
    print("Total Points: " .. TPG.ACE.GetPlayerPoints(ply))
    print("Total Props: " .. TPG.ACE.GetPlayerPropCount(ply))
    print("================")
end

-- Console command to debug
concommand.Add("tpg_debug_ace", function(ply)
    if IsValid(ply) then
        TPG.ACE.DebugPlayer(ply)
    end
end)