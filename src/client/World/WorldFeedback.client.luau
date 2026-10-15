--!strict
--[[
	WorldFeedback
	Finitions d'immersion, toutes discrètes :
		- TITRE DE LIEU : en entrant dans une région, son nom (police gothique) et sa devise
		  apparaissent en fondu au tiers haut de l'écran, puis s'effacent. Pas pendant le créateur ni
		  la cinématique d'arrivée (qui affiche déjà le nom du village), et pas plus d'une fois toutes
		  les REGION_TITLE_COOLDOWN secondes pour une même région (longer une frontière ne spamme rien).
		- MÉCANISME : quand un mécanisme répond (WorldRemotes.MechanismPulse), une lueur douce pulse à
		  cet endroit et un carillon discret joue (si AudioConfig en fournit un).
		- SONS DE RETOUR : UIBus.Feedback("secret" | "mechanism" | "regionEnter"), catégorie Effets.
	Le mode « effets réduits » adoucit la lueur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(sharedFolder:WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local RegionConfig = require(sharedFolder:WaitForChild("World"):WaitForChild("RegionConfig") :: ModuleScript)
local WorldRemotes = require(sharedFolder:WaitForChild("World"):WaitForChild("WorldRemotes") :: ModuleScript)

local clientFolder = script.Parent.Parent
local AudioMixer = require(clientFolder:WaitForChild("Audio"):WaitForChild("AudioMixer") :: ModuleScript)
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local CreatorSession = require(clientFolder:WaitForChild("AvatarCreator"):WaitForChild("CreatorSession") :: ModuleScript)
local Theme = require(clientFolder:WaitForChild("UI"):WaitForChild("Theme") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)

local REGION_ATTRIBUTE = "Region"
local REGION_SETTLE = 1.2 -- secondes dans la région avant d'afficher son nom
local REGION_TITLE_COOLDOWN = 120
local TITLE_FADE_IN = 1.2
local TITLE_HOLD = 3
local TITLE_FADE_OUT = 1.6
local PULSE_RADIUS = 90 -- studs : au-delà, le joueur n'est pas concerné
local PULSE_COLOR = Color3.fromRGB(255, 214, 150)
local PULSE_BRIGHTNESS = 2.2
local PULSE_RANGE = 14
local PULSE_DURATION = 1.4

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Sons de retour
--------------------------------------------------------------------------------

local feedbackSounds: { [string]: Sound } = {}
local function playFeedback(kind: string)
	local spec = (AudioConfig.FEEDBACK_SOUNDS :: any)[kind]
	if spec == nil or spec.id == "" then
		return
	end
	local sound: Sound? = feedbackSounds[kind]
	if sound == nil then
		local newSound = Instance.new("Sound")
		newSound.Name = "Feedback_" .. kind
		newSound.SoundId = spec.id
		newSound.Volume = spec.volume
		AudioMixer.assign(newSound, "Sfx")
		newSound.Parent = SoundService
		feedbackSounds[kind] = newSound
		sound = newSound
	end
	if sound and not sound.IsPlaying then
		sound:Play()
	end
end
UIBus.Feedback:Connect(playFeedback)

--------------------------------------------------------------------------------
-- Titre de lieu
--------------------------------------------------------------------------------

local screen = Theme.screenGui("RegionTitleGui", Theme.displayOrder.world)
local titleGroup, titleContent = Theme.group({
	name = "RegionTitle",
	style = "none",
	border = false,
	parent = screen.safe,
	anchor = Vector2.new(0.5, 0.5),
	position = UDim2.fromScale(0.5, 0.26),
	size = UDim2.fromOffset(720, 120),
	visible = false,
})
local nameLabel = Theme.title({
	parent = titleContent,
	font = Theme.fonts.display,
	textSize = 52,
	alignX = Enum.TextXAlignment.Center,
	size = UDim2.new(1, 0, 0, 62),
	stroke = true,
	scaled = true,
	maxTextSize = 52,
})
Theme.divider({ parent = titleContent, position = UDim2.new(0.2, 0, 0, 70), size = UDim2.new(0.6, 0, 0, 1) })
local subtitleLabel = Theme.caption({
	parent = titleContent,
	alignX = Enum.TextXAlignment.Center,
	color = Theme.colors.goldBright,
	position = UDim2.fromOffset(0, 80),
	size = UDim2.new(1, 0, 0, 22),
	stroke = true,
})

local lastShownAt: { [string]: number } = {}
local currentRegion: any = localPlayer:GetAttribute(REGION_ATTRIBUTE) -- pas de titre au chargement
local settleToken = 0
local showToken = 0

local function showTitle(regionId: string)
	local region = RegionConfig.getRegion(regionId)
	if region == nil then
		return
	end
	showToken += 1
	local token = showToken
	lastShownAt[regionId] = os.clock()
	nameLabel.Text = region.name
	subtitleLabel.Text = string.upper(region.subtitle)
	Theme.fade(titleGroup, true, TITLE_FADE_IN)
	playFeedback("regionEnter")
	task.delay(TITLE_FADE_IN + TITLE_HOLD, function()
		if token == showToken then
			Theme.fade(titleGroup, false, TITLE_FADE_OUT)
		end
	end)
end

local function canShowTitle(): boolean
	return localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) ~= true
		and not CreatorSession.isActive()
		and not CreatorSession.isArrivalBusy()
end

localPlayer:GetAttributeChangedSignal(REGION_ATTRIBUTE):Connect(function()
	local regionId = localPlayer:GetAttribute(REGION_ATTRIBUTE)
	if regionId == currentRegion then
		return
	end
	currentRegion = regionId
	settleToken += 1
	local token = settleToken
	task.delay(REGION_SETTLE, function()
		if token ~= settleToken or type(regionId) ~= "string" or not canShowTitle() then
			return
		end
		local last = lastShownAt[regionId]
		if last == nil or os.clock() - last > REGION_TITLE_COOLDOWN then
			showTitle(regionId)
		end
	end)
end)

--------------------------------------------------------------------------------
-- Lueur des mécanismes
--------------------------------------------------------------------------------

WorldRemotes.MechanismPulse.OnClientEvent:Connect(function(position: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or (root.Position - position).Magnitude > PULSE_RADIUS then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "MechanismPulse"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	local light = Instance.new("PointLight")
	light.Color = PULSE_COLOR
	light.Range = PULSE_RANGE
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	holder.Parent = workspace
	local peak = if ClientSettings.isReducedEffects() then PULSE_BRIGHTNESS * 0.45 else PULSE_BRIGHTNESS
	local rise = TweenService:Create(light, TweenInfo.new(PULSE_DURATION * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Brightness = peak })
	rise.Completed:Once(function()
		local fall = TweenService:Create(light, TweenInfo.new(PULSE_DURATION * 0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Brightness = 0 })
		fall.Completed:Once(function()
			holder:Destroy()
		end)
		fall:Play()
	end)
	rise:Play()
	playFeedback("mechanism")
end)
