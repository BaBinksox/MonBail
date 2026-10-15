--!strict
--[[
	AvatarCreatorController (LocalScript)
	Chef d'orchestre du créateur de personnage, côté client. Le déroulé est celui du Hub d'origine :
		1. INTRODUCTION : le serveur demande l'ouverture (OpenCreator). Voile noir, phrases de narration,
		   musique du Hub (fondu d'entrée), puis le voile se lève pendant que la caméra avance ;
		2. CRÉATION : six étapes d'apparence (Corps, Visage, Marques, Chevelure, Tenue, Proportions).
		   Chaque changement demande un aperçu au serveur (PreviewAvatar, léger anti-rebond) ;
		3. DESTIN : choix de la Magie Innée (aucun aperçu : elle ne change pas l'apparence) ;
		4. RÉCAPITULATIF : relecture, puis confirmation explicite (« irréversible »). ApplyAvatar part UNE
		   seule fois et l'écran se fond au noir ;
		5. ENTRÉE DANS LE MONDE : le serveur confirme (CreatorClosed). Derrière le voile noir partagé de
		   Theme, on rend la caméra et les interfaces. World/ArrivalController joue ensuite la cinématique
		   d'arrivée, ou rouvre simplement l'écran si elle ne vient pas.

	Le client ne modifie jamais le personnage : il n'envoie que des index et des échelles (le Selection
	d'AvatarConfig). Le serveur applique, enregistre la magie, sauvegarde, libère le joueur et gère seul
	l'attribut IsCustomizing. Un joueur dont le personnage est déjà sauvegardé ne reçoit jamais
	OpenCreator.

	CreatorClosed peut arriver à TOUT moment (pendant l'intro, une transition, la confirmation...) :
	chaque suite asynchrone vérifie qu'elle appartient encore à la session en cours (jeton de session).

	Modules : AvatarCreatorView (interface), AvatarCreatorCamera (caméra et éclairage),
	AvatarCreatorInput (raccourcis, actifs seulement pendant la création), AvatarCreatorCatalog
	(étapes et vignettes), CreatorSession (état partagé avec ArrivalController).
]]

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local avatarFolder = sharedFolder:WaitForChild("Avatar")
local AvatarConfig = require(avatarFolder:WaitForChild("AvatarConfig"))
local Remotes = require(avatarFolder:WaitForChild("AvatarRemotes"))
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Camera = require(script.Parent:WaitForChild("AvatarCreatorCamera"))
local Catalog = require(script.Parent:WaitForChild("AvatarCreatorCatalog"))
local CreatorSession = require(script.Parent:WaitForChild("CreatorSession"))
local Input = require(script.Parent:WaitForChild("AvatarCreatorInput"))
local View = require(script.Parent:WaitForChild("AvatarCreatorView"))
local MusicDirector = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("MusicDirector"))

type Selection = AvatarConfig.Selection
type Step = Catalog.Step
type Slider = Theme.Slider

-- closed -> intro -> editing -> confirming -> closing -> closed (closing possible depuis tout état ouvert)
type Phase = "closed" | "intro" | "editing" | "confirming" | "closing"

-- Narration d'ouverture (inchangée). Passer INTRO_ENABLED à false pour tester plus vite.
local INTRO_ENABLED = true
local INTRO_LINES = {
	"Le froid. Puis le silence.",
	"Vous êtes mort... et pourtant, vos yeux s'ouvrent.",
	"Avant que le temps ne reprenne son cours, souvenez-vous de qui vous étiez.",
}
local INTRO_FADE_IN = 0.7
local INTRO_HOLD = 1.3
local INTRO_FADE_OUT = 0.5

local REVEAL_DURATION = 3 -- le voile noir se lève pendant que la caméra avance
local CHROME_DELAY = REVEAL_DURATION * 0.6 -- le rail et le panneau entrent quand la vue est presque revenue
local CHROME_SHOW_DURATION = 0.8
local CLOSE_FADE_OUT = 0.6
local CLOSE_FADE_IN = 1.2 -- réouverture de secours (voir scheduleReopenSafety)
local REOPEN_SAFETY_DELAY = 8 -- s après la fermeture : filet si ni la cinématique ni son repli n'ont rouvert l'écran


local PREVIEW_DELAY = 0.12 -- anti-rebond des aperçus
local PREVIEW_MIN_INTERVAL = 0.25 -- au plus un aperçu par quart de seconde pendant un défilement rapide

local CONFIRM_ARM_DELAY = 0.6 -- la validation ne s'arme qu'après ce délai : un double clic ne valide pas
local CONFIRM_FADE = 1.4 -- fondu au noir à la validation
local CONFIRM_TIMEOUT = 15 -- sans réponse du serveur, on rend la main pour relancer la validation
local CONFIRM_PENDING_TEXT = ". . ."
local CONFIRM_NARRATION = "Le temps reprend son cours..."
local CONFIRM_TIMEOUT_TEXT = "Le monde tarde à répondre. Réessayez dans un instant."

local ROTATE_STEP = 35 -- degrés par appui sur ⟲ / ⟳
local SKIN_REFRESH_DELAY = 2.5 -- s : le temps que le serveur ait appliqué l'aperçu (tête classique)

-- Rappel des commandes, sous le personnage, selon le dernier périphérique utilisé.
local HINTS: { [Theme.InputMode]: string } = {
	mouse = "Glisser : tourner la vue  ·  Molette : zoom  ·  Gauche / Droite : option  ·  Haut / Bas ou Tab : catégorie  ·  Entrée : continuer",
	touch = "Glissez pour tourner la vue  ·  Pincez pour zoomer",
	gamepad = "LB / RB : option  ·  LT / RT : catégorie  ·  Joystick droit : tourner la vue  ·  A : choisir",
}

local localPlayer = Players.LocalPlayer

local STEPS = Catalog.STEPS
local DESTINY_STEP = Catalog.findStep("destiny") or #STEPS
local APPEARANCE_COUNT = Catalog.countAppearanceSteps()

--------------------------------------------------------------------------------
-- Vue et musique
--------------------------------------------------------------------------------

-- MagicConfig.MAGICS est affiché tel quel : une magie ajoutée apparaît sans rien toucher ici.
local view = View.new(STEPS, MagicConfig.MAGICS)

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local selection: Selection = Catalog.defaultSelection()
local phase: Phase = "closed"
local sessionToken = 0 -- change à chaque ouverture et à chaque fermeture
local currentStep = 1
local isConfirmBoxOpen = false
local confirmArmedAt = 0 -- os.clock() à partir duquel la validation est possible
local focusedSlider = 1 -- 1 = taille, 2 = carrure (curseur piloté par Gauche / Droite)
local previewThread: thread? = nil
local lastPreviewClock = -math.huge
local ambienceEffects: { Instance } = {}
local characterConnection: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isCurrent(token: number): boolean
	return token == sessionToken
end

-- Liste circulaire : après le dernier choix on revient au premier.
local function cycleIndex(current: number, optionCount: number, direction: number): number
	return (current - 1 + direction) % optionCount + 1
end

-- Index de l'option courante d'une étape "liste" (1 pour les autres étapes).
local function getOptionIndex(step: Step): number
	local list = step.list
	return if list then list.get(selection) else 1
end

-- Rang d'une étape parmi les étapes d'apparence ("3 / 6").
local function getAppearancePosition(stepIndex: number): number
	local position = 0
	for index = 1, stepIndex do
		local kind = STEPS[index].kind
		if kind == "list" or kind == "proportions" then
			position += 1
		end
	end
	return position
end

local function getSelectedMagic(): MagicConfig.Magic
	return MagicConfig.MAGICS[selection.magicIndex] or MagicConfig.MAGICS[1]
end

--------------------------------------------------------------------------------
-- Aperçus (le serveur applique, il garde déjà la dernière demande en file)
--------------------------------------------------------------------------------

local function cancelPreview()
	local thread = previewThread
	previewThread = nil
	if thread then
		task.cancel(thread)
	end
end

local function sendPreviewNow()
	cancelPreview()
	lastPreviewClock = os.clock()
	Remotes.PreviewAvatar:FireServer(selection)
end

-- Aperçu différé : plusieurs changements rapprochés partent en UN envoi, avec le dernier choix.
local function schedulePreview()
	if previewThread then
		return
	end
	local sinceLast = os.clock() - lastPreviewClock
	local delay = math.max(PREVIEW_DELAY, PREVIEW_MIN_INTERVAL - sinceLast)
	previewThread = task.delay(delay, function()
		previewThread = nil
		if phase == "intro" or phase == "editing" then
			lastPreviewClock = os.clock()
			Remotes.PreviewAvatar:FireServer(selection)
		end
	end)
end

--------------------------------------------------------------------------------
-- Musique et ambiance (effets locaux : seul ce client les perçoit)
--------------------------------------------------------------------------------

-- La musique du créateur passe par MusicDirector (couche prioritaire « override ») : une seule
-- musique à la fois, fondus réglés dans AudioConfig.TRACKS.creator, volume « Musique » du joueur.
-- Changer de page ne la relance pas ; à la fermeture, la musique de la région reprend.
local function startMusic()
	MusicDirector.set("override", "creator")
end

local function stopMusic()
	MusicDirector.set("override", nil)
end

-- Monde froid et délavé (la profondeur de champ est gérée par AvatarCreatorCamera).
local function enableAmbience()
	if #ambienceEffects > 0 then
		return -- déjà en place (réouverture pendant le fondu de fermeture)
	end
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "AvatarCreatorColor"
	colorCorrection.Saturation = -0.45
	colorCorrection.Contrast = 0.15
	colorCorrection.Brightness = -0.04
	colorCorrection.TintColor = Color3.fromRGB(188, 200, 232)
	colorCorrection.Parent = Lighting
	ambienceEffects = { colorCorrection }
end

local function disableAmbience()
	for _, effect in ambienceEffects do
		effect:Destroy()
	end
	ambienceEffects = {}
end

-- Couleur de peau du personnage, reprise sous les vignettes de visages et de marques.
local function refreshSkinColor()
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		view:setSkinColor(head.Color)
	end
end

--------------------------------------------------------------------------------
-- Sélection à la manette
--------------------------------------------------------------------------------

local function isInsideCreator(object: GuiObject?): boolean
	return object ~= nil and object:IsDescendantOf(view.gui)
end

-- Place la sélection de la manette sur l'élément logique de l'étape. Sans `force`, ne fait rien si la
-- sélection est déjà dans le créateur (on ne vole pas la place du joueur).
local function selectDefault(force: boolean?)
	if phase ~= "editing" or Theme.getInputMode() ~= "gamepad" then
		return
	end
	if not force and isInsideCreator(GuiService.SelectedObject) then
		return
	end
	local target: GuiObject?
	if isConfirmBoxOpen then
		target = view.backButton.instance -- par prudence, on part de "Annuler"
	else
		local step = STEPS[currentStep]
		target = view:getDefaultSelectable(step, currentStep, getOptionIndex(step))
	end
	if target and target.Visible then
		GuiService.SelectedObject = target
	end
end

local function clearSelection()
	if isInsideCreator(GuiService.SelectedObject) then
		GuiService.SelectedObject = nil
	end
end

--------------------------------------------------------------------------------
-- Affichage
--------------------------------------------------------------------------------

local function refreshHint()
	view:setHint(HINTS[Theme.getInputMode()])
end

local function refreshOption(stepIndex: number)
	local list = STEPS[stepIndex].list
	if list == nil then
		return
	end
	local index = list.get(selection)
	view:setOption(stepIndex, index, list.options[index].name, #list.options)
end

local function setFocusedSlider(index: number)
	focusedSlider = index
	view.heightSlider:setFocused(index == 1)
	view.widthSlider:setFocused(index == 2)
end

-- Curseur visé par Gauche / Droite ou LB / RB : celui que la manette sélectionne, sinon le curseur actif.
local function getActiveSlider(): Slider
	local selected = GuiService.SelectedObject
	local heightSlider, widthSlider = view.heightSlider, view.widthSlider
	if selected and selected:IsDescendantOf(widthSlider.instance) then
		return widthSlider
	elseif selected and selected:IsDescendantOf(heightSlider.instance) then
		return heightSlider
	end
	return if focusedSlider == 2 then widthSlider else heightSlider
end

local function refreshSummary()
	local values: { [number]: string } = {}
	for index, step in STEPS do
		values[index] = Catalog.describe(step, selection)
	end
	view:setSummary(values, getSelectedMagic())
end

local function refreshHeader()
	local step = STEPS[currentStep]
	local caption
	if step.kind == "destiny" then
		caption = "DESTIN"
	elseif step.kind == "summary" then
		caption = "DERNIER REGARD"
	else
		caption = `ÉVEIL  ·  {getAppearancePosition(currentStep)} / {APPEARANCE_COUNT}`
	end
	view:setHeader(caption, step.title, step.subtitle)
end

-- Boutons du pied selon l'étape et l'état de la confirmation.
local function refreshFooter()
	local backButton, nextButton = view.backButton, view.nextButton
	if phase == "confirming" then
		view:setFooter("Annuler", CONFIRM_PENDING_TEXT, true)
		backButton:setEnabled(false)
		nextButton:setEnabled(false)
		return
	end

	local step = STEPS[currentStep]
	local previousStep = STEPS[currentStep - 1]
	local nextStep = STEPS[currentStep + 1]
	local backText = if previousStep then `‹  {previousStep.label}` else nil
	backButton:setEnabled(true)
	nextButton:setEnabled(true)

	if step.kind == "summary" and isConfirmBoxOpen then
		view:setFooter("Annuler", `S'éveiller  ·  {getSelectedMagic().name}`, true)
		nextButton:setEnabled(os.clock() >= confirmArmedAt)
	elseif step.kind == "summary" then
		view:setFooter(backText, "Confirmer")
	else
		view:setFooter(backText, if nextStep then `{nextStep.label}  ›` else "Suivant  ›")
	end
end

-- Contre-jour aux couleurs de la magie au Destin et au récapitulatif, lumière froide ailleurs.
local function refreshAccent()
	local kind = STEPS[currentStep].kind
	if kind == "destiny" or kind == "summary" then
		Camera.setAccent(getSelectedMagic().palette.main)
	else
		Camera.setAccent(nil)
	end
end

-- Contenu de la page de l'étape courante (appelé au creux du fondu des pages).
local function renderStepContent()
	local step = STEPS[currentStep]
	view:showPage(step, currentStep)
	if step.kind == "list" then
		refreshOption(currentStep)
	elseif step.kind == "proportions" then
		view.heightSlider:setValue(selection.heightScale, true)
		view.widthSlider:setValue(selection.widthScale, true)
		setFocusedSlider(focusedSlider)
	elseif step.kind == "destiny" then
		view:setMagic(selection.magicIndex)
	elseif step.kind == "summary" then
		refreshSummary()
	end
	view:setConfirming(isConfirmBoxOpen)
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

-- Va à l'étape `index` (bornée). `instant` : sans fondu des pages (ouverture).
local function goToStep(index: number, instant: boolean?)
	local target = math.clamp(index, 1, #STEPS)
	if target == currentStep and not instant then
		return
	end
	-- En arrivant aux Proportions par le haut, Haut / Bas partent du curseur le plus proche.
	if STEPS[target].kind == "proportions" then
		focusedSlider = if target < currentStep then 2 else 1
	end
	isConfirmBoxOpen = false
	currentStep = target

	view.tabs:select(target, true)
	Camera.setShot(STEPS[target].shot)
	view:setError(nil)
	refreshAccent()
	refreshHeader()
	refreshFooter()

	if instant then
		renderStepContent()
	else
		view:transitionPages(function()
			renderStepContent()
			selectDefault(true)
		end)
	end
end

local function openConfirmBox()
	isConfirmBoxOpen = true
	confirmArmedAt = os.clock() + CONFIRM_ARM_DELAY
	view:setError(nil)
	view:setConfirming(true)
	refreshFooter()
	selectDefault(true)

	local token = sessionToken
	task.delay(CONFIRM_ARM_DELAY, function()
		if isCurrent(token) and phase == "editing" and isConfirmBoxOpen then
			refreshFooter() -- le bouton de validation s'arme
		end
	end)
end

local function closeConfirmBox()
	isConfirmBoxOpen = false
	view:setConfirming(false)
	refreshFooter()
	selectDefault(true)
end

-- Validation finale : un seul ApplyAvatar par session (la phase quitte "editing" avant l'envoi).
local function confirmSelection()
	if phase ~= "editing" or not isConfirmBoxOpen or os.clock() < confirmArmedAt then
		return
	end
	phase = "confirming"
	local token = sessionToken

	cancelPreview() -- inutile : le choix final contient déjà tout
	clearSelection()
	refreshFooter()
	Remotes.ApplyAvatar:FireServer(selection)

	-- Fondu au noir : le serveur applique, sauvegarde et libère le joueur derrière le voile.
	view:setChromeShown(false)
	Camera.resetView()
	view:setVeil(true, CONFIRM_FADE)
	view:setNarration(CONFIRM_NARRATION, CONFIRM_FADE)

	task.delay(CONFIRM_TIMEOUT, function()
		if not isCurrent(token) or (phase :: Phase) ~= "confirming" then
			return
		end
		-- Aucune réponse : on rend la main. Une nouvelle validation est sans risque (le serveur ignore
		-- une demande quand la précédente est encore en cours).
		phase = "editing"
		confirmArmedAt = os.clock()
		view:setNarration(nil, 0.4)
		view:setVeil(false, 0.8)
		view:setChromeShown(true, CHROME_SHOW_DURATION)
		view:setError(CONFIRM_TIMEOUT_TEXT)
		refreshFooter()
		selectDefault(true)
	end)
end

local function onNextPressed()
	if phase ~= "editing" then
		return
	end
	if STEPS[currentStep].kind ~= "summary" then
		goToStep(currentStep + 1)
	elseif isConfirmBoxOpen then
		confirmSelection()
	else
		openConfirmBox()
	end
end

local function onBackPressed()
	if phase ~= "editing" then
		return
	end
	if isConfirmBoxOpen then
		closeConfirmBox()
	elseif currentStep > 1 then
		goToStep(currentStep - 1)
	end
end

--------------------------------------------------------------------------------
-- Choix
--------------------------------------------------------------------------------

-- Clic sur une vignette.
local function chooseOption(stepIndex: number, optionIndex: number)
	if phase ~= "editing" or stepIndex ~= currentStep then
		return
	end
	local list = STEPS[stepIndex].list
	if list == nil or list.options[optionIndex] == nil or list.get(selection) == optionIndex then
		return
	end
	list.set(selection, optionIndex)
	refreshOption(stepIndex)
	schedulePreview()
end

local function chooseMagic(index: number)
	if phase ~= "editing" or MagicConfig.MAGICS[index] == nil then
		return
	end
	selection.magicIndex = index
	view:setMagic(index)
	refreshAccent()
end

-- Flèches, LB / RB, boutons ‹ ›.
local function changeOption(direction: number)
	if phase ~= "editing" or isConfirmBoxOpen then
		return
	end
	local step = STEPS[currentStep]
	local list = step.list
	if list then
		list.set(selection, cycleIndex(list.get(selection), #list.options, direction))
		refreshOption(currentStep)
		schedulePreview()
		-- À la manette, la sélection suit la vignette choisie si elle était dans la grille.
		local grid = view.grids[currentStep]
		local selected = GuiService.SelectedObject
		local tile = grid and grid.tiles[list.get(selection)]
		if grid and tile and selected and selected:IsDescendantOf(grid.scroller) then
			GuiService.SelectedObject = tile.instance
		end
	elseif step.kind == "proportions" then
		getActiveSlider():nudge(direction) -- onChanged met à jour le choix et l'aperçu
	elseif step.kind == "destiny" then
		chooseMagic(cycleIndex(selection.magicIndex, #MagicConfig.MAGICS, direction))
	end
end

-- Haut / Bas, Tab, LT / RT.
local function changeCategory(direction: number, fromArrows: boolean)
	if phase ~= "editing" then
		return
	end
	if fromArrows and STEPS[currentStep].kind == "proportions" then
		if direction > 0 and focusedSlider == 1 then
			setFocusedSlider(2)
			return
		elseif direction < 0 and focusedSlider == 2 then
			setFocusedSlider(1)
			return
		end
	end
	local target = currentStep + direction
	if target >= 1 and target <= #STEPS then
		goToStep(target)
	end
end

-- Curseur de proportions déplacé (glisser, boutons, flèches) : la valeur est déjà sur un cran valide.
local function bindSlider(slider: Slider, sliderIndex: number, apply: (value: number) -> (), read: () -> number)
	slider:onChanged(function(value: number)
		if phase ~= "editing" then
			slider:setValue(read(), true) -- hors édition, on revient au choix en cours
			return
		end
		apply(value)
		setFocusedSlider(sliderIndex)
		schedulePreview()
	end)
end

--------------------------------------------------------------------------------
-- Ouverture / fermeture
--------------------------------------------------------------------------------

local function playIntro(token: number)
	for _, line in INTRO_LINES do
		view:setNarration(line, INTRO_FADE_IN)
		task.wait(INTRO_FADE_IN + INTRO_HOLD)
		if not isCurrent(token) then
			return
		end
		view:setNarration(nil, INTRO_FADE_OUT)
		task.wait(INTRO_FADE_OUT)
		if not isCurrent(token) then
			return
		end
	end
end

-- Un nouveau personnage (réapparition pendant la création) : on relit sa couleur de peau.
local function watchCharacter(token: number)
	local previous = characterConnection
	if previous then
		previous:Disconnect()
	end
	characterConnection = localPlayer.CharacterAdded:Connect(function()
		task.delay(SKIN_REFRESH_DELAY, function()
			if isCurrent(token) then
				refreshSkinColor()
			end
		end)
	end)
	task.delay(SKIN_REFRESH_DELAY, function()
		if isCurrent(token) then
			refreshSkinColor()
		end
	end)
end

local function stopWatchingCharacter()
	local connection = characterConnection
	characterConnection = nil
	if connection then
		connection:Disconnect()
	end
end

local inputHandlers: Input.Handlers = {
	onOption = changeOption,
	onCategory = changeCategory,
	onAdvance = function()
		-- Entrée continue, mais ne valide jamais : au récapitulatif, elle ouvre seulement la confirmation.
		if not (STEPS[currentStep].kind == "summary" and isConfirmBoxOpen) then
			onNextPressed()
		end
	end,
	onBack = onBackPressed,
	onOrbit = Camera.setOrbitInput,
	onDrag = function(delta: Vector2)
		-- En pixels virtuels : la même vitesse de rotation sur un téléphone et sur un écran 4K.
		Camera.drag(delta / math.max(view.screen.scale.Scale, 0.01))
	end,
	onZoom = Camera.zoomBy,
	onInputModeChanged = function()
		refreshHint()
		selectDefault()
	end,
	onGamepadUsed = function()
		selectDefault()
	end,
}

local function open()
	if phase == "intro" or phase == "editing" then
		-- Le serveur redemande l'ouverture après une réapparition : le nouveau personnage doit
		-- simplement recevoir le choix en cours (la caméra le suit déjà).
		sendPreviewNow()
		return
	elseif phase == "confirming" then
		return -- le choix final est parti : le serveur l'applique aussi au nouveau personnage
	end

	-- "closed", ou "closing" (rouvert pendant le fondu de fermeture : la fermeture s'interrompt).
	sessionToken += 1
	local token = sessionToken
	phase = "intro"
	CreatorSession.setActive(true)

	selection = Catalog.defaultSelection()
	isConfirmBoxOpen = false
	focusedSlider = 1
	goToStep(1, true)

	-- Tout se met en place derrière le voile noir du créateur.
	view:setVeil(true, 0)
	view:setNarration(nil, 0)
	view:setChromeShown(false, 0)
	view.gui.Enabled = true
	view:requestStageRefresh()
	Theme.screenFade(0) -- le voile partagé (noir après une fermeture) laisse la place à celui du créateur
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	enableAmbience()
	Camera.setWindow(view:measureStage())
	Camera.start()
	startMusic()
	sendPreviewNow() -- le personnage porte déjà le premier choix quand le voile se lève
	refreshSkinColor()
	refreshHint()
	watchCharacter(token)

	if INTRO_ENABLED then
		playIntro(token)
		if not isCurrent(token) then
			return
		end
	end

	-- Le réveil : le voile se lève pendant que la caméra avance vers le personnage.
	Camera.dollyIn(REVEAL_DURATION)
	view:setVeil(false, REVEAL_DURATION)
	task.wait(CHROME_DELAY)
	if not isCurrent(token) then
		return
	end
	view:setChromeShown(true, CHROME_SHOW_DURATION)
	task.wait(CHROME_SHOW_DURATION * 0.5)
	if not isCurrent(token) then
		return
	end

	phase = "editing"
	Input.enable(view.dragZone, inputHandlers)
	refreshFooter()
	selectDefault(true)
end

-- Filet de sécurité : ArrivalController rouvre normalement l'écran (cinématique, ou repli après 4 s).
-- Si, bien plus tard, l'écran est toujours noir sans cinématique en cours, on le rouvre ici.
local function scheduleReopenSafety(token: number)
	task.delay(REOPEN_SAFETY_DELAY, function()
		if isCurrent(token) and phase == "closed" and not CreatorSession.isArrivalBusy() and Theme.getScreenOpacity() > 0.5 then
			Theme.screenFade(0, CLOSE_FADE_IN)
		end
	end)
end

local function close()
	if phase == "closed" or phase == "closing" then
		return
	end
	sessionToken += 1
	local token = sessionToken
	phase = "closing"
	isConfirmBoxOpen = false

	Input.disable()
	cancelPreview()
	clearSelection()
	stopWatchingCharacter()
	stopMusic()

	-- Fondu au noir sur le voile partagé de Theme : il reste noir une fois le créateur fermé.
	Theme.screenFade(1, CLOSE_FADE_OUT)
	task.wait(CLOSE_FADE_OUT)
	if not isCurrent(token) then
		return -- rouvert pendant le fondu : la nouvelle session a tout repris
	end

	-- Derrière le voile : on rend la caméra, l'ambiance et les interfaces du jeu.
	Camera.stop()
	Camera.setStage(nil)
	disableAmbience()
	view:setChromeShown(false, 0)
	view:setConfirming(false)
	view:setNarration(nil, 0)
	view:setVeil(false, 0)
	view.gui.Enabled = false
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)

	phase = "closed"
	CreatorSession.setActive(false) -- ArrivalController prend le relais (l'écran est noir)
	scheduleReopenSafety(token)
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

view.tabs:onChanged(function(index: number)
	if phase == "editing" then
		goToStep(index)
	end
end)

view.previousOption:onActivated(function()
	changeOption(-1)
end)
view.nextOption:onActivated(function()
	changeOption(1)
end)

for stepIndex, grid in view.grids do
	for optionIndex, tile in grid.tiles do
		tile:onActivated(function()
			chooseOption(stepIndex, optionIndex)
		end)
	end
end

bindSlider(view.heightSlider, 1, function(value: number)
	selection.heightScale = value
end, function(): number
	return selection.heightScale
end)
bindSlider(view.widthSlider, 2, function(value: number)
	selection.widthScale = value
end, function(): number
	return selection.widthScale
end)
view.resetProportions:onActivated(function()
	if phase == "editing" then
		view.heightSlider:setValue(AvatarConfig.HEIGHT_SCALE.default)
		view.widthSlider:setValue(AvatarConfig.WIDTH_SCALE.default)
	end
end)

for index, card in view.magicCards do
	card.button.Activated:Connect(function()
		chooseMagic(index)
	end)
end

for _, row in view.summaryRows do
	row.button:onActivated(function()
		if phase == "editing" then
			goToStep(row.stepIndex)
		end
	end)
end
view.powerButton:onActivated(function()
	if phase == "editing" then
		goToStep(DESTINY_STEP)
	end
end)

view.backButton:onActivated(onBackPressed)
view.nextButton:onActivated(onNextPressed)

view.rotateLeft:onActivated(function()
	Camera.rotateBy(-ROTATE_STEP)
end)
view.rotateRight:onActivated(function()
	Camera.rotateBy(ROTATE_STEP)
end)

-- La caméra cadre le personnage dans la zone que l'interface laisse libre.
view:onStageChanged(function(window: View.Window)
	Camera.setWindow(window)
end)

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

Remotes.OpenCreator.OnClientEvent:Connect(open)
Remotes.CreatorClosed.OnClientEvent:Connect(close)

-- Scène du créateur (SpawnService). Requis à part : si le serveur ne crée jamais ces Remotes, le
-- créateur fonctionne quand même, avec le cadrage relatif au personnage.
task.spawn(function()
	local SpawnRemotes = require(sharedFolder:WaitForChild("World"):WaitForChild("SpawnRemotes"))
	SpawnRemotes.CreatorStageReady.OnClientEvent:Connect(function(_stageCFrame: any, cameraCFrame: any)
		Camera.setStage(if typeof(cameraCFrame) == "CFrame" then cameraCFrame else nil)
	end)
end)
