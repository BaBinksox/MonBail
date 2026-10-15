--!strict
--[[
	ArrivalController (LocalScript)
	Cinématique d'arrivée dans le monde, à la sortie du créateur de personnage.

	SpawnRemotes.ArrivalCinematic(cameraCFrame, focus, regionName), envoyé par le serveur juste après
	avoir posé le personnage au belvédère :
		1. l'écran est déjà noir (fondu de fin du créateur, voile partagé de Theme) ou le devient ;
		2. la caméra (Scriptable) se place à cameraCFrame, tournée vers `focus` ;
		3. fondu d'ouverture, lent travelling (6,5 s) entre deux bandes cinéma, titre de la région en
		   lettres dorées (son nom et son sous-titre, lus dans RegionConfig) ;
		4. retour en douceur derrière le personnage, puis caméra normale (Custom, sujet = Humanoid).
	Pendant la cinématique, les déplacements sont suspendus (contrôles du PlayerModule) et
	CreatorSession.isArrivalBusy() est vrai : les interfaces peuvent s'en servir pour rester discrètes.

	Repli : si l'événement n'arrive pas dans les 4 s qui suivent CreatorClosed, l'écran est simplement
	rouvert (jamais d'écran noir bloqué). Un événement qui arrive après ce repli est ignoré : on ne
	reprend pas la caméra à un joueur qui joue déjà.
	Aucune touche n'est liée ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AvatarRemotes = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarRemotes"))
local RegionConfig = require(sharedFolder:WaitForChild("World"):WaitForChild("RegionConfig"))

local clientFolder = script.Parent.Parent
local Theme = require(clientFolder:WaitForChild("UI"):WaitForChild("Theme"))
local CreatorSession = require(clientFolder:WaitForChild("AvatarCreator"):WaitForChild("CreatorSession"))

local FALLBACK_DELAY = 4 -- s après CreatorClosed sans cinématique : l'écran est rouvert
local LATE_WINDOW = 15 -- s après ce repli pendant lesquelles une cinématique tardive est ignorée
local CREATOR_WAIT_TIMEOUT = 6 -- s d'attente de la fin de la fermeture du créateur
local BLACKOUT_FADE = 0.6 -- fondu au noir si l'écran ne l'est pas déjà
local OPEN_FADE = 1.8 -- fondu d'ouverture sur le premier plan
local REOPEN_FADE = 1.2 -- réouverture simple (repli, ou fin anormale)

local TRAVEL_DURATION = 6.5
local TITLE_DELAY = 1.2 -- après le début du fondu d'ouverture
local TITLE_FADE_IN = 1.4
local TITLE_HOLD = 2.4
local TITLE_FADE_OUT = 1.2
local TITLE_DRIFT = 0.02 -- le titre remonte doucement en apparaissant (part de l'écran)
local RETURN_DURATION = 1.8 -- vol de retour derrière le personnage
local BARS_DURATION = 0.9
local BAR_HEIGHT = 0.1 -- part de la hauteur de l'écran couverte par chaque bande cinéma

local CINEMATIC_FOV = 50
local PUSH_FRACTION = 0.12 -- le travelling avance de cette part de la distance au point visé...
local MAX_PUSH = 18 -- ... sans dépasser ce nombre de studs
local DRIFT_FRACTION = 0.06 -- glissement latéral (part de la distance)
local MAX_DRIFT = 14
local DESCENT_FRACTION = 0.03 -- légère descente (part de la distance)
local MAX_DESCENT = 8

-- Pose de la caméra de jeu en fin de cinématique (proche de celle de la caméra Roblox par défaut).
local RETURN_DISTANCE = 12.5
local RETURN_PITCH = 14 -- degrés, la caméra plonge légèrement
local SUBJECT_HEIGHT = 1.5 -- au-dessus du RootPart

local RENDER_STEP_NAME = "ArrivalCinematic"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local DEFAULT_SUBTITLE = "Les Terres de la Cloche" -- région inconnue de RegionConfig

local COLORS = Theme.colors
local FONTS = Theme.fonts

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Interface : bandes cinéma et titre (au-dessus du voile noir partagé)
--------------------------------------------------------------------------------

local screen = Theme.screenGui("ArrivalTitleGui", Theme.displayOrder.cinematic)
screen.gui.Enabled = false

local function newBar(name: string): Frame
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.Size = UDim2.fromScale(1, BAR_HEIGHT)
	bar.Parent = screen.root
	return bar
end

-- Positions des bandes : rentrées (hors de l'écran) ou sorties.
local TOP_BAR_HIDDEN = UDim2.fromScale(0, -BAR_HEIGHT)
local TOP_BAR_SHOWN = UDim2.fromScale(0, 0)
local BOTTOM_BAR_HIDDEN = UDim2.fromScale(0, 1)
local BOTTOM_BAR_SHOWN = UDim2.fromScale(0, 1 - BAR_HEIGHT)

local topBar = newBar("TopBar")
local bottomBar = newBar("BottomBar")

local TITLE_POSITION = UDim2.fromScale(0.5, 0.62)
local titleGroup, titleContent = Theme.group({
	name = "Title",
	style = "none",
	border = false,
	corner = 0,
	anchor = Vector2.new(0.5, 0.5),
	position = TITLE_POSITION,
	size = UDim2.new(0.86, 0, 0, 150),
	maxSize = Vector2.new(980, 150),
	parent = screen.safe,
})
titleGroup.GroupTransparency = 1
titleGroup.Visible = false

local titleLayout = Instance.new("UIListLayout")
titleLayout.FillDirection = Enum.FillDirection.Vertical
titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
titleLayout.Padding = UDim.new(0, Theme.spacing.sm)
titleLayout.Parent = titleContent

local regionLabel = Theme.title({
	name = "RegionName",
	font = FONTS.display,
	textSize = Theme.textSize.display,
	color = COLORS.goldBright,
	alignX = Enum.TextXAlignment.Center,
	size = UDim2.new(1, 0, 0, 76),
	scaled = true,
	minTextSize = 28,
	maxTextSize = Theme.textSize.display,
	stroke = true,
	layoutOrder = 1,
	parent = titleContent,
})
-- Or patiné : plus clair en haut des lettres.
local regionGradient = Instance.new("UIGradient")
regionGradient.Rotation = 90
regionGradient.Color = ColorSequence.new(COLORS.goldBright, COLORS.gold)
regionGradient.Parent = regionLabel

Theme.divider({ size = UDim2.new(0.42, 0, 0, 1), layoutOrder = 2, parent = titleContent })

local subtitleLabel = Theme.label({
	name = "Subtitle",
	font = FONTS.title,
	textSize = 22,
	color = COLORS.text,
	alignX = Enum.TextXAlignment.Center,
	size = UDim2.new(1, 0, 0, 30),
	scaled = true,
	minTextSize = 13,
	maxTextSize = 22,
	stroke = true,
	layoutOrder = 3,
	parent = titleContent,
})

local function setBarsShown(shown: boolean, duration: number)
	local topTarget = if shown then TOP_BAR_SHOWN else TOP_BAR_HIDDEN
	local bottomTarget = if shown then BOTTOM_BAR_SHOWN else BOTTOM_BAR_HIDDEN
	if duration <= 0 then
		topBar.Position = topTarget
		bottomBar.Position = bottomTarget
		return
	end
	Theme.tween(topBar, { Position = topTarget }, duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Theme.tween(bottomBar, { Position = bottomTarget }, duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

local function hideTitleNow()
	titleGroup.GroupTransparency = 1
	titleGroup.Visible = false
	titleGroup.Position = TITLE_POSITION
end

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local isPlaying = false
local closeToken = 0 -- incrémenté à chaque CreatorClosed
local pendingCloseToken: number? = nil -- fermeture qui attend encore sa cinématique
local lateUntil = 0 -- os.clock() jusqu'auquel une cinématique tardive est ignorée
local savedFieldOfView = 70

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Nom affiché et sous-titre d'une région : `regionName` peut être le nom ou l'identifiant.
local function describeRegion(regionName: string): (string, string)
	for _, region in RegionConfig.REGIONS do
		if region.name == regionName or region.id == regionName then
			return region.name, region.subtitle
		end
	end
	return regionName, DEFAULT_SUBTITLE
end

local function getHumanoid(): Humanoid?
	local character = localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Suspend ou rend les déplacements du joueur (module de contrôle standard de Roblox).
-- Sans PlayerModule (jeu qui le remplace), la cinématique se joue sans bloquer les déplacements.
local function setControlsEnabled(enabled: boolean)
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if playerModule == nil or not playerModule:IsA("ModuleScript") then
		return
	end
	local isDone, problem = pcall(function()
		local controls = (require :: any)(playerModule):GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not isDone then
		warn(`[Arrival] Contrôles du joueur inaccessibles : {problem}`)
	end
end

-- Départ et arrivée du travelling : on avance vers `focus` en glissant un peu de côté et en descendant.
local function buildTravel(cameraCFrame: CFrame, focus: Vector3): (Vector3, Vector3)
	local start = cameraCFrame.Position
	local toFocus = focus - start
	local distance = toFocus.Magnitude
	if distance < 1e-3 then
		return start, start
	end
	local forward = toFocus.Unit
	local side = forward:Cross(Vector3.yAxis)
	local right = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local finish = start
		+ forward * math.min(distance * PUSH_FRACTION, MAX_PUSH)
		+ right * math.min(distance * DRIFT_FRACTION, MAX_DRIFT)
		- Vector3.yAxis * math.min(distance * DESCENT_FRACTION, MAX_DESCENT)
	return start, finish
end

-- Pose de la caméra de jeu : derrière le personnage, tournée vers `lookToward` (le village).
local function computeGameplayPose(lookToward: Vector3): CFrame?
	local humanoid = getHumanoid()
	local rootPart = humanoid and humanoid.RootPart
	if rootPart == nil then
		return nil
	end
	local subject = rootPart.Position + Vector3.new(0, SUBJECT_HEIGHT, 0)
	local flat = Vector3.new(lookToward.X - subject.X, 0, lookToward.Z - subject.Z)
	local direction = if flat.Magnitude > 1e-3 then flat.Unit else rootPart.CFrame.LookVector
	local pitch = math.rad(RETURN_PITCH)
	local position = subject - direction * math.cos(pitch) * RETURN_DISTANCE + Vector3.yAxis * math.sin(pitch) * RETURN_DISTANCE
	return CFrame.lookAt(position, subject)
end

-- Joue `update(alpha)` à chaque image pendant `duration` secondes (alpha adouci de 0 à 1). YIELD.
local function animateCamera(duration: number, update: (alpha: number) -> ())
	local startClock = os.clock()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, function()
		local progress = math.clamp((os.clock() - startClock) / duration, 0, 1)
		update(TweenService:GetValue(progress, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
	end)
	task.wait(duration)
end

--------------------------------------------------------------------------------
-- Cinématique
--------------------------------------------------------------------------------

-- Remet tout dans l'état de jeu normal (fin de cinématique, ou erreur en cours de route).
local function restore()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)

	local camera = workspace.CurrentCamera
	if camera and isPlaying then
		camera.FieldOfView = savedFieldOfView
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = getHumanoid()
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end

	setControlsEnabled(true)
	hideTitleNow()
	setBarsShown(false, 0)
	screen.gui.Enabled = false
	if Theme.getScreenOpacity() > 0 then
		Theme.screenFade(0, REOPEN_FADE)
	end

	isPlaying = false
	CreatorSession.setArrivalBusy(false)
end

-- Titre : apparition (en remontant doucement), tenue, disparition. YIELD.
local function playTitle(displayName: string, subtitle: string)
	regionLabel.Text = displayName
	subtitleLabel.Text = subtitle
	titleGroup.GroupTransparency = 1
	titleGroup.Position = TITLE_POSITION + UDim2.fromScale(0, TITLE_DRIFT)
	titleGroup.Visible = true

	Theme.tween(titleGroup, { GroupTransparency = 0 }, TITLE_FADE_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	Theme.tween(titleGroup, { Position = TITLE_POSITION }, TITLE_FADE_IN + TITLE_HOLD, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	task.wait(TITLE_FADE_IN + TITLE_HOLD)
	Theme.fade(titleGroup, false, TITLE_FADE_OUT)
	task.wait(TITLE_FADE_OUT)
end

-- Déroulé complet. YIELD (environ 9 s).
local function play(cameraCFrame: CFrame, focus: Vector3, regionName: string)
	-- 1. Le créateur doit avoir rendu caméra et écran (la cinématique peut arriver avant CreatorClosed).
	if CreatorSession.isActive() and not CreatorSession.waitUntilClosed(CREATOR_WAIT_TIMEOUT) then
		warn("[Arrival] Le créateur de personnage est toujours ouvert : cinématique d'arrivée ignorée")
		return
	end

	-- 2. Écran noir (déjà noir en sortie du créateur).
	if Theme.getScreenOpacity() < 0.99 then
		Theme.screenFade(1, BLACKOUT_FADE)
		task.wait(BLACKOUT_FADE)
	end

	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end

	-- 3. Premier plan, derrière le voile.
	setControlsEnabled(false)
	savedFieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CINEMATIC_FOV
	local startPosition, endPosition = buildTravel(cameraCFrame, focus)
	camera.CFrame = CFrame.lookAt(startPosition, focus)
	setBarsShown(true, 0) -- invisibles tant que l'écran est noir
	screen.gui.Enabled = true

	-- 4. Fondu d'ouverture, travelling et titre (le titre se joue pendant le travelling).
	Theme.screenFade(0, OPEN_FADE)
	local displayName, subtitle = describeRegion(regionName)
	task.delay(TITLE_DELAY, function()
		if isPlaying then
			playTitle(displayName, subtitle)
		end
	end)
	animateCamera(TRAVEL_DURATION, function(alpha: number)
		camera.CFrame = CFrame.lookAt(startPosition:Lerp(endPosition, alpha), focus)
	end)

	-- 5. Retour en douceur derrière le personnage, tourné vers le village.
	local fromCFrame = camera.CFrame
	setBarsShown(false, BARS_DURATION)
	animateCamera(RETURN_DURATION, function(alpha: number)
		local target = computeGameplayPose(focus)
		if target then
			camera.CFrame = fromCFrame:Lerp(target, alpha)
		end
		camera.FieldOfView = CINEMATIC_FOV + (savedFieldOfView - CINEMATIC_FOV) * alpha
	end)
end

-- Le serveur vient de poser le personnage debout au belvédère ; c'est ce client qui simule sa
-- physique : on efface toute vitesse héritée et on le relève s'il était couché ou assis.
local LYING_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Seated] = true,
}
local function settleCharacter()
	local humanoid = getHumanoid()
	local root = humanoid and humanoid.RootPart
	if humanoid == nil or root == nil then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.PlatformStand = false
	humanoid.Sit = false
	if LYING_STATES[humanoid:GetState()] then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function onArrivalCinematic(cameraCFrame: any, focus: any, regionName: any)
	if typeof(cameraCFrame) ~= "CFrame" or typeof(focus) ~= "Vector3" then
		warn("[Arrival] ArrivalCinematic reçu avec des paramètres invalides : ignoré")
		return
	end
	if isPlaying or os.clock() < lateUntil then
		return -- déjà en cours, ou trop tard : l'écran a été rouvert et le joueur joue
	end
	pendingCloseToken = nil -- la fermeture en attente est servie : pas de repli
	isPlaying = true
	settleCharacter()
	CreatorSession.setArrivalBusy(true)

	local name = if type(regionName) == "string" then regionName else ""
	local isDone, problem = pcall(function()
		play(cameraCFrame, focus, name)
	end)
	if not isDone then
		warn(`[Arrival] Cinématique d'arrivée interrompue : {problem}`)
	end
	restore()
end

--------------------------------------------------------------------------------
-- Repli : jamais d'écran noir bloqué
--------------------------------------------------------------------------------

local function onCreatorClosed()
	closeToken += 1
	local token = closeToken
	pendingCloseToken = token
	task.delay(FALLBACK_DELAY, function()
		if pendingCloseToken ~= token then
			return -- la cinématique est arrivée (ou une fermeture plus récente a pris le relais)
		end
		pendingCloseToken = nil
		if isPlaying then
			return
		end
		lateUntil = os.clock() + LATE_WINDOW
		CreatorSession.waitUntilClosed(2) -- le fondu de fermeture du créateur dure moins d'une seconde
		if not isPlaying and Theme.getScreenOpacity() > 0 then
			Theme.screenFade(0, REOPEN_FADE)
		end
	end)
end

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

AvatarRemotes.CreatorClosed.OnClientEvent:Connect(onCreatorClosed)

-- Requis à part : le repli ci-dessus fonctionne même si le serveur ne crée jamais SpawnRemotes.
task.spawn(function()
	local SpawnRemotes = require(sharedFolder:WaitForChild("World"):WaitForChild("SpawnRemotes"))
	SpawnRemotes.ArrivalCinematic.OnClientEvent:Connect(onArrivalCinematic)
end)
