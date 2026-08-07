--[[--
    disposableat (client): stock HUD flags only, no custom drawing.

    Standard ammo counter, crosshair, weapon info box and pickup bounce icon.
    There is no `SWEP:DrawHUD`, so everything the player sees comes from the
    weapon base reading these four flags.

    @module tpg.weapon.disposableat.client
    @realm client
]]
include('shared.lua')

SWEP.DrawAmmo           = true
SWEP.DrawCrosshair      = true
SWEP.DrawWeaponInfoBox	= true
SWEP.BounceWeaponIcon   = true