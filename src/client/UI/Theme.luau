--!strict
--[[
	Theme
	Charte graphique commune à TOUTES les interfaces du jeu (créateur de personnage, cinématiques,
	grimoire, guilde, missions, HUD...). Palette dark fantasy, polices, tailles, et des fabriques qui
	construisent des éléments déjà stylés, adaptatifs (souris, tactile, manette) et cohérents.

	================================================================================================
	MODE D'EMPLOI (de quoi s'en servir sans lire la suite)
	================================================================================================
	local Theme = require(<Client>:WaitForChild("UI"):WaitForChild("Theme"))

	ÉCRAN ------------------------------------------------------------------------------------------
	local screen = Theme.screenGui("GrimoireGui", Theme.displayOrder.menu)        --> Screen
		screen.gui    ScreenGui (IgnoreGuiInset = true, ResetOnSpawn = false), déjà parenté au PlayerGui
		screen.root   toile plein écran en PIXELS VIRTUELS : environ 1280 x 720 en paysage, 720 x 1280 en
		              portrait. Un UIScale l'agrandit ou la rétrécit pour remplir l'écran réel : on dessine
		              en Scale + pixels virtuels (TextSize, marges, UISizeConstraint), et tout reste
		              proportionné du téléphone à l'écran 4K. Pour les fonds plein écran.
		screen.safe   même toile, privée de la barre Roblox du haut (et des encoches en paysage tactile) :
		              c'est ICI qu'on pose panneaux et boutons.
		screen.scale  l'UIScale (géré par Theme, ne pas le modifier)
	Theme.getLayout(screen) -> Layout
		{ width, height (px virtuels), screenWidth, screenHeight (px réels), isPortrait, isCompact
		  (téléphone ou petite fenêtre), isTouch, scale }
	Theme.onLayoutChanged(screen, function(layout) ... end) -> Connection   (rotation, redimensionnement)
	Theme.setUserScale(multiplicateur)   réglage "taille de l'interface" du joueur (0.8 à 1.3)
	Theme.getInputMode() -> "mouse" | "touch" | "gamepad"   (dernier périphérique utilisé)

	FABRIQUES --------------------------------------------------------------------------------------
	Chaque fabrique prend UNE table `props` (obligatoire, `{}` accepté). Champs communs, tous facultatifs :
		name, parent, size: UDim2, position: UDim2, anchor: Vector2, layoutOrder, zIndex, visible,
		minSize / maxSize: Vector2 (UISizeConstraint), aspectRatio: number (UIAspectRatioConstraint)

	Theme.panel(props) -> Frame             fond charbon translucide, liseré or terni, coins arrondis
		+ style "panel" | "raised" | "sunken" | "glass" | "none", border, borderColor, corner, padding, active
	Theme.group(props) -> (CanvasGroup, Frame)
		comme panel, mais tout le contenu se fond d'un bloc (Theme.fade). Poser les enfants (et les
		UIListLayout) dans le Frame retourné en second ("Content"), pas dans le CanvasGroup.
	Theme.title(props) -> TextLabel         titre (Garamond, ivoire)
	Theme.label(props) -> TextLabel         texte courant
	Theme.caption(props) -> TextLabel       petite légende en capitales (Gotham, gris)
		+ text, font, textSize, color, transparency, alignX, alignY, wrap, rich,
		  scaled (TextScaled borné par minTextSize / maxTextSize), autoSize "X" | "Y" | "XY", stroke
	Theme.button(props) -> Button           bouton à états : survol, pressé, désactivé, sélectionné
		+ text, glyph (symbole à gauche du texte), variant "primary" | "secondary" | "ghost" | "danger" | "tab",
		  font, textSize, alignX, accent (Color3 qui remplace l'or), enabled, selected, round, onActivated
		button.instance (TextButton : Selectable, cadre de sélection manette doré), button.label
		button:onActivated(fn) -> Connection    (n'est PAS appelé quand le bouton est désactivé)
		button:setEnabled(bool)  :isEnabled()  :setSelected(bool)  :isSelected()
		button:setText(string)   :setGlyph(string)  :setAccent(Color3?)  :setVariant(variant)  :destroy()
	Theme.iconButton(props) -> Button       bouton carré (rond si round = true) à symbole : props.glyph
	Theme.tabs(props) -> Tabs               rail d'onglets défilant, vertical ou horizontal
		+ items = { { id, label, glyph?, separatorBefore? } }, orientation, selected, thickness, length,
		  autoSelect (défaut true ; false = le clic prévient seulement, le propriétaire appelle select)
		tabs:select(index, silent?)  :getSelected()  :onChanged(fn(index, id)) -> Connection
		tabs:setOrientation("vertical" | "horizontal")  :setEnabled(index, bool)  :destroy()
		tabs.instance (ScrollingFrame), tabs.buttons ({ Button })
	Theme.slider(props) -> Slider           curseur à crans : min, max, step, value, label, format(value)
		slider:setValue(v, silent?)  :getValue()  :nudge(±1)  :setFocused(bool)
		slider:onChanged(fn(value)) -> Connection  :destroy()
		slider.instance, slider.track (sélectionnable), slider.minusButton, slider.plusButton
	Theme.scroller(props) -> ScrollingFrame  zone défilante transparente, barre dorée fine
		+ direction "vertical" | "horizontal" (AutomaticCanvasSize réglé en conséquence)
	Theme.divider(props) -> Frame           filet doré qui s'estompe aux deux bouts
		+ vertical, color, thickness, transparency

	ANIMATION --------------------------------------------------------------------------------------
	Theme.tween(instance, goal, duration?, style?, direction?) -> Tween   (déjà lancé ; Quad Out)
	Theme.fade(object, shown, duration?) -> Tween?
		apparition / disparition douce (CanvasGroup : tout le groupe ; texte, image ou cadre seul sinon).
		Visible passe à false à la fin d'une disparition, et à true au début d'une apparition.
	Theme.screenFade(opacity, duration?) -> Tween?
		voile noir PARTAGÉ par tout le jeu, au-dessus de tout (0 = ouvert, 1 = noir ; durée 0 = immédiat).
		Il bloque les clics tant qu'il est opaque. Theme.getScreenOpacity() -> number (valeur actuelle)

	DIVERS -----------------------------------------------------------------------------------------
	Theme.colors, Theme.fonts, Theme.textSize, Theme.spacing, Theme.durations, Theme.alpha,
	Theme.displayOrder (tables gelées ; ordre d'affichage de chaque famille d'écrans)
	Theme.linkSelection(objects, "horizontal" | "vertical" | "grid", columns?)  voisins à la manette
	Theme.scrollIntoView(scroller, target)   fait défiler une liste jusqu'à l'un de ses éléments
	Theme.makeSelectable(object)   élément sur mesure sélectionnable à la manette (cadre doré commun)
	Theme.magicGradient(palette) -> ColorSequence   dégradé d'une Magie Innée (void -> main -> glow)
	Theme.playSound(name)   sons d'interface (aucun pour l'instant : voir SOUNDS)

	Règles : aucune image n'est utilisée (pas d'ID d'asset inventé) ; tout est dessiné avec des
	cadres, des liserés et des dégradés.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--------------------------------------------------------------------------------
-- Palette, polices, mesures
--------------------------------------------------------------------------------

local COLORS = table.freeze({
	-- Fonds (charbon)
	ink = Color3.fromRGB(6, 6, 9), -- noir d'encre : voiles, ombres (fond historique du projet)
	background = Color3.fromRGB(22, 20, 25), -- fond des panneaux (assez clair pour détacher le texte)
	surface = Color3.fromRGB(38, 34, 40), -- éléments en relief : boutons, cartes, vignettes
	surfaceHover = Color3.fromRGB(56, 49, 54),
	sunken = Color3.fromRGB(12, 11, 15), -- creux : pistes de curseur, champs
	-- Or et accents
	gold = Color3.fromRGB(176, 146, 96), -- or terni : liserés (couleur historique du projet)
	goldBright = Color3.fromRGB(226, 194, 132), -- or vif : survol, titres mis en avant
	goldDim = Color3.fromRGB(104, 86, 58), -- or éteint : éléments inactifs
	amber = Color3.fromRGB(230, 152, 52), -- accent chaud : sélection, action principale
	cyan = Color3.fromRGB(92, 214, 232), -- accent froid : tout ce qui touche au TEMPS
	danger = Color3.fromRGB(222, 88, 76), -- rouge : danger, erreur, action irréversible (lisible en texte)
	success = Color3.fromRGB(146, 206, 120), -- vert : réussite, objectif accompli
	-- Textes
	text = Color3.fromRGB(238, 232, 220), -- ivoire
	textMuted = Color3.fromRGB(176, 168, 156), -- gris chaud (descriptions, légendes : contraste ≥ 7:1 sur les panneaux)
	textDim = Color3.fromRGB(118, 112, 106), -- texte désactivé (encore lisible)
	textOnAccent = Color3.fromRGB(18, 13, 8), -- texte posé sur un fond doré
})

-- Polices déjà utilisées dans le projet (Hub, dialogues, carte du monde, glitch).
local FONTS = table.freeze({
	display = Enum.Font.GrenzeGotisch, -- très grands titres (régions, chapitres) : gothique de la carte
	title = Enum.Font.Garamond, -- titres de panneaux, boutons : celle du Hub et des dialogues
	body = Enum.Font.Garamond, -- texte courant
	caption = Enum.Font.GothamMedium, -- légendes en capitales, rappels de touches, compteurs
	hand = Enum.Font.Fondamento, -- manuscrit : parchemins, journal, lettres
	mono = Enum.Font.Code, -- chiffres techniques (glitch, débogage)
})

-- Tailles de texte en pixels VIRTUELS (l'UIScale de l'écran les adapte).
local TEXT_SIZE = table.freeze({
	display = 64,
	title = 34,
	heading = 24,
	button = 20,
	body = 18,
	label = 16,
	caption = 13,
	small = 11,
})

local SPACING = table.freeze({ xs = 4, sm = 8, md = 12, lg = 18, xl = 28 })
local DURATIONS = table.freeze({ fast = 0.12, normal = 0.25, slow = 0.6 })

-- Transparences de référence.
local ALPHA = table.freeze({
	panel = 0.04, -- fond d'un panneau : quasi opaque, le texte ne se lit plus « sur la scène »
	glass = 0.22, -- panneau léger qui laisse deviner la scène
	raised = 0.02, -- élément en relief (cartes, boutons)
	border = 0.25, -- liseré au repos
	borderFaint = 0.7, -- liseré discret
})

-- Ordre d'affichage des familles d'écrans (les valeurs historiques sont reprises).
local DISPLAY_ORDER = table.freeze({
	hud = 10, -- jauge de Tension, suivi de quête
	world = 30, -- présages, textes du monde
	map = 40, -- carte du monde
	creator = 50, -- créateur de personnage
	dialogue = 60,
	menu = 70, -- grimoire, guilde, missions
	glitch = 100, -- anomalie temporelle
	veil = 950, -- voile noir partagé (Theme.screenFade)
	cinematic = 960, -- titres de cinématique (au-dessus du voile)
})

local CORNER_RADIUS = 6
local BUTTON_HEIGHT = 44 -- hauteur par défaut d'un bouton (px virtuels) : cible tactile confortable

-- Toile virtuelle
local REFERENCE_LONG_SIDE = 1280
local REFERENCE_SHORT_SIDE = 720
local MIN_SCALE = 0.5
local MIN_SCALE_TOUCH = 0.68 -- sur téléphone, on garde des cibles assez grandes pour le doigt
local MAX_SCALE = 3
local COMPACT_SHORT_SIDE = 600 -- px réels : en dessous, mise en page "téléphone"
local USER_SCALE_MIN = 0.8
local USER_SCALE_MAX = 1.3
local NOTCH_MARGIN = 44 -- px réels de marge latérale en paysage tactile (encoches)
local HOME_INDICATOR_MARGIN = 14 -- px réels en bas sur tactile (barre d'accueil)

-- Sons d'interface.
-- >>> SON : aucun son d'interface n'est encore choisi. Y mettre "rbxassetid://..." d'un son DÉJÀ
-- présent dans le projet (règle : aucun ID inventé). "" = silence.
local SOUNDS: { [string]: string } = {
	hover = "",
	click = "",
	confirm = "",
	back = "",
}

--------------------------------------------------------------------------------
-- Types publics
--------------------------------------------------------------------------------

export type Screen = {
	gui: ScreenGui,
	root: Frame,
	safe: Frame,
	scale: UIScale,
}

export type Layout = {
	width: number,
	height: number,
	screenWidth: number,
	screenHeight: number,
	isPortrait: boolean,
	isCompact: boolean,
	isTouch: boolean,
	scale: number,
}

export type InputMode = "mouse" | "touch" | "gamepad"

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type PanelStyle = "panel" | "raised" | "sunken" | "glass" | "none"

export type PanelProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	style: PanelStyle?,
	border: boolean?,
	borderColor: Color3?,
	corner: number?,
	padding: number?,
	active: boolean?, -- true : le panneau absorbe les clics (rien ne passe au monde derrière)
}

export type LabelProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	text: string?,
	font: Enum.Font?,
	textSize: number?,
	color: Color3?,
	transparency: number?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	wrap: boolean?,
	rich: boolean?,
	scaled: boolean?,
	minTextSize: number?,
	maxTextSize: number?,
	autoSize: ("X" | "Y" | "XY")?,
	stroke: boolean?, -- contour sombre (lisibilité sur la scène 3D)
}

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "tab"

