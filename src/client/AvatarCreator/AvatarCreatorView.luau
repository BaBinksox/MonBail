--!strict
--[[
	AvatarCreatorView
	Construit l'interface du créateur de personnage avec Theme, entièrement par code (rien à poser
	dans StarterGui). Aucune règle de jeu ni aucun Remote ici : la vue crée les éléments, les met en
	page selon l'écran et sait les mettre à jour (option choisie, carte sélectionnée, récapitulatif).
	AvatarCreatorController décide QUOI afficher et QUAND.

	Disposition : le personnage est TOUJOURS dans la zone libre (Stage), rien ne le recouvre.
		Écran large (PC, tablette, téléphone en paysage)     Écran haut (téléphone, tablette en portrait)
		+------+--------------------+-----------+            +----------------------------+
		| Rail |    personnage      |  Panneau  |            | Rail (onglets défilants)   |
		|      |                    | d'options |            +----------------------------+
		|      |  (<)          (>)  |           |            |        personnage          |
		+------+--------------------+-----------+            |  (<)                  (>)  |
		                                                     +----------------------------+
		                                                     | Feuille d'options          |
		                                                     +----------------------------+
	La zone libre est MESURÉE (positions réelles du rail et du panneau) puis transmise à la caméra,
	qui y cadre le personnage : aucune position codée en dur ne peut le faire chevaucher.

	Arborescence :
		AvatarCreatorGui (ScreenGui, Theme.screenGui)
		└── Root (toile virtuelle de Theme)
		    ├── DragZone      bouton invisible plein écran : glisser = tourner la vue
		    ├── Shade         assombrit les bords de l'écran (jamais le centre)
		    ├── Safe
		    │   ├── RailSlot  emplacement fixe du rail ; Rail glisse dedans à l'apparition
		    │   └── PanelSlot emplacement fixe du panneau ; Panel = en-tête, pages, pied, confirmation
		    ├── Stage         zone libre : boutons de rotation et rappel des commandes en bas
		    └── Veil          voile noir (intro, fondus) et texte de narration
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Avatar"):WaitForChild("AvatarConfig"))
local MagicConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Magic"):WaitForChild("MagicConfig"))
local SpellConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Magic"):WaitForChild("SpellConfig"))
local MagicShowcase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Magic"):WaitForChild("MagicShowcase"))
local SpellTags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Magic"):WaitForChild("SpellTags"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Catalog = require(script.Parent:WaitForChild("AvatarCreatorCatalog"))

type Button = Theme.Button
type Slider = Theme.Slider
type Tabs = Theme.Tabs
type Layout = Theme.Layout
type Step = Catalog.Step
type Magic = MagicConfig.Magic

export type Mode = "wide" | "tall"

-- Rectangle normalisé de l'écran (même forme que AvatarCreatorCamera.Window).
export type Window = {
	x: number,
	y: number,
	width: number,
	height: number,
}

-- Grille de vignettes d'une étape "liste".
export type OptionGrid = {
	stepIndex: number,
	scroller: ScrollingFrame,
	layout: UIGridLayout,
	tiles: { Button },
}

-- Carte d'une Magie Innée (page Destin).
export type MagicCard = {
	button: TextButton,
	stroke: UIStroke,
	magic: Magic,
	isHovered: boolean,
	isLocked: boolean, -- la Roulette du Destin a scellé une autre magie
	previewButton: Button, -- « Aperçu » : gestes et effets de la magie, purement visuels
}

-- État de la Roulette du Destin (page Destin).
export type DestinyState = "idle" | "confirm" | "spinning" | "sealed" | "error"

-- Ligne du récapitulatif : cliquer ramène à l'étape.
export type SummaryRow = {
	button: Button,
	valueLabel: TextLabel,
	stepIndex: number,
}

local COLORS = Theme.colors
local FONTS = Theme.fonts

local DISPLAY_ORDER = Theme.displayOrder.creator
local EDGE_MARGIN = 12 -- px virtuels entre le bord de l'écran et le rail / le panneau
local RAIL_HEADER_HEIGHT = 56
local RAIL_TALL_HEIGHT = 56
local HEADER_HEIGHT = 84
local HEADER_HEIGHT_COMPACT = 62
local FOOTER_HEIGHT = 50
local SELECTOR_HEIGHT = 58
local CONFIRM_BOX_HEIGHT = 124
local DESCRIPTION_HEIGHT = 150 -- texte d'une option (peuples : récit, avantage, inconvénient)
local CONTROLS_BAND = 64 -- bande des boutons de rotation, sous le personnage (px virtuels)
local TILE_ASPECT = 0.82 -- largeur / hauteur d'une vignette (le nom tient sous l'image)
local TILE_GAP = 8
local CHROME_SHOW_DURATION = 0.6
local CHROME_HIDE_DURATION = 0.4
local PAGE_FADE_OUT = 0.1
local PAGE_FADE_IN = 0.2
local DEFAULT_SKIN = Color3.fromRGB(234, 190, 152) -- avant de connaître la couleur de peau du personnage
local DEFAULT_WINDOW: Window = { x = 0.2, y = 0.05, width = 0.45, height = 0.8 }

local AvatarCreatorView = {}
AvatarCreatorView.__index = AvatarCreatorView

type ViewData = {
	screen: Theme.Screen,
	gui: ScreenGui,
	dragZone: TextButton,

	railSlot: Frame,
	railConstraint: UISizeConstraint,
	rail: Frame,
	railPadding: UIPadding,
	railHeader: Frame,
	tabs: Tabs,

	panelSlot: Frame,
	panelConstraint: UISizeConstraint,
	panel: Frame,
	panelPadding: UIPadding,
	header: Frame,
	stepCaption: TextLabel,
	titleLabel: TextLabel,
	subtitleLabel: TextLabel,
	pagesGroup: CanvasGroup,

	optionsPage: Frame,
	previousOption: Button,
	nextOption: Button,
	optionName: TextLabel,
	optionCounter: TextLabel,
	grids: { [number]: OptionGrid }, -- par index d'étape

	proportionsPage: Frame,
	heightSlider: Slider,
	widthSlider: Slider,
	resetProportions: Button,

	destinyPage: Frame,
	magicCards: { MagicCard },
	spinButton: Button,
	spinConfirmButton: Button,
	spinCancelButton: Button,
	spinStatus: TextLabel,
	spinConfirmRow: Frame,
	optionDescription: TextLabel,
	optionDescriptionScroller: ScrollingFrame,

	summaryPage: Frame,
	summaryRows: { SummaryRow },
	powerButton: Button,
	powerBand: UIGradient,
	powerName: TextLabel,
	powerUltimate: TextLabel,
	errorLabel: TextLabel,
	confirmBox: Frame,

	footer: Frame,
	backButton: Button,
	nextButton: Button,

	stage: Frame,
	stageControls: CanvasGroup,
	rotateLeft: Button,
	rotateRight: Button,
	hintLabel: TextLabel,

	veil: Frame,
	introLabel: TextLabel,

	mode: Mode,
	_columns: number,
	_selectedMagic: number,
	_chromeShown: boolean,
	_pageToken: number,
	_stageDirty: boolean,
	_stageListeners: { (window: Window) -> () },
	_skinDiscs: { Frame },
	_veilTween: Tween?,
	_narrationTween: Tween?,
}

export type View = typeof(setmetatable({} :: ViewData, AvatarCreatorView))

--------------------------------------------------------------------------------
-- Briques
--------------------------------------------------------------------------------

