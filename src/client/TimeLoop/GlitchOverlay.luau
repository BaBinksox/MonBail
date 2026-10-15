--!strict
--[[
	GlitchOverlay
	La "rupture de la réalité" à l'écran, pour l'anomalie et pour le rembobinage. Local à ce client.

	Quatre couches, toutes re-tirées au hasard plusieurs fois par seconde :
		1. images de neige (ImageLabel, voir TimeLoopConfig.GLITCH_IMAGES) qui sautent et clignotent ;
		2. tranches : des bandes horizontales qui déchirent l'image ;
		3. flashs : l'écran entier claque d'une couleur ;
		4. post-traitement : ColorCorrection et BlurEffect poussés à l'extrême, champ de vision qui tressaute.

	Deux profils règlent la violence de l'ensemble : "anomaly" (malaise) et "rewind" (rupture totale).
	Une seule boucle RenderStepped, et seulement entre start() et stop().
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeLoop")
local Config = require(sharedFolder:WaitForChild("TimeLoopConfig") :: ModuleScript)
local ClientSettings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)

local REDUCED_INTERVAL = 2.5 -- « effets réduits » : sursauts d'image 2,5 fois plus espacés

type Range = { min: number, max: number }

type Profile = {
	interval: Range, -- secondes entre deux tirages
	sliceChance: number, -- probabilité qu'une tranche soit visible à un tirage
	sliceMaxHeight: number, -- hauteur maximale d'une tranche (fraction de l'écran)
	noiseTransparency: Range, -- transparence des images de neige (1 = invisibles)
	flashChance: number,
	blur: Range,
	contrast: Range,
	saturation: Range,
	brightness: Range,
	tints: { Color3 },
	fieldOfViewJitter: number, -- degrés
	messageJitter: number, -- pixels
}

local PROFILES: { [string]: Profile } = {
	-- Fenêtre critique : le monde vacille, mais on lit encore l'écran.
	anomaly = {
		interval = { min = 0.03, max = 0.12 },
		sliceChance = 0.3,
		sliceMaxHeight = 0.03,
		noiseTransparency = { min = 0.8, max = 0.95 },
		flashChance = 0.04,
		blur = { min = 8, max = 24 },
		contrast = { min = 0.3, max = 0.9 },
		saturation = { min = -1, max = -0.3 },
		brightness = { min = -0.05, max = 0.05 },
		tints = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(80, 255, 255),
			Color3.fromRGB(210, 70, 255),
			Color3.fromRGB(255, 255, 255),
		},
		fieldOfViewJitter = 2,
		messageJitter = 10,
	},
	-- Rembobinage : la réalité se déchire.
	rewind = {
		interval = { min = 0.02, max = 0.07 },
		sliceChance = 0.75,
		sliceMaxHeight = 0.1,
		noiseTransparency = { min = 0.4, max = 0.8 },
		flashChance = 0.2,
		blur = { min = 10, max = 46 },
		contrast = { min = 0.6, max = 1 },
		saturation = { min = -1, max = 1 },
		brightness = { min = -0.25, max = 0.3 },
		tints = {
			Color3.fromRGB(70, 255, 255),
			Color3.fromRGB(255, 60, 220),
			Color3.fromRGB(60, 80, 255),
			Color3.fromRGB(150, 255, 120),
			Color3.fromRGB(255, 255, 255),
		},
		fieldOfViewJitter = 9,
		messageJitter = 26,
	},
}

local SLICE_COUNT = 14
local SLICE_COLORS = {
	Color3.new(1, 1, 1),
	Color3.new(0, 0, 0),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(255, 0, 200),
}
local NOISE_TILE_SIZE = 420 -- pixels : taille d'une image de neige, répétée sur tout l'écran
local MESSAGE_POSITION = UDim2.fromScale(0.5, 0.3)
local NEUTRAL_COLOR = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }

local random = Random.new()

local GlitchOverlay = {}

-- Instances, créées une seule fois par init().
local gui: ScreenGui? = nil
local messageLabel: TextLabel
local captionLabel: TextLabel
local flashFrame: Frame
local slices: { Frame } = {}
local noiseLabels: { ImageLabel } = {}
local colorCorrection: ColorCorrectionEffect
local blur: BlurEffect

-- État de la boucle.
local connection: RBXScriptConnection? = nil
local colorTween: Tween? = nil
local baseFieldOfView: number? = nil

local function pick(range: Range): number
	return random:NextNumber(range.min, range.max)
end

