--!strict
--[[
	Vfx/Pyromancy (ModuleScript, client)
	Effets de la PYROMANCIE, joués sur les événements du serveur. Les flammes sont de VRAIES flammes
	animées (effet Fire de Roblox) doublées de particules de feu ; aucune ne blesse : la brûlure est
	posée par le serveur et rendue visible par StatusEffects (flammes sur le corps de la cible).

	Braise Ardente (sort 1, PROJECTILE ; pose « Brûlure », cumulable)
		préparation  une flamme naît dans la paume et grossit, des étincelles y convergent
		vol          boule de feu : noyau incandescent, enveloppe de flammes qui traînent, étincelles
		impact       petite explosion ardente (gerbe de feu, étincelles, fumée), sol roussi
	Cercle Incandescent (sort 2, ZONE AUTOUR DE SOI ; repousse et brûle fort)
		préparation  le sol chauffe autour du lanceur : braises qui montent, petites flammes qui
		             s'allument une à une sur le pourtour de la zone
		impact       langues de feu de hauteurs différentes qui jaillissent du centre vers le bord,
		             sol incandescent, braises qui flottent. La zone n'agit qu'à cet instant (côté
		             serveur) : les flammes retombent en ~1,2 s, la brûlure continue sur les cibles.
	Brasier du Parjure (ultime ; brûlure à 2 crans)
		préparation  cercle de flammes qui monte autour du lanceur, fissures de lave au sol, braises
		             en spirale
		impact       colonne de feu, trois vagues de flammes qui s'éloignent jusqu'au bord de la zone,
		             sol de lave, éclat bref, secousse (sauf effets réduits) ; le sol brûle encore un peu
]]

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Pyromancy = {}

local CORE_YELLOW = Color3.fromRGB(255, 236, 150)
local DEEP_RED = Color3.fromRGB(190, 40, 10)
local ASH = Color3.fromRGB(40, 30, 26)
local LAVA = Color3.fromRGB(255, 90, 20)

local function fireGradient(palette: any): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, CORE_YELLOW),
		ColorSequenceKeypoint.new(0.4, palette.main),
		ColorSequenceKeypoint.new(1, DEEP_RED),
	})
end

