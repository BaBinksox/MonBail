--!strict
--[[
	WorldMapController (LocalScript)
	Fait vivre la carte du monde construite par WorldMapView :
		- touche marquée TOGGLE_LETTER (M) : déroule ou range le parchemin ;
		- clic sur un continent : son nom, son surnom, sa vignette et son histoire s'affichent à droite ;
		- le pied de carte donne l'heure et le temps qu'il fait, lus dans l'état du monde.

	Purement local : la carte ne demande rien au serveur.

	La touche est reconnue par la lettre imprimée dessus, pas par son KeyCode : sur un clavier
	AZERTY, la touche "M" n'envoie pas Enum.KeyCode.M (voir Shared/Input/KeyboardLayout).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local worldFolder = sharedFolder:WaitForChild("World")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local KeyboardLayout = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyboardLayout") :: ModuleScript)
local Config = require(worldFolder:WaitForChild("WorldMapConfig") :: ModuleScript)
local WorldConfig = require(worldFolder:WaitForChild("WorldConfig") :: ModuleScript)

local WorldMapView = require(script.Parent:WaitForChild("WorldMapView") :: ModuleScript)

local OPEN_DURATION = 0.35
local CLOSE_DURATION = 0.2
local BACKDROP_TRANSPARENCY = 0.45 -- voile sombre derrière le parchemin, carte ouverte
local CLOSED_SCALE = 0.94 -- le parchemin grandit légèrement en s'ouvrant

local localPlayer = Players.LocalPlayer
local view = WorldMapView.create(localPlayer:WaitForChild("PlayerGui"))

local isOpen = false
local selectedId = Config.CURRENT_CONTINENT_ID

--------------------------------------------------------------------------------
-- Contenu
--------------------------------------------------------------------------------

local function tween(instance: Instance, duration: number, goal: { [string]: any }): Tween
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local newTween = TweenService:Create(instance, tweenInfo, goal)
	newTween:Play()
	return newTween
end

local function findContinent(id: string): any
	for _, continent in Config.CONTINENTS do
		if continent.id == id then
			return continent
		end
	end
	return Config.CONTINENTS[1]
end

-- Remplit le panneau de droite avec le continent `id` et encadre celui-ci sur la carte.
local function selectContinent(id: string)
	local continent = findContinent(id)
	selectedId = continent.id

	view.infoName.Text = continent.name
	view.infoEpithet.Text = continent.epithet
	view.infoLore.Text = continent.lore
	view.infoIllustration.Image = continent.illustration
	view.infoIllustrationHint.Visible = continent.illustration == ""
	view.infoHereTag.Visible = continent.id == Config.CURRENT_CONTINENT_ID

	for continentId, node in view.continents do
		node.outline.Transparency = if continentId == selectedId then 0.1 else 1
	end
end

-- "14 h  -  Brume  -  [M] ranger la carte" : l'heure et la météo du monde au moment où on ouvre la carte.
local function refreshFooter()
	local hour = math.floor(WorldConfig.getClockTime())
	local weather = WorldConfig.WEATHERS[workspace:GetAttribute(WorldConfig.WEATHER_ATTRIBUTE)]
	local weatherName = if weather then weather.name else ""
	view.footer.Text = `{hour} h  -  {weatherName}  -  [{Config.TOGGLE_LETTER}] ranger la carte`
end

--------------------------------------------------------------------------------
-- Ouverture / fermeture
--------------------------------------------------------------------------------

local function open()
	if isOpen then
		return
	end
	isOpen = true

	selectContinent(selectedId)
	refreshFooter()

	view.gui.Enabled = true
	tween(view.backdrop, OPEN_DURATION, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
	tween(view.sheet, OPEN_DURATION, { GroupTransparency = 0 })
	tween(view.sheetScale, OPEN_DURATION, { Scale = 1 })
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false

	tween(view.backdrop, CLOSE_DURATION, { BackgroundTransparency = 1 })
	tween(view.sheetScale, CLOSE_DURATION, { Scale = CLOSED_SCALE })
	tween(view.sheet, CLOSE_DURATION, { GroupTransparency = 1 }).Completed:Once(function()
		if not isOpen then -- pas rouverte pendant le fondu
			view.gui.Enabled = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Entrées
--------------------------------------------------------------------------------

for id, node in view.continents do
	node.button.Activated:Connect(function()
		selectContinent(id)
	end)
	-- Survol : le nom du continent s'éclaire.
	node.button.MouseEnter:Connect(function()
		node.nameLabel.TextStrokeTransparency = 0
	end)
	node.button.MouseLeave:Connect(function()
		node.nameLabel.TextStrokeTransparency = 0.25
	end)
end

view.closeButton.Activated:Connect(close)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	-- La touche pressée porte-t-elle la lettre de la carte sur CE clavier ?
	if not KeyboardLayout.isLetter(input.KeyCode, Config.TOGGLE_LETTER, Config.TOGGLE_KEY) then
		return
	end

	if isOpen then
		close() -- même si un bouton de la carte a le focus
	elseif not gameProcessed and localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) ~= true then
		open() -- jamais pendant le Hub de création, ni en tapant dans le chat
	end
end)

-- Trace de démarrage : confirme dans la fenêtre Output que ce script tourne, et dit quelle touche
-- physique ouvre la carte sur ce clavier (KeyCode.M en QWERTY, KeyCode.Semicolon en AZERTY).
if Config.DEBUG_LOGS then
	local keyCode = KeyboardLayout.findKeyCode(Config.TOGGLE_LETTER, Config.TOGGLE_KEY)
	print(`[Carte] Prête. La touche "{Config.TOGGLE_LETTER}" de ce clavier est KeyCode.{keyCode.Name}`)
end
