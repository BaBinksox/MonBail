--!strict
--[[
	Vfx/Gravity (ModuleScript, client)
	Effets de la GRAVITÉ, joués sur les événements du serveur. Masse et pression rendues par des
	fragments de roche en lévitation (décor sans collision), de la poussière attirée ou plaquée au
	sol, des ondes de pression et une lentille de verre qui s'écrase. Aucun objet ne pousse ni ne
	blesse : les ralentissements, soulèvements et écrasements sont ceux du serveur.

	Pression Gravitationnelle (sort 1, ZONE CIBLÉE instantanée ; ralentit et use la garde)
		préparation  geste de compression : la poussière converge vers la main ; au point visé, des
		             cailloux se soulèvent et tremblent, la poussière est attirée
		impact       l'espace s'écrase (lentille qui s'aplatit), les cailloux retombent violemment,
		             onde de pression rasante, fissures, secousse légère
	Champ Gravitationnel (sort 2, ZONE PERSISTANTE ~4 s ; ralentit et use la garde à chaque impulsion)
		manifestation  pierres en suspension qui tournent lentement autour du centre, poussière
		             attirée, dôme de verre presque invisible qui marque la limite ; à chaque impulsion
		             du serveur, les pierres plongent et la poussière est plaquée au sol
		fin          les pierres retombent et s'effacent (même si le champ s'arrête plus tôt)
	Effondrement Stellaire (ultime ; soulève 0,35 s puis écrase et cloue au sol)
		préparation  débris qui s'élèvent dans toute la zone, colonnes de poussière, dôme qui se
		             contracte
		impact       onde de pression ; les débris proches des cibles montent avec elles, puis tout
		             s'abat à l'instant de l'écrasement : fissures, poussière, secousse
]]

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Gravity = {}

local DUST = Color3.fromRGB(150, 140, 125)
local CRACK = Color3.fromRGB(28, 26, 30)

-- Temps du serveur (UltimateBehaviors) : soulèvement puis écrasement.
local LIFT_DURATION = 0.35
local SLAM_DURATION = 0.2

local function keyOf(position: Vector3): string
	return string.format("%d:%d:%d", math.floor(position.X + 0.5), math.floor(position.Y + 0.5), math.floor(position.Z + 0.5))
end

local function dust(position: Vector3, amount: number, speed: number, props: { [string]: any }?)
	local base: { [string]: any } = {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(DUST),
		Speed = NumberRange.new(speed * 0.4, speed),
		Drag = 4,
		Lifetime = NumberRange.new(0.6, 1.1),
		Size = NumberSequence.new(1.2, 3.2),
		Transparency = NumberSequence.new(0.35, 1),
		Rotation = NumberRange.new(0, 360),
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	VfxKit.burst(position, amount, base)
end

-- Onde de pression rasante (onde de choc à plat + poussière qui fuse au ras du sol).
local function pressureWave(ground: Vector3, radius: number, palette: any, detail: number)
	VfxKit.burst(ground + Vector3.new(0, 0.3, 0), 2, {
		Texture = T.shockwave,
		Color = ColorSequence.new(palette.glow, palette.main),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.35),
		Size = NumberSequence.new(0.5, radius * 2.4),
		Transparency = NumberSequence.new(0.2, 1),
	})
	dust(ground + Vector3.new(0, 0.5, 0), 20 * detail, radius * 1.6, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(88, 88), -- presque à l'horizontale
		Acceleration = Vector3.new(0, -6, 0),
	})
end

