--!strict
--[[
	UltimateChoreographies (ModuleScript, client)
	Mises en scène DÉDIÉES des techniques ultimes, enregistrées dans CombatEffects (registerUltimate).
	Chacune suit le même rythme que le serveur : une préparation de `magic.ultimateWindup` secondes
	(posture du lanceur, accumulation lisible), puis l'impact au moment exact où le serveur applique
	dégâts et altération, puis une disparition progressive. Moins de particules, plus de formes :
	disque de givre, cristaux, cœur de vide, onde, liens d'énergie.

		ice        « Hiver Éternel »         givre qui se rassemble, sol qui gèle, cristaux qui jaillissent
		                                     autour du lanceur et emprisonnent les cibles, fonte lente ;
		antimatter « Éruption d'Antimatière » cœur de vide qui grossit, espace comprimé (anneau qui se
		                                     resserre, matière aspirée, liens vers les cibles), implosion
		                                     puis onde violente.
	Tout est local et décoratif (pièces ancrées, intangibles, détruites toutes seules). Mode
	« effets réduits » : moitié moins de cristaux et de particules, voiles d'écran atténués.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local clientFolder = script.Parent.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)

local MagicFx = require(script.Parent:WaitForChild("MagicFx") :: ModuleScript)

local SPARK_TEXTURE = MagicFx.SPARK_TEXTURE
local SMOKE_TEXTURE = MagicFx.SMOKE_TEXTURE
local getFolder, scaled, part, tween, disc = MagicFx.getFolder, MagicFx.scaled, MagicFx.part, MagicFx.tween, MagicFx.disc
local groundBelow, burst, inwardStream, crystal, rootOf = MagicFx.groundBelow, MagicFx.burst, MagicFx.inwardStream, MagicFx.crystal, MagicFx.rootOf
local random = MagicFx.random

local UltimateChoreographies = {}

--------------------------------------------------------------------------------
-- Glace : Hiver Éternel
--------------------------------------------------------------------------------

function UltimateChoreographies.ice(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ignore: { Instance } = { getFolder() }
	if caster then
		table.insert(ignore, caster)
	end
	for _, target in targets do
		table.insert(ignore, target)
	end
	local ground = groundBelow(origin, ignore)

	-- 1. Le froid se rassemble : particules aspirées vers le lanceur, lumière qui monte.
	local stream, shell = inwardStream(origin, 9, ColorSequence.new(palette.glow, palette.main), SPARK_TEXTURE, 55, windup)
	local light = Instance.new("PointLight")
	light.Color = palette.main
	light.Range = 18
	light.Brightness = 0
	light.Parent = shell
	tween(light, windup, { Brightness = 3.5 })

	-- 2. Le sol gèle peu à peu sous le lanceur.
	local floor = disc("FrostFloor", ground, 4, palette.glow, Enum.Material.Ice, windup + 3.5)
	floor.Transparency = 1
	tween(floor, windup, { Size = Vector3.new(0.12, radius * 1.1, radius * 1.1), Transparency = 0.35 }, Enum.EasingStyle.Sine)

	-- 3. Le givre gagne les pieds des cibles (manifestation autour des ennemis).
	task.delay(windup * 0.35, function()
		for _, target in targets do
			local targetRoot = rootOf(target)
			if targetRoot then
				local targetGround = groundBelow(targetRoot.Position, ignore)
				local mark = disc("FrostMark", targetGround, 1, palette.glow, Enum.Material.Ice, windup + 3)
				mark.Transparency = 0.8
				tween(mark, windup * 0.6, { Size = Vector3.new(0.12, 6, 6), Transparency = 0.3 })
			end
		end
	end)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.45 * intensity, windup, 0.9)
	end

	task.wait(windup)
	stream.Enabled = false

	-- 4. Impact : cristaux qui jaillissent en couronne autour du lanceur...
	local spikeCount = scaled(12)
	for index = 1, spikeCount do
		local angle = (index / spikeCount) * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local distance = random:NextNumber(3.5, math.max(5, radius * 0.45))
		local base = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		crystal(base, Vector3.yAxis + outward * 0.45, random:NextNumber(3.5, 6.5), random:NextNumber(0.9, 1.4), palette.glow, 1.1)
	end
	-- ... et emprisonnent les cibles (gel appliqué par le serveur à cet instant).
	for _, target in targets do
		local targetRoot = rootOf(target)
		if targetRoot then
			local targetGround = groundBelow(targetRoot.Position, ignore)
			for index = 1, scaled(5) do
				local angle = (index / 5) * math.pi * 2
				local base = targetGround + Vector3.new(math.cos(angle) * 1.6, 0, math.sin(angle) * 1.6)
				local inward = -Vector3.new(math.cos(angle), 0, math.sin(angle))
				crystal(base, Vector3.yAxis + inward * 0.35, random:NextNumber(3, 4.5), 0.8, palette.glow, 1.5)
			end
			CombatEffects.playHitImpact(target, nil, palette.glow, 6)
		end
	end
	burst(origin, 40, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), palette.glow)
		emitter.Speed = NumberRange.new(radius * 0.8, radius * 1.6)
		emitter.Drag = 3
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Size = NumberSequence.new(0.5, 0)
		emitter.Transparency = NumberSequence.new(0, 1)
	end)
	SfxPlayer.play("impact_ice", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.8 * intensity, 0.04, 0.8)
		CombatEffects.shake(0.35, 0.7 * intensity)
	end
	tween(light, 1.2, { Brightness = 0 })

	-- 5. Fonte : le sol gelé s'efface lentement.
	task.delay(1.6, function()
		if floor.Parent then
			tween(floor, 1.6, { Transparency = 1 }, Enum.EasingStyle.Sine)
		end
	end)
