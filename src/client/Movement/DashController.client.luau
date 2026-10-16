--!strict
--[[
	DashController (LocalScript)
	L'esquive du joueur :
		- touche Dash (KeyBindings : C, B à la manette, bouton tactile) : propulse le personnage dans
		  la direction où il marche (ou droit devant lui s'il est immobile), avec un cooldown ;
		- DOUBLE APPUI sur une touche de direction (ZQSD / WASD, flèches) en moins de
		  DASH_DOUBLE_TAP_WINDOW s : dash dans cette direction, relative à la caméra ;
		  (Maj, l'ancienne touche du dash, sert désormais au sprint : voir MovementController.)
		- la propulsion est une LinearVelocity temporaire sur le HumanoidRootPart, posée ici car
		  c'est le client qui simule la physique de son propre personnage ;
		- annonce le dash au serveur (cooldown vérifié, invulnérabilité accordée) ;
		- joue la traînée du dash, pour soi et pour les dashs des autres joueurs.

	Rien ne tourne en continu : tout part de l'appui sur la touche, dans onDashInput().
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Movement")
local Config = require(sharedFolder:WaitForChild("MovementConfig") :: ModuleScript)
local Remotes = require(sharedFolder:WaitForChild("MovementRemotes") :: ModuleScript)
local KeyBindings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)

local clientFolder = script.Parent.Parent
local TouchLayout = require(clientFolder:WaitForChild("Input"):WaitForChild("TouchLayout") :: ModuleScript)
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local MovementState = require(script.Parent:WaitForChild("MovementState") :: ModuleScript)

local DASH_ACTION = "Dash"

-- Assez de force pour atteindre DASH_SPEED en une frame, quel que soit le poids du personnage.
local DASH_MAX_FORCE = 1e6

-- Traînée : un large ruban vertical derrière le personnage, de la tête aux genoux.
local TRAIL_NAME = "DashTrail"
local TRAIL_TOP_OFFSET = 1.6 -- studs au-dessus du centre du RootPart
local TRAIL_BOTTOM_OFFSET = -1.8
local TRAIL_LIFETIME = 0.3
local TRAIL_COLOR_HEAD = Color3.fromRGB(215, 200, 255)
local TRAIL_COLOR_TAIL = Color3.fromRGB(70, 30, 140)

local localPlayer = Players.LocalPlayer
local lastDashClock = -math.huge
local lastTapKey: Enum.KeyCode? = nil
local lastTapClock = -math.huge

--------------------------------------------------------------------------------
-- Effet visuel (local à ce client)
--------------------------------------------------------------------------------

local function newTrailAttachment(name: string, offsetY: number, rootPart: BasePart): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = Vector3.new(0, offsetY, 0)
	attachment.Parent = rootPart
	return attachment
end

-- La traînée est créée au premier dash de chaque personnage, puis réutilisée.
local function getDashTrail(rootPart: BasePart): Trail
	local existingTrail = rootPart:FindFirstChild(TRAIL_NAME)
	if existingTrail and existingTrail:IsA("Trail") then
		return existingTrail
	end

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Enabled = false
	trail.Attachment0 = newTrailAttachment("DashTrailTop", TRAIL_TOP_OFFSET, rootPart)
	trail.Attachment1 = newTrailAttachment("DashTrailBottom", TRAIL_BOTTOM_OFFSET, rootPart)
	trail.Lifetime = TRAIL_LIFETIME
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(TRAIL_COLOR_HEAD, TRAIL_COLOR_TAIL)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = rootPart
	return trail
end

local function playDashTrail(character: Model)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local trail = getDashTrail(rootPart)
	trail.Enabled = true
	task.delay(Config.DASH_DURATION, function()
		trail.Enabled = false -- le sillage déjà tracé finit de s'estomper tout seul
	end)
end

--------------------------------------------------------------------------------
-- Dash
--------------------------------------------------------------------------------

-- Direction horizontale du dash : celle de la marche, ou le regard du personnage s'il est à l'arrêt.
local function getDashDirection(humanoid: Humanoid, rootPart: BasePart): Vector3
	local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	return direction.Unit
end

-- Propulse `rootPart` à vitesse constante pendant DASH_DURATION, puis rend la main au Humanoid.
local function propel(rootPart: BasePart, direction: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = rootPart

	-- Mode Plane : seule la vitesse horizontale est imposée, la gravité continue d'agir.
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Config.DASH_SPEED
	velocity.MaxForce = DASH_MAX_FORCE
	velocity.Parent = rootPart

	task.delay(Config.DASH_DURATION, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

-- Direction d'un double appui : la touche de direction, tournée comme la caméra (à plat).
local function directionFromKey(keyCode: Enum.KeyCode): Vector3?
	local localDirection = KeyBindings.DIRECTION_KEYS[keyCode]
	local camera = workspace.CurrentCamera
	if localDirection == nil or camera == nil then
		return nil
	end
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		return nil
	end
	forward = forward.Unit
	local right = forward:Cross(Vector3.yAxis)
	return (right * localDirection.X - forward * localDirection.Z).Unit
end

-- Seul point d'entrée du dash. `forcedDirection` : dash au double appui.
local function onDashInput(forcedDirection: Vector3?)
	local now = os.clock()
	if now - lastDashClock < Config.DASH_COOLDOWN then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if character == nil or humanoid == nil or rootPart == nil then
		return
	end
	-- Un RootPart ancré = joueur figé par le serveur (création d'avatar, anomalie, rewind).
	if humanoid.Health <= 0 or rootPart.Anchored then
		return
	end

	if MovementState.concentrating then
		return -- la Concentration immobilise presque : pas d'esquive pendant la posture
	end

	lastDashClock = now
	local direction = forcedDirection or getDashDirection(humanoid, rootPart)
	Remotes.RequestDash:FireServer(direction)
	propel(rootPart, direction)
	playDashTrail(character)
	CharacterAnimator.get(character, true):play("dash")
	SfxPlayer.play("dodge", rootPart)
end

--------------------------------------------------------------------------------
-- Entrées et événements
--------------------------------------------------------------------------------

local dashBinding = KeyBindings.BINDINGS.Dash
ContextActionService:BindAction(DASH_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		onDashInput(nil)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, dashBinding.touch ~= nil, dashBinding.keyCode or dashBinding.fallbackKeyCode, dashBinding.gamepad or Enum.KeyCode.ButtonB)
ContextActionService:SetTitle(DASH_ACTION, dashBinding.label)
TouchLayout.place(DASH_ACTION, "Dash")

-- Double appui sur une même touche de direction.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or KeyBindings.DIRECTION_KEYS[input.KeyCode] == nil then
		return
	end
	local now = os.clock()
	if lastTapKey == input.KeyCode and now - lastTapClock <= Config.DASH_DOUBLE_TAP_WINDOW then
		lastTapKey = nil
		local direction = directionFromKey(input.KeyCode)
		if direction then
			onDashInput(direction)
		end
		return
	end
	lastTapKey = input.KeyCode
	lastTapClock = now
end)

-- Un AUTRE joueur dashe : son déplacement est déjà répliqué, il ne manque que sa traînée.
Remotes.DashStarted.OnClientEvent:Connect(function(character: Model?)
	if character then
		playDashTrail(character)
	end
end)
