--!strict
--[[
	DialogueView
	Construit la boîte de dialogue en bas de l'écran, entièrement par code. Aucune logique ici :
	c'est NPCInteraction qui écrit le texte lettre par lettre et réagit aux entrées.

	Arborescence produite :
		DialogueGui (ScreenGui)
		├── ClickCatcher (TextButton)   invisible, plein écran : un clic n'importe où fait avancer
		│                               le dialogue (et n'est donc pas pris pour un coup d'épée)
		└── Box (Frame)                 la boîte, en bas de l'écran
		    ├── NamePlate               nom du personnage qui parle
		    ├── Line                    la réplique
		    └── Hint                    rappel des touches, visible quand la réplique est finie
]]

local COLOR_BACKGROUND = Color3.fromRGB(6, 6, 9)
local COLOR_TEXT = Color3.fromRGB(226, 220, 208)
local COLOR_MUTED = Color3.fromRGB(128, 122, 114)
local COLOR_ACCENT = Color3.fromRGB(176, 146, 96) -- or terni, comme le Hub et la jauge

local FONT_TEXT = Enum.Font.Garamond
local FONT_CAPTION = Enum.Font.GothamMedium

local BOX_SIZE = UDim2.new(0.62, 0, 0, 150)
local BOTTOM_MARGIN = 96 -- pixels : au-dessus de la jauge de Tension

export type View = {
	gui: ScreenGui,
	clickCatcher: TextButton,
	namePlate: TextLabel,
	line: TextLabel,
	hint: TextLabel,
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

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
	box.Size = BOX_SIZE
	box.BackgroundColor3 = COLOR_BACKGROUND
	box.BackgroundTransparency = 0.12
	box.BorderSizePixel = 0
	box.Parent = gui

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

	gui.Parent = parent

	return {
		gui = gui,
		clickCatcher = clickCatcher,
		namePlate = namePlate,
		line = line,
		hint = hint,
	}
end

return DialogueView
