--!strict
--[[
	BossEffectsController (LocalScript)
	Effets visuels des boss, joués localement par chaque client.

	Le serveur ne fait que publier l'état de chaque boss dans un attribut de son Model
	(BossConfig.STATE_ATTRIBUTE). Ce script l'écoute et habille deux états :
		- Charging  : particules rouges et noires aspirées vers le boss, cœur sombre qui grossit,
		              lueur rouge et silhouette surlignée. C'est l'annonce de l'attaque fatale ;
		- Staggered : silhouette pâle, pour signaler la faille après un rewind.
	Tout autre état retire l'effet en cours.

	Rien ne tourne en continu ici : les effets sont des émetteurs et des tweens que le moteur anime.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Boss")
local Config = require(sharedFolder:WaitForChild("BossConfig") :: ModuleScript)

local COLOR_RED = Color3.fromRGB(255, 40, 45)
local COLOR_DARK_RED = Color3.fromRGB(90, 0, 10)
local COLOR_BLACK = Color3.fromRGB(8, 2, 4)
local COLOR_STAGGER = Color3.fromRGB(190, 215, 255)

-- Textures de particules livrées avec le client Roblox (aucun asset à importer).
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local CHARGE_SPHERE_DIAMETER = 18 -- les particules naissent sur cette sphère et convergent vers le boss
local CHARGE_CORE_SIZE = 5 -- diamètre final du cœur sombre

-- Fonction qui retire l'effet en cours d'un boss.
type Cleanup = () -> ()

local activeEffects: { [Model]: Cleanup } = {}

--------------------------------------------------------------------------------
-- Briques de base
--------------------------------------------------------------------------------

-- Pièce purement décorative : locale, ancrée, intangible.
local function newEffectPart(name: string, size: Vector3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function newHighlight(boss: Model, fillColor: Color3, fillTransparency: number): Highlight
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = fillColor
	highlight.FillTransparency = fillTransparency
	highlight.OutlineColor = fillColor
	highlight.OutlineTransparency = 0
	highlight.Parent = boss
	return highlight
end

--------------------------------------------------------------------------------
-- Effets par état
--------------------------------------------------------------------------------

-- Charge de l'attaque fatale. Le boss est ancré par le serveur pendant cet état :
-- l'effet peut donc rester posé là où il a commencé.
local function playCharge(boss: Model): Cleanup
	local center = boss:GetPivot().Position
	local pulseInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	-- Sphère invisible : sa surface sert de point de départ aux particules.
	local sphere = newEffectPart("BossChargeSphere", Vector3.one * CHARGE_SPHERE_DIAMETER, center)
	sphere.Transparency = 1
	sphere.Parent = workspace

	-- Éclats rouges aspirés vers le centre.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.Shape = Enum.ParticleEmitterShape.Sphere
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	sparks.Rate = 90
	sparks.Lifetime = NumberRange.new(0.45, 0.6)
	sparks.Speed = NumberRange.new(13, 17)
	sparks.Color = ColorSequence.new(COLOR_RED, COLOR_BLACK)
	sparks.Size = NumberSequence.new(1.4, 0.2)
	sparks.Transparency = NumberSequence.new(0, 0.6)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = sphere

	-- Volutes noires, plus lentes, qui épaississent l'air autour du boss.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Shape = Enum.ParticleEmitterShape.Sphere
	smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	smoke.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	smoke.Rate = 30
	smoke.Lifetime = NumberRange.new(0.8, 1.1)
	smoke.Speed = NumberRange.new(6, 9)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-80, 80)
	smoke.Color = ColorSequence.new(COLOR_DARK_RED, COLOR_BLACK)
	smoke.Size = NumberSequence.new(5, 1.5)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.LightEmission = 0
	smoke.Parent = sphere

	-- Cœur sombre qui enfle pendant toute la charge.
	local core = newEffectPart("BossChargeCore", Vector3.one * 0.5, center)
	core.Material = Enum.Material.Neon
	core.Color = COLOR_BLACK
	core.Parent = workspace
	local coreInfo = TweenInfo.new(Config.CHARGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(core, coreInfo, { Size = Vector3.one * CHARGE_CORE_SIZE }):Play()

	-- Lueur rouge qui bat sur le décor.
	local light = Instance.new("PointLight")
	light.Color = COLOR_RED
	light.Range = 40
	light.Brightness = 2
	light.Parent = sphere
	TweenService:Create(light, pulseInfo, { Brightness = 9 }):Play()

	-- Silhouette du boss surlignée de rouge, qui bat au même rythme.
	local highlight = newHighlight(boss, COLOR_RED, 0.75)
	TweenService:Create(highlight, pulseInfo, { FillTransparency = 0.35 }):Play()

	return function()
		sphere:Destroy() -- emporte les particules et la lumière
		core:Destroy()
		highlight:Destroy()
	end
end

-- Boss sonné : une simple silhouette pâle, le temps que dure la faille.
local function playStagger(boss: Model): Cleanup
	local highlight = newHighlight(boss, COLOR_STAGGER, 0.8)
	return function()
		highlight:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Suivi de l'état des boss
--------------------------------------------------------------------------------

local function clearEffect(boss: Model)
	local cleanup = activeEffects[boss]
	if cleanup then
		activeEffects[boss] = nil
		cleanup()
	end
end

local function onStateChanged(boss: Model)
	clearEffect(boss)

	local state = boss:GetAttribute(Config.STATE_ATTRIBUTE)
	if state == Config.STATES.Charging then
		activeEffects[boss] = playCharge(boss)
	elseif state == Config.STATES.Staggered then
		activeEffects[boss] = playStagger(boss)
	end
end

local function trackBoss(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	instance:GetAttributeChangedSignal(Config.STATE_ATTRIBUTE):Connect(function()
		onStateChanged(instance)
	end)
	onStateChanged(instance)
end

local function untrackBoss(instance: Instance)
	if instance:IsA("Model") then
		clearEffect(instance)
	end
end

CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(trackBoss)
CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(untrackBoss)
for _, instance in CollectionService:GetTagged(Config.TAG) do
	trackBoss(instance)
end
