--[[--
    disposableat (server): overrides `shared.lua`'s `DeployDelay` of 2 up to 3,
    and re-arms the fire delay on every Equip.

    Because this file loads after `shared.lua`, the 3 set here is the value
    that actually applies in game, not the 2 visible in `shared.lua`.

    @module tpg.weapon.disposableat.server
    @realm server
]]
AddCSLuaFile ("cl_init.lua")
AddCSLuaFile ("shared.lua")

include ('shared.lua')

SWEP.DeployDelay = 3 --No more rocket 2 taps or sprinting lawnchairs

--- Runs every time this weapon is equipped (initial pickup, or switched back
-- to): re-arms `NextPrimaryFire` to `CurTime() + DeployDelay`, which is what
-- stops firing immediately on a fast weapon-switch back to this tube.
-- @realm server
function SWEP:Equip()

	self:DoAmmoStatDisplay()
	self:SetNextPrimaryFire( CurTime() + self.DeployDelay )
end