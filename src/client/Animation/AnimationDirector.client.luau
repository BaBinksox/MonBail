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

CombatRemotes.AttackStarted.OnClientEvent:Connect(function(attacker: Model?, comboIndex: any, kind: any)
	if type(kind) == "string" and kind ~= "" then
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

-- Parade et Concentration des autres joueurs : attributs posés par le serveur.
local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end
	player:GetAttributeChangedSignal(ParryConfig.PARRY_STANCE_ATTRIBUTE):Connect(function()
		playRemote(player.Character, "parry")
	end)
	player:GetAttributeChangedSignal(CONCENTRATING_ATTRIBUTE):Connect(function()
		local character = player.Character
		if character == nil or not isNearCamera(character) then
			return
		end
		local animator = animatorFor(character)
		if player:GetAttribute(CONCENTRATING_ATTRIBUTE) == true then
			animator:play("concentrate")
		else
			animator:stop("hold")
		end
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