export type ButtonProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	text: string?,
	glyph: string?,
	variant: ButtonVariant?,
	font: Enum.Font?,
	textSize: number?,
	alignX: Enum.TextXAlignment?,
	accent: Color3?,
	enabled: boolean?,
	selected: boolean?,
	round: boolean?,
	onActivated: (() -> ())?,
}

export type TabItem = {
	id: string,
	label: string,
	glyph: string?,
	separatorBefore: boolean?,
}

export type TabOrientation = "vertical" | "horizontal"

export type TabsProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	items: { TabItem },
	orientation: TabOrientation?,
	selected: number?,
	thickness: number?, -- hauteur d'un onglet en vertical (px virtuels)
	length: number?, -- largeur d'un onglet en horizontal (px virtuels)
	textSize: number?,
	autoSelect: boolean?,
}

export type SliderProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	label: string?,
	min: number,
	max: number,
	step: number,
	value: number?,
	format: ((value: number) -> string)?,
}

export type ScrollerProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	minSize: Vector2?,
	maxSize: Vector2?,
	aspectRatio: number?,
	direction: ("vertical" | "horizontal")?,
}

export type DividerProps = {
	name: string?,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	vertical: boolean?,
	color: Color3?,
	thickness: number?,
	transparency: number?,
}

-- Palette d'une Magie Innée (même forme que MagicConfig.Palette).
export type MagicPalette = {
	void: Color3,
	main: Color3,
	glow: Color3,
}

local Theme = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getPlayerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Ajoute `callback` à `listeners` ; la connexion retournée l'en retire.
local function connectListener<T>(listeners: { T }, callback: T): Connection
	table.insert(listeners, callback)
	local connection: Connection
	connection = {
		Connected = true,
		Disconnect = function(self: Connection)
			if not self.Connected then
				return
			end
			self.Connected = false
			local index = table.find(listeners, callback)
			if index then
				table.remove(listeners, index)
			end
		end,
	}
	return connection
