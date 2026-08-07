--[[--
    `tpg_flag`: the single neutral Capture the Flag flag.

    Spawned by `TPG.CTF.SpawnFlags` (`gamemode/objectives/sv_ctf.lua`) once per
    round, only when the round is CTF: `flag.HomePos` is set, `:Spawn()` is
    called, and then `:SetHome(pos)` -- in that order -- before the entity is
    handed off. A team grabs it just by walking within `PICKUP_RADIUS` (100u)
    while on a team and alive; it drops on the carrier's death (or on going
    invalid/leaving their team) and auto-returns after a timeout. Getting it
    into your own safezone calls back into `TPG.CTF.OnCapture(self, carrier)`
    to score the delivery -- there is no physical base, delivery is judged by
    `TPG.Protection.IsInSafezone` (falling back to a flat-radius check against
    `TPG.State.spawns` if that module isn't loaded).

    Every reset (initial spawn, capture, drop timeout, carry timeout) re-rolls
    the home spot via `TPG.CTF.RollFlagPoint` rather than returning to a fixed
    position, so the flag can move between the KOTH point and CP points across
    a round -- unless an admin placed a custom CTF point, in which case the
    roll always returns that fixed spot.

    Visual is an AAS-style waving cloth on a pole (`cl_init.lua`), tinted by
    the carrying team (grey while neutral). `DisableDuplicator` is set, and it
    is not player-spawnable (`Spawnable = false`, `AdminOnly = true`).

    @module tpg.ent.flag
    @realm shared
]]

ENT.Type    = "anim"
ENT.Base    = "base_gmodentity"

ENT.PrintName         = "TPG Flag"
ENT.Category          = "The Proving Ground"
ENT.Spawnable         = false
ENT.AdminOnly         = true
ENT.DisableDuplicator = true

ENT.STATE_HOME    = 0   -- neutral, parked on the KOTH point
ENT.STATE_CARRIED = 1
ENT.STATE_DROPPED = 2

--- Networked vars: `FlagState` (one of `STATE_HOME`/`STATE_CARRIED`/
-- `STATE_DROPPED`), `PossessTeam` (0 when nobody holds it), `Carrier` (the
-- carrying `Player` entity, or NULL) and `CarryEnd` (a `CurTime()` deadline
-- the carry auto-returns at, or 0 when not carried -- this is what
-- `cl_hud_ctf.lua`'s carry-timer bar counts down against).
-- @realm shared
function ENT:SetupDataTables()
    self:NetworkVar("Int",    0, "FlagState")    -- STATE_*
    self:NetworkVar("Int",    1, "PossessTeam")  -- team currently carrying (0 = none)
    self:NetworkVar("Entity", 0, "Carrier")
    self:NetworkVar("Float",  0, "CarryEnd")     -- CurTime() the carry auto-returns (0 = not carried)
end
