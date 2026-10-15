--!strict
--[[
	AvatarCreatorCamera
	Caméra scriptable du créateur de personnage, et l'éclairage de studio qui l'accompagne.

	Le personnage est cadré dans une FENÊTRE de l'écran : la zone que l'interface laisse libre,
	mesurée par AvatarCreatorView (entre le rail et le panneau sur un écran large, entre le rail et la
	feuille d'options sur un téléphone en portrait). La caméra calcule la distance et le décalage qui
	placent le sujet au centre de cette fenêtre, quel que soit le format de l'écran : rien ne
	recouvre jamais le personnage.

	Plans (setShot) :
		"body"    plein pied (corps, tenue, proportions)
		"face"    gros plan du visage (visage, marques, chevelure)
		"destiny" contre-plongée de trois quarts, contre-jour aux couleurs de la magie (setAccent)
		"summary" plein pied, léger trois quarts
	Le joueur fait tourner la vue autour du personnage (drag, setOrbitInput, rotateBy), la penche un
	peu et zoome, dans des bornes. Toutes les transitions sont amorties : aucune coupure sèche.

	Base de cadrage :
		- si le serveur a fourni la caméra de la scène (SpawnRemotes.CreatorStageReady, cameraCFrame),
		  l'orbite part du côté de cette caméra et le travelling d'ouverture part de ce plan exact ;
		- sinon, comme avant : face au personnage (son LookVector), travelling avant depuis plus loin.

	Recalculée à chaque image à partir du personnage : elle suit les changements de taille
	(proportions) et un éventuel nouveau personnage (réapparition).
	Éclairage : trois lumières locales (clé chaude, débouchage froid, contre-jour) qui tournent avec la
	vue, et une profondeur de champ qui suit la distance. start() crée tout, stop() détruit tout et
	rend la caméra au joueur.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

export type Shot = "body" | "face" | "destiny" | "summary"

-- Rectangle normalisé de l'écran (0..1), origine en haut à gauche.
export type Window = {
	x: number,
	y: number,
	width: number,
	height: number,
}

type ShotSpec = {
	subject: "body" | "head",
	fill: number, -- part de la fenêtre (en hauteur) occupée par le sujet
	pitch: number, -- degrés : négatif = la caméra plonge, positif = contre-plongée
	yawOffset: number, -- degrés ajoutés à l'orbite du joueur
}

local SHOTS: { [Shot]: ShotSpec } = {
	body = { subject = "body", fill = 0.86, pitch = -5, yawOffset = 0 },
	face = { subject = "head", fill = 0.82, pitch = -3, yawOffset = 0 },
	destiny = { subject = "body", fill = 0.9, pitch = 7, yawOffset = 20 },
	summary = { subject = "body", fill = 0.84, pitch = -4, yawOffset = -14 },
}

local RENDER_STEP_NAME = "AvatarCreatorCamera"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local FIELD_OF_VIEW = 40
local INTRO_ZOOM = 1.9 -- départ du travelling (sans caméra de scène) : multiple de la distance finale
local MIN_ZOOM = 0.75
local MAX_ZOOM = 1.35
local MAX_PITCH_OFFSET = 14 -- degrés que le joueur peut ajouter ou retirer à l'inclinaison du plan
local DRAG_YAW_PER_PIXEL = 0.35 -- degrés par pixel glissé horizontalement
local DRAG_PITCH_PER_PIXEL = 0.12
local ORBIT_YAW_SPEED = 140 -- degrés par seconde, joystick à fond
local ORBIT_PITCH_SPEED = 40
local FRAMING_SHARPNESS = 5 -- amortissement des changements de plan (plus grand = plus vif)
local ORBIT_SHARPNESS = 12 -- amortissement de la rotation
local SNAP_DISTANCE = 30 -- studs : au-delà (réapparition ailleurs), on recadre sans glisser
local SWAY_AMPLITUDE = 0.01 -- "respiration" verticale, en fraction de la distance
local SWAY_SPEED = 0.6
local HAIR_ALLOWANCE = 0.35 -- studs gardés au-dessus de la tête (cheveux)
local MIN_WINDOW_SIZE = 0.1

local DEFAULT_WINDOW: Window = { x = 0.2, y = 0.05, width = 0.45, height = 0.85 }

-- Éclairage de studio (lumières locales : seul ce client les voit).
local KEY_COLOR = Color3.fromRGB(255, 228, 196)
local FILL_COLOR = Color3.fromRGB(160, 182, 230)
local RIM_COLOR = Color3.fromRGB(140, 186, 255)
local KEY_BRIGHTNESS = 1.4
local FILL_BRIGHTNESS = 0.45
local RIM_BRIGHTNESS = 2
local RIM_ACCENT_BRIGHTNESS = 3.2
local LIGHT_RANGE = 14
local ACCENT_FADE = 0.6

local localPlayer = Players.LocalPlayer

local AvatarCreatorCamera = {}

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

type Framing = {
	center: Vector3,
	height: number,
	width: number,
	pitch: number,
	fill: number,
	window: Window,
}

type Subject = {
	center: Vector3,
	height: number,
	width: number,
}

type LightRig = {
	folder: Folder,
	keyPart: Part,
	fillPart: Part,
	rimPart: Part,
	rim: PointLight,
}

local isRunning = false
local savedFieldOfView = 70
local shot: Shot = "body"
local window: Window = DEFAULT_WINDOW
local stageCameraCFrame: CFrame? = nil

local targetYaw = 0 -- orbite voulue par le joueur (degrés)
local currentYaw = 0 -- orbite affichée, yawOffset du plan compris
local targetPitchOffset = 0
local targetZoom = 1
local currentZoom = 1
local orbitInput = Vector2.zero
local current: Framing? = nil
local currentBase: Vector3? = nil -- direction de base affichée (amortie si la caméra de scène arrive en cours)

local isIntroHolding = false -- avant dollyIn : la caméra attend sur le plan de départ
local dollyStartClock: number? = nil
local dollyDuration = 1

local lights: LightRig? = nil
local depthOfField: DepthOfFieldEffect? = nil
local rimTween: Tween? = nil

--------------------------------------------------------------------------------
-- Mesure du personnage
--------------------------------------------------------------------------------

local function getRootPart(): BasePart?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.RootPart
end

-- Ce qu'il faut cadrer pour ce plan : centre, hauteur et largeur (studs).
local function measureSubject(kind: "body" | "head"): Subject?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if character == nil or humanoid == nil or rootPart == nil then
		return nil
	end

	local rootPosition = rootPart.Position
	local head = character:FindFirstChild("Head")
	local headPosition = rootPosition + Vector3.new(0, 2.2, 0)
	local headHeight = 1
	if head and head:IsA("BasePart") then
		headPosition = head.Position
		headHeight = head.Size.Y
	end

	if kind == "head" then
		-- La tête, la chevelure et le haut des épaules.
		local faceHeight = math.max(headHeight, 1) * 2.3
		return {
			center = headPosition + Vector3.new(0, headHeight * 0.1, 0),
			height = faceHeight,
			width = faceHeight * 0.9,
		}
	end

	local feetY = rootPosition.Y - rootPart.Size.Y / 2 - humanoid.HipHeight
	local topY = headPosition.Y + headHeight / 2 + HAIR_ALLOWANCE
	local height = math.max(topY - feetY, 2)
	return {
		center = Vector3.new(rootPosition.X, (topY + feetY) / 2, rootPosition.Z),
		height = height * 1.04,
		width = math.max(height * 0.55, 2.5),
	}
end

-- Direction horizontale du personnage vers la caméra, orbite nulle.
local function getBaseDirection(rootPart: BasePart): Vector3
	local stageCamera = stageCameraCFrame
	local direction = if stageCamera then stageCamera.Position - rootPart.Position else rootPart.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return direction.Unit
end

-- Rapproche la direction de base affichée de la direction voulue. Recalage immédiat au premier
-- calcul, après une réapparition lointaine ou pour un demi-tour (le mélange passerait par zéro).
local function smoothBaseDirection(target: Vector3, deltaTime: number, snap: boolean): Vector3
	local previous = currentBase
	if snap or previous == nil or (previous + target).Magnitude < 0.2 then
		currentBase = target
		return target
	end
	local alpha = 1 - math.exp(-FRAMING_SHARPNESS * deltaTime)
	local blended = previous:Lerp(target, alpha)
	local result = if blended.Magnitude > 1e-3 then blended.Unit else target
	currentBase = result
	return result
end

--------------------------------------------------------------------------------
-- Cadrage
--------------------------------------------------------------------------------

-- Place la caméra pour que le sujet (centre, hauteur, largeur) remplisse `fill` de la fenêtre
-- `frameWindow`, centré dedans. Retourne la CFrame et la distance au sujet.
local function computeCameraCFrame(
	framing: Framing,
	toCamera: Vector3,
	zoomFactor: number,
	aspect: number
): (CFrame, number)
	local frameWindow = framing.window
	local windowWidth = math.max(frameWindow.width, MIN_WINDOW_SIZE)
	local windowHeight = math.max(frameWindow.height, MIN_WINDOW_SIZE)

	local forward = -toCamera
	local right = forward:Cross(Vector3.yAxis).Unit
	forward = CFrame.fromAxisAngle(right, math.rad(framing.pitch)):VectorToWorldSpace(forward)
	local up = right:Cross(forward)

	-- Distance qui fait tenir le sujet en hauteur ET en largeur dans la fenêtre.
	local tanHalf = math.tan(math.rad(FIELD_OF_VIEW / 2))
	local distanceForHeight = framing.height / (2 * tanHalf * windowHeight * framing.fill)
	local distanceForWidth = framing.width / (2 * tanHalf * aspect * windowWidth * framing.fill)
	local distance = math.max(distanceForHeight, distanceForWidth) * zoomFactor

	-- Décalage qui amène le sujet au centre de la fenêtre plutôt qu'au centre de l'écran.
	local halfHeight = distance * tanHalf
	local halfWidth = halfHeight * aspect
	local offsetRight = (frameWindow.x + windowWidth / 2 - 0.5) * 2 * halfWidth
	local offsetUp = (0.5 - (frameWindow.y + windowHeight / 2)) * 2 * halfHeight

	local position = framing.center - forward * distance - right * offsetRight - up * offsetUp
	return CFrame.fromMatrix(position, right, up, -forward), distance
end

local function lerpNumber(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

local function lerpWindow(from: Window, to: Window, alpha: number): Window
	return {
		x = lerpNumber(from.x, to.x, alpha),
		y = lerpNumber(from.y, to.y, alpha),
		width = lerpNumber(from.width, to.width, alpha),
		height = lerpNumber(from.height, to.height, alpha),
	}
end

-- Rapproche le cadrage affiché du cadrage voulu (amorti exponentiel, indépendant des FPS).
local function smoothFraming(target: Framing, deltaTime: number): Framing
	local previous = current
	if previous == nil or (previous.center - target.center).Magnitude > SNAP_DISTANCE then
		return target
	end
	local alpha = 1 - math.exp(-FRAMING_SHARPNESS * deltaTime)
	return {
		center = previous.center:Lerp(target.center, alpha),
		height = lerpNumber(previous.height, target.height, alpha),
		width = lerpNumber(previous.width, target.width, alpha),
		pitch = lerpNumber(previous.pitch, target.pitch, alpha),
		fill = lerpNumber(previous.fill, target.fill, alpha),
		window = lerpWindow(previous.window, target.window, alpha),
	}
end

--------------------------------------------------------------------------------
-- Éclairage de studio
--------------------------------------------------------------------------------

local function newLightPart(name: string, color: Color3, brightness: number, parent: Instance): (Part, PointLight)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = LIGHT_RANGE
	light.Shadows = false
	light.Parent = part

	part.Parent = parent
	return part, light
end

local function createLights(): LightRig
	-- Créées par un LocalScript : ces pièces n'existent que chez ce joueur.
	local folder = Instance.new("Folder")
	folder.Name = "AvatarCreatorStudioLights"
	local keyPart = newLightPart("KeyLight", KEY_COLOR, KEY_BRIGHTNESS, folder)
	local fillPart = newLightPart("FillLight", FILL_COLOR, FILL_BRIGHTNESS, folder)
	local rimPart, rim = newLightPart("RimLight", RIM_COLOR, RIM_BRIGHTNESS, folder)
	folder.Parent = workspace
	return { folder = folder, keyPart = keyPart, fillPart = fillPart, rimPart = rimPart, rim = rim }
end

-- Les lumières tournent avec la vue : la clé reste devant à gauche, le contre-jour derrière.
local function placeLights(rig: LightRig, center: Vector3, toCamera: Vector3, height: number)
	local right = (-toCamera):Cross(Vector3.yAxis).Unit
	local spread = math.max(height, 2)
	rig.keyPart.CFrame = CFrame.new(center + toCamera * spread * 0.8 - right * spread * 0.6 + Vector3.yAxis * spread * 0.45)
	rig.fillPart.CFrame = CFrame.new(center + toCamera * spread * 0.8 + right * spread * 0.7)
	rig.rimPart.CFrame = CFrame.new(center - toCamera * spread * 0.6 + Vector3.yAxis * spread * 0.5)
end

--------------------------------------------------------------------------------
-- Boucle
--------------------------------------------------------------------------------

local lastUpdateClock = os.clock()

local function update()
	local now = os.clock()
	local deltaTime = math.clamp(now - lastUpdateClock, 0, 0.1)
	lastUpdateClock = now

	local camera = workspace.CurrentCamera
	local rootPart = getRootPart()
	local spec = SHOTS[shot]
	local subject = measureSubject(spec.subject)
	if camera == nil or rootPart == nil or subject == nil then
		return
	end

	-- Les scripts caméra par défaut peuvent reprendre la main (au respawn par exemple).
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = FIELD_OF_VIEW

	-- Commandes continues (joystick droit).
	if orbitInput.Magnitude > 0 then
		targetYaw += orbitInput.X * ORBIT_YAW_SPEED * deltaTime
		targetPitchOffset = math.clamp(
			targetPitchOffset - orbitInput.Y * ORBIT_PITCH_SPEED * deltaTime,
			-MAX_PITCH_OFFSET,
			MAX_PITCH_OFFSET
		)
	end

	local orbitAlpha = 1 - math.exp(-ORBIT_SHARPNESS * deltaTime)
	currentYaw = lerpNumber(currentYaw, targetYaw + spec.yawOffset, orbitAlpha)
	currentZoom = lerpNumber(currentZoom, targetZoom, orbitAlpha)

	local previousFraming = current
	local isSnapping = previousFraming == nil or (previousFraming.center - subject.center).Magnitude > SNAP_DISTANCE
	local baseDirection = smoothBaseDirection(getBaseDirection(rootPart), deltaTime, isSnapping)

	local framing = smoothFraming({
		center = subject.center,
		height = subject.height,
		width = subject.width,
		pitch = spec.pitch + targetPitchOffset,
		fill = spec.fill,
		window = window,
	}, deltaTime)
	current = framing

	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local toCamera = CFrame.Angles(0, math.rad(currentYaw), 0):VectorToWorldSpace(baseDirection)

	-- Travelling d'ouverture : depuis le plan de la scène, ou depuis plus loin.
	local zoomFactor = currentZoom
	local introProgress: number? = nil
	local dollyStart = dollyStartClock
	if isIntroHolding then
		introProgress = 0
	elseif dollyStart then
		local progress = math.clamp((now - dollyStart) / dollyDuration, 0, 1)
		introProgress = TweenService:GetValue(progress, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		if progress >= 1 then
			dollyStartClock = nil
		end
	end
	local stageCamera = stageCameraCFrame
	if introProgress and stageCamera == nil then
		zoomFactor *= lerpNumber(INTRO_ZOOM, 1, introProgress)
	end

	local cameraCFrame, distance = computeCameraCFrame(framing, toCamera, zoomFactor, aspect)
	local sway = math.sin(now * SWAY_SPEED) * SWAY_AMPLITUDE * distance
	cameraCFrame += Vector3.new(0, sway, 0)
	if introProgress and stageCamera then
		cameraCFrame = stageCamera:Lerp(cameraCFrame, introProgress)
	end
	camera.CFrame = cameraCFrame

	local effect = depthOfField
	if effect then
		effect.FocusDistance = (cameraCFrame.Position - framing.center).Magnitude
		effect.InFocusRadius = math.clamp(framing.height * 0.8, 2, 8)
	end
	local rig = lights
	if rig then
		placeLights(rig, framing.center, toCamera, framing.height)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Verrouille la caméra sur le personnage, au plan de départ du travelling (voir dollyIn).
function AvatarCreatorCamera.start()
	if isRunning then
		return
	end
	isRunning = true

	targetYaw = 0
	currentYaw = SHOTS[shot].yawOffset
	targetPitchOffset = 0
	targetZoom = 1
	currentZoom = 1
	orbitInput = Vector2.zero
	current = nil
	currentBase = nil
	isIntroHolding = true
	dollyStartClock = nil
	lastUpdateClock = os.clock()

	local camera = workspace.CurrentCamera
	if camera then
		savedFieldOfView = camera.FieldOfView
	end

	lights = createLights()
	local effect = Instance.new("DepthOfFieldEffect")
	effect.Name = "AvatarCreatorDepthOfField"
	effect.FocusDistance = 10
	effect.InFocusRadius = 5
	effect.FarIntensity = 0.75
	effect.NearIntensity = 0
	effect.Parent = Lighting
	depthOfField = effect

	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, update)
end

-- Lance le travelling d'ouverture (vers le cadrage du plan courant) sur `duration` secondes.
function AvatarCreatorCamera.dollyIn(duration: number)
	isIntroHolding = false
	dollyStartClock = os.clock()
	dollyDuration = math.max(duration, 0.01)
end

-- Rend la caméra au joueur et détruit l'éclairage de studio.
function AvatarCreatorCamera.stop()
	if not isRunning then
		return
	end
	isRunning = false
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)

	local tween = rimTween
	if tween then
		tween:Cancel()
	end
	rimTween = nil
	local rig = lights
	if rig then
		rig.folder:Destroy()
	end
	lights = nil
	local effect = depthOfField
	if effect then
		effect:Destroy()
	end
	depthOfField = nil

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = savedFieldOfView
		camera.CameraType = Enum.CameraType.Custom
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function AvatarCreatorCamera.isRunning(): boolean
	return isRunning
end

-- Caméra de la scène fournie par le serveur (CreatorStageReady), ou nil : cadrage face au personnage.
function AvatarCreatorCamera.setStage(cameraCFrame: CFrame?)
	stageCameraCFrame = cameraCFrame
end

-- Plan demandé par l'étape courante (transition amortie).
function AvatarCreatorCamera.setShot(newShot: Shot)
	shot = newShot
end

-- Zone libre de l'écran où cadrer le personnage (rectangle normalisé).
function AvatarCreatorCamera.setWindow(newWindow: Window)
	window = {
		x = math.clamp(newWindow.x, 0, 1),
		y = math.clamp(newWindow.y, 0, 1),
		width = math.clamp(newWindow.width, MIN_WINDOW_SIZE, 1),
		height = math.clamp(newWindow.height, MIN_WINDOW_SIZE, 1),
	}
end

-- Glisser à la souris ou au doigt, en pixels d'écran.
function AvatarCreatorCamera.drag(delta: Vector2)
	targetYaw -= delta.X * DRAG_YAW_PER_PIXEL
	targetPitchOffset = math.clamp(targetPitchOffset + delta.Y * DRAG_PITCH_PER_PIXEL, -MAX_PITCH_OFFSET, MAX_PITCH_OFFSET)
end

-- Joystick droit, composantes -1..1 (Vector2.zero pour arrêter).
function AvatarCreatorCamera.setOrbitInput(input: Vector2)
	orbitInput = input
end

-- Rotation d'un cran (boutons ⟲ ⟳), en degrés.
function AvatarCreatorCamera.rotateBy(degrees: number)
	targetYaw += degrees
end

-- Zoom : valeur positive = plus près.
function AvatarCreatorCamera.zoomBy(amount: number)
	targetZoom = math.clamp(targetZoom - amount, MIN_ZOOM, MAX_ZOOM)
end

-- Revient à la vue de face, sans zoom ni inclinaison.
function AvatarCreatorCamera.resetView()
	targetYaw = math.round(targetYaw / 360) * 360 -- le tour le plus proche : pas de tour complet inutile
	targetPitchOffset = 0
	targetZoom = 1
end

-- Couleur du contre-jour (palette d'une magie au Destin), ou nil pour la lumière froide par défaut.
function AvatarCreatorCamera.setAccent(color: Color3?)
	local rig = lights
	if rig == nil then
		return
	end
	local previous = rimTween
	if previous then
		previous:Cancel()
	end
	rimTween = TweenService:Create(rig.rim, TweenInfo.new(ACCENT_FADE, Enum.EasingStyle.Sine), {
		Color = color or RIM_COLOR,
		Brightness = if color then RIM_ACCENT_BRIGHTNESS else RIM_BRIGHTNESS,
	})
	local tween = rimTween :: Tween
	tween:Play()
end

return AvatarCreatorCamera
