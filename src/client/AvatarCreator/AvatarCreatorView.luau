--!strict
--[[
	AvatarCreatorView
	Construit le ScreenGui du Hub de création, entièrement par code (rien à poser dans StarterGui,
	et l'interface est versionnée avec le reste). Ce module ne contient AUCUNE logique : il crée les
	instances et les expose, c'est AvatarCreatorController qui les anime et écoute les boutons.

	Le panneau a deux pages, affichées l'une après l'autre :
		1. ÉVEIL  : l'apparence (7 sélecteurs "< valeur >") et le bouton pour continuer ;
		2. DESTIN : le choix de la Magie Innée (un bouton par magie), sa description, la validation.

	Arborescence produite :
		AvatarCreatorGui (ScreenGui)
		├── Panel (CanvasGroup)          panneau, à droite
		│   ├── Shade                    dégradé noir qui fond vers la scène
		│   └── Content
		│       ├── AppearancePage
		│       └── DestinyPage
		└── Fade (Frame)                 voile noir plein écran (intro et transitions)
		    └── IntroLabel               texte de narration
]]

local COLOR_BACKGROUND = Color3.fromRGB(6, 6, 9)
local COLOR_TEXT = Color3.fromRGB(226, 220, 208)
local COLOR_MUTED = Color3.fromRGB(128, 122, 114)
local COLOR_ACCENT = Color3.fromRGB(176, 146, 96) -- or terni

local FONT_TITLE = Enum.Font.Garamond
local FONT_CAPTION = Enum.Font.GothamMedium

local PANEL_WIDTH_SCALE = 0.34
local LIST_PADDING = 10
local STEPPER_HEIGHT = 52
local STEPPER_BUTTON_SIZE = 34
local MAGIC_BUTTON_HEIGHT = 44
local MAGIC_DESCRIPTION_HEIGHT = 92
-- Hauteur d'écran (pixels) pour laquelle le contenu est dessiné. En dessous, il rétrécit en bloc.
local REFERENCE_SCREEN_HEIGHT = 640

-- Sélecteur "< valeur >" : sert aux listes (coiffures, visages...) comme aux échelles.
export type Stepper = {
	valueLabel: TextLabel,
	counterLabel: TextLabel, -- position dans la liste, ex. "3 / 15" (vide pour une échelle)
	previousButton: TextButton,
	nextButton: TextButton,
}

-- Bouton d'une Magie Innée dans la page DESTIN.
export type MagicButton = {
	button: TextButton,
	stroke: UIStroke, -- liseré, mis en avant quand la magie est sélectionnée
}

-- Ce que la vue a besoin de savoir d'une magie pour dessiner son bouton.
export type MagicEntry = {
	name: string,
	color: Color3,
}

export type View = {
	gui: ScreenGui,
	panel: CanvasGroup,
	fade: Frame,
	introLabel: TextLabel,

	appearancePage: Frame,
	baseStepper: Stepper,
	faceStepper: Stepper,
	markStepper: Stepper,
	hairStepper: Stepper,
	outfitStepper: Stepper,
	heightStepper: Stepper,
	widthStepper: Stepper,
	nextButton: TextButton,

	destinyPage: Frame,
	magicButtons: { MagicButton },
	magicDescription: TextLabel,
	confirmButton: TextButton,
	backButton: TextButton,
}

local AvatarCreatorView = {}

--------------------------------------------------------------------------------
-- Briques de base
--------------------------------------------------------------------------------

local function newLabel(text: string, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color
	return label
end

local function newArrowButton(text: string): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromOffset(STEPPER_BUTTON_SIZE, STEPPER_BUTTON_SIZE)
	button.Font = FONT_TITLE
	button.Text = text
	button.TextSize = 28
	button.TextColor3 = COLOR_ACCENT
	return button
end

local function newSeparator(layoutOrder: number, parent: Instance)
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.BorderSizePixel = 0
	separator.BackgroundColor3 = COLOR_ACCENT
	separator.BackgroundTransparency = 0.5
	separator.Size = UDim2.new(0.5, 0, 0, 1)
	separator.LayoutOrder = layoutOrder
	separator.Parent = parent
end

-- Titre + sous-titre + séparateur en tête d'une page (LayoutOrder 1 à 3).
local function newPageHeader(title: string, subtitle: string, parent: Instance)
	local titleLabel = newLabel(title, FONT_TITLE, 40, COLOR_TEXT)
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 44)
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = parent

	local subtitleLabel = newLabel(subtitle, FONT_TITLE, 18, COLOR_MUTED)
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(1, 0, 0, 20)
	subtitleLabel.LayoutOrder = 2
	subtitleLabel.Parent = parent

	newSeparator(3, parent)
end

-- Grand bouton à liseré doré (continuer, valider).
local function newWideButton(name: string, text: string, layoutOrder: number, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = COLOR_ACCENT
	button.BackgroundTransparency = 1
	button.Size = UDim2.new(1, 0, 0, 44)
	button.Font = FONT_TITLE
	button.Text = text
	button.TextSize = 22
	button.TextColor3 = COLOR_TEXT
	button.LayoutOrder = layoutOrder
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = COLOR_ACCENT
	stroke.Thickness = 1
	stroke.Parent = button

	return button
end

-- Une page du panneau : un cadre plein, dont les enfants s'empilent verticalement, centrés.
local function newPage(name: string, parent: Instance): Frame
	local page = Instance.new("Frame")
	page.Name = name
	page.BackgroundTransparency = 1
	page.Size = UDim2.fromScale(1, 1)
	page.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, LIST_PADDING)
	layout.Parent = page

	return page
end

local function newStepper(name: string, caption: string, layoutOrder: number, parent: Instance): Stepper
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, STEPPER_HEIGHT)
	frame.LayoutOrder = layoutOrder
	frame.Parent = parent

	local captionLabel = newLabel(caption, FONT_CAPTION, 12, COLOR_MUTED)
	captionLabel.Name = "Caption"
	captionLabel.Size = UDim2.new(1, 0, 0, 16)
	captionLabel.Parent = frame

	local counterLabel = newLabel("", FONT_CAPTION, 11, COLOR_MUTED)
	counterLabel.Name = "Counter"
	counterLabel.Size = UDim2.new(1, 0, 0, 16)
	counterLabel.TextXAlignment = Enum.TextXAlignment.Right
	counterLabel.Parent = frame

	local previousButton = newArrowButton("<")
	previousButton.Name = "Previous"
	previousButton.AnchorPoint = Vector2.new(0, 1)
	previousButton.Position = UDim2.fromScale(0, 1)
	previousButton.Parent = frame

	local nextButton = newArrowButton(">")
	nextButton.Name = "Next"
	nextButton.AnchorPoint = Vector2.new(1, 1)
	nextButton.Position = UDim2.fromScale(1, 1)
	nextButton.Parent = frame

	local valueLabel = newLabel("", FONT_TITLE, 24, COLOR_TEXT)
	valueLabel.Name = "Value"
	valueLabel.AnchorPoint = Vector2.new(0.5, 1)
	valueLabel.Position = UDim2.fromScale(0.5, 1)
	valueLabel.Size = UDim2.new(1, -2 * STEPPER_BUTTON_SIZE, 0, STEPPER_BUTTON_SIZE)
	valueLabel.TextScaled = true -- les noms longs rétrécissent au lieu de déborder
	valueLabel.Parent = frame

	local valueSizeLimit = Instance.new("UITextSizeConstraint")
	valueSizeLimit.MinTextSize = 12
	valueSizeLimit.MaxTextSize = 23
	valueSizeLimit.Parent = valueLabel

	return {
		valueLabel = valueLabel,
		counterLabel = counterLabel,
		previousButton = previousButton,
		nextButton = nextButton,
	}