end

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Champs communs des props (voir l'en-tête). Le parent est posé par chaque fabrique, en dernier.
local function applyCommon(object: GuiObject, props: any)
	if props.name then
		object.Name = props.name
	end
	if props.size then
		object.Size = props.size
	end
	if props.position then
		object.Position = props.position
	end
	if props.anchor then
		object.AnchorPoint = props.anchor
	end
	if props.layoutOrder then
		object.LayoutOrder = props.layoutOrder
	end
	if props.zIndex then
		object.ZIndex = props.zIndex
	end
	if props.visible ~= nil then
		object.Visible = props.visible
	end
	if props.minSize or props.maxSize then
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = props.minSize or Vector2.zero
		constraint.MaxSize = props.maxSize or Vector2.new(math.huge, math.huge)
		constraint.Parent = object
	end
	if props.aspectRatio then
		local constraint = Instance.new("UIAspectRatioConstraint")
		constraint.AspectRatio = props.aspectRatio
		constraint.Parent = object
	end
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

local function addPadding(object: GuiObject, padding: number)
	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingTop = UDim.new(0, padding)
	uiPadding.PaddingBottom = UDim.new(0, padding)
	uiPadding.PaddingLeft = UDim.new(0, padding)
	uiPadding.PaddingRight = UDim.new(0, padding)
	uiPadding.Parent = object
end

-- Produit des UIScale de `object` et de ses ancêtres : convertit des px réels en px locaux.
local function getAccumulatedScale(object: Instance): number
	local scale = 1
	local current: Instance? = object
	while current do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
		current = current.Parent
	end
	return if scale > 0 then scale else 1
end

--------------------------------------------------------------------------------
-- Écrans et toile virtuelle
--------------------------------------------------------------------------------

type ScreenRecord = {
	screen: Screen,
	padding: UIPadding,
	listeners: { (layout: Layout) -> () },
}

local screenRecords: { [ScreenGui]: ScreenRecord } = {}
local userScale = 1

-- Facteur d'échelle de la toile pour un écran de `size` pixels.
local function computeScale(size: Vector2): number
	if size.X <= 0 or size.Y <= 0 then
		return 1
	end
	local isPortrait = size.Y > size.X
	local referenceWidth = if isPortrait then REFERENCE_SHORT_SIDE else REFERENCE_LONG_SIDE
	local referenceHeight = if isPortrait then REFERENCE_LONG_SIDE else REFERENCE_SHORT_SIDE
	local fit = math.min(size.X / referenceWidth, size.Y / referenceHeight)
	local minimum = if isTouchDevice() then MIN_SCALE_TOUCH else MIN_SCALE
	return math.clamp(fit, minimum, MAX_SCALE) * userScale
end

local function buildLayout(screen: Screen): Layout
	local size = screen.gui.AbsoluteSize
	local scale = screen.scale.Scale
	return {
		width = size.X / scale,
		height = size.Y / scale,
		screenWidth = size.X,
		screenHeight = size.Y,
		isPortrait = size.Y > size.X,
		isCompact = math.min(size.X, size.Y) < COMPACT_SHORT_SIDE,
		isTouch = isTouchDevice(),
		scale = scale,
	}
end

-- Recalcule l'échelle, la taille de la toile et la zone sûre, puis prévient les abonnés.
local function refreshScreen(record: ScreenRecord)
	local screen = record.screen
	local size = screen.gui.AbsoluteSize
	local scale = computeScale(size)

	-- La toile mesure (écran / échelle) ; l'UIScale la ramène exactement à la taille de l'écran.
	screen.scale.Scale = scale
	screen.root.Size = UDim2.fromScale(1 / scale, 1 / scale)

	local topLeftInset = GuiService:GetGuiInset()
	local isTouch = isTouchDevice()
	local sideMargin = if isTouch and size.X > size.Y then NOTCH_MARGIN else 0
	local bottomMargin = if isTouch then HOME_INDICATOR_MARGIN else 0
	record.padding.PaddingTop = UDim.new(0, topLeftInset.Y / scale)
	record.padding.PaddingBottom = UDim.new(0, bottomMargin / scale)
	record.padding.PaddingLeft = UDim.new(0, sideMargin / scale)
	record.padding.PaddingRight = UDim.new(0, sideMargin / scale)

	local layout = buildLayout(screen)
	for _, listener in table.clone(record.listeners) do
		task.spawn(listener, layout)
	end
end

-- Crée un ScreenGui adaptatif (voir l'en-tête). `parent` : PlayerGui par défaut.
function Theme.screenGui(name: string, displayOrder: number, parent: Instance?): Screen
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.DisplayOrder = displayOrder
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Name = "ThemeScale"
	scale.Parent = root

	local safe = Instance.new("Frame")
	safe.Name = "Safe"
	safe.BackgroundTransparency = 1
	safe.Size = UDim2.fromScale(1, 1)
	safe.Parent = root

	local padding = Instance.new("UIPadding")
	padding.Parent = safe

	local screen: Screen = { gui = gui, root = root, safe = safe, scale = scale }
	local record: ScreenRecord = { screen = screen, padding = padding, listeners = {} }
	screenRecords[gui] = record

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refreshScreen(record)
	end)
	gui.Destroying:Connect(function()
		screenRecords[gui] = nil
		table.clear(record.listeners)
	end)

	gui.Parent = parent or getPlayerGui()
	refreshScreen(record)
	return screen
end

function Theme.getLayout(screen: Screen): Layout
	return buildLayout(screen)
end

-- `callback(layout)` à chaque changement de taille d'écran (et de réglage d'échelle).
function Theme.onLayoutChanged(screen: Screen, callback: (layout: Layout) -> ()): Connection
	local record = screenRecords[screen.gui]
	if record == nil then
		return connectListener({}, callback) -- écran détruit : connexion inerte
	end
	return connectListener(record.listeners, callback)
end

-- Réglage "taille de l'interface" du joueur, appliqué à toutes les toiles ouvertes.
function Theme.setUserScale(multiplier: number)
	userScale = math.clamp(multiplier, USER_SCALE_MIN, USER_SCALE_MAX)
	for _, record in screenRecords do
		refreshScreen(record)
	end
end

function Theme.getInputMode(): InputMode
	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Touch then
		return "touch"
	end
	if string.find(lastInput.Name, "Gamepad", 1, true) then
		return "gamepad"
	end
	return "mouse"
end

--------------------------------------------------------------------------------
-- Panneaux et textes
--------------------------------------------------------------------------------

local PANEL_LOOKS: { [PanelStyle]: { color: Color3, transparency: number } } = {
	panel = { color = COLORS.background, transparency = ALPHA.panel },
	raised = { color = COLORS.surface, transparency = ALPHA.raised },
	sunken = { color = COLORS.sunken, transparency = 0.25 },
	glass = { color = COLORS.background, transparency = ALPHA.glass },
	none = { color = COLORS.background, transparency = 1 },
}

-- Habille `object` en panneau. `withSheen` : léger reflet (haut plus clair), réservé aux Frames.
local function decoratePanel(object: GuiObject, props: PanelProps, withSheen: boolean)
	local style: PanelStyle = props.style or "panel"
	local look = PANEL_LOOKS[style]
	object.BackgroundColor3 = look.color
	object.BackgroundTransparency = look.transparency
	object.BorderSizePixel = 0
	object.Active = props.active == true

	local corner = props.corner or CORNER_RADIUS
	if corner > 0 then
		addCorner(object, UDim.new(0, corner))
	end
	if props.border ~= false and style ~= "none" then
		addStroke(object, props.borderColor or COLORS.gold, ALPHA.border, 1)
	end
	if withSheen and style ~= "none" and style ~= "sunken" then
		local sheen = Instance.new("UIGradient")
		sheen.Name = "Sheen"
		sheen.Rotation = 90
		sheen.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
		sheen.Parent = object
	end
