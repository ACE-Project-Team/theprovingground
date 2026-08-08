--[[--
    The repair torch: a spawn-only tool for economy rounds.

    ACE ships a welding torch (`weapon_ace_torch`) that repairs damaged armour.
    TPG hands it out under two conditions at once -- the player is standing in
    their own safezone, and the round is running the per-player economy -- and
    takes it away the moment either stops being true.

    WHY THOSE TWO CONDITIONS.

    Safezone, because a torch in the field is a second health bar: a crew that
    can weld between shots wins a fight it lost. Inside the safezone there is
    nobody to fight, so repairing there is just the pause between fights, which
    is the thing worth having.

    Economy, because that is the mode where a destroyed vehicle is a real loss.
    A team-budget round refunds what you lose, so limping home to weld saves you
    nothing you would not get by dying and pasting a fresh one -- the torch would
    be a slower version of respawning. In an economy round the vehicle you drove
    out is money you already spent and will not get back, so repairing it instead
    of replacing it is a decision, and this is what makes it available to make.

    Driven from the safezone loop in `sv_protection.lua` via @{TPG.Repair.Update}
    rather than a `Think` of its own: that loop already knows, this frame, who is
    alive, on a team, and inside their zone, and re-deriving all three here would
    be the same work done twice.

    @module tpg.repair
    @realm server
]]

TPG.Repair = TPG.Repair or {}

-- ACE's own welding torch. Not read from the weapon config: this is not a
-- loadout pick and it is not discovered -- it is one specific tool, handed out
-- by a rule, and a server without it simply has no repair torch.
-- Nothing keeps it out of the loadout menu explicitly and nothing needs to:
-- ACE files it as Slot 0, and discovery only buckets slots 1-4, so it is not a
-- pick anyone can make. If ACE ever reslots it, it wants an Exclude entry --
-- carrying a torch as your sidearm is the exact thing this file is shaped to
-- prevent.
local TORCH = "weapon_ace_torch"

--[[--
    Give or take the repair torch for one player, for this frame.

    Safe to call every frame: both branches check what the player is already
    holding first, so a player standing still in their safezone is not handed a
    new torch sixty-six times a second.

    A player who had the torch out when they leave the zone loses it mid-swing
    and the engine picks another weapon for them. That is deliberate and is the
    whole rule -- a grace period would be a window to weld in, which is what the
    safezone condition exists to prevent.

    @tparam Player ply
    @tparam boolean inSafezone Whether they are in their OWN safezone this frame.
    @realm server
]]
function TPG.Repair.Update(ply, inSafezone)
    local wanted = inSafezone and TPG.Gear and TPG.Gear.EconomyActive
        and TPG.Gear.EconomyActive() or false

    if wanted then
        if not ply:HasWeapon(TORCH) then
            ply:Give(TORCH)
        end
    elseif ply:HasWeapon(TORCH) then
        ply:StripWeapon(TORCH)
    end
end
