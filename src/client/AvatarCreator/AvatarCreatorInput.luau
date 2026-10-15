--!strict
--[[
	AvatarCreatorInput
	Raccourcis du créateur de personnage, actifs UNIQUEMENT entre enable() et disable() : rien n'est
	lié en dehors du créateur, et aucune touche du jeu n'est réutilisée (E, R, F, Maj, M, J, Q restent
	à leurs propriétaires ; aucune lettre n'est utilisée).

		Clavier   Gauche / Droite     option précédente / suivante (curseur actif aux Proportions)
		          Haut / Bas          catégorie précédente / suivante (aux Proportions, passent d'abord
		                              d'un curseur à l'autre)
		          Tab / Maj + Tab     catégorie suivante / précédente
		          Entrée              continuer (au récapitulatif : ouvre la confirmation, ne valide jamais)
		          Retour arrière      revenir en arrière (ou annuler la confirmation)
		Souris    glisser sur la scène : tourner la vue ; molette : zoom
		Manette   LB / RB             option précédente / suivante (ou curseur sélectionné)
		          LT / RT             catégorie précédente / suivante
		          joystick droit      tourner et pencher la vue
		          croix, joystick gauche, A : naviguer et choisir (sélection native de GuiService)
		Tactile   un doigt sur la scène : tourner ; deux doigts : zoom ; boutons de 44 px virtuels et plus

	Les actions passent par ContextActionService à haute priorité et sont consommées : les autres
	scripts (combat, dash...) les reçoivent comme gameProcessed et les ignorent. La zone de glisser
	est un bouton invisible : un clic sur la scène n'est donc jamais pris pour un coup d'épée.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

export type Handlers = {
	onOption: (direction: number) -> (),
	-- `fromArrows` : vrai pour Haut / Bas (qui passent d'abord d'un curseur à l'autre aux Proportions),
	-- faux pour Tab et les gâchettes (toujours un changement de catégorie).
	onCategory: (direction: number, fromArrows: boolean) -> (),
	onAdvance: () -> (),
	onBack: () -> (),
	onOrbit: (input: Vector2) -> (),
	onDrag: (delta: Vector2) -> (),
	onZoom: (amount: number) -> (),
	onInputModeChanged: () -> (),
	onGamepadUsed: () -> (),
}

local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local ACTION_OPTION = "AvatarCreatorOption"
local ACTION_CATEGORY = "AvatarCreatorCategory"
local ACTION_ADVANCE = "AvatarCreatorAdvance"
local ACTION_BACK = "AvatarCreatorBack"
local ACTION_ORBIT = "AvatarCreatorOrbit"

local THUMBSTICK_DEADZONE = 0.18
local WHEEL_ZOOM_STEP = 0.08 -- zoom par cran de molette
local PINCH_ZOOM_FACTOR = 0.004 -- zoom par pixel d'écart gagné entre deux doigts

local AvatarCreatorInput = {}

local handlers: Handlers? = nil
local connections: { RBXScriptConnection } = {}
local mouseDragging = false
local dragTouch: InputObject? = nil
local lastTouchPosition = Vector3.zero
local activeTouches: { [InputObject]: Vector3 } = {}
local lastPinchDistance: number? = nil

--------------------------------------------------------------------------------
-- Actions (ContextActionService)
--------------------------------------------------------------------------------

-- Maj + Tab remonte d'une catégorie (Maj seule n'est jamais liée : elle reste au dash).
local function isShiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function onOptionAction(_actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
	local current = handlers
	if current and state == Enum.UserInputState.Begin then
		local isPrevious = input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.ButtonL1
		current.onOption(if isPrevious then -1 else 1)
	end
	return Enum.ContextActionResult.Sink
end

local function onCategoryAction(_actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
	local current = handlers
	if current and state == Enum.UserInputState.Begin then
		local keyCode = input.KeyCode
		local isPrevious = keyCode == Enum.KeyCode.Up
			or keyCode == Enum.KeyCode.ButtonL2
			or (keyCode == Enum.KeyCode.Tab and isShiftHeld())
		local fromArrows = keyCode == Enum.KeyCode.Up or keyCode == Enum.KeyCode.Down
		current.onCategory(if isPrevious then -1 else 1, fromArrows)
	end
	return Enum.ContextActionResult.Sink
end

local function onAdvanceAction(_actionName: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	local current = handlers
	if current and state == Enum.UserInputState.Begin then
		current.onAdvance()
	end
	return Enum.ContextActionResult.Sink
end

local function onBackAction(_actionName: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	local current = handlers
	if current and state == Enum.UserInputState.Begin then
		current.onBack()
	end
	return Enum.ContextActionResult.Sink
end

local function onOrbitAction(_actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
	local current = handlers
	if current == nil then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		current.onOrbit(Vector2.zero)
	else
		local stick = Vector2.new(input.Position.X, input.Position.Y)
		current.onOrbit(if stick.Magnitude < THUMBSTICK_DEADZONE then Vector2.zero else stick)
	end
	return Enum.ContextActionResult.Sink
end

--------------------------------------------------------------------------------
-- Glisser et pincer sur la scène
--------------------------------------------------------------------------------

local function countTouches(): number
	local count = 0
	for _ in activeTouches do
		count += 1
	end
	return count
end

-- Écart entre les deux premiers doigts posés sur la scène (nil s'il n'y en a pas deux).
local function getPinchDistance(): number?
	local first: Vector3? = nil
	for _, position in activeTouches do
		if first == nil then
			first = position
		else
			return (position - first).Magnitude
		end
	end
	return nil
end

local function onDragZoneInputBegan(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDragging = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		activeTouches[input] = input.Position
		if countTouches() == 1 then
			dragTouch = input
			lastTouchPosition = input.Position
			lastPinchDistance = nil
		else
			dragTouch = nil -- deux doigts : on zoome au lieu de tourner
			lastPinchDistance = getPinchDistance()
		end
	end
end

local function onDragZoneInputChanged(input: InputObject)
	local current = handlers
	if current and input.UserInputType == Enum.UserInputType.MouseWheel then
		current.onZoom(input.Position.Z * WHEEL_ZOOM_STEP)
	end
end

local function onInputChanged(input: InputObject)
	local current = handlers
	if current == nil then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement and mouseDragging then
		current.onDrag(Vector2.new(input.Delta.X, input.Delta.Y))
	elseif input.UserInputType == Enum.UserInputType.Touch and activeTouches[input] then
		activeTouches[input] = input.Position
		if input == dragTouch then
			local delta = input.Position - lastTouchPosition
			lastTouchPosition = input.Position
			current.onDrag(Vector2.new(delta.X, delta.Y))
		else
			local distance = getPinchDistance()
			local previous = lastPinchDistance
			if distance and previous then
				current.onZoom((distance - previous) * PINCH_ZOOM_FACTOR)
			end
			lastPinchDistance = distance
		end
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDragging = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		activeTouches[input] = nil
		if input == dragTouch then
			dragTouch = nil
		end
		lastPinchDistance = getPinchDistance()
	end
end

local function onInputBegan(input: InputObject, _gameProcessed: boolean)
	local current = handlers
	if current and string.find(input.UserInputType.Name, "Gamepad", 1, true) then
		current.onGamepadUsed()
	end
end

local function resetDragState()
	mouseDragging = false
	dragTouch = nil
	table.clear(activeTouches)
	lastPinchDistance = nil
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Active les raccourcis du créateur. `dragZone` : bouton invisible derrière l'interface.
function AvatarCreatorInput.enable(dragZone: GuiButton, newHandlers: Handlers)
	AvatarCreatorInput.disable()
	handlers = newHandlers

	ContextActionService:BindActionAtPriority(ACTION_OPTION, onOptionAction, false, ACTION_PRIORITY,
		Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority(ACTION_CATEGORY, onCategoryAction, false, ACTION_PRIORITY,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Tab, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(ACTION_ADVANCE, onAdvanceAction, false, ACTION_PRIORITY,
		Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter)
	ContextActionService:BindActionAtPriority(ACTION_BACK, onBackAction, false, ACTION_PRIORITY,
		Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(ACTION_ORBIT, onOrbitAction, false, ACTION_PRIORITY,
		Enum.KeyCode.Thumbstick2)

	table.insert(connections, dragZone.InputBegan:Connect(onDragZoneInputBegan))
	table.insert(connections, dragZone.InputChanged:Connect(onDragZoneInputChanged))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(function()
		local current = handlers
		if current then
			current.onInputModeChanged()
		end
	end))
end

-- Retire tous les raccourcis et écouteurs (idempotent).
function AvatarCreatorInput.disable()
	local previous = handlers
	handlers = nil
	if previous then
		previous.onOrbit(Vector2.zero)
	end

	for _, actionName in { ACTION_OPTION, ACTION_CATEGORY, ACTION_ADVANCE, ACTION_BACK, ACTION_ORBIT } do
		ContextActionService:UnbindAction(actionName)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	resetDragState()
end

function AvatarCreatorInput.isEnabled(): boolean
	return handlers ~= nil
end

return AvatarCreatorInput