-- Gerbe de feu : flammes, étincelles et fumée.
local function fireBurst(position: Vector3, scale: number, palette: any, detail: number)
	VfxKit.burst(position, 18 * detail * scale, {
		Texture = T.fire,
		Color = fireGradient(palette),
		Speed = NumberRange.new(4 * scale, 10 * scale),
		Drag = 5,
		Lifetime = NumberRange.new(0.3, 0.55),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6 * scale), NumberSequenceKeypoint.new(1, 3 * scale) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
	VfxKit.burst(position, 22 * detail * scale, {
		Texture = T.fireSparks,
		Color = ColorSequence.new(CORE_YELLOW, palette.main),
		Speed = NumberRange.new(8 * scale, 18 * scale),
		Drag = 3,
		Acceleration = Vector3.new(0, -12, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = NumberSequence.new(0.35, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	VfxKit.burst(position + Vector3.new(0, 1, 0), 8 * detail * scale, {
		Texture = T.smoke,
		LightEmission = 0,
		Color = ColorSequence.new(ASH),
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 4, 0),
		Lifetime = NumberRange.new(0.8, 1.3),
		Size = NumberSequence.new(1.5 * scale, 4 * scale),
		Transparency = NumberSequence.new(0.5, 1),
		Rotation = NumberRange.new(0, 360),
	})
end

-- Braises qui flottent et montent au-dessus d'une zone pendant `duration`.
local function floatingEmbers(center: Vector3, radius: number, duration: number, rate: number, palette: any)
	local holder = VfxKit.part("Embers", Vector3.new(radius * 2, 0.4, radius * 2), palette.main, Enum.Material.SmoothPlastic, duration + 2)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0))
	local emitter = VfxKit.emitter(holder, {
		Texture = T.fireSparks,
		Color = ColorSequence.new(CORE_YELLOW, palette.main),
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(25, 25),
		Rate = rate,
		Speed = NumberRange.new(2, 5),
		Acceleration = Vector3.new(0, 2, 0),
		Lifetime = NumberRange.new(0.8, 1.6),
		Size = NumberSequence.new(0.25, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	task.delay(duration, function()
		emitter.Enabled = false
	end)
end

--------------------------------------------------------------------------------
-- Braise Ardente
--------------------------------------------------------------------------------

local function emberCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("EmberCharge", Vector3.one * 2.2, palette.main, Enum.Material.SmoothPlastic, duration + 0.2)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.6, -0.3), duration)
	local fire = Instance.new("Fire")
	fire.Size = 1
	fire.Heat = 4
	fire.Color = palette.main
	fire.SecondaryColor = CORE_YELLOW
	fire.Parent = holder
	VfxKit.tween(fire, duration, { Size = 3.5 })
	VfxKit.emitter(holder, {
		Texture = T.fireSparks,
		Color = ColorSequence.new(CORE_YELLOW, palette.main),
		Rate = 45 * detail,
		Lifetime = NumberRange.new(0.18, 0.25),
		Speed = NumberRange.new(5, 8),
		Size = NumberSequence.new(0.05, 0.25),
		Transparency = NumberSequence.new(0.8, 0),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	})
end

local function emberProjectile(palette: any, _spell: any): BasePart
	local root = VfxKit.part("Ember", Vector3.one * 0.3, palette.main, Enum.Material.SmoothPlastic, 3)
	root.Transparency = 1
	local core = VfxKit.attach(root, "Part", "Core", Vector3.one * 0.7, CFrame.new(), CORE_YELLOW, Enum.Material.Neon);
	(core :: Part).Shape = Enum.PartType.Ball
	local shell = VfxKit.attach(root, "Part", "Shell", Vector3.one * 1.25, CFrame.new(), palette.main, Enum.Material.Neon);
	(shell :: Part).Shape = Enum.PartType.Ball
	shell.Transparency = 0.45
	local fire = Instance.new("Fire")
	fire.Size = 3.5
	fire.Heat = 2
	fire.Color = palette.main
	fire.SecondaryColor = CORE_YELLOW
	fire.Parent = root
	local detail = VfxKit.detail(nil)
	VfxKit.emitter(root, {
		Texture = T.fire,
		Color = fireGradient(palette),
		Rate = 40 * detail,
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(0.5, 1.5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
	})
	VfxKit.emitter(root, {
		Texture = T.fireSparks,
		Color = ColorSequence.new(CORE_YELLOW, palette.main),
		Rate = 25 * detail,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(2, 4),
		Acceleration = Vector3.new(0, -8, 0),
		Size = NumberSequence.new(0.25, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	return root
end

local function emberImpact(_spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	fireBurst(position, 1, palette, detail)
	VfxKit.flash(position, palette.main, 14, 3, 0.35, detail)
	local ground = VfxKit.groundBelow(position, VfxKit.ignore(caster, targets))
	VfxKit.groundPatches("Scorch", ground, 1.8, ASH, Enum.Material.Slate, 0.2, VfxKit.count(4, detail, 2), 0.1, 1.2)
	VfxKit.flames(ground + Vector3.new(0, 0.3, 0), 2.5, 4, palette.main, CORE_YELLOW, 0.6, detail)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
	end
	SfxPlayer.play("impact_pyromancy", position)
end

--------------------------------------------------------------------------------
-- Cercle Incandescent
--------------------------------------------------------------------------------

local FLAME_LIFE = 1.2 -- s : la zone n'agit qu'au moment de l'impact (serveur)

local function circleTelegraph(spell: any, aimPoint: Vector3, palette: any)
	local duration = math.max(spell.castTime, 0.2)
	local detail = VfxKit.detail(aimPoint)
	floatingEmbers(aimPoint, spell.radius * 0.8, duration + 0.2, 30 * detail, palette)
	VfxKit.groundPatches("HotGround", aimPoint, spell.radius, DEEP_RED, Enum.Material.Neon, 0.75, VfxKit.count(10, detail, 4), duration, 0.4)
	-- Petites flammes qui s'allument une à une sur le pourtour : la limite du danger.
	local points = VfxKit.count(8, detail, 4)
	for index = 1, points do
		local angle = index / points * math.pi * 2
		local position = aimPoint + Vector3.new(math.cos(angle), 0.2, math.sin(angle)) * spell.radius
		task.delay(duration * (index - 1) / points, function()
			VfxKit.flames(position, 2, 3, palette.main, CORE_YELLOW, duration - duration * (index - 1) / points + 0.15, detail)
		end)
	end
end

local function circleImpact(spell: any, position: Vector3, targets: { Model }, _caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	-- Langues de feu de hauteurs variées, du centre vers le bord.
	local tongues = VfxKit.count(12, detail, 5)
	for index = 1, tongues do
		local angle = index / tongues * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local ring = random:NextNumber(0.35, 1)
		local spot = position + Vector3.new(math.cos(angle) * spell.radius * ring, 0.2, math.sin(angle) * spell.radius * ring)
		task.delay(ring * 0.15, function()
			VfxKit.flames(spot, random:NextNumber(4, 9), random:NextNumber(6, 12), palette.main, CORE_YELLOW, FLAME_LIFE * random:NextNumber(0.7, 1), detail)
		end)
	end
	VfxKit.groundPatches("HotGround", position, spell.radius, LAVA, Enum.Material.Neon, 0.45, VfxKit.count(16, detail, 6), 0.15, FLAME_LIFE)
	floatingEmbers(position, spell.radius, FLAME_LIFE + 0.6, 45 * detail, palette)
	-- Souffle de chaleur qui part vers l'extérieur (repousse, côté serveur).
	VfxKit.burst(position + Vector3.new(0, 1, 0), 26 * detail, {
		Texture = T.fire,
		Color = fireGradient(palette),
		SpreadAngle = Vector2.new(5, 180),
		EmissionDirection = Enum.NormalId.Front,
		Speed = NumberRange.new(spell.radius * 1.5, spell.radius * 2.2),
		Drag = 4,
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = NumberSequence.new(2, 4),
		Transparency = NumberSequence.new(0.2, 1),
		Rotation = NumberRange.new(0, 360),
	})
	VfxKit.flash(position + Vector3.new(0, 2, 0), palette.main, spell.radius * 2.5, 3, 0.6, detail)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(6, detail))
	end
	local intensity = CombatEffects.intensityAt(position, spell.radius * 2)
	if intensity > 0 then
		CombatEffects.shake(0.2, 0.3 * intensity)
	end
	SfxPlayer.play("impact_pyromancy", position)
end

--------------------------------------------------------------------------------
-- Brasier du Parjure (ultime)
--------------------------------------------------------------------------------

function Pyromancy.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.6
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ground = VfxKit.groundBelow(origin, VfxKit.ignore(caster, targets))

	-- 1. Le cercle de flammes monte autour du lanceur.
	local ringFlames = VfxKit.count(8, detail, 4)
	for index = 1, ringFlames do
		local angle = index / ringFlames * math.pi * 2
		local spot = ground + Vector3.new(math.cos(angle) * 3.5, 0.2, math.sin(angle) * 3.5)
		local holder = VfxKit.flames(spot, 2, 4, palette.main, CORE_YELLOW, windup + 0.15, detail)
		local fire = holder:FindFirstChildOfClass("Fire")
		if fire then
			VfxKit.tween(fire, windup, { Size = 9, Heat = 14 })
		end
	end
	-- Fissures de lave qui rayonnent.
	local cracks = VfxKit.count(8, detail, 4)
	for index = 1, cracks do
		local angle = index / cracks * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = random:NextNumber(radius * 0.3, radius * 0.55)
		local base = ground + Vector3.new(0, 0.07, 0)
		local crack = VfxKit.part("LavaCrack", Vector3.new(0.5, 0.1, 0.1), LAVA, Enum.Material.Neon, windup + 2.8)
		crack.CFrame = CFrame.lookAt(base, base + direction)
		VfxKit.tween(crack, windup, { Size = Vector3.new(random:NextNumber(0.35, 0.7), 0.1, length), CFrame = CFrame.lookAt(base + direction * length / 2, base + direction * length) })
		task.delay(windup + 1.4, function()
			if crack.Parent then
				VfxKit.tween(crack, 1.2, { Color = ASH, Transparency = 1 })
			end
		end)
	end
	-- Braises en spirale.
	local spiral = VfxKit.part("FireSpiral", Vector3.new(8, 0.4, 8), palette.main, Enum.Material.SmoothPlastic, windup + 1.5)
	spiral.Transparency = 1
	spiral.CFrame = CFrame.new(ground + Vector3.new(0, 0.5, 0))
	local spiralEmitter = VfxKit.emitter(spiral, {
		Texture = T.fireSparks,
		Color = ColorSequence.new(CORE_YELLOW, palette.main),
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10),
		Rate = 80 * detail,
		Speed = NumberRange.new(8, 14),
		Lifetime = NumberRange.new(0.5, 0.8),
		Size = NumberSequence.new(0.35, 0),
		Transparency = NumberSequence.new(0, 1),
		Rotation = NumberRange.new(0, 360),
	})
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.35 * intensity, windup, 0.8)
		CombatEffects.shake(windup, 0.1 * intensity)
	end

	task.wait(windup)
	spiralEmitter.Enabled = false

	-- 2. Colonne de feu au centre.
	for level = 0, VfxKit.count(3, detail, 2) - 1 do
		VfxKit.flames(ground + Vector3.new(0, 0.5 + level * 4, 0), 12 - level * 2, 20, palette.main, CORE_YELLOW, 1.1, detail)
	end
	fireBurst(origin + Vector3.new(0, 2, 0), 2.5, palette, detail)

	-- 3. Trois vagues de flammes qui s'éloignent jusqu'au bord de la zone.
	local waves = VfxKit.count(3, detail, 2)
	local perWave = VfxKit.count(12, detail, 5)
	VfxKit.reserve(waves * perWave * 2, 1)
	for wave = 1, waves do
		local distance = radius * wave / waves * 0.9
		task.delay(0.1 * wave, function()
			for index = 1, perWave do
				local angle = index / perWave * math.pi * 2 + wave * 0.3
				local spot = ground + Vector3.new(math.cos(angle) * distance, 0.2, math.sin(angle) * distance)
				VfxKit.flames(spot, random:NextNumber(5, 9), random:NextNumber(8, 14), palette.main, CORE_YELLOW, 0.7, detail)
			end
		end)
	end
	VfxKit.groundPatches("HotGround", ground, radius * 0.9, LAVA, Enum.Material.Neon, 0.5, VfxKit.count(20, detail, 8), 0.3, 1.6)
	floatingEmbers(ground, radius * 0.7, 2.2, 50 * detail, palette)
	VfxKit.flash(origin + Vector3.new(0, 4, 0), palette.main, 40, 5, 0.7, detail)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, VfxKit.count(8, detail))
	end
	SfxPlayer.play("impact_pyromancy", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.6 * intensity, 0.04, 0.6)
		CombatEffects.shake(0.45, 0.75 * intensity)
	end
end

--------------------------------------------------------------------------------

Pyromancy.spells = {
	ember = { charge = emberCharge, projectile = emberProjectile, impact = emberImpact },
	blazing_circle = { telegraph = circleTelegraph, impact = circleImpact },
}

return Pyromancy
