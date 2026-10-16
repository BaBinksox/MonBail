--!strict
--[[
	AnimationDirector (LocalScript)
	Fait vivre les poses de TOUS les personnages proches, chez ce client :
		- personnage local : locomotion lue dans MovementState (sprint, saut, chute) ; ses actions
		  (coups, sorts, dash...) sont lancées directement par les contrôleurs qui les déclenchent ;
		- autres joueurs : leurs actions arrivent par les événements du serveur (coup d'épée lancé,
		  dash, double saut, sort, parade) et leur locomotion se déduit de leur vitesse et de
		  l'attribut Sprinting posé par le serveur ;
		- ennemis et joueurs touchés : sursaut à chaque impact validé (HitConfirmed).
	Les poses procédurales ne sont pas répliquées par Roblox : chaque client les calcule, à partir des
	mêmes événements, ce qui donne la même chose chez tout le monde.
	Coût : une boucle par image sur les seuls personnages animés à moins de REMOTE_POSE_RADIUS studs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(sharedFolder:WaitForChild("Animation"):WaitForChild("AnimationConfig") :: ModuleScript)
local CombatRemotes = require(sharedFolder:WaitForChild("Combat"):WaitForChild("CombatRemotes") :: ModuleScript)
local MovementConfig = require(sharedFolder:WaitForChild("Movement"):WaitForChild("MovementConfig") :: ModuleScript)
local MovementRemotes = require(sharedFolder:WaitForChild("Movement"):WaitForChild("MovementRemotes") :: ModuleScript)
local ParryConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ParryConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local CharacterAnimator = require(script.Parent:WaitForChild("CharacterAnimator") :: ModuleScript)
local MovementState = require(clientFolder:WaitForChild("Movement"):WaitForChild("MovementState") :: ModuleScript)

local AIRBORNE_SPEED = 3 -- studs/s verticaux : au-delà, un personnage distant est « en l'air »
local CONCENTRATING_ATTRIBUTE = "Concentrating"
local CHARGING_ATTRIBUTE = "Charging" -- = CombatConfig.CHARGING_ATTRIBUTE
local PLUNGE_REMOTE_TIMEOUT = 1.5 -- s : au-delà, la plongée d'un autre joueur est considérée finie

local localPlayer = Players.LocalPlayer

local function isNearCamera(character: Model): boolean
	local camera = workspace.CurrentCamera
	local root = character:FindFirstChild("HumanoidRootPart")
	if camera == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - camera.CFrame.Position).Magnitude <= AnimationConfig.REMOTE_POSE_RADIUS
end

local function animatorFor(character: Model?): any
	if character == nil or character.Parent == nil then
		return nil
	end
	return CharacterAnimator.get(character, character == localPlayer.Character)
end

-- Joue `actionName` sur un personnage d'un AUTRE joueur (le local joue déjà les siennes).
local function playRemote(character: Model?, actionName: string, options: any?)
	if character == nil or character == localPlayer.Character or not isNearCamera(character) then
		return
	end
	local animator = animatorFor(character)
	if animator then
		animator:play(actionName, options)
	end
end

--------------------------------------------------------------------------------
-- Boucle par image
--------------------------------------------------------------------------------

local function updateLocomotion()
	local character = localPlayer.Character
	if character then
		local animator = animatorFor(character)
		if animator then
			animator:setLocomotion(MovementState.sprintRamp, MovementState.airborne, MovementState.verticalSpeed, MovementState.speed)
		end
	end
	for _, player in Players:GetPlayers() do
		local other = player.Character
		if player ~= localPlayer and other and isNearCamera(other) then
			local root = other:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local velocity = root.AssemblyLinearVelocity
				local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				local sprinting = player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) == true and horizontal > 18
				local airborne = math.abs(velocity.Y) > AIRBORNE_SPEED
				if sprinting or airborne then
					local animator = animatorFor(other)
					animator:setLocomotion(if sprinting then 1 else 0, airborne, velocity.Y, horizontal)
				else
					local existing = CharacterAnimator.find(other)
					if existing then
						existing:setLocomotion(0, false, 0, horizontal)
					end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	updateLocomotion()
	for _, animator in CharacterAnimator.getActive() do
		if not animator:update(dt) then
			animator:destroy() -- plus rien à animer : articulations rendues, recréé au besoin
		end
	end
end)

--------------------------------------------------------------------------------
-- Événements du serveur (actions des autres joueurs, impacts)
--------------------------------------------------------------------------------

-- Plongée d'un autre joueur : lame levée pendant sa chute, frappe quand il touche le sol.
local function playRemotePlunge(character: Model)
	if character == localPlayer.Character or not isNearCamera(character) then
		return
	end
	local animator = animatorFor(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if animator == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	animator:play("sword_plunge_fall")
	local startClock = os.clock()
	local hasFallen = false
	while character.Parent and os.clock() - startClock < PLUNGE_REMOTE_TIMEOUT do
		local verticalSpeed = root.AssemblyLinearVelocity.Y
		if verticalSpeed < -20 then
			hasFallen = true
		elseif hasFallen and verticalSpeed > -3 then
			break -- la chute vient de s'arrêter : il est au sol
		end
		RunService.Heartbeat:Wait()
	end
	animator:stop("hold")
	animator:play("sword_plunge")
end

CombatRemotes.AttackStarted.OnClientEvent:Connect(function(attacker: Model?, comboIndex: any, kind: any)
	if kind == "sword_plunge" then
		if attacker then
			task.spawn(playRemotePlunge, attacker)
		end
	elseif type(kind) == "string" and kind ~= "" then
		playRemote(attacker, kind)
	elseif type(comboIndex) == "number" then
		playRemote(attacker, `sword_{comboIndex}`)
	end
end)

CombatRemotes.HitConfirmed.OnClientEvent:Connect(function(_attacker: Model?, target: Model?, _damage: any, result: any)
	if target == nil or not isNearCamera(target) then
		return
	end
	local animator = animatorFor(target)
	if animator then
		animator:play(if result == "broken" then "stagger" else "hit_react")
	end
end)

MovementRemotes.DashStarted.OnClientEvent:Connect(function(character: Model?)
	playRemote(character, "dash")
end)

MovementRemotes.DoubleJumped.OnClientEvent:Connect(function(character: Model?)
	playRemote(character, "double_jump")
end)

-- Postures maintenues d'un autre joueur (Concentration, charge) : attribut booléen posé par le serveur.
local function watchHold(player: Player, attribute: string, actionName: string)
	player:GetAttributeChangedSignal(attribute):Connect(function()
		local character = player.Character
		if character == nil or not isNearCamera(character) then
			return
		end
		local animator = animatorFor(character)
		if player:GetAttribute(attribute) == true then
			animator:play(actionName)
		elseif animator:isPlaying(actionName) then
			animator:stop("hold")
		end
	end)
end

-- Parade, Concentration et charge des autres joueurs : attributs posés par le serveur.
local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end
	player:GetAttributeChangedSignal(ParryConfig.PARRY_STANCE_ATTRIBUTE):Connect(function()
		playRemote(player.Character, "parry")
	end)
	watchHold(player, CONCENTRATING_ATTRIBUTE, "concentrate")
	watchHold(player, CHARGING_ATTRIBUTE, "sword_charge")
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
