--[[
    Vehicle Systems
]]

TPG.Vehicles = {}

-- Track all seats
TPG.Vehicles.Seats = {}

hook.Add("OnEntityCreated", "TPG_TrackSeats", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        
        if ent:GetClass() == "prop_vehicle_prisoner_pod" then
            TPG.Vehicles.Seats[ent] = {
                lastPos = ent:GetPos(),
                lastVel = Vector(0, 0, 0),
            }
        end
    end)
end)

hook.Add("EntityRemoved", "TPG_UntrackSeats", function(ent)
    TPG.Vehicles.Seats[ent] = nil
end)

-- Easy vehicle entry
function TPG.Vehicles.EasyEntry(ply)
    local tr = ply:GetEyeTrace()
    local owner = tr.Entity:CPPIGetOwner()
    
    if owner ~= ply then
        TPG.Util.ChatMessage(ply, "[TPG] You don't own that vehicle.", Color(255, 0, 0))
        return
    end
    
    -- Find nearest seat owned by player
    local bestSeat = nil
    local bestDist = TPG.Config.easyEntryRange
    
    for seat, data in pairs(TPG.Vehicles.Seats) do
        if not IsValid(seat) then continue end
        if seat:CPPIGetOwner() ~= ply then continue end
        
        local dist = ply:GetPos():Distance(seat:GetPos())
        if dist < bestDist then
            bestDist = dist
            bestSeat = seat
        end
    end
    
    if not bestSeat then
        TPG.Util.ChatMessage(ply, "[TPG] No nearby seat found.", Color(255, 0, 0))
        return
    end
    
    TPG.Util.ChatMessage(ply, "[TPG] Entering vehicle in " .. TPG.Config.easyEntryDelay .. "s. Don't move!", Color(0, 255, 255))
    
    local startPos = ply:GetPos()
    
    timer.Simple(TPG.Config.easyEntryDelay, function()
        if not IsValid(ply) or not IsValid(bestSeat) then return end
        
        local currentPos = ply:GetPos()
        if currentPos:Distance(startPos) > 100 then
            TPG.Util.ChatMessage(ply, "[TPG] You moved too far!", Color(255, 0, 0))
            return
        end
        
        ply:EnterVehicle(bestSeat)
        TPG.Util.ChatMessage(ply, "[TPG] Entered vehicle.", Color(0, 255, 255))
    end)
end

-- Check juggernaut in vehicle
hook.Add("CanPlayerEnterVehicle", "TPG_JuggernautCheck", function(ply, veh)
    local armorId = TPG.Util.GetPData(ply, "Armor", 1)
    local armor = TPG.GetArmor(armorId)
    
    if not armor.canUseSeat then
        TPG.Util.ChatMessage(ply, "[TPG] Your armor is too heavy for seats!", Color(255, 0, 0))
        return false
    end
end)