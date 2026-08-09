--[[--
    Per-player economy (BETA): a personal wallet that replaces the shared team point budget.

    Each player has a personal wallet of points ("money"), earned through
    objective hold, kills, and passive income, and spent on vehicles as a
    TRUE PURCHASE -- a destroyed tank is NOT refunded. While active this
    REPLACES the shared per-team point budget (the team weight/prop limits
    from @{tpg.proptracking} stay in force regardless, as physical
    guardrails -- the economy only replaces the POINTS side of the budget).

    **Secondary-mode activation.** The economy is not always on. Each round it
    has a `TPG.Config.economyChance` chance to switch on (gated by
    `tpg_economy_random`), or an admin can force it always-on
    (`tpg_economy_enabled`). The active state is rolled in `TPG.Rounds.Setup`
    via @{ECON.RollForRound} BEFORE the round state resets, so
    @{ECON.OnRoundReset} sees the correct value when it decides whether to
    reset wallets; it is then announced so players know the round is
    per-player. `TPG_EconomyActive` is a `SetGlobalBool`, readable client-side.

    **Where the money comes from.** A `Think` hook pays passive income plus
    per-objective hold income every `passiveInterval` seconds, gated on the
    round actually being active (so nobody banks money during the
    wait-for-players window). `PlayerDeath` pays a kill reward scaled by the
    victim's fielded vehicle value, with anti-farm carve-outs for safezone
    kills and spawn-protected victims, and separately penalizes a team-killer.
    A comeback multiplier (`IncomeMult`) applies to every income source: the
    team currently behind on tickets earns `losingIncomeMult`, and the
    underdog system's own multiplier (@{tpg.underdog}) can raise that further
    -- the two take the MAX of each other rather than stacking, so underdog's
    "+25% income" announcement never understates what a losing team was
    already earning from this multiplier alone.

    **Where the money goes.** Vehicle purchases are billed in
    `sv_duplication.lua`'s dupe-paste flow, which calls
    @{ECON.GetContraptionCost} to price the build and @{ECON.Charge} to pay
    for it -- that is also the ONLY place `ECON.Charge` is currently called
    from for ACE contraptions. Stock (non-ACE) vehicles -- jeep, airboat, APC
    -- carry no ACE point value and would otherwise be a free ride around the
    economy, so `PlayerSpawnedVehicle` charges a flat `stockVehicleCost` for
    them directly, deferred a frame so the safezone system gets first refusal
    and ACE's point totals have a chance to settle. Loadout gear
    (`sv_gear.lua`) and CTF flag deliveries (`tpg.ctf`) also spend through
    @{ECON.Reward}/@{ECON.Charge}.

    **Post-spawn re-billing is implemented but OFF by default**
    (`tpg_economy_rebill`, 0). With it off, a vehicle costs what it cost at
    spawn and every later edit is free; the machinery below still tracks what
    was paid (`con.TPG_BilledPoints`) and still runs a settle pass after every
    edit, but the actual charge is skipped. It is off because charging for a
    "modification" means trusting ACE's point total the instant a hook fires,
    and a partial rebuild reads as a modification nobody made -- that race is
    now guarded (see `PointsSettled`), but combat itself still moves the
    number (shooting a component off a tank splits the contraption and drops
    its total), which is a second class of phantom "modification" this file
    does not yet tell apart from a deliberate edit. Re-enable only once that
    is solved.

    **Reconnect behaviour is asymmetric by design.** A brand new player gets
    `startingMoney`. A player who disconnects and rejoins gets back the exact
    wallet they left with (`pState.carriedMoney`, stashed by
    `core/sv_gamestate.lua`) rather than a fresh stipend -- otherwise spending
    down to zero and reconnecting would be a free top-up. This is the opposite
    of `sv_gear.lua`'s cooldowns, which also survive a reconnect but for the
    opposite reason (to stop a cooldown from being cleared by leaving).

    **Per-player state fields** (on `TPG.State.GetPlayer(ply)`, i.e. `pState`):
    `money` (current wallet, mirrored to the client via `NWInt TPG_Money`),
    `carriedMoney` (set on disconnect elsewhere, consumed once on the next
    `PlayerInitialSpawn` and then cleared).

    **Per-contraption state fields:** `con.TPG_BilledPoints` (running total
    actually paid, the number refunds are computed from), `con.TPG_RebillPending`
    /`TPG_RebillDeadline` (settle-loop bookkeeping, see `ArmSettle`),
    `con.TPG_BaselinePending` (the just-spawned baseline hasn't seen a settled
    point total yet, so the next settle ADOPTS the number instead of billing
    the difference).

    **What breaks if this file does not load:** `TPG.Economy` stays nil, so
    every `TPG.Economy and TPG.Economy.X` guard elsewhere (duplication, gear,
    CTF, underdog) short-circuits to the shared team-budget behaviour. Nothing
    crashes, but every round behaves as if the economy can never roll on,
    since `ECON.RollForRound` itself would not exist to be called.

    @module tpg.economy
    @realm server
]]