end

function Theme.panel(props: PanelProps): Frame
	local p = props
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	decoratePanel(frame, p, true)
	if p.padding then
		addPadding(frame, p.padding)
	end
	applyCommon(frame, p)
	frame.Parent = p.parent
	return frame
end

-- Panneau dont tout le contenu se fond d'un bloc. Retourne (groupe, contenu) : poser les enfants
-- dans `contenu` (le liseré est un cadre intérieur, sinon le CanvasGroup le rognerait).
function Theme.group(props: PanelProps): (CanvasGroup, Frame)
	local p = props
	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Active = p.active == true

	local surface = Instance.new("Frame")
	surface.Name = "Surface"
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.new(1, -2, 1, -2) -- 1 px de marge : le liseré reste dans le groupe
	surface.ZIndex = 0
	decoratePanel(surface, p, true)
	surface.Active = false
	surface.Parent = group

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 1
	if p.padding then
		addPadding(content, p.padding)
	end
	content.Parent = group

	applyCommon(group, p)
	group.Parent = p.parent
	return group, content
end

type TextDefaults = { font: Enum.Font, textSize: number, color: Color3 }

local function newText(props: LabelProps, defaults: TextDefaults): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, (props.textSize or defaults.textSize) + 6)
	label.Font = props.font or defaults.font
	label.TextSize = props.textSize or defaults.textSize
	label.TextColor3 = props.color or defaults.color
	label.TextTransparency = props.transparency or 0
	label.Text = props.text or ""
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrap == true
	label.RichText = props.rich == true

	if props.scaled then
		label.TextScaled = true
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.maxTextSize or label.TextSize
		constraint.MinTextSize = props.minTextSize or 9
		constraint.Parent = label
	end
	if props.autoSize == "X" then
		label.AutomaticSize = Enum.AutomaticSize.X
	elseif props.autoSize == "Y" then
		label.AutomaticSize = Enum.AutomaticSize.Y
	elseif props.autoSize == "XY" then
		label.AutomaticSize = Enum.AutomaticSize.XY
	end
	if props.stroke then
		label.TextStrokeColor3 = COLORS.ink
		label.TextStrokeTransparency = 0.35
	end

	applyCommon(label, props)
	label.Parent = props.parent
	return label
end

function Theme.title(props: LabelProps): TextLabel
	return newText(props, { font = FONTS.title, textSize = TEXT_SIZE.title, color = COLORS.text })
end

function Theme.label(props: LabelProps): TextLabel
	return newText(props, { font = FONTS.body, textSize = TEXT_SIZE.body, color = COLORS.text })
end

function Theme.caption(props: LabelProps): TextLabel
	return newText(props, { font = FONTS.caption, textSize = TEXT_SIZE.caption, color = COLORS.textMuted })
end

function Theme.divider(props: DividerProps): Frame
	local p = props
	local thickness = p.thickness or 1
	local line = Instance.new("Frame")
	line.Name = "Divider"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = p.color or COLORS.gold
	line.BackgroundTransparency = p.transparency or 0.25
	line.Size = if p.vertical then UDim2.new(0, thickness, 1, 0) else UDim2.new(1, 0, 0, thickness)

	-- Les deux bouts s'estompent : filet d'enluminure plutôt que trait de tableur.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = if p.vertical then 90 else 0
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = line

	applyCommon(line, p)
	line.Parent = p.parent
	return line
end

function Theme.scroller(props: ScrollerProps): ScrollingFrame
	local p = props
	local isHorizontal = p.direction == "horizontal"
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = 3
	scroller.ScrollBarImageColor3 = COLORS.gold
	scroller.ScrollBarImageTransparency = 0.3
	scroller.ScrollingDirection = if isHorizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	scroller.AutomaticCanvasSize = if isHorizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroller.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroller.Selectable = false
	applyCommon(scroller, p)
	scroller.Parent = p.parent
	return scroller
end

--------------------------------------------------------------------------------
-- Fond cliquable d'une fenêtre modale
--------------------------------------------------------------------------------

-- Vrai si le point d'écran `point` tombe dans `object`. Les deux conventions de coordonnées
-- (avec ou sans la barre Roblox du haut) sont testées : dans le doute, le point est « dedans ».
function Theme.isPointInside(object: GuiObject, point: Vector2): boolean
	if not object.Visible then
		return false
	end
	local topLeft = object.AbsolutePosition
	local bottomRight = topLeft + object.AbsoluteSize
	local inset = GuiService:GetGuiInset()
	for _, candidate in { point, point + inset } do
		if candidate.X >= topLeft.X and candidate.X <= bottomRight.X and candidate.Y >= topLeft.Y and candidate.Y <= bottomRight.Y then
			return true
		end
	end
	return false
end

local POINTER_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

--[[
	Ferme une fenêtre quand on clique sur son FOND, jamais quand on clique dedans.
	`backdrop` : bouton plein écran derrière la fenêtre ; `inside` : les cadres de la fenêtre (livre,
	parchemin...). Le clic ne compte que s'il a COMMENCÉ et FINI hors de ces cadres, à la souris ou
	au doigt : un clic sur un texte, une marge, une barre de défilement ou un glisser depuis le livre
	ne ferme rien, même si le moteur transmet le clic au fond. La manette ferme avec sa touche
	Retour (B), gérée par la fenêtre ; le fond n'est donc pas sélectionnable.
]]
function Theme.bindBackdropDismiss(backdrop: GuiButton, inside: { GuiObject }, onDismiss: () -> ()): { RBXScriptConnection }
	backdrop.Selectable = false
	backdrop.ZIndex = 0
	local pressedOutside = false
	local function isInside(point: Vector2): boolean
		for _, object in inside do
			if Theme.isPointInside(object, point) then
				return true
			end
		end
		return false
	end
	local function pointOf(input: InputObject?): Vector2?
		if input == nil or not POINTER_INPUTS[input.UserInputType] then
			return nil
		end
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return {
		backdrop.InputBegan:Connect(function(input: InputObject)
			local point = pointOf(input)
			if point then
				pressedOutside = not isInside(point)
			end
		end),
		backdrop.Activated:Connect(function(input: InputObject?)
			local point = pointOf(input)
			local wasOutside = pressedOutside
			pressedOutside = false
			if point and wasOutside and not isInside(point) then
				onDismiss()
			end
		end),
	}
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

