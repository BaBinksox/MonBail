--!strict
--[[
	MovementController (LocalScript)
	Mobilité du personnage local :
		- SPRINT : Maj maintenu (clavier), L3 en bascule (manette), bouton en bascule (tactile). La
		  vitesse monte progressivement de la course au sprint (MovementModel), redescend vite au
		  relâchement. La vitesse de base vient du SERVEUR (attribut MoveSpeedBase : peuple et
		  altérations compris) ; ce script ne fait que la multiplier par la montée en sprint, et
		  seulement si le serveur a accepté le sprint (attribut Sprinting). Champ de vision élargi
		  et quelques traits de vitesse à pleine allure ;
		- DOUBLE SAUT : un second appui sur Saut en l'air donne une impulsion vers le haut, une seule
		  fois par passage en l'air (remise à zéro uniquement au retour au sol). Le serveur le vérifie ;
		- ATTERRISSAGE : petite flexion après une vraie chute.
	MovementState est mis à jour à chaque image pour les autres scripts (poses, interface).
	Une seule connexion par image (Heartbeat), pour ce seul personnage.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local Config = require(sharedFolder:WaitForChild("Movement"):WaitForChild("MovementConfig") :: ModuleScript)
local MovementModel = require(sharedFolder:WaitForChild("Movement"):WaitForChild("MovementModel") :: ModuleScript)
local Remotes = require(sharedFolder:WaitForChild("Movement"):WaitForChild("MovementRemotes") :: ModuleScript)

local clientFolder = script.Parent.Parent
local TouchLayout = require(clientFolder:WaitForChild("Input"):WaitForChild("TouchLayout") :: ModuleScript)
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)
local MovementEffects = require(script.Parent:WaitForChild("MovementEffects") :: ModuleScript)
local MovementState = require(script.Parent:WaitForChild("MovementState") :: ModuleScript)

local SPRINT_ACTION = "Sprint"
local JUMP_HELD_INTERVAL = 0.15 -- JumpRequest répété plus vite que ça = bouton maintenu, pas un nouvel appui
local LAND_MIN_AIR_TIME = 0.35 -- s en l'air avant de jouer la flexion d'atterrissage
local SPRINT_GRACE = 0.35 -- s pendant lesquels le sprint est joué en attendant la réponse du serveur
local DOUBLE_JUMP_FOV_PUNCH = 3

local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
}
local GROUND_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

local localPlayer = Players.LocalPlayer
local wantsSprint = false
local sprintRequestedAt = -math.huge
local airTime = 0
local lastJumpRequestClock = -math.huge
local fovBase: number? = nil -- FOV d'origine tant que ce script ajoute un bonus
local fovBonus = 0
local fovPunch = 0
local stateConnection: RBXScriptConnection? = nil

local function getParts(): (Humanoid?, BasePart?)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function setWantsSprint(wants: boolean)
	if wantsSprint == wants then
		return
	end
	wantsSprint = wants
	MovementState.wantsSprint = wants
	if wants then
		sprintRequestedAt = os.clock()
	end
	Remotes.RequestSprint:FireServer(wants)
end

-- Le sprint compte s'il est voulu ET accepté par le serveur (ou tout juste demandé).
local function isSprintGranted(): boolean
	if not wantsSprint or MovementState.concentrating then
		return false
	end
	return localPlayer:GetAttribute(Config.SPRINT_ATTRIBUTE) == true or os.clock() - sprintRequestedAt < SPRINT_GRACE
end

--------------------------------------------------------------------------------
-- Champ de vision (seulement quand la caméra est celle du jeu)
--------------------------------------------------------------------------------

local function releaseFieldOfView(camera: Camera?)
	local base = fovBase
	if camera and base then
		camera.FieldOfView = base
	end
	fovBase = nil
	fovBonus = 0
	fovPunch = 0
end

local function updateFieldOfView(dt: number, sprintAmount: number)
	local camera = workspace.CurrentCamera
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom or localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true then
		if fovBase then
			releaseFieldOfView(camera) -- une cinématique prend la caméra : on rend le FOV d'origine
		end
		return
	end
	local target = Config.SPRINT_FOV_BONUS * sprintAmount
	fovBonus += (target - fovBonus) * math.min(1, dt * Config.SPRINT_FOV_SMOOTHING)
	fovPunch = math.max(0, fovPunch - dt * DOUBLE_JUMP_FOV_PUNCH * 4)
	local extra = fovBonus + fovPunch
	if extra < 0.05 and fovBase then
		releaseFieldOfView(camera)
		return
	end
	if extra >= 0.05 then
		if fovBase == nil then
			fovBase = camera.FieldOfView
		end
		camera.FieldOfView = (fovBase :: number) + extra
	end
end

--------------------------------------------------------------------------------
-- Double saut et atterrissage
--------------------------------------------------------------------------------

