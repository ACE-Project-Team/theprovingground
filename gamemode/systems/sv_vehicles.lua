--[[--
    Vehicle seat tracking, easy-entry, and the juggernaut seat lock.

    Three small, unrelated pieces of vehicle glue that did not earn their own
    files: a live table of every `prop_vehicle_prisoner_pod` seat in the map
    (kept up to date purely by `OnEntityCreated`/`EntityRemoved`, not by
    scanning `ents.GetAll()`), the "look at your vehicle, hold still, get
    teleported into the nearest seat you own" bind, and a hook that keeps the
    heaviest armor tiers out of seats entirely.

    `TPG.Vehicles.Seats` is reset on `TPG_TrackSeats`/`TPG_UntrackSeats` only,
    never rebuilt wholesale, so it survives round transitions -- seats that
    still exist stay tracked, and only entities that are actually removed drop
    out.

    @module tpg.vehicles
    @realm server
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

--[[--
    Teleport a player into the nearest seat they own, after a short delay.

    Looks at what the player is aiming at and requires it to be owned by them
    (this is an ownership check on the eye-trace target, not on the seat
    itself -- aim at any prop you own, not necessarily the vehicle). Then
    finds the closest tracked seat within `TPG.Config.easyEntryRange` that
    they also own, warns them, and after `TPG.Config.easyEntryDelay` seconds
    enters them into it, provided they have not moved more than 100 units
    from where they were standing when the timer started.

    Bound from `core/sv_commands.lua`'s easy-entry command.

    @tparam Player ply
    @realm server
]]
function TPG.Vehicles.EasyEntry(ply)
    local tr = ply:GetEyeTrace()

    -- An eye trace that hits nothing still returns a result, with the world
    -- (or NULL) as its entity. Aiming at the skybox used to reach straight
    -- into CPPIGetOwner on that.
    if TPG.Util.GetOwner(tr.Entity) ~= ply then
        TPG.Util.ChatMessage(ply, "[TPG] You don't own that vehicle.", Color(255, 0, 0))
        return
    end
    
    -- Find nearest seat owned by player
    local bestSeat = nil
    local bestDist = TPG.Config.easyEntryRange
    
    for seat, data in pairs(TPG.Vehicles.Seats) do
        if not IsValid(seat) then continue end
        if TPG.Util.GetOwner(seat) ~= ply then continue end
        
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

--- Block heavy-armor players from entering any seat.
-- Reads the player's equipped armor (`TPG.GetArmor`, which always resolves to
-- a real entry -- it falls back to armor id 1 for anything unknown, so this
-- never sees a nil armor table) and denies entry when that armor's
-- `canUseSeat` flag is false, the juggernaut tier being the current example.
-- @realm server
-- @function TPG_JuggernautCheck
hook.Add("CanPlayerEnterVehicle", "TPG_JuggernautCheck", function(ply, veh)
    local armorId = TPG.Util.GetPData(ply, "Armor", 1)
    local armor = TPG.GetArmor(armorId)
    
    if not armor.canUseSeat then
        TPG.Util.ChatMessage(ply, "[TPG] Your armor is too heavy for seats!", Color(255, 0, 0))
        return false
    end
end)