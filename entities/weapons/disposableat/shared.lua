--[[
    Disposable AT

    One THEAT rocket, then the tube is gone (the weapon strips itself after
    firing). Rebuilt on weapon_ace_base: the original was written against the
    long-removed "ace_basewep" base, so it had been silently dead -- wrong
    base, no fire functions, and nothing in the loadout system offered it.
    It's now discovered like any other ACE SWEP (Slot 4 -> Special).

    Ballistics are the original's 60mm THEAT round. NOTE: field names must be
    the modern ACF spelling "Area" (FrArea/PenArea/SlugPenArea) -- the original
    used the long-dead "Ae" + "ra" spelling, so ACF read nil PenArea/SlugPenArea and
    errored on deploy (DoAmmoStatDisplay) and on ground impact (PenetrateGround).
]]

AddCSLuaFile("shared.lua")

SWEP.Base = "weapon_ace_base"

SWEP.PrintName    = "Disposable AT"
SWEP.Slot         = 4
SWEP.SlotPos      = 3
SWEP.Spawnable    = true
SWEP.Category     = "ACE Sweps - RKT"

SWEP.Purpose      = "Clear backblast! One rocket, then ditch the tube."
SWEP.Instructions = "Left mouse to shoot. Single use."

-- Visuals
SWEP.ViewModelFlip   = false
SWEP.ViewModel       = "models/weapons/v_RPG.mdl"
SWEP.WorldModel      = "models/weapons/w_rocket_launcher.mdl"
SWEP.HoldType        = "rpg"
SWEP.CSMuzzleFlashes = false
SWEP.DeployDelay     = 2

-- Fire settings
SWEP.FireRate            = 0.2
-- Must be a sound registered with ACE_DefineGunFireSound: the base's fire path
-- does next(ACE.GSounds.GunFire[Sound]), which errors on an unregistered sound
-- (the table entry is nil, not empty). Reuse the AT4's registered launch sound.
SWEP.Primary.Sound       = "ace_weapons/sweps/multi_sound/at4_multi.mp3"
SWEP.Primary.LightScale  = 300
SWEP.Primary.ClipSize    = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "RPG_Round"
SWEP.Primary.BulletCount = 1

SWEP.Secondary.Ammo        = "none"
SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1

-- Recoil / spread (one big kick; explicit Side/Roll so the base's ViewPunch
-- never sees nil)
SWEP.HeatPerShot         = 100
SWEP.HeatMax             = 100
SWEP.HeatReductionRate   = 25
SWEP.ViewPunchAmount     = 8
SWEP.ViewPunchAmountSide = 0
SWEP.ViewPunchAmountRoll = 0

SWEP.BaseSpread     = 0.2
SWEP.MaxSpread      = 15
SWEP.MovementSpread = 3
SWEP.UnscopedSpread = 0.5

SWEP.ZoomFOV  = 50
SWEP.HasScope = false

SWEP.CarrySpeedMul = 0.8   -- lighter than a reloadable launcher

