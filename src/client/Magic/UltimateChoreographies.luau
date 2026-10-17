--!strict
--[[
	UltimateChoreographies (ModuleScript, client)
	Mises en scène DÉDIÉES des techniques ultimes, enregistrées dans CombatEffects (registerUltimate).
	Chacune suit le même rythme que le serveur : une préparation de `magic.ultimateWindup` secondes
	(posture du lanceur, accumulation lisible), puis l'impact au moment exact où le serveur applique
	dégâts et altération, puis une disparition progressive. Moins de particules, plus de formes :
	disque de givre, cristaux, cœur de vide, onde, liens d'énergie.

		ice        « Hiver Éternel »         voir Vfx/Ice ;
		antimatter « Rupture du Néant »       voir Vfx/Antimatter ;
		pyromancy  « Brasier du Parjure »    colonne de flammes qui monte autour du lanceur, sol qui
		                                     rougeoie, puis nova de feu et sol qui brûle encore ;
		lightning  « Jugement Céleste »      ciel qui s'assombrit, cercles de visée sur les cibles, puis
		                                     foudre qui tombe du ciel sur chacune ;
		shadow     « Marée d'Ombres »        flaque d'ombre qui s'étend, vrilles vers les cibles, puis vague
		                                     sombre et vie aspirée vers le lanceur ;
		gravity    « Effondrement Stellaire » poussière qui s'élève, anneaux de gravité empilés, puis dôme
		                                     qui s'abat et fissure le sol (les cibles sont ensuite
		                                     soulevées puis écrasées par le serveur).
	Tout est local et décoratif (pièces ancrées, intangibles, détruites toutes seules). Mode
	« effets réduits » : moitié moins de cristaux et de particules, voiles d'écran atténués.
]]

local Debris = game:GetService("Debris")

local clientFolder = script.Parent.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)

local MagicFx = require(script.Parent:WaitForChild("MagicFx") :: ModuleScript)
local IceVfx = require(script.Parent:WaitForChild("Vfx"):WaitForChild("Ice") :: ModuleScript)
local AntimatterVfx = require(script.Parent:WaitForChild("Vfx"):WaitForChild("Antimatter") :: ModuleScript)

local SPARK_TEXTURE = MagicFx.SPARK_TEXTURE
local SMOKE_TEXTURE = MagicFx.SMOKE_TEXTURE
local getFolder, scaled, part, tween, disc = MagicFx.getFolder, MagicFx.scaled, MagicFx.part, MagicFx.tween, MagicFx.disc
local groundBelow, burst, rootOf = MagicFx.groundBelow, MagicFx.burst, MagicFx.rootOf
local random = MagicFx.random

local UltimateChoreographies = {}

--------------------------------------------------------------------------------
-- Glace : Hiver Éternel
--------------------------------------------------------------------------------

-- Magies 3.0 : la chorégraphie vit dans Vfx/Ice.
UltimateChoreographies.ice = IceVfx.ultimate

--------------------------------------------------------------------------------
-- Antimatière : Rupture du Néant
--------------------------------------------------------------------------------

-- Magies 3.0 : la chorégraphie vit dans Vfx/Antimatter.
UltimateChoreographies.antimatter = AntimatterVfx.ultimate

--------------------------------------------------------------------------------
-- Pyromancie : Brasier du Parjure
--------------------------------------------------------------------------------

local function prepare(caster: Model?, targets: { Model }): { Instance }
	local ignore: { Instance } = { getFolder() }
	if caster then
		table.insert(ignore, caster)
	end
	for _, target in targets do
		table.insert(ignore, target)
	end
	return ignore
end