local function newFrame(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = parent
	return frame
end

local function addCorner(object: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = object
end

local function addStroke(object: GuiObject, color: Color3, transparency: number, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = object
	return stroke
end

local function addListLayout(parent: Instance, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

local function addUniformPadding(parent: Instance, padding: number): UIPadding
	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingTop = UDim.new(0, padding)
	uiPadding.PaddingBottom = UDim.new(0, padding)
	uiPadding.PaddingLeft = UDim.new(0, padding)
	uiPadding.PaddingRight = UDim.new(0, padding)
	uiPadding.Parent = parent
	return uiPadding
end

-- Pastille ronde (base des vignettes dessinées).
local function newDisc(parent: Instance, color: Color3, transparency: number): Frame
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = color
	disc.BackgroundTransparency = transparency
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	addCorner(disc, UDim.new(0.5, 0))
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = disc
	disc.Parent = parent
	return disc
end

local function newImage(name: string, image: string, parent: Instance): ImageLabel
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = name
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = image
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	imageLabel.Position = UDim2.fromScale(0.5, 0.5)
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.Parent = parent
	return imageLabel
end

--------------------------------------------------------------------------------
-- Vignettes
--------------------------------------------------------------------------------

-- Dessine la vignette d'une option dans `parent`. Les pastilles couleur peau sont ajoutées à `skinDiscs`.
local function drawThumbnail(thumbnail: Catalog.Thumbnail, parent: Frame, skinDiscs: { Frame })
	local kind = thumbnail.kind
	local image = thumbnail.image

	if kind == "image" and image then
		local disc = newDisc(parent, COLORS.sunken, 0.35)
		addStroke(disc, COLORS.goldDim, 0.6, 1)
		newImage("Thumbnail", image, parent)
		local inset = thumbnail.inset
		if inset then
			-- Petit médaillon en coin : la cape d'une tenue.
			local insetFrame = newFrame("Inset", parent)
			insetFrame.AnchorPoint = Vector2.new(1, 1)
			insetFrame.Position = UDim2.fromScale(1, 1)
			insetFrame.Size = UDim2.fromScale(0.42, 0.42)
			local insetDisc = newDisc(insetFrame, COLORS.background, 0.05)
			addStroke(insetDisc, COLORS.gold, 0.3, 1)
			local insetImage = newImage("InsetImage", inset, insetDisc)
			insetImage.Size = UDim2.fromScale(0.9, 0.9)
		end
	elseif kind == "face" and image then
		local disc = newDisc(parent, DEFAULT_SKIN, 0)
		addStroke(disc, COLORS.goldDim, 0.4, 1)
		local face = newImage("Face", image, disc)
		face.Size = UDim2.fromScale(0.94, 0.94)
		table.insert(skinDiscs, disc)
	elseif kind == "swatches" and thumbnail.colors and #thumbnail.colors > 0 then
		-- Tenue ou ornement fabriqué : ses couleurs en anneaux concentriques, sceau au centre.
		local colors = thumbnail.colors
		local outer = newDisc(parent, colors[1], 0)
		addStroke(outer, COLORS.gold, 0.25, 1.5)
		local holder: Frame = outer
		for index = 2, math.min(#colors, 4) do
			local ring = newDisc(holder, colors[index], 0)
			ring.Name = "Ring" .. index
			ring.Size = UDim2.fromScale(0.74, 0.74)
			holder = ring
		end
		local seal = newDisc(holder, COLORS.background, 0.15)
		seal.Name = "Seal"
		seal.Size = UDim2.fromScale(0.6, 0.6)
		addStroke(seal, COLORS.gold, 0.4, 1)
		Theme.title({
			name = "Initial",
			text = thumbnail.text or "",
			color = COLORS.goldBright,
			alignX = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(0.62, 0.62),
			scaled = true,
			maxTextSize = 48,
			parent = seal,
		})
	elseif kind == "swatch" and thumbnail.color then
		local disc = newDisc(parent, thumbnail.color, 0)
		addStroke(disc, COLORS.gold, 0.25, 1.5)
	elseif kind == "medallion" or kind == "swatch" then
		local disc = newDisc(parent, COLORS.sunken, 0.2)
		addStroke(disc, COLORS.gold, 0.2, 1.5)
		Theme.title({
			name = "Initial",
			text = thumbnail.text or "",
			color = COLORS.goldBright,
			alignX = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(0.6, 0.6),
			scaled = true,
			maxTextSize = 64,
			parent = disc,
		})
	else
		local disc = newDisc(parent, COLORS.sunken, 0.5)
		addStroke(disc, COLORS.goldDim, 0.6, 1)
		Theme.label({
			name = "None",
			text = "—",
			color = COLORS.textMuted,
			alignX = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(0.5, 0.5),
			scaled = true,
			maxTextSize = 40,
			parent = disc,
		})
	end
end

-- Vignette cliquable d'une option : image en haut, nom dessous.
local function createTile(entry: Catalog.OptionEntry, index: number, parent: Instance, skinDiscs: { Frame }): Button
	local tile = Theme.button({
		name = "Option" .. index,
		text = entry.name,
		font = FONTS.caption,
		textSize = 12,
		layoutOrder = index,
		parent = parent,
	})
	local label = tile.label
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -4)
	label.Size = UDim2.new(1, -8, 0.2, 0)
	label.TextWrapped = true

	local thumb = newFrame("Thumb", tile.instance)
	thumb.AnchorPoint = Vector2.new(0.5, 0)
	thumb.Position = UDim2.new(0.5, 0, 0, 6)
	thumb.Size = UDim2.new(1, -12, 0.76, -8)
	drawThumbnail(entry.thumbnail, thumb, skinDiscs)
	return tile
end

--------------------------------------------------------------------------------
-- Cartes de magie
--------------------------------------------------------------------------------

local function refreshCard(card: MagicCard, isSelected: boolean)
	local palette = card.magic.palette
	local isHovered = card.isHovered and not card.isLocked
	Theme.tween(card.stroke, {
		Transparency = if isSelected then 0 elseif card.isLocked then 0.9 elseif isHovered then 0.2 else 0.65,
		Thickness = if isSelected then 2 else 1,
	}, Theme.durations.fast)
	Theme.tween(card.button, {
		BackgroundColor3 = if isSelected then palette.main elseif isHovered then COLORS.surfaceHover else COLORS.surface,
		BackgroundTransparency = if isSelected then 0.72 elseif card.isLocked then 0.7 elseif isHovered then 0.08 else 0.18,
	}, Theme.durations.fast)
end

-- "#RRGGBB" d'une couleur, pour le texte enrichi.
local function hexOf(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function createMagicCard(magic: Magic, index: number, parent: Instance): MagicCard
	local button = Instance.new("TextButton")
	button.Name = "Magic_" .. magic.id
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.BackgroundColor3 = COLORS.surface
	button.BackgroundTransparency = 0.3
	button.Size = UDim2.new(1, -8, 0, 0)
	button.AutomaticSize = Enum.AutomaticSize.Y
	button.LayoutOrder = index
	Theme.makeSelectable(button)
	addCorner(button, UDim.new(0, Theme.cornerRadius))
	local stroke = addStroke(button, magic.palette.main, 0.65, 1)

	-- Bande aux couleurs de la magie : cœur sombre -> couleur dominante -> éclat.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.Position = UDim2.fromOffset(6, 8)
	band.Size = UDim2.new(0, 5, 1, -16)
	addCorner(band, UDim.new(0.5, 0))
	local bandGradient = Instance.new("UIGradient")
	bandGradient.Color = Theme.magicGradient(magic.palette)
	bandGradient.Rotation = 90
	bandGradient.Parent = band
	band.Parent = button

	local texts = newFrame("Texts", button)
	texts.Position = UDim2.fromOffset(20, 0)
	texts.Size = UDim2.new(1, -30, 0, 0)
	texts.AutomaticSize = Enum.AutomaticSize.Y
	local textPadding = Instance.new("UIPadding")
	textPadding.PaddingTop = UDim.new(0, 10)
	textPadding.PaddingBottom = UDim.new(0, 12)
	textPadding.Parent = texts
	addListLayout(texts, 3)

	-- En-tête : nom de la magie et bouton d'aperçu (gestes et effets, sans aucun effet de jeu).
	local header = newFrame("Header", texts)
	header.Size = UDim2.new(1, 0, 0, 30)
	header.LayoutOrder = 1
	Theme.title({
		name = "Name",
		text = magic.name,
		textSize = 24,
		color = magic.palette.glow,
		size = UDim2.new(1, -116, 1, 0),
		parent = header,
	})
	local previewButton = Theme.button({
		name = "Preview",
		text = "Aperçu",
		glyph = "▶",
		textSize = 13,
		accent = magic.palette.main,
		anchor = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0, 108, 1, 0),
		parent = header,
	})

	local profile = MagicShowcase.get(magic.id)
	local order = 1
	local function nextOrder(): number
		order += 1
		return order
	end
	local accentHex = hexOf(magic.palette.main)

	if profile then
		Theme.label({
			name = "Identity",
			text = profile.identity,
			textSize = 15,
			color = COLORS.text,
			wrap = true,
			autoSize = "Y",
			size = UDim2.new(1, 0, 0, 0),
			layoutOrder = nextOrder(),
			parent = texts,
		})
		local level = math.clamp(profile.difficulty, 1, #MagicShowcase.DIFFICULTY_LABELS)
		Theme.caption({
			name = "Difficulty",
			text = `Difficulté : {MagicShowcase.DIFFICULTY_LABELS[level]}  {string.rep("●", level)}{string.rep("○", #MagicShowcase.DIFFICULTY_LABELS - level)}`,
			color = magic.palette.main,
			size = UDim2.new(1, 0, 0, 16),
			layoutOrder = nextOrder(),
			parent = texts,
		})
	end

	-- Les deux sorts, tirés de SpellConfig (noms, coûts et descriptions réels).
	local function spellLine(slot: string, title: string)
		local spell = SpellConfig.forMagic(magic.id, slot)
		if spell == nil then
			return
		end
		Theme.label({
			name = if slot == "base" then "BaseSpell" else "SecondarySpell",
			text = `<b>{title} · {spell.name}</b>  <font color="{accentHex}">{spell.manaCost} Mana</font>\n<i>{SpellTags.describe(spell)}</i> — {spell.description}`,
			textSize = 14,
			color = COLORS.text,
			rich = true,
			wrap = true,
			autoSize = "Y",
			size = UDim2.new(1, 0, 0, 0),
			layoutOrder = nextOrder(),
			parent = texts,
		})
	end
	spellLine("base", "Sort de base (1)")
	spellLine("secondary", "Sort secondaire (2)")

	Theme.caption({
		name = "Ultimate",
		text = `Ultime (E) · {magic.ultimateName}`,
		color = magic.palette.main,
		size = UDim2.new(1, 0, 0, 16),
		scaled = true,
		minTextSize = 9,
		layoutOrder = nextOrder(),
		parent = texts,
	})
	Theme.label({
		name = "Description",
		text = magic.description,
		textSize = 14,
		color = COLORS.textMuted,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = nextOrder(),
		parent = texts,
	})
	Theme.label({
		name = "Advantage",
		text = `✦ {magic.advantage}`,
		textSize = 14,
		color = COLORS.success,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = nextOrder(),
		parent = texts,
	})
	Theme.label({
		name = "Drawback",
		text = `✧ {magic.drawback}`,
		textSize = 14,
		color = COLORS.danger,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = nextOrder(),
		parent = texts,
	})

	-- Style tactique : une phrase, puis quatre jauges (dégâts, contrôle, mobilité, soutien).
	if profile then
		Theme.label({
			name = "Playstyle",
			text = profile.playstyle,
			textSize = 13,
			color = COLORS.textMuted,
			wrap = true,
			autoSize = "Y",
			size = UDim2.new(1, 0, 0, 0),
			layoutOrder = nextOrder(),
			parent = texts,
		})
		local roles = newFrame("Roles", texts)
		roles.Size = UDim2.new(1, 0, 0, 0)
		roles.AutomaticSize = Enum.AutomaticSize.Y
		roles.LayoutOrder = nextOrder()
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0.5, -6, 0, 16)
		grid.CellPadding = UDim2.fromOffset(8, 4)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = roles
		for roleIndex, role in MagicShowcase.ROLE_ORDER do
			local value = math.clamp((profile.roles :: any)[role.key] or 0, 0, MagicShowcase.MAX_ROLE)
			local cell = newFrame("Role_" .. role.key, roles)
			cell.LayoutOrder = roleIndex
			Theme.caption({
				name = "Label",
				text = role.label,
				color = if value > 0 then COLORS.text else COLORS.textMuted,
				size = UDim2.new(0.5, -4, 1, 0),
				parent = cell,
			})
			local track = newFrame("Track", cell)
			track.BackgroundTransparency = 0.6
			track.BackgroundColor3 = COLORS.ink
			track.AnchorPoint = Vector2.new(1, 0.5)
			track.Position = UDim2.fromScale(1, 0.5)
			track.Size = UDim2.new(0.5, 0, 0, 6)
			addCorner(track, UDim.new(0.5, 0))
			local fill = newFrame("Fill", track)
			fill.BackgroundTransparency = 0
			fill.BackgroundColor3 = magic.palette.main
			fill.Size = UDim2.fromScale(value / MagicShowcase.MAX_ROLE, 1)
			addCorner(fill, UDim.new(0.5, 0))
			cell:SetAttribute("Value", value)
		end
	end

	button.Parent = parent
	return { button = button, stroke = stroke, magic = magic, isHovered = false, isLocked = false, previewButton = previewButton }
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function buildShade(root: Frame)
	local shade = newFrame("Shade", root)
	shade.ZIndex = 2

	-- Chaque bord : sombre contre le bord de l'écran, transparent vers le centre (rotation du dégradé).
	type Edge = { name: string, position: UDim2, size: UDim2, rotation: number }
	local edges: { Edge } = {
		{ name = "Left", position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.3, 1), rotation = 0 },
		{ name = "Right", position = UDim2.fromScale(0.7, 0), size = UDim2.fromScale(0.3, 1), rotation = 180 },
		{ name = "Top", position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.18), rotation = 90 },
		{ name = "Bottom", position = UDim2.fromScale(0, 0.78), size = UDim2.fromScale(1, 0.22), rotation = -90 },
	}
	for _, edge in edges do
		local frame = Instance.new("Frame")
		frame.Name = edge.name
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = COLORS.ink
		frame.Position = edge.position
		frame.Size = edge.size
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rotation
		gradient.Transparency = NumberSequence.new(0.35, 1)
		gradient.Parent = frame
		frame.Parent = shade
	end
end

-- Construit l'interface. `steps` : étapes du catalogue ; `magics` : MagicConfig.MAGICS (nombre libre).
function AvatarCreatorView.new(steps: { Step }, magics: { Magic }): View
	local screen = Theme.screenGui("AvatarCreatorGui", DISPLAY_ORDER)
	local gui = screen.gui
	gui.Enabled = false
	local root = screen.root

	-- Zone de glisser : sous tout le reste ; un clic sur la scène n'atteint jamais le monde.
	local dragZone = Instance.new("TextButton")
	dragZone.Name = "DragZone"
	dragZone.AutoButtonColor = false
	dragZone.BackgroundTransparency = 1
	dragZone.Text = ""
	dragZone.Size = UDim2.fromScale(1, 1)
	dragZone.Selectable = false
	dragZone.ZIndex = 1
	dragZone.Parent = root

	buildShade(root)
	screen.safe.ZIndex = 3

	-- Rail ------------------------------------------------------------------------
	local railSlot = newFrame("RailSlot", screen.safe)
	local railConstraint = Instance.new("UISizeConstraint")
	railConstraint.Parent = railSlot

	local rail = Theme.panel({ name = "Rail", style = "glass", active = true, parent = railSlot })
	rail.Size = UDim2.fromScale(1, 1)
	local railPadding = addUniformPadding(rail, 10)

	local railHeader = newFrame("Header", rail)
	railHeader.Size = UDim2.new(1, 0, 0, RAIL_HEADER_HEIGHT)
	Theme.caption({
		text = "SOUVENEZ-VOUS",
		color = COLORS.gold,
		alignX = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 16),
		parent = railHeader,
	})
	Theme.title({
		text = "Éveil",
		textSize = 28,
		alignX = Enum.TextXAlignment.Center,
		position = UDim2.fromOffset(0, 16),
		size = UDim2.new(1, 0, 0, 32),
		parent = railHeader,
	})

	local tabItems: { Theme.TabItem } = {}
	for index, step in steps do
		tabItems[index] = {
			id = step.id,
			label = step.label,
			glyph = step.numeral,
			separatorBefore = step.kind == "destiny",
		}
	end
	local tabs = Theme.tabs({
		items = tabItems,
		orientation = "vertical",
		autoSelect = false,
		thickness = 42,
		length = 132,
		textSize = 16,
		parent = rail,
	})

	-- Panneau --------------------------------------------------------------------
	local panelSlot = newFrame("PanelSlot", screen.safe)
	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.Parent = panelSlot

	local panel = Theme.panel({ name = "Panel", style = "panel", active = true, parent = panelSlot })
	panel.Size = UDim2.fromScale(1, 1)
	local panelPadding = addUniformPadding(panel, 18)

	local header = newFrame("Header", panel)
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	local stepCaption = Theme.caption({ name = "Step", color = COLORS.gold, size = UDim2.new(1, 0, 0, 16), parent = header })
	local titleLabel = Theme.title({
		name = "Title",
		textSize = 32,
		position = UDim2.fromOffset(0, 18),
		size = UDim2.new(1, 0, 0, 36),
		scaled = true,
		minTextSize = 18,
		parent = header,
	})
	local subtitleLabel = Theme.label({
		name = "Subtitle",
		textSize = 16,
		color = COLORS.textMuted,
		position = UDim2.fromOffset(0, 56),
		size = UDim2.new(1, 0, 0, 20),
		scaled = true,
		minTextSize = 11,
		parent = header,
	})
	Theme.divider({ anchor = Vector2.new(0, 1), position = UDim2.fromScale(0, 1), parent = header })

	local pagesGroup, pages = Theme.group({ name = "Pages", style = "none", border = false, corner = 0, parent = panel })

	local footer = newFrame("Footer", panel)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT)
	local backButton = Theme.button({
		name = "Back",
		text = "‹  Précédent",
		size = UDim2.new(0.4, -4, 1, 0),
		parent = footer,
	})
	local nextButton = Theme.button({
		name = "Next",
		text = "Suivant  ›",
		variant = "primary",
		anchor = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0.6, -4, 1, 0),
		parent = footer,
	})

	-- Confirmation (au-dessus du pied, dans le panneau : elle ne couvre jamais le personnage).
	local confirmBox = Theme.panel({
		name = "ConfirmBox",
		style = "raised",
		borderColor = COLORS.danger,
		padding = 12,
		active = true,
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, 0, 1, -(FOOTER_HEIGHT + 8)),
		size = UDim2.new(1, 0, 0, CONFIRM_BOX_HEIGHT),
		visible = false,
		zIndex = 5,
		parent = panel,
	})
	confirmBox.BackgroundTransparency = 0.02
	Theme.caption({ text = "IRRÉVERSIBLE", color = COLORS.danger, size = UDim2.new(1, 0, 0, 16), parent = confirmBox })
	Theme.label({
		text = "Rouvrir les yeux avec ce corps et ce pouvoir ? Une fois éveillé, plus rien de tout cela ne pourra être changé.",
		textSize = 16,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
		position = UDim2.fromOffset(0, 22),
		size = UDim2.new(1, 0, 1, -22),
		scaled = true,
		minTextSize = 11,
		parent = confirmBox,
	})

	-- Page : options en liste -------------------------------------------------------
	local optionsPage = newFrame("OptionsPage", pages)
	local selector = newFrame("Selector", optionsPage)
	selector.Size = UDim2.new(1, 0, 0, SELECTOR_HEIGHT)
	local previousOption = Theme.iconButton({
		name = "PreviousOption",
		glyph = "‹",
		textSize = 30,
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromScale(0, 0.5),
		size = UDim2.fromOffset(48, 48),
		parent = selector,
	})
	local nextOption = Theme.iconButton({
		name = "NextOption",
		glyph = "›",
		textSize = 30,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		size = UDim2.fromOffset(48, 48),
		parent = selector,
	})
	local optionName = Theme.title({
		name = "OptionName",
		textSize = 24,
		alignX = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 4),
		size = UDim2.new(1, -116, 0, 30),
		scaled = true,
		minTextSize = 14,
		parent = selector,
	})
	local optionCounter = Theme.caption({
		name = "Counter",
		alignX = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 36),
		size = UDim2.new(1, -116, 0, 16),
		parent = selector,
	})

	-- Texte de l'option (peuples) : récit, avantage, inconvénient. Défile s'il est long.
	local optionDescriptionScroller = Theme.scroller({
		name = "Description",
		position = UDim2.fromOffset(0, SELECTOR_HEIGHT + 4),
		size = UDim2.new(1, 0, 0, DESCRIPTION_HEIGHT),
		visible = false,
		parent = optionsPage,
	})
	local optionDescription = Theme.label({
		name = "Text",
		textSize = 15,
		wrap = true,
		rich = true,
		autoSize = "Y",
		alignY = Enum.TextYAlignment.Top,
		size = UDim2.new(1, -8, 0, 0),
		parent = optionDescriptionScroller,
	})
	optionDescription.LineHeight = 1.08

	local skinDiscs: { Frame } = {}
	local grids: { [number]: OptionGrid } = {}
	for stepIndex, step in steps do
		local list = step.list
		if list then
			local hasDescription = false
			for _, entry in list.options do
				if entry.description then
					hasDescription = true
				end
			end
			local gridTop = SELECTOR_HEIGHT + 8 + (if hasDescription then DESCRIPTION_HEIGHT + 8 else 0)
			local scroller = Theme.scroller({
				name = "Grid_" .. step.id,
				position = UDim2.fromOffset(0, gridTop),
				size = UDim2.new(1, 0, 1, -gridTop),
				visible = false,
				parent = optionsPage,
			})
			addUniformPadding(scroller, 4) -- place pour le cadre de sélection manette

			local layout = Instance.new("UIGridLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
			layout.CellSize = UDim2.new(1 / 3, -TILE_GAP, 0, 100)
			local cellAspect = Instance.new("UIAspectRatioConstraint")
			cellAspect.AspectRatio = TILE_ASPECT
			cellAspect.DominantAxis = Enum.DominantAxis.Width
			cellAspect.Parent = layout
			layout.Parent = scroller

			local tiles: { Button } = {}
			for optionIndex, entry in list.options do
				tiles[optionIndex] = createTile(entry, optionIndex, scroller, skinDiscs)
			end
			grids[stepIndex] = { stepIndex = stepIndex, scroller = scroller, layout = layout, tiles = tiles }
		end
	end

	-- Page : proportions -----------------------------------------------------------
	local proportionsPage = newFrame("ProportionsPage", pages)
	proportionsPage.Visible = false
	addListLayout(proportionsPage, 14)
	Theme.label({
		text = "Ajustez votre taille et votre carrure, cran par cran. Les bornes sont celles du monde.",
		textSize = 15,
		color = COLORS.textMuted,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = 1,
		parent = proportionsPage,
	})
	local heightRange = AvatarConfig.HEIGHT_SCALE
	local heightSlider = Theme.slider({
		name = "Height",
		label = "TAILLE",
		min = heightRange.min,
		max = heightRange.max,
		step = heightRange.step,
		value = heightRange.default,
		format = Catalog.formatScale,
		layoutOrder = 2,
		parent = proportionsPage,
	})
	local widthRange = AvatarConfig.WIDTH_SCALE
	local widthSlider = Theme.slider({
		name = "Width",
		label = "CARRURE",
		min = widthRange.min,
		max = widthRange.max,
		step = widthRange.step,
		value = widthRange.default,
		format = Catalog.formatScale,
		layoutOrder = 3,
		parent = proportionsPage,
	})
	local resetProportions = Theme.button({
		name = "ResetProportions",
		text = "Revenir aux proportions d'origine",
		variant = "ghost",
		textSize = 16,
		size = UDim2.new(1, 0, 0, 40),
		layoutOrder = 4,
		parent = proportionsPage,
	})

	-- Page : Destin ----------------------------------------------------------------
	local destinyPage = newFrame("DestinyPage", pages)
	destinyPage.Visible = false
	local destinyScroller = Theme.scroller({ name = "Magics", parent = destinyPage })
	addUniformPadding(destinyScroller, 4)
	addListLayout(destinyScroller, 10)

	-- Roulette du Destin : règles, bouton, confirmation, verdict. Toujours gratuite.
	local roulette = Theme.panel({ name = "Roulette", style = "raised", padding = 10, size = UDim2.new(1, -8, 0, 0), layoutOrder = 0, parent = destinyScroller })
	roulette.AutomaticSize = Enum.AutomaticSize.Y
	addListLayout(roulette, 6)
	Theme.caption({ text = "ROULETTE DU DESTIN", color = COLORS.goldBright, size = UDim2.new(1, 0, 0, 16), layoutOrder = 1, parent = roulette })
	Theme.label({
		name = "Rules",
		text = MagicConfig.DESTINY_RULES,
		textSize = 14,
		color = COLORS.textMuted,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = 2,
		parent = roulette,
	})
	local spinButton = Theme.button({
		name = "Spin",
		text = "Laisser le destin choisir",
		glyph = "✶",
		size = UDim2.new(1, 0, 0, 40),
		layoutOrder = 3,
		parent = roulette,
	})
	local spinConfirmRow = newFrame("ConfirmRow", roulette)
	spinConfirmRow.Size = UDim2.new(1, 0, 0, 40)
	spinConfirmRow.LayoutOrder = 4
	spinConfirmRow.Visible = false
	local spinConfirmButton = Theme.button({
		name = "SpinConfirm",
		text = "Tourner la roue",
		variant = "primary",
		size = UDim2.new(0.5, -4, 1, 0),
		parent = spinConfirmRow,
	})
	local spinCancelButton = Theme.button({
		name = "SpinCancel",
		text = "Je choisirai moi-même",
		anchor = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0.5, -4, 1, 0),
		parent = spinConfirmRow,
	})
	local spinStatus = Theme.label({
		name = "Status",
		text = "Ou choisissez vous-même une magie ci-dessous.",
		textSize = 15,
		wrap = true,
		rich = true,
		autoSize = "Y",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = 5,
		parent = roulette,
	})

	local magicCards: { MagicCard } = {}
	for index, magic in magics do
		magicCards[index] = createMagicCard(magic, index, destinyScroller)
	end

	-- Page : récapitulatif ---------------------------------------------------------
	local summaryPage = newFrame("SummaryPage", pages)
	summaryPage.Visible = false
	local summaryScroller = Theme.scroller({ name = "Summary", parent = summaryPage })
	addUniformPadding(summaryScroller, 4)
	addListLayout(summaryScroller, 6)

	local summaryRows: { SummaryRow } = {}
	for stepIndex, step in steps do
		if step.kind == "list" or step.kind == "proportions" then
			local row = Theme.button({
				name = "Row_" .. step.id,
				variant = "ghost",
				size = UDim2.new(1, -8, 0, 44),
				layoutOrder = stepIndex,
				parent = summaryScroller,
			})
			Theme.caption({
				text = `{step.numeral}   {string.upper(step.label)}`,
				color = COLORS.gold,
				position = UDim2.fromOffset(12, 0),
				size = UDim2.new(0.4, -12, 1, 0),
				scaled = true,
				minTextSize = 9,
				parent = row.instance,
			})
			local valueLabel = Theme.label({
				name = "Value",
				textSize = 17,
				alignX = Enum.TextXAlignment.Right,
				anchor = Vector2.new(1, 0),
				position = UDim2.new(1, -28, 0, 0),
				size = UDim2.new(0.6, -28, 1, 0),
				scaled = true,
				minTextSize = 11,
				parent = row.instance,
			})
			Theme.label({
				text = "›",
				color = COLORS.goldDim,
				alignX = Enum.TextXAlignment.Center,
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -6, 0.5, 0),
				size = UDim2.fromOffset(18, 24),
				parent = row.instance,
			})
			table.insert(summaryRows, { button = row, valueLabel = valueLabel, stepIndex = stepIndex })
		end
	end

	-- Ligne du pouvoir : bande colorée, nom, ultime.
	local powerButton = Theme.button({
		name = "Row_destiny",
		variant = "ghost",
		size = UDim2.new(1, -8, 0, 76),
		layoutOrder = #steps + 1,
		parent = summaryScroller,
	})
	local powerBandFrame = Instance.new("Frame")
	powerBandFrame.Name = "Band"
	powerBandFrame.BorderSizePixel = 0
	powerBandFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	powerBandFrame.Position = UDim2.fromOffset(4, 8)
	powerBandFrame.Size = UDim2.new(0, 5, 1, -16)
	addCorner(powerBandFrame, UDim.new(0.5, 0))
	local powerBand = Instance.new("UIGradient")
	powerBand.Rotation = 90
	powerBand.Parent = powerBandFrame
	powerBandFrame.Parent = powerButton.instance
	Theme.caption({
		text = "POUVOIR",
		color = COLORS.gold,
		position = UDim2.fromOffset(18, 8),
		size = UDim2.new(1, -46, 0, 16),
		parent = powerButton.instance,
	})
	local powerName = Theme.title({
		name = "PowerName",
		textSize = 24,
		position = UDim2.fromOffset(18, 24),
		size = UDim2.new(1, -46, 0, 28),
		scaled = true,
		minTextSize = 14,
		parent = powerButton.instance,
	})
	local powerUltimate = Theme.caption({
		name = "PowerUltimate",
		position = UDim2.fromOffset(18, 52),
		size = UDim2.new(1, -46, 0, 16),
		scaled = true,
		minTextSize = 9,
		parent = powerButton.instance,
	})

	Theme.label({
		name = "Warning",
		text = "Ce choix est irréversible : une fois éveillé, votre apparence et votre Magie Innée ne pourront plus être modifiées.",
		textSize = 15,
		color = COLORS.textMuted,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, -8, 0, 0),
		layoutOrder = #steps + 2,
		parent = summaryScroller,
	})
	local errorLabel = Theme.label({
		name = "Error",
		textSize = 15,
		color = COLORS.danger,
		wrap = true,
		autoSize = "Y",
		size = UDim2.new(1, -8, 0, 0),
		layoutOrder = #steps + 3,
		visible = false,
		parent = summaryScroller,
	})

	-- Zone libre du personnage : boutons de rotation et rappel des commandes ------------
	local stage = newFrame("Stage", root)
	stage.ZIndex = 4
	local stageControls, stageContent = Theme.group({
		name = "Controls",
		style = "none",
		border = false,
		corner = 0,
		anchor = Vector2.new(0, 1),
		position = UDim2.fromScale(0, 1),
		size = UDim2.new(1, 0, 0, CONTROLS_BAND),
		parent = stage,
	})
	local rotateLeft = Theme.iconButton({
		name = "RotateLeft",
		glyph = "⟲",
		round = true,
		textSize = 26,
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 12, 0.5, 0),
		size = UDim2.fromOffset(48, 48),
		parent = stageContent,
	})
	local rotateRight = Theme.iconButton({
		name = "RotateRight",
		glyph = "⟳",
		round = true,
		textSize = 26,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -12, 0.5, 0),
		size = UDim2.fromOffset(48, 48),
		parent = stageContent,
	})
	local hintLabel = Theme.caption({
		name = "Hint",
		alignX = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, -140, 0, 34),
		wrap = true,
		scaled = true,
		maxTextSize = 13,
		minTextSize = 8,
		stroke = true,
		parent = stageContent,
	})

	-- Voile noir et narration (au-dessus de tout) -------------------------------------
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BorderSizePixel = 0
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.Size = UDim2.fromScale(1, 1)
	veil.Active = true
	veil.ZIndex = 100
	veil.Parent = root
	local introLabel = Theme.label({
		name = "IntroLabel",
		font = FONTS.title,
		textSize = 30,
		alignX = Enum.TextXAlignment.Center,
		wrap = true,
		transparency = 1,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.8, 0.3),
		parent = veil,
	})

	local data: ViewData = {
		screen = screen,
		gui = gui,
		dragZone = dragZone,
		railSlot = railSlot,
		railConstraint = railConstraint,
		rail = rail,
		railPadding = railPadding,
		railHeader = railHeader,
		tabs = tabs,
		panelSlot = panelSlot,
		panelConstraint = panelConstraint,
		panel = panel,
		panelPadding = panelPadding,
		header = header,
		stepCaption = stepCaption,
		titleLabel = titleLabel,
		subtitleLabel = subtitleLabel,
		pagesGroup = pagesGroup,
		optionsPage = optionsPage,
		previousOption = previousOption,
		nextOption = nextOption,
		optionName = optionName,
		optionCounter = optionCounter,
		grids = grids,
		proportionsPage = proportionsPage,
		heightSlider = heightSlider,
		widthSlider = widthSlider,
		resetProportions = resetProportions,
		destinyPage = destinyPage,
		magicCards = magicCards,
		spinButton = spinButton,
		spinConfirmButton = spinConfirmButton,
		spinCancelButton = spinCancelButton,
		spinStatus = spinStatus,
		spinConfirmRow = spinConfirmRow,
		optionDescription = optionDescription,
		optionDescriptionScroller = optionDescriptionScroller,
		summaryPage = summaryPage,
		summaryRows = summaryRows,
		powerButton = powerButton,
		powerBand = powerBand,
		powerName = powerName,
		powerUltimate = powerUltimate,
		errorLabel = errorLabel,
		confirmBox = confirmBox,
		footer = footer,
		backButton = backButton,
		nextButton = nextButton,
		stage = stage,
		stageControls = stageControls,
		rotateLeft = rotateLeft,
		rotateRight = rotateRight,
		hintLabel = hintLabel,
		veil = veil,
		introLabel = introLabel,
		mode = "wide",
		_columns = 3,
		_selectedMagic = 1,
		_chromeShown = true,
		_pageToken = 0,
		_stageDirty = false,
		_stageListeners = {},
		_skinDiscs = skinDiscs,
		_veilTween = nil,
		_narrationTween = nil,
	}
	local view = setmetatable(data, AvatarCreatorView)

	-- Survol des cartes de magie (souris et manette).
	for index, card in magicCards do
		local function setHovered(isHovered: boolean)
			card.isHovered = isHovered
			refreshCard(card, index == view._selectedMagic)
		end
		card.button.MouseEnter:Connect(function()
			setHovered(true)
		end)
		card.button.MouseLeave:Connect(function()
			setHovered(false)
		end)
		card.button.SelectionGained:Connect(function()
			setHovered(true)
		end)
		card.button.SelectionLost:Connect(function()
			setHovered(false)
		end)
	end

	-- La zone libre est remesurée dès que le rail, le panneau ou l'écran bougent.
	local function markStageDirty()
		view:_scheduleStageRefresh()
	end
	for _, slot in { railSlot, panelSlot } do
		slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(markStageDirty)
		slot:GetPropertyChangedSignal("AbsolutePosition"):Connect(markStageDirty)
	end
	Theme.onLayoutChanged(screen, function(layout: Layout)
		view:applyLayout(layout)
	end)

	view:applyLayout(Theme.getLayout(screen))
	view:setChromeShown(false, 0)
	return view
