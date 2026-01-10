--[[
    AFK Detection and Kick
]]

TPG.AFK = {}

hook.Add("PlayerInitialSpawn", "TPG_AFK_Init", function(ply)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
    ply._tpgWarned = false
end)

hook.Add("KeyPress", "TPG_AFK_Activity", function(ply, key)
    ply._tpgLastActivity = CurTime() + TPG.Config.afkKickTime
    
    if ply._tpgWarned then
        ply._tpgWarned = false
        TPG.Util.ChatMessage(ply, "[TPG] You are no longer AFK.", Color(0, 255, 0))
    end
end)

hook.Add("Think", "TPG_AFK_Check", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:IsConnected() or not ply:IsFullyAuthenticated() then continue end
        
        local afkTime = ply._tpgLastActivity or (CurTime() + TPG.Config.afkKickTime)
        local timeLeft = afkTime - CurTime()
        
        if timeLeft <= TPG.Config.afkWarningTime and not ply._tpgWarned then
            TPG.Util.ChatMessage(ply, "[TPG] AFK Warning: Move within " .. math.ceil(timeLeft) .. " seconds or be kicked.", Color(255, 0, 0))
            ply._tpgWarned = true
        elseif timeLeft <= 0 then
            ply:Kick("AFK")
        end
    end
end)