TPG.Economy = TPG.Economy or {}
local ECON = TPG.Economy

-- ── Tunables (need play-testing; reference: ACE's reworked pricing puts a
-- good modern tank at ~6,000 pts) ──────────────────────────────────────────
ECON.Config = {
    startingMoney     = 3000,   -- half a good tank (~6k): field a light/medium now, earn the heavy
    maxMoney          = 60000,  -- wallet cap

    losingIncomeMult  = 1.5,    -- all income x1.5 for whichever team is behind on tickets

    -- Passive and kill income were trimmed 10% (150 -> 135, 400 -> 360, and the
    -- kill clamp with them) because wallets were outrunning what there is to
    -- spend them on. Objective hold income is deliberately NOT cut: it's the
    -- one source that requires standing somewhere contested, and shaving it
    -- would push players further toward farming kills from safety, which is the
    -- opposite of what the trim is for.
    passiveIncome     = 135,    -- granted every passiveInterval seconds
    passiveInterval   = 10,

    captureHoldIncome = 100,    -- per interval, per objective you are standing on
    captureRadiusM    = 30,     -- metres from an objective to earn hold income

    killRewardBase    = 360,    -- flat reward per enemy kill
    killRewardVehFrac = 0.072,  -- + this fraction of the victim's vehicle value
    killRewardMax     = 3600,   -- per-kill clamp

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

-- Post-spawn re-billing. OFF for now: a vehicle costs what it cost when you
-- spawned it, and modifying it afterwards is free. The machinery below is left
-- intact and still tracks what was paid; only the charging is gated.
--
-- It's off because charging for a "modification" means trusting ACE's point
-- total the moment a hook fires, and a partial rebuild reads as a modification
-- nobody made. That's now guarded, but combat itself still moves the number --
-- shooting a component off a tank splits the contraption and drops its total --
-- so there is a second class of phantom modification that isn't solved yet.
-- Re-enable once battle damage can be told apart from a player edit.
local cvRebill = CreateConVar("tpg_economy_rebill", "0",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Charge for post-spawn vehicle modifications. 0 = purchase at spawn only.")

-- ── Budget-change feed ──────────────────────────────────────────────────────
-- Tells the owning client "your budget just changed by N, because <reason>", so
-- the economy HUD can float a little +N / -N with a label. Purely cosmetic.
util.AddNetworkString("TPG_MoneyDelta")

--- Tell a client their wallet changed, for the HUD's floating +N/-N popup.
-- Purely cosmetic net message; does not itself change `pState.money`. No-op
-- for an invalid player or a zero delta.
-- @tparam Player ply
-- @tparam number delta Signed; rounded before sending.
-- @tparam[opt=""] string reason Short label the HUD displays with the popup.
-- @realm server
function ECON.Notify(ply, delta, reason)
    if not IsValid(ply) or (delta or 0) == 0 then return end
    net.Start("TPG_MoneyDelta")
        net.WriteInt(math.Round(delta), 20)   -- signed; wallet cap fits in 20 bits
        net.WriteString(reason or "")
    net.Send(ply)
end

-- ── Wallet helpers ────────────────────────────────────────────────────────

--- A player's current wallet balance.
-- @tparam Player ply
-- @treturn number 0 for an invalid player or one with no recorded balance.
-- @realm server
function ECON.GetMoney(ply)
    if not IsValid(ply) then return 0 end
    return TPG.State.GetPlayer(ply).money or 0
end

--- Set a player's wallet to an exact amount, clamped to `[0, ECON.Config.maxMoney]`.
-- Also mirrors the value to the client via `NWInt TPG_Money`. Every other
-- wallet-changing function in this file goes through this, so it is the one
-- place the clamp and the network sync both live.
-- @tparam Player ply
-- @tparam number amount
-- @realm server
function ECON.SetMoney(ply, amount)
    if not IsValid(ply) then return end
    local pState = TPG.State.GetPlayer(ply)
    pState.money = math.Clamp(math.floor(amount), 0, ECON.Config.maxMoney)
    ply:SetNWInt("TPG_Money", pState.money)
end

-- Comeback income multiplier. ANY team currently behind on tickets earns
-- losingIncomeMult on all income; the (hard-losing) underdog state keeps its
-- own configured multiplier. The two do NOT stack -- the better one applies --
-- so underdog's "+25% income" announcement never understates what a losing
-- team was already earning.
local function IncomeMult(ply)
    local mult = 1
    local teamId = ply:Team()
    local enemy  = TPG.GetEnemyTeam and TPG.GetEnemyTeam(teamId)
    if enemy and TPG.Util.IsOnTeam(ply) then
        local own   = (TPG.State.scores and TPG.State.scores[teamId]) or 0
        local their = (TPG.State.scores and TPG.State.scores[enemy]) or 0
        if own < their then mult = ECON.Config.losingIncomeMult or 1.5 end
    end
    if TPG.Underdog and TPG.Underdog.GetIncomeMult then
        mult = math.max(mult, TPG.Underdog.GetIncomeMult(ply))
    end
    return mult
end

--- Pay a player income, scaled by the comeback/underdog multiplier.
-- No-op unless `ECON.Active`, so callers do not need to guard every reward
-- site themselves -- this is what makes it safe for e.g. `TPG.CTF.OnCapture`
-- to always call it regardless of which mode the round is in.
-- @tparam Player ply
-- @tparam number amount Base amount before the comeback multiplier.
-- @tparam ?string _reason Unused; accepted for call-site symmetry with @{ECON.Charge}.
-- @realm server
function ECON.Reward(ply, amount, _reason)
    if not ECON.Active or not IsValid(ply) or (amount or 0) <= 0 then return end
    -- Losing/underdog teams earn faster (all income sources).
    amount = amount * IncomeMult(ply)
    ECON.SetMoney(ply, ECON.GetMoney(ply) + amount)
end

--- Deduct money as a penalty (clamped at zero by @{ECON.SetMoney}).
-- No-op unless the economy is live, same as @{ECON.Reward}.
-- @tparam Player ply
-- @tparam number amount
-- @tparam ?string _reason Unused; accepted for call-site symmetry with @{ECON.Charge}.
-- @realm server
function ECON.Penalize(ply, amount, _reason)
    if not ECON.Active or not IsValid(ply) or (amount or 0) <= 0 then return end
    ECON.SetMoney(ply, ECON.GetMoney(ply) - amount)
end

--- Can this player afford a cost, right now.
-- @tparam Player ply
-- @tparam number cost
-- @treturn boolean
-- @realm server
function ECON.CanAfford(ply, cost)
    return ECON.GetMoney(ply) >= math.floor(cost or 0)
end

--[[--
    Deduct a cost if the player can afford it, and notify them of the charge.

    Unlike @{ECON.Reward}/@{ECON.Penalize}, this does NOT check `ECON.Active`
    itself -- every current call site (dupe purchases, gear, stock vehicles)
    already gates the call on the economy being active, but a future caller
    that forgets to check `ECON.Active` first would still successfully charge
    the player's wallet.

    @tparam Player ply
    @tparam number cost
    @tparam[opt="purchase"] string reason Passed through to @{ECON.Notify}.
    @treturn boolean True if the charge succeeded; false (no state change) if
     the player is invalid or can't afford it.
    @realm server
]]
function ECON.Charge(ply, cost, reason)
    if not IsValid(ply) then return false end
    cost = math.floor(cost or 0)
    if ECON.GetMoney(ply) < cost then return false end
    ECON.SetMoney(ply, ECON.GetMoney(ply) - cost)
    ECON.Notify(ply, -cost, reason or "purchase")
    return true
end

--- Vehicle cost: sum of unique contraptions' ACE points across a set of entities.
-- Forces each unique contraption to bring its point total up to date first
-- (via `ACE_EnsureContraptionPoints`), so a just-pasted build is priced
-- correctly even before anything else has read its points.
-- @tparam table entList Entities from a paste or spawn.
-- @treturn number
-- @realm server
function ECON.GetContraptionCost(entList)
    local seen, cost = {}, 0
    for _, ent in pairs(entList) do
        if not IsValid(ent) or not ent.CFW_GetContraption then continue end
        local con = ent:CFW_GetContraption()
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
-- Ticks every `passiveInterval` seconds (a manual CurTime gate inside Think,
-- not a timer.Create) and pays every alive, teamed player passive income plus
-- hold income for each objective within `captureRadiusM`. The two are
-- aggregated into one @{ECON.Notify} call per player per tick so the HUD
-- floats a single "+N income" instead of stacked popups.
local lastTick = 0
hook.Add("Think", "TPG_EconomyIncome", function()
    if not ECON.Active then return end
    -- No income before the round actually starts (wait-for-players window) --
    -- otherwise fast loaders bank money the late joiners never got.
    if not TPG.State.round.active then return end
    if CurTime() - lastTick < ECON.Config.passiveInterval then return end
    lastTick = CurTime()

    local capRadius  = TPG.Util.MetersToUnits(ECON.Config.captureRadiusM)
    local objectives = TPG.State.objectives or {}

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        if not TPG.Util.IsOnTeam(ply) then continue end

        -- Aggregate this tick's passive + per-objective hold into one number so
        -- the HUD floats a single "+N income" instead of three stacked popups.
        local before = ECON.GetMoney(ply)
        ECON.Reward(ply, ECON.Config.passiveIncome, "passive")

        local held = 0
        for _, obj in pairs(objectives) do
            if IsValid(obj) and ply:GetPos():Distance(obj:GetPos()) < capRadius then
                ECON.Reward(ply, ECON.Config.captureHoldIncome, "hold")
                held = held + 1
            end
        end

        -- Report the ACTUAL gain (after the underdog multiplier / wallet cap).
        ECON.Notify(ply, ECON.GetMoney(ply) - before, held > 0 and "hold" or "income")
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
            local before = ECON.GetMoney(attacker)
            ECON.Penalize(attacker, penalty, "teamkill")
            ECON.Notify(attacker, ECON.GetMoney(attacker) - before, "teamkill")
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
    local before   = ECON.GetMoney(attacker)
    ECON.Reward(attacker, reward, "kill")
    ECON.Notify(attacker, ECON.GetMoney(attacker) - before, "kill")
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
    if not TPG.Util.IsOnTeam(ply) then return end   -- spectators sandbox for free

    local cost = ECON.Config.stockVehicleCost or 0
    if cost <= 0 then return end
    if not STOCK_VEHICLE_CLASSES[ent:GetClass()] then return end

    -- Defer a frame: the safezone restriction (sv_protection) may remove the
    -- vehicle this same frame, and ACE point totals settle on a timer.Simple(0).
    timer.Simple(0, function()
        if not IsValid(ply) or not IsValid(ent) then return end

        -- Part of an actual ACE contraption? Then it's billed through the build,
        -- not as a stock vehicle -- leave it alone.
        if ent.CFW_GetContraption then
            local con = ent:CFW_GetContraption()
            if con and (con.ACEPoints or 0) > 0 then return end
        end

        if not ECON.Charge(ply, cost, "vehicle") then
            ent:Remove()
            TPG.Util.ChatMessage(ply, "[TPG] Not enough points for a vehicle (costs " ..
                cost .. ", you have " .. ECON.GetMoney(ply) .. ").", Color(255, 0, 0))
            return
        end

        TPG.Util.ChatMessage(ply, "[TPG] Vehicle purchased for " .. cost ..
            " pts. Balance: " .. ECON.GetMoney(ply), Color(0, 255, 0))
    end)
end)

-- ── Post-spawn re-billing ───────────────────────────────────────────────────
-- ACE's point system recalculates a contraption's cost whenever its owner edits
-- it after spawn (bolts on armor, links ammo/GBUs, swaps a gun). The INITIAL
-- purchase is billed once by the dupe-finish flow above; this closes the loophole
-- where you field a cheap chassis, pay little, then upgrade it for free.
--
-- Each freshly spawned build is stamped with the cost already paid
-- (con.TPG_BilledPoints). ACE fires ACE_OnContraptionPointsRecalculated after any
-- rebuild; when the fresh total rises above the billed baseline we charge the
-- difference (economy) and always report it (both modes). A drop is not refunded
-- -- a vehicle is a true purchase -- we just lower the baseline so re-adding the
-- same part bills again. Scratch-built (non-dupe) contraptions are never stamped,
-- matching the existing economy which only charges dupes and stock vehicles.
local REBILL_DEBOUNCE  = 0.75   -- edits fire a burst of recalcs; settle to one
local REBILL_MIN_DELTA = 25     -- ignore display-scale / rounding jitter
local REBILL_MAX_WAIT  = 8      -- settle attempts before giving up (~6s)

-- Is this contraption's point total a finished number?
--
-- ACE rebuilds armor and non-armor independently and fires the recalc hook after
-- EITHER half lands, so con.ACEPoints is routinely a partial total mid-burst --
-- a rebuild that touched only non-armor reports it while ACEArmorPoints is still
-- 0, and vice versa. Billing off one of those is how a 3k vehicle briefly reads
-- 20k and back. Only a contraption with nothing left dirty is a real number.
local function PointsSettled(con)
    if not istable(con) then return false end
    if not con.ACEArmorCalculated then return false end
    return not (con.ACEPointsDirty or con.ACEArmorDirty or con.ACENonArmorDirty)
end

local SettleRebill   -- defined below; ArmSettle drives it

-- Wait for ACE to finish, then settle exactly once.
--
-- Deliberately never calls EnsureContraptionPoints: forcing a rebuild from a
-- timer is what turns one edit into a cascade, and every forced rebuild fires
-- the very hook that scheduled us. We pull on ACE's hook and let it tell us when
-- it's done. If it never settles we give up rather than spin.
local function ArmSettle(con, attempt)
    timer.Simple(REBILL_DEBOUNCE, function()
        if not istable(con) or con.ACERemoving then
            if istable(con) then con.TPG_RebillPending = nil end
            return
        end

        local burstOver = CurTime() >= (con.TPG_RebillDeadline or 0)
        if (not burstOver or not PointsSettled(con)) and attempt < REBILL_MAX_WAIT then
            ArmSettle(con, attempt + 1)
            return
        end

        con.TPG_RebillPending = nil
        if PointsSettled(con) then SettleRebill(con) end
    end)
end

--[[--
    Stamp the price already paid onto each unique contraption in a spawned build.

    Called from `sv_duplication.lua` after a paste passes every limit check,
    in BOTH the economy and the shared-budget mode -- `con.TPG_BilledPoints`
    is what @{ECON.RefundActivePurchases} and the re-bill settle logic key
    off, regardless of which budget mode charged for the purchase (or
    whether either did).

    If the build has not settled a real point total yet (the common case for
    a build that just landed), the stamped baseline is marked provisional
    (`con.TPG_BaselinePending`) so the first settle ADOPTS the real number
    instead of billing the difference between it and a partial reading -- see
    `SettleRebill`. Without that, a brand-new vehicle could announce itself
    as "modified" seconds after spawning, for an edit nobody made.

    @tparam table entList Entities from the paste.
    @realm server
]]
function ECON.MarkContraptionsBilled(entList)
    local seen = {}
    for _, ent in pairs(entList) do
        if IsValid(ent) and ent.CFW_GetContraption then
            local con = ent:CFW_GetContraption()
            if con and not seen[con] then
                seen[con] = true
                if _G.ACE_EnsureContraptionPoints then
                    ACE_EnsureContraptionPoints(con, con.GetACEBaseplate and con:GetACEBaseplate() or nil)
                end
                con.TPG_BilledPoints = math.floor(con.ACEPoints or 0)

                -- A freshly pasted build usually hasn't settled yet. Stamping a
                -- partial total as the baseline and then charging the difference
                -- once the real one lands is what made a brand new vehicle
                -- announce itself as "modified" seconds after spawning. Mark the
                -- baseline provisional so the first settled total replaces it
                -- instead of billing against it.
                if not PointsSettled(con) then
                    con.TPG_BaselinePending = true
                    con.TPG_RebillDeadline  = CurTime() + REBILL_DEBOUNCE
                    if not con.TPG_RebillPending then
                        con.TPG_RebillPending = true
                        ArmSettle(con, 0)
                    end
                end
            end
        end
    end
end

-- Resolve the human owner of a contraption via any of its entities.
local function ContraptionOwner(con)
    if not con or not con.ents then return nil end
    for ent in pairs(con.ents) do
        if IsValid(ent) and ent.CPPIGetOwner then
            local owner = ent:CPPIGetOwner()
            if IsValid(owner) and owner:IsPlayer() then return owner end
        end
    end
    return nil
end

-- Settle exactly one rebill for a contraption whose points have finished
-- moving. Assigns to the `local SettleRebill` declared above ArmSettle --
-- this looks like a bare global function statement, but because that local
-- is in scope at this point in the same chunk, Lua's `function name(...)`
-- sugar resolves `name` to the existing local rather than creating a global.
function SettleRebill(con)
    if not istable(con) or con.ACERemoving then return end
    if con.TPG_BilledPoints == nil then return end

    local newTotal = math.floor(con.ACEPoints or 0)

    -- The baseline stamped at spawn was provisional; this is the first real
    -- number this build has ever had. Adopt it as the price paid rather than
    -- charging for the difference between it and a partial reading.
    if con.TPG_BaselinePending then
        con.TPG_BaselinePending = nil
        con.TPG_BilledPoints    = newTotal
        return
    end

    -- Re-billing off: the vehicle costs what it cost at spawn. Note this leaves
    -- TPG_BilledPoints where it is on purpose -- it records what the player
    -- actually paid, and RefundActivePurchases hands back exactly that, so
    -- letting a now-free upgrade raise the baseline would refund money that was
    -- never spent.
    if not cvRebill:GetBool() then return end

    local delta = newTotal - con.TPG_BilledPoints
    if math.abs(delta) < REBILL_MIN_DELTA then return end

    local owner = ContraptionOwner(con)
    if not IsValid(owner) or not TPG.Util.IsOnTeam(owner) then
        con.TPG_BilledPoints = newTotal   -- no teamed owner to bill; keep current
        return
    end

    con.TPG_BilledPoints = newTotal

    if delta > 0 then
        if ECON.Active then
            local pay = math.min(delta, ECON.GetMoney(owner))
            if pay > 0 then
                ECON.SetMoney(owner, ECON.GetMoney(owner) - pay)
                ECON.Notify(owner, -pay, "modify")
            end
            if pay < delta then
                TPG.Util.ChatMessage(owner, "[TPG] Modifications cost " .. delta ..
                    " pts but you could only pay " .. pay .. ". Balance: " ..
                    ECON.GetMoney(owner) .. ".", Color(255, 120, 120))
            else
                TPG.Util.ChatMessage(owner, "[TPG] Vehicle modified: -" .. delta ..
                    " pts. Now worth " .. newTotal .. ". Balance: " ..
                    ECON.GetMoney(owner) .. ".", Color(255, 200, 0))
            end
        else
            TPG.Util.ChatMessage(owner, "[TPG] Vehicle modified: now worth " ..
                newTotal .. " pts (+" .. delta .. ").", Color(255, 200, 0))
        end
    else
        TPG.Util.ChatMessage(owner, "[TPG] Vehicle modified: now worth " .. newTotal ..
            " pts (" .. delta .. (ECON.Active and ", no refund" or "") .. ").",
            Color(150, 220, 255))
    end
end

hook.Add("ACE_OnContraptionPointsRecalculated", "TPG_RebillModifiedVehicle", function(con, change)
    if not istable(con) or con.ACERemoving then return end
    if con.TPG_BilledPoints == nil then return end   -- scratch build; nothing to re-bill

    -- With re-billing off the only reason to still settle is to finish a
    -- provisional baseline from spawn, so the recorded purchase price (and the
    -- refund built on it) is the real number rather than a partial one.
    if not cvRebill:GetBool() and not con.TPG_BaselinePending then return end

    -- No early-out on the delta here. A partial recalc can land within
    -- REBILL_MIN_DELTA of the baseline purely by coincidence, and skipping it
    -- would strand the burst without a settle.

    -- Slide the deadline on every recalc so one edit settles once AFTER the
    -- burst finishes. The old code armed a fixed timer on the FIRST recalc and
    -- ignored every later one, so a burst longer than the debounce got billed
    -- mid-flight, then billed again on the next burst -- three messages and
    -- three charges for a single edit, with only the last figure correct.
    con.TPG_RebillDeadline = CurTime() + REBILL_DEBOUNCE
    if con.TPG_RebillPending then return end
    con.TPG_RebillPending = true
    ArmSettle(con, 0)
end)

-- ── Refunds ────────────────────────────────────────────────────────────────

--[[--
    Hand a player back everything they've paid into the vehicles they still have standing, and remove those vehicles.

    This is deliberately NOT a general refund -- a destroyed tank stays a true
    purchase, that's the whole model. It exists for the one case where the
    game moved the player instead of the player moving: a scramble drops you
    on the other side of the map with your build parked in what is now enemy
    spawn. Removing the vehicle as part of the refund is what keeps it a
    relocation rather than a way to end up with the money and the tank.

    `con.TPG_BilledPoints` is the running total actually paid for that
    contraption (initial purchase plus any post-spawn modifications billed by
    `SettleRebill`), so it's exactly the right number to give back. No-op if
    the economy isn't active.

    @tparam Player ply
    @treturn number Total refunded; 0 if the economy is off, the player is
     invalid, or they own nothing billed.
    @realm server
]]
function ECON.RefundActivePurchases(ply)
    if not ECON.Active or not IsValid(ply) then return 0 end
    if not (TPG.ACE and TPG.ACE.GetPlayerContraptions) then return 0 end

    local refund, doomed = 0, {}
    for _, con in ipairs(TPG.ACE.GetPlayerContraptions(ply)) do
        local billed = con.TPG_BilledPoints
        if billed and billed > 0 then
            refund = billed + refund
            con.TPG_BilledPoints = nil
            -- Collect first: removing entities mutates con.ents underneath us.
            for ent in pairs(con.ents or {}) do
                doomed[#doomed + 1] = ent
            end
        end
    end

    for _, ent in ipairs(doomed) do
        if IsValid(ent) then ent:Remove() end
    end

    if refund > 0 then
        ECON.SetMoney(ply, ECON.GetMoney(ply) + refund)
        ECON.Notify(ply, refund, "refund")
    end
    return refund
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

--- Reset every connected player's wallet to `ECON.Config.startingMoney`.
-- Unconditional -- does not check `ECON.Active` or `resetEachRound` itself;
-- see @{ECON.OnRoundReset} for the gated caller.
-- @realm server
function ECON.ResetWallets()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then ECON.SetMoney(ply, ECON.Config.startingMoney) end
    end
end

--- Reset wallets for a new round, if the economy is active and configured to.
-- Called from `TPG.State.ResetRound()`. Relies on @{ECON.RollForRound} having
-- already set `ECON.Active` for this round before this runs.
-- @realm server
function ECON.OnRoundReset()
    if ECON.Active and ECON.Config.resetEachRound then ECON.ResetWallets() end
end

--[[--
    Per-round activation roll: is the economy live this round.

    The economy behaves like a secondary game mode: forced always-on by
    `tpg_economy_enabled`, otherwise a `TPG.Config.economyChance` chance each
    round (`tpg_economy_random`), otherwise off. Sets `ECON.Active` and
    mirrors it to clients via `SetGlobalBool("TPG_EconomyActive", ...)`.

    Call this from `TPG.Rounds.Setup` BEFORE `ResetRound`, so
    @{ECON.OnRoundReset} sees the correct state when it decides whether to
    reset wallets.

    @treturn boolean The rolled `ECON.Active` value.
    @realm server
]]
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

-- New players start with the stipend -- but someone RE-joining gets the wallet
-- they left with (core/sv_gamestate.lua stashes it), otherwise spending down to
-- zero and reconnecting would be a free top-up. Runs unconditionally, whether
-- or not the economy is currently active this round, since the wallet needs a
-- sane value ready for whenever it next matters.
hook.Add("PlayerInitialSpawn", "TPG_EconomyInitMoney", function(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        local pState = TPG.State.GetPlayer(ply)
        local carried = pState.carriedMoney
        pState.carriedMoney = nil
        ECON.SetMoney(ply, carried or ECON.Config.startingMoney)
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
