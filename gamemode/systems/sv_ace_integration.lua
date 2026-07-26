--[[
    ACE/CFW Integration
    Uses ACE's existing tracking - contraption.ACEPoints, contraption.totalMass
]]

TPG.ACE = TPG.ACE or {}

-- Owner -> contraptions, built in ONE pass over the entity list.
--
-- This used to be a full ents.GetAll() sweep per player, per reader. A single
-- PropTracking update asks for props + mass + points on every player, so with
-- N players that was 3N complete entity scans (each with a CPPIGetOwner and a
-- GetContraption on every entity) every 2 seconds. Sweep once and let all the
-- readers share it instead.
--
-- The cache is scoped to a single tick, so it can never go stale: a purchase
-- check that runs on the same tick as a spawn still sees the truth. Ownership
-- attribution is unchanged -- a contraption is still credited to every player
-- who owns at least one entity in it, deduped per owner.
local mapTick, mapCache = -1, {}

local function ContraptionMap()
    if mapTick == engine.TickCount() then return mapCache end

    local byOwner = {}
    local seen = {}

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if not ent.GetContraption then continue end

        local owner = ent:CPPIGetOwner()
        if not IsValid(owner) then continue end

        local contraption = ent:GetContraption()
        if not contraption then continue end

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

    mapTick, mapCache = engine.TickCount(), byOwner
    return byOwner
end

-- Get all contraptions owned by a player
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

-- Get total ACE points for a player
function TPG.ACE.GetPlayerPoints(ply)
    local total = 0

    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- ACE stores this on the contraption object (rebuilt on demand above)
        EnsureConPoints(con)
        total = total + (con.ACEPoints or 0)
    end

    return total
end

-- Get total mass for a player (CFW tracks this)
function TPG.ACE.GetPlayerMass(ply)
    local total = 0
    
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- CFW stores totalMass on the contraption
        -- It's updated automatically when entities are added/removed
        total = total + (con.totalMass or 0)
    end
    
    return total
end

-- Get points breakdown by type
function TPG.ACE.GetPlayerPointsByType(ply)
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
        EnsureConPoints(con)
        local breakdown = con.ACEPointsPerType
        if breakdown then
            for category, points in pairs(breakdown) do
                totals[category] = (totals[category] or 0) + (points or 0)
            end
        end
    end
    
    return totals
end

-- Get prop count for a player (count entities in contraptions)
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

-- Debug: Print contraption info for a player
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