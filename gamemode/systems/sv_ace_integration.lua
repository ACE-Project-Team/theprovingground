--[[
    ACE/CFW Integration
    Hooks into CFW contraption system for point tracking
]]

TPG.ACE = {}

-- Track contraptions per team
TPG.ACE.TeamContraptions = {
    [TEAM_GREEN] = {},
    [TEAM_RED] = {},
}

-- Material cost table
TPG.ACE.MaterialCosts = {
    ["RHA"]         = 1.0,
    ["CHA"]         = 1.1,
    ["Aluminum"]    = 0.7,
    ["Titanium"]    = 1.5,
    ["Ceramic"]     = 1.3,
    ["ERA"]         = 2.0,
    ["Rubber"]      = 0.3,
    ["Glass"]       = 0.2,
}

-- Entity type classification
TPG.ACE.EntityTypes = {
    ["acf_engine"]              = "Engines",
    ["acf_gun"]                 = "Firepower",
    ["acf_rack"]                = "Firepower",
    ["acf_fueltank"]            = "Fuel",
    ["acf_ammo"]                = "Ammo",
    ["ace_crewseat_gunner"]     = "Crew",
    ["ace_crewseat_loader"]     = "Crew",
    ["ace_crewseat_driver"]     = "Crew",
    ["ace_rwr_dir"]             = "Electronics",
    ["ace_rwr_sphere"]          = "Electronics",
    ["acf_missileradar"]        = "Electronics",
    ["acf_opticalcomputer"]     = "Electronics",
    ["ace_ecm"]                 = "Electronics",
    ["ace_trackingradar"]       = "Electronics",
    ["ace_searchradar"]         = "Electronics",
    ["ace_irst"]                = "Electronics",
    ["ace_sonar"]               = "Electronics",
}

-- Calculate points for an entity
function TPG.ACE.CalculatePoints(ent)
    if not IsValid(ent) then return 0 end
    
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return 0 end
    
    local mass = phys:GetMass()
    local pointsPerTon = 100
    
    -- Use ACF value if available
    if ACF and ACF.PointsPerTon then
        pointsPerTon = ACF.PointsPerTon
    end
    
    local points = (mass / 1000) * pointsPerTon
    
    -- Apply material multiplier
    local entACF = ent.ACF or {}
    local material = entACF.Material or "RHA"
    local matCost = TPG.ACE.MaterialCosts[material] or 1.0
    
    -- Apply ductility factor
    local ductility = entACF.Ductility or 0
    local ductMul = 1 / math.pow(1 + ductility, 0.5)
    
    points = points * matCost * ductMul
    
    -- Add special entity points
    points = points + (ent.ACEPoints or 0)
    
    return points
end

function TPG.ACE.GetEntityType(ent)
    if not IsValid(ent) then return "Armor" end
    return TPG.ACE.EntityTypes[ent:GetClass()] or "Armor"
end

-- Called when CFW creates a contraption
hook.Add("cfw.contraption.created", "TPG_ContraptionCreated", function(contraption)
    if not TPG.CFWAvailable then return end
    
    -- Initialize ACE points tracking
    contraption.TPG_Points = 0
    contraption.TPG_PointsByType = {
        Armor = 0,
        Engines = 0,
        Firepower = 0,
        Fuel = 0,
        Ammo = 0,
        Crew = 0,
        Electronics = 0,
    }
end)

-- Called when entity added to contraption
hook.Add("cfw.contraption.entityAdded", "TPG_EntityAdded", function(contraption, ent)
    if not TPG.CFWAvailable then return end
    if not IsValid(ent) then return end
    
    local points = TPG.ACE.CalculatePoints(ent)
    ent._tpgPoints = points
    
    contraption.TPG_Points = (contraption.TPG_Points or 0) + points
    
    -- Track by type
    local entType = TPG.ACE.GetEntityType(ent)
    contraption.TPG_PointsByType = contraption.TPG_PointsByType or {}
    contraption.TPG_PointsByType[entType] = (contraption.TPG_PointsByType[entType] or 0) + points
    
    -- Update team totals
    TPG.ACE.UpdateTeamPoints(ent, false)
end)

