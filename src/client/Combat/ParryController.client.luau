--!strict
--[[
	ParryController (LocalScript)
	La parade parfaite côté client : une touche, une posture immédiate, et c'est le serveur qui juge.
		- Clavier : l'EMPLACEMENT de Q en QWERTY, c'est-à-dire la touche marquée « A » en AZERTY
		  (KeyBindings.Parry). Manette : L1. Tactile : bouton « Parade » (ContextActionService).
		- Appui : ParryRemotes.RequestParry (le serveur horodate), posture visuelle STANCE_DURATION
		  (contour acier sur le personnage), recharge locale ParryConfig.COOLDOWN.
		- ParryResult (pour tous) : étincelle à l'endroit du choc ; pour le défenseur, éclair blanc et
		  « Parade parfaite ».
		- Ennemis étourdis (attribut StunnedUntil) : un contour ambré tant que dure l'ouverture.
	Aucune image ni aucun son d'asset : tout est construit avec des Parts et des effets intégrés.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local ParryConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ParryConfig") :: ModuleScript)
local ParryRemotes = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ParryRemotes") :: ModuleScript)
local EnemyDefinitions = require(sharedFolder:WaitForChild("Enemy"):WaitForChild("EnemyDefinitions") :: ModuleScript)

local clientFolder = script.Parent.Parent
local Theme = require(clientFolder:WaitForChild("UI"):WaitForChild("Theme") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)

local ACTION_NAME = "Parry"
local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local STANCE_COLOR = Color3.fromRGB(196, 210, 232)
local SPARK_COLOR = Color3.fromRGB(255, 226, 160)
local STUN_COLOR = Color3.fromRGB(230, 152, 52)

local localPlayer = Players.LocalPlayer
local lastParryClock = -math.huge
local isInDialogue = false

--------------------------------------------------------------------------------
-- Retours visuels
--------------------------------------------------------------------------------

local feedbackScreen = Theme.screenGui("ParryGui", Theme.displayOrder.world)
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.Parent = feedbackScreen.root
feedbackScreen.safe.ZIndex = 2 -- le titre « Parade parfaite » reste au-dessus du flash
local perfect = Theme.title({
	parent = feedbackScreen.safe,
	text = "Parade parfaite",
	size = UDim2.fromOffset(420, 50),
	position = UDim2.fromScale(0.5, 0.32),
	anchor = Vector2.new(0.5, 0.5),
	alignX = Enum.TextXAlignment.Center,
	stroke = true,
	visible = false,
})
perfect.TextSize = 38
perfect.TextColor3 = Theme.colors.goldBright

local function showStance(character: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "ParryStance"
	highlight.FillTransparency = 1
	highlight.OutlineColor = STANCE_COLOR
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(ParryConfig.STANCE_DURATION), { OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, ParryConfig.STANCE_DURATION + 0.1)
end

local function spark(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "ParrySpark"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = SPARK_COLOR
	part.Size = Vector3.one * 0.6
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Position = position
	local light = Instance.new("PointLight")
	light.Color = SPARK_COLOR
	light.Range = 12
	light.Brightness = 4
	light.Parent = part
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 4, Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	Debris:AddItem(part, 0.4)
end

local function celebrate()
	flash.BackgroundTransparency = 0.55
	TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	perfect.TextTransparency = 0
	perfect.Visible = true
	task.delay(0.9, function()
		Theme.fade(perfect, false, 0.4)
	end)
end

--------------------------------------------------------------------------------
-- Demande de parade
--------------------------------------------------------------------------------

local function canParry(): boolean
	if isInDialogue or localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true then
		return false
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function onParryAction(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	if now - lastParryClock < ParryConfig.COOLDOWN or not canParry() then
		return Enum.ContextActionResult.Sink
	end
	lastParryClock = now
	ParryRemotes.RequestParry:FireServer()
	local character = localPlayer.Character
	if character then
		showStance(character)
	end
	return Enum.ContextActionResult.Sink
end

local binding = KeyBindings.BINDINGS.Parry
ContextActionService:BindAction(ACTION_NAME, onParryAction, true, binding.keyCode or binding.fallbackKeyCode, binding.gamepad or Enum.KeyCode.ButtonL1)
ContextActionService:SetTitle(ACTION_NAME, binding.label)
ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -170, 1, -150))

UIBus.DialogueStateChanged:Connect(function(isOpen: boolean)
	isInDialogue = isOpen
end)

ParryRemotes.ParryResult.OnClientEvent:Connect(function(defender: any, _attacker: any, position: any)
	if typeof(position) == "Vector3" then
		spark(position)
	end
	if defender ~= nil and defender == localPlayer.Character then
		celebrate()
	end
end)

--------------------------------------------------------------------------------
-- Ennemis étourdis : la fenêtre de contre-attaque se voit
--------------------------------------------------------------------------------

local function watchStun(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function refresh()
		local stunnedUntil = model:GetAttribute(ParryConfig.STUNNED_UNTIL_ATTRIBUTE)
		if type(stunnedUntil) ~= "number" then
			return
		end
		local remaining = stunnedUntil - workspace:GetServerTimeNow()
		if remaining <= 0 then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "Stunned"
		highlight.FillColor = STUN_COLOR
		highlight.FillTransparency = 0.75
		highlight.OutlineColor = STUN_COLOR
		highlight.Adornee = model
		highlight.Parent = model
		Debris:AddItem(highlight, remaining)
	end
	model:GetAttributeChangedSignal(ParryConfig.STUNNED_UNTIL_ATTRIBUTE):Connect(refresh)
end

for _, model in CollectionService:GetTagged(EnemyDefinitions.TAG) do
	watchStun(model)
end
CollectionService:GetInstanceAddedSignal(EnemyDefinitions.TAG):Connect(watchStun)
