--!strict
--[[
	Vfx/Shadow (ModuleScript, client)
	Effets de l'OMBRE, joués sur les événements du serveur. Matière sombre faite de fumée qui
	assombrit (LightEmission 0), de filaments qui ondulent (rubans dont la courbure bouge), de
	traînées ; l'énergie volée revient au lanceur sous forme de lueurs (le soin est celui du serveur).

	Trait Obscur (sort 1, PROJECTILE ; draine la vie, soigne le lanceur)
		préparation  des volutes sombres convergent vers la main
		vol          cœur sombre cerclé de rouge, filaments qui se tordent autour, fumée en traînée
		impact       éclaboussure d'ombre, puis des fragments d'énergie quittent la cible et reviennent
		             au lanceur (drain réel)
	Voile des Ombres (sort 2, SUR SOI ; protège : -40 % de dégâts, +15 % de vitesse)
		préparation  l'ombre monte du sol autour du lanceur
		manifestation  filaments sombres qui tournent autour du corps à différentes hauteurs, fumée
		             aux pieds ; il dure exactement tant que le voile est actif (attribut du serveur)
		             et laisse le joueur visible ; il se disperse à la fin
	Marée d'Ombres (ultime ; dégâts lourds, le lanceur se soigne)
		préparation  une flaque d'ombre s'étend, des formes sombres s'en élèvent et glissent vers les
		             cibles, des vrilles ondulantes les relient au sol
		impact       les formes se referment sur les cibles et éclatent, vague sombre, puis la vie
		             aspirée revient au lanceur en lueurs
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local StatusConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("StatusConfig") :: ModuleScript)

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Shadow = {}

local INK = Color3.fromRGB(8, 4, 8)

local function darkSmoke(parent: Instance, rate: number, props: { [string]: any }?): ParticleEmitter
	local emitter = VfxKit.emitter(parent, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(INK),
		Rate = rate,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(0.5, 1.5),
		Size = NumberSequence.new(1, 2.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	})
	if props then
		for key, value in props do
			(emitter :: any)[key] = value
		end
	end
	return emitter
end

-- Traînée sombre sur un attachement (ruban entre deux attachements proches).
local function shadowTrail(parent: Instance, a0: Attachment, a1: Attachment, palette: any, lifetime: number): Trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(INK, palette.main)
	trail.LightEmission = 0
	trail.Lifetime = lifetime
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	trail.Parent = parent
	return trail
end

-- Lueurs de vie : de `from` vers le lanceur (suivi en temps réel), en courbe.
local function lifeWisps(from: Vector3, caster: Model?, count: number, palette: any)
	local casterRoot = if caster then VfxKit.rootOf(caster) else nil
	if casterRoot == nil then
		return
	end
	for index = 1, count do
		local wisp = VfxKit.part("LifeWisp", Vector3.one * 0.45, palette.glow, Enum.Material.Neon, 1.2, Enum.PartType.Ball)
		wisp.CFrame = CFrame.new(from)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.15, 0)
		a0.Parent = wisp
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.15, 0)
		a1.Parent = wisp
		local trail = shadowTrail(wisp, a0, a1, palette, 0.3)
		trail.Color = ColorSequence.new(palette.glow, palette.main)
		trail.LightEmission = 1
		local bend = random:NextUnitVector() * random:NextNumber(3, 6) + Vector3.new(0, 3, 0)
		local delay = (index - 1) * 0.07
		task.delay(delay, function()
			VfxKit.animate(0.55, function(alpha: number)
				local target = casterRoot.Position + Vector3.new(0, 1, 0)
				local control = (from + target) / 2 + bend
				local p = (1 - alpha) ^ 2 * from + 2 * (1 - alpha) * alpha * control + alpha ^ 2 * target
				wisp.CFrame = CFrame.new(p)
			end, wisp, function()
				wisp:Destroy()
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- Trait Obscur
--------------------------------------------------------------------------------

local function boltCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("ShadowCharge", Vector3.one * 2.4, palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.6, -0.3), duration)
	darkSmoke(holder, 40 * detail, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(4, 6),
		Lifetime = NumberRange.new(0.25, 0.3),
		Size = NumberSequence.new(0.8, 0.2),
	})
	local orb = VfxKit.part("ShadowOrb", Vector3.one * 0.1, palette.void, Enum.Material.SmoothPlastic, duration + 0.05, Enum.PartType.Ball)
	VfxKit.follow(orb, holder, CFrame.new(), duration)
	VfxKit.tween(orb, duration, { Size = Vector3.one * 0.7 })
