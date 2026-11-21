--[[
    Vehicle-kill ledger.

    Same precedent as test_rush: this loads ONE server file and drives its
    hooks by hand. The ledger is the interesting logic (doom thresholds,
    freshness windows, attacker choice, once-per-fight crediting); the CFW and
    EntityTakeDamage plumbing is left to in-game testing.
]]

local gmod = expect.load.gmod

-- ── stubs for the neighbours the file talks to ──────────────────────────────
-- Other suites' cases can clobber these globals between this file's require
-- and its own cases running, so every stub is re-applied inside reset().

local conOf = {}       -- ent -> con
local conOwnerOf = {}  -- con -> owner player
local usage = {}       -- victim -> points
local drained = {}     -- { victim, points } calls
local econPaid = {}    -- { killer, value }
local assistPaid = {}  -- { assist, value }
local broadcasts = {}
local pstates = {}

local function applyStubs()
    ACE = {
        GetContraptionFromEntity = function(ent) return conOf[ent] end,
        GetContraptionOwner = function(con) return conOwnerOf[con] end,
    }
    TPG.PropTracking = { GetPlayerUsage = function(ply) return { points = usage[ply] or 0 } end }
    TPG.Commendations = { DrainKillTickets = function(victim, points)
        drained[#drained + 1] = { victim = victim, points = points }
        return 1
    end }
    TPG.Economy = { VehicleKillReward = function(killer, value)
        econPaid[#econPaid + 1] = { killer = killer, value = value }
    end,
    VehicleKillAssistReward = function(assist, value)
        assistPaid[#assistPaid + 1] = { assist = assist, value = value }
    end }
    TPG.Util = TPG.Util or {}
    TPG.Util.ChatBroadcast = function(msg) broadcasts[#broadcasts + 1] = msg end
    TPG.State = TPG.State or {}
    TPG.State.GetPlayer = function(ply)
        pstates[ply] = pstates[ply] or { stats = {} }
        return pstates[ply]
    end
end

-- ── fakes ───────────────────────────────────────────────────────────────────

local function ply(t)
    return gmod.player(t, { IsPlayer = function() return true end })
end

local function ent(con, owner, mass)
    local e = {
        _con = con,
        _owner = owner,
        _mass = mass or 0,
        IsValid = function() return true end,
        IsPlayer = function() return false end,
        CPPIGetOwner = function(self) return self._owner end,
        GetClass = function() return "prop_physics" end,
    }
    conOf[e] = con
    return e
end

local function con(mass, owner)
    local c = { totalMass = mass, ents = {} }
    conOwnerOf[c] = owner
    return c
end

-- An entity deleted/destroyed at hook time: marked for deletion, `_mass` cached.
local function deadEnt(con, mass)
    return { _mass = mass,
             IsValid = function() return false end,
             IsMarkedForDeletion = function() return true end }
end

-- An acf_ammo crate living on the contraption. `opts.dead` models it already
-- cooking off (Exploding) so the remaining-ammo scan counts it as gone.
local function ammoEnt(c, calMm, opts)
    opts = opts or {}
    local e = {
        _mass = opts.mass or 0,
        Caliber = calMm / 10,           -- ACE stores crate calibers in cm
        BulletData = { Caliber = calMm / 10 },
        Exploding = opts.dead or nil,
        Inflictor = opts.inflictor,
        GetClass = function() return "acf_ammo" end,
        IsValid = function() return true end,
        IsMarkedForDeletion = function() return opts.marked or false end,
    }
    c.ents[e] = true            -- CFW keeps con.ents as a set keyed by entity
    conOf[e] = c
    return e
end

local function dmg(amount, attacker)
    return {
        GetDamage = function() return amount end,
        GetAttacker = function() return attacker end,
    }
end

local function fireDamage(victimEnt, amount, attacker)
    hook.GetTable().EntityTakeDamage.TPG_VehicleKillLedger(victimEnt, dmg(amount, attacker))
end

local function fireRemoved(c, e)
    hook.GetTable()["cfw.contraption.entityRemoved"].TPG_VehicleKillRemovedEnt(c, e)
end

local function fireAdded(c, e)
    hook.GetTable()["cfw.contraption.entityAdded"].TPG_VehicleKillAddedEnt(c, e)
end

local function fireSplit(parent, child)
    hook.GetTable()["cfw.contraption.split"].TPG_VehicleKillSplit(parent, child)
end

local function fireMerged(c, into)
    hook.GetTable()["cfw.contraption.merged"].TPG_VehicleKillMerged(c, into)
end

local function fireConRemoved(c)
    hook.GetTable()["cfw.contraption.removed"].TPG_VehicleKillRemoved(c)
end

local function fireAmmoExplode(e)
    hook.GetTable().ACE_AmmoExplode.TPG_VehicleKillAmmo(e, e.BulletData)
end

local function killed() return econPaid end

local function reset()
    conOf, conOwnerOf, usage = {}, {}, {}
    drained, econPaid, assistPaid, broadcasts, pstates = {}, {}, {}, {}, {}
    gmod.curtime = 0
    applyStubs()
    -- loader.reset() wipes the hook registry before every case, so the file's
    -- hook.Add registrations have to be re-run per test.
    expect.load.dofile(expect.root .. "/gamemode/systems/sv_vehiclekill.lua")
end

-- ── cases ───────────────────────────────────────────────────────────────────

describe("vehiclekill: ledger + doom + credit")

it("ignores friendly fire entirely", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 500, green)          -- owner shooting own tank
    fireDamage(e, 500, ply(TEAM_GREEN))
    expect.nils(c.TPG_VK, "no ledger should exist for friendly damage")

    -- A red player hits it: ledger spawns, owner recorded.
    fireDamage(e, 100, red)
    expect.truthy(c.TPG_VK, "enemy hit should start the ledger")
    expect.eq(c.TPG_VK.owner, green)
    expect.eq(c.TPG_VK.lastAttacker, red)
end)

it("ignores world and spectator damage", function()
    reset()
    local green = ply(TEAM_GREEN)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 100, nil)
    fireDamage(e, 100, ply(TEAM_UNASSIGNED))
    expect.nils(c.TPG_VK)
end)

it("resolves a CPPI-owned gun entity to its owner", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)
    local gun = { IsValid = function() return true end,
                  IsPlayer = function() return false end,
                  CPPIGetOwner = function() return red end }

    fireDamage(e, 50, gun)
    expect.eq(c.TPG_VK.lastAttacker, red)
    expect.eq(c.TPG_VK.dmg[red], 50)
end)

it("dooms at half mass lost with fresh enemy damage, then pays once", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)
    usage[green] = 4200

    fireDamage(e, 100, red)
    fireRemoved(c, deadEnt(c, 500))   -- lost 50% of peak
    expect.truthy(c.TPG_VKDoomAt, "50% loss with fresh hits should doom")

    fireConRemoved(c)                    -- wreck finally ends (undo or shot up)
    expect.eq(#killed(), 1)
    expect.eq(killed()[1].killer, red)
    expect.eq(killed()[1].value, 4200)
    expect.eq(#drained, 1)
    expect.eq(drained[1].points, 4200)
    expect.eq(pstates[red].stats.vehicleKills, 1)
    expect.truthy(#broadcasts > 0, "kill feed should announce it")

    -- Never twice, even if CFW fires again for a fragment.
    fireConRemoved(c)
    expect.eq(#killed(), 1)
end)

it("pays nothing when the tank was never doomed", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 100, red)
    fireRemoved(c, deadEnt(c, 200))   -- only 20% gone: not "literally dead"
    expect.nils(c.TPG_VKDoomAt)

    fireConRemoved(c)
    expect.eq(#killed(), 0)
end)

it("expires both the doom and the credit window", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    -- Damage goes stale BEFORE the mass drops: normal cleanup later, no doom.
    fireDamage(e, 100, red)
    gmod.curtime = 40                    -- past the 30s window
    fireRemoved(c, deadEnt(c, 700))
    expect.nils(c.TPG_VKDoomAt, "stale hits should not doom")

    -- Doomed, but the wreck outlives the credit window before ending.
    gmod.curtime = 50
    fireDamage(e, 100, red)              -- fresh hit re-dooms it
    fireRemoved(c, deadEnt(c, 700))
    expect.truthy(c.TPG_VKDoomAt)
    gmod.curtime = 50 + 31
    fireConRemoved(c)
    expect.eq(#killed(), 0, "credit should expire with the window")
end)

it("repairs un-doom a build that regains its mass", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 100, red)
    fireRemoved(c, deadEnt(c, 600))   -- 60% gone: doomed
    expect.truthy(c.TPG_VKDoomAt)

    fireAdded(c, ent(c, green, 900))     -- welded back together mid-fight
    expect.nils(c.TPG_VKDoomAt, "recovered mass should un-doom")

    fireConRemoved(c)
    expect.eq(#killed(), 0)
end)

it("picks the top enemy contributor, not the last plinker", function()
    reset()
    local green = ply(TEAM_GREEN)
    local heavy = ply(TEAM_RED)
    local plink = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 900, heavy)            -- did the real work
    fireDamage(e, 10, plink)             -- nicked it at the end
    fireRemoved(c, deadEnt(c, 600))
    fireConRemoved(c)

    expect.eq(#killed(), 1)
    expect.eq(killed()[1].killer, heavy, "credit belongs to the heavy hitter")
end)

it("shares one kill across split fragments", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 100, red)
    fireRemoved(c, deadEnt(c, 600))
    expect.truthy(c.TPG_VKDoomAt)

    -- Turret flies off into its own fragment.
    local frag = con(400, green)
    fireSplit(c, frag)
    expect.eq(frag.TPG_VK, c.TPG_VK, "fragment inherits the shared ledger")

    -- Removing the (healthy-looking) fragment alone pays nothing...
    fireConRemoved(frag)
    expect.eq(#killed(), 0)

    -- ...the parent ending pays it, once.
    fireConRemoved(c)
    expect.eq(#killed(), 1)
    expect.eq(killed()[1].killer, red)

    -- And the fragment's later removal can't pay again.
    fireConRemoved(frag)
    expect.eq(#killed(), 1)
end)

it("merges ledgers when contraptions combine", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local other = ply(TEAM_RED)
    local c1 = con(1000, green)
    local c2 = con(500, green)
    local e1 = ent(c1, green)
    local e2 = ent(c2, green)

    fireDamage(e1, 100, red)
    gmod.curtime = 5                     -- c2's hit is the fresher one
    fireDamage(e2, 300, other)
    fireMerged(c2, c1)

    expect.eq(c1.TPG_VK.dmg[red], 100)
    expect.eq(c1.TPG_VK.dmg[other], 300)
    expect.eq(c1.TPG_VK.lastAttacker, other, "freshest hit wins on merge")
end)

it("tracks peak mass upward but never downward", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 50, red)
    expect.eq(c.TPG_VKPeak, 1000)

    fireAdded(c, ent(c, green, 500))     -- owner added plating mid-fight
    expect.eq(c.TPG_VKPeak, 1500, "peak follows growth")

    fireRemoved(c, deadEnt(c, 700))   -- 700/1500: only 47% of peak lost
    expect.nils(c.TPG_VKDoomAt, "under half lost should not doom")

    fireRemoved(c, deadEnt(c, 100))   -- 800/1500: 53% of peak lost -> doomed
    expect.truthy(c.TPG_VKDoomAt)
end)

it("does not manufacture doom from the teardown ejections themselves", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    -- Two-entity contraption: deleting the small half is 37.5%, under the line.
    local c = con(1600, green)
    local e = ent(c, green)

    fireDamage(e, 100, red)
    fireRemoved(c, deadEnt(c, 600))      -- 600/1600 = 37.5%
    expect.nils(c.TPG_VKDoomAt, "under half lost should not doom")

    -- Disbanding ejects the survivor while it is still valid: that departure
    -- is teardown bookkeeping, not destruction, and must not count.
    fireRemoved(c, ent(c, green, 1000))
    expect.nils(c.TPG_VKDoomAt, "the ejected survivor is not destruction")

    fireConRemoved(c)
    expect.eq(#killed(), 0)
end)

it("pays an assist to a meaningful second contributor", function()
    reset()
    local green = ply(TEAM_GREEN)
    local heavy = ply(TEAM_RED)
    local wing  = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)
    usage[green] = 6000

    fireDamage(e, 700, heavy)            -- 70% of the damage: the kill
    fireDamage(e, 300, wing)             -- 30%: over the 15% assist line
    fireRemoved(c, deadEnt(c, 600))
    fireConRemoved(c)

    expect.eq(#killed(), 1)
    expect.eq(killed()[1].killer, heavy)
    expect.eq(#assistPaid, 1)
    expect.eq(assistPaid[1].assist, wing)
    expect.eq(assistPaid[1].value, 6000, "assist is priced on the same fielded value")
    expect.eq(pstates[wing].stats.assists, 1)
    expect.eq(pstates[wing].stats.vehicleKills or 0, 0, "assist is not the kill")
    expect.truthy(string.find(broadcasts[#broadcasts] or "", "assisted"), "feed names the assist")
end)

it("ignores a plinker below the assist share", function()
    reset()
    local green = ply(TEAM_GREEN)
    local heavy = ply(TEAM_RED)
    local plink = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 900, heavy)
    fireDamage(e, 100, plink)            -- 10% < 15% line: no assist
    fireRemoved(c, deadEnt(c, 600))
    fireConRemoved(c)

    expect.eq(#killed(), 1)
    expect.eq(#assistPaid, 0)
    expect.eq((pstates[plink] and pstates[plink].stats.assists or 0), 0)
    expect.falsy(string.find(broadcasts[#broadcasts] or "", "assisted"))
end)

it("lists multiple assists when a squad shares the kill", function()
    reset()
    local green = ply(TEAM_GREEN)
    local a = ply(TEAM_RED)
    local b = ply(TEAM_RED)
    local d = ply(TEAM_RED)
    local c = con(1000, green)
    local e = ent(c, green)

    fireDamage(e, 400, a)                -- top takes the kill
    fireDamage(e, 350, b)
    fireDamage(e, 250, d)
    fireRemoved(c, deadEnt(c, 600))
    fireConRemoved(c)

    expect.eq(#assistPaid, 2)
    local names = broadcasts[#broadcasts] or ""
    expect.truthy(string.find(names, "assisted"))
end)

it("credits the kill instantly when the main ammo cooks off", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)
    usage[green] = 8000

    -- One big rack, under half the con's mass: mass-doom alone could never pay.
    local rack = ammoEnt(c, 120, { dead = true, inflictor = red })

    fireDamage(e, 100, red)
    fireAmmoExplode(rack)

    expect.eq(#killed(), 1, "main ammo death is the kill, no removal needed")
    expect.eq(killed()[1].killer, red)
    expect.eq(killed()[1].value, 8000)
    expect.truthy(c.TPG_VKDoomAt)

    -- The later removal must not pay a second time.
    fireConRemoved(c)
    expect.eq(#killed(), 1)
end)

it("does not doom while a second big rack survives", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)

    ammoEnt(c, 120)                                -- surviving main rack
    local dead = ammoEnt(c, 120, { dead = true })  -- the cooked one

    fireDamage(e, 100, red)
    fireAmmoExplode(dead)
    expect.eq(#killed(), 0, "a live main rack means the tank still fights")
end)

it("treats mid ammo as the main armament when nothing bigger exists", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(800, green)
    local e = ent(c, green)

    local rack = ammoEnt(c, 20, { dead = true })   -- 20mm autocannon = this
                                                 -- light build's main gun
    fireDamage(e, 100, red)
    fireAmmoExplode(rack)

    expect.eq(#killed(), 1, "mid ammo is main when it is the biggest aboard")
end)

it("pays an assist when a big tank loses all mid ammo", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)
    usage[green] = 6000

    ammoEnt(c, 120)                                -- main rack, stays live
    local coax = ammoEnt(c, 20, { dead = true, inflictor = red })

    fireDamage(e, 100, red)
    fireAmmoExplode(coax)

    expect.eq(#killed(), 0, "secondary ammo is not a mission kill")
    expect.eq(#assistPaid, 1, "wiped secondary band pays the assist")
    expect.eq(assistPaid[1].assist, red)
    expect.eq(assistPaid[1].value, 6000)

    -- And it only pays once: a second mid rack dying repeats nothing.
    local coax2 = ammoEnt(c, 20, { dead = true, inflictor = red })
    fireAmmoExplode(coax2)
    expect.eq(#assistPaid, 1)
end)

it("ignores coax ammo unless it was the only thing aboard", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)

    ammoEnt(c, 120)                                -- main rack live: coax is
    local mg = ammoEnt(c, 8, { dead = true })      -- decoration
    fireDamage(e, 100, red)
    fireAmmoExplode(mg)
    expect.eq(#killed(), 0)
    expect.eq(#assistPaid, 0)

    -- A build that carries ONLY MG ammo still dies with it.
    reset()
    local g2, r2 = ply(TEAM_GREEN), ply(TEAM_RED)
    local c2 = con(500, g2)
    local e2 = ent(c2, g2)
    local mgOnly = ammoEnt(c2, 8, { dead = true })
    fireDamage(e2, 100, r2)
    fireAmmoExplode(mgOnly)
    expect.eq(#killed(), 1, "losing literally all ammo is still a kill")
end)

it("evaluates a cook-off that preceded the ledger", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)

    -- The rack explodes BEFORE any recorded enemy hit (same-hit hook order).
    local rack = ammoEnt(c, 120, { dead = true })
    fireAmmoExplode(rack)
    expect.eq(#killed(), 0)

    -- The very hit that caused it opens the ledger, which picks the event up.
    fireDamage(e, 100, red)
    expect.eq(#killed(), 1)
end)

it("counts quiet ammo removals like combat ones", function()
    reset()
    local green = ply(TEAM_GREEN)
    local red = ply(TEAM_RED)
    local c = con(3000, green)
    local e = ent(c, green)

    -- Deleting the main rack mid-fight: dead ammunition is dead ammunition.
    fireDamage(e, 100, red)
    fireRemoved(c, ammoEnt(c, 120, { dead = true, marked = true }))
    expect.eq(#killed(), 1)
end)
