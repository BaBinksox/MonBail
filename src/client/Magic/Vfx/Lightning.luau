--!strict
--[[
	Vfx/Lightning (ModuleScript, client)
	Effets de la FOUDRE, joués sur les événements du serveur. Les éclairs suivent les positions
	RÉELLES envoyées par le serveur (point touché, cibles de la chaîne dans l'ordre des rebonds).
	Flashs brefs : lumière courte, voile d'écran léger, rien en « effets réduits » au-delà d'un
	scintillement.

	Arc Électrique (sort 1, INSTANTANÉ, une cible ; pose « Électrisé » = interrompt)
		préparation  crépitement dans la main, petits arcs qui sautent autour d'elle
		manifestation  éclair ramifié de la main au point touché (cœur blanc, halo jaune, branches)
		impact       éclat lumineux, gerbe d'étincelles ; sans cible, l'éclair s'éteint dans le vide
	Chaîne Foudroyante (sort 2, CHAÎNE jusqu'à 4 cibles, -20 % à chaque rebond)
		préparation  aura électrique autour du lanceur, arcs qui courent sur les bras
		manifestation  l'éclair saute de cible en cible, dans l'ordre et aux positions du serveur ;
		             chaque rebond est plus fin (il perd de sa force), chaque nœud jaillit d'étincelles
	Jugement Céleste (ultime ; pose « Paralysie »)
		préparation  le ciel s'assombrit, l'électricité statique rampe autour du lanceur, une lueur
		             vacille au-dessus de chaque cible
		impact       éclair ramifié tombé du ciel sur chaque cible, éclair central massif près du lanceur,
		             onde d'étincelles au sol, flash bref
]]

local magicFolder = script.Parent.Parent
local clientFolder = magicFolder.Parent
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local VfxKit = require(magicFolder:WaitForChild("VfxKit") :: ModuleScript)

local T = VfxKit.TEXTURES
local random = VfxKit.random

local Lightning = {}

local CORE_WHITE = Color3.fromRGB(250, 252, 255)
local SCORCH = Color3.fromRGB(34, 32, 40)
local CAST_HEIGHT = 1.5

local function sparks(position: Vector3, amount: number, speed: number, palette: any)
	VfxKit.burst(position, amount, {
		Texture = T.spark,
		Color = ColorSequence.new(CORE_WHITE, palette.main),
		Speed = NumberRange.new(speed * 0.5, speed),
		Drag = 6,
		Acceleration = Vector3.new(0, -10, 0),
		Lifetime = NumberRange.new(0.15, 0.4),
		Size = NumberSequence.new(0.3, 0),
		Transparency = NumberSequence.new(0, 1),
	})
end

-- Petits arcs qui sautent autour d'une pièce pendant `duration` (électricité statique).
local function crawlingArcs(part: BasePart, radius: number, duration: number, palette: any, detail: number)
	local count = VfxKit.count(math.floor(duration / 0.08), detail, 2)
	for index = 1, count do
		task.delay((index - 1) * duration / count, function()
			if part.Parent then
				local center = part.Position
				local from = center + random:NextUnitVector() * radius
				local to = center + random:NextUnitVector() * radius
				VfxKit.bolt(from, to, CORE_WHITE, palette.main, 0.08, 0.1, 0, 0.25)
			end
		end)
	end
end

local function castOrigin(caster: Model?, fallback: Vector3): Vector3
	local hand = VfxKit.handOf(caster)
	if hand then
		return hand.Position
	end
	local root = if caster then VfxKit.rootOf(caster) else nil
	return if root then root.Position + Vector3.new(0, CAST_HEIGHT, 0) else fallback
end

--------------------------------------------------------------------------------
-- Arc Électrique
--------------------------------------------------------------------------------

local function arcCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local hand = VfxKit.handOf(caster)
	if hand == nil then
		return
	end
	local detail = VfxKit.detail(hand.Position)
	local holder = VfxKit.part("ArcCharge", Vector3.one * 0.6, palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	holder.Transparency = 1
	VfxKit.follow(holder, hand, CFrame.new(0, -0.5, -0.2), duration)
	VfxKit.emitter(holder, {
		Texture = T.spark,
		Color = ColorSequence.new(CORE_WHITE, palette.main),
		Rate = 90 * detail,
		Lifetime = NumberRange.new(0.05, 0.12),
		Speed = NumberRange.new(6, 12),
		Size = NumberSequence.new(0.2, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	crawlingArcs(holder, 0.9, duration, palette, detail)
end

local function arcImpact(_spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local from = castOrigin(caster, position + Vector3.new(0, 0, 3))
	VfxKit.bolt(from, position, CORE_WHITE, palette.main, 0.22, 0.22, VfxKit.count(2, detail, 1), detail)
	if #targets > 0 then
		VfxKit.flash(position, palette.glow, 16, 5, 0.18, detail)
		sparks(position, 24 * detail, 18, palette)
		for _, target in targets do
			CombatEffects.playHitImpact(target, position, palette.glow, VfxKit.count(8, detail))
		end
	else
		sparks(position, 8 * detail, 8, palette) -- l'éclair s'éteint dans le vide
	end
	SfxPlayer.play("impact_lightning", position)
end

--------------------------------------------------------------------------------
-- Chaîne Foudroyante
--------------------------------------------------------------------------------

local function chainCharge(caster: Model?, _spell: any, palette: any, duration: number)
	local root = if caster then VfxKit.rootOf(caster) else nil
	local hand = VfxKit.handOf(caster)
	if root == nil or hand == nil then
		return
	end
	local detail = VfxKit.detail(root.Position)
	local aura = VfxKit.part("ChainAura", Vector3.new(3, 5, 3), palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	aura.Transparency = 1
	VfxKit.follow(aura, root, CFrame.new(), duration)
	VfxKit.emitter(aura, {
		Texture = T.spark,
		Color = ColorSequence.new(CORE_WHITE, palette.main),
		Shape = Enum.ParticleEmitterShape.Box,
		Rate = 60 * detail,
		Lifetime = NumberRange.new(0.06, 0.15),
		Speed = NumberRange.new(2, 6),
		Size = NumberSequence.new(0.25, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	crawlingArcs(aura, 1.8, duration, palette, detail)
	local handGlow = VfxKit.part("ChainHand", Vector3.one * 0.6, palette.main, Enum.Material.SmoothPlastic, duration + 0.1)
	handGlow.Transparency = 1
	VfxKit.follow(handGlow, hand, CFrame.new(0, -0.5, 0), duration)
	crawlingArcs(handGlow, 0.8, duration, palette, detail)
end

local function chainImpact(spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any)
	local detail = VfxKit.detail(position)
	local previous = castOrigin(caster, position + Vector3.new(0, 0, 3))
	if #targets == 0 then
		VfxKit.bolt(previous, position, CORE_WHITE, palette.main, 0.2, 0.2, 1, detail)
		sparks(position, 8 * detail, 8, palette)
		SfxPlayer.play("impact_lightning", position)
		return
	end
	local width = 0.3
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		local point = if targetRoot then targetRoot.Position else target:GetPivot().Position
		local from = previous
		local thisWidth = width
		task.delay((index - 1) * 0.06, function()
			VfxKit.bolt(from, point, CORE_WHITE, palette.main, thisWidth, 0.25, VfxKit.count(2, detail, 1), detail)
			VfxKit.flash(point, palette.glow, 12, 4, 0.18, detail)
			sparks(point, 16 * detail, 14, palette)
			CombatEffects.playHitImpact(target, point, palette.glow, VfxKit.count(6, detail))
		end)
		previous = point
		width *= 1 - (spell.chainFalloff or 0.2) -- l'arc perd de sa force à chaque rebond
	end
	SfxPlayer.play("impact_lightning", position)
end

--------------------------------------------------------------------------------
-- Jugement Céleste (ultime)
--------------------------------------------------------------------------------

local SKY_HEIGHT = 60

function Lightning.ultimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local windup = magic.ultimateWindup or 0.45
	local palette = magic.palette
	local radius = magic.radius
	local detail = VfxKit.detail(origin)
	local intensity = CombatEffects.intensityAt(origin, radius)
	local ground = VfxKit.groundBelow(origin, VfxKit.ignore(caster, targets))

	-- 1. Le ciel s'assombrit, l'électricité statique rampe autour du lanceur.
	if intensity > 0 then
		CombatEffects.tintScreen(Color3.fromRGB(60, 70, 120), 0.45 * intensity, windup, 0.5)
	end
	local aura = VfxKit.part("StaticAura", Vector3.new(4, 6, 4), palette.main, Enum.Material.SmoothPlastic, windup + 0.3)
	aura.Transparency = 1
	aura.CFrame = CFrame.new(origin)
	crawlingArcs(aura, 3, windup, palette, detail)
	VfxKit.emitter(aura, {
		Texture = T.spark,
		Color = ColorSequence.new(CORE_WHITE, palette.main),
		Shape = Enum.ParticleEmitterShape.Box,
		Rate = 80 * detail,
		Lifetime = NumberRange.new(0.08, 0.2),
		Speed = NumberRange.new(4, 10),
		Size = NumberSequence.new(0.3, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	-- Une lueur vacille au-dessus de chaque cible : la foudre a choisi.
	local struck = VfxKit.count(8, detail, 3)
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot and index <= struck then
			local mark = VfxKit.part("StrikeMark", Vector3.one * 0.6, palette.glow, Enum.Material.Neon, windup + 0.1, Enum.PartType.Ball)
			mark.Transparency = 0.4
			mark.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 7, 0))
			VfxKit.tween(mark, windup, { Size = Vector3.one * 1.6, Transparency = 0.1 })
			crawlingArcs(mark, 1.2, windup, palette, detail)
		end
	end

	task.wait(windup)

	-- 2. Éclairs tombés du ciel sur chaque cible.
	for index, target in targets do
		local targetRoot = VfxKit.rootOf(target)
		if targetRoot and index <= struck then
			local point = targetRoot.Position
			local sky = point + Vector3.new(random:NextNumber(-6, 6), SKY_HEIGHT, random:NextNumber(-6, 6))
			task.delay(random:NextNumber(0, 0.08), function()
				VfxKit.bolt(sky, point, CORE_WHITE, palette.main, 0.45, 0.3, VfxKit.count(3, detail, 1), detail)
				sparks(point, 20 * detail, 20, palette)
				VfxKit.flash(point, palette.glow, 18, 5, 0.2, detail)
			end)
		end
		CombatEffects.playHitImpact(target, nil, palette.glow, VfxKit.count(8, detail))
	end
	-- Éclair central massif près du lanceur, onde d'étincelles au sol, sol roussi.
	local strike = ground + Vector3.new(0, 0.2, 0)
	VfxKit.bolt(strike + Vector3.new(0, SKY_HEIGHT, 0), strike, CORE_WHITE, palette.main, 0.9, 0.35, VfxKit.count(4, detail, 2), detail)
	VfxKit.burst(strike + Vector3.new(0, 0.5, 0), 40 * detail, {
		Texture = T.spark,
		Color = ColorSequence.new(CORE_WHITE, palette.main),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(85, 85),
		Speed = NumberRange.new(radius * 0.8, radius * 1.4),
		Drag = 3,
		Lifetime = NumberRange.new(0.25, 0.5),
		Size = NumberSequence.new(0.45, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	VfxKit.groundPatches("Scorch", ground, 4, SCORCH, Enum.Material.Slate, 0.2, VfxKit.count(6, detail, 3), 0.05, 1.2)
	VfxKit.flash(strike + Vector3.new(0, 4, 0), palette.glow, 50, 6, 0.3, detail)
	SfxPlayer.play("impact_lightning", origin)
	if intensity > 0 then
		CombatEffects.tintScreen(palette.glow, 0.5 * intensity, 0.03, 0.35)
		CombatEffects.shake(0.3, 0.6 * intensity)
	end
end

--------------------------------------------------------------------------------

Lightning.spells = {
	electric_arc = { charge = arcCharge, impact = arcImpact },
	chain_lightning = { charge = chainCharge, impact = chainImpact },
}

return Lightning
