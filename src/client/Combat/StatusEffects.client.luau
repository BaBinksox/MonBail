--!strict
--[[
	StatusEffects (LocalScript)
	Rend VISIBLES les altérations posées par le serveur (StatusService) sur les ennemis et les
	joueurs, à partir des attributs Status_<id> (heure serveur de fin) du Model :
		brûlure     braises qui montent (plus denses à chaque cran)
		froid       teinte bleutée ; gel : gangue de glace translucide
		électrisé   étincelles crépitantes ; paralysie : idem, plus vives
		drain       volutes sombres ; voile (joueur) : silhouette assombrie
		pression    poussière plaquée au sol ; cloué : idem
	Purement décoratif et local. Un effet disparaît dès que l'attribut est retiré ou expiré.
	Mode « effets réduits » : moitié moins de particules.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local StatusConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("StatusConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)

local TIME_LOOP_ENTITY_TAG = "TimeLoopEntity"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FX_PREFIX = "StatusFx_"

type Look = { texture: string, rate: number, speed: NumberRange, acceleration: Vector3, size: NumberSequence, lifetime: NumberRange, tint: number?, crystal: boolean? }

local LOOKS: { [string]: Look } = {
	burn = { texture = SPARK_TEXTURE, rate = 10, speed = NumberRange.new(1, 3), acceleration = Vector3.new(0, 6, 0), size = NumberSequence.new(0.35, 0), lifetime = NumberRange.new(0.5, 0.9) },
	chill = { texture = SPARK_TEXTURE, rate = 5, speed = NumberRange.new(0.2, 0.6), acceleration = Vector3.new(0, -1, 0), size = NumberSequence.new(0.2, 0), lifetime = NumberRange.new(0.8, 1.2), tint = 0.75 },
	frostbite = { texture = SPARK_TEXTURE, rate = 6, speed = NumberRange.new(0.2, 0.6), acceleration = Vector3.new(0, -1, 0), size = NumberSequence.new(0.25, 0), lifetime = NumberRange.new(0.8, 1.2), tint = 0.65 },
	freeze = { texture = SPARK_TEXTURE, rate = 4, speed = NumberRange.new(0.1, 0.3), acceleration = Vector3.zero, size = NumberSequence.new(0.3, 0), lifetime = NumberRange.new(0.6, 1), tint = 0.5, crystal = true },
	shock = { texture = SPARK_TEXTURE, rate = 14, speed = NumberRange.new(4, 8), acceleration = Vector3.zero, size = NumberSequence.new(0.2, 0), lifetime = NumberRange.new(0.08, 0.18) },
	paralysis = { texture = SPARK_TEXTURE, rate = 22, speed = NumberRange.new(5, 9), acceleration = Vector3.zero, size = NumberSequence.new(0.25, 0), lifetime = NumberRange.new(0.08, 0.2) },
	drain = { texture = SMOKE_TEXTURE, rate = 5, speed = NumberRange.new(0.5, 1.2), acceleration = Vector3.new(0, 1, 0), size = NumberSequence.new(0.8, 1.6), lifetime = NumberRange.new(0.8, 1.2) },
	veil = { texture = SMOKE_TEXTURE, rate = 6, speed = NumberRange.new(0.3, 0.7), acceleration = Vector3.new(0, 0.6, 0), size = NumberSequence.new(1.2, 2.2), lifetime = NumberRange.new(1, 1.5), tint = 0.7 },
	pressure = { texture = SMOKE_TEXTURE, rate = 6, speed = NumberRange.new(0.5, 1), acceleration = Vector3.new(0, -8, 0), size = NumberSequence.new(0.8, 1.6), lifetime = NumberRange.new(0.5, 0.8) },
	pinned = { texture = SMOKE_TEXTURE, rate = 8, speed = NumberRange.new(0.5, 1), acceleration = Vector3.new(0, -10, 0), size = NumberSequence.new(1, 2), lifetime = NumberRange.new(0.5, 0.8) },
}

local watched: { [Model]: boolean } = {}

local function removeFx(model: Model, statusId: string)
	local fx = model:FindFirstChild(FX_PREFIX .. statusId, true)
	while fx do
		fx:Destroy()
		fx = model:FindFirstChild(FX_PREFIX .. statusId, true)
	end
end

local function addFx(model: Model, statusId: string, level: number)
	local look = LOOKS[statusId]
	local def = StatusConfig.STATUSES[statusId]
	local root = model:FindFirstChild("HumanoidRootPart")
	if look == nil or def == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	removeFx(model, statusId)
	local isReduced = ClientSettings.isReducedEffects()

	local attachment = Instance.new("Attachment")
	attachment.Name = FX_PREFIX .. statusId
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = look.texture
	emitter.Rate = look.rate * math.max(1, level) * (if isReduced then 0.5 else 1)
	emitter.Speed = look.speed
	emitter.Acceleration = look.acceleration
	emitter.Size = look.size
	emitter.Lifetime = look.lifetime
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = if look.texture == SPARK_TEXTURE then 1 else 0
	emitter.Color = ColorSequence.new(def.color)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = attachment

	if look.tint then
		local highlight = Instance.new("Highlight")
		highlight.Name = FX_PREFIX .. statusId
		highlight.FillColor = def.color
		highlight.FillTransparency = look.tint
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
	end
	if look.crystal then
		-- Gangue de glace : une pièce translucide soudée au RootPart, sans collision.
		local extents = model:GetExtentsSize()
		local crystal = Instance.new("Part")
		crystal.Name = FX_PREFIX .. statusId
		crystal.Material = Enum.Material.Glass
		crystal.Color = def.color
		crystal.Transparency = 0.55
		crystal.Size = Vector3.new(extents.X + 0.6, extents.Y + 0.4, extents.Z + 0.6)
		crystal.CanCollide = false
		crystal.CanQuery = false
		crystal.CanTouch = false
		crystal.Massless = true
		crystal.CastShadow = false
		crystal.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = crystal
		weld.Part1 = root
		weld.Parent = crystal
		crystal.Parent = model
	end
end

local function refresh(model: Model, statusId: string)
	local name = StatusConfig.ATTRIBUTE_PREFIX .. statusId
	local untilTime = model:GetAttribute(name)
	if type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow() then
		local level = model:GetAttribute(name .. "Level")
		local existing = model:FindFirstChild(FX_PREFIX .. statusId, true)
		local previousLevel = if existing then existing:GetAttribute("Level") else nil
		if existing == nil or previousLevel ~= level then
			addFx(model, statusId, if type(level) == "number" then level else 1)
			local fx = model:FindFirstChild(FX_PREFIX .. statusId, true)
			if fx then
				fx:SetAttribute("Level", level)
			end
		end
		-- Filet de sécurité : l'effet s'éteint à l'heure prévue même si l'attribut tarde à partir.
		task.delay(untilTime - workspace:GetServerTimeNow() + 0.1, function()
			local current = model:GetAttribute(name)
			if type(current) ~= "number" or current <= workspace:GetServerTimeNow() then
				removeFx(model, statusId)
			end
		end)
	else
		removeFx(model, statusId)
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	watched[model] = true
	for statusId in StatusConfig.STATUSES do
		model:GetAttributeChangedSignal(StatusConfig.ATTRIBUTE_PREFIX .. statusId):Connect(function()
			refresh(model, statusId)
		end)
	end
	model.Destroying:Connect(function()
		watched[model] = nil
	end)
end

CollectionService:GetInstanceAddedSignal(TIME_LOOP_ENTITY_TAG):Connect(watch)
for _, model in CollectionService:GetTagged(TIME_LOOP_ENTITY_TAG) do
	watch(model)
end
local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
