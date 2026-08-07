--[[--
    `tpg_controlpoint`: a capturable objective for CP/KOTH rounds.

    Spawned by `TPG.Objectives.SpawnAll` (not in this file's scope) using the
    `{ pos, name }` entries @{tpg.maps.GetObjectives} returns for the current
    game type -- one entity per authored objective. The spawner is expected to
    set `.PointID` and `.PointName` on the entity and then call
    `:SetupNetworking()` (server, `init.lua`) so the pip/HUD naming matches
    before the point starts thinking.

    All capture math lives server-side in `init.lua`: a signed `CapProgress`
    ranging `-CapTimeMax` to `+CapTimeMax` seconds, whose sign is read as the
    owning team (see `tpg.controlpoint`'s `STATE_*`/`TeamToState` for the
    shared version of this convention -- this entity keeps its own copy rather
    than calling into that module). `CapOwnership`, `CapProgress` and the
    entity's `Color` (team-tinted, brightness scaled by how firmly the point is
    held) are networked so `cl_init.lua` and the HUD files can read them
    without a dedicated net message. `UpdateTransmitState` forces
    `TRANSMIT_ALWAYS` so every point exists on every client from the moment
    they join -- default PVS networking would otherwise hide a point clientside
    (no HUD marker) until a player had physically been near it.

    Calls back into `TPG.Objectives.OnCapture(self, capTeam)` (if present) on
    every non-neutral capture, and broadcasts a chat line + sounds on every
    ownership change including a return to neutral.

    @module tpg.ent.controlpoint
    @realm shared
]]

ENT.Type = "anim"
ENT.PrintName = "Control Point"
ENT.Author = "RDC"
ENT.Category = "TPG Objectives"
ENT.Spawnable = false
ENT.AdminSpawnable = false