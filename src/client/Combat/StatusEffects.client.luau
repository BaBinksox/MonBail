--!strict
--[[
	StatusEffects (LocalScript)
	Rend VISIBLES les altérations posées par le serveur (StatusService) sur les ennemis et les
	joueurs, à partir des attributs Status_<id> (heure serveur de fin) du Model :
		brûlure     braises qui montent (plus denses à chaque cran)
		froid       teinte bleutée ; gel : givre sur la silhouette et éclats de glace sur le corps
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
		-- Gel : givre blanc sur la silhouette et éclats de glace pris sur le corps (soudés au
		-- RootPart, sans masse ni collision). La cage de la Prison Cristalline s'y ajoute.
		local frost = model:FindFirstChildOfClass("Highlight")
		if frost and frost.Name == FX_PREFIX .. statusId then
			frost.OutlineColor = Color3.new(1, 1, 1)
			frost.OutlineTransparency = 0.35
		end
		local extents = model:GetExtentsSize()
		local shardCount = if isReduced then 2 else 4
		for index = 1, shardCount do
			local shard = Instance.new("Part")
			shard.Name = FX_PREFIX .. statusId
			shard.Material = Enum.Material.Glass
			shard.Color = def.color
			shard.Transparency = 0.25
			shard.Size = Vector3.new(0.5, extents.Y * 0.45, 0.5)
			shard.CanCollide = false
			shard.CanQuery = false
			shard.CanTouch = false
			shard.Massless = true
			shard.CastShadow = false
			local angle = index / shardCount * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * extents.X * 0.4, -extents.Y * 0.15, math.sin(angle) * extents.Z * 0.4)
			shard.CFrame = root.CFrame * CFrame.new(offset) * CFrame.Angles(math.sin(angle) * 0.5, angle, math.cos(angle) * 0.5) * CFrame.Angles(0, math.rad(45), 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = shard
			weld.Part1 = root
			weld.Parent = shard
			shard.Parent = model
		end
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
