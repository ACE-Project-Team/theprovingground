--[[
    Spawn-time prop ownership claiming (the AdvDupe2 safezone hole).

    AdvDupe2 fires PlayerSpawnedProp for every pasted prop_physics, but
    NadmodPP claims props via cleanup.Add - which the duplicator path never
    calls - so a pasted plate stayed ownerless until touched, and ACE's
    DefaultCanDamage let shells hit it inside the safezone. These cases pin
    the TPG_*Claim hooks: a player-spawned entity with no CPPI owner is
    claimed to its spawner at creation.

    Loads the one server file and drives its registered hooks by hand.
]]

local gmod = expect.load.gmod

-- Fake entity: just the CPPI surface the claim hook touches.
local function fakeEnt(owner)
    local e = {
        IsValid   = function() return true end,
        claimedTo = nil,
    }
    e.CPPIGetOwner = function() return owner end
    e.CPPISetOwner = function(_, ply) e.claimedTo = ply end
    return e
end

local function reset()
    expect.load.dofile(expect.root .. "/gamemode/player/sv_protection.lua")
end

-- ── cases ───────────────────────────────────────────────────────────────────

describe("protection: spawn-time prop claiming")

it("claims an unowned pasted prop to its spawner", function()
    reset()
    local ply = gmod.player(TEAM_GREEN, {})
    local ent = fakeEnt(nil)

    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/hunter/plates/plate.mdl", ent)
    expect.eq(ent.claimedTo, ply, "unowned prop should be claimed to the spawner")
end)

it("does not steal a prop that already has an owner", function()
    reset()
    local ply  = gmod.player(TEAM_GREEN, {})
    local boss = gmod.player(TEAM_RED, {})
    local ent  = fakeEnt(boss)

    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/hunter/plates/plate.mdl", ent)
    expect.nils(ent.claimedTo, "already-owned prop must not be re-claimed")
end)

it("leaves world-owned props alone", function()
    reset()
    local ply   = gmod.player(TEAM_GREEN, {})
    local world = { IsValid = function() return true end }  -- game.GetWorld()
    local ent   = fakeEnt(world)

    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/hunter/plates/plate.mdl", ent)
    expect.nils(ent.claimedTo, "world-owned prop must not be re-claimed")
end)

it("claims pasted prop_effects the same way", function()
    reset()
    local ply = gmod.player(TEAM_GREEN, {})
    local ent = fakeEnt(nil)

    gmod.hooks.PlayerSpawnedEffect.TPG_EffectClaim(ply, "models/props_c17/oildrum001.mdl", ent)
    expect.eq(ent.claimedTo, ply, "pasted effect should be claimed to the spawner")
end)

it("survives entities with no CPPI implementation at all", function()
    reset()
    local ply = gmod.player(TEAM_GREEN, {})
    local ent = { IsValid = function() return true end }  -- no CPPI methods

    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/x.mdl", ent)
    -- no claim attempted and no error raised: reaching this line is the pass
end)

it("ignores an invalid entity argument", function()
    reset()
    local ply = gmod.player(TEAM_GREEN, {})
    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/x.mdl", nil)
    gmod.hooks.PlayerSpawnedProp.TPG_PropClaim(ply, "models/x.mdl", { IsValid = function() return false end })
    -- same: no error is the pass
end)
