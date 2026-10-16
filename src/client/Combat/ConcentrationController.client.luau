--!strict
--[[
	ConcentrationController (LocalScript)
	La Concentration côté client :
		- commande maintenue (KeyBindings.Concentrate : G, croix droite à la manette, bouton tactile) :
		  appui = demande au serveur (RequestConcentrate true), relâchement = fin (false). Le SERVEUR
		  accorde ou refuse (recharge, Mana déjà plein, charge en cours...) et pose l'attribut
		  Concentrating ; c'est cet attribut, et lui seul, qui déclenche la pose et les effets ;
		- pose « concentrate » (canal hold), son discret, aura propre à la Magie Innée (braises pour
		  la Pyromancie, givre pour la Glace, étincelles pour la Foudre, volutes pour l'Ombre, matière
		  aspirée pour l'Antimatière, poussière écrasée pour la Gravité), pour soi et pour les autres ;
		- MovementState.concentrating : le dash et l'épée se mettent en retrait pendant la posture ;
		- Mana plein : une note cristalline discrète (seulement après une vraie remontée).
	Mode « effets réduits » : aura deux fois moins dense, sans lumière.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local ResourceConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ResourceConfig") :: ModuleScript)
local CombatRemotes = require(sharedFolder:WaitForChild("Combat"):WaitForChild("CombatRemotes") :: ModuleScript)

local clientFolder = script.Parent.Parent
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local MovementState = require(clientFolder:WaitForChild("Movement"):WaitForChild("MovementState") :: ModuleScript)
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)

local ACTION_NAME = "Concentrate"
local AURA_NAME = "ConcentrationAura"
local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local MANA_FULL_SOUND_FROM = 0.85 -- la note ne sonne que si le Mana était descendu sous 85 %
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type AuraStyle = {
	texture: string,
	rate: number,
	speed: NumberRange,
	acceleration: Vector3,
	size: NumberSequence,
	lifetime: NumberRange,
	lightEmission: number,
	spread: Vector2,
	inward: boolean, -- particules qui partent loin et reviennent vers le corps (vitesse négative)
}

-- Une aura par Magie Innée : même discrétion, signatures différentes.
local AURA_STYLES: { [string]: AuraStyle } = {
	pyromancy = { texture = SPARK_TEXTURE, rate = 14, speed = NumberRange.new(1, 2.5), acceleration = Vector3.new(0, 5, 0), size = NumberSequence.new(0.25, 0), lifetime = NumberRange.new(0.8, 1.3), lightEmission = 1, spread = Vector2.new(30, 30), inward = false },
	ice = { texture = SPARK_TEXTURE, rate = 10, speed = NumberRange.new(0.4, 1), acceleration = Vector3.new(0, -1.5, 0), size = NumberSequence.new(0.2, 0.05), lifetime = NumberRange.new(1.2, 1.8), lightEmission = 0.6, spread = Vector2.new(180, 180), inward = false },
	lightning = { texture = SPARK_TEXTURE, rate = 18, speed = NumberRange.new(4, 7), acceleration = Vector3.zero, size = NumberSequence.new(0.18, 0), lifetime = NumberRange.new(0.12, 0.25), lightEmission = 1, spread = Vector2.new(180, 180), inward = false },
	shadow = { texture = SMOKE_TEXTURE, rate = 6, speed = NumberRange.new(0.3, 0.8), acceleration = Vector3.new(0, 0.8, 0), size = NumberSequence.new(1, 2.4), lifetime = NumberRange.new(1.4, 2), lightEmission = 0, spread = Vector2.new(180, 40), inward = false },
	antimatter = { texture = SPARK_TEXTURE, rate = 12, speed = NumberRange.new(-3, -2), acceleration = Vector3.zero, size = NumberSequence.new(0.05, 0.25), lifetime = NumberRange.new(0.7, 0.9), lightEmission = 1, spread = Vector2.new(180, 180), inward = true },
	gravity = { texture = SMOKE_TEXTURE, rate = 7, speed = NumberRange.new(0.5, 1), acceleration = Vector3.new(0, -6, 0), size = NumberSequence.new(0.6, 1.4), lifetime = NumberRange.new(0.8, 1.2), lightEmission = 0, spread = Vector2.new(180, 20), inward = false },
}

local localPlayer = Players.LocalPlayer
local isHolding = false
local isInDialogue = false
local lowestManaRatio = 1

--------------------------------------------------------------------------------
-- Aura
--------------------------------------------------------------------------------

local function removeAura(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local aura = root and root:FindFirstChild(AURA_NAME)
	if aura then
		aura:Destroy()
	end
end

local function addAura(character: Model, magicId: any)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	removeAura(character)
	local magic = MagicConfig.getById(magicId)
	local style = AURA_STYLES[magic.id] or AURA_STYLES.pyromancy
	local isReduced = ClientSettings.isReducedEffects()

	local attachment = Instance.new("Attachment")
	attachment.Name = AURA_NAME
	attachment.Position = if style.inward then Vector3.zero else Vector3.new(0, -1.6, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = style.texture
	emitter.Rate = style.rate * (if isReduced then 0.5 else 1)
	emitter.Speed = style.speed
	emitter.Acceleration = style.acceleration
	emitter.Size = style.size
	emitter.Lifetime = style.lifetime
	emitter.LightEmission = style.lightEmission
	emitter.LightInfluence = if style.lightEmission > 0 then 0 else 1
	emitter.SpreadAngle = style.spread
	emitter.Color = ColorSequence.new(magic.palette.glow, magic.palette.main)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = if style.inward then Enum.ParticleEmitterShapeStyle.Surface else Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = attachment
	if style.inward then
		-- Matière aspirée : les particules naissent sur une sphère et filent vers le corps.
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	end

	if not isReduced then
		local light = Instance.new("PointLight")
		light.Color = magic.palette.main
		light.Brightness = 0.6
		light.Range = 7
		light.Shadows = false
		light.Parent = attachment
	end
end

local function refreshPlayer(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local isConcentrating = player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == true
	if isConcentrating then
		addAura(character, player:GetAttribute(MagicConfig.ATTRIBUTE))
	else
		removeAura(character)
	end
	if player ~= localPlayer then
		return -- la pose des autres joueurs est jouée par l'AnimationDirector
	end
	MovementState.concentrating = isConcentrating
	local animator = CharacterAnimator.get(character, true)
	if isConcentrating then
		animator:play("concentrate")
		local root = character:FindFirstChild("HumanoidRootPart")
		SfxPlayer.play("concentrate", if root and root:IsA("BasePart") then root else nil)
	elseif animator:isPlaying("concentrate") then
		animator:stop("hold")
	end
end

--------------------------------------------------------------------------------
-- Commande
--------------------------------------------------------------------------------

local function canRequest(): boolean
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	return humanoid ~= nil
		and root ~= nil
		and humanoid.Health > 0
		and not root.Anchored
		and not isInDialogue
		and localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) ~= true
end

local function setHolding(wants: boolean)
	if wants == isHolding then
		return
	end
	isHolding = wants
	if wants and not canRequest() then
		isHolding = false
		return
	end
	CombatRemotes.RequestConcentrate:FireServer(wants)
end

local binding = KeyBindings.BINDINGS.Concentrate
ContextActionService:BindAction(ACTION_NAME, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		setHolding(true)
		return Enum.ContextActionResult.Sink
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setHolding(false)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, binding.touch ~= nil, binding.keyCode or binding.fallbackKeyCode, binding.gamepad or Enum.KeyCode.DPadRight)
ContextActionService:SetTitle(ACTION_NAME, binding.label)
if binding.touch then
	ContextActionService:SetPosition(ACTION_NAME, binding.touch)
end

UIBus.DialogueStateChanged:Connect(function(isOpen: boolean)
	isInDialogue = isOpen
	if isOpen then
		setHolding(false)
	end
end)

--------------------------------------------------------------------------------
-- Attributs posés par le serveur
--------------------------------------------------------------------------------

local function onManaChanged()
	local max = localPlayer:GetAttribute(ResourceConfig.MANA_MAX_ATTRIBUTE)
	local mana = localPlayer:GetAttribute(ResourceConfig.MANA_ATTRIBUTE)
	if type(max) ~= "number" or type(mana) ~= "number" or max <= 0 then
		return
	end
	local ratio = mana / max
	if ratio >= 0.999 then
		if lowestManaRatio < MANA_FULL_SOUND_FROM then
			SfxPlayer.play("manaFull")
		end
		lowestManaRatio = 1
	else
		lowestManaRatio = math.min(lowestManaRatio, ratio)
	end
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(ResourceConfig.CONCENTRATING_ATTRIBUTE):Connect(function()
		refreshPlayer(player)
	end)
	player.CharacterAdded:Connect(function()
		if player == localPlayer then
			isHolding = false
			MovementState.concentrating = false
		end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
localPlayer:GetAttributeChangedSignal(ResourceConfig.MANA_ATTRIBUTE):Connect(onManaChanged)