end

-- Bouton d'une magie : son nom, précédé d'une barre à sa couleur.
local function newMagicButton(entry: MagicEntry, layoutOrder: number, parent: Instance): MagicButton
	local button = Instance.new("TextButton")
	button.Name = "Magic" .. layoutOrder
	button.AutoButtonColor = false
	button.BackgroundColor3 = entry.color
	button.BackgroundTransparency = 1
	button.Size = UDim2.new(1, 0, 0, MAGIC_BUTTON_HEIGHT)
	button.Font = FONT_TITLE
	button.Text = entry.name
	button.TextSize = 24
	button.TextColor3 = COLOR_TEXT
	button.LayoutOrder = layoutOrder
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = entry.color
	stroke.Thickness = 1
	stroke.Transparency = 0.75
	stroke.Parent = button

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.BorderSizePixel = 0
	swatch.BackgroundColor3 = entry.color
	swatch.Size = UDim2.new(0, 4, 1, 0)
	swatch.Parent = button

	return {
		button = button,
		stroke = stroke,
	}
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- `magicEntries` : une entrée par Magie Innée, dans l'ordre de MagicConfig.MAGICS.
function AvatarCreatorView.create(parent: Instance, magicEntries: { MagicEntry }): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "AvatarCreatorGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	-- Panneau ---------------------------------------------------------------
	local panel = Instance.new("CanvasGroup") -- CanvasGroup : permet de fondre tout le panneau d'un coup
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.fromScale(1, 0)
	panel.Size = UDim2.fromScale(PANEL_WIDTH_SCALE, 1)
	panel.Parent = gui

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = COLOR_BACKGROUND
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = panel

	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.25),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	shadeGradient.Parent = shade

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(1, 0.5)
	content.Position = UDim2.fromScale(1, 0.5)
	content.Size = UDim2.fromScale(0.8, 1)
	content.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 32)
	padding.Parent = content

	-- Sur un petit écran (ou une petite fenêtre Studio), tout le contenu rétrécit pour rester visible.
	local contentScale = Instance.new("UIScale")
	contentScale.Parent = content

	local function updateContentScale()
		contentScale.Scale = math.min(1, gui.AbsoluteSize.Y / REFERENCE_SCREEN_HEIGHT)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContentScale)

	-- Page 1 : apparence ------------------------------------------------------
	local appearancePage = newPage("AppearancePage", content)
	newPageHeader("É V E I L", "Souvenez-vous de qui vous étiez.", appearancePage)

	local baseStepper = newStepper("Base", "CORPS", 4, appearancePage)
	local faceStepper = newStepper("Face", "VISAGE", 5, appearancePage)
	local markStepper = newStepper("Mark", "CICATRICES ET TATOUAGES", 6, appearancePage)
	local hairStepper = newStepper("Hair", "CHEVELURE", 7, appearancePage)
	local outfitStepper = newStepper("Outfit", "TENUE", 8, appearancePage)
	local heightStepper = newStepper("Height", "TAILLE", 9, appearancePage)
	local widthStepper = newStepper("Width", "CARRURE", 10, appearancePage)

	newSeparator(11, appearancePage)
	local nextButton = newWideButton("Next", "CONTINUER", 12, appearancePage)

	-- Page 2 : Magie Innée ----------------------------------------------------
	local destinyPage = newPage("DestinyPage", content)
	destinyPage.Visible = false
	newPageHeader("D E S T I N", "Une seule magie coule dans vos veines.", destinyPage)

	local magicButtons: { MagicButton } = {}
	for index, entry in magicEntries do
		magicButtons[index] = newMagicButton(entry, 3 + index, destinyPage)
	end
	local afterMagics = 3 + #magicEntries

	local magicDescription = newLabel("", FONT_TITLE, 17, COLOR_MUTED)
	magicDescription.Name = "MagicDescription"
	magicDescription.Size = UDim2.new(1, 0, 0, MAGIC_DESCRIPTION_HEIGHT)
	magicDescription.TextWrapped = true
	magicDescription.TextYAlignment = Enum.TextYAlignment.Top
	magicDescription.RichText = true
	magicDescription.LayoutOrder = afterMagics + 1
	magicDescription.Parent = destinyPage

	newSeparator(afterMagics + 2, destinyPage)
	local confirmButton = newWideButton("Confirm", "", afterMagics + 3, destinyPage)

	local backButton = Instance.new("TextButton")
	backButton.Name = "Back"
	backButton.AutoButtonColor = false
	backButton.BackgroundTransparency = 1
	backButton.Size = UDim2.new(1, 0, 0, 24)
	backButton.Font = FONT_TITLE
	backButton.Text = "Revenir à l'apparence"
	backButton.TextSize = 17
	backButton.TextColor3 = COLOR_MUTED
	backButton.LayoutOrder = afterMagics + 4
	backButton.Parent = destinyPage

	-- Voile noir + narration (au-dessus de tout) -----------------------------
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BorderSizePixel = 0
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 10
	fade.Parent = gui

	local introLabel = newLabel("", FONT_TITLE, 30, COLOR_TEXT)
	introLabel.Name = "IntroLabel"
	introLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	introLabel.Position = UDim2.fromScale(0.5, 0.5)
	introLabel.Size = UDim2.fromScale(0.8, 0.2)
	introLabel.TextWrapped = true
	introLabel.TextTransparency = 1
	introLabel.ZIndex = 11
	introLabel.Parent = fade

	gui.Parent = parent
	updateContentScale()

	return {
		gui = gui,
		panel = panel,
		fade = fade,
		introLabel = introLabel,

		appearancePage = appearancePage,
		baseStepper = baseStepper,
		faceStepper = faceStepper,
		markStepper = markStepper,
		hairStepper = hairStepper,
		outfitStepper = outfitStepper,
		heightStepper = heightStepper,
		widthStepper = widthStepper,
		nextButton = nextButton,

		destinyPage = destinyPage,
		magicButtons = magicButtons,
		magicDescription = magicDescription,
		confirmButton = confirmButton,
		backButton = backButton,
	}
end

return AvatarCreatorView
