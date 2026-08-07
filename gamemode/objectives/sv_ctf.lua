--[[--
    Capture the Flag: one neutral flag.

    CTF is only available on maps that define a KOTH point; the single neutral
    flag spawns there. Either team can grab it and carry it to their own spawn
    to score, draining the enemy's tickets. The spawn is only a delivery target,
    never where the flag lives. Admins can override the flag spot with the point
    tool.

    Per-flag mechanics (pickup, drop, return, delivery) live on the `tpg_flag`
    entity; this module owns spawning, home resolution and capture scoring.

    **This is the module to copy when adding a game type that needs its own
    scoring.** The pattern is @{SpawnFlags}: @{tpg.rounds.Setup} calls it every
    round unconditionally, and it returns immediately unless the round is
    actually CTF. That keeps the round loop free of per-mode branching -- it
    calls every mode's hook and each one decides whether this round is its
    business. `ARCHITECTURE.md` walks through the other four steps.

    @module tpg.ctf
    @realm server
]]

TPG.CTF = TPG.CTF or {}
TPG.CTF.Flag = nil

--- Can the current map host CTF? That is, is there a point to put the flag on?
-- Checked by the game type roll: when this is false, CTF's slice of the roll
-- falls through to KOTH rather than starting a round that cannot be played.
-- @treturn boolean
-- @realm server
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

--- The flag's home anchor: an admin-placed CTF point, else the map's KOTH point.
-- This is the "can this map host CTF at all" answer. The spot the flag actually
-- uses for a given round comes from @{RollFlagPoint}.
-- @treturn ?Vector nil if the map has neither.
-- @realm server
function TPG.CTF.GetFlagPoint()
    local custom = TPG.Maps.GetCustomFlagPoint and TPG.Maps.GetCustomFlagPoint()
    if custom then return custom end
    return KothPoint()
end

--[[--
    Pick where the flag lives for this round.

    An admin-placed point always wins outright. Otherwise the KOTH point keeps
    at least a 50% share (`TPG.Config.ctfKothWeight`, clamped to 0.5 and up) and
    the rest is split evenly among the map's CP capture points, so the flag does
    not always sit on the same hill. CP points within about 256 units of the
    KOTH point are skipped, so the roll is not wasted on what is effectively the
    same spot.

    @treturn ?Vector nil if the map has no KOTH point, in which case no flag
     spawns and the round has nothing to score with.
    @realm server
]]
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

--- Remove the flag, if one exists. Safe to call in any mode.
-- @realm server
function TPG.CTF.Cleanup()
    if IsValid(TPG.CTF.Flag) then TPG.CTF.Flag:Remove() end
    TPG.CTF.Flag = nil
end

--- Spawn this round's flag, if this round is CTF.
-- Called unconditionally from @{tpg.rounds.Setup} every round; returns
-- immediately when the game type is anything else, after clearing any flag left
-- over from a previous round. See the module summary -- this no-op-unless-mine
-- shape is the pattern to copy for a new game type.
-- @realm server
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

--[[--
    Score a delivery: the carrier reached their own spawn with the flag.

    Drains `TPG.Config.ctfCaptureTicketLoss` from the enemy pool, multiplied by
    the objective overtime factor -- the same one the control-point drain uses,
    so a CTF round that has gone long ends in a couple of deliveries instead of
    eight. Then credits the carrier's round and lifetime capture counts, pays
    the economy reward if that mode is running, announces it, and sends the flag
    home.

    Called by the `tpg_flag` entity, not by the round loop. It runs the win
    check itself, because the drain happens between scoring steps.

    @tparam Entity flag The flag entity.
    @tparam Player carrier Who delivered it.
    @realm server
]]
function TPG.CTF.OnCapture(flag, carrier)
    if not (IsValid(flag) and IsValid(carrier)) then return end

    local capTeam = carrier:Team()
    local enemy   = TPG.GetEnemyTeam(capTeam)

    -- Drain the enemy's tickets; the normal win check resolves the round.
    -- Overtime multiplies it, same as the control-point drain, so a CTF round
    -- that's gone long ends in a couple of deliveries instead of eight.
    local loss = (TPG.Config.ctfCaptureTicketLoss or 75)
        * ((TPG.Objectives and TPG.Objectives.GetOvertimeDrainMul
            and TPG.Objectives.GetOvertimeDrainMul()) or 1)
    TPG.State.AddScore(enemy, -math.ceil(loss))

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
        TPG.Util.PlaySound(ply, ply:Team() == capTeam and "friends/friend_online.wav" or "friends/friend_offline.wav")
    end

    flag:ReturnHome("captured")

    if TPG.Net and TPG.Net.SyncScores then TPG.Net.SyncScores() end
    if TPG.Rounds and TPG.Rounds.CheckWinCondition then TPG.Rounds.CheckWinCondition() end
end