local function onStateChanged(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	if AIR_STATES[new] then
		if not MovementState.airborne then
			MovementState.airborne = true
			airTime = 0
		end
	elseif GROUND_STATES[new] then
		local wasAirborne = MovementState.airborne
		local fallTime = airTime
		MovementState.airborne = false
		MovementState.jumpsUsed = 0 -- seul un vrai retour au sol rend le double saut
		airTime = 0
		local character = localPlayer.Character
		if wasAirborne and fallTime >= LAND_MIN_AIR_TIME and character then
			CharacterAnimator.get(character, true):play("land")
		end
	end
end

local function tryDoubleJump()
	local humanoid, root = getParts()
	local character = localPlayer.Character
	if humanoid == nil or root == nil or character == nil or root.Anchored or humanoid.JumpHeight <= 0 then
		return
	end
	if MovementState.concentrating then
		return
	end
	if not MovementModel.canDoubleJump({ isAirborne = MovementState.airborne, airTime = airTime, jumpsUsed = MovementState.jumpsUsed }) then
		return
	end
	MovementState.jumpsUsed += 1
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, Config.DOUBLE_JUMP_VELOCITY, velocity.Z)
	Remotes.RequestDoubleJump:FireServer()
	CharacterAnimator.get(character, true):play("double_jump")
	MovementEffects.doubleJump(character)
	SfxPlayer.play("doubleJump", root)
	if not ClientSettings.isReducedEffects() then
		fovPunch = DOUBLE_JUMP_FOV_PUNCH
	end
end

UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	local isNewPress = now - lastJumpRequestClock > JUMP_HELD_INTERVAL
	lastJumpRequestClock = now
	if isNewPress and MovementState.airborne then
		tryDoubleJump()
	end
end)

--------------------------------------------------------------------------------
-- Boucle
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt: number)
	local humanoid, root = getParts()
	if humanoid == nil or root == nil then
		MovementState.sprintRamp = 0
		MovementEffects.setSpeedStreaks(0)
		return
	end
	if MovementState.airborne then
		airTime += dt
	end
	local isMoving = humanoid.MoveDirection.Magnitude > Config.SPRINT_MIN_MOVE
	local granted = isSprintGranted() and not root.Anchored
	-- En l'air, l'élan est conservé tel quel (ni gagné ni perdu) tant que le sprint est tenu.
	local previous = MovementState.sprintRamp
	local ramp = if MovementState.airborne and granted then previous else MovementModel.stepSprint(previous, dt, granted, isMoving)
	if previous < 0.05 and ramp >= 0.05 then
		SfxPlayer.play("sprintStart", root)
	end
	MovementState.sprintRamp = ramp

	local base = humanoid:GetAttribute(Config.MOVE_SPEED_ATTRIBUTE)
	local baseSpeed = if type(base) == "number" then base else humanoid.WalkSpeed
	local target = baseSpeed * MovementModel.sprintFactor(ramp)
	if math.abs(humanoid.WalkSpeed - target) > 0.01 then
		humanoid.WalkSpeed = target
	end

	local velocity = root.AssemblyLinearVelocity
	MovementState.verticalSpeed = velocity.Y
	MovementState.speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	updateFieldOfView(dt, ramp)
	MovementEffects.setSpeedStreaks(if ramp > 0.85 and isMoving then (ramp - 0.85) / 0.15 else 0)
end)

--------------------------------------------------------------------------------
-- Entrées
--------------------------------------------------------------------------------

local sprintBinding = KeyBindings.BINDINGS.Sprint
ContextActionService:BindAction(SPRINT_ACTION, function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local isToggle = input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == sprintBinding.gamepad
	if isToggle then
		if state == Enum.UserInputState.Begin then
			setWantsSprint(not wantsSprint)
		end
	elseif state == Enum.UserInputState.Begin then
		setWantsSprint(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setWantsSprint(false)
	end
	return Enum.ContextActionResult.Pass -- Maj reste lisible par les autres scripts
end, sprintBinding.touch ~= nil, sprintBinding.keyCode or sprintBinding.fallbackKeyCode, sprintBinding.gamepad or Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle(SPRINT_ACTION, sprintBinding.label)
TouchLayout.place(SPRINT_ACTION, "Sprint")

-- Fenêtre perdue (Alt-Tab avec Maj enfoncée) ou dialogue (qui capte Maj) : on relâche le sprint.
UserInputService.WindowFocusReleased:Connect(function()
	setWantsSprint(false)
end)
UIBus.DialogueStateChanged:Connect(function(isOpen: boolean)
	if isOpen then
		setWantsSprint(false)
	end
end)

--------------------------------------------------------------------------------
-- Personnage
--------------------------------------------------------------------------------

local function onCharacter(character: Model)
	MovementState.airborne = false
	MovementState.jumpsUsed = 0
	MovementState.sprintRamp = 0
	airTime = 0
	releaseFieldOfView(workspace.CurrentCamera)
	if wantsSprint then
		Remotes.RequestSprint:FireServer(true) -- le serveur a remis Sprinting à faux au respawn
		sprintRequestedAt = os.clock()
	end
	local previous = stateConnection
	if previous then
		previous:Disconnect()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		stateConnection = humanoid.StateChanged:Connect(onStateChanged)
	end
end

localPlayer.CharacterAdded:Connect(onCharacter)
if localPlayer.Character then
	task.spawn(onCharacter, localPlayer.Character)
end

-- Double saut des AUTRES joueurs : leur cercle magique (la pose est jouée par l'AnimationDirector).
Remotes.DoubleJumped.OnClientEvent:Connect(function(character: Model?)
	if character and character ~= localPlayer.Character then
		MovementEffects.doubleJump(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			SfxPlayer.play("doubleJump", root)
		end
	end
end)
