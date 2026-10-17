--!strict
--[[
	Vfx/Ice (ModuleScript, client)
	Effets de la GLACE, joués sur les événements du serveur (SpellCast, SpellImpact, UltimateFired).
	Aucun dégât ni altération ici : ce qui est montré suit ce que le serveur a réellement fait.

	Éclat de Givre (sort 1, projectile rapide, pose « Froid » = ralentissement)
		préparation  un cristal se forme dans la main, le givre converge vers elle
		vol          fragment de glace irrégulier (corps en losange, pointe, éclat secondaire, cœur
		             lumineux), traînée de particules froides
		impact       le cristal éclate en fragments qui retombent, bouffée de givre, plaques de glace
		             qui s'étendent aux pieds de la cible puis fondent
		conséquence  ralentissement visible via StatusEffects (teinte bleutée, givre qui tombe)
	Prison Cristalline (sort 2, zone au point visé, pose « Gel » = immobilisation ; « Froid » sur un boss)
		préparation  le sol se couvre de givre, brume froide, bourgeons de cristal qui poussent un à un
		             sur le pourtour (aucun disque)
		impact       cinq pointes jaillissent l'une après l'autre autour de chaque cible et se
		             referment sur elle ; elles TIENNENT tant que le gel dure (attribut du serveur),
		             puis éclatent. Un boss (converti en simple froid) brise aussitôt sa cage.
	Hiver Éternel (ultime ; pose « Hiver Éternel » = fort ralentissement, pas un gel)
		préparation  voile froid à l'écran, cristaux en suspension qui tournent et montent autour du
		             lanceur, givre qui gagne le sol jusqu'au rayon de l'ultime
		impact       couronne de grandes formations autour du lanceur, trois pointes autour de chaque
		             cible, éclat lumineux bref, légère secousse (sauf effets réduits)
		fin          les formations se fendent et éclatent en fragments, le givre fond
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local StatusConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("StatusConfig") :: ModuleScript)
local BossConfig = require(sharedFolder:WaitForChild("Boss"):WaitForChild("BossConfig") :: ModuleScript)

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Ice = {}

local FROST_WHITE = Color3.fromRGB(235, 248, 255)

local function isBoss(model: Model): boolean
	return CollectionService:HasTag(model, BossConfig.TAG)
end

-- Fin du gel (secondes restantes) d'après l'attribut posé par le serveur, ou nil.
local function freezeRemaining(model: Model): number?
	local untilTime = model:GetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. "freeze")
	if type(untilTime) ~= "number" then
		return nil
	end
	local remaining = untilTime - workspace:GetServerTimeNow()
	return if remaining > 0 then remaining else nil
end

local function ignoreList(caster: Model?, targets: { Model }): { Instance }
	local list: { Instance } = { VfxKit.folder() }
	if caster then
		table.insert(list, caster)
	end
	for _, target in targets do
		table.insert(list, target)
	end
	return list
end