local function flameEmitter(parent: Instance, palette: any, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(palette.glow, palette.main)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.Acceleration = Vector3.new(0, 14, 0)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Size = NumberSequence.new(0.9, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Rate = scaled(rate)
	emitter.Parent = parent
	return emitter
end

function UltimateChoreographies.pyromancy(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = prepare(caster, targets)
	local ground = groundBelow(origin, ignore)

	-- 1. Le sol rougeoie, une couronne de flammes monte autour du lanceur.
	local glowFloor = disc("EmberFloor", ground, 3, palette.main, Enum.Material.Neon, windup + 3)
	glowFloor.Transparency = 0.9
	tween(glowFloor, windup, { Size = Vector3.new(0.12, 9, 9), Transparency = 0.45 })
	local emitters: { ParticleEmitter } = {}
	for index = 1, scaled(8) do
		local angle = index / 8 * math.pi * 2
		local anchor = part("FlameAnchor", Enum.PartType.Block, Vector3.one * 0.2, palette.main, Enum.Material.SmoothPlastic, windup + 2)
		anchor.Transparency = 1
		anchor.CFrame = CFrame.new(ground + Vector3.new(math.cos(angle) * 3, 0.3, math.sin(angle) * 3))
		anchor.Parent = getFolder()
		table.insert(emitters, flameEmitter(anchor, palette, 18))
	end
	local core = part("FireCore", Enum.PartType.Ball, Vector3.one * 0.5, palette.glow, Enum.Material.Neon, windup + 1)
	core.CFrame = CFrame.new(origin + Vector3.new(0, 4, 0))
	core.Parent = getFolder()
	tween(core, windup, { Size = Vector3.one * 3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local light = Instance.new("PointLight")
	light.Color = palette.main
	light.Range = 22
	light.Brightness = 1
	light.Parent = core
	tween(light, windup, { Brightness = 5 })
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.35 * intensity, windup, 0.5)
	end

	task.wait(windup)
	for _, emitter in emitters do
		emitter.Enabled = false
	end

	-- 2. Nova : un mur de feu court jusqu'au bord de la zone, gerbe de braises.
	core:Destroy()
	local wall = part("FireWall", Enum.PartType.Cylinder, Vector3.new(4, 4, 4), palette.main, Enum.Material.Neon, 0.9)
	wall.Transparency = 0.2
	wall.CFrame = CFrame.new(ground + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	wall.Parent = getFolder()
	tween(wall, 0.55, { Size = Vector3.new(1, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	burst(origin, 60, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(palette.glow, palette.main)
		emitter.Speed = NumberRange.new(radius, radius * 2)
		emitter.Acceleration = Vector3.new(0, 10, 0)
		emitter.Drag = 2
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Size = NumberSequence.new(1.2, 0)
		emitter.Transparency = NumberSequence.new(0, 1)
	end)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, 8)
	end
	SfxPlayer.play("impact_pyromancy", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.7 * intensity, 0.04, 0.6)
		CombatEffects.shake(0.45, 0.8 * intensity)
	end
	-- 3. Le sol brûle encore un moment (la brûlure continue côté serveur).
	tween(glowFloor, 0.3, { Size = Vector3.new(0.12, radius * 1.6, radius * 1.6), Transparency = 0.55 })
	task.delay(1.4, function()
		if glowFloor.Parent then
			tween(glowFloor, 1.4, { Transparency = 1 }, Enum.EasingStyle.Sine)
		end
	end)
end

--------------------------------------------------------------------------------
-- Foudre : Jugement Céleste
--------------------------------------------------------------------------------

local function skyBolt(from: Vector3, to: Vector3, color: Color3)
	local segments = 7
	local previous = from
	for index = 1, segments do
		local point = from:Lerp(to, index / segments)
		if index < segments then
			point += Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))
		end
		local length = (point - previous).Magnitude
		local segment = part("Bolt", Enum.PartType.Block, Vector3.new(0.5, 0.5, length), color, Enum.Material.Neon, 0.35)
		segment.CFrame = CFrame.lookAt((previous + point) / 2, point)
		segment.Parent = getFolder()
		tween(segment, 0.3, { Transparency = 1, Size = Vector3.new(0.1, 0.1, length) })
		previous = point
	end
end

function UltimateChoreographies.lightning(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = prepare(caster, targets)

	-- 1. Le ciel s'assombrit, l'air crépite autour du lanceur, chaque cible est marquée.
	if intensity > 0 then
		CombatEffects.tintScreen(Color3.fromRGB(70, 80, 120), 0.5 * intensity, windup, 0.3)
	end
	burst(origin + Vector3.new(0, 2, 0), 20, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(palette.glow)
		emitter.Speed = NumberRange.new(5, 10)
		emitter.Lifetime = NumberRange.new(0.1, 0.25)
		emitter.Size = NumberSequence.new(0.3, 0)
	end)
	local marks: { Vector3 } = {}
	for _, target in targets do
		local targetRoot = rootOf(target)
		if targetRoot then
			local ground = groundBelow(targetRoot.Position, ignore)
			table.insert(marks, ground)
			local circle = disc("StrikeMark", ground, 7, palette.main, Enum.Material.Neon, windup + 0.3)
			circle.Transparency = 0.85
			tween(circle, windup, { Size = Vector3.new(0.12, 2.5, 2.5), Transparency = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end

	task.wait(windup)

	-- 2. La foudre tombe du ciel sur chaque cible (et un éclair sur le lanceur).
	for _, ground in marks do
		skyBolt(ground + Vector3.new(random:NextNumber(-4, 4), 70, random:NextNumber(-4, 4)), ground, palette.glow)
		local flash = disc("StrikeFlash", ground, 2, palette.glow, Enum.Material.Neon, 0.5)
		tween(flash, 0.35, { Size = Vector3.new(0.12, 8, 8), Transparency = 1 })
	end
	skyBolt(origin + Vector3.new(0, 70, 0), origin, palette.glow)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.glow, 10)
	end
	SfxPlayer.play("impact_lightning", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(Color3.new(1, 1, 1), 0.9 * intensity, 0.03, 0.4)
		CombatEffects.shake(0.3, 0.9 * intensity)
	end
end

--------------------------------------------------------------------------------
-- Ombre : Marée d'Ombres
--------------------------------------------------------------------------------

function UltimateChoreographies.shadow(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = prepare(caster, targets)
	local ground = groundBelow(origin, ignore)

	-- 1. Une flaque d'ombre s'étend sous le lanceur ; des vrilles rampent vers les cibles.
	local pool = disc("ShadowPool", ground, 2, palette.void, Enum.Material.SmoothPlastic, windup + 3)
	pool.Transparency = 0.6
	tween(pool, windup, { Size = Vector3.new(0.12, radius * 1.8, radius * 1.8), Transparency = 0.15 }, Enum.EasingStyle.Sine)
	local casterRoot = caster and rootOf(caster)
	local tetherAnchor = part("ShadowAnchor", Enum.PartType.Block, Vector3.one * 0.2, palette.void, Enum.Material.SmoothPlastic, windup + 1.5)
	tetherAnchor.Transparency = 1
	tetherAnchor.CFrame = CFrame.new(if casterRoot then casterRoot.Position else origin)
	tetherAnchor.Parent = getFolder()
	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Parent = tetherAnchor
	local beams: { Beam } = {}
	for _, target in targets do
		local targetRoot = rootOf(target)
		if targetRoot then
			local attachment = Instance.new("Attachment")
			attachment.Name = "ShadowTendril"
			attachment.Parent = targetRoot
			Debris:AddItem(attachment, windup + 1.2)
			local beam = Instance.new("Beam")
			beam.Attachment0 = anchorAttachment
			beam.Attachment1 = attachment
			beam.Color = ColorSequence.new(palette.void, palette.main)
			beam.Width0 = 0.6
			beam.Width1 = 0.15
			beam.CurveSize0 = random:NextNumber(-4, 4)
			beam.Segments = 14
			beam.Transparency = NumberSequence.new(0.2, 0.5)
			beam.Parent = tetherAnchor
			table.insert(beams, beam)
		end
	end
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.45 * intensity, windup, 0.7)
	end

	task.wait(windup)

	-- 2. La vague sombre se dresse ; la vie des cibles remonte vers le lanceur (vrilles inversées).
	local wave = part("ShadowWave", Enum.PartType.Cylinder, Vector3.new(5, 4, 4), palette.void, Enum.Material.SmoothPlastic, 0.9)
	wave.Transparency = 0.25
	wave.CFrame = CFrame.new(ground + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	wave.Parent = getFolder()
	tween(wave, 0.5, { Size = Vector3.new(1, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	for _, beam in beams do
		beam.Color = ColorSequence.new(palette.glow, palette.main)
		beam.LightEmission = 1
		beam.Width0 = 0.25
		beam.Width1 = 0.6
	end
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, 8)
	end
	SfxPlayer.play("impact_shadow", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.6 * intensity, 0.05, 0.8)
		CombatEffects.shake(0.4, 0.7 * intensity)
	end
	task.delay(0.8, function()
		if pool.Parent then
			tween(pool, 1.4, { Transparency = 1, Size = Vector3.new(0.12, radius * 0.6, radius * 0.6) }, Enum.EasingStyle.Sine)
		end
	end)
end

--------------------------------------------------------------------------------
-- Gravité : Effondrement Stellaire
--------------------------------------------------------------------------------

function UltimateChoreographies.gravity(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = prepare(caster, targets)
	local ground = groundBelow(origin, ignore)

	-- 1. La poussière s'élève, des anneaux de gravité s'empilent au-dessus de la zone.
	burst(ground + Vector3.new(0, 0.5, 0), 30, function(emitter: ParticleEmitter)
		emitter.Texture = SMOKE_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(150, 145, 160))
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.Acceleration = Vector3.new(0, 4, 0)
		emitter.Lifetime = NumberRange.new(windup, windup + 0.4)
		emitter.Size = NumberSequence.new(1, 3)
		emitter.Transparency = NumberSequence.new(0.4, 1)
	end)
	for index = 1, 3 do
		task.delay(windup * (index - 1) / 3, function()
			local ringPart = disc("GravityRing", ground + Vector3.new(0, 3 + index * 2.5, 0), radius * 1.8, palette.main, Enum.Material.Neon, windup + 0.3)
			ringPart.Transparency = 0.85
			tween(ringPart, windup * 0.6, { Transparency = 0.4, Size = Vector3.new(0.12, radius * 1.2, radius * 1.2) })
			task.delay(windup - windup * (index - 1) / 3, function()
				if ringPart.Parent then
					tween(ringPart, 0.12, { CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end)
	end
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.4 * intensity, windup, 0.6)
		CombatEffects.shake(windup, 0.12 * intensity)
	end

	task.wait(windup)

	-- 2. Le dôme s'abat : écrasement, sol fissuré, débris.
	local dome = part("GravityDome", Enum.PartType.Ball, Vector3.one * radius * 2, palette.glow, Enum.Material.ForceField, 0.6)
	dome.Transparency = 0.3
	dome.CFrame = CFrame.new(ground + Vector3.new(0, radius * 0.6, 0))
	dome.Parent = getFolder()
	tween(dome, 0.18, { CFrame = CFrame.new(ground), Size = Vector3.new(radius * 2.2, 2, radius * 2.2), Transparency = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for index = 1, scaled(10) do
		local angle = index / 10 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local length = random:NextNumber(radius * 0.3, radius * 0.8)
		local crack = part("GroundCrack", Enum.PartType.Block, Vector3.new(0.4, 0.15, length), palette.main, Enum.Material.Neon, 2.4)
		crack.Transparency = 0.2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		crack.CFrame = CFrame.lookAt(ground + direction * length / 2 + Vector3.new(0, 0.1, 0), ground + direction * length + Vector3.new(0, 0.1, 0))
		crack.Parent = getFolder()
		task.delay(1, function()
			if crack.Parent then
				tween(crack, 1.2, { Transparency = 1 })
			end
		end)
	end
	burst(ground + Vector3.new(0, 1, 0), 30, function(emitter: ParticleEmitter)
		emitter.Texture = SMOKE_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(140, 135, 150))
		emitter.SpreadAngle = Vector2.new(85, 10)
		emitter.Speed = NumberRange.new(radius * 0.6, radius * 1.2)
		emitter.Drag = 3
		emitter.Lifetime = NumberRange.new(0.8, 1.3)
		emitter.Size = NumberSequence.new(2, 5)
		emitter.Transparency = NumberSequence.new(0.3, 1)
	end)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, 8)
	end
	SfxPlayer.play("impact_gravity", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.6 * intensity, 0.04, 0.6)
		CombatEffects.shake(0.5, 1.2 * intensity)
	end
end

return UltimateChoreographies