-- Fissures sombres qui rayonnent depuis `ground` (décor plat, sans collision).
local function cracks(ground: Vector3, count: number, length: number, palette: any, life: number)
	for index = 1, count do
		local angle = index / count * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local size = length * random:NextNumber(0.6, 1)
		local base = ground + Vector3.new(0, 0.06, 0)
		local crack = VfxKit.part("GroundCrack", Vector3.new(0.4, 0.08, 0.1), CRACK, Enum.Material.Slate, life + 1.3)
		crack.CFrame = CFrame.lookAt(base, base + direction)
		local seam = VfxKit.attach(crack, "Part", "Seam", Vector3.new(0.12, 0.1, 0.1), CFrame.new(0, 0.02, 0), palette.main, Enum.Material.Neon)
		VfxKit.tween(crack, 0.15, { Size = Vector3.new(random:NextNumber(0.3, 0.6), 0.08, size), CFrame = CFrame.lookAt(base + direction * size / 2, base + direction * size) })
		VfxKit.tween(seam, 0.15, { Size = Vector3.new(0.12, 0.1, size * 0.85) })
		task.delay(life, function()
			if crack.Parent then
				VfxKit.fadeGroup(crack, 1.1)
			end
		end)
	end
end

-- Un caillou qui tombe sur le sol puis s'efface.
local function dropRock(rock: BasePart, groundY: number, duration: number)
	local landing = Vector3.new(rock.Position.X, groundY + rock.Size.Y * 0.4, rock.Position.Z)
	VfxKit.tween(rock, duration, { Position = landing }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(duration + 0.5, function()
		if rock.Parent then
			VfxKit.tween(rock, 0.8, { Transparency = 1 })
		end
	end)
	task.delay(duration + 1.4, function()
		rock:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Pression Gravitationnelle
--------------------------------------------------------------------------------

local pressRocks: { [string]: { BasePart } } = {}

local function pressCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("GravityCharge", Vector3.one * 2.6, palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.6, -0.3), duration)
	VfxKit.emitter(holder, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(DUST),
		Rate = 30 * detail,
		Lifetime = NumberRange.new(0.25, 0.3),
		Speed = NumberRange.new(5, 7),
		Size = NumberSequence.new(0.8, 0.2),
		Transparency = NumberSequence.new(0.6, 0.2),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	})
	-- Compression : une sphère dense qui se resserre dans la main.
	local mass = VfxKit.part("CompressedMass", Vector3.one * 1.4, palette.main, Enum.Material.Glass, duration + 0.05, Enum.PartType.Ball)
	mass.Transparency = 0.4
	VfxKit.follow(mass, holder, CFrame.new(), duration)
	VfxKit.tween(mass, duration, { Size = Vector3.one * 0.45, Transparency = 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local function pressTelegraph(spell: any, aimPoint: Vector3, palette: any)
	local duration = math.max(spell.castTime, 0.2)
	local detail = VfxKit.detail(aimPoint)
	local rocks: { BasePart } = {}
	local count = VfxKit.count(5, detail, 2)
	for _ = 1, count do
		local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * spell.radius * 0.8
		local rock = VfxKit.rock(aimPoint + offset + Vector3.new(0, 0.2, 0), random:NextNumber(0.4, 0.8), duration + 2)
		local lifted = rock.Position + Vector3.new(0, random:NextNumber(0.6, 1.4), 0)
		VfxKit.tween(rock, duration, { Position = lifted }, Enum.EasingStyle.Sine)
		table.insert(rocks, rock)
	end
	pressRocks[keyOf(aimPoint)] = rocks
	-- Poussière attirée vers le point.
	local well = VfxKit.part("PressureWell", Vector3.one * spell.radius * 2, palette.main, Enum.Material.SmoothPlastic, duration + 0.5)
	well.Transparency = 1
	well.CFrame = CFrame.new(aimPoint + Vector3.new(0, 0.5, 0))
	local inflow = VfxKit.emitter(well, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(DUST),
		Rate = 25 * detail,
		Lifetime = NumberRange.new(0.4, 0.5),
		Speed = NumberRange.new(spell.radius * 1.5, spell.radius * 2),
		Size = NumberSequence.new(1, 0.3),
		Transparency = NumberSequence.new(0.7, 0.3),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	})
	task.delay(duration, function()
		inflow.Enabled = false
	end)
	-- Filet de sécurité : sort annulé (aucun impact) -> les cailloux retombent quand même.
	task.delay(duration + 1, function()
		local pending = pressRocks[keyOf(aimPoint)]
		if pending == rocks then
			pressRocks[keyOf(aimPoint)] = nil
			for _, rock in rocks do
				if rock.Parent then
					dropRock(rock, aimPoint.Y, 0.3)
				end
			end
		end
	end)
end

local function pressImpact(spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local ground = VfxKit.groundBelow(position + Vector3.new(0, 1, 0), VfxKit.ignore(caster, targets))
	-- L'espace s'écrase : une lentille de verre aplatie vers le sol.
	local lens = VfxKit.part("PressureLens", Vector3.new(spell.radius * 2, spell.radius * 1.4, spell.radius * 2), palette.glow, Enum.Material.Glass, 0.5)
	lens.Transparency = 0.6
	lens.CFrame = CFrame.new(ground + Vector3.new(0, spell.radius * 0.9, 0))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = lens
	VfxKit.tween(lens, 0.14, { Size = Vector3.new(spell.radius * 2.4, 0.3, spell.radius * 2.4), CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)), Transparency = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- Les cailloux soulevés retombent violemment.
	local key = keyOf(position)
	local rocks = pressRocks[key]
	pressRocks[key] = nil
	if rocks then
		for _, rock in rocks do
			if rock.Parent then
				dropRock(rock, ground.Y, 0.12)
			end
		end
	end
	task.delay(0.12, function()
		pressureWave(ground, spell.radius, palette, detail)
		cracks(ground, VfxKit.count(5, detail, 3), spell.radius * 0.9, palette, 1)
		for _, target in targets do
			local targetRoot = VfxKit.rootOf(target)
			if targetRoot then
				dust(targetRoot.Position, 8 * detail, 4, { Acceleration = Vector3.new(0, -30, 0) })
			end
			CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
		end
		local intensity = CombatEffects.intensityAt(position, spell.radius * 3)
		if intensity > 0 then
			CombatEffects.shake(0.15, 0.25 * intensity)
		end
	end)
	SfxPlayer.play("impact_gravity", position)
end

--------------------------------------------------------------------------------
-- Champ Gravitationnel
--------------------------------------------------------------------------------

type Field = { stop: () -> () }
local fields: { [string]: Field } = {}

local function fieldTelegraph(spell: any, aimPoint: Vector3, palette: any)
	local detail = VfxKit.detail(aimPoint)
	local life = spell.castTime + spell.pulses * spell.pulseInterval
	local radius = spell.radius
	local key = keyOf(aimPoint)
	-- Dôme presque invisible qui marque la limite (une demi-sphère de verre sortant du sol).
	local dome = VfxKit.part("GravityDome", Vector3.one * radius * 2, palette.glow, Enum.Material.Glass, life + 2, Enum.PartType.Ball)
	dome.Transparency = 1
	dome.CFrame = CFrame.new(aimPoint)
	VfxKit.tween(dome, spell.castTime, { Transparency = 0.88 })
	-- Pierres en suspension, en orbite lente.
	type Stone = { part: Part, angle: number, distance: number, height: number, speed: number }
	local stones: { Stone } = {}
	for index = 1, VfxKit.count(9, detail, 4) do
		local rock = VfxKit.rock(aimPoint, random:NextNumber(0.5, 1.2), life + 2.5)
		table.insert(stones, { part = rock, angle = index * 0.7, distance = random:NextNumber(radius * 0.25, radius * 0.85), height = random:NextNumber(1, 3.5), speed = random:NextNumber(0.4, 0.8) })
	end
	-- Poussière attirée vers le centre, au ras du sol.
	local well = VfxKit.part("FieldDust", Vector3.new(radius * 2, 0.6, radius * 2), DUST, Enum.Material.SmoothPlastic, life + 2)
	well.Transparency = 1
	well.CFrame = CFrame.new(aimPoint + Vector3.new(0, 0.4, 0))
	local dustFlow = VfxKit.emitter(well, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(DUST),
		Shape = Enum.ParticleEmitterShape.Box,
		Rate = 18 * detail,
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(0.5, 1),
		Acceleration = Vector3.new(0, -2, 0),
		Size = NumberSequence.new(1, 2),
		Transparency = NumberSequence.new(0.5, 1),
		Rotation = NumberRange.new(0, 360),
	})
	local dip = 0
	local stopped = false
	local motion = VfxKit.animate(life, function(_alpha: number, elapsed: number)
		dip = math.max(dip - 0.05, 0)
		for _, stone in stones do
			local angle = stone.angle + elapsed * stone.speed
			local jitter = Vector3.new(random:NextNumber(-0.05, 0.05), random:NextNumber(-0.05, 0.05), random:NextNumber(-0.05, 0.05))
			local lift = math.min(elapsed / math.max(spell.castTime, 0.1), 1)
			local position = aimPoint + Vector3.new(math.cos(angle) * stone.distance, stone.height * lift - dip, math.sin(angle) * stone.distance) + jitter
			stone.part.CFrame = CFrame.new(position) * CFrame.Angles(elapsed * 0.6, elapsed * 0.4 + stone.angle, 0)
		end
	end, dome)
	-- Impulsions du serveur : les pierres plongent, la poussière est plaquée au sol.
	for pulse = 0, spell.pulses - 1 do
		task.delay(spell.castTime + pulse * spell.pulseInterval, function()
			if stopped then
				return
			end
			dip = 0.9
			dust(aimPoint + Vector3.new(0, 0.5, 0), 6 * detail, radius * 0.8, { EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(88, 88), Acceleration = Vector3.new(0, -8, 0), Lifetime = NumberRange.new(0.4, 0.6) })
			dome.Transparency = 0.8
			VfxKit.tween(dome, spell.pulseInterval * 0.8, { Transparency = 0.88 })
		end)
	end
	local function stop()
		if stopped then
			return
		end
		stopped = true
		motion:Disconnect()
		dustFlow.Enabled = false
		VfxKit.tween(dome, 0.6, { Transparency = 1 })
		task.delay(1.6, function()
			dome:Destroy()
			well:Destroy()
		end)
		local groundY = aimPoint.Y
		for _, stone in stones do
			if stone.part.Parent then
				dropRock(stone.part, groundY, 0.25)
			end
		end
		if fields[key] and fields[key].stop == stop then
			fields[key] = nil
		end
	end
	fields[key] = { stop = stop }
	task.delay(life + 0.2, stop) -- filet de sécurité si l'impact n'arrive pas
end

local function fieldImpact(_spell: any, position: Vector3, targets: { Model }, _caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local field = fields[keyOf(position)]
	if field then
		field.stop()
	end
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot then
			dust(targetRoot.Position, 5 * detail, 3, { Acceleration = Vector3.new(0, -25, 0) })
		end
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(3, detail))
	end
end

--------------------------------------------------------------------------------
-- Effondrement Stellaire (ultime)
--------------------------------------------------------------------------------

function Gravity.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.7
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = VfxKit.ignore(caster, targets)
	local ground = VfxKit.groundBelow(origin, ignore)
	local total = windup + LIFT_DURATION + SLAM_DURATION + 2

	-- 1. Les débris de toute la zone s'élèvent ; colonnes de poussière ; dôme qui se contracte.
	type Debris = { part: Part, rise: Vector3 }
	local debris: { Debris } = {}
	for _ = 1, VfxKit.count(16, detail, 6) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(3, radius * 0.75)
		local start = ground + Vector3.new(math.cos(angle) * distance, 0.3, math.sin(angle) * distance)
		local rock = VfxKit.rock(start, random:NextNumber(0.6, 1.6), total)
		local rise = start + Vector3.new(0, random:NextNumber(2.5, 7), 0)
		local spin = CFrame.Angles(math.rad(random:NextNumber(-90, 90)), math.rad(random:NextNumber(-90, 90)), 0)
		VfxKit.tween(rock, windup, { CFrame = CFrame.new(rise) * (rock.CFrame - rock.Position) * spin }, Enum.EasingStyle.Sine)
		table.insert(debris, { part = rock, rise = rise })
	end
	local columns = VfxKit.part("DustColumns", Vector3.new(radius * 1.4, 0.6, radius * 1.4), DUST, Enum.Material.SmoothPlastic, total)
	columns.Transparency = 1
	columns.CFrame = CFrame.new(ground + Vector3.new(0, 0.4, 0))
	local rising = VfxKit.emitter(columns, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(DUST),
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(8, 8),
		Rate = 30 * detail,
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(5, 9),
		Size = NumberSequence.new(1.5, 3),
		Transparency = NumberSequence.new(0.5, 1),
		Rotation = NumberRange.new(0, 360),
	})
	local dome = VfxKit.part("GravityDome", Vector3.one * radius * 2, palette.glow, Enum.Material.Glass, windup + 0.5, Enum.PartType.Ball)
	dome.Transparency = 0.9
	dome.CFrame = CFrame.new(origin)
	VfxKit.tween(dome, windup, { Size = Vector3.one * 8, Transparency = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.void, 0.45 * intensity, windup, 0.6)
		CombatEffects.shake(windup, 0.12 * intensity)
	end

	task.wait(windup)
	rising.Enabled = false
	dome:Destroy()

	-- 2. Onde de pression ; les débris proches des cibles montent avec elles (soulèvement serveur).
	pressureWave(ground, radius, palette, detail)
	VfxKit.flash(origin + Vector3.new(0, 3, 0), palette.glow, 30, 4, 0.4, detail)
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot then
			for _ = 1, VfxKit.count(2, detail, 1) do
				local rock = VfxKit.rock(targetRoot.Position - Vector3.new(random:NextNumber(-1.5, 1.5), 2.5, random:NextNumber(-1.5, 1.5)), random:NextNumber(0.5, 1), total)
				table.insert(debris, { part = rock, rise = rock.Position + Vector3.new(0, 38 * LIFT_DURATION, 0) })
				VfxKit.tween(rock, LIFT_DURATION, { Position = rock.Position + Vector3.new(0, 38 * LIFT_DURATION, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
			CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
		end
	end

	task.wait(LIFT_DURATION)

	-- 3. Tout s'abat à l'instant de l'écrasement.
	for _, item in debris do
		if item.part.Parent then
			dropRock(item.part, ground.Y, SLAM_DURATION)
		end
	end
	task.wait(SLAM_DURATION)
	cracks(ground, VfxKit.count(10, detail, 4), radius * 0.45, palette, 1.4)
	dust(ground + Vector3.new(0, 1, 0), 30 * detail, radius * 1.2, { EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80) })
	for _, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot then
			dust(targetRoot.Position, 10 * detail, 6)
			VfxKit.shatter(targetRoot.Position - Vector3.new(0, 2, 0), VfxKit.count(4, detail, 2), Color3.fromRGB(86, 80, 74), Enum.Material.Slate, 0.5, 12, 0.7)
		end
	end
	SfxPlayer.play("impact_gravity", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.4 * intensity, 0.04, 0.5)
		CombatEffects.shake(0.45, 0.85 * intensity)
	end
end

--------------------------------------------------------------------------------

Gravity.spells = {
	gravity_press = { charge = pressCharge, telegraph = pressTelegraph, impact = pressImpact },
	gravity_field = { charge = pressCharge, telegraph = fieldTelegraph, impact = fieldImpact },
}

return Gravity
