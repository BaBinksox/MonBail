--!strict
--[[
	EnemyBrain
	Boîte à outils commune à EnemyService et aux comportements (Server/Enemy/Behaviors/*).
	Elle ne garde aucun état global : tout l'état d'un ennemi vit dans son enregistrement `Enemy`.

		- Perception : cibles valides (vivantes, ni immunisées ni dans le Hub, à bonne hauteur, visibles),
		  provocation (un joueur qui frappe devient la cible), laisse autour du point d'apparition.
		- Déplacement : Humanoid:MoveTo direct quand la voie est libre, sinon PathfindingService. Le calcul
		  de chemin (qui YIELD) part dans son propre thread : la boucle de décision n'attend jamais.
		- Orientation : AlignOrientation à vitesse de rotation limitée (turnSpeed), pour qu'un ennemi lent
		  puisse être contourné.
		- Attaques : beginAttack() envoie le TÉLÉGRAPHE aux clients proches, puis la résolution est
		  planifiée à la fin du télégraphe (task.delay, protégée par un jeton). À l'impact, le SERVEUR teste
		  la géométrie (cercle / cône / ligne) sur les positions serveur des joueurs ; chaque joueur touché
		  passe par DamageService.damagePlayer (dash, parade, immunités). Un étourdissement ou la mort
		  invalident le jeton : l'attaque n'a pas lieu.

	Comportement = table { name, init?, think, modifyDamage?, onImpact?, onReset?, cleanup? } (type Behavior).
	`think` est appelé par la boucle unique d'EnemyService ; il décide et ne doit JAMAIS yield.
]]

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRemotes = require(ReplicatedStorage.Shared.Combat.CombatRemotes)
local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)
local EnemyRemotes = require(ReplicatedStorage.Shared.Enemy.EnemyRemotes)

local CombatStatus = require(script.Parent.Parent.Combat.CombatStatus)
local DamageService = require(script.Parent.Parent.Combat.DamageService)

local AI = Definitions.AI

type EnemyDef = Definitions.EnemyDef
type AttackDef = Definitions.AttackDef
type DamageSource = DamageService.DamageSource

export type Geometry = {
	shape: Definitions.AttackShape,
	origin: Vector3, -- point au sol
	direction: Vector3, -- unitaire, à plat
	radius: number,
	angle: number?,
	length: number?,
	width: number?,
}

export type Behavior = {
	name: string,
	init: ((enemy: Enemy) -> ())?,
	think: (enemy: Enemy, now: number, dt: number) -> (),
	modifyDamage: ((enemy: Enemy, amount: number, source: DamageSource) -> number)?,
	onImpact: ((enemy: Enemy, attack: AttackDef, geometry: Geometry) -> ())?,
	onReset: ((enemy: Enemy) -> ())?, -- l'ennemi rentre à son point d'apparition (laisse dépassée)
	cleanup: ((enemy: Enemy) -> ())?, -- mort ou disparition : libérer l'état du comportement
}

export type Navigation = {
	path: Path,
	waypoints: { PathWaypoint }?,
	index: number,
	goal: Vector3?,
	computedAt: number,
	isComputing: boolean,
}

export type Enemy = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	def: EnemyDef,
	enemyId: string,
	home: CFrame, -- point d'apparition (position du RootPart, orientation de l'ancre)
	behavior: Behavior,
	rootHeight: number, -- distance du RootPart au sol (pieds)
	isAlive: boolean, -- false dès la mort ou la disparition : plus aucune décision
	state: string, -- "idle" | "asleep" | "combat" | "attacking" | "stunned" | "returning" (lisible au débogage)
	target: Player?,
	targetRoot: BasePart?,
	baseSpeed: number,
	telegraphScale: number, -- < 1 : télégraphes raccourcis (rage)
	cooldownScale: number,
	cooldowns: { [string]: number }, -- attackId -> os.clock() à partir duquel elle est prête
	busyUntil: number, -- os.clock() : télégraphe, récupération, incantation en cours
	actionToken: number, -- incrémenté à chaque action ou interruption : invalide les résolutions en attente
	pendingAction: thread?,
	currentAttack: AttackDef?,
	lastDamagedClock: number,
	lastAttacker: Player?,
	lastAttackedClock: number,
	returnStartedClock: number,
	nav: Navigation,
	align: AlignOrientation?,
	walkTrack: AnimationTrack?,
	tracks: { [string]: AnimationTrack | false },
	isWalking: boolean,
	summoner: Enemy?, -- invocations : l'ennemi qui les a appelées
}

type Hooks = {
	-- Fait apparaître une invocation (EnemyService). `onSpawned` reçoit son enregistrement. Peut YIELD.
	spawnSummon: ((owner: Enemy, enemyId: string, cframe: CFrame, onSpawned: (Enemy) -> ()) -> ())?,
	-- Retire un ennemi sans récompense ni réapparition (invocations d'un élite qui rentre chez lui).
	despawn: ((enemy: Enemy) -> ())?,
}

local GROUND_PROBE = 30 -- studs sondés sous un point pour trouver le sol
local PARAMS_REFRESH = 0.1 -- secondes de validité de la liste d'exclusion des rayons
local LEASH_MARGIN = 2 -- studs gardés en deçà de la laisse pour les destinations calculées
local DASH_WALL_MARGIN = 2.5 -- studs gardés avant un mur au bout d'un bond
local DASH_MAX_FORCE = 1e6
local ALIGN_MAX_TORQUE = 1e7
local ALIGN_RESPONSIVENESS = 40
local STAND_STEP_LIMIT = 10 -- studs de dénivelé maximal pour une téléportation
local STAND_CLEARANCE = 1.5 -- rayon libre exigé à l'arrivée d'une téléportation
local BASE_SPEED_ATTRIBUTE = "BaseWalkSpeed" -- posé par UltimateBehaviors pendant un ralentissement

local EnemyBrain = {}

EnemyBrain.hooks = {
	spawnSummon = nil,
	despawn = nil,
} :: Hooks

local random = Random.new()
local cachedParams: RaycastParams? = nil
local cachedParamsClock = -math.huge

--------------------------------------------------------------------------------
-- Géométrie de base
--------------------------------------------------------------------------------

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end
EnemyBrain.flat = flat

-- Vecteur unitaire à plat ; `fallback` (lui-même aplati) si `vector` est quasi nul.
local function flatUnit(vector: Vector3, fallback: Vector3): Vector3
	local flattened = flat(vector)
	if flattened.Magnitude > 1e-3 then
		return flattened.Unit
	end
	local flatFallback = flat(fallback)
	return if flatFallback.Magnitude > 1e-3 then flatFallback.Unit else Vector3.new(0, 0, -1)
end
EnemyBrain.flatUnit = flatUnit

function EnemyBrain.flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

-- Dossier Workspace.Enemies (créé au besoin).
function EnemyBrain.getFolder(): Folder
	local existing = workspace:FindFirstChild(Definitions.FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = Definitions.FOLDER_NAME
	folder.Parent = workspace
	return folder
end

-- Paramètres de rayon qui ne voient que le DÉCOR : ennemis et personnages exclus, pièces non
-- collidables ignorées (ancres invisibles, décorations).
function EnemyBrain.getWorldParams(): RaycastParams
	local now = os.clock()
	if cachedParams and now - cachedParamsClock < PARAMS_REFRESH then
		return cachedParams
	end
	local ignore: { Instance } = { EnemyBrain.getFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	cachedParams = params
	cachedParamsClock = now
	return params
end

-- Point du sol sous `position` (sondé depuis un peu au-dessus), ou nil s'il n'y en a pas.
function EnemyBrain.findGround(position: Vector3, params: RaycastParams?): Vector3?
	local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -GROUND_PROBE, 0), params or EnemyBrain.getWorldParams())
	return if result then result.Position else nil
end

--[[
	true si `point` (position du RootPart d'un joueur) est dans la zone `geometry`, à `margin` studs
	près (rayon du corps). Fonction pure, sans accès au monde.
]]
function EnemyBrain.isPointInGeometry(geometry: Geometry, point: Vector3, margin: number): boolean
	local height = point.Y - geometry.origin.Y
	if height > AI.HIT_VERTICAL_REACH or height < -AI.HIT_VERTICAL_REACH * 0.5 then
		return false -- au-dessus (saut) ou sur un autre étage
	end
	local offset = flat(point - geometry.origin)
	local distance = offset.Magnitude

	if geometry.shape == "circle" then
		return distance <= geometry.radius + margin
	elseif geometry.shape == "cone" then
		if distance > geometry.radius + margin then
			return false
		end
		if distance <= margin then
			return true -- collé au sommet du cône
		end
		local halfAngle = math.rad((geometry.angle or 90) / 2)
		local cosine = math.clamp(offset.Unit:Dot(geometry.direction), -1, 1)
		-- Le corps du joueur déborde : la marge se convertit en angle à cette distance.
		return math.acos(cosine) <= halfAngle + math.atan(margin / distance)
	else
		local length = geometry.length or geometry.radius
		local along = offset:Dot(geometry.direction)
		if along < -margin or along > length + margin then
			return false
		end
		local lateral = (offset - geometry.direction * along).Magnitude
		return lateral <= (geometry.width or 4) / 2 + margin
	end
end

--------------------------------------------------------------------------------
-- Joueurs et cibles
--------------------------------------------------------------------------------

-- Personnage vivant d'un joueur et son RootPart, sinon nil.
function EnemyBrain.getLivingCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if character == nil or humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return character, rootPart
end

-- Joueurs dont le personnage est à moins de `radius` studs de `position`.
function EnemyBrain.getPlayersNear(position: Vector3, radius: number): { Player }
	local near = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") and (rootPart.Position - position).Magnitude <= radius then
			table.insert(near, player)
		end
	end
	return near
end

function EnemyBrain.isPlayerNear(enemy: Enemy, radius: number): boolean
	local position = enemy.rootPart.Position
	for _, player in Players:GetPlayers() do
		local _, rootPart = EnemyBrain.getLivingCharacter(player)
		if rootPart and (rootPart.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- Une cible doit être en jeu, ni immunisée (Hub, anomalie, rembobinage), et à une hauteur plausible.
local function isTargetable(enemy: Enemy, player: Player, rootPart: BasePart): boolean
	if player.Parent ~= Players or DamageService.isPlayerImmune(player) then
		return false
	end
	return math.abs(rootPart.Position.Y - enemy.rootPart.Position.Y) <= enemy.def.aggro.verticalTolerance
end

-- Aucun élément de décor solide entre les yeux de l'ennemi et `position`.
function EnemyBrain.hasLineOfSight(enemy: Enemy, position: Vector3): boolean
	local origin = enemy.rootPart.Position + Vector3.new(0, enemy.rootHeight * 0.5, 0)
	return workspace:Raycast(origin, position - origin, EnemyBrain.getWorldParams()) == nil
end

--[[
	Met à jour la cible de `enemy` : garde l'actuelle tant qu'elle est valide et à moins de loseRadius,
	sinon prend celui qui vient de le frapper (provocation), sinon le joueur visible le plus proche
	dans detectRadius.
]]
function EnemyBrain.updateTarget(enemy: Enemy, now: number)
	local aggro = enemy.def.aggro
	local position = enemy.rootPart.Position

	local current = enemy.target
	if current then
		local _, rootPart = EnemyBrain.getLivingCharacter(current)
		if rootPart and isTargetable(enemy, current, rootPart) and (rootPart.Position - position).Magnitude <= aggro.loseRadius then
			enemy.targetRoot = rootPart
			return
		end
		enemy.target = nil
		enemy.targetRoot = nil
	end

	local attacker = enemy.lastAttacker
	if attacker and now - enemy.lastAttackedClock <= AI.PROVOKE_WINDOW then
		local _, rootPart = EnemyBrain.getLivingCharacter(attacker)
		if rootPart and isTargetable(enemy, attacker, rootPart) and (rootPart.Position - position).Magnitude <= aggro.loseRadius then
			enemy.target = attacker
			enemy.targetRoot = rootPart
			return
		end
	end

	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = aggro.detectRadius
	for _, player in Players:GetPlayers() do
		local _, rootPart = EnemyBrain.getLivingCharacter(player)
		if rootPart then
			local distance = (rootPart.Position - position).Magnitude
			if distance <= bestDistance and isTargetable(enemy, player, rootPart) then
				best, bestRoot, bestDistance = player, rootPart, distance
			end
		end
	end
	if best and bestRoot and EnemyBrain.hasLineOfSight(enemy, bestRoot.Position) then
		enemy.target = best
		enemy.targetRoot = bestRoot
	end
end

--------------------------------------------------------------------------------
-- Laisse
--------------------------------------------------------------------------------

function EnemyBrain.distanceFromHome(enemy: Enemy): number
	return EnemyBrain.flatDistance(enemy.rootPart.Position, enemy.home.Position)
end

function EnemyBrain.isOutsideLeash(enemy: Enemy, position: Vector3): boolean
	return EnemyBrain.flatDistance(position, enemy.home.Position) > enemy.def.aggro.leashRadius - LEASH_MARGIN
end

-- Ramène `position` à l'intérieur de la laisse (même hauteur).
function EnemyBrain.clampToLeash(enemy: Enemy, position: Vector3): Vector3
	local home = enemy.home.Position
	local offset = flat(position - home)
	local limit = math.max(enemy.def.aggro.leashRadius - LEASH_MARGIN, 0)
	if offset.Magnitude <= limit then
		return position
	end
	local clamped = home + offset.Unit * limit
	return Vector3.new(clamped.X, position.Y, clamped.Z)
end

--------------------------------------------------------------------------------
-- Vitesse et animations
--------------------------------------------------------------------------------

-- Réapplique la vitesse de base, sauf pendant un ralentissement d'ultime (qui la rendra lui-même).
function EnemyBrain.refreshSpeed(enemy: Enemy)
	local humanoid = enemy.humanoid
	if humanoid:GetAttribute(BASE_SPEED_ATTRIBUTE) ~= nil then
		return
	end
	if math.abs(humanoid.WalkSpeed - enemy.baseSpeed) > 0.01 then
		humanoid.WalkSpeed = enemy.baseSpeed
	end
end

function EnemyBrain.setBaseSpeed(enemy: Enemy, speed: number)
	enemy.baseSpeed = speed
	EnemyBrain.refreshSpeed(enemy)
end

-- Paralysé par un effet de vitesse (Foudre) : ni déplacement ni attaque.
function EnemyBrain.isImmobilized(enemy: Enemy): boolean
	local humanoid = enemy.humanoid
	return humanoid:GetAttribute(BASE_SPEED_ATTRIBUTE) ~= nil and humanoid.WalkSpeed <= 0.05
end

local function loadTrack(enemy: Enemy, animationId: string, isLooped: boolean): AnimationTrack?
	if animationId == "" then
		return nil
	end
	local cached = enemy.tracks[animationId]
	if cached ~= nil then
		return if cached then cached else nil
	end

	local humanoid = enemy.humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local isLoaded, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not isLoaded then
		enemy.tracks[animationId] = false -- rig incompatible (R6 de secours, modèle maison) : sans animation
		return nil
	end
	track.Looped = isLooped
	track.Priority = if isLooped then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	enemy.tracks[animationId] = track
	return track
end

function EnemyBrain.playAnimation(enemy: Enemy, animationId: string, speed: number?)
	local track = loadTrack(enemy, animationId, false)
	if track then
		track:Play(0.1, 1, speed or 1)
	end
end

local function setWalking(enemy: Enemy, isWalking: boolean)
	if enemy.isWalking == isWalking then
		return
	end
	enemy.isWalking = isWalking
	local track = enemy.walkTrack
	if track == nil then
		return
	end
	if isWalking then
		track:Play(0.2)
		track:AdjustSpeed(math.max(0.5, enemy.humanoid.WalkSpeed / Definitions.WALK_ANIMATION_BASE_SPEED))
	else
		track:Stop(0.2)
	end
end

--------------------------------------------------------------------------------
-- Orientation
--------------------------------------------------------------------------------

local function ensureAlign(enemy: Enemy): AlignOrientation
	local existing = enemy.align
	if existing and existing.Parent then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "EnemyFacingAttachment"
	attachment.Parent = enemy.rootPart

	local align = Instance.new("AlignOrientation")
	align.Name = "EnemyFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = ALIGN_MAX_TORQUE
	align.MaxAngularVelocity = math.rad(enemy.def.turnSpeed)
	align.Responsiveness = ALIGN_RESPONSIVENESS
	align.Enabled = false
	align.Parent = enemy.rootPart
	enemy.align = align
	return align
end

-- Tourne l'ennemi vers `position` (à plat), à sa vitesse de rotation. Un ennemi ancré pivote d'un coup.
function EnemyBrain.face(enemy: Enemy, position: Vector3)
	local rootPart = enemy.rootPart
	local flatTarget = Vector3.new(position.X, rootPart.Position.Y, position.Z)
	if (flatTarget - rootPart.Position).Magnitude < 0.1 then
		return
	end
	if rootPart.Anchored then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, flatTarget)
		return
	end
	local align = ensureAlign(enemy)
	enemy.humanoid.AutoRotate = false
	align.CFrame = CFrame.lookAt(rootPart.Position, flatTarget)
	align.Enabled = true
end

-- Rend l'orientation au Humanoid (il regarde là où il marche).
function EnemyBrain.releaseFacing(enemy: Enemy)
	if enemy.align then
		enemy.align.Enabled = false
	end
	enemy.humanoid.AutoRotate = true
end

-- true si `position` est dans le cône frontal d'ouverture `angle` (degrés) de l'ennemi.
function EnemyBrain.isInFront(enemy: Enemy, position: Vector3, angle: number): boolean
	local rootPart = enemy.rootPart
	local offset = flat(position - rootPart.Position)
	if offset.Magnitude < 0.5 then
		return true -- dans son corps : considéré de face
	end
	local look = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	return offset.Unit:Dot(look) >= math.cos(math.rad(angle / 2))
end

--------------------------------------------------------------------------------
-- Déplacement
--------------------------------------------------------------------------------

function EnemyBrain.stop(enemy: Enemy)
	if enemy.rootPart.Anchored then
		return
	end
	enemy.humanoid:MoveTo(enemy.rootPart.Position)
	setWalking(enemy, false)
end

-- Aucun obstacle de décor entre l'ennemi et `destination` : MoveTo direct suffit.
local function isDirectPathClear(enemy: Enemy, destination: Vector3): boolean
	local origin = enemy.rootPart.Position
	local offset = destination - origin
	if flat(offset).Magnitude < 0.5 then
		return true
	end
	return workspace:Raycast(origin, offset, EnemyBrain.getWorldParams()) == nil
end

-- Calcul de chemin en arrière-plan (ComputeAsync YIELD) : un seul à la fois par ennemi.
local function requestPath(enemy: Enemy, destination: Vector3)
	local nav = enemy.nav
	if nav.isComputing then
		return
	end
	nav.isComputing = true
	local start = enemy.rootPart.Position
	task.spawn(function()
		local isComputed = pcall(function()
			nav.path:ComputeAsync(start, destination)
		end)
		nav.isComputing = false
		if not enemy.isAlive then
			return
		end
		nav.computedAt = os.clock()
		nav.goal = destination
		if isComputed and nav.path.Status == Enum.PathStatus.Success then
			nav.waypoints = nav.path:GetWaypoints()
			nav.index = 2 -- [1] est la position de départ
		else
			nav.waypoints = nil
		end
	end)
end

local function followPath(enemy: Enemy, destination: Vector3)
	local nav = enemy.nav
	local goal = nav.goal
	local isStale = goal == nil or (goal - destination).Magnitude > AI.REPATH_DISTANCE or os.clock() - nav.computedAt > AI.REPATH_INTERVAL
	if isStale then
		requestPath(enemy, destination)
	end

	local waypoints = nav.waypoints
	if waypoints == nil then
		enemy.humanoid:MoveTo(destination) -- en attendant un chemin (ou sans chemin possible) : tout droit
		return
	end
	local position = enemy.rootPart.Position
	while nav.index <= #waypoints and flat(waypoints[nav.index].Position - position).Magnitude < AI.WAYPOINT_REACHED do
		nav.index += 1
	end
	local waypoint = waypoints[nav.index]
	if waypoint == nil then
		enemy.humanoid:MoveTo(destination)
		return
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		enemy.humanoid.Jump = true
	end
	enemy.humanoid:MoveTo(waypoint.Position)
end

--[[
	Marche vers `destination`. Avec `faceTowards`, l'ennemi garde ce point en face (il recule ou
	tourne autour en le regardant) ; sans, il regarde là où il va.
]]
function EnemyBrain.moveTo(enemy: Enemy, destination: Vector3, faceTowards: Vector3?)
	if enemy.rootPart.Anchored then
		return
	end
	if faceTowards then
		EnemyBrain.face(enemy, faceTowards)
	else
		EnemyBrain.releaseFacing(enemy)
	end
	if flat(destination - enemy.rootPart.Position).Magnitude < 1 then
		EnemyBrain.stop(enemy)
		return
	end
	setWalking(enemy, true)
	if isDirectPathClear(enemy, destination) then
		enemy.nav.waypoints = nil
		enemy.nav.goal = nil
		enemy.humanoid:MoveTo(destination)
	else
		followPath(enemy, destination)
	end
end

-- Sans cible : rentre au point d'apparition au pas, puis y reste en regardant comme son ancre.
function EnemyBrain.idle(enemy: Enemy)
	enemy.state = "idle"
	if enemy.rootPart.Anchored then
		return
	end
	if EnemyBrain.distanceFromHome(enemy) > AI.HOME_TOLERANCE then
		EnemyBrain.moveTo(enemy, enemy.home.Position)
	else
		EnemyBrain.stop(enemy)
		EnemyBrain.face(enemy, enemy.home.Position + enemy.home.LookVector * 10)
	end
end

-- Déplace instantanément l'ennemi : RootPart à `rootPosition`, tourné vers `lookAt`.
function EnemyBrain.teleport(enemy: Enemy, rootPosition: Vector3, lookAt: Vector3?)
	local rootPart = enemy.rootPart
	local look = if lookAt
		then Vector3.new(lookAt.X, rootPosition.Y, lookAt.Z)
		else rootPosition + flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	if (look - rootPosition).Magnitude < 0.1 then
		look = rootPosition + Vector3.new(0, 0, -1)
	end
	local target = CFrame.lookAt(rootPosition, look)
	local model = enemy.model
	model:PivotTo(target * rootPart.CFrame:ToObjectSpace(model:GetPivot()))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	enemy.nav.waypoints = nil
	enemy.nav.goal = nil
	if enemy.align then
		enemy.align.CFrame = target
	end
end

--[[
	Position de RootPart où l'ennemi peut se tenir près de `candidate` : sol présent, dénivelé
	raisonnable, place libre. nil sinon.
]]
function EnemyBrain.findStandingPoint(enemy: Enemy, candidate: Vector3): Vector3?
	local params = EnemyBrain.getWorldParams()
	local feetY = enemy.rootPart.Position.Y - enemy.rootHeight
	local ground = EnemyBrain.findGround(Vector3.new(candidate.X, feetY + STAND_STEP_LIMIT, candidate.Z), params)
	if ground == nil or math.abs(ground.Y - feetY) > STAND_STEP_LIMIT then
		return nil
	end
	local rootPosition = ground + Vector3.new(0, enemy.rootHeight, 0)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = params.FilterDescendantsInstances
	overlap.RespectCanCollide = true
	if #workspace:GetPartBoundsInRadius(rootPosition, STAND_CLEARANCE, overlap) > 0 then
		return nil
	end
	return rootPosition
end

--[[
	Bond : propulse l'ennemi le long de `direction` sur `distance` studs en `duration` s (LinearVelocity
	horizontale ; la gravité reste libre). Raccourci devant un mur, annulé au bord d'un vide.
]]
function EnemyBrain.dash(enemy: Enemy, direction: Vector3, distance: number, duration: number)
	local rootPart = enemy.rootPart
	if rootPart.Anchored or distance <= 0 or duration <= 0 then
		return
	end
	local params = EnemyBrain.getWorldParams()
	local unit = flatUnit(direction, rootPart.CFrame.LookVector)
	local wall = workspace:Raycast(rootPart.Position, unit * distance, params)
	local travel = if wall then math.max(0, (wall.Position - rootPart.Position).Magnitude - DASH_WALL_MARGIN) else distance
	-- Pas de bond dans le vide : on raccourcit jusqu'à trouver du sol à l'arrivée.
	while travel >= 1 and EnemyBrain.findGround(rootPart.Position + unit * travel, params) == nil do
		travel *= 0.5
	end
	if travel < 1 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "EnemyDashAttachment"
	attachment.Parent = rootPart

	local speed = travel / duration
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "EnemyDash"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(unit.X * speed, unit.Z * speed)
	velocity.MaxForce = DASH_MAX_FORCE
	velocity.Parent = rootPart

	Debris:AddItem(velocity, duration)
	Debris:AddItem(attachment, duration)
end

--------------------------------------------------------------------------------
-- Messages aux clients
--------------------------------------------------------------------------------

function EnemyBrain.action(enemy: Enemy, action: string, position: Vector3?, toPosition: Vector3?)
	local data: EnemyRemotes.ActionData = {
		enemy = enemy.model,
		action = action,
		position = position,
		toPosition = toPosition,
	}
	local center = position or enemy.rootPart.Position
	for _, player in EnemyBrain.getPlayersNear(center, Definitions.TELEGRAPH_BROADCAST_RADIUS) do
		EnemyRemotes.EnemyAction:FireClient(player, data)
	end
end

local function broadcastTelegraph(data: EnemyRemotes.TelegraphData)
	for _, player in EnemyBrain.getPlayersNear(data.origin, Definitions.TELEGRAPH_BROADCAST_RADIUS) do
		EnemyRemotes.Telegraph:FireClient(player, data)
	end
end

--------------------------------------------------------------------------------
-- Attaques
--------------------------------------------------------------------------------

-- L'ennemi peut agir : vivant, en jeu, pas étourdi.
function EnemyBrain.canAct(enemy: Enemy): boolean
	return enemy.isAlive
		and enemy.humanoid.Health > 0
		and enemy.rootPart.Parent ~= nil
		and not CombatStatus.isStunned(enemy.model)
end

function EnemyBrain.getAttack(enemy: Enemy, attackId: string): AttackDef?
	for _, attack in enemy.def.attacks do
		if attack.id == attackId then
			return attack
		end
	end
	return nil
end

function EnemyBrain.isAttackReady(enemy: Enemy, attack: AttackDef, now: number): boolean
	return now >= (enemy.cooldowns[attack.id] or 0)
end

-- Tirage pondéré parmi les attaques prêtes dont la portée couvre `distance` (et que `filter` accepte).
function EnemyBrain.pickAttack(enemy: Enemy, distance: number, now: number, filter: ((AttackDef) -> boolean)?): AttackDef?
	local candidates: { AttackDef } = {}
	local totalWeight = 0
	for _, attack in enemy.def.attacks do
		if distance <= attack.range and EnemyBrain.isAttackReady(enemy, attack, now) and (filter == nil or filter(attack)) then
			table.insert(candidates, attack)
			totalWeight += attack.weight or 1
		end
	end
	if #candidates == 0 then
		return nil
	end
	local roll = random:NextNumber() * totalWeight
	for _, attack in candidates do
		roll -= attack.weight or 1
		if roll <= 0 then
			return attack
		end
	end
	return candidates[#candidates]
end

-- Zone de l'attaque, figée au moment du télégraphe. `direction` remplace la visée vers la cible.
function EnemyBrain.buildGeometry(enemy: Enemy, attack: AttackDef, targetPosition: Vector3?, direction: Vector3?): Geometry
	local rootPart = enemy.rootPart
	local selfPosition = rootPart.Position
	local aim = if targetPosition then targetPosition - selfPosition else rootPart.CFrame.LookVector
	local unit = flatUnit(direction or aim, rootPart.CFrame.LookVector)
	local center = if attack.center == "target" and targetPosition then targetPosition else selfPosition
	local height = if attack.center == "target" and targetPosition then 3 else enemy.rootHeight
	local ground = EnemyBrain.findGround(center) or (center - Vector3.new(0, height, 0))
	return {
		shape = attack.shape,
		origin = ground,
		direction = unit,
		radius = attack.radius,
		angle = attack.angle,
		length = attack.length or attack.radius,
		width = attack.width,
	}
end

-- Joueurs touchés par `geometry` maintenant (positions serveur), sans décor entre la zone et eux.
function EnemyBrain.getPlayersInGeometry(geometry: Geometry): { Player }
	local victims = {}
	local params = EnemyBrain.getWorldParams()
	local eye = geometry.origin + Vector3.new(0, 2, 0)
	for _, player in Players:GetPlayers() do
		local _, rootPart = EnemyBrain.getLivingCharacter(player)
		if rootPart and EnemyBrain.isPointInGeometry(geometry, rootPart.Position, AI.HIT_MARGIN) then
			if workspace:Raycast(eye, rootPart.Position - eye, params) == nil then
				table.insert(victims, player)
			end
		end
	end
	return victims
end

-- Un joueur pris dans la zone : DamageService décide (dash, parade, immunités). Peut YIELD (parade).
local function strikePlayer(enemy: Enemy, player: Player, attack: AttackDef)
	local character = player.Character
	local source: DamageSource = {
		model = enemy.model,
		kind = "enemy",
		unblockable = not attack.parryable,
	}
	local result, applied = DamageService.damagePlayer(player, attack.damage, source)
	if result == "hit" and applied > 0 and character then
		-- Mêmes effets d'impact qu'un coup d'épée (CombatController).
		CombatRemotes.HitConfirmed:FireAllClients(enemy.model, character, applied)
	end
end

local function resolveAttack(enemy: Enemy, token: number, attack: AttackDef, geometry: Geometry)
	if enemy.actionToken ~= token then
		return -- interrompue entre-temps (étourdissement, mort, retour au point)
	end
	enemy.pendingAction = nil
	enemy.currentAttack = nil
	if not EnemyBrain.canAct(enemy) then
		return
	end
	enemy.busyUntil = os.clock() + attack.recovery

	for _, player in EnemyBrain.getPlayersInGeometry(geometry) do
		task.spawn(strikePlayer, enemy, player, attack) -- une parade qui attend ne retarde pas les autres
	end
	local onImpact = enemy.behavior.onImpact
	if onImpact then
		onImpact(enemy, attack, geometry)
	end
end

--[[
	Lance `attack` : arrêt, posture, télégraphe aux clients proches, puis résolution serveur à la fin
	du télégraphe (attack.telegraph x telegraphScale). `direction` : visée imposée (sinon vers la cible).
]]
function EnemyBrain.beginAttack(enemy: Enemy, attack: AttackDef, targetPosition: Vector3?, direction: Vector3?)
	local now = os.clock()
	local telegraph = attack.telegraph * enemy.telegraphScale
	local geometry = EnemyBrain.buildGeometry(enemy, attack, targetPosition, direction)

	enemy.actionToken += 1
	local token = enemy.actionToken
	enemy.currentAttack = attack
	enemy.state = "attacking"
	enemy.cooldowns[attack.id] = now + telegraph + attack.cooldown * enemy.cooldownScale
	enemy.busyUntil = now + telegraph + attack.recovery

	EnemyBrain.stop(enemy)
	EnemyBrain.face(enemy, enemy.rootPart.Position + geometry.direction * 10)
	EnemyBrain.playAnimation(enemy, attack.animationId, attack.animationSpeed)

	broadcastTelegraph({
		shape = geometry.shape,
		origin = geometry.origin,
		direction = geometry.direction,
		radius = geometry.radius,
		angle = geometry.angle,
		length = geometry.length,
		width = geometry.width,
		duration = telegraph,
		enemy = enemy.model,
		unblockable = not attack.parryable,
		startedAt = workspace:GetServerTimeNow(),
	})

	enemy.pendingAction = task.delay(telegraph, resolveAttack, enemy, token, attack, geometry)
end

--[[
	Incantation sans zone (invocation...) : l'ennemi est occupé `duration` s, puis `onComplete` est
	appelé s'il peut toujours agir. Un étourdissement l'annule, comme une attaque.
]]
function EnemyBrain.beginChannel(enemy: Enemy, duration: number, onComplete: (Enemy) -> ())
	enemy.actionToken += 1
	local token = enemy.actionToken
	enemy.state = "attacking"
	enemy.busyUntil = os.clock() + duration
	EnemyBrain.stop(enemy)
	enemy.pendingAction = task.delay(duration, function()
		if enemy.actionToken ~= token then
			return
		end
		enemy.pendingAction = nil
		if EnemyBrain.canAct(enemy) then
			onComplete(enemy)
		end
	end)
end

-- Annule l'action en cours (attaque télégraphiée, incantation) et prévient les clients.
function EnemyBrain.interrupt(enemy: Enemy)
	local pending = enemy.pendingAction
	enemy.actionToken += 1
	enemy.pendingAction = nil
	enemy.currentAttack = nil
	enemy.busyUntil = 0
	if pending then
		pcall(task.cancel, pending)
		EnemyBrain.action(enemy, "cancel")
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function EnemyBrain.new(model: Model, humanoid: Humanoid, rootPart: BasePart, def: EnemyDef, home: CFrame, behavior: Behavior, rootHeight: number): Enemy
	local scale = def.appearance.modelScale
	local enemy: Enemy = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		def = def,
		enemyId = def.id,
		home = home,
		behavior = behavior,
		rootHeight = rootHeight,
		isAlive = true,
		state = "idle",
		target = nil,
		targetRoot = nil,
		baseSpeed = def.walkSpeed,
		telegraphScale = 1,
		cooldownScale = 1,
		cooldowns = {},
		busyUntil = 0,
		actionToken = 0,
		pendingAction = nil,
		currentAttack = nil,
		lastDamagedClock = -math.huge,
		lastAttacker = nil,
		lastAttackedClock = -math.huge,
		returnStartedClock = 0,
		nav = {
			path = PathfindingService:CreatePath({
				AgentRadius = math.max(2, 2 * scale),
				AgentHeight = math.max(5, 5 * scale),
				AgentCanJump = true,
				WaypointSpacing = 6,
			}),
			waypoints = nil,
			index = 1,
			goal = nil,
			computedAt = -math.huge,
			isComputing = false,
		},
		align = nil,
		walkTrack = nil,
		tracks = {},
		isWalking = false,
		summoner = nil,
	}
	if not rootPart.Anchored then
		enemy.walkTrack = loadTrack(enemy, Definitions.WALK_ANIMATION_ID, true)
	end
	return enemy
end

-- Arrête définitivement l'ennemi (mort, disparition) : plus de décision, d'attaque ni de calcul de chemin.
function EnemyBrain.shutdown(enemy: Enemy)
	if not enemy.isAlive then
		return
	end
	EnemyBrain.interrupt(enemy)
	enemy.isAlive = false
	enemy.target = nil
	enemy.targetRoot = nil
	enemy.summoner = nil
	if enemy.walkTrack then
		enemy.walkTrack:Stop(0)
	end
	for _, track in enemy.tracks do
		if track then
			track:Stop(0)
		end
	end
	if enemy.align then
		enemy.align.Enabled = false
	end
	local cleanup = enemy.behavior.cleanup
	if cleanup then
		local isCleaned, message = pcall(cleanup, enemy)
		if not isCleaned then
			warn(`[Enemy] Nettoyage du comportement {enemy.behavior.name} impossible : {message}`)
		end
	end
	enemy.nav.waypoints = nil
	pcall(function()
		enemy.nav.path:Destroy()
	end)
end

return EnemyBrain
