--[[
    Capture the Flag (one neutral flag)

    CTF is only available on maps that define a KOTH point; the single neutral
    flag spawns on that point. Either team can grab it and carry it to their own
    spawn to score, draining the enemy's tickets. The spawn is only a delivery
    target, never where the flag lives. Admins can override the flag spot with
    the point tool.

    Per-flag mechanics (pickup / drop / return / delivery) live on the tpg_flag
    entity; this module owns spawning, home resolution, and capture scoring.
]]

TPG.CTF = TPG.CTF or {}
TPG.CTF.Flag = nil

-- Does the current map support CTF? (i.e. is there a KOTH point to host it?)
function TPG.CTF.IsSupported()
    return TPG.CTF.GetFlagPoint() ~= nil
end

-- Resolve the flag's home: a custom-placed CTF point, else the map's KOTH point.
function TPG.CTF.GetFlagPoint()
    local custom = TPG.Maps.GetCustomFlagPoint and TPG.Maps.GetCustomFlagPoint()
    if custom then return custom end

    local koth = TPG.Maps.Get()[GAMEMODE_KOTH]
    local objs = koth and koth.objectives
    if objs and objs[1] then return objs[1].pos end

    return nil
end

function TPG.CTF.Cleanup()
    if IsValid(TPG.CTF.Flag) then TPG.CTF.Flag:Remove() end
    TPG.CTF.Flag = nil
end

function TPG.CTF.SpawnFlags()
    TPG.CTF.Cleanup()
    if TPG.State.gameType ~= GAMEMODE_CTF then return end

    local point = TPG.CTF.GetFlagPoint()
    if not point then
        print("[TPG] CTF: no KOTH point on this map, cannot spawn flag")
        return
    end

    local pos  = point + Vector(0, 0, 5)
    local flag = ents.Create("tpg_flag")
    if not IsValid(flag) then return end

    flag.HomePos = pos
    flag:SetPos(pos)
    flag:Spawn()
    flag:SetHome(pos)

    TPG.CTF.Flag = flag
    print("[TPG] CTF: spawned the flag")
end

-- Called by the flag entity when a carrier reaches their own spawn.
function TPG.CTF.OnCapture(flag, carrier)
    if not (IsValid(flag) and IsValid(carrier)) then return end

    local capTeam = carrier:Team()
    local enemy   = TPG.GetEnemyTeam(capTeam)

    -- Drain the enemy's tickets; the normal win check resolves the round.
    TPG.State.AddScore(enemy, -(TPG.Config.ctfCaptureTicketLoss or 75))

    local ps = TPG.State.GetPlayer(carrier)
    ps.stats.captures = (ps.stats.captures or 0) + 1
    if TPG.Economy and TPG.Economy.Reward then
        TPG.Economy.Reward(carrier, TPG.Config.ctfCaptureReward or 1500, "ctf_capture")
    end
    if TPG.Stats and TPG.Stats.OnFlagCapture then
        TPG.Stats.OnFlagCapture(carrier)
    end

    local td = TPG.GetTeamData(capTeam)
    TPG.Util.ChatBroadcast("[CTF] " .. carrier:Nick() .. " delivered the flag for " ..
        td.name .. "!", td.color)

    for _, ply in ipairs(player.GetAll()) do
        TPG.Util.PlaySound(ply, ply:Team() == capTeam and "Announcer.Success" or "Announcer.Failure")
    end

    flag:ReturnHome("captured")

    if TPG.Net and TPG.Net.SyncScores then TPG.Net.SyncScores() end
    if TPG.Rounds and TPG.Rounds.CheckWinCondition then TPG.Rounds.CheckWinCondition() end
end
