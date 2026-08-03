--[[
    Movement prediction repair (client)

    The bug this exists for: a Juggernaut felt like it was sprinting, even
    though the server had it moving at roughly a third of normal speed.

    Movement is predicted on the client and simulated again on the server, and
    both realms have to agree on the player's walk/run speed or the two
    disagree about where the player ended up. The ACE weapon base takes a
    snapshot of its owner's speed when it deploys and then force-holds the
    player to it every Think:

        NormalPlayerWalkSpeed = owner:GetWalkSpeed()      -- init.lua, Deploy
        owner:SetWalkSpeed(NormalPlayerWalkSpeed * mul)   -- shared.lua, Think

    Deploy lives in the weapon's init.lua, which is SERVER ONLY. Think is in
    shared.lua and runs on both. So the client's copy of the weapon never takes
    a snapshot and keeps the SWEP table's fallbacks -- a flat 200 walk / 400 run
    -- and then pins the local player to those every frame, overwriting the real
    speed the server sent down.

    For most loadouts the two numbers are close enough that nobody notices. For
    a Juggernaut the server says 120/178 and the client predicts 200/400, and
    the player spends the whole life outrunning their own position.

    The fix is entirely on our side of the fence: sv_loadout publishes the two
    speeds it set, and this hands them to the client's copy of the weapon so
    ACE's own Think arrives at the server's answer instead of its fallback. No
    ACE file is touched, and if the addon ever starts snapshotting client-side
    this simply writes the value that's already there.
]]

local lastWalk, lastRun, lastWeapon = 0, 0, nil

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