function Theme.tween(
	instance: Instance,
	goal: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tweenInfo = TweenInfo.new(
		duration or DURATIONS.normal,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local newTween = TweenService:Create(instance, tweenInfo, goal)
	newTween:Play()
	return newTween
end

-- Propriété de transparence que Theme.fade anime pour cette classe d'objet.
local function getFadeProperty(object: GuiObject): string
	if object:IsA("CanvasGroup") then
		return "GroupTransparency"
	elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		return "TextTransparency"
	elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
		return "ImageTransparency"
	end
	return "BackgroundTransparency"
end

function Theme.fade(object: GuiObject, shown: boolean, duration: number?): Tween?
	local property = getFadeProperty(object)
	-- La transparence "visible" d'origine est retenue au premier appel (un texte à 0.3 revient à 0.3).
	local baseAttribute = "ThemeFadeBase"
	local base = object:GetAttribute(baseAttribute)
	if type(base) ~= "number" then
		local current: number = (object :: any)[property]
		base = if property == "GroupTransparency" or current >= 1 then 0 else current
		object:SetAttribute(baseAttribute, base)
	end

	if shown then
		object.Visible = true
	end
	local fadeTween = Theme.tween(object, { [property] = if shown then base else 1 }, duration or DURATIONS.normal)
	if not shown then
		fadeTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				object.Visible = false
			end
		end)
	end
	return fadeTween
end

-- Voile noir partagé --------------------------------------------------------------

local veilFrame: Frame? = nil
local veilTween: Tween? = nil

local function getVeil(): Frame
	local existing = veilFrame
	if existing and existing.Parent then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ThemeScreenVeil"
	gui.DisplayOrder = DISPLAY_ORDER.veil
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Veil"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui

	gui.Parent = getPlayerGui()
	veilFrame = frame
	return frame
end

-- Voile noir plein écran partagé : 0 = ouvert, 1 = noir. Durée nulle ou absente = immédiat.
function Theme.screenFade(opacity: number, duration: number?): Tween?
	local frame = getVeil()
	local gui = frame.Parent :: ScreenGui
	local previous = veilTween
	if previous then
		previous:Cancel()
	end
	veilTween = nil

	local target = 1 - math.clamp(opacity, 0, 1)
	gui.Enabled = true
	frame.Active = target < 1 -- tant qu'il est visible, il absorbe les clics

	if duration == nil or duration <= 0 then
		frame.BackgroundTransparency = target
		gui.Enabled = target < 1
		return nil
	end

	local fadeTween = Theme.tween(frame, { BackgroundTransparency = target }, duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	veilTween = fadeTween
	fadeTween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and target >= 1 then
			gui.Enabled = false
		end
	end)
	return fadeTween
end

function Theme.getScreenOpacity(): number
	local frame = veilFrame
	if frame == nil or frame.Parent == nil then
		return 0
	end
	local gui = frame.Parent :: ScreenGui
	return if gui.Enabled then 1 - frame.BackgroundTransparency else 0
end

--------------------------------------------------------------------------------
-- Sons
--------------------------------------------------------------------------------

local soundCache: { [string]: Sound } = {}

-- Chargé à la demande : Theme reste utilisable sans le reste du client (aperçus, tests).
local function getAudioMixer(): any
	local audioFolder = ((script.Parent :: Instance).Parent :: Instance):WaitForChild("Audio")
	return require(audioFolder:WaitForChild("AudioMixer") :: ModuleScript)
end

function Theme.playSound(name: string)
	local soundId = SOUNDS[name]
	if soundId == nil or soundId == "" then
		return
	end
	local sound: Sound? = soundCache[name]
	if sound == nil then
		local newSound = Instance.new("Sound")
		newSound.Name = "ThemeSound_" .. name
		newSound.SoundId = soundId
		newSound.Volume = 0.5
		getAudioMixer().assign(newSound, "Sfx")
		newSound.Parent = SoundService
		soundCache[name] = newSound
		sound = newSound
	end
	SoundService:PlayLocalSound(sound)
end

--------------------------------------------------------------------------------
-- Sélection à la manette
--------------------------------------------------------------------------------

local selectionImage: Frame? = nil

-- Cadre doré dessiné autour de l'élément sélectionné à la manette (partagé par tous les boutons).
local function getSelectionImage(): Frame
	local existing = selectionImage
	if existing then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "ThemeSelection"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, 8, 1, 8)
	addCorner(frame, UDim.new(0, CORNER_RADIUS + 3))
	addStroke(frame, COLORS.amber, 0, 2)
	selectionImage = frame
	return frame
end

-- Rend un élément sur mesure (carte, ligne cliquable) sélectionnable à la manette, avec le cadre doré commun.
function Theme.makeSelectable(object: GuiObject)
	object.Selectable = true
	object.SelectionImageObject = getSelectionImage()
end

local function setNeighbor(object: GuiObject, property: string, neighbor: GuiObject?)
	(object :: any)[property] = neighbor
end

-- Relie des objets pour la navigation à la manette (croix directionnelle / joystick gauche).
function Theme.linkSelection(objects: { GuiObject }, mode: "horizontal" | "vertical" | "grid", columns: number?)
	local count = #objects
	local columnCount = if mode == "grid" then math.max(1, columns or 1) elseif mode == "horizontal" then count else 1
	for index, object in objects do
		local column = (index - 1) % columnCount
		local left = if column > 0 then objects[index - 1] else nil
		local right = if column < columnCount - 1 and index < count then objects[index + 1] else nil
		local up = if index - columnCount >= 1 then objects[index - columnCount] else nil
		local down = if index + columnCount <= count then objects[index + columnCount] else nil
		setNeighbor(object, "NextSelectionLeft", left)
		setNeighbor(object, "NextSelectionRight", right)
		if mode ~= "horizontal" then
			setNeighbor(object, "NextSelectionUp", up)
			setNeighbor(object, "NextSelectionDown", down)
		end
	end
end

--------------------------------------------------------------------------------
-- Bouton
--------------------------------------------------------------------------------

local Button = {}
Button.__index = Button

type ButtonData = {
	instance: TextButton,
	label: TextLabel,
	glyphLabel: TextLabel?,
	stroke: UIStroke,
	indicator: Frame?, -- barre de l'onglet sélectionné (variante "tab")
	_variant: ButtonVariant,
	_accent: Color3?,
	_enabled: boolean,
	_selected: boolean,
	_hovered: boolean,
	_pressed: boolean,
	_scale: UIScale,
	_listeners: { () -> () },
	_connections: { RBXScriptConnection },
}

export type Button = typeof(setmetatable({} :: ButtonData, Button))

type ButtonLook = {
	background: Color3,
	backgroundTransparency: number,
	stroke: Color3,
	strokeTransparency: number,
	text: Color3,
}

local function computeButtonLook(button: Button): ButtonLook
	local variant = button._variant
	local accent = button._accent or COLORS.gold
	local isQuiet = variant == "ghost" or variant == "tab"

	if not button._enabled then
		return {
			background = COLORS.surface,
			backgroundTransparency = if isQuiet then 1 else 0.55,
			stroke = COLORS.goldDim,
			strokeTransparency = if isQuiet then 1 else 0.75,
			text = COLORS.textDim,
		}
	end

	local isActive = button._hovered or button._pressed
	local isSelected = button._selected

	if variant == "primary" then
		return {
			background = if button._pressed then COLORS.goldDim elseif isActive then COLORS.goldBright else accent,
			backgroundTransparency = 0.04,
			stroke = COLORS.goldBright,
			strokeTransparency = if isActive then 0 else 0.45,
			text = COLORS.textOnAccent,
		}
	elseif variant == "danger" then
		return {
			background = COLORS.danger,
			backgroundTransparency = if button._pressed then 0.3 elseif isActive then 0.05 else 0.2,
			stroke = Color3.fromRGB(240, 120, 110),
			strokeTransparency = if isActive then 0 else 0.5,
			text = COLORS.text,
		}
	elseif variant == "ghost" then
		return {
			background = COLORS.surface,
			backgroundTransparency = if isActive then 0.5 else 1,
			stroke = accent,
			strokeTransparency = if isSelected then 0.3 else 1,
			text = if isSelected or isActive then COLORS.goldBright else COLORS.textMuted,
		}
	elseif variant == "tab" then
		return {
			background = COLORS.surface,
			backgroundTransparency = if isSelected then 0.3 elseif isActive then 0.6 else 1,
			stroke = accent,
			strokeTransparency = 1,
			text = if isSelected then COLORS.goldBright elseif isActive then COLORS.text else COLORS.textMuted,
		}
	end

	-- secondary
	return {
		background = if isSelected then accent elseif isActive then COLORS.surfaceHover else COLORS.surface,
		backgroundTransparency = if isSelected then 0.7 elseif isActive then 0.05 else 0.12,
		stroke = if isSelected or isActive then COLORS.goldBright else accent,
		strokeTransparency = if isSelected then 0 elseif isActive then 0.1 else ALPHA.border,
		text = if isSelected or isActive then COLORS.goldBright else COLORS.text,
	}