end

local function boltProjectile(palette: any, _spell: any): BasePart
	local root = VfxKit.part("DarkBolt", Vector3.one * 0.3, palette.main, Enum.Material.SmoothPlastic, 3)
	root.Transparency = 1
	local core = VfxKit.attach(root, "Part", "Core", Vector3.one * 0.75, CFrame.new(), palette.void, Enum.Material.SmoothPlastic);
	(core :: Part).Shape = Enum.PartType.Ball
	local rim = VfxKit.attach(root, "Part", "Rim", Vector3.one * 1.05, CFrame.new(), palette.main, Enum.Material.ForceField);
	(rim :: Part).Shape = Enum.PartType.Ball
	rim.Transparency = 0.2
	local detail = VfxKit.detail(nil)
	darkSmoke(root, 35 * detail, { Lifetime = NumberRange.new(0.3, 0.5), Size = NumberSequence.new(0.8, 1.8), Speed = NumberRange.new(0.2, 0.6) })
	-- Filaments qui se tordent autour du trait (attachements animés).
	local filaments: { { a0: Attachment, a1: Attachment, phase: number } } = {}
	for index = 1, (if VfxKit.rich(detail) then 3 else 2) do
		local a0 = Instance.new("Attachment")
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = root
		shadowTrail(root, a0, a1, palette, 0.35)
		table.insert(filaments, { a0 = a0, a1 = a1, phase = index * 2.1 })
	end
	VfxKit.animate(3, function(_alpha: number, elapsed: number)
		for _, pair in filaments do
			local angle = elapsed * 14 + pair.phase
			local offset = Vector3.new(math.cos(angle), math.sin(angle * 1.3), 0) * 0.7
			pair.a0.Position = offset
			pair.a1.Position = offset * 1.25
		end
	end, root)
	return root
end

local function boltImpact(_spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	VfxKit.burst(position, 14 * detail, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(INK),
		Speed = NumberRange.new(4, 9),
		Drag = 5,
		Lifetime = NumberRange.new(0.5, 0.8),
		Size = NumberSequence.new(1.2, 3),
		Transparency = NumberSequence.new(0.2, 1),
		Rotation = NumberRange.new(0, 360),
	})
	VfxKit.burst(position, 12 * detail, {
		Texture = T.spark,
		Color = ColorSequence.new(palette.glow, palette.main),
		Speed = NumberRange.new(6, 12),
		Drag = 5,
		Lifetime = NumberRange.new(0.2, 0.4),
		Size = NumberSequence.new(0.3, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	VfxKit.flash(position, palette.main, 10, 2, 0.3, detail)
	if #targets > 0 then
		lifeWisps(position, caster, VfxKit.count(4, detail, 2), palette)
	end
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
	end
	SfxPlayer.play("impact_shadow", position)
end

--------------------------------------------------------------------------------
-- Voile des Ombres
--------------------------------------------------------------------------------

local VEIL_FALLBACK = 4 -- s, si l'attribut du serveur n'est pas encore arrivé

local function veilCharge(caster: Model?, _spell: any, _palette: any, duration: number)
	local root = if caster then VfxKit.rootOf(caster) else nil
	if root == nil or caster == nil then
		return
	end
	local detail = VfxKit.detail(root.Position)
	local ground = VfxKit.groundBelow(root.Position, { caster, VfxKit.folder() })
	local base = VfxKit.part("ShadowRise", Vector3.new(4, 0.4, 4), INK, Enum.Material.SmoothPlastic, duration + 1.5)
	base.Transparency = 1
	base.CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0))
	local rise = darkSmoke(base, 30 * detail, {
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(15, 15),
		Speed = NumberRange.new(2, 4),
		Lifetime = NumberRange.new(0.5, 0.8),
	})
	task.delay(duration, function()
		rise.Enabled = false
	end)
end

local function veilRemaining(caster: Model): number
	local untilTime = caster:GetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. "veil")
	if type(untilTime) == "number" then
		return math.max(untilTime - workspace:GetServerTimeNow(), 0)
	end
	return -1 -- inconnu
end