function SWEP:InitBulletData()

	self.BulletData = {}

		self.BulletData.Id = "75mmHW"
		self.BulletData.Type = "THEAT"
		self.BulletData.Id = 2
		self.BulletData.Caliber = 6.0
		self.BulletData.PropLength = 14 --Volume of the case as a cylinder * Powder density converted from g to kg
		self.BulletData.ProjLength = 60 --Volume of the projectile as a cylinder * streamline factor (Data5) * density of steel
		self.BulletData.Data5 = 2500  --He Filler or Flechette count
		self.BulletData.Data6 = 60 --HEAT ConeAng or Flechette Spread
		self.BulletData.Data7 = 0
		self.BulletData.Data8 = 0
		self.BulletData.Data9 = 0
		self.BulletData.Data10 = 1 -- Tracer
		self.BulletData.Colour = Color(255, 110, 0)
		--
		self.BulletData.Data13 = 57 --THEAT ConeAng2
		self.BulletData.Data14 = 0.85 --THEAT HE Allocation
		self.BulletData.Data15 = 0

		self.BulletData.AmmoType  = self.BulletData.Type
		self.BulletData.FrArea    = 3.1416 * (self.BulletData.Caliber/2)^2
		self.BulletData.ProjMass  = self.BulletData.FrArea * (self.BulletData.ProjLength*7.9/1000)
		self.BulletData.PropMass  = self.BulletData.FrArea * (self.BulletData.PropLength*ACF.PDensity/1000) --Volume of the case as a cylinder * Powder density converted from g to kg
		self.BulletData.FillerVol = self.BulletData.Data5
		self.BulletData.FillerMass = self.BulletData.FillerVol * ACF.HEDensity/1000
		self.BulletData.BoomFillerMass = self.BulletData.FillerMass / 250
		local ConeArea = 3.1416 * self.BulletData.Caliber/2 * ((self.BulletData.Caliber/2)^2 + self.BulletData.ProjLength^2)^0.5
		local ConeThick = self.BulletData.Caliber/50

		local ConeVol = ConeArea * ConeThick
		self.BulletData.SlugMass = ConeVol*7.9/1000
		self.BulletData.SlugMass2 = ConeVol*7.9/1000
		local Rad = math.rad(self.BulletData.Data6/2)
		self.BulletData.HEAllocation = self.BulletData.Data14
		self.BulletData.SlugCaliber =  self.BulletData.Caliber - self.BulletData.Caliber * (math.sin(Rad)*0.5+math.cos(Rad)*1.5)/2
		self.BulletData.SlugMV =( self.BulletData.FillerMass/2 * (1-self.BulletData.HEAllocation) * ACF.HEPower * math.sin(math.rad(10+self.BulletData.Data6)/2) /self.BulletData.SlugMass)^ACF.HEATMVScale
		self.BulletData.SlugCaliber2 =  self.BulletData.Caliber - self.BulletData.Caliber * (math.sin(Rad)*0.5+math.cos(Rad)*1.5)/2
		self.BulletData.SlugMV2 =( self.BulletData.FillerMass/2 * self.BulletData.HEAllocation * ACF.HEPower * math.sin(math.rad(10+self.BulletData.Data6)/2) /self.BulletData.SlugMass)^ACF.HEATMVScale
		self.BulletData.Detonated = 0
		local SlugFrArea = 3.1416 * (self.BulletData.SlugCaliber/2)^2
		local SlugFrArea2 = 3.1416 * (self.BulletData.SlugCaliber2/2)^2
		self.BulletData.SlugPenArea = SlugFrArea^ACF.PenAreaMod
		self.BulletData.SlugPenArea2 = SlugFrArea^ACF.PenAreaMod
		self.BulletData.SlugDragCoef = ((SlugFrArea/10000)/self.BulletData.SlugMass)*1000
		self.BulletData.SlugDragCoef2 = ((SlugFrArea2/10000)/self.BulletData.SlugMass2)*1000
		self.BulletData.SlugRicochet = 	500									--Base ricochet angle (The HEAT slug shouldn't ricochet at all)
		self.BulletData.SlugRicochet2 = 	500									--Base ricochet angle (The HEAT slug shouldn't ricochet at all)

		self.BulletData.CasingMass = self.BulletData.ProjMass - self.BulletData.FillerMass - ConeVol*7.9/1000
		self.BulletData.Fragments = math.max(math.floor((self.BulletData.BoomFillerMass/self.BulletData.CasingMass)*ACF.HEFrag),2)
		self.BulletData.FragMass = self.BulletData.CasingMass/self.BulletData.Fragments
		self.BulletData.DragCoef  = ((self.BulletData.FrArea/10000)/self.BulletData.ProjMass)

		--Don't touch below here
		self.BulletData.MuzzleVel = ACF_MuzzleVelocity( self.BulletData.PropMass, self.BulletData.ProjMass, self.BulletData.Caliber )
		self.BulletData.ShovePower = 0.2
		self.BulletData.KETransfert = 0.3
		self.BulletData.PenArea = self.BulletData.FrArea^ACF.PenAreaMod
		self.BulletData.Pos = Vector(0 , 0 , 0)
		self.BulletData.LimitVel = 800
		self.BulletData.Ricochet = 999
		self.BulletData.Flight = Vector(0 , 0 , 0)
		self.BulletData.BoomPower = self.BulletData.PropMass + self.BulletData.FillerMass

		local SlugEnergy = ACF_Kinetic( self.BulletData.SlugMV*39.37 , self.BulletData.SlugMass, 999999 )
		self.BulletData.MaxPen = (SlugEnergy.Penetration/self.BulletData.SlugPenArea)*ACF.KEtoRHA
		local SlugEnergy2 = ACF_Kinetic( self.BulletData.SlugMV2*39.37 , self.BulletData.SlugMass2, 999999 )
		self.BulletData.MaxPen = (SlugEnergy2.Penetration/self.BulletData.SlugPenArea2)*ACF.KEtoRHA

		--For Fake Crate
		self.BoomFillerMass = self.BulletData.BoomFillerMass
		self.Type = self.BulletData.Type
		self.BulletData.Tracer = self.BulletData.Data10
		self.Tracer = self.BulletData.Tracer
		self.Caliber = self.BulletData.Caliber
		self.ProjMass = self.BulletData.ProjMass
		self.FillerMass = self.BulletData.FillerMass
		self.DragCoef = self.BulletData.DragCoef
		self.Colour = self.BulletData.Colour
		self.DetonatorAngle = 80

end

-- Single use: the tube is spent after one rocket. Strip shortly after the shot
-- resolves; OnRemove (below) hands the carry-speed penalty back.
function SWEP:OnPrimaryAttack()
	if not SERVER then return end

	local owner = self:GetOwner()
	timer.Simple(0.1, function()
		if IsValid(owner) then
			owner:StripWeapon("disposableat")
		end
	end)
end

-- The base's OnRemove only restores the carry-speed penalty when its fake crate
-- is still valid -- and a tube stripped the instant it fires usually isn't, so
-- the 0.8x slow stuck permanently. Always restore the snapshotted speed here,
-- then defer to the base for its crate cleanup.
function SWEP:OnRemove()
	if SERVER then
		local owner = self:GetOwner()
		if IsValid(owner) and owner:IsPlayer() and self.NormalPlayerWalkSpeed then
			owner:SetWalkSpeed(self.NormalPlayerWalkSpeed)
			owner:SetRunSpeed(self.NormalPlayerRunSpeed)
		end
	end

	if self.BaseClass and self.BaseClass.OnRemove then
		self.BaseClass.OnRemove(self)
	end
end