-- Called when entity removed from contraption
hook.Add("cfw.contraption.entityRemoved", "TPG_EntityRemoved", function(contraption, ent)
    if not TPG.CFWAvailable then return end
    if not IsValid(ent) then return end
    
    local points = ent._tpgPoints or 0
    contraption.TPG_Points = math.max(0, (contraption.TPG_Points or 0) - points)
    
    local entType = TPG.ACE.GetEntityType(ent)
    contraption.TPG_PointsByType = contraption.TPG_PointsByType or {}
    contraption.TPG_PointsByType[entType] = math.max(0, (contraption.TPG_PointsByType[entType] or 0) - points)
    
    -- Update team totals
    TPG.ACE.UpdateTeamPoints(ent, true)
end)

-- Update team point totals
function TPG.ACE.UpdateTeamPoints(ent, removing)
    if not IsValid(ent) then return end
    
    local owner = ent:CPPIGetOwner()
    if not IsValid(owner) then return end
    if not owner:IsPlayer() then return end
    
    local teamId = owner:Team()
    if not TPG.Util.IsOnTeam(owner) then return end
    
    -- Recalculate team totals after a short delay
    timer.Simple(0.1, function()
        if TPG.PropTracking and TPG.PropTracking.UpdateTeamTotals then
            TPG.PropTracking.UpdateTeamTotals()
        end
    end)
end

-- Check contraption legality
function TPG.ACE.CheckLegality(contraption)
    if not contraption then return end
    
    local baseplate = nil
    if contraption.GetACEBaseplate then
        baseplate = contraption:GetACEBaseplate()
    end
    
    if not IsValid(baseplate) then return end
    
    local owner = baseplate:CPPIGetOwner()
    if not IsValid(owner) then return end
    
    local points = contraption.TPG_Points or 0
    local maxPoints = TPG.Config.playerPointLimit
    
    if points > maxPoints then
        local overBy = math.ceil(points - maxPoints)
        TPG.Util.ChatBroadcast(
            "[TPG] " .. owner:Nick() .. " has a vehicle " .. overBy .. "pts over the limit!",
            Color(255, 234, 0)
        )
    end
end

-- Hook for CFW family events (alternative structure)
hook.Add("cfw.family.created", "TPG_FamilyCreated", function(family)
    if not TPG.CFWAvailable then return end
    
    family.TPG_Points = 0
    family.TPG_PointsByType = {
        Armor = 0,
        Engines = 0,
        Firepower = 0,
        Fuel = 0,
        Ammo = 0,
        Crew = 0,
        Electronics = 0,
    }
end)

hook.Add("cfw.family.added", "TPG_FamilyAdded", function(family, ent)
    if not TPG.CFWAvailable then return end
    if not IsValid(ent) then return end
    
    local points = TPG.ACE.CalculatePoints(ent)
    ent._tpgPoints = points
    
    family.TPG_Points = (family.TPG_Points or 0) + points
    
    local entType = TPG.ACE.GetEntityType(ent)
    family.TPG_PointsByType = family.TPG_PointsByType or {}
    family.TPG_PointsByType[entType] = (family.TPG_PointsByType[entType] or 0) + points
end)

hook.Add("cfw.family.subbed", "TPG_FamilyRemoved", function(family, ent)
    if not TPG.CFWAvailable then return end
    if not IsValid(ent) then return end
    
    local points = ent._tpgPoints or 0
    family.TPG_Points = math.max(0, (family.TPG_Points or 0) - points)
    
    local entType = TPG.ACE.GetEntityType(ent)
    family.TPG_PointsByType = family.TPG_PointsByType or {}
    family.TPG_PointsByType[entType] = math.max(0, (family.TPG_PointsByType[entType] or 0) - points)
end)