end

--------------------------------------------------------------------------------
-- Antimatière : Éruption d'Antimatière
--------------------------------------------------------------------------------

function UltimateChoreographies.antimatter(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.2
	local palette = magic.palette
	local radius = magic.radius
	local intensity = CombatEffects.intensityAt(origin, radius)
	local center = origin + Vector3.new(0, 1.5, 0)
	local ignore: { Instance } = { getFolder() }
	if caster then
		table.insert(ignore, caster)
	end
	for _, target in targets do
		table.insert(ignore, target)
	end
	local ground = groundBelow(origin, ignore)

	-- 1. Le cœur de vide naît et grossit ; une coque déformante se resserre autour de lui.
	local core = part("VoidCore", Enum.PartType.Ball, Vector3.one * 0.4, palette.void, Enum.Material.SmoothPlastic, windup + 2)
	core.CFrame = CFrame.new(center)
	core.Parent = getFolder()
	tween(core, windup, { Size = Vector3.one * 4.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local distortion = part("Distortion", Enum.PartType.Ball, Vector3.one * 12, palette.main, Enum.Material.ForceField, windup + 2)
	distortion.Transparency = 0.7
	distortion.CFrame = CFrame.new(center)
	distortion.Parent = getFolder()
	tween(distortion, windup, { Size = Vector3.one * 5.5, Transparency = 0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local light = Instance.new("PointLight")
	light.Color = palette.main
	light.Range = 16
	light.Brightness = 0.5
	light.Parent = core
	tween(light, windup, { Brightness = 3 })

	-- 2. L'espace se comprime : anneau au sol qui se resserre, matière aspirée.
	local ring = disc("CompressionRing", ground, radius * 2, palette.main, Enum.Material.Neon, windup + 0.2)
	ring.Transparency = 0.6
	tween(ring, windup, { Size = Vector3.new(0.12, 2, 2), Transparency = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local stream = inwardStream(center, radius * 0.45, ColorSequence.new(palette.glow, palette.main), SPARK_TEXTURE, 60, windup)

	-- 3. Des liens d'énergie relient chaque cible au cœur.
	local coreAttachment = Instance.new("Attachment")
	coreAttachment.Parent = core
	for _, target in targets do
		local targetRoot = rootOf(target)
		if targetRoot then
			local attachment = Instance.new("Attachment")
			attachment.Name = "VoidTether"
			attachment.Parent = targetRoot
			Debris:AddItem(attachment, windup + 0.1)
			local beam = Instance.new("Beam")
			beam.Attachment0 = attachment
			beam.Attachment1 = coreAttachment
			beam.Color = ColorSequence.new(palette.main, palette.glow)
			beam.LightEmission = 1
			beam.Width0 = 0.08
			beam.Width1 = 0.35
			beam.Segments = 12
			beam.CurveSize0 = random:NextNumber(-3, 3)
			beam.CurveSize1 = random:NextNumber(-3, 3)
			beam.FaceCamera = true
			beam.Transparency = NumberSequence.new(0.6, 0.1)
			beam.Parent = core
		end
	end
	if intensity > 0 then
		CombatEffects.tintScreen(palette.main, 0.5 * intensity, windup, 0.6)
		CombatEffects.shake(windup, 0.15 * intensity)
	end

	-- La coque tremble légèrement pendant la compression.
	local startClock = os.clock()
	local wobble = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startClock
		if distortion.Parent then
			distortion.CFrame = CFrame.new(center) * CFrame.Angles(math.sin(t * 40) * 0.05, t * 3, math.cos(t * 37) * 0.05)
		end
	end)

	task.wait(windup)
	wobble:Disconnect()
	stream.Enabled = false

	-- 4. Implosion : tout se replie d'un coup...
	tween(core, 0.07, { Size = Vector3.one * 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(distortion, 0.07, { Size = Vector3.one * 0.5 })
	task.wait(0.07)
	core:Destroy()

	-- 5. ... puis l'onde part, violente.
	local wave = part("VoidWave", Enum.PartType.Ball, Vector3.one * 2, palette.glow, Enum.Material.ForceField, 0.8)
	wave.CFrame = CFrame.new(center)
	wave.Parent = getFolder()
	tween(wave, 0.5, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	local groundWave = disc("VoidGroundWave", ground, 2, palette.main, Enum.Material.Neon, 0.8)
	groundWave.Transparency = 0.15
	tween(groundWave, 0.6, { Size = Vector3.new(0.12, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	tween(distortion, 0.45, { Size = Vector3.one * radius * 1.4, Transparency = 1 }, Enum.EasingStyle.Quart)
	burst(center, 70, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), palette.main)
		emitter.Speed = NumberRange.new(radius * 1.4, radius * 3)
		emitter.Drag = 3
		emitter.Lifetime = NumberRange.new(0.35, 0.7)
		emitter.Size = NumberSequence.new(1.6, 0)
		emitter.Transparency = NumberSequence.new(0, 1)
	end)
	burst(center, 24, function(emitter: ParticleEmitter)
		emitter.Texture = SMOKE_TEXTURE
		emitter.LightEmission = 0
		emitter.Color = ColorSequence.new(palette.main, palette.void)
		emitter.Speed = NumberRange.new(radius * 0.3, radius * 0.9)
		emitter.Drag = 2
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Size = NumberSequence.new(3, 9)
		emitter.Transparency = NumberSequence.new(0.4, 1)
	end)
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, 8)
	end
	SfxPlayer.play("impact_antimatter", center)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.9 * intensity, 0.04, 0.7)
		CombatEffects.shake(0.55, 1.1 * intensity)
	end
end

return UltimateChoreographies
