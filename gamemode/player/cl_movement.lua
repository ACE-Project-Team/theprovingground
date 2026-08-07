--[[--
    Movement prediction repair (client).

    The bug this exists for: a Juggernaut felt like it was sprinting, even
    though the server had it moving at roughly a third of normal speed.

    The cause is in sv_loadout.lua's StampSpeed, which has the full write-up:
    the ACE weapon base force-holds its owner's speed every Think from
    SWEP.NormalPlayerWalkSpeed / NormalPlayerRunSpeed, and the weapons that
    define their own Deploy (grenades, smoke, mines) never fill those in, so
    they force the SWEP table's fallback 200 walk / 400 run instead.

    That Think is in shared.lua, so it runs on the client too, inside movement
    prediction. Fixing only the server would leave the local player predicting
    against 200/400 between snapshots and getting corrected on every update --
    the position ends up right, but the movement feels wrong doing it.

    So this is the client half of the same fix: sv_loadout publishes the two
    speeds it set, and this writes them onto the client's copy of every weapon
    the player holds. No ACE file is touched, and where the base DOES snapshot
    correctly this just writes back the value already there.

    @module tpg.movement
    @realm client
]]

local lastWalk, lastRun, lastWeapon = 0, 0, nil

--[[--
    Re-applies the server's authoritative walk/run speeds to the local player
    and to every ACE weapon they are carrying, so movement prediction agrees
    with the server between snapshots.

    Reads `TPG_WalkSpeed` / `TPG_RunSpeed`, the networked ints
    `player/sv_loadout.lua` publishes. A walk speed of 0 means the server has
    not run a loadout for this player yet (spectating, or still connecting) and
    the hook does nothing, leaving engine defaults in place.

    Cheap on a normal frame: three comparisons against the last-seen values,
    then an early return. The loop over held weapons only runs when the loadout
    changes or a different weapon is drawn, which is exactly when a stale
    snapshot could be reintroduced.

    @realm client
    @function TPG_SpeedPrediction
]]
hook.Add("Think", "TPG_SpeedPrediction", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- 0 means the server hasn't run a loadout for us yet (spectator, or still
    -- connecting). Leave the engine defaults alone until it has.
    local walk = ply:GetNWInt("TPG_WalkSpeed", 0)
    if walk <= 0 then return end
    local run = ply:GetNWInt("TPG_RunSpeed", walk)

    -- The whole hook is three comparisons on a normal frame. Work only happens
    -- when the loadout changes or a different weapon comes out, which is also
    -- exactly when a stale snapshot could be reintroduced.
    local weapon = ply:GetActiveWeapon()
    if walk == lastWalk and run == lastRun and weapon == lastWeapon then return end
    lastWalk, lastRun, lastWeapon = walk, run, weapon

    -- Every ACE weapon the player holds, not just the active one: the base also
    -- restores these values on holster, so a stale field on a weapon that isn't
    -- out yet would put the wrong speed back the moment it is.
    for _, held in ipairs(ply:GetWeapons()) do
        if held.NormalPlayerWalkSpeed then
            held.NormalPlayerWalkSpeed = walk
            held.NormalPlayerRunSpeed  = run
        end
    end

    ply:SetWalkSpeed(walk)
    ply:SetRunSpeed(run)
end)
