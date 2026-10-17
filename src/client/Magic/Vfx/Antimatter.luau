--!strict
--[[
	Vfx/Antimatter (ModuleScript, client)
	Effets de l'ANTIMATIÈRE, joués sur les événements du serveur. Rien ici ne déplace ni ne blesse :
	les aspirations montrées sont celles que le serveur applique (StatusConfig « pull » : jamais sur
	un boss ; ultime : survivants tirés vers le lanceur, UltimateBehaviors).

	Roblox n'a pas de réfraction plein écran : la « déformation de l'espace » est une illusion faite
	de sphères de verre (le matériau Glass brouille ce qu'il y a derrière, selon la qualité
	graphique du joueur), de coques ForceField qui ondulent, de particules sombres aspirées et de
	fragments en orbite.

	Fragment du Vide (sort 1, projectile LENT qui EXPLOSE en zone ; aucune altération)
		préparation  une sphère noire se condense dans la main, l'énergie violette y converge
		vol          sphère à couches (cœur noir, lentille de verre, coque ondulante), traînée courte
		             de fragments sombres
		impact       la sphère enfle, se contracte d'un coup, puis l'onde de rupture part (coque,
		             lentille, onde de choc, éclats noirs projetés)
	Singularité Mineure (sort 2, ZONE qui ASPIRE jusqu'à 6 ennemis puis implose ; les boss résistent)
		préparation  un point noir naît au-dessus du sol, l'espace se bombe autour (lentille), la
		             poussière commence à converger
		impact       cœur sombre, coque qui ondule, anneaux de fragments en orbite, matière aspirée,
		             liens tendus vers chaque ennemi réellement aspiré (un boss rompt le lien) ;
		             contraction puis implosion finale
	Rupture du Néant (ultime)
		préparation  la matière obscure de toute la zone est tirée en spirale vers un cœur au-dessus
		             du lanceur, qui grossit pendant que l'espace se comprime ; liens vers les cibles ;
		             juste avant la libération, musique et ambiance s'effacent un instant (joueurs
		             proches seulement)
		libération   effondrement du cœur, onde géante, fissures sombres au sol, éclats projetés,
		             éclat lumineux bref, secousse modérée (désactivée en effets réduits) ; les
		             survivants sont tirés vers le lanceur (traînées vers lui)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local BossConfig = require(sharedFolder:WaitForChild("Boss"):WaitForChild("BossConfig") :: ModuleScript)

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local AudioMixer = require(clientFolder:WaitForChild("Audio"):WaitForChild("AudioMixer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Antimatter = {}

local VOID_BLACK = Color3.fromRGB(4, 2, 8)

local function isBoss(model: Model): boolean
	return CollectionService:HasTag(model, BossConfig.TAG)
end

local function ball(name: string, size: number, color: Color3, material: Enum.Material, lifetime: number, transparency: number): Part
	local part = VfxKit.part(name, Vector3.one * size, color, material, lifetime, Enum.PartType.Ball)
	part.Transparency = transparency
	return part
end

local function attachBall(root: BasePart, name: string, size: number, color: Color3, material: Enum.Material, transparency: number): BasePart
	local part = VfxKit.attach(root, "Part", name, Vector3.one * size, CFrame.new(), color, material);
	(part :: Part).Shape = Enum.PartType.Ball
	part.Transparency = transparency
	return part
end

-- Particules sombres (LightEmission 0 : elles assombrissent au lieu d'éclairer).
local function darkMatter(parent: Instance, rate: number, props: { [string]: any }?): ParticleEmitter
	local emitter = VfxKit.emitter(parent, {
		Texture = T.spark,
		LightEmission = 0,
		Color = ColorSequence.new(VOID_BLACK),
		Rate = rate,
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(0.5, 2),
		Drag = 3,
		Size = NumberSequence.new(0.35, 0),
		Transparency = NumberSequence.new(0, 1),
		Rotation = NumberRange.new(0, 360),
	})
	if props then
		for key, value in props do
			(emitter :: any)[key] = value
		end
	end
	return emitter
end

-- Tourbillon à plat (texture de vortex qui tourne), au-dessus d'une pièce.
local function vortex(parent: BasePart, size: number, color: Color3, rate: number, lifetime: number): ParticleEmitter
	return VfxKit.emitter(parent, {
		Texture = T.vortex,
		Color = ColorSequence.new(color),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Speed = NumberRange.new(0.01),
		Rate = rate,
		Lifetime = NumberRange.new(lifetime),
		Size = NumberSequence.new(size),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(220, 300),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) }),
	})
end

-- Onde de rupture : coque, lentille de verre, onde de choc à plat, éclats noirs, éclair violet.
local function ruptureWave(center: Vector3, radius: number, palette: any, detail: number, strength: number)
	local shell = ball("RuptureShell", 1, palette.main, Enum.Material.ForceField, 0.7, 0.1)
	shell.CFrame = CFrame.new(center)
	VfxKit.tween(shell, 0.45, { Size = Vector3.one * radius * 2.2, Transparency = 1 }, Enum.EasingStyle.Quart)
	local lens = ball("RuptureLens", 1, palette.glow, Enum.Material.Glass, 0.6, 0.55)
	lens.CFrame = CFrame.new(center)
	VfxKit.tween(lens, 0.35, { Size = Vector3.one * radius * 1.6, Transparency = 1 }, Enum.EasingStyle.Quart)
	VfxKit.burst(center, 2, {
		Texture = T.shockwave,
		Color = ColorSequence.new(palette.glow, palette.main),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.4),
		Size = NumberSequence.new(0.5, radius * 2.6),
		Transparency = NumberSequence.new(0.1, 1),
	})
	VfxKit.shatter(center, VfxKit.count(8 * strength, detail, 3), VOID_BLACK, Enum.Material.SmoothPlastic, 0.4, 12 + radius, 0.6)
	VfxKit.shatter(center, VfxKit.count(4 * strength, detail, 2), palette.main, Enum.Material.Neon, 0.25, 14 + radius, 0.5)
	VfxKit.burst(center, 30 * detail * strength, {
		Texture = T.spark,
		Color = ColorSequence.new(palette.glow, palette.main),
		Speed = NumberRange.new(radius * 1.5, radius * 3.5),
		Drag = 4,
		Lifetime = NumberRange.new(0.25, 0.5),
		Size = NumberSequence.new(0.5, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	VfxKit.flash(center, palette.main, radius * 4, 4, 0.4, detail)
end

-- Fragments en orbite autour de `center` (plans inclinés), mis à jour image par image.
type Orbiter = { part: Part, plane: CFrame, speed: number, radius: number, phase: number }
local function orbiters(center: Vector3, count: number, rings: number, radius: number, palette: any, lifetime: number): { Orbiter }
	local list: { Orbiter } = {}
	for index = 1, count do
		local ring = (index - 1) % rings
		local plane = CFrame.Angles(math.rad(60 + ring * 35), math.rad(ring * 70), 0)
		local dark = index % 3 ~= 0
		local size = random:NextNumber(0.25, 0.5)
		local part = VfxKit.part("VoidShard", Vector3.new(size, size, size * 1.8), if dark then VOID_BLACK else palette.main, if dark then Enum.Material.SmoothPlastic else Enum.Material.Neon, lifetime)
		table.insert(list, { part = part, plane = plane, speed = random:NextNumber(5, 8) * (if ring % 2 == 0 then 1 else -1), radius = radius * random:NextNumber(0.85, 1.15), phase = random:NextNumber(0, math.pi * 2) })
		part.CFrame = CFrame.new(center)
	end
	return list
end

local function placeOrbiters(list: { Orbiter }, center: Vector3, elapsed: number, radiusScale: number)
	for _, orbiter in list do
		if orbiter.part.Parent then
			local angle = orbiter.phase + elapsed * orbiter.speed
			local offset = orbiter.plane:VectorToWorldSpace(Vector3.new(math.cos(angle), 0, math.sin(angle)) * orbiter.radius * radiusScale)
			local position = center + offset
			orbiter.part.CFrame = CFrame.lookAt(position, position + orbiter.plane:VectorToWorldSpace(Vector3.new(-math.sin(angle), 0, math.cos(angle))))
		end
	end
end

--------------------------------------------------------------------------------
-- Préparation dans la main (commune aux deux sorts, plus ou moins forte)
--------------------------------------------------------------------------------

local function handCharge(caster: Model?, palette: any, duration: number, size: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("VoidCharge", Vector3.one * 2.6, palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.6, -0.4), duration)
	local core = ball("ChargingVoid", 0.1, VOID_BLACK, Enum.Material.SmoothPlastic, duration + 0.05, 0)
	VfxKit.follow(core, holder, CFrame.new(), duration)
	VfxKit.tween(core, duration, { Size = Vector3.one * size }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local rim = ball("ChargingRim", 0.2, palette.main, Enum.Material.ForceField, duration + 0.05, 0.2)
	VfxKit.follow(rim, holder, CFrame.new(), duration)
	VfxKit.tween(rim, duration, { Size = Vector3.one * size * 1.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	VfxKit.emitter(holder, {
		Texture = T.spark,
		Color = ColorSequence.new(palette.glow, palette.main),
		Rate = 55 * detail,
		Lifetime = NumberRange.new(0.2, 0.28),
		Speed = NumberRange.new(6, 9),
		Size = NumberSequence.new(0.05, 0.3),
		Transparency = NumberSequence.new(0.9, 0),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	})
end

--------------------------------------------------------------------------------
-- Fragment du Vide
--------------------------------------------------------------------------------

local function fragmentCharge(caster: Model?, _spell: any, palette: any, duration: number)
	handCharge(caster, palette, duration, 0.8)
end

local function fragmentProjectile(palette: any, _spell: any): BasePart
	local root = VfxKit.part("VoidFragment", Vector3.one * 0.3, palette.main, Enum.Material.SmoothPlastic, 3)
	root.Transparency = 1
	attachBall(root, "Core", 0.9, VOID_BLACK, Enum.Material.SmoothPlastic, 0)
	attachBall(root, "Lens", 1.4, palette.glow, Enum.Material.Glass, 0.55)
	attachBall(root, "Shell", 1.9, palette.main, Enum.Material.ForceField, 0.25)
	local detail = VfxKit.detail(nil)
	darkMatter(root, 45 * detail, { Speed = NumberRange.new(0.5, 1.5) })
	VfxKit.emitter(root, {
		Texture = T.spark,
		Color = ColorSequence.new(palette.glow, palette.main),
		Rate = 25 * detail,
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(0.3, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	return root
end

local function fragmentImpact(spell: any, position: Vector3, targets: { Model }, _caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	-- Contraction : la sphère enfle, puis s'effondre sur elle-même...
	local core = ball("VoidFold", 0.9, VOID_BLACK, Enum.Material.SmoothPlastic, 0.4, 0)
	core.CFrame = CFrame.new(position)
	local rim = ball("VoidFoldRim", 1.6, palette.main, Enum.Material.ForceField, 0.4, 0.1)
	rim.CFrame = CFrame.new(position)
	VfxKit.tween(core, 0.06, { Size = Vector3.one * 2 })
	VfxKit.tween(rim, 0.06, { Size = Vector3.one * 3 })
	task.delay(0.06, function()
		VfxKit.tween(core, 0.09, { Size = Vector3.one * 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		VfxKit.tween(rim, 0.09, { Size = Vector3.one * 0.2, Transparency = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	-- ... puis l'onde de rupture part.
	task.delay(0.15, function()
		core:Destroy()
		rim:Destroy()
		ruptureWave(position, spell.radius, palette, detail, 1)
		for _, target in targets do
			CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(8, detail))
		end
		SfxPlayer.play("impact_antimatter", position)
	end)
end

--------------------------------------------------------------------------------
-- Singularité Mineure
--------------------------------------------------------------------------------

local SINGULARITY_HEIGHT = 3

local function singularityCharge(caster: Model?, _spell: any, palette: any, duration: number)
	handCharge(caster, palette, duration, 1.1)
end

local function singularityTelegraph(spell: any, aimPoint: Vector3, palette: any)
	local duration = math.max(spell.castTime, 0.2)
	local detail = VfxKit.detail(aimPoint)
	local center = aimPoint + Vector3.new(0, SINGULARITY_HEIGHT, 0)
	local seed = ball("SingularitySeed", 0.15, VOID_BLACK, Enum.Material.SmoothPlastic, duration + 0.1, 0)
	seed.CFrame = CFrame.new(center)
	VfxKit.tween(seed, duration, { Size = Vector3.one * 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- L'espace se bombe : une lentille de verre qui gonfle autour du point.
	local lens = ball("SingularityLens", 0.5, palette.glow, Enum.Material.Glass, duration + 0.1, 0.8)
	lens.CFrame = CFrame.new(center)
	VfxKit.tween(lens, duration, { Size = Vector3.one * 6, Transparency = 0.6 }, Enum.EasingStyle.Sine)
	-- La poussière du sol commence à converger (zone lisible, sans disque).
	local dust = VfxKit.part("SingularityDust", Vector3.new(spell.radius * 2, 0.4, spell.radius * 2), palette.main, Enum.Material.SmoothPlastic, duration + 1.5)
	dust.Transparency = 1
	dust.CFrame = CFrame.new(aimPoint + Vector3.new(0, 0.3, 0))
	local emitter = darkMatter(dust, 40 * detail, {
		Shape = Enum.ParticleEmitterShape.Box,
		Speed = NumberRange.new(0.2, 0.5),
		Lifetime = NumberRange.new(0.6, 0.9),
		Acceleration = Vector3.new(0, 6, 0),
		Size = NumberSequence.new(0.3, 0.1),
	})
	task.delay(duration + 0.6, function()
		emitter.Enabled = false
	end)
end

local function singularityImpact(spell: any, position: Vector3, targets: { Model }, _caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local center = position + Vector3.new(0, SINGULARITY_HEIGHT, 0)
	local pull = 0.8
	for _, application in spell.statuses do
		if application.id == "pull" and application.duration then
			pull = application.duration
		end
	end
	local lifetime = pull + 0.6

	-- Le cœur, la lentille qui brouille, la coque qui ondule.
	local core = ball("Singularity", 1.6, VOID_BLACK, Enum.Material.SmoothPlastic, lifetime, 0)
	core.CFrame = CFrame.new(center)
	local lens = ball("SingularityLens", 5, palette.glow, Enum.Material.Glass, lifetime, 0.6)
	lens.CFrame = CFrame.new(center)
	local shell = ball("SingularityShell", 6.5, palette.main, Enum.Material.ForceField, lifetime, 0.35)
	shell.CFrame = CFrame.new(center)
	vortex(core, 7, palette.main, 6 * math.max(detail, 0.5), 0.5)
	local stream = darkMatter(shell, 70 * detail, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(6, 9),
		Lifetime = NumberRange.new(0.35, 0.45),
	})
	local sparks = VfxKit.emitter(shell, {
		Texture = T.spark,
		Color = ColorSequence.new(palette.glow, palette.main),
		Rate = 40 * detail,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(7, 10),
		Lifetime = NumberRange.new(0.3, 0.4),
		Size = NumberSequence.new(0.3, 0.05),
		Transparency = NumberSequence.new(0.2, 1),
	})
	local rings = orbiters(center, VfxKit.count(12, detail, 4), 3, 3.4, palette, lifetime)
	local wobble = VfxKit.animate(pull, function(_alpha: number, elapsed: number)
		local pulse = 1 + math.sin(elapsed * 25) * 0.05
		shell.CFrame = CFrame.new(center) * CFrame.Angles(math.sin(elapsed * 31) * 0.1, elapsed * 4, math.cos(elapsed * 27) * 0.1)
		shell.Size = Vector3.one * 6.5 * pulse
		placeOrbiters(rings, center, elapsed, 1)
	end, core)

	-- Liens vers les ennemis RÉELLEMENT aspirés ; un boss (immunisé) rompt le sien aussitôt.
	local coreAttachment = Instance.new("Attachment")
	coreAttachment.Parent = core
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot == nil then
			continue
		end
		local attachment = VfxKit.point(targetRoot.Position, pull)
		VfxKit.follow(attachment.Parent :: BasePart, targetRoot, CFrame.new(), pull)
		local resists = isBoss(target) or targetRoot.Anchored
		local beam = VfxKit.tether(attachment, coreAttachment, ColorSequence.new(palette.main, palette.glow), 0.12, 0.45, if resists then 0.15 else pull, random:NextNumber(-2, 2))
		beam.Segments = 20
		if resists then
			VfxKit.burst(targetRoot.Position, 10 * detail, { Texture = T.spark, Color = ColorSequence.new(palette.glow), Speed = NumberRange.new(6, 12), Drag = 4, Lifetime = NumberRange.new(0.2, 0.35), Size = NumberSequence.new(0.3, 0), Transparency = NumberSequence.new(0, 1) })
		else
			-- Traînée de matière arrachée à la cible, tirée vers le centre.
			local toward = (center - targetRoot.Position)
			darkMatter(attachment.Parent :: BasePart, 30 * detail, {
				Acceleration = if toward.Magnitude > 0.1 then toward.Unit * 40 else Vector3.zero,
				Speed = NumberRange.new(0.5, 1),
				Lifetime = NumberRange.new(0.3, 0.45),
				Size = NumberSequence.new(0.45, 0.1),
			})
		end
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
	end

	-- Contraction, puis implosion finale.
	task.delay(pull, function()
		wobble:Disconnect()
		stream.Enabled = false
		sparks.Enabled = false
		VfxKit.tween(core, 0.12, { Size = Vector3.one * 2.6 })
		VfxKit.tween(lens, 0.12, { Size = Vector3.one * 1.2, Transparency = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		VfxKit.tween(shell, 0.12, { Size = Vector3.one * 2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		VfxKit.animate(0.2, function(alpha: number, elapsed: number)
			placeOrbiters(rings, center, pull + elapsed * 2, 1 - alpha * 0.9)
		end)
		task.delay(0.12, function()
			VfxKit.tween(core, 0.08, { Size = Vector3.one * 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		task.delay(0.2, function()
			for _, orbiter in rings do
				orbiter.part:Destroy()
			end
			core:Destroy()
			lens:Destroy()
			shell:Destroy()
			ruptureWave(center, spell.radius * 0.7, palette, detail, 1.4)
			local intensity = CombatEffects.intensityAt(center, spell.radius * 2)
			if intensity > 0 then
				CombatEffects.shake(0.22, 0.3 * intensity)
			end
			SfxPlayer.play("impact_antimatter", center)
		end)
	end)
end

--------------------------------------------------------------------------------
-- Rupture du Néant (ultime)
--------------------------------------------------------------------------------

function Antimatter.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.75
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local center = origin + Vector3.new(0, 4, 0)
	local lifetime = windup + 1.5
	local ignore: { Instance } = { VfxKit.folder() }
	if caster then
		table.insert(ignore, caster)
	end
	for _, target in targets do
		table.insert(ignore, target)
	end
	local ground = VfxKit.groundBelow(origin, ignore)

	-- 1. Concentration : cœur qui grossit, espace qui se comprime (lentille qui se resserre).
	local core = ball("VoidCore", 0.3, VOID_BLACK, Enum.Material.SmoothPlastic, lifetime, 0)
	core.CFrame = CFrame.new(center)
	VfxKit.tween(core, windup, { Size = Vector3.one * 3.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local lens = ball("Distortion", 16, palette.glow, Enum.Material.Glass, lifetime, 0.85)
	lens.CFrame = CFrame.new(center)
	VfxKit.tween(lens, windup, { Size = Vector3.one * 4.5, Transparency = 0.45 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local shell = ball("VoidShell", 9, palette.main, Enum.Material.ForceField, lifetime, 0.6)
	shell.CFrame = CFrame.new(center)
	vortex(core, 10, palette.main, 8 * math.max(detail, 0.5), 0.6)
	local sink = VfxKit.part("VoidSink", Vector3.one * radius * 1.2, palette.main, Enum.Material.SmoothPlastic, lifetime)
	sink.Transparency = 1
	sink.CFrame = CFrame.new(center)
	local inflow = darkMatter(sink, 90 * detail, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(radius * 0.8, radius * 1),
		Lifetime = NumberRange.new(0.6, 0.7),
		Size = NumberSequence.new(0.6, 0.15),
	})
	if VfxKit.rich(detail) then
		local light = Instance.new("PointLight")
		light.Color = palette.main
		light.Range = 24
		light.Brightness = 0.5
		light.Shadows = false
		light.Parent = core
		VfxKit.tween(light, windup, { Brightness = 3 })
	end

	-- Matière obscure tirée en spirale de toute la zone vers le cœur.
	type Mote = { part: Part, start: Vector3, angle: number }
	local motes: { Mote } = {}
	for index = 1, VfxKit.count(14, detail, 5) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(radius * 0.3, radius * 0.6)
		local start = origin + Vector3.new(math.cos(angle) * distance, random:NextNumber(0.5, 3), math.sin(angle) * distance)
		local dark = index % 4 ~= 0
		local size = random:NextNumber(0.4, 0.9)
		local mote = VfxKit.part("VoidMote", Vector3.new(size, size, size * 1.6), if dark then VOID_BLACK else palette.main, if dark then Enum.Material.SmoothPlastic else Enum.Material.Neon, windup + 0.2)
		mote.CFrame = CFrame.new(start)
		table.insert(motes, { part = mote, start = start, angle = angle })
	end
	local spiral = VfxKit.animate(windup, function(alpha: number, elapsed: number)
		local eased = alpha * alpha
		for _, mote in motes do
			if mote.part.Parent then
				local offset = mote.start - center
				local swirl = CFrame.Angles(0, eased * 4 + mote.angle * 0.1, 0)
				local position = center + swirl:VectorToWorldSpace(offset * (1 - eased))
				mote.part.CFrame = CFrame.lookAt(position, center) * CFrame.Angles(0, 0, elapsed * 6)
			end
		end
		shell.CFrame = CFrame.new(center) * CFrame.Angles(math.sin(elapsed * 37) * 0.08, elapsed * 5, math.cos(elapsed * 33) * 0.08)
		shell.Size = Vector3.one * (9 - eased * 4.5) * (1 + math.sin(elapsed * 30) * 0.04)
	end, core)

	-- Liens vers les cibles.
	local coreAttachment = Instance.new("Attachment")
	coreAttachment.Parent = core
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot then
			local attachment = Instance.new("Attachment")
			attachment.Name = "VoidTether"
			attachment.Parent = targetRoot
			game:GetService("Debris"):AddItem(attachment, windup + 0.1)
			local beam = VfxKit.tether(attachment, coreAttachment, ColorSequence.new(palette.main, palette.glow), 0.06, 0.4, windup + 0.05, random:NextNumber(-3, 3))
			beam.Transparency = NumberSequence.new(0.5, 0.1)
		end
	end
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.5 * intensity, windup, 0.6)
		CombatEffects.shake(windup, 0.12 * intensity)
		-- Instant de silence juste avant la libération (joueurs proches seulement).
		task.delay(math.max(windup - 0.3, 0), function()
			AudioMixer.duck(0.15, 0.15, 0.3, 0.9)
		end)
	end

	task.wait(windup)
	spiral:Disconnect()
	inflow.Enabled = false
	for _, mote in motes do
		mote.part:Destroy()
	end

	-- 2. Effondrement du cœur...
	VfxKit.tween(core, 0.06, { Size = Vector3.one * 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	VfxKit.tween(lens, 0.06, { Size = Vector3.one * 0.6 })
	VfxKit.tween(shell, 0.06, { Size = Vector3.one * 0.8 })
	task.wait(0.06)
	core:Destroy()
	lens:Destroy()
	shell:Destroy()

	-- 3. ... et libération : onde géante, fissures sombres, éclats.
	ruptureWave(center, radius, palette, detail, 2.5)
	local wave = ball("VoidWave", 2, palette.glow, Enum.Material.ForceField, 0.8, 0)
	wave.CFrame = CFrame.new(center)
	VfxKit.tween(wave, 0.55, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	VfxKit.burst(center, 24 * detail, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(palette.main, VOID_BLACK),
		Speed = NumberRange.new(radius * 0.3, radius * 0.9),
		Drag = 2,
		Lifetime = NumberRange.new(0.8, 1.4),
		Rotation = NumberRange.new(0, 360),
		Size = NumberSequence.new(3, 9),
		Transparency = NumberSequence.new(0.4, 1),
	})
	-- Fissures : lames sombres qui rayonnent au sol puis s'effacent (décor, sans collision).
	local cracks = VfxKit.count(10, detail, 4)
	for index = 1, cracks do
		local angle = index / cracks * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local length = random:NextNumber(radius * 0.25, radius * 0.5)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local crack = VfxKit.part("VoidCrack", Vector3.new(0.5, 0.08, 0.1), VOID_BLACK, Enum.Material.SmoothPlastic, 2.2)
		crack.CFrame = CFrame.lookAt(ground + Vector3.new(0, 0.06, 0), ground + Vector3.new(0, 0.06, 0) + direction)
		local glow = VfxKit.attach(crack, "Part", "CrackGlow", Vector3.new(0.18, 0.1, 0.1), CFrame.new(0, 0.02, 0), palette.main, Enum.Material.Neon)
		local finalCFrame = CFrame.lookAt(ground + Vector3.new(0, 0.06, 0) + direction * length / 2, ground + Vector3.new(0, 0.06, 0) + direction * length)
		VfxKit.tween(crack, 0.18, { Size = Vector3.new(random:NextNumber(0.4, 0.8), 0.08, length), CFrame = finalCFrame })
		VfxKit.tween(glow, 0.18, { Size = Vector3.new(0.18, 0.1, length * 0.9) })
		task.delay(0.9, function()
			VfxKit.fadeGroup(crack, 1.1)
		end)
	end
	-- Les survivants sont tirés vers le lanceur par le serveur : traînées vers lui.
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot and not targetRoot.Anchored then
			local toward = origin - targetRoot.Position
			if toward.Magnitude > 3 then
				local trail = VfxKit.point(targetRoot.Position, 0.5)
				VfxKit.follow(trail.Parent :: BasePart, targetRoot, CFrame.new(), 0.4)
				darkMatter(trail.Parent :: BasePart, 50 * detail, { Acceleration = -toward.Unit * 30, Lifetime = NumberRange.new(0.25, 0.35), Size = NumberSequence.new(0.6, 0.1) })
			end
			CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(8, detail))
		end
	end
	SfxPlayer.play("impact_antimatter", center)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.7 * intensity, 0.04, 0.7)
		CombatEffects.shake(0.4, 0.8 * intensity)
	end
end

--------------------------------------------------------------------------------

Antimatter.spells = {
	void_fragment = { charge = fragmentCharge, projectile = fragmentProjectile, impact = fragmentImpact },
	minor_singularity = { charge = singularityCharge, telegraph = singularityTelegraph, impact = singularityImpact },
}

return Antimatter
