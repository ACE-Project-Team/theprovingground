--[[
    Shared Utility Functions
]]

TPG.Util = {}

-- Messaging (server only implementations)
if SERVER then
    function TPG.Util.ChatMessage(ply, message, color)
        color = color or color_white
        
        net.Start("TPG_ChatMessage")
            net.WriteColor(color)
            net.WriteString(message)
        net.Send(ply)
    end
    
    function TPG.Util.ChatBroadcast(message, color)
        color = color or color_white
        
        net.Start("TPG_ChatMessage")
            net.WriteColor(color)
            net.WriteString(message)
        net.Broadcast()
    end
    
    function TPG.Util.ChatTeam(teamId, message, color)
        color = color or TPG.GetTeamData(teamId).color
        
        for _, ply in ipairs(team.GetPlayers(teamId)) do
            TPG.Util.ChatMessage(ply, message, color)
        end
    end
    
    function TPG.Util.PlaySound(ply, soundPath)
        ply:SendLua(string.format("LocalPlayer():EmitSound(%q)", soundPath))
    end
    
    function TPG.Util.PlaySoundAll(soundPath)
        for _, ply in ipairs(player.GetAll()) do
            TPG.Util.PlaySound(ply, soundPath)
        end
    end
end

-- Math
function TPG.Util.Clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function TPG.Util.UnitsToMeters(units)
    return units / 39.37
end

function TPG.Util.MetersToUnits(meters)
    return meters * 39.37
end

-- Team helpers
function TPG.Util.IsOnTeam(ply)
    local t = ply:Team()
    return t == TEAM_GREEN or t == TEAM_RED
end

function TPG.Util.GetTeamDifference()
    return team.NumPlayers(TEAM_GREEN) - team.NumPlayers(TEAM_RED)
end

function TPG.Util.GetUndermannedTeam()
    local diff = TPG.Util.GetTeamDifference()
    if diff > 0 then return TEAM_RED end
    if diff < 0 then return TEAM_GREEN end
    return nil
end

-- Distance
function TPG.Util.IsWithinDistance(ply, point, distance)
    return ply:GetPos():DistToSqr(point) < (distance * distance)
end

function TPG.Util.GetDistanceMeters(pos1, pos2)
    return TPG.Util.UnitsToMeters(pos1:Distance(pos2))
end

-- PData helpers with defaults
function TPG.Util.GetPData(ply, key, default)
    local val = ply:GetPData("TPG_" .. key, default)
    if val == nil then return default end
    return tonumber(val) or val
end

function TPG.Util.SetPData(ply, key, value)
    ply:SetPData("TPG_" .. key, value)
end