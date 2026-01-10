--[[
    ACE/CFW Integration
    Uses ACE's existing tracking - contraption.ACEPoints, contraption.totalMass
]]

TPG.ACE = TPG.ACE or {}

-- Get all contraptions owned by a player
function TPG.ACE.GetPlayerContraptions(ply)
    if not IsValid(ply) then return {} end
    
    local contraptions = {}
    local seen = {}
    
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if not ent.GetContraption then continue end
        
        local owner = ent:CPPIGetOwner()
        if owner ~= ply then continue end
        
        local contraption = ent:GetContraption()
        if contraption and not seen[contraption] then
            seen[contraption] = true
            table.insert(contraptions, contraption)
        end
    end
    
    return contraptions
end

-- Get total ACE points for a player
function TPG.ACE.GetPlayerPoints(ply)
    local total = 0
    
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        -- ACE stores this on the contraption object
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