local function veilImpact(_spell: any, _position: Vector3, _targets: { Model }, caster: Model?, palette: any)
	local root = if caster then VfxKit.rootOf(caster) else nil
	if root == nil or caster == nil then
		return
	end
	local detail = VfxKit.detail(root.Position)
	local maxDuration = VEIL_FALLBACK + 0.5
	-- Filaments en orbite autour du corps (porteurs invisibles qui suivent le lanceur).
	type Wisp = { part: Part, height: number, radius: number, speed: number, phase: number }
	local wisps: { Wisp } = {}
	for index = 1, VfxKit.count(4, detail, 2) do
		local carrier = VfxKit.part("VeilFilament", Vector3.one * 0.2, INK, Enum.Material.SmoothPlastic, maxDuration + 1)
		carrier.Transparency = 1
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.25, 0)
		a0.Parent = carrier
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.25, 0)
		a1.Parent = carrier
		shadowTrail(carrier, a0, a1, palette, 0.6)
		table.insert(wisps, { part = carrier, height = -1.8 + index * 0.9, radius = random:NextNumber(1.6, 2.2), speed = random:NextNumber(4, 6) * (if index % 2 == 0 then -1 else 1), phase = index * 1.6 })
	end
	local feet = VfxKit.part("VeilSmoke", Vector3.new(3, 0.4, 3), INK, Enum.Material.SmoothPlastic, maxDuration + 1.5)
	feet.Transparency = 1
	local smoke = darkSmoke(feet, 14 * detail, { Shape = Enum.ParticleEmitterShape.Box, Speed = NumberRange.new(0.3, 0.8), Lifetime = NumberRange.new(0.8, 1.2), Size = NumberSequence.new(1.2, 2.4) })
	local function dispel()
		smoke.Enabled = false
		task.delay(1.5, function()
			feet:Destroy()
		end)
		for _, wisp in wisps do
			if wisp.part.Parent then
				VfxKit.burst(wisp.part.Position, 4 * detail, { Texture = T.smoke, LightEmission = 0, Color = ColorSequence.new(INK), Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.4, 0.6), Size = NumberSequence.new(0.8, 1.6), Transparency = NumberSequence.new(0.3, 1) })
				wisp.part:Destroy()
			end
		end
	end
	VfxKit.animate(maxDuration, function(_alpha: number, elapsed: number)
		if not root.Parent then
			return
		end
		-- Le voile dure exactement tant que le serveur le maintient.
		local remaining = veilRemaining(caster)
		if remaining == 0 or (remaining < 0 and elapsed > VEIL_FALLBACK) then
			error("fin du voile") -- arrête l'animation (attrapé par VfxKit.animate)
		end
		local center = root.Position
		for _, wisp in wisps do
			local angle = wisp.phase + elapsed * wisp.speed
			local bob = math.sin(elapsed * 3 + wisp.phase) * 0.4
			wisp.part.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * wisp.radius, wisp.height + bob, math.sin(angle) * wisp.radius))
		end
		feet.CFrame = CFrame.new(center - Vector3.new(0, 2.6, 0))
	end, feet, dispel)
	VfxKit.burst(root.Position, 10 * detail, { Texture = T.spark, Color = ColorSequence.new(palette.glow, palette.main), Speed = NumberRange.new(3, 6), Lifetime = NumberRange.new(0.3, 0.5), Size = NumberSequence.new(0.3, 0), Transparency = NumberSequence.new(0, 1) })
end

--------------------------------------------------------------------------------
-- Marée d'Ombres (ultime)
--------------------------------------------------------------------------------

