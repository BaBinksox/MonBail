--!strict
--[[
	MovementService
	Façade serveur de la mobilité (singleton).

	Le déplacement d'un personnage est simulé par le client de son joueur : c'est lui qui se propulse
	(dash), accélère (sprint) et saute. Le serveur, lui, garde l'AUTORITÉ sur ce qui compte :
		- VITESSE DE BASE : calculée ici (vitesse du Humanoid x peuple x altérations x Concentration)
		  et publiée dans l'attribut MoveSpeedBase du Humanoid (et dans WalkSpeed). Le client ne fait
		  que la multiplier par sa montée en sprint ; un ralentissement s'applique donc aussi au sprint ;
		- SPRINT : demandé par le client (RequestSprint), accepté ou refusé ici (attribut Sprinting) ;
		- DOUBLE SAUT : un seul par passage en l'air (RequestDoubleJump), vérifié ici ;
		- DASH : cooldown vérifié, courte invulnérabilité accordée (isDashing) ;
		- CONTRÔLES : toutes les SPEED_CHECK_INTERVAL s, la distance parcourue et la hauteur de montée
		  de chaque joueur sont comparées à ce qui est permis. Plusieurs mesures hors limite d'affilée
		  ramènent le personnage à sa dernière position valide (les téléportations du serveur, les
		  éjections de combat et les dashs ne comptent pas).
	Sans validation ici, ni invulnérabilité ni vitesse supplémentaire : un client ne peut pas se les
	donner tout seul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Movement.MovementConfig)
local Remotes = require(ReplicatedStorage.Shared.Movement.MovementRemotes)
local RaceConfig = require(ReplicatedStorage.Shared.Avatar.RaceConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local RaceService = require(script.Parent.Parent.Avatar.RaceService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

type Tracker = {
	lastPosition: Vector3?,
	lastValidPosition: Vector3?,
	violations: number,
	groundedSinceDoubleJump: boolean,
	lastDoubleJumpClock: number,
	groundedRootY: number?, -- hauteur du RootPart la dernière fois qu'il a été vu au sol
}

-- Fournisseur d'un multiplicateur de vitesse (altérations, Concentration...). 1 = aucun effet.
export type SpeedProvider = (player: Player) -> number

local BASE_WALK_SPEED_ATTRIBUTE = "RaceBaseWalkSpeed" -- posé par RaceService : vitesse du Humanoid nu
local DEFAULT_WALK_SPEED = 16
local DEFAULT_JUMP_HEIGHT = 7.2
local GROUND_PROBE_EXTRA = 2 -- studs sous les pieds pour compter comme « au sol »

local MovementService = {}

local lastDashClock: { [Player]: number } = {} -- os.clock() du dernier dash accepté
local trackers: { [Player]: Tracker } = {}
local speedProviders: { SpeedProvider } = {}
local sprintLimiter = RateLimiter.new(8, 12)
local jumpLimiter = RateLimiter.new(4, 6)
local isStarted = false

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function canAct(player: Player): boolean
	if getHumanoid(player) == nil then
		return false
	end
	return not (AvatarService.isCustomizing(player) or TimeLoopService.isInAnomaly(player) or TimeLoopService.isRewinding())
end

local function getTracker(player: Player): Tracker
	local tracker = trackers[player]
	if tracker == nil then
		tracker = { lastPosition = nil, lastValidPosition = nil, violations = 0, groundedSinceDoubleJump = true, lastDoubleJumpClock = -math.huge, groundedRootY = nil }
		trackers[player] = tracker
	end
	return tracker
end

-- Le personnage touche-t-il le sol (raycast sous les pieds) ?
local function isGrounded(character: Model, root: BasePart, humanoid: Humanoid): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local reach = humanoid.HipHeight + root.Size.Y / 2 + GROUND_PROBE_EXTRA
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

-- Poussée de combat ou d'ultime en cours (LinearVelocity posée par le serveur) : déplacement légitime.
local function isBeingPushed(character: Model): boolean
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("LinearVelocity") and descendant.Name ~= "DashVelocity" then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Vitesse
--------------------------------------------------------------------------------

-- Multiplicateur total des fournisseurs (altérations, Concentration). 0 = immobilisé.
local function getProviderMultiplier(player: Player): number
	local multiplier = 1
	for _, provider in speedProviders do
		local isOk, value = pcall(provider, player)
		if isOk and type(value) == "number" and value == value then
			multiplier *= math.max(0, value)
		end
	end
	return multiplier
end

-- Recalcule et publie la vitesse de base (et la hauteur de saut : nulle si immobilisé).
function MovementService.refreshSpeed(player: Player)
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return
	end
	local base = humanoid:GetAttribute(BASE_WALK_SPEED_ATTRIBUTE)
	if type(base) ~= "number" then
		base = DEFAULT_WALK_SPEED
	end
	local race = RaceConfig.getById(player:GetAttribute(RaceConfig.ATTRIBUTE))
	local multiplier = getProviderMultiplier(player)
	local speed = (base :: number) * race.modifiers.walkSpeed * multiplier
	if math.abs(humanoid.WalkSpeed - speed) > 1e-3 then
		humanoid.WalkSpeed = speed
	end
	humanoid:SetAttribute(Config.MOVE_SPEED_ATTRIBUTE, speed)
	humanoid.JumpHeight = if multiplier <= 0.01 then 0 else DEFAULT_JUMP_HEIGHT
	if multiplier <= 0.01 and player:GetAttribute(Config.SPRINT_ATTRIBUTE) == true then
		player:SetAttribute(Config.SPRINT_ATTRIBUTE, false)
	end
end

function MovementService.addSpeedProvider(provider: SpeedProvider)
	table.insert(speedProviders, provider)
end

-- Vitesse maximale permise maintenant (sprint compris) : sert au contrôle de vitesse.
function MovementService.getMaxSpeed(player: Player): number
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return 0
	end
	local base = humanoid:GetAttribute(Config.MOVE_SPEED_ATTRIBUTE)
	local speed = if type(base) == "number" then base else humanoid.WalkSpeed
	return speed * Config.SPRINT_MULTIPLIER
end

--------------------------------------------------------------------------------
-- Sprint, double saut, dash
--------------------------------------------------------------------------------

function MovementService.isSprinting(player: Player): boolean
	return player:GetAttribute(Config.SPRINT_ATTRIBUTE) == true
end

-- Coupe le sprint (Concentration, immobilisation, mort...).
function MovementService.stopSprint(player: Player)
	if player:GetAttribute(Config.SPRINT_ATTRIBUTE) == true then
		player:SetAttribute(Config.SPRINT_ATTRIBUTE, false)
	end
end

-- Bloqueurs de sprint enregistrés par d'autres systèmes (Concentration...).
local sprintBlockers: { (player: Player) -> boolean } = {}
function MovementService.addSprintBlocker(blocker: (player: Player) -> boolean)
	table.insert(sprintBlockers, blocker)
end

local function onSprintRequested(player: Player, wants: any)
	if type(wants) ~= "boolean" or not sprintLimiter:allow(player) then
		return
	end
	if not wants then
		MovementService.stopSprint(player)
		return
	end
	if not canAct(player) or getProviderMultiplier(player) <= 0.01 then
		return
	end
	for _, blocker in sprintBlockers do
		local isOk, blocked = pcall(blocker, player)
		if isOk and blocked then
			return
		end
	end
	player:SetAttribute(Config.SPRINT_ATTRIBUTE, true)
end

local function onDoubleJumpRequested(player: Player)
	if not jumpLimiter:allow(player) or not canAct(player) then
		return
	end
	local humanoid, root = getHumanoid(player)
	local character = player.Character
	if humanoid == nil or root == nil or character == nil or humanoid.JumpHeight <= 0 then
		return
	end
	local tracker = getTracker(player)
	local now = os.clock()
	-- Un seul double saut par passage en l'air : il faut avoir été vu au sol depuis le précédent.
	if not tracker.groundedSinceDoubleJump or now - tracker.lastDoubleJumpClock < Config.DOUBLE_JUMP_MIN_AIR_TIME then
		if Config.DEBUG_LOGS then
			print(`[Movement] Double saut refusé pour {player.Name} : pas revenu au sol`)
		end
		return
	end
	tracker.groundedSinceDoubleJump = false
	tracker.lastDoubleJumpClock = now
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.DoubleJumped:FireClient(other, character)
		end
	end
end

local function onDashRequested(player: Player, direction: any)
	if not canAct(player) then
		return
	end

	local now = os.clock()
	local lastClock = lastDashClock[player]
	if lastClock and now - lastClock < Config.DASH_COOLDOWN - Config.LATENCY_TOLERANCE then
		if Config.DEBUG_LOGS then
			print(`[Movement] Dash refusé pour {player.Name} : cooldown`)
		end
		return
	end
	lastDashClock[player] = now

	local flat = if typeof(direction) == "Vector3" and direction.Magnitude > 1e-3 then Vector3.new(direction.X, 0, direction.Z) else nil
	-- Le joueur joue déjà son effet en local : seuls les autres clients sont prévenus.
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			Remotes.DashStarted:FireClient(otherPlayer, player.Character, if flat and flat.Magnitude > 1e-3 then flat.Unit else nil)
		end
	end
end

--------------------------------------------------------------------------------
-- Contrôles périodiques
--------------------------------------------------------------------------------

local function checkPlayer(player: Player, interval: number)
	local tracker = getTracker(player)
	local humanoid, root = getHumanoid(player)
	local character = player.Character
	if humanoid == nil or root == nil or character == nil or root.Anchored then
		tracker.lastPosition = nil
		tracker.violations = 0
		return
	end
	if isGrounded(character, root, humanoid) then
		tracker.groundedSinceDoubleJump = true
		tracker.groundedRootY = root.Position.Y
	end

	local position = root.Position
	local previous = tracker.lastPosition
	tracker.lastPosition = position
	if previous == nil then
		tracker.lastValidPosition = position
		return
	end
	local flatDistance = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z).Magnitude
	if flatDistance > Config.TELEPORT_DISTANCE then
		tracker.lastValidPosition = position -- téléporté par le serveur (arrivée, respawn, porte)
		tracker.violations = 0
		return
	end
	local exempt = MovementService.isDashing(player)
		or (lastDashClock[player] ~= nil and os.clock() - lastDashClock[player] < Config.DASH_DURATION + interval)
		or isBeingPushed(character)
		or TimeLoopService.isRewindingFor(player)
	local allowed = MovementService.getMaxSpeed(player) * Config.SPEED_TOLERANCE + Config.SPEED_TOLERANCE_FLAT
	local speed = flatDistance / interval
	-- Montée mesurée depuis le dernier appui au sol (et non au-dessus du sol actuel : un double saut
	-- au bord du ravin est légitime même si le fond est loin dessous).
	local rising = root.AssemblyLinearVelocity.Y > 5
	local takeoff = tracker.groundedRootY
	local tooHigh = rising and not exempt and takeoff ~= nil and position.Y - takeoff > Config.MAX_RISE_HEIGHT

	if (speed > allowed and not exempt) or tooHigh then
		tracker.violations += 1
		if tracker.violations >= Config.SPEED_VIOLATIONS_BEFORE_CORRECTION or tooHigh then
			local valid = tracker.lastValidPosition
			if valid then
				warn(`[Movement] {player.Name} : déplacement hors limite ({math.floor(speed)} studs/s, permis {math.floor(allowed)}) : position corrigée`)
				root.CFrame = CFrame.new(valid) * root.CFrame.Rotation
				root.AssemblyLinearVelocity = Vector3.zero
				tracker.lastPosition = valid
			end
			tracker.violations = 0
		end
	else
		tracker.violations = 0
		tracker.lastValidPosition = position
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function MovementService.start()
	if isStarted then
		return
	end
	isStarted = true

	Remotes.RequestDash.OnServerEvent:Connect(onDashRequested)
	Remotes.RequestSprint.OnServerEvent:Connect(onSprintRequested)
	Remotes.RequestDoubleJump.OnServerEvent:Connect(onDoubleJumpRequested)
	RaceService.setAfterApply(MovementService.refreshSpeed)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute(Config.SPRINT_ATTRIBUTE, false)
			local tracker = getTracker(player)
			tracker.lastPosition = nil
			tracker.violations = 0
			tracker.groundedSinceDoubleJump = true
			tracker.groundedRootY = nil
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastDashClock[player] = nil
		trackers[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Config.SPEED_CHECK_INTERVAL then
			return
		end
		local interval = elapsed
		elapsed = 0
		for _, player in Players:GetPlayers() do
			checkPlayer(player, interval)
		end
	end)
end

-- true pendant la fenêtre d'invulnérabilité d'un dash validé. Toute source de dégâts
-- (épée d'un autre joueur, coups du boss...) doit épargner un joueur pour qui c'est vrai.
function MovementService.isDashing(player: Player): boolean
	local lastClock = lastDashClock[player]
	return lastClock ~= nil and os.clock() - lastClock <= Config.DASH_INVULNERABILITY
end

-- os.clock() du dernier dash validé (esquive parfaite), ou nil.
function MovementService.getLastDashClock(player: Player): number?
	return lastDashClock[player]
end

return MovementService
