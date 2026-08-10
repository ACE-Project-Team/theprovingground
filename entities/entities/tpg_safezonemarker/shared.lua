--[[--
    `tpg_safezonemarker`: the translucent sphere shown at a team's spawn to
    mark the boundary of spawn protection.

    Purely decorative -- it draws a sphere, it does not enforce anything. All
    protection logic (who counts as "in the safezone", who gets hurt for being
    in the enemy's) lives in `gamemode/player/sv_protection.lua`, which is a
    separate system this entity does not call into or read from.

    The sphere is scaled from @{TPG.Maps.GetSafezoneRadius}, which is the map's
    own `safezoneRadius` falling back to the global `TPG.Config.safezoneRadius`.
    `sv_protection.lua` reads it through the same function, so the drawn
    boundary and the enforced one cannot drift. Older comments in this repo
    describe the per-map field as dead -- it was, for a long while, when every
    consumer went straight to the global; it is not any more.

    @module tpg.ent.safezonemarker
    @realm shared
]]

ENT.Type = "anim"
ENT.PrintName = "Safezone Marker"
ENT.Author = "RDC"
ENT.Category = "TPG Objectives"
ENT.Spawnable = false
ENT.AdminSpawnable = false