end

--------------------------------------------------------------------------------
-- Mise en page
--------------------------------------------------------------------------------

-- Position d'un élément du décor (rail ou panneau) caché hors de l'écran, selon la disposition.
local function getHiddenOffset(mode: Mode, isRail: boolean): UDim2
	if mode == "wide" then
		return if isRail then UDim2.fromScale(-1.3, 0) else UDim2.fromScale(1.3, 0)
	end
	return if isRail then UDim2.fromScale(0, -2) else UDim2.fromScale(0, 1.3)
end

-- Écran large : rail à gauche, panneau à droite. Écran haut : rail en haut, feuille en bas.
function AvatarCreatorView.applyLayout(self: View, layout: Layout)
	local mode: Mode = if layout.isPortrait then "tall" else "wide"
	self.mode = mode
	local isCompact = layout.isCompact

	if mode == "wide" then
		self.railSlot.AnchorPoint = Vector2.new(0, 0.5)
		self.railSlot.Position = UDim2.new(0, EDGE_MARGIN, 0.5, 0)
		self.railSlot.Size = UDim2.fromScale(0.17, 0.86)
		self.railConstraint.MinSize = Vector2.new(150, 220)
		self.railConstraint.MaxSize = Vector2.new(230, 640)

		self.panelSlot.AnchorPoint = Vector2.new(1, 0.5)
		self.panelSlot.Position = UDim2.new(1, -EDGE_MARGIN, 0.5, 0)
		self.panelSlot.Size = UDim2.fromScale(0.34, 0.94)
		self.panelConstraint.MinSize = Vector2.new(320, 300)
		self.panelConstraint.MaxSize = Vector2.new(500, 900)

		local showRailHeader = layout.height >= 560
		self.railHeader.Visible = showRailHeader
		self.tabs:setOrientation("vertical")
		local tabsTop = if showRailHeader then RAIL_HEADER_HEIGHT + 6 else 0
		self.tabs.instance.Position = UDim2.fromOffset(0, tabsTop)
		self.tabs.instance.Size = UDim2.new(1, 0, 1, -tabsTop)
		self.railPadding.PaddingTop = UDim.new(0, 10)
		self.railPadding.PaddingBottom = UDim.new(0, 10)
		self._columns = 3
	else
		self.railSlot.AnchorPoint = Vector2.new(0.5, 0)
		self.railSlot.Position = UDim2.fromOffset(0, 8) + UDim2.fromScale(0.5, 0)
		self.railSlot.Size = UDim2.new(1, -2 * EDGE_MARGIN, 0, RAIL_TALL_HEIGHT)
		self.railConstraint.MinSize = Vector2.zero
		self.railConstraint.MaxSize = Vector2.new(math.huge, math.huge)

		self.panelSlot.AnchorPoint = Vector2.new(0.5, 1)
		self.panelSlot.Position = UDim2.fromScale(0.5, 1)
		self.panelSlot.Size = UDim2.fromScale(1, 0.46)
		self.panelConstraint.MinSize = Vector2.new(0, 320)
		self.panelConstraint.MaxSize = Vector2.new(900, 640)

		self.railHeader.Visible = false
		self.tabs:setOrientation("horizontal")
		self.tabs.instance.Position = UDim2.new()
		self.tabs.instance.Size = UDim2.fromScale(1, 1)
		self.railPadding.PaddingTop = UDim.new(0, 4)
		self.railPadding.PaddingBottom = UDim.new(0, 4)
		self._columns = math.clamp(math.floor(layout.width / 130), 4, 6)
	end

	-- En-tête plus court sur téléphone.
	local headerHeight = if isCompact then HEADER_HEIGHT_COMPACT else HEADER_HEIGHT
	local panelPadding = if isCompact then 12 else 18
	self.header.Size = UDim2.new(1, 0, 0, headerHeight)
	self.titleLabel.Position = UDim2.fromOffset(0, if isCompact then 14 else 18)
	self.titleLabel.Size = UDim2.new(1, 0, 0, if isCompact then 28 else 36)
	self.subtitleLabel.Position = UDim2.fromOffset(0, if isCompact then 42 else 56)
	self.subtitleLabel.Size = UDim2.new(1, 0, 0, if isCompact then 16 else 20)
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(self.panelPadding :: any)[side] = UDim.new(0, panelPadding)
	end
	local pagesTop = headerHeight + 10
	self.pagesGroup.Position = UDim2.fromOffset(0, pagesTop)
	self.pagesGroup.Size = UDim2.new(1, 0, 1, -(pagesTop + FOOTER_HEIGHT + 10))

	-- Vignettes : colonnes selon la largeur disponible.
	for _, grid in self.grids do
		grid.layout.CellSize = UDim2.new(1 / self._columns, -TILE_GAP, 0, 100)
		self:relinkGrid(grid)
	end

	-- Un décor caché reste caché hors de l'écran dans la nouvelle disposition.
	if not self._chromeShown then
		self.rail.Position = getHiddenOffset(mode, true)
		self.panel.Position = getHiddenOffset(mode, false)
	end
	self:_scheduleStageRefresh()
end

-- Voisins manette des vignettes d'une grille (colonnes de la disposition courante).
function AvatarCreatorView.relinkGrid(self: View, grid: OptionGrid)
	local objects: { GuiObject } = {}
	for index, tile in grid.tiles do
		objects[index] = tile.instance
	end
	Theme.linkSelection(objects, "grid", self._columns)
end

-- Mesure la zone libre (entre le rail et le panneau), y place la scène et retourne la fenêtre
-- de cadrage de la caméra (zone libre moins la bande des boutons de rotation).
function AvatarCreatorView.measureStage(self: View): Window
	local screenSize = self.gui.AbsoluteSize
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		return DEFAULT_WINDOW
	end
	local scale = self.screen.scale.Scale
	local railPosition, railSize = self.railSlot.AbsolutePosition, self.railSlot.AbsoluteSize
	local panelPosition = self.panelSlot.AbsolutePosition
	local topInset = GuiService:GetGuiInset().Y

	local left, top, right, bottom
	if self.mode == "wide" then
		left = railPosition.X + railSize.X
		right = panelPosition.X
		top = topInset
		bottom = screenSize.Y
	else
		left = 0
		right = screenSize.X
		top = railPosition.Y + railSize.Y
		bottom = panelPosition.Y
	end
	local width = math.max(right - left, 1)
	local height = math.max(bottom - top, 1)

	self.stage.Position = UDim2.fromOffset(left / scale, top / scale)
	self.stage.Size = UDim2.fromOffset(width / scale, height / scale)

	local band = math.min(CONTROLS_BAND * scale, height * 0.3)
	return {
		x = left / screenSize.X,
		y = top / screenSize.Y,
		width = width / screenSize.X,
		height = math.max(height - band, 1) / screenSize.Y,
	}
end

-- Regroupe les remesures d'une même image (plusieurs propriétés changent ensemble).
function AvatarCreatorView._scheduleStageRefresh(self: View)
	if self._stageDirty then
		return
	end
	self._stageDirty = true
	task.defer(function()
		self._stageDirty = false
		local window = self:measureStage()
		for _, listener in table.clone(self._stageListeners) do
			task.spawn(listener, window)
		end
	end)
end

-- `callback(window)` chaque fois que la zone libre change (pour la caméra).
function AvatarCreatorView.onStageChanged(self: View, callback: (window: Window) -> ())
	table.insert(self._stageListeners, callback)
end

-- Redemande une mesure de la zone libre à l'image suivante (après avoir activé l'écran, par exemple :
-- les positions absolues ne sont à jour qu'une fois l'interface affichée).
function AvatarCreatorView.requestStageRefresh(self: View)
	self:_scheduleStageRefresh()
end

--------------------------------------------------------------------------------
-- Apparitions et transitions
--------------------------------------------------------------------------------

-- Fait entrer (ou sortir) le rail, le panneau et les commandes de la scène. Durée 0 = immédiat.
function AvatarCreatorView.setChromeShown(self: View, shown: boolean, duration: number?)
	self._chromeShown = shown
	local railTarget = if shown then UDim2.new() else getHiddenOffset(self.mode, true)
	local panelTarget = if shown then UDim2.new() else getHiddenOffset(self.mode, false)
	local length = duration or (if shown then CHROME_SHOW_DURATION else CHROME_HIDE_DURATION)

	if shown then
		self.rail.Visible = true
		self.panel.Visible = true
	end
	if length <= 0 then
		self.rail.Position = railTarget
		self.panel.Position = panelTarget
		self.rail.Visible = shown
		self.panel.Visible = shown
		self.stageControls.GroupTransparency = if shown then 0 else 1
		self.stageControls.Visible = shown
		return
	end

	local direction = if shown then Enum.EasingDirection.Out else Enum.EasingDirection.In
	Theme.tween(self.rail, { Position = railTarget }, length, Enum.EasingStyle.Quart, direction)
	local panelTween = Theme.tween(self.panel, { Position = panelTarget }, length, Enum.EasingStyle.Quart, direction)
	if not shown then
		panelTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and not self._chromeShown then
				self.rail.Visible = false
				self.panel.Visible = false
			end
		end)
	end
	Theme.fade(self.stageControls, shown, length)
end

function AvatarCreatorView.isChromeShown(self: View): boolean
	return self._chromeShown
end

-- Voile noir du créateur (intro, validation). Le voile visible absorbe les clics ; une fois levé, il
-- est masqué pour ne plus rien bloquer. Un fondu en cours est remplacé. Durée 0 ou absente = immédiat.
function AvatarCreatorView.setVeil(self: View, shown: boolean, duration: number?): Tween?
	local previous = self._veilTween
	if previous then
		previous:Cancel()
	end
	self._veilTween = nil

	local veil = self.veil
	local target = if shown then 0 else 1
	if duration == nil or duration <= 0 then
		veil.BackgroundTransparency = target
		veil.Visible = shown
		return nil
	end

	veil.Visible = true
	local veilTween = Theme.tween(veil, { BackgroundTransparency = target }, duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	self._veilTween = veilTween
	if not shown then
		veilTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and self._veilTween == veilTween then
				veil.Visible = false
			end
		end)
	end
	return veilTween
end

-- Texte de narration posé sur le voile. `text` nil = le texte s'efface (et garde son contenu
-- pendant le fondu). Durée 0 ou absente = immédiat. Retourne le fondu lancé.
function AvatarCreatorView.setNarration(self: View, text: string?, duration: number?): Tween?
	local previous = self._narrationTween
	if previous then
		previous:Cancel()
	end
	self._narrationTween = nil

	local label = self.introLabel
	if text then
		label.Text = text
	end
	local target = if text then 0 else 1
	if duration == nil or duration <= 0 then
		label.TextTransparency = target
		return nil
	end
	local narrationTween =
		Theme.tween(label, { TextTransparency = target }, duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	self._narrationTween = narrationTween
	return narrationTween
end

-- Fondu court des pages : `apply` est appelé au creux du fondu (il dessine le nouvel état).
-- Deux transitions rapprochées : seule la dernière est appliquée.
function AvatarCreatorView.transitionPages(self: View, apply: () -> ())
	self._pageToken += 1
	local token = self._pageToken
	Theme.tween(self.pagesGroup, { GroupTransparency = 1 }, PAGE_FADE_OUT).Completed:Once(function()
		if token ~= self._pageToken then
			return
		end
		apply()
		Theme.tween(self.pagesGroup, { GroupTransparency = 0 }, PAGE_FADE_IN)
	end)
end

--------------------------------------------------------------------------------
-- Contenu
--------------------------------------------------------------------------------

function AvatarCreatorView.setHeader(self: View, caption: string, title: string, subtitle: string)
	self.stepCaption.Text = caption
	self.titleLabel.Text = title
	self.subtitleLabel.Text = subtitle
end

-- Affiche la page de l'étape `stepIndex` (et seulement elle).
function AvatarCreatorView.showPage(self: View, step: Step, stepIndex: number)
	self.optionsPage.Visible = step.kind == "list"
	for index, grid in self.grids do
		grid.scroller.Visible = index == stepIndex
	end
	self.proportionsPage.Visible = step.kind == "proportions"
	self.destinyPage.Visible = step.kind == "destiny"
	self.summaryPage.Visible = step.kind == "summary"
end

-- Option courante d'une étape "liste" : nom, compteur "3 / 22", vignette mise en avant.
function AvatarCreatorView.setOption(self: View, stepIndex: number, optionIndex: number, name: string, count: number, description: string?)
	self.optionName.Text = name
	self.optionCounter.Text = `{optionIndex} / {count}`
	self.optionDescriptionScroller.Visible = description ~= nil
	self.optionDescription.Text = description or ""
	self.optionDescriptionScroller.CanvasPosition = Vector2.zero
	local grid = self.grids[stepIndex]
	if grid then
		for index, tile in grid.tiles do
			tile:setSelected(index == optionIndex)
		end
		-- La vignette choisie reste visible (positions à jour à l'image suivante, après un changement de page).
		local selectedTile = grid.tiles[optionIndex]
		if selectedTile then
			task.defer(function()
				if grid.scroller.Visible then
					Theme.scrollIntoView(grid.scroller, selectedTile.instance)
				end
			end)
		end
	end
end

function AvatarCreatorView.setMagic(self: View, magicIndex: number)
	self._selectedMagic = magicIndex
	for index, card in self.magicCards do
		refreshCard(card, index == magicIndex)
	end
end

-- Roulette du Destin. `sealedIndex` : magie scellée (état "sealed") ; les autres cartes s'éteignent.
function AvatarCreatorView.setDestinyState(self: View, state: DestinyState, sealedIndex: number?, message: string?)
	self.spinButton.instance.Visible = state == "idle" or state == "error"
	self.spinButton:setEnabled(state == "idle" or state == "error")
	self.spinConfirmRow.Visible = state == "confirm"
	local sealedMagic = if sealedIndex then self.magicCards[sealedIndex] else nil
	if state == "idle" then
		self.spinStatus.Text = "Ou choisissez vous-même une magie ci-dessous."
	elseif state == "confirm" then
		self.spinStatus.Text = "Tourner la roue ? Son verdict sera <b>définitif</b> pour ce personnage, et remplacera votre choix."
	elseif state == "spinning" then
		self.spinStatus.Text = "La roue tourne…"
	elseif state == "sealed" and sealedMagic then
		self.spinStatus.Text = `Le destin a parlé : <b>{sealedMagic.magic.name}</b>. Ce pouvoir est le vôtre.`
	elseif state == "error" then
		self.spinStatus.Text = message or "La roue reste muette. Réessayez dans un instant."
	end
	for index, card in self.magicCards do
		card.isLocked = state == "sealed" and index ~= sealedIndex
		card.button.Selectable = not card.isLocked
		refreshCard(card, index == self._selectedMagic)
	end
end

-- Remplit le récapitulatif. `values[stepIndex]` = texte de l'étape.
function AvatarCreatorView.setSummary(self: View, values: { [number]: string }, magic: Magic)
	for _, row in self.summaryRows do
		row.valueLabel.Text = values[row.stepIndex] or ""
	end
	self.powerName.Text = magic.name
	self.powerName.TextColor3 = magic.palette.glow
	self.powerUltimate.Text = `Ultime · {magic.ultimateName}`
	self.powerUltimate.TextColor3 = magic.palette.main
	self.powerBand.Color = Theme.magicGradient(magic.palette)
end

function AvatarCreatorView.setConfirming(self: View, confirming: boolean)
	self.confirmBox.Visible = confirming
end

function AvatarCreatorView.setError(self: View, text: string?)
	self.errorLabel.Text = text or ""
	self.errorLabel.Visible = text ~= nil
end

-- Boutons du pied : `backText` nil masque le bouton de gauche. `isFinal` : le bouton de droite devient
-- celui de la validation irréversible (rouge).
function AvatarCreatorView.setFooter(self: View, backText: string?, nextText: string, isFinal: boolean?)
	self.backButton.instance.Visible = backText ~= nil
	self.backButton:setText(backText or "")
	self.nextButton:setText(nextText)
	self.nextButton:setVariant(if isFinal then "danger" else "primary")
end

function AvatarCreatorView.setHint(self: View, text: string)
	self.hintLabel.Text = text
end

-- Couleur de peau du personnage, reprise sous les vignettes de visages et de marques.
function AvatarCreatorView.setSkinColor(self: View, color: Color3)
	for _, disc in self._skinDiscs do
		disc.BackgroundColor3 = color
	end
end

-- Élément à sélectionner à la manette en arrivant sur une étape.
function AvatarCreatorView.getDefaultSelectable(self: View, step: Step, stepIndex: number, optionIndex: number): GuiObject?
	if step.kind == "list" then
		local grid = self.grids[stepIndex]
		local tile = grid and grid.tiles[optionIndex]
		return if tile then tile.instance else nil
	elseif step.kind == "proportions" then
		return self.heightSlider.track
	elseif step.kind == "destiny" then
		local card = self.magicCards[self._selectedMagic]
		return if card then card.button else nil
	elseif self.confirmBox.Visible then
		return self.nextButton.instance
	end
	return self.nextButton.instance
end

return AvatarCreatorView
