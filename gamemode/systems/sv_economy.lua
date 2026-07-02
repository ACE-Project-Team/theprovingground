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

    killRewardBase    = 250,    -- flat reward per enemy kill
    killRewardVehFrac = 0.05,   -- + this fraction of the victim's vehicle value
    killRewardMax     = 2500,   -- per-kill clamp

    teamkillPenalty   = 400,    -- deducted from a player's wallet for killing a teammate

    -- Stock spawn-menu vehicles (jeep, airboat, and any add-on cars) aren't ACE
    -- contraptions, so they have no point value and would otherwise be a free
    -- ride around the economy. Charge a flat fee to field one; 0 disables it.
    stockVehicleCost  = 1500,

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

-- Deduct money (clamped at zero by SetMoney). No-op unless the economy is live.
function ECON.Penalize(ply, amount, _reason)
    if not ECON.Active or not IsValid(ply) or (amount or 0) <= 0 then return end
    ECON.SetMoney(ply, ECON.GetMoney(ply) - amount)
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
    if attacker == victim then return end

    -- Team kills: no reward, and a small wallet penalty so it stings a little.
    if attacker:Team() == victim:Team() then
        local penalty = ECON.Config.teamkillPenalty or 0
        if penalty > 0 then
            ECON.Penalize(attacker, penalty, "teamkill")
            TPG.Util.ChatMessage(attacker, "[TPG] Team kill: -" .. penalty ..
                " pts. Balance: " .. ECON.GetMoney(attacker), Color(255, 120, 120))
        end
        return
    end

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

-- ── Stock (non-ACE) vehicle purchases ──────────────────────────────────────
-- These stock vehicles carry no ACE point value, so under the economy they'd be
-- a free way to get around. Charge a flat fee, and if the buyer can't afford it,
-- remove the vehicle. Seats (prop_vehicle_prisoner_pod) are deliberately absent:
-- they're build components, not transport.
local STOCK_VEHICLE_CLASSES = {
    ["prop_vehicle_jeep"]    = true,
    ["prop_vehicle_airboat"] = true,
    ["prop_vehicle_apc"]     = true,
}

hook.Add("PlayerSpawnedVehicle", "TPG_EconomyStockVehicle", function(ply, ent)
    if not ECON.Active then return end
    if not IsValid(ply) or not IsValid(ent) then return end

    local cost = ECON.Config.stockVehicleCost or 0
    if cost <= 0 then return end
    if not STOCK_VEHICLE_CLASSES[ent:GetClass()] then return end

    -- Defer a frame: the safezone restriction (sv_protection) may remove the
    -- vehicle this same frame, and ACE point totals settle on a timer.Simple(0).
    timer.Simple(0, function()
        if not IsValid(ply) or not IsValid(ent) then return end

        -- Part of an actual ACE contraption? Then it's billed through the build,
        -- not as a stock vehicle -- leave it alone.
        if ent.GetContraption then
            local con = ent:GetContraption()
            if con and (con.ACEPoints or 0) > 0 then return end
        end

        if not ECON.Charge(ply, cost) then
            ent:Remove()
            TPG.Util.ChatMessage(ply, "[TPG] Not enough points for a vehicle (costs " ..
                cost .. ", you have " .. ECON.GetMoney(ply) .. ").", Color(255, 0, 0))
            return
        end

        TPG.Util.ChatMessage(ply, "[TPG] Vehicle purchased for " .. cost ..
            " pts. Balance: " .. ECON.GetMoney(ply), Color(0, 255, 0))
    end)
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