-- Brume froide basse (porteur ancré au sol), coupée après `duration`.
local function coldMist(position: Vector3, radius: number, duration: number, detail: number)
	local anchor = VfxKit.part("ColdMist", Vector3.new(radius * 1.6, 0.2, radius * 1.6), FROST_WHITE, Enum.Material.SmoothPlastic, duration + 2)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0))
	local emitter = VfxKit.emitter(anchor, {
		Texture = T.smoke,
		LightEmission = 0.2,
		Color = ColorSequence.new(FROST_WHITE),
		Rate = 14 * detail,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(70, 70),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	task.delay(duration, function()
		emitter.Enabled = false
	end)
end

-- Bouffée de poudre de glace.
local function icePowder(position: Vector3, amount: number, speed: number)
	VfxKit.burst(position, amount, {
		Texture = T.smoke,
		LightEmission = 0.3,
		Color = ColorSequence.new(FROST_WHITE),
		Speed = NumberRange.new(speed * 0.3, speed),
		Drag = 4,
		Lifetime = NumberRange.new(0.5, 0.9),
		Size = NumberSequence.new(1, 2.6),
		Transparency = NumberSequence.new(0.45, 1),
		Rotation = NumberRange.new(0, 360),
	})
	VfxKit.burst(position, amount * 0.7, {
		Texture = T.spark,
		Color = ColorSequence.new(FROST_WHITE),
		Speed = NumberRange.new(speed * 0.5, speed * 1.4),
		Drag = 5,
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = NumberSequence.new(0.35, 0),
		Transparency = NumberSequence.new(0, 1),
	})
end

-- Une pointe qui jaillit, tient, puis éclate en fragments.
local function growSpire(base: Vector3, direction: Vector3, height: number, width: number, palette: any, hold: number, rise: number, core: boolean, detail: number)
	local up = direction.Unit
	local look = if math.abs(up.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis:Cross(up).Unit
	local pivot = CFrame.fromMatrix(base, look, up) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
	local root = VfxKit.spire(pivot, height, width, palette.glow, rise + hold + 1.5, if core then palette.main else nil)
	VfxKit.erupt(root, height, rise)
	task.delay(rise + hold, function()
		if root.Parent then
			VfxKit.shatter(base + up * height * 0.5, VfxKit.count(5, detail), palette.glow, Enum.Material.Glass, width * 0.7, 10, 0.7)
			root:Destroy()
		end
	end)
	return root
end

--------------------------------------------------------------------------------
-- Éclat de Givre
--------------------------------------------------------------------------------

local function shardCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("ShardCharge", Vector3.one * 2.4, palette.glow, Enum.Material.SmoothPlastic, duration + 0.1)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.6, -0.3), duration)
	local forming = VfxKit.part("FormingCrystal", Vector3.one * 0.1, palette.glow, Enum.Material.Glass, duration + 0.05)
	forming.Transparency = 0.15
	VfxKit.follow(forming, holder, VfxKit.DIAMOND, duration)
	VfxKit.tween(forming, duration, { Size = Vector3.one * 0.55 }, Enum.EasingStyle.Back)
	VfxKit.emitter(holder, {
		Texture = T.spark,
		Color = ColorSequence.new(FROST_WHITE, palette.main),
		Rate = 60 * detail,
		Lifetime = NumberRange.new(0.18, 0.25),
		Speed = NumberRange.new(6, 9),
		Size = NumberSequence.new(0.05, 0.25),
		Transparency = NumberSequence.new(0.9, 0),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, -- de la surface vers la main
	})
end

local function shardProjectile(palette: any, _spell: any): BasePart
	local root = VfxKit.part("FrostShard", Vector3.one * 0.3, palette.glow, Enum.Material.SmoothPlastic, 3)
	root.Transparency = 1
	-- Fragment principal pointé vers l'avant (-Z), légèrement de travers : forme irrégulière.
	local forward = CFrame.Angles(-math.pi / 2, 0, 0)
	VfxKit.attachCrystal(root, CFrame.new(0, 0, 0.9) * forward * CFrame.Angles(0, 0.4, 0.12), 2.1, 0.55, palette.glow, 0.12, palette.main)
	VfxKit.attachCrystal(root, CFrame.new(0.22, 0.12, 0.6) * forward * CFrame.Angles(0.25, 1.1, -0.35), 1.1, 0.3, FROST_WHITE, 0.2)
	VfxKit.attachCrystal(root, CFrame.new(-0.2, -0.1, 0.7) * forward * CFrame.Angles(-0.3, 0.2, 0.4), 0.9, 0.25, palette.glow, 0.2)
	VfxKit.emitter(root, {
		Texture = T.spark,
		Color = ColorSequence.new(FROST_WHITE, palette.main),
		Rate = 40 * VfxKit.detail(nil),
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = Vector3.new(0, -4, 0),
		Size = NumberSequence.new(0.22, 0),
		Transparency = NumberSequence.new(0.1, 1),
	})
	VfxKit.emitter(root, {
		Texture = T.smoke,
		LightEmission = 0.2,
		Color = ColorSequence.new(FROST_WHITE),
		Rate = 14 * VfxKit.detail(nil),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(0, 0.5),
		Size = NumberSequence.new(0.5, 1.4),
		Transparency = NumberSequence.new(0.7, 1),
	})
	return root
end

local function shardImpact(_spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	VfxKit.shatter(position, VfxKit.count(8, detail, 3), palette.glow, Enum.Material.Glass, 0.45, 15, 0.75)
	icePowder(position, 16 * detail, 7)
	VfxKit.flash(position, palette.main, 10, 2.5, 0.35, detail)
	local ignore = ignoreList(caster, targets)
	local firstRoot = if targets[1] then VfxKit.rootOf(targets[1]) else nil
	local where = if firstRoot then firstRoot.Position else position
	VfxKit.frostSpread(VfxKit.groundBelow(where, ignore), 2.4, palette.glow, VfxKit.count(6, detail, 2), 0.2, 0.9)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.glow, VfxKit.count(6, detail))
	end
	SfxPlayer.play("impact_ice", position)
end

--------------------------------------------------------------------------------
-- Prison Cristalline
--------------------------------------------------------------------------------

local function prisonTelegraph(spell: any, aimPoint: Vector3, palette: any)
	local duration = math.max(spell.castTime, 0.2)
	local detail = VfxKit.detail(aimPoint)
	VfxKit.frostSpread(aimPoint, spell.radius, palette.glow, VfxKit.count(14, detail, 4), duration, 0.6)
	coldMist(aimPoint, spell.radius, duration + 0.4, detail)
	-- Bourgeons de cristal sur le pourtour, un à un : la zone se lit sans disque.
	local buds = VfxKit.count(8, detail, 4)
	for index = 1, buds do
		local angle = index / buds * math.pi * 2
		local base = aimPoint + Vector3.new(math.cos(angle), 0, math.sin(angle)) * spell.radius
		task.delay(duration * (index - 1) / buds, function()
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
			growSpire(base, Vector3.yAxis + outward * 0.3, random:NextNumber(0.8, 1.3), 0.35, palette, duration + 0.2, 0.12, false, detail)
		end)
	end
end

local function prisonImpact(spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local ignore = ignoreList(caster, targets)
	icePowder(position + Vector3.new(0, 1, 0), 22 * detail, 12)
	VfxKit.flash(position + Vector3.new(0, 2, 0), palette.main, 16, 3, 0.5, detail)

	-- Quelques pointes dans la zone, même sans cible : la manifestation reste lisible.
	for _ = 1, VfxKit.count(4, detail, 2) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(0.3, 0.85) * spell.radius
		local base = position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		growSpire(base, Vector3.yAxis + Vector3.new(random:NextNumber(-0.2, 0.2), 0, random:NextNumber(-0.2, 0.2)), random:NextNumber(1.8, 2.8), 0.55, palette, 0.7, 0.14, false, detail)
	end

	local fullCages = VfxKit.count(4, detail)
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot == nil then
			continue
		end
		local ground = VfxKit.groundBelow(targetRoot.Position, ignore)
		local resists = isBoss(target)
		local spikes = if index <= fullCages then VfxKit.count(5, detail, 3) else 2
		local cageRadius = math.clamp(target:GetExtentsSize().X * 0.55, 1.4, 3)
		local spires: { BasePart } = {}
		for spike = 1, spikes do
			local angle = spike / spikes * math.pi * 2 + random:NextNumber(-0.2, 0.2)
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local base = ground + outward * cageRadius
			local height = random:NextNumber(3.2, 4.6)
			task.delay((spike - 1) * 0.05, function()
				-- Les pointes se referment sur la cible (inclinées vers elle) ; elles tiennent
				-- longtemps : leur éclatement est décidé plus bas, selon le gel réel.
				local root = growSpire(base, Vector3.yAxis - outward * 0.45, height, 0.8, palette, 6, 0.13, spike == 1, detail)
				table.insert(spires, root)
			end)
		end
		CombatEffects.playHitImpact(target, nil, palette.glow, VfxKit.count(6, detail))
		-- Durée de la cage : celle du gel publié par le serveur ; un boss la brise tout de suite.
		task.delay(0.25, function()
			local hold = if resists then 0.15 else math.clamp(freezeRemaining(target) or 0.4, 0.4, 3)
			task.delay(hold, function()
				for _, root in spires do
					if root.Parent then
						local center = root.Position + root.CFrame.UpVector * 1.5
						VfxKit.shatter(center, VfxKit.count(if resists then 6 else 4, detail), palette.glow, Enum.Material.Glass, 0.5, if resists then 18 else 9, 0.7)
						root:Destroy()
					end
				end
				if resists then
					icePowder(targetRoot.Position, 14 * detail, 14) -- la cage vole en éclats
				end
			end)
		end)
	end
	local intensity = CombatEffects.intensityAt(position, spell.radius * 2)
	if intensity > 0 then
		CombatEffects.shake(0.18, 0.25 * intensity)
	end
	SfxPlayer.play("impact_ice", position)
end

--------------------------------------------------------------------------------
-- Hiver Éternel (ultime)
--------------------------------------------------------------------------------

function Ice.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.85
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore = ignoreList(caster, targets)
	local ground = VfxKit.groundBelow(origin, ignore)

	-- 1. Le froid tombe : voile d'écran, souffle de givre aspiré vers le lanceur.
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.5 * intensity, windup, 1.2)
	end
	local center = VfxKit.part("WinterCore", Vector3.one * 16, palette.glow, Enum.Material.SmoothPlastic, windup + 2)
	center.Transparency = 1
	center.CFrame = CFrame.new(origin + Vector3.new(0, 1, 0))
	local gather = VfxKit.emitter(center, {
		Texture = T.spark,
		Color = ColorSequence.new(FROST_WHITE, palette.main),
		Rate = 70 * detail,
		Lifetime = NumberRange.new(0.5, 0.7),
		Speed = NumberRange.new(12, 16),
		Size = NumberSequence.new(0.1, 0.4),
		Transparency = NumberSequence.new(0.8, 0),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	})
	coldMist(ground, radius * 0.5, windup + 1, detail)
	if VfxKit.rich(detail) then
		local light = Instance.new("PointLight")
		light.Color = palette.main
		light.Range = 22
		light.Brightness = 0
		light.Shadows = false
		light.Parent = center
		VfxKit.tween(light, windup, { Brightness = 4 })
		task.delay(windup, function()
			VfxKit.tween(light, 1.4, { Brightness = 0 })
		end)
	end

	-- 2. Cristaux en suspension : ils tournent autour du lanceur en montant.
	local floaters: { { part: Part, angle: number, distance: number, height: number } } = {}
	for index = 1, VfxKit.count(8, detail, 3) do
		local size = random:NextNumber(0.4, 0.8)
		local crystal = VfxKit.part("FloatingCrystal", Vector3.one * size, palette.glow, Enum.Material.Glass, windup + 0.4)
		crystal.Transparency = 0.15
		table.insert(floaters, { part = crystal, angle = index * 0.8, distance = random:NextNumber(3, 5), height = random:NextNumber(0.5, 2.5) })
	end
	VfxKit.animate(windup, function(alpha: number, elapsed: number)
		for _, floater in floaters do
			local angle = floater.angle + elapsed * 3
			local distance = floater.distance * (1 - alpha * 0.35)
			local position = origin + Vector3.new(math.cos(angle) * distance, floater.height + alpha * 2.5, math.sin(angle) * distance)
			floater.part.CFrame = CFrame.new(position) * VfxKit.DIAMOND * CFrame.Angles(0, elapsed * 4, 0)
		end
	end)

	-- 3. Le givre gagne tout le sol de la zone.
	VfxKit.frostSpread(ground, radius * 0.9, palette.glow, VfxKit.count(26, detail, 8), windup, 2.4)

	task.wait(windup)
	gather.Enabled = false
	-- Les cristaux en suspension partent vers l'extérieur en éclatant.
	for _, floater in floaters do
		if floater.part.Parent then
			VfxKit.shatter(floater.part.Position, 2, palette.glow, Enum.Material.Glass, 0.35, 16, 0.6)
			floater.part:Destroy()
		end
	end

	-- 4. Impact : grandes formations en couronne autour du lanceur...
	local crown = VfxKit.count(8, detail, 4)
	for index = 1, crown do
		local angle = index / crown * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = ground + outward * random:NextNumber(4, math.max(5, radius * 0.35))
		task.delay(random:NextNumber(0, 0.12), function()
			growSpire(base, Vector3.yAxis + outward * 0.5, random:NextNumber(5, 8), random:NextNumber(1.1, 1.6), palette, 1.4, 0.16, true, detail)
		end)
	end
	-- ... et trois pointes autour de chaque cible (ralentie par le serveur à cet instant).
	local framed = VfxKit.count(5, detail, 2)
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot and index <= framed then
			local targetGround = VfxKit.groundBelow(targetRoot.Position, ignore)
			for spike = 1, 3 do
				local angle = spike / 3 * math.pi * 2 + random:NextNumber(0, 1)
				local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
				task.delay(0.04 * spike, function()
					growSpire(targetGround + outward * 2.2, Vector3.yAxis + outward * 0.25, random:NextNumber(3.5, 5), 0.9, palette, 1.2, 0.14, false, detail)
				end)
			end
		end
		if targetRoot then
			CombatEffects.playHitImpact(target, nil, palette.glow, VfxKit.count(6, detail))
		end
	end
	icePowder(origin + Vector3.new(0, 1, 0), 40 * detail, radius * 1.2)
	VfxKit.flash(origin + Vector3.new(0, 3, 0), FROST_WHITE, 30, 5, 0.6, detail)
	SfxPlayer.play("impact_ice", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(FROST_WHITE, 0.55 * intensity, 0.05, 0.9)
		CombatEffects.shake(0.3, 0.55 * intensity)
	end
end

--------------------------------------------------------------------------------

Ice.spells = {
	frost_shard = { charge = shardCharge, projectile = shardProjectile, impact = shardImpact },
	crystal_prison = { telegraph = prisonTelegraph, impact = prisonImpact },
}

return Ice