local function new(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className) :: any
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- Crée les effets et l'interface. À appeler une fois, avant tout start().
function GlitchOverlay.init(playerGui: Instance)
	if gui then
		return
	end

	-- Créés depuis un LocalScript : ces effets n'existent que sur ce client.
	colorCorrection = new("ColorCorrectionEffect", { Name = "TimeLoopColorCorrection" }, Lighting)
	blur = new("BlurEffect", { Name = "TimeLoopBlur", Size = 0 }, Lighting)

	local screenGui = new("ScreenGui", {
		Name = "TimeLoopGlitchGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Enabled = false,
	}, nil)

	-- 1. Neige : chaque image est répétée en mosaïque sur un cadre plus grand que l'écran,
	--    qu'on décale au hasard à chaque tirage pour qu'elle "grésille".
	for index, image in Config.GLITCH_IMAGES do
		noiseLabels[index] = new("ImageLabel", {
			Name = "Noise" .. index,
			BackgroundTransparency = 1,
			Image = image,
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(NOISE_TILE_SIZE, NOISE_TILE_SIZE),
			Size = UDim2.new(1, NOISE_TILE_SIZE, 1, NOISE_TILE_SIZE),
			ZIndex = 1,
		}, screenGui)
	end

	-- 2. Tranches.
	for index = 1, SLICE_COUNT do
		slices[index] = new("Frame", {
			Name = "Slice" .. index,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		}, screenGui)
	end

	-- 3. Flash plein écran.
	flashFrame = new("Frame", {
		Name = "Flash",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, screenGui)

	-- Texte central (message de l'anomalie) et légende en coin (compteur du rembobinage).
	messageLabel = new("TextLabel", {
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = MESSAGE_POSITION,
		Size = UDim2.fromScale(0.8, 0.1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 70, 70),
		TextScaled = true,
		TextStrokeTransparency = 0,
		ZIndex = 4,
	}, screenGui)

	captionLabel = new("TextLabel", {
		Name = "Caption",
		Position = UDim2.fromOffset(36, 28),
		Size = UDim2.fromOffset(520, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 34,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, screenGui)

	screenGui.Parent = playerGui
	gui = screenGui
end

--------------------------------------------------------------------------------
-- Boucle
--------------------------------------------------------------------------------

-- Un tirage : toutes les couches prennent de nouvelles valeurs au hasard.
local function applyFrame(profile: Profile)
	local tint = profile.tints[random:NextInteger(1, #profile.tints)]

	colorCorrection.TintColor = tint
	colorCorrection.Contrast = pick(profile.contrast)
	colorCorrection.Saturation = pick(profile.saturation)
	colorCorrection.Brightness = pick(profile.brightness)
	blur.Size = pick(profile.blur)

	for _, noise in noiseLabels do
		noise.ImageTransparency = pick(profile.noiseTransparency)
		noise.Position = UDim2.fromOffset(-random:NextInteger(0, NOISE_TILE_SIZE), -random:NextInteger(0, NOISE_TILE_SIZE))
	end

	for _, slice in slices do
		local isVisible = random:NextNumber() < profile.sliceChance
		slice.Visible = isVisible
		if isVisible then
			slice.Position = UDim2.fromScale(random:NextNumber(-0.1, 0.4), random:NextNumber())
			slice.Size = UDim2.fromScale(random:NextNumber(0.3, 1.1), random:NextNumber(0.003, profile.sliceMaxHeight))
			slice.BackgroundColor3 = SLICE_COLORS[random:NextInteger(1, #SLICE_COLORS)]
			slice.BackgroundTransparency = random:NextNumber(0.15, 0.7)
		end
	end

	local isFlashing = random:NextNumber() < profile.flashChance
	flashFrame.BackgroundColor3 = tint
	flashFrame.BackgroundTransparency = if isFlashing then random:NextNumber(0.55, 0.85) else 1

	local jitter = profile.messageJitter
	messageLabel.Position = MESSAGE_POSITION
		+ UDim2.fromOffset(random:NextInteger(-jitter, jitter), random:NextInteger(-jitter, jitter))

	local camera = workspace.CurrentCamera
	if camera and baseFieldOfView then
		camera.FieldOfView = baseFieldOfView + random:NextNumber(-profile.fieldOfViewJitter, profile.fieldOfViewJitter)
	end
end

local function disconnect()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Lance (ou change) le glitch. `profileName` : "anomaly" ou "rewind".
function GlitchOverlay.start(profileName: string)
	local profile = PROFILES[profileName]
	local screenGui = gui
	if profile == nil or screenGui == nil then
		return
	end

	disconnect()
	if colorTween then
		colorTween:Cancel() -- un retour à la normale en cours écraserait les valeurs du glitch
		colorTween = nil
	end

	local camera = workspace.CurrentCamera
	if baseFieldOfView == nil and camera then
		baseFieldOfView = camera.FieldOfView
	end

	screenGui.Enabled = true
	local nextFrameClock = 0
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now >= nextFrameClock then
			nextFrameClock = now + pick(profile.interval) * (if ClientSettings.isReducedEffects() then REDUCED_INTERVAL else 1)
			applyFrame(profile)
		end
	end)
end

-- Arrête le glitch : l'interface disparaît d'un coup, l'image revient à la normale en `fadeDuration` secondes.
function GlitchOverlay.stop(fadeDuration: number)
	disconnect()
	if gui then
		gui.Enabled = false
	end
	if blur then
		blur.Size = 0
	end

	local camera = workspace.CurrentCamera
	if camera and baseFieldOfView then
		camera.FieldOfView = baseFieldOfView
	end
	baseFieldOfView = nil

	if colorCorrection then
		local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local tween = TweenService:Create(colorCorrection, tweenInfo, NEUTRAL_COLOR)
		colorTween = tween
		tween:Play()
	end
end

-- Texte au centre de l'écran ("" pour l'effacer).
function GlitchOverlay.setMessage(text: string)
	if gui then
		messageLabel.Text = text
	end
end

-- Texte en haut à gauche, façon affichage de magnétoscope ("" pour l'effacer).
function GlitchOverlay.setCaption(text: string)
	if gui then
		captionLabel.Text = text
	end
end

return GlitchOverlay