function Shadow.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.6
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ground = VfxKit.groundBelow(origin, VfxKit.ignore(caster, targets))

	-- 1. La flaque d'ombre s'étend.
	VfxKit.groundPatches("ShadowPool", ground, radius * 0.8, INK, Enum.Material.SmoothPlastic, 0.15, VfxKit.count(18, detail, 6), windup, 1.2)
	local pool = VfxKit.part("ShadowMist", Vector3.new(radius * 1.4, 0.4, radius * 1.4), INK, Enum.Material.SmoothPlastic, windup + 2.5)
	pool.Transparency = 1
	pool.CFrame = CFrame.new(ground + Vector3.new(0, 0.4, 0))
	local mist = darkSmoke(pool, 40 * detail, { Shape = Enum.ParticleEmitterShape.Box, Speed = NumberRange.new(0.2, 0.6), Lifetime = NumberRange.new(1, 1.5), Size = NumberSequence.new(2, 4) })
	if intensity > 0 then
		CombatEffects.tintScreen(palette.void, 0.55 * intensity, windup, 0.8)
	end

	-- 2. Des formes sombres s'élèvent et glissent vers les cibles ; vrilles du sol vers elles.
	type Shade = { part: Part, start: Vector3, target: BasePart? }
	local shades: { Shade } = {}
	local shadeCount = VfxKit.count(math.max(#targets, 4), detail, 3)
	shadeCount = math.min(shadeCount, 8)
	for index = 1, shadeCount do
		local angle = index / shadeCount * math.pi * 2
		local start = ground + Vector3.new(math.cos(angle) * radius * 0.6, 1.5, math.sin(angle) * radius * 0.6)
		local carrier = VfxKit.part("Shade", Vector3.new(1.5, 4, 1.5), INK, Enum.Material.SmoothPlastic, windup + 1.5)
		carrier.Transparency = 1
		carrier.CFrame = CFrame.new(start)
		darkSmoke(carrier, 26 * detail, { Shape = Enum.ParticleEmitterShape.Box, Speed = NumberRange.new(0.2, 0.6), Lifetime = NumberRange.new(0.4, 0.7), Size = NumberSequence.new(2.2, 3.6), Acceleration = Vector3.new(0, 2, 0) })
		local target = targets[((index - 1) % math.max(#targets, 1)) + 1]
		table.insert(shades, { part = carrier, start = start, target = if target then VfxKit.rootOf(target) else nil })
	end
	VfxKit.animate(windup, function(alpha: number)
		local eased = alpha * alpha
		for _, shade in shades do
			local goal = if shade.target and shade.target.Parent then shade.target.Position else origin
			shade.part.CFrame = CFrame.new(shade.start:Lerp(goal, eased * 0.85))
		end
	end)
	local tendrils = VfxKit.count(6, detail, 2)
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot and index <= tendrils then
			local foot = VfxKit.point(VfxKit.groundBelow(targetRoot.Position, VfxKit.ignore(caster, targets)) + Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3)), windup + 0.2)
			local grip = Instance.new("Attachment")
			grip.Parent = targetRoot
			game:GetService("Debris"):AddItem(grip, windup + 0.2)
			VfxKit.filament(foot, grip, ColorSequence.new(INK, palette.main), 0.9, windup + 0.15, 0, 4)
		end
	end

	task.wait(windup)
	mist.Enabled = false

	-- 3. Les formes se referment sur les cibles et éclatent ; vague sombre ; la vie revient.
	for _, shade in shades do
		if shade.part.Parent then
			VfxKit.burst(shade.part.Position, 10 * detail, { Texture = T.smoke, LightEmission = 0, Color = ColorSequence.new(INK), Speed = NumberRange.new(4, 8), Drag = 3, Lifetime = NumberRange.new(0.5, 0.8), Size = NumberSequence.new(2, 4), Transparency = NumberSequence.new(0.2, 1), Rotation = NumberRange.new(0, 360) })
			shade.part:Destroy()
		end
	end
	VfxKit.burst(origin + Vector3.new(0, 1, 0), 30 * detail, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(INK, palette.void),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(85, 85),
		Speed = NumberRange.new(radius * 0.8, radius * 1.3),
		Drag = 3,
		Lifetime = NumberRange.new(0.6, 1),
		Size = NumberSequence.new(3, 6),
		Transparency = NumberSequence.new(0.25, 1),
		Rotation = NumberRange.new(0, 360),
	})
	VfxKit.flash(origin + Vector3.new(0, 3, 0), palette.main, 30, 3, 0.5, detail)
	local wispsPer = if #targets > 4 then 1 else 3
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot then
			CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(8, detail))
			if index <= 6 then
				lifeWisps(targetRoot.Position, caster, VfxKit.count(wispsPer, detail, 1), palette)
			end
		end
	end
	SfxPlayer.play("impact_shadow", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.45 * intensity, 0.05, 0.7)
		CombatEffects.shake(0.35, 0.6 * intensity)
	end
end

--------------------------------------------------------------------------------

Shadow.spells = {
	dark_bolt = { charge = boltCharge, projectile = boltProjectile, impact = boltImpact },
	shadow_veil = { charge = veilCharge, impact = veilImpact },
}

return Shadow
