--[[
    Per-Player Economy (BETA)

    Each player has a personal wallet of points ("money"), earned through
    captures (objective hold), kills, and passive income, and spent on vehicles
    as a TRUE PURCHASE -- a destroyed tank is NOT refunded. While active this
    REPLACES the shared per-team point budget (the team weight/prop limits stay
    as physical guardrails).

    The economy is a SECONDARY MODE: each round it has a TPG.Config.economyChance
    chance to switch on (tpg_economy_random), or an admin can force it always-on
    (tpg_economy_enabled). The active state is rolled in TPG.Rounds.Setup via
    ECON.RollForRound() and announced so players know the round is per-player.
]]

TPG.Economy = TPG.Economy or {}
local ECON = TPG.Economy

-- ── Tunables (need play-testing; reference: strong tank ~= 11,000 pts) ─────
ECON.Config = {
    startingMoney     = 6000,   -- enough for a medium; a strong tank must be earned
    maxMoney          = 60000,  -- wallet cap

    passiveIncome     = 100,    -- granted every passiveInterval seconds
    passiveInterval   = 10,

    captureHoldIncome = 60,     -- per interval, per objective you are standing on
    captureRadiusM    = 30,     -- metres from an objective to earn hold income

    killRewardBase    = 200,    -- flat reward per enemy kill
    killRewardVehFrac = 0.05,   -- + this fraction of the victim's vehicle value
    killRewardMax     = 2000,   -- per-kill clamp

    resetEachRound    = true,   -- wallet resets to startingMoney each round
}

-- Rolled per round (see ECON.RollForRound).
ECON.Active = false

-- Admin force-on. When 1 the economy is always active, overriding the random roll.
local cv = CreateConVar("tpg_economy_enabled", "0",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Force the per-player economy ON every round. Overrides tpg_economy_random.")

-- When 1 (and not force-on), the economy is a secondary mode with a per-round
-- chance (TPG.Config.economyChance) to be active.
local cvRandom = CreateConVar("tpg_economy_random", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Treat the per-player economy as a secondary mode: per-round chance to activate.")

-- ── Wallet helpers ────────────────────────────────────────────────────────
function ECON.GetMoney(ply)
    if not IsValid(ply) then return 0 end
    return TPG.State.GetPlayer(ply).money or 0
end

function ECON.SetMoney(ply, amount)
    if not IsValid(ply) then return end
    local pState = TPG.State.GetPlayer(ply)
    pState.money = math.Clamp(math.floor(amount), 0, ECON.Config.maxMoney)
    ply:SetNWInt("TPG_Money", pState.money)
end

function ECON.Reward(ply, amount, _reason)
    if not ECON.Active or not IsValid(ply) or (amount or 0) <= 0 then return end
    ECON.SetMoney(ply, ECON.GetMoney(ply) + amount)
end

function ECON.CanAfford(ply, cost)
    return ECON.GetMoney(ply) >= math.floor(cost or 0)
end

function ECON.Charge(ply, cost)
    if not IsValid(ply) then return false end
    cost = math.floor(cost or 0)
    if ECON.GetMoney(ply) < cost then return false end
    ECON.SetMoney(ply, ECON.GetMoney(ply) - cost)
    return true
end

-- ── Vehicle cost = sum of unique contraption ACEPoints in a set of ents ────
function ECON.GetContraptionCost(entList)
    local seen, cost = {}, 0
    for _, ent in pairs(entList) do
        if not IsValid(ent) or not ent.GetContraption then continue end
        local con = ent:GetContraption()
        if not con or seen[con] then continue end
        seen[con] = true

        -- Make sure ACE's point total is up to date before reading it.
        if _G.ACE_EnsureContraptionPoints then
            ACE_EnsureContraptionPoints(con, con.GetACEBaseplate and con:GetACEBaseplate() or nil)
        end
        cost = cost + (con.ACEPoints or 0)
    end
    return cost
end

-- ── Income: passive + objective hold ──────────────────────────────────────
local lastTick = 0
hook.Add("Think", "TPG_EconomyIncome", function()
    if not ECON.Active then return end
    if CurTime() - lastTick < ECON.Config.passiveInterval then return end
    lastTick = CurTime()

    local capRadius  = TPG.Util.MetersToUnits(ECON.Config.captureRadiusM)
    local objectives = TPG.State.objectives or {}

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        if not TPG.Util.IsOnTeam(ply) then continue end

        ECON.Reward(ply, ECON.Config.passiveIncome, "passive")

        for _, obj in pairs(objectives) do
            if IsValid(obj) and ply:GetPos():Distance(obj:GetPos()) < capRadius then
                ECON.Reward(ply, ECON.Config.captureHoldIncome, "hold")
            end
        end
    end
end)

-- ── Income: kills (anti-farm: nothing for safezone kills / protected targets)
hook.Add("PlayerDeath", "TPG_EconomyKillReward", function(victim, _inflictor, attacker)
    if not ECON.Active then return end
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if attacker == victim or attacker:Team() == victim:Team() then return end

    -- No reward for kills made from your own safezone...
    if TPG.Protection and TPG.Protection.IsInSafezone and TPG.Protection.IsInSafezone(attacker) then
        return
    end
    -- ...or against a spawn-protected / safezoned victim.
    if (TPG.State.GetPlayer(victim).spawnProtection or 0) > 0 then return end
    if TPG.Protection and TPG.Protection.IsInSafezone and TPG.Protection.IsInSafezone(victim) then
        return
    end

    -- Scale reward by the value of the vehicle the victim was fielding.
    local vehValue = (TPG.ACE and TPG.ACE.GetPlayerPoints and TPG.ACE.GetPlayerPoints(victim)) or 0
    local reward   = math.min(ECON.Config.killRewardBase + vehValue * ECON.Config.killRewardVehFrac,
                              ECON.Config.killRewardMax)
    ECON.Reward(attacker, reward, "kill")
end)

-- ── Lifecycle ──────────────────────────────────────────────────────────────
function ECON.ResetWallets()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then ECON.SetMoney(ply, ECON.Config.startingMoney) end
    end
end

-- Called from TPG.State.ResetRound().
function ECON.OnRoundReset()
    if ECON.Active and ECON.Config.resetEachRound then ECON.ResetWallets() end
end

-- Per-round activation roll. The economy behaves like a secondary game mode:
-- forced always-on by tpg_economy_enabled, otherwise a TPG.Config.economyChance
-- chance each round (tpg_economy_random). Call this from TPG.Rounds.Setup BEFORE
-- ResetRound so OnRoundReset sees the correct state.
function ECON.RollForRound()
    if cv:GetBool() then
        ECON.Active = true
    elseif cvRandom:GetBool() then
        ECON.Active = math.random() < (TPG.Config.economyChance or 0.30)
    else
        ECON.Active = false
    end
    SetGlobalBool("TPG_EconomyActive", ECON.Active)
    return ECON.Active
end

-- New players start with the stipend.
hook.Add("PlayerInitialSpawn", "TPG_EconomyInitMoney", function(ply)
    timer.Simple(1, function()
        if IsValid(ply) then ECON.SetMoney(ply, ECON.Config.startingMoney) end
    end)
end)

-- Initial state at map load (before the first round rolls it). Respects the
-- force convar; the random per-round roll then takes over in Rounds.Setup.
local function Latch()
    ECON.Active = cv:GetBool()
    SetGlobalBool("TPG_EconomyActive", ECON.Active)
end
hook.Add("InitPostEntity", "TPG_EconomyLatch", Latch)
Latch()  -- also latch immediately (covers Lua autorefresh during development)
