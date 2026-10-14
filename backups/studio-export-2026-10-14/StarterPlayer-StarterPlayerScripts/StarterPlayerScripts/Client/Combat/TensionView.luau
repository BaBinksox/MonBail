--!strict
--[[
	TensionView
	Construit la jauge de Tension, entièrement par code (rien à poser dans StarterGui).
	Comme AvatarCreatorView, ce module ne contient AUCUNE logique : il crée les instances
	et les expose, c'est CombatController qui remplit la barre et affiche l'invite.

	Arborescence produite :
		TensionGui (ScreenGui)
		└── Container (Frame)        bas de l'écran, centré
		    ├── Prompt               invite de l'ultime, visible seulement jauge pleine
		    ├── Caption              "TENSION"
		    └── Bar (Frame)          fond sombre + liseré
		        └── Fill             partie remplie (largeur = ratio de Tension)
]]

local COLOR_BACKGROUND = Color3.fromRGB(6, 6, 9)
local COLOR_MUTED = Color3.fromRGB(128, 122, 114)
local COLOR_ACCENT = Color3.fromRGB(176, 146, 96) -- or terni, comme le menu de création
local COLOR_FILL_START = Color3.fromRGB(70, 30, 140)
local COLOR_FILL_END = Color3.fromRGB(190, 120, 255)

local FONT_TITLE = Enum.Font.Garamond
local FONT_CAPTION = Enum.Font.GothamMedium

local CONTAINER_SIZE = UDim2.fromOffset(340, 52)
local BOTTOM_MARGIN = 36 -- pixels entre la jauge et le bas de l'écran
local BAR_HEIGHT = 10

export type View = {
	gui: ScreenGui,
	bar: Frame,
	barStroke: UIStroke,
	fill: Frame,
	prompt: TextLabel,
}

local TensionView = {}

function TensionView.create(parent: Instance): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "TensionGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10 -- sous le menu de création (50) et le glitch d'anomalie (100)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
	container.Size = CONTAINER_SIZE
	container.Parent = gui

	local prompt = Instance.new("TextLabel")
	prompt.Name = "Prompt"
	prompt.BackgroundTransparency = 1
	prompt.Size = UDim2.new(1, 0, 0, 22)
	prompt.Font = FONT_TITLE
	prompt.TextSize = 20
	prompt.TextColor3 = COLOR_FILL_END
	prompt.TextStrokeColor3 = COLOR_BACKGROUND
	prompt.TextStrokeTransparency = 0.3
	prompt.Text = ""
	prompt.Visible = false
	prompt.Parent = container

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(0, 26)
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.Font = FONT_CAPTION
	caption.TextSize = 11
	caption.TextColor3 = COLOR_MUTED
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = "TENSION"
	caption.Parent = container

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = COLOR_BACKGROUND
	bar.BackgroundTransparency = 0.25
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	bar.Parent = container

	local barStroke = Instance.new("UIStroke")
	barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barStroke.Color = COLOR_ACCENT
	barStroke.Transparency = 0.4
	barStroke.Thickness = 1
	barStroke.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1) -- la couleur vient du dégradé
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(COLOR_FILL_START, COLOR_FILL_END)
	fillGradient.Parent = fill

	gui.Parent = parent

	return {
		gui = gui,
		bar = bar,
		barStroke = barStroke,
		fill = fill,
		prompt = prompt,
	}
end

return TensionView
