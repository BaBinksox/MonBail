--!strict
--[[
	SpellEffects (ModuleScript, client)
	Effets visuels des sorts, joués localement par chaque client à partir des événements du serveur
	(SpellCast, SpellImpact, ReactionTriggered). Rien ici n'a d'effet sur le jeu : pièces locales,
	ancrées, intangibles, détruites toutes seules ; particules de textures livrées avec Roblox.
		castStarted(caster, spell, castId, origin, aimPoint)   annonce : projectile, zone visée, champ
		impact(castId, spell, position, targets)               explosion, rayons, chaîne d'éclairs
		reaction(target, reactionId, position)                 réaction élémentaire
	Couleurs : palette de la magie du sort (MagicConfig). Mode « effets réduits » : particules
	divisées par deux, pas de secousse.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local StatusConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("StatusConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local PROJECTILE_HEIGHT = 1.5
local MAX_PROJECTILE_LIFETIME = 3

local SpellEffects = {}

type Projectile = { part: BasePart, connection: RBXScriptConnection }
local projectiles: { [number]: Projectile } = {}
local pendingImpacts: { [number]: boolean } = {} -- impacts arrivés avant le départ visuel du projectile

local folder: Folder? = nil
local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SpellEffects"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

local function count(value: number): number
	return if ClientSettings.isReducedEffects() then math.max(1, math.floor(value / 2)) else value
end

local function newPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	Debris:AddItem(part, lifetime)
	return part
end

local function tween(instance: Instance, duration: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function burst(position: Vector3, color: Color3, amount: number, speed: number, texture: string?)
	local anchor = newPart("SpellBurst", Enum.PartType.Block, Vector3.one * 0.2, color, 1.5)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = texture or SPARK_TEXTURE
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.Speed = NumberRange.new(speed * 0.4, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Lifetime = NumberRange.new(0.25, 0.6)
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Parent = anchor
	task.delay(0.03, function()
		emitter:Emit(count(amount))
	end)
end

-- Anneau plat au sol (cylindre couché) qui s'étend jusqu'à `radius`.
local function ring(position: Vector3, radius: number, color: Color3, duration: number, startRadius: number?)
	local start = (startRadius or 0.5) * 2
	local part = newPart("SpellRing", Enum.PartType.Cylinder, Vector3.new(0.2, start, start), color, duration + 0.1)
	part.Transparency = 0.3
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = getFolder()
	tween(part, duration, { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 })
end

-- Rayon droit entre deux points (éclair, trait d'ombre).
local function beam(from: Vector3, to: Vector3, color: Color3, width: number, duration: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local part = newPart("SpellBeam", Enum.PartType.Block, Vector3.new(width, width, length), color, duration + 0.1)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Transparency = 0.1
	part.Parent = getFolder()
	tween(part, duration, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
end

-- Éclair en zigzag : quelques segments décalés.
local function lightningBolt(from: Vector3, to: Vector3, color: Color3)
	local segments = 5
	local previous = from
	local random = Random.new()
	for index = 1, segments do
		local alpha = index / segments
		local point = from:Lerp(to, alpha)
		if index < segments then
			point += Vector3.new(random:NextNumber(-0.8, 0.8), random:NextNumber(-0.8, 0.8), random:NextNumber(-0.8, 0.8))
		end
		beam(previous, point, color, 0.25, 0.18)
		previous = point
	end
end

local function removeProjectile(castId: number): Vector3?
	local projectile = projectiles[castId]
	if projectile == nil then
		return nil
	end
	projectiles[castId] = nil
	projectile.connection:Disconnect()
	local position = projectile.part.Position
	projectile.part:Destroy()
	return position
end

--------------------------------------------------------------------------------
-- Effets propres à certains sorts (le reste utilise les effets communs ci-dessous)
--------------------------------------------------------------------------------

type ProjectileLook = (palette: any, spell: any) -> BasePart
type Telegraph = (spell: any, aimPoint: Vector3, palette: any) -> ()
type ImpactPlayer = (spell: any, position: Vector3, targets: { Model }, caster: Model?, palette: any) -> ()

local PROJECTILE_LOOKS: { [string]: ProjectileLook } = {}
local TELEGRAPHS: { [string]: Telegraph } = {}
local IMPACTS: { [string]: ImpactPlayer } = {}

-- GLACE : voir Vfx/Ice (Magies 3.0).

-- ANTIMATIÈRE : voir Vfx/Antimatter (Magies 3.0).

-- PYROMANCIE, FOUDRE, OMBRE, GRAVITÉ : voir Vfx/Pyromancy, Vfx/Lightning, Vfx/Shadow, Vfx/Gravity.

--------------------------------------------------------------------------------
-- Magies 3.0 : un module d'effets par magie (Client/Magic/Vfx), qui remplace les effets ci-dessus
-- pour ses sorts. Chaque sort peut y définir : charge (préparation dans la main du lanceur),
-- projectile (apparence en vol), telegraph (annonce de la zone), impact (résolution).
--------------------------------------------------------------------------------

type Charge = (caster: Model?, spell: any, palette: any, duration: number) -> ()
local CHARGES: { [string]: Charge } = {}
local VFX_MODULES = { "Ice", "Antimatter", "Pyromancy", "Lightning", "Shadow", "Gravity" }
local vfxFolder = script.Parent:WaitForChild("Vfx")
for _, moduleName in VFX_MODULES do
	local module = require(vfxFolder:WaitForChild(moduleName) :: ModuleScript) :: any
	for spellId, hooks in module.spells do
		if hooks.charge then
			CHARGES[spellId] = hooks.charge
		end
		if hooks.projectile then
			PROJECTILE_LOOKS[spellId] = hooks.projectile
		end
		if hooks.telegraph then
			TELEGRAPHS[spellId] = hooks.telegraph
		end
		if hooks.impact then
			IMPACTS[spellId] = hooks.impact
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Annonce d'un sort : départ du projectile (après l'incantation), cercle de la zone visée, champ.
function SpellEffects.castStarted(caster: Model?, spell: any, castId: number, origin: Vector3, aimPoint: Vector3)
	local magic = MagicConfig.getById(spell.magic)
	local palette = magic.palette
	local charge = CHARGES[spell.id]
	if charge then
		task.spawn(charge, caster, spell, palette, math.max(spell.castTime, 0.15))
	end
	local telegraph = TELEGRAPHS[spell.id]
	if telegraph and (spell.kind == "zone" or spell.kind == "field") then
		telegraph(spell, aimPoint, palette)
		return
	end
	if spell.kind == "zone" or spell.kind == "field" then
		-- Le point d'effet est annoncé pendant l'incantation : un cercle qui se resserre.
		local duration = math.max(spell.castTime, 0.15)
		local part = newPart("SpellTelegraph", Enum.PartType.Cylinder, Vector3.new(0.15, spell.radius * 2, spell.radius * 2), palette.main, duration + 0.05)
		part.Transparency = 0.75
		part.CFrame = CFrame.new(aimPoint + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Parent = getFolder()
		tween(part, duration, { Transparency = 0.45 })
		if spell.kind == "field" then
			local lifetime = spell.castTime + spell.pulses * spell.pulseInterval
			local field = newPart("GravityField", Enum.PartType.Cylinder, Vector3.new(0.3, spell.radius * 2, spell.radius * 2), palette.main, lifetime)
			field.Material = Enum.Material.ForceField
			field.Transparency = 0.4
			field.CFrame = CFrame.new(aimPoint + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			field.Parent = getFolder()
			for pulse = 0, spell.pulses - 1 do
				task.delay(spell.castTime + pulse * spell.pulseInterval, function()
					ring(aimPoint, spell.radius, palette.glow, spell.pulseInterval * 0.9, spell.radius * 0.3)
				end)
			end
		end
		return
	end
	if spell.kind ~= "projectile" then
		return
	end
	task.delay(spell.castTime, function()
		if pendingImpacts[castId] then
			pendingImpacts[castId] = nil
			return
		end
		local root = caster and caster:FindFirstChild("HumanoidRootPart")
		local start = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, PROJECTILE_HEIGHT, 0) else origin
		local offset = aimPoint - start
		local direction = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.zAxis
		local look = PROJECTILE_LOOKS[spell.id]
		local orb: BasePart = if look then look(palette, spell) else newPart("SpellProjectile", Enum.PartType.Ball, Vector3.one * math.clamp(spell.radius * 0.6, 0.8, 1.8), palette.main, MAX_PROJECTILE_LIFETIME)
		orb.CFrame = CFrame.lookAt(start, start + direction)
		orb.Parent = getFolder()
		local light = Instance.new("PointLight")
		light.Color = palette.main
		light.Range = 10
		light.Brightness = 2
		light.Parent = orb
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.3, 0)
		a0.Parent = orb
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.3, 0)
		a1.Parent = orb
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(palette.glow, palette.main)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = orb
		local travelled = 0
		local connection = RunService.Heartbeat:Connect(function(dt: number)
			local step = spell.speed * dt
			travelled += step
			if travelled >= spell.range then
				removeProjectile(castId)
				return
			end
			local nextPosition = orb.Position + direction * step
			orb.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
		end)
		projectiles[castId] = { part = orb, connection = connection }
	end)
end

-- Résolution d'un sort (envoyée par le serveur) : explosion, rayons, impacts sur les cibles.
function SpellEffects.impact(castId: number, spell: any, position: Vector3, targets: { Model }, caster: Model?)
	local magic = MagicConfig.getById(spell.magic)
	local palette = magic.palette
	local projectilePosition = removeProjectile(castId)
	local custom = IMPACTS[spell.id]
	if custom then
		if spell.kind == "projectile" and projectilePosition == nil then
			pendingImpacts[castId] = true
			task.delay(MAX_PROJECTILE_LIFETIME, function()
				pendingImpacts[castId] = nil
			end)
		end
		custom(spell, position, targets, caster, palette)
		return
	end
	if spell.kind == "projectile" and projectilePosition == nil then
		pendingImpacts[castId] = true -- l'impact est arrivé avant le départ visuel : pas de projectile fantôme
		task.delay(MAX_PROJECTILE_LIFETIME, function()
			pendingImpacts[castId] = nil
		end)
	end
	local casterRoot = caster and caster:FindFirstChild("HumanoidRootPart")
	local casterPosition = if casterRoot and casterRoot:IsA("BasePart") then casterRoot.Position + Vector3.new(0, PROJECTILE_HEIGHT, 0) else nil

	if spell.kind == "line" and casterPosition then
		lightningBolt(casterPosition, position, palette.glow)
	elseif spell.kind == "chain" then
		local previous = casterPosition
		for _, target in targets do
			local point = target:GetPivot().Position
			if previous then
				lightningBolt(previous, point, palette.glow)
			end
			previous = point
		end
	elseif spell.kind == "self" and caster then
		burst(caster:GetPivot().Position, palette.main, 24, 8, SMOKE_TEXTURE)
		ring(caster:GetPivot().Position - Vector3.new(0, 2.5, 0), 6, palette.main, 0.5)
	end
	if spell.radius >= 3 and spell.kind ~= "self" and spell.kind ~= "field" then
		ring(position, spell.radius, palette.main, 0.45)
		burst(position, palette.main, 30, spell.radius * 3)
	elseif spell.kind ~= "self" and spell.kind ~= "field" then
		burst(position, palette.main, 14, 14)
	end
	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main, 8)
	end
end

-- Réaction élémentaire : éclat plus large, de la couleur de la réaction.
function SpellEffects.reaction(target: Model?, reactionId: string, position: Vector3)
	local color = Color3.new(1, 1, 1)
	for _, reaction in StatusConfig.REACTIONS do
		if reaction.id == reactionId then
			color = reaction.color
		end
	end
	burst(position, color, 40, 24)
	ring(position - Vector3.new(0, 2, 0), 8, color, 0.5, 1)
	if target then
		CombatEffects.playHitImpact(target, position, color, 12)
	end
end

return SpellEffects
