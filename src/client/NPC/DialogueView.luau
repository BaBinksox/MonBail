--!strict
--[[
	DialogueView
	Construit la boîte de dialogue en bas de l'écran, entièrement par code. Aucune logique ici :
	c'est NPCInteraction qui écrit le texte lettre par lettre et réagit aux entrées.

	Arborescence produite :
		DialogueGui (ScreenGui)
		├── ClickCatcher (TextButton)   invisible, plein écran : un clic n'importe où fait avancer
		│                               le dialogue (et n'est donc pas pris pour un coup d'épée)
		├── Box (Frame)                 la boîte, en bas de l'écran
		│   ├── NamePlate               nom du personnage qui parle
		│   ├── Line                    la réplique
		│   └── Hint                    rappel des touches, visible quand la réplique est finie
		└── Options (Frame)             choix proposés par le serveur (accepter une quête, ouvrir les contrats...)

	La taille s'adapte à l'écran (UIScale d'après la hauteur, largeur bornée) : lisible sur téléphone.
]]

local COLOR_BACKGROUND = Color3.fromRGB(6, 6, 9)
local COLOR_TEXT = Color3.fromRGB(226, 220, 208)
local COLOR_MUTED = Color3.fromRGB(128, 122, 114)
local COLOR_ACCENT = Color3.fromRGB(176, 146, 96) -- or terni, comme le Hub et la jauge

local FONT_TEXT = Enum.Font.Garamond
local FONT_CAPTION = Enum.Font.GothamMedium

local BOX_SIZE = UDim2.new(0.9, 0, 0, 150)
local BOX_MAX_WIDTH = 940 -- pixels (avant mise à l'échelle)
local BOTTOM_MARGIN = 96 -- pixels : au-dessus de la jauge de Tension
local REFERENCE_HEIGHT = 720 -- hauteur d'écran pour laquelle l'échelle vaut 1
local OPTION_HEIGHT = 40

export type Option = { id: string, label: string }

export type View = {
	gui: ScreenGui,
	clickCatcher: TextButton,
	namePlate: TextLabel,
	line: TextLabel,
	hint: TextLabel,
	options: Frame,
}

local DialogueView = {}

function DialogueView.create(parent: Instance): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "DialogueGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.AutoButtonColor = false
	clickCatcher.Text = ""
	clickCatcher.Parent = gui

	-- Mise à l'échelle selon la hauteur de l'écran (téléphone en paysage ~ 0.6, PC 1080p ~ 1.2).
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function refreshScale()
		local camera = workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
		scale.Scale = math.clamp(height / REFERENCE_HEIGHT, 0.6, 1.25)
	end
	refreshScale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
	box.Size = BOX_SIZE
	box.BackgroundColor3 = COLOR_BACKGROUND
	box.BackgroundTransparency = 0.12
	box.BorderSizePixel = 0
	box.Parent = gui

	local boxConstraint = Instance.new("UISizeConstraint")
	boxConstraint.MaxSize = Vector2.new(BOX_MAX_WIDTH, math.huge)
	boxConstraint.Parent = box

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 4)
	boxCorner.Parent = box

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = COLOR_ACCENT
	boxStroke.Thickness = 1
	boxStroke.Transparency = 0.3
	boxStroke.Parent = box

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 26)
	padding.PaddingRight = UDim.new(0, 26)
	padding.Parent = box

	-- Cartouche du nom, à cheval sur le bord supérieur de la boîte.
	local namePlate = Instance.new("TextLabel")
	namePlate.Name = "NamePlate"
	namePlate.AnchorPoint = Vector2.new(0, 0.5)
	namePlate.Position = UDim2.fromOffset(0, -22)
	namePlate.Size = UDim2.fromOffset(0, 30)
	namePlate.AutomaticSize = Enum.AutomaticSize.X
	namePlate.BackgroundColor3 = COLOR_BACKGROUND
	namePlate.BorderSizePixel = 0
	namePlate.Font = FONT_TEXT
	namePlate.Text = ""
	namePlate.TextSize = 22
	namePlate.TextColor3 = COLOR_ACCENT
	namePlate.Parent = box

	local namePadding = Instance.new("UIPadding")
	namePadding.PaddingLeft = UDim.new(0, 14)
	namePadding.PaddingRight = UDim.new(0, 14)
	namePadding.Parent = namePlate

	local nameStroke = Instance.new("UIStroke")
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	nameStroke.Color = COLOR_ACCENT
	nameStroke.Thickness = 1
	nameStroke.Transparency = 0.3
	nameStroke.Parent = namePlate

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.Size = UDim2.new(1, 0, 1, -22)
	line.BackgroundTransparency = 1
	line.Font = FONT_TEXT
	line.Text = ""
	line.TextSize = 25
	line.TextColor3 = COLOR_TEXT
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.Parent = box

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.fromScale(1, 1)
	hint.Size = UDim2.fromOffset(260, 18)
	hint.BackgroundTransparency = 1
	hint.Font = FONT_CAPTION
	hint.Text = ""
	hint.TextSize = 12
	hint.TextColor3 = COLOR_MUTED
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Visible = false
	hint.Parent = box

	-- Choix : une colonne de boutons au-dessus de la boîte, à droite.
	local options = Instance.new("Frame")
	options.Name = "Options"
	options.AnchorPoint = Vector2.new(1, 1)
	options.Position = UDim2.new(0.95, 0, 1, -(BOTTOM_MARGIN + 170))
	options.Size = UDim2.fromOffset(320, 0)
	options.AutomaticSize = Enum.AutomaticSize.Y
	options.BackgroundTransparency = 1
	options.Visible = false
	options.Parent = gui

	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.Padding = UDim.new(0, 8)
	optionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Parent = options

	gui.Parent = parent

	return {
		gui = gui,
		clickCatcher = clickCatcher,
		namePlate = namePlate,
		line = line,
		hint = hint,
		options = options,
	}
end

-- Affiche les choix `list` (numérotés 1, 2, 3...) ; `onChoose(id)` est appelé au clic.
-- Retourne les boutons (dans l'ordre) pour la navigation clavier / manette.
function DialogueView.setOptions(view: View, list: { Option }, onChoose: (id: string) -> ()): { TextButton }
	DialogueView.clearOptions(view)
	local buttons = {}
	for index, option in list do
		local button = Instance.new("TextButton")
		button.Name = `Option{index}`
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(320, OPTION_HEIGHT)
		button.BackgroundColor3 = COLOR_BACKGROUND
		button.BackgroundTransparency = 0.08
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Font = FONT_TEXT
		button.Text = `{index}.  {option.label}`
		button.TextSize = 21
		button.TextColor3 = COLOR_TEXT
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Selectable = true
		button.Parent = view.options

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = COLOR_ACCENT
		stroke.Transparency = 0.35
		stroke.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 14)
		padding.Parent = button

		button.Activated:Connect(function()
			onChoose(option.id)
		end)
		table.insert(buttons, button)
	end
	view.options.Visible = #buttons > 0
	return buttons
end

function DialogueView.clearOptions(view: View)
	for _, child in view.options:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	view.options.Visible = false
end

return DialogueView
