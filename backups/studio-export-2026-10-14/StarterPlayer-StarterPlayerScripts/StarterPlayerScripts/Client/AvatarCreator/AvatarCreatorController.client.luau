--!strict
--[[
	AvatarCreatorController (LocalScript)
	Chef d'orchestre du Hub de création, côté client :
		- ouvre le Hub quand le serveur le demande (OpenCreator) : narration, caméra, ambiance, musique ;
		- page ÉVEIL  : garde le choix d'apparence, met à jour l'interface et demande un aperçu
		  au serveur à chaque clic ;
		- page DESTIN : choix de la Magie Innée (aucun aperçu : elle ne change pas l'apparence) ;
		- envoie le choix final (ApplyAvatar) et referme tout quand le serveur confirme (CreatorClosed).

	Le client ne modifie jamais le personnage lui-même : il ne fait qu'envoyer des index et des échelles,
	c'est le serveur qui applique l'apparence, enregistre la magie, sauvegarde et libère le joueur.
	Un joueur dont le personnage est déjà sauvegardé ne reçoit jamais OpenCreator : il ne voit pas le Hub.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local avatarFolder = sharedFolder:WaitForChild("Avatar")
local AvatarConfig = require(avatarFolder:WaitForChild("AvatarConfig") :: ModuleScript)
local Remotes = require(avatarFolder:WaitForChild("AvatarRemotes") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)

local Camera = require(script.Parent:WaitForChild("AvatarCreatorCamera") :: ModuleScript)
local View = require(script.Parent:WaitForChild("AvatarCreatorView") :: ModuleScript)

-- Narration d'ouverture. Passer INTRO_ENABLED à false pour tester plus vite.
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
local PANEL_FADE_DURATION = 1
local PAGE_FADE_DURATION = 0.25 -- fondu du panneau entre les deux pages
local CLOSE_FADE_OUT = 0.6
local CLOSE_FADE_IN = 1.2

local MUSIC_FADE_IN = 2.5
local MUSIC_FADE_OUT = 1.5

local CONFIRM_PENDING_TEXT = ". . ."

-- Liseré d'un bouton de magie : discret au repos, plein quand la magie est sélectionnée.
local MAGIC_STROKE_IDLE = 0.75
local MAGIC_FILL_SELECTED = 0.8 -- transparence du fond coloré du bouton sélectionné

--------------------------------------------------------------------------------
-- Vue et musique
--------------------------------------------------------------------------------

local magicEntries = {}
for index, magic in MagicConfig.MAGICS do
	magicEntries[index] = { name = magic.name, color = magic.palette.main }
end

local view = View.create(Players.LocalPlayer:WaitForChild("PlayerGui"), magicEntries)

-- Créé depuis un LocalScript : ce son n'existe et ne se joue que sur ce client.
local music = Instance.new("Sound")
music.Name = "HubMusic"
music.SoundId = AvatarConfig.HUB_MUSIC_ID
music.Looped = true
music.Volume = 0
music.Parent = SoundService

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local selection = {
	baseIndex = 1,
	faceIndex = 1,
	markIndex = 1,
	hairIndex = 1,
	outfitIndex = 1,
	heightScale = AvatarConfig.HEIGHT_SCALE.default,
	widthScale = AvatarConfig.WIDTH_SCALE.default,
	magicIndex = 1,
}
local isOpen = false
local isInteractive = false -- false pendant les transitions et l'attente du serveur
local ambienceEffects: { Instance } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function tween(instance: Instance, duration: number, goal: { [string]: any }): Tween
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local newTween = TweenService:Create(instance, tweenInfo, goal)
	newTween:Play()
	return newTween
end

-- Liste circulaire : après le dernier choix on revient au premier.
local function cycleIndex(current: number, optionCount: number, direction: number): number
	return (current - 1 + direction) % optionCount + 1
end

-- Échelle bornée, arrondie au centième pour éviter les dérives de flottants (0.95000001...).
local function stepScale(current: number, range: any, direction: number): number
	local stepped = math.round((current + direction * range.step) * 100) / 100
	return math.clamp(stepped, range.min, range.max)
end

-- Affiche l'option `index` de `options` dans un sélecteur de liste : son nom et "3 / 15".
local function showListOption(stepper: any, options: { any }, index: number)
	stepper.valueLabel.Text = options[index].name
	stepper.counterLabel.Text = `{index} / {#options}`
end

local function refreshAppearancePage()
	showListOption(view.baseStepper, AvatarConfig.BASE_OPTIONS, selection.baseIndex)
	showListOption(view.faceStepper, AvatarConfig.FACE_OPTIONS, selection.faceIndex)
	showListOption(view.markStepper, AvatarConfig.MARK_OPTIONS, selection.markIndex)
	showListOption(view.hairStepper, AvatarConfig.HAIR_OPTIONS, selection.hairIndex)
	showListOption(view.outfitStepper, AvatarConfig.OUTFIT_OPTIONS, selection.outfitIndex)
	view.heightStepper.valueLabel.Text = `{math.round(selection.heightScale * 100)} %`
	view.widthStepper.valueLabel.Text = `{math.round(selection.widthScale * 100)} %`
end

local function refreshDestinyPage()
	local selectedMagic = MagicConfig.MAGICS[selection.magicIndex]

	for index, magicButton in view.magicButtons do
		local isSelected = index == selection.magicIndex
		magicButton.stroke.Transparency = if isSelected then 0 else MAGIC_STROKE_IDLE
		magicButton.button.BackgroundTransparency = if isSelected then MAGIC_FILL_SELECTED else 1
	end

	view.magicDescription.Text = `<b>{selectedMagic.ultimateName}</b>\n{selectedMagic.description}`
	view.confirmButton.Text = `S'ÉVEILLER  -  {selectedMagic.name}`
end

local function sendPreview()
	Remotes.PreviewAvatar:FireServer(selection)
end

--------------------------------------------------------------------------------
-- Musique et ambiance (effets locaux : seul ce client les perçoit)
--------------------------------------------------------------------------------

local function startMusic()
	if AvatarConfig.HUB_MUSIC_ID == "" then
		return
	end
	music.Volume = 0
	music:Play()
	tween(music, MUSIC_FADE_IN, { Volume = AvatarConfig.HUB_MUSIC_VOLUME })
end

local function stopMusic()
	tween(music, MUSIC_FADE_OUT, { Volume = 0 }).Completed:Once(function()
		if not isOpen then
			music:Stop()
		end
	end)
end

local function enableAmbience()
	-- Monde froid et délavé.
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "AvatarCreatorColor"
	colorCorrection.Saturation = -0.45
	colorCorrection.Contrast = 0.15
	colorCorrection.Brightness = -0.04
	colorCorrection.TintColor = Color3.fromRGB(188, 200, 232)
	colorCorrection.Parent = Lighting

	-- Décor flou derrière le personnage. Pendant le travelling d'ouverture, le personnage
	-- entre peu à peu dans la zone nette : c'est la vue qui "revient".
	local depthOfField = Instance.new("DepthOfFieldEffect")
	depthOfField.Name = "AvatarCreatorDepthOfField"
	depthOfField.FocusDistance = 10
	depthOfField.InFocusRadius = 5
	depthOfField.FarIntensity = 0.8
	depthOfField.NearIntensity = 0
	depthOfField.Parent = Lighting

	ambienceEffects = { colorCorrection, depthOfField }
end

local function disableAmbience()
	for _, effect in ambienceEffects do
		effect:Destroy()
	end
	ambienceEffects = {}
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local function showPageInstantly(isDestinyPage: boolean)
	view.appearancePage.Visible = not isDestinyPage
	view.destinyPage.Visible = isDestinyPage
end

-- Passe d'une page à l'autre par un bref fondu du panneau. YIELD.
local function switchPage(isDestinyPage: boolean)
	isInteractive = false
	tween(view.panel, PAGE_FADE_DURATION, { GroupTransparency = 1 }).Completed:Wait()
	showPageInstantly(isDestinyPage)
	tween(view.panel, PAGE_FADE_DURATION, { GroupTransparency = 0 }).Completed:Wait()
	isInteractive = true
end

--------------------------------------------------------------------------------
-- Ouverture / fermeture
--------------------------------------------------------------------------------

local function playIntro()
	for _, line in INTRO_LINES do
		view.introLabel.Text = line
		tween(view.introLabel, INTRO_FADE_IN, { TextTransparency = 0 }).Completed:Wait()
		task.wait(INTRO_HOLD)
		tween(view.introLabel, INTRO_FADE_OUT, { TextTransparency = 1 }).Completed:Wait()
	end
end

local function open()
	if isOpen then
		-- Le serveur redemande l'ouverture après un respawn : le nouveau personnage
		-- doit simplement recevoir le choix en cours, la caméra le suit déjà.
		sendPreview()
		return
	end
	isOpen = true

	selection.baseIndex = 1
	selection.faceIndex = 1
	selection.markIndex = 1
	selection.hairIndex = 1
	selection.outfitIndex = 1
	selection.heightScale = AvatarConfig.HEIGHT_SCALE.default
	selection.widthScale = AvatarConfig.WIDTH_SCALE.default
	selection.magicIndex = 1
	refreshAppearancePage()
	refreshDestinyPage()
	showPageInstantly(false)

	-- Tout se met en place derrière le voile noir.
	view.fade.BackgroundTransparency = 0
	view.panel.GroupTransparency = 1
	view.gui.Enabled = true
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	enableAmbience()
	Camera.start()
	startMusic()
	sendPreview() -- le personnage porte déjà le premier choix quand le voile se lève

	if INTRO_ENABLED then
		playIntro()
	end

	-- Le réveil : le voile se lève pendant que la caméra avance vers le personnage.
	Camera.dollyIn(REVEAL_DURATION)
	tween(view.fade, REVEAL_DURATION, { BackgroundTransparency = 1 })
	task.wait(REVEAL_DURATION * 0.6)
	tween(view.panel, PANEL_FADE_DURATION, { GroupTransparency = 0 }).Completed:Wait()

	isInteractive = true
end

local function close()
	if not isOpen then
		return
	end
	isInteractive = false
	isOpen = false
	stopMusic()

	-- Fondu au noir, on rend la caméra et l'écran derrière le voile, puis on rouvre les yeux en jeu.
	tween(view.fade, CLOSE_FADE_OUT, { BackgroundTransparency = 0 }).Completed:Wait()
	Camera.stop()
	disableAmbience()
	view.panel.GroupTransparency = 1
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	tween(view.fade, CLOSE_FADE_IN, { BackgroundTransparency = 1 }).Completed:Wait()

	if not isOpen then -- le Hub n'a pas été rouvert pendant le fondu
		view.gui.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

-- Relie les deux flèches d'un sélecteur à `onStep(direction)`, avec direction = -1 ou +1.
local function bindStepper(stepper: any, onStep: (direction: number) -> ())
	local function step(direction: number)
		if not isInteractive then
			return
		end
		onStep(direction)
		refreshAppearancePage()
		sendPreview()
	end

	stepper.previousButton.Activated:Connect(function()
		step(-1)
	end)
	stepper.nextButton.Activated:Connect(function()
		step(1)
	end)
end

-- Léger fond doré au survol d'un grand bouton.
local function bindHover(button: TextButton)
	button.MouseEnter:Connect(function()
		tween(button, 0.15, { BackgroundTransparency = 0.75 })
	end)
	button.MouseLeave:Connect(function()
		tween(button, 0.15, { BackgroundTransparency = 1 })
	end)
end

-- Page ÉVEIL --------------------------------------------------------------------

bindStepper(view.baseStepper, function(direction: number)
	selection.baseIndex = cycleIndex(selection.baseIndex, #AvatarConfig.BASE_OPTIONS, direction)
end)

bindStepper(view.faceStepper, function(direction: number)
	selection.faceIndex = cycleIndex(selection.faceIndex, #AvatarConfig.FACE_OPTIONS, direction)
end)

bindStepper(view.markStepper, function(direction: number)
	selection.markIndex = cycleIndex(selection.markIndex, #AvatarConfig.MARK_OPTIONS, direction)
end)

bindStepper(view.hairStepper, function(direction: number)
	selection.hairIndex = cycleIndex(selection.hairIndex, #AvatarConfig.HAIR_OPTIONS, direction)
end)

bindStepper(view.outfitStepper, function(direction: number)
	selection.outfitIndex = cycleIndex(selection.outfitIndex, #AvatarConfig.OUTFIT_OPTIONS, direction)
end)

bindStepper(view.heightStepper, function(direction: number)
	selection.heightScale = stepScale(selection.heightScale, AvatarConfig.HEIGHT_SCALE, direction)
end)

bindStepper(view.widthStepper, function(direction: number)
	selection.widthScale = stepScale(selection.widthScale, AvatarConfig.WIDTH_SCALE, direction)
end)

view.nextButton.Activated:Connect(function()
	if isInteractive then
		switchPage(true)
	end
end)
bindHover(view.nextButton)

-- Page DESTIN -------------------------------------------------------------------

for index, magicButton in view.magicButtons do
	magicButton.button.Activated:Connect(function()
		if isInteractive then
			selection.magicIndex = index
			refreshDestinyPage()
		end
	end)
end

view.backButton.Activated:Connect(function()
	if isInteractive then
		switchPage(false)
	end
end)

view.confirmButton.Activated:Connect(function()
	if not isInteractive then
		return
	end
	isInteractive = false
	view.confirmButton.Text = CONFIRM_PENDING_TEXT
	Remotes.ApplyAvatar:FireServer(selection)
end)
bindHover(view.confirmButton)

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

Remotes.OpenCreator.OnClientEvent:Connect(open)
Remotes.CreatorClosed.OnClientEvent:Connect(close)