end

-- Applique l'apparence de l'état courant (en fondu court, sauf `instant`).
local function refreshButton(button: Button, instant: boolean?)
	local look = computeButtonLook(button)
	local duration = if instant then 0 else DURATIONS.fast
	local function apply(target: Instance, goal: { [string]: any })
		if duration <= 0 then
			for property, value in goal do
				(target :: any)[property] = value
			end
		else
			Theme.tween(target, goal, duration)
		end
	end

	apply(button.instance, { BackgroundColor3 = look.background, BackgroundTransparency = look.backgroundTransparency })
	apply(button.stroke, { Color = look.stroke, Transparency = look.strokeTransparency })
	apply(button.label, { TextColor3 = look.text })
	local glyphLabel = button.glyphLabel
	if glyphLabel then
		apply(glyphLabel, { TextColor3 = if button._selected and button._enabled then COLORS.amber else look.text })
	end
	local indicator = button.indicator
	if indicator then
		apply(indicator, { BackgroundTransparency = if button._selected then 0 else 1 })
	end
	apply(button._scale, { Scale = if button._pressed and button._enabled then 0.96 else 1 })
end

local function createButton(props: ButtonProps, isIcon: boolean): Button
	local variant: ButtonVariant = props.variant or "secondary"
	local textSize = props.textSize or (if isIcon then TEXT_SIZE.heading else TEXT_SIZE.button)

	local instance = Instance.new("TextButton")
	instance.Name = if isIcon then "IconButton" else "Button"
	instance.AutoButtonColor = false
	instance.Text = ""
	instance.BorderSizePixel = 0
	instance.Size = if isIcon then UDim2.fromOffset(BUTTON_HEIGHT, BUTTON_HEIGHT) else UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	instance.Selectable = true
	instance.SelectionImageObject = getSelectionImage()
	addCorner(instance, if props.round then UDim.new(0.5, 0) else UDim.new(0, CORNER_RADIUS))

	local stroke = addStroke(instance, COLORS.gold, ALPHA.border, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = instance

	local glyphLabel: TextLabel? = nil
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = props.font or FONTS.title
	label.TextScaled = true -- un libellé trop long rétrécit au lieu de déborder
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	label.Parent = instance

	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = textSize
	sizeLimit.MinTextSize = 9
	sizeLimit.Parent = label

	if isIcon then
		label.Text = props.glyph or props.text or ""
		label.Size = UDim2.fromScale(0.7, 0.7)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
	else
		label.Text = props.text or ""
		local horizontalPadding = SPACING.md
		if props.glyph then
			-- Symbole à gauche (chiffre romain d'un onglet...), texte à sa droite.
			local glyph = Instance.new("TextLabel")
			glyph.Name = "Glyph"
			glyph.BackgroundTransparency = 1
			glyph.Font = FONTS.title
			glyph.Text = props.glyph
			glyph.TextScaled = true
			glyph.AnchorPoint = Vector2.new(0, 0.5)
			glyph.Position = UDim2.new(0, horizontalPadding, 0.5, 0)
			glyph.Size = UDim2.new(0, 26, 0.6, 0)
			glyph.Parent = instance
			local glyphLimit = Instance.new("UITextSizeConstraint")
			glyphLimit.MaxTextSize = textSize
			glyphLimit.MinTextSize = 9
			glyphLimit.Parent = glyph
			glyphLabel = glyph

			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.new(0, horizontalPadding + 32, 0.5, 0)
			label.Size = UDim2.new(1, -(2 * horizontalPadding + 32), 0.62, 0)
			label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
		else
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.new(1, -2 * horizontalPadding, 0.62, 0)
		end
	end

	local indicator: Frame? = nil
	if variant == "tab" then
		local bar = Instance.new("Frame")
		bar.Name = "Indicator"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = props.accent or COLORS.amber
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(0, 3, 0.7, 0)
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(0, 0.5)
		bar.Parent = instance
		indicator = bar
	end

	local data: ButtonData = {
		instance = instance,
		label = label,
		glyphLabel = glyphLabel,
		stroke = stroke,
		indicator = indicator,
		_variant = variant,
		_accent = props.accent,
		_enabled = props.enabled ~= false,
		_selected = props.selected == true,
		_hovered = false,
		_pressed = false,
		_scale = scale,
		_listeners = {},
		_connections = {},
	}
	local button = setmetatable(data, Button)
	instance.Selectable = button._enabled

	local function setHovered(isHovered: boolean)
		if button._hovered ~= isHovered then
			button._hovered = isHovered
			if isHovered and button._enabled then
				Theme.playSound("hover")
			end
			refreshButton(button)
		end
	end
	local function setPressed(isPressed: boolean)
		if button._pressed ~= isPressed then
			button._pressed = isPressed
			refreshButton(button)
		end
	end

	local connections = button._connections
	table.insert(connections, instance.MouseEnter:Connect(function()
		setHovered(true)
	end))
	table.insert(connections, instance.MouseLeave:Connect(function()
		setPressed(false)
		setHovered(false)
	end))
	table.insert(connections, instance.SelectionGained:Connect(function()
		setHovered(true)
	end))
	table.insert(connections, instance.SelectionLost:Connect(function()
		setHovered(false)
	end))
	table.insert(connections, instance.MouseButton1Down:Connect(function()
		setPressed(true)
	end))
	table.insert(connections, instance.MouseButton1Up:Connect(function()
		setPressed(false)
		if Theme.getInputMode() == "touch" then
			setHovered(false) -- au doigt, pas de survol qui resterait allumé
		end
	end))
	table.insert(connections, instance.Activated:Connect(function()
		if not button._enabled then
			return
		end
		Theme.playSound("click")
		for _, listener in table.clone(button._listeners) do
			task.spawn(listener)
		end
	end))

	if props.onActivated then
		button:onActivated(props.onActivated)
	end

	refreshButton(button, true)
	applyCommon(instance, props)
	instance.Parent = props.parent
	return button
end

function Button.onActivated(self: Button, callback: () -> ()): Connection
	return connectListener(self._listeners, callback)
end

function Button.setEnabled(self: Button, enabled: boolean)
	if self._enabled == enabled then
		return
	end
	self._enabled = enabled
	self._pressed = false
	self.instance.Selectable = enabled
	refreshButton(self)
end

function Button.isEnabled(self: Button): boolean
	return self._enabled
end

function Button.setSelected(self: Button, selected: boolean)
	if self._selected == selected then
		return
	end
	self._selected = selected
	refreshButton(self)
end

function Button.isSelected(self: Button): boolean
	return self._selected
end

function Button.setText(self: Button, text: string)
	self.label.Text = text
end

function Button.setGlyph(self: Button, glyph: string)
	local glyphLabel = self.glyphLabel
	if glyphLabel then
		glyphLabel.Text = glyph
	else
		self.label.Text = glyph -- bouton à symbole seul
	end
end

-- Change la variante (un bouton "primary" qui devient "danger" pour une action irréversible...).
function Button.setVariant(self: Button, variant: ButtonVariant)
	if self._variant == variant then
		return
	end
	self._variant = variant
	refreshButton(self)
end

function Button.setAccent(self: Button, accent: Color3?)
	self._accent = accent
	local indicator = self.indicator
	if indicator then
		indicator.BackgroundColor3 = accent or COLORS.amber
	end
	refreshButton(self)
end

-- Côté de la barre d'onglet sélectionné : à gauche (rail vertical) ou en bas (rail horizontal).
function Button.setIndicatorSide(self: Button, side: "left" | "bottom")
	local indicator = self.indicator
	if indicator == nil then
		return
	end
	if side == "left" then
		indicator.AnchorPoint = Vector2.new(0, 0.5)
		indicator.Position = UDim2.fromScale(0, 0.5)
		indicator.Size = UDim2.new(0, 3, 0.7, 0)
	else
		indicator.AnchorPoint = Vector2.new(0.5, 1)
		indicator.Position = UDim2.fromScale(0.5, 1)
		indicator.Size = UDim2.new(0.7, 0, 0, 3)
	end
end

function Button.destroy(self: Button)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._listeners)
	self.instance:Destroy()
end

function Theme.button(props: ButtonProps): Button
	return createButton(props, false)
end

function Theme.iconButton(props: ButtonProps): Button
	return createButton(props, true)
end

--------------------------------------------------------------------------------
-- Onglets
--------------------------------------------------------------------------------

local Tabs = {}
Tabs.__index = Tabs

type TabsData = {
	instance: ScrollingFrame,
	buttons: { Button },
	items: { TabItem },
	_layout: UIListLayout,
	_separators: { Frame },
	_orientation: TabOrientation,
	_selected: number,
	_thickness: number,
	_length: number,
	_autoSelect: boolean,
	_listeners: { (index: number, id: string) -> () },
}

export type Tabs = typeof(setmetatable({} :: TabsData, Tabs))

-- Fait défiler `scroller` pour que `target` soit entièrement visible.
local function scrollIntoView(scroller: ScrollingFrame, target: GuiObject)
	local scale = getAccumulatedScale(scroller)
	local windowPosition = scroller.AbsolutePosition
	local windowSize = scroller.AbsoluteWindowSize
	local targetPosition = target.AbsolutePosition
	local targetSize = target.AbsoluteSize
	local canvas = scroller.CanvasPosition

	local deltaX, deltaY = 0, 0
	if targetPosition.X < windowPosition.X then
		deltaX = targetPosition.X - windowPosition.X
	elseif targetPosition.X + targetSize.X > windowPosition.X + windowSize.X then
		deltaX = (targetPosition.X + targetSize.X) - (windowPosition.X + windowSize.X)
	end
	if targetPosition.Y < windowPosition.Y then
		deltaY = targetPosition.Y - windowPosition.Y
	elseif targetPosition.Y + targetSize.Y > windowPosition.Y + windowSize.Y then
		deltaY = (targetPosition.Y + targetSize.Y) - (windowPosition.Y + windowSize.Y)
	end
	if deltaX ~= 0 or deltaY ~= 0 then
		scroller.CanvasPosition = canvas + Vector2.new(deltaX, deltaY) / scale
	end
end

function Theme.tabs(props: TabsProps): Tabs
	local scroller = Theme.scroller({ name = "Tabs" })
	scroller.ScrollBarThickness = 2

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SPACING.xs)
	layout.Parent = scroller

	local data: TabsData = {
		instance = scroller,
		buttons = {},
		items = props.items,
		_layout = layout,
		_separators = {},
		_orientation = props.orientation or "vertical",
		_selected = 0,
		_thickness = props.thickness or BUTTON_HEIGHT,
		_length = props.length or 128,
		_autoSelect = props.autoSelect ~= false,
		_listeners = {},
	}
	local tabs = setmetatable(data, Tabs)

	for index, item in props.items do
		if item.separatorBefore then
			local separator = Theme.divider({ layoutOrder = index * 2 - 1, parent = scroller })
			table.insert(tabs._separators, separator)
		end
		local button = Theme.button({
			name = "Tab_" .. item.id,
			text = item.label,
			glyph = item.glyph,
			variant = "tab",
			textSize = props.textSize or TEXT_SIZE.label,
			layoutOrder = index * 2,
			parent = scroller,
		})
		button:onActivated(function()
			if tabs._autoSelect then
				tabs:select(index, true)
			end
			for _, listener in table.clone(tabs._listeners) do
				task.spawn(listener, index, item.id)
			end
		end)
		tabs.buttons[index] = button
	end

	tabs:setOrientation(tabs._orientation)
	if props.selected then
		tabs:select(props.selected, true)
	end

	applyCommon(scroller, props)
	scroller.Parent = props.parent
	return tabs
end

function Tabs.setOrientation(self: Tabs, orientation: TabOrientation)
	self._orientation = orientation
	local isVertical = orientation == "vertical"
	local scroller = self.instance

	self._layout.FillDirection = if isVertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	self._layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	self._layout.VerticalAlignment = if isVertical then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
	scroller.ScrollingDirection = if isVertical then Enum.ScrollingDirection.Y else Enum.ScrollingDirection.X
	scroller.AutomaticCanvasSize = if isVertical then Enum.AutomaticSize.Y else Enum.AutomaticSize.X
	scroller.CanvasSize = UDim2.new()

	local objects: { GuiObject } = {}
	for _, button in self.buttons do
		button.instance.Size = if isVertical
			then UDim2.new(1, -6, 0, self._thickness)
			else UDim2.new(0, self._length, 1, -8)
		button:setIndicatorSide(if isVertical then "left" else "bottom")
		table.insert(objects, button.instance)
	end
	for _, separator in self._separators do
		separator.Size = if isVertical then UDim2.new(1, -6, 0, 1) else UDim2.new(0, 1, 0.6, 0)
		local gradient = separator:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Rotation = if isVertical then 0 else 90
		end
	end
	Theme.linkSelection(objects, if isVertical then "vertical" else "horizontal")
end

function Tabs.select(self: Tabs, index: number, silent: boolean?)
	local item = self.items[index]
	if item == nil then
		return
	end
	self._selected = index
	for buttonIndex, button in self.buttons do
		button:setSelected(buttonIndex == index)
	end
	scrollIntoView(self.instance, self.buttons[index].instance)
	if not silent then
		for _, listener in table.clone(self._listeners) do
			task.spawn(listener, index, item.id)
		end
	end
end

-- Fait défiler `scroller` (sans animation) pour que `target`, l'un de ses descendants, soit visible.
function Theme.scrollIntoView(scroller: ScrollingFrame, target: GuiObject)
	scrollIntoView(scroller, target)
end

function Tabs.getSelected(self: Tabs): number
	return self._selected
end

function Tabs.onChanged(self: Tabs, callback: (index: number, id: string) -> ()): Connection
	return connectListener(self._listeners, callback)
end

function Tabs.setEnabled(self: Tabs, index: number, enabled: boolean)
	local button = self.buttons[index]
	if button then
		button:setEnabled(enabled)
	end
end

function Tabs.destroy(self: Tabs)
	for _, button in self.buttons do
		button:destroy()
	end
	table.clear(self._listeners)
	self.instance:Destroy()
end

--------------------------------------------------------------------------------
-- Curseur à crans
--------------------------------------------------------------------------------

local Slider = {}
Slider.__index = Slider

type SliderData = {
	instance: Frame,
	track: TextButton,
	fill: Frame,
	knob: Frame,
	valueLabel: TextLabel,
	captionLabel: TextLabel,
	minusButton: Button,
	plusButton: Button,
	_ticks: { Frame },
	_min: number,
	_max: number,
	_step: number,
	_value: number,
	_format: (value: number) -> string,
	_focused: boolean,
	_dragInput: InputObject?,
	_listeners: { (value: number) -> () },
	_connections: { RBXScriptConnection },
}

export type Slider = typeof(setmetatable({} :: SliderData, Slider))

local SLIDER_HEIGHT = 80
local SLIDER_TRACK_HEIGHT = 6
local SLIDER_KNOB_SIZE = 16

-- Valeur ramenée sur le cran le plus proche, bornée, arrondie au centième (pas de 0.95000001).
local function snapValue(slider: Slider, value: number): number
	local steps = math.round((value - slider._min) / slider._step)
	local snapped = math.round((slider._min + steps * slider._step) * 100) / 100
	return math.clamp(snapped, slider._min, slider._max)
end

local function refreshSlider(slider: Slider)
	local range = slider._max - slider._min
	local fraction = if range > 0 then (slider._value - slider._min) / range else 0
	slider.fill.Size = UDim2.new(fraction, 0, 0, SLIDER_TRACK_HEIGHT)
	slider.knob.Position = UDim2.fromScale(fraction, 0.5)
	slider.valueLabel.Text = slider._format(slider._value)
	slider.minusButton:setEnabled(slider._value > slider._min)
	slider.plusButton:setEnabled(slider._value < slider._max)

	local tickCount = #slider._ticks
	for index, tick in slider._ticks do
		local tickFraction = if tickCount > 1 then (index - 1) / (tickCount - 1) else 0
		tick.BackgroundColor3 = if tickFraction <= fraction + 1e-6 then COLORS.goldBright else COLORS.goldDim
	end
end

function Theme.slider(props: SliderProps): Slider
	local frame = Instance.new("Frame")
	frame.Name = "Slider"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, SLIDER_HEIGHT)

	local captionLabel = Theme.caption({
		name = "Caption",
		text = props.label or "",
		size = UDim2.new(0.6, 0, 0, 22),
		parent = frame,
	})
	local valueLabel = Theme.label({
		name = "Value",
		font = FONTS.title,
		textSize = TEXT_SIZE.heading,
		alignX = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0.4, 0, 0, 24),
		parent = frame,
	})

	local controlRow = Instance.new("Frame")
	controlRow.Name = "Controls"
	controlRow.BackgroundTransparency = 1
	controlRow.Position = UDim2.fromOffset(0, 30)
	controlRow.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	controlRow.Parent = frame

	local minusButton = Theme.iconButton({ name = "Minus", glyph = "–", parent = controlRow })
	local plusButton = Theme.iconButton({
		name = "Plus",
		glyph = "+",
		anchor = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		parent = controlRow,
	})

	-- Zone cliquable de la piste (plus haute que la piste visible : facile à attraper au doigt).
	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.AutoButtonColor = false
	track.BackgroundTransparency = 1
	track.Text = ""
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.new(1, -2 * (BUTTON_HEIGHT + SPACING.md), 1, 0)
	track.Selectable = true
	track.SelectionImageObject = getSelectionImage()
	track.Parent = controlRow

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.BorderSizePixel = 0
	rail.BackgroundColor3 = COLORS.sunken
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.fromScale(0, 0.5)
	rail.Size = UDim2.new(1, 0, 0, SLIDER_TRACK_HEIGHT)
	rail.Parent = track
	addCorner(rail, UDim.new(0.5, 0))
	addStroke(rail, COLORS.goldDim, 0.4, 1)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = COLORS.gold
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.new(0, 0, 0, SLIDER_TRACK_HEIGHT)
	fill.Parent = track
	addCorner(fill, UDim.new(0.5, 0))

	-- Un cran par valeur possible.
	local ticks: { Frame } = {}
	local stepCount = math.max(1, math.round((props.max - props.min) / props.step))
	for index = 0, stepCount do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. index
		tick.BorderSizePixel = 0
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(index / stepCount, 0.5)
		tick.Size = UDim2.fromOffset(2, 12)
		tick.ZIndex = 2
		tick.Parent = track
		table.insert(ticks, tick)
	end

	-- Curseur : un losange doré.
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = COLORS.goldBright
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(SLIDER_KNOB_SIZE, SLIDER_KNOB_SIZE)
	knob.Rotation = 45
	knob.ZIndex = 3
	knob.Parent = track
	addStroke(knob, COLORS.ink, 0.2, 1)

	local data: SliderData = {
		instance = frame,
		track = track,
		fill = fill,
		knob = knob,
		valueLabel = valueLabel,
		captionLabel = captionLabel,
		minusButton = minusButton,
		plusButton = plusButton,
		_ticks = ticks,
		_min = props.min,
		_max = props.max,
		_step = props.step,
		_value = props.value or props.min,
		_format = props.format or function(value: number): string
			return tostring(value)
		end,
		_focused = false,
		_dragInput = nil,
		_listeners = {},
		_connections = {},
	}
	local slider = setmetatable(data, Slider)
	slider._value = snapValue(slider, slider._value)

	minusButton:onActivated(function()
		slider:nudge(-1)
	end)
	plusButton:onActivated(function()
		slider:nudge(1)
	end)

	-- Glisser sur la piste (souris ou doigt).
	local function setFromScreenX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local fraction = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		slider:setValue(slider._min + fraction * (slider._max - slider._min))
	end

	local connections = slider._connections
	table.insert(connections, track.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			slider._dragInput = input
			setFromScreenX(input.Position.X)
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		local dragInput = slider._dragInput
		if dragInput == nil then
			return
		end
		local isMouseDrag = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if isMouseDrag or input == dragInput then
			setFromScreenX(input.Position.X)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		local dragInput = slider._dragInput
		if dragInput == nil then
			return
		end
		if input == dragInput or input.UserInputType == dragInput.UserInputType then
			slider._dragInput = nil
		end
	end))

	refreshSlider(slider)
	applyCommon(frame, props)
	frame.Parent = props.parent
	return slider
end

function Slider.setValue(self: Slider, value: number, silent: boolean?)
	local snapped = snapValue(self, value)
	local changed = snapped ~= self._value
	self._value = snapped
	refreshSlider(self)
	if changed and not silent then
		for _, listener in table.clone(self._listeners) do
			task.spawn(listener, snapped)
		end
	end
end

function Slider.getValue(self: Slider): number
	return self._value
end

-- Avance d'un cran : direction = -1 ou +1.
function Slider.nudge(self: Slider, direction: number)
	self:setValue(self._value + direction * self._step)
end

-- Mise en avant du curseur que les flèches du clavier pilotent.
function Slider.setFocused(self: Slider, focused: boolean)
	self._focused = focused
	self.captionLabel.TextColor3 = if focused then COLORS.goldBright else COLORS.textMuted
	self.knob.Size = if focused
		then UDim2.fromOffset(SLIDER_KNOB_SIZE + 4, SLIDER_KNOB_SIZE + 4)
		else UDim2.fromOffset(SLIDER_KNOB_SIZE, SLIDER_KNOB_SIZE)
end

function Slider.onChanged(self: Slider, callback: (value: number) -> ()): Connection
	return connectListener(self._listeners, callback)
end

function Slider.destroy(self: Slider)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._listeners)
	self.minusButton:destroy()
	self.plusButton:destroy()
	self.instance:Destroy()
end

--------------------------------------------------------------------------------
-- Magies
--------------------------------------------------------------------------------

-- Dégradé d'une Magie Innée : cœur sombre -> couleur dominante -> éclat.
function Theme.magicGradient(palette: MagicPalette): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.void),
		ColorSequenceKeypoint.new(0.55, palette.main),
		ColorSequenceKeypoint.new(1, palette.glow),
	})
end

--------------------------------------------------------------------------------
-- Tables publiques
--------------------------------------------------------------------------------

Theme.colors = COLORS
Theme.fonts = FONTS
Theme.textSize = TEXT_SIZE
Theme.spacing = SPACING
Theme.durations = DURATIONS
Theme.alpha = ALPHA
Theme.displayOrder = DISPLAY_ORDER
Theme.buttonHeight = BUTTON_HEIGHT
Theme.cornerRadius = CORNER_RADIUS

return Theme
