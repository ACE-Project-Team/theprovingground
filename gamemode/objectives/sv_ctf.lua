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

-- The map's KOTH capture point -- the flag's default home, ignoring any custom
-- override.
local function KothPoint()
    local koth = TPG.Maps.Get()[GAMEMODE_KOTH]
    local objs = koth and koth.objectives
    if objs and objs[1] then return objs[1].pos end
    return nil
end

-- The map's CP-mode capture points, used as alternate flag homes.
local function CPPoints()
    local cp = TPG.Maps.Get()[GAMEMODE_CP]
    local objs = cp and cp.objectives
    if not objs then return {} end

    local pts = {}
    for _, o in ipairs(objs) do
        if o.pos then pts[#pts + 1] = o.pos end
    end
    return pts
end

-- Resolve the flag's home anchor (custom-placed CTF point, else the KOTH point).
-- Used for the supported check; the actual per-round spot comes from RollFlagPoint.
function TPG.CTF.GetFlagPoint()
    local custom = TPG.Maps.GetCustomFlagPoint and TPG.Maps.GetCustomFlagPoint()
    if custom then return custom end
    return KothPoint()
end

-- Pick the flag's home for THIS round. A custom-placed point always wins.
-- Otherwise the KOTH point keeps at least a 50% share (TPG.Config.ctfKothWeight)
-- and the remaining chance is split evenly among the map's CP capture points, so
-- the flag doesn't always sit on the same hill. CP points sitting basically on
-- top of the KOTH point are skipped so the roll isn't wasted on a duplicate.
function TPG.CTF.RollFlagPoint()
    local custom = TPG.Maps.GetCustomFlagPoint and TPG.Maps.GetCustomFlagPoint()
    if custom then return custom end

    local koth = KothPoint()
    if not koth then return nil end

    local alts = {}
    for _, p in ipairs(CPPoints()) do
        if p:DistToSqr(koth) > (256 * 256) then alts[#alts + 1] = p end
    end
    if #alts == 0 then return koth end

    local kothWeight = math.Clamp(TPG.Config.ctfKothWeight or 0.5, 0.5, 1)
    if math.random() < kothWeight then return koth end
    return alts[math.random(#alts)]
end

function TPG.CTF.Cleanup()
    if IsValid(TPG.CTF.Flag) then TPG.CTF.Flag:Remove() end
    TPG.CTF.Flag = nil
end

function TPG.CTF.SpawnFlags()
    TPG.CTF.Cleanup()
    if TPG.State.gameType ~= GAMEMODE_CTF then return end

    local point = TPG.CTF.RollFlagPoint()
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
