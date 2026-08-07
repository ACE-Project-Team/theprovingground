--[[--
    `tpg_safezonemarker`: the translucent sphere shown at a team's spawn to
    mark the boundary of spawn protection.

    Purely decorative -- it draws a sphere, it does not enforce anything. All
    protection logic (who counts as "in the safezone", who gets hurt for being
    in the enemy's) lives in `gamemode/player/sv_protection.lua`, which is a
    separate system this entity does not call into or read from.

    Accuracy trap: the sphere is scaled from the GLOBAL `TPG.Config.safezoneRadius`
    (`config/sh_config.lua`, currently 750), not from the running map's own
    `safezoneRadius` field in its `tpg.maps` config entry. `sv_protection.lua`
    reads the same global, so the two stay consistent with each other today --
    but the per-map `safezoneRadius` field that every map config in
    `_loader.lua` authors is not read by ANYTHING in the codebase. If a map
    were ever given a non-default per-map radius, this marker (and the actual
    protection check) would silently keep using the global value instead,
    with no error and no visible mismatch until someone measured it.

    @module tpg.ent.safezonemarker
    @realm shared
]]

ENT.Type = "anim"
ENT.PrintName = "Safezone Marker"
ENT.Author = "RDC"
ENT.Category = "TPG Objectives"
ENT.Spawnable = false
ENT.AdminSpawnable = false