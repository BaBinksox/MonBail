--!strict
--[[
	WorldMapView
	Construit la carte du monde, entièrement par code. Comme les autres vues, ce module ne contient
	AUCUNE logique : il crée les instances et les expose, c'est WorldMapController qui ouvre, ferme
	et réagit aux clics.

	Style : un vieux parchemin. Tout est dessiné avec des cadres, des dégradés et des polices,
	sans aucune image ; chaque emplacement d'image de WorldMapConfig remplace le dessin par défaut
	dès qu'il est renseigné.

	Arborescence produite :
		WorldMapGui (ScreenGui)
		├── Backdrop (TextButton)        voile sombre ; il absorbe les clics tant que la carte est ouverte
		└── Sheet (CanvasGroup)          le parchemin
		    ├── Title, Footer, Close
		    ├── MapArea                  mers, rose des vents, un cadre par continent
		    └── InfoPanel                nom, surnom, vignette et histoire du continent sélectionné
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World")
local Config = require(sharedFolder:WaitForChild("WorldMapConfig") :: ModuleScript)

local COLOR_PARCHMENT = Color3.fromRGB(218, 198, 158)
local COLOR_PARCHMENT_SHADE = Color3.fromRGB(168, 142, 100)
local COLOR_INK = Color3.fromRGB(52, 36, 22)
local COLOR_INK_FADED = Color3.fromRGB(110, 86, 60)
local COLOR_SEAL = Color3.fromRGB(140, 30, 30) -- rouge de cire, pour "Vous êtes ici"

local FONT_TITLE = Enum.Font.GrenzeGotisch -- gothique, pour les titres
local FONT_HAND = Enum.Font.Fondamento -- calligraphie, pour tout le reste

local SHEET_ASPECT_RATIO = 1.6
local MAP_AREA_WIDTH = 0.66 -- part du parchemin occupée par la carte (le reste : panneau d'informations)

-- Un continent sur la carte.
export type ContinentNode = {
	button: TextButton, -- zone cliquable
	nameLabel: TextLabel,
	outline: UIStroke, -- cadre de sélection
}

export type View = {
	gui: ScreenGui,
	backdrop: TextButton,
	sheet: CanvasGroup,
	sheetScale: UIScale,
	closeButton: TextButton,
	footer: TextLabel,
	continents: { [string]: ContinentNode }, -- par id de continent
	infoName: TextLabel,
	infoEpithet: TextLabel,
	infoLore: TextLabel,
	infoIllustration: ImageLabel,
	infoIllustrationHint: TextLabel, -- texte affiché tant qu'il n'y a pas d'illustration
	infoHereTag: TextLabel, -- "Vous êtes ici"
}

local WorldMapView = {}

local function new(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className) :: any
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function newText(properties: { [string]: any }, parent: Instance): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT_HAND,
		TextColor3 = COLOR_INK,
		TextSize = 20,
	}, nil)
	for property, value in properties do
		label[property] = value
	end
	label.Parent = parent
	return label
end

--------------------------------------------------------------------------------
-- Continents
--------------------------------------------------------------------------------

-- Silhouette par défaut : quelques taches arrondies qui se chevauchent, à l'encre du continent.
local function drawBlobs(continent: any, parent: Instance)
	for index, blob in continent.blobs do
		local shape = new("Frame", {
			Name = "Blob" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(blob.x, blob.y),
			Size = UDim2.fromScale(blob.width, blob.height),
			Rotation = blob.rotation,
			BackgroundColor3 = continent.color,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
		}, parent)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shape)
		new("UIStroke", { Color = COLOR_INK, Transparency = 0.55, Thickness = 1.5 }, shape)
	end
end

local function newContinent(continent: any, mapArea: Instance): ContinentNode
	local frame = new("Frame", {
		Name = continent.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(continent.position.X, continent.position.Y),
		Size = UDim2.fromScale(continent.size.X, continent.size.Y),
		BackgroundTransparency = 1,
	}, mapArea)

	if continent.image ~= "" then
		new("ImageLabel", {
			Name = "Shape",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = continent.image,
			ScaleType = Enum.ScaleType.Fit,
		}, frame)
	else
		drawBlobs(continent, frame)
	end

	local nameLabel = newText({
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.2, 0.3),
		Text = continent.name,
		TextColor3 = Color3.fromRGB(250, 238, 214),
		TextStrokeColor3 = COLOR_INK,
		TextStrokeTransparency = 0.25,
		TextScaled = true,
	}, frame)
	new("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 22 }, nameLabel)

	-- Zone cliquable transparente, au-dessus du dessin. Son liseré sert de cadre de sélection.
	local button = new("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
	}, frame)
	new("UICorner", { CornerRadius = UDim.new(0.12, 0) }, button)
	local outline = new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = COLOR_SEAL,
		Thickness = 2,
		Transparency = 1,
	}, button)

	return {
		button = button,
		nameLabel = nameLabel,
		outline = outline,
	}
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function WorldMapView.create(parent: Instance): View
	local gui = new("ScreenGui", {
		Name = "WorldMapGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, nil)

	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, gui)

	-- Parchemin -----------------------------------------------------------------
	local sheet = new("CanvasGroup", {
		Name = "Sheet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundColor3 = COLOR_PARCHMENT,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, gui)
	new("UIAspectRatioConstraint", { AspectRatio = SHEET_ASPECT_RATIO }, sheet)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, sheet)
	new("UIStroke", { Color = COLOR_INK, Thickness = 3, Transparency = 0.2 }, sheet)
	-- Papier vieilli : plus sombre vers les coins.
	new("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLOR_PARCHMENT_SHADE),
			ColorSequenceKeypoint.new(0.3, COLOR_PARCHMENT),
			ColorSequenceKeypoint.new(0.7, COLOR_PARCHMENT),
			ColorSequenceKeypoint.new(1, COLOR_PARCHMENT_SHADE),
		}),
	}, sheet)
	local sheetScale = new("UIScale", { Scale = 0.94 }, sheet)

	if Config.PARCHMENT_IMAGE ~= "" then
		new("ImageLabel", {
			Name = "ParchmentTexture",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Config.PARCHMENT_IMAGE,
			ScaleType = Enum.ScaleType.Crop,
		}, sheet)
	end

	-- Filet intérieur, comme sur une carte ancienne.
	local innerBorder = new("Frame", {
		Name = "InnerBorder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -28, 1, -28),
		BackgroundTransparency = 1,
	}, sheet)
	new("UIStroke", { Color = COLOR_INK_FADED, Thickness = 1, Transparency = 0.3 }, innerBorder)

	newText({
		Name = "Title",
		Position = UDim2.fromScale(0, 0.035),
		Size = UDim2.fromScale(MAP_AREA_WIDTH, 0.09),
		Font = FONT_TITLE,
		Text = Config.TITLE,
		TextScaled = true,
	}, sheet)

	local footer = newText({
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.04, 0.965),
		Size = UDim2.fromScale(MAP_AREA_WIDTH - 0.04, 0.045),
		Text = "",
		TextColor3 = COLOR_INK_FADED,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, sheet)

	local closeButton = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 20),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = FONT_TITLE,
		Text = "X",
		TextColor3 = COLOR_INK,
		TextSize = 30,
		ZIndex = 6,
	}, sheet)

	-- Carte ---------------------------------------------------------------------
	local mapArea = new("Frame", {
		Name = "MapArea",
		Position = UDim2.fromScale(0.03, 0.14),
		Size = UDim2.fromScale(MAP_AREA_WIDTH - 0.03, 0.76),
		BackgroundTransparency = 1,
	}, sheet)

	for _, sea in Config.SEAS do
		newText({
			Name = "Sea",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(sea.position.X, sea.position.Y),
			Size = UDim2.fromScale(0.3, 0.06),
			Rotation = sea.rotation,
			Text = sea.name,
			TextColor3 = COLOR_INK_FADED,
			TextTransparency = 0.35,
			TextScaled = true,
		}, mapArea)
	end

	-- Rose des vents, dessinée en caractères.
	local compass = new("Frame", {
		Name = "Compass",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.09, 0.14),
		Size = UDim2.fromScale(0.11, 0.11),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundTransparency = 1,
	}, mapArea)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, compass)
	new("UIStroke", { Color = COLOR_INK_FADED, Thickness = 1.5, Transparency = 0.2 }, compass)
	newText({ Name = "North", Size = UDim2.fromScale(1, 0.4), Font = FONT_TITLE, Text = "N", TextScaled = true }, compass)
	newText({
		Name = "Star",
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.6),
		Text = "+",
		TextColor3 = COLOR_INK_FADED,
		TextScaled = true,
	}, compass)

	local continents: { [string]: ContinentNode } = {}
	for _, continent in Config.CONTINENTS do
		continents[continent.id] = newContinent(continent, mapArea)
	end

	-- Panneau d'informations --------------------------------------------------------
	local infoPanel = new("Frame", {
		Name = "InfoPanel",
		Position = UDim2.fromScale(MAP_AREA_WIDTH + 0.01, 0.1),
		Size = UDim2.fromScale(1 - MAP_AREA_WIDTH - 0.05, 0.82),
		BackgroundColor3 = COLOR_PARCHMENT_SHADE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, sheet)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, infoPanel)
	new("UIStroke", { Color = COLOR_INK_FADED, Thickness = 1, Transparency = 0.3 }, infoPanel)
	new("UIPadding", {
		PaddingTop = UDim.new(0.03, 0),
		PaddingBottom = UDim.new(0.03, 0),
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
	}, infoPanel)

	local infoName = newText({
		Name = "Name",
		Size = UDim2.fromScale(1, 0.1),
		Font = FONT_TITLE,
		Text = "",
		TextScaled = true,
	}, infoPanel)

	local infoEpithet = newText({
		Name = "Epithet",
		Position = UDim2.fromScale(0, 0.1),
		Size = UDim2.fromScale(1, 0.06),
		Text = "",
		TextColor3 = COLOR_INK_FADED,
		TextScaled = true,
	}, infoPanel)

	-- Emplacement de la vignette du continent.
	local illustrationFrame = new("Frame", {
		Name = "IllustrationFrame",
		Position = UDim2.fromScale(0, 0.19),
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = COLOR_INK,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
	}, infoPanel)
	new("UIStroke", { Color = COLOR_INK_FADED, Thickness = 1, Transparency = 0.2 }, illustrationFrame)

	local infoIllustration = new("ImageLabel", {
		Name = "Illustration",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
	}, illustrationFrame)

	local infoIllustrationHint = newText({
		Name = "Hint",
		Size = UDim2.fromScale(1, 1),
		Text = "Illustration à venir",
		TextColor3 = COLOR_INK_FADED,
		TextTransparency = 0.3,
		TextSize = 18,
	}, illustrationFrame)

	local infoLore = newText({
		Name = "Lore",
		Position = UDim2.fromScale(0, 0.52),
		Size = UDim2.fromScale(1, 0.38),
		Text = "",
		TextWrapped = true,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, infoPanel)
	new("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 20 }, infoLore)

	local infoHereTag = newText({
		Name = "HereTag",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.07),
		Font = FONT_TITLE,
		Text = "Vous êtes ici",
		TextColor3 = COLOR_SEAL,
		TextScaled = true,
		Visible = false,
	}, infoPanel)

	gui.Parent = parent

	return {
		gui = gui,
		backdrop = backdrop,
		sheet = sheet,
		sheetScale = sheetScale,
		closeButton = closeButton,
		footer = footer,
		continents = continents,
		infoName = infoName,
		infoEpithet = infoEpithet,
		infoLore = infoLore,
		infoIllustration = infoIllustration,
		infoIllustrationHint = infoIllustrationHint,
		infoHereTag = infoHereTag,
	}
end

return WorldMapView
