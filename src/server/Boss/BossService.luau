--!strict
--[[
	BossService
	IA des boss (singleton serveur). Tout Model taggé BossConfig.TAG dans le Workspace devient un boss.

	Chaque boss fait tourner la même boucle de décision, toutes les THINK_INTERVAL secondes :
		1. pas de cible vivante à portée              -> Idle
		2. PV <= 20 % et attaque fatale disponible    -> performUltimate()
		3. cible au corps-à-corps                     -> performAttack()
		4. sinon                                      -> chase() (PathfindingService)

	L'attaque fatale est le lien avec le Time-Loop :
		charge (immobile, invulnérable) -> TimeLoopService.openAnomaly(participant le plus proche)
		   A. un participant rembobine -> la RENCONTRE revient 5 s en arrière, le boss reste sonné : la faille ;
		   B. personne ne fait rien    -> TimeLoopService tue le joueur visé, le boss reprend sa traque.

	Chaque boss a sa RENCONTRE (EncounterService) : il ne cible que ses participants, l'anomalie et
	le rembobinage ne concernent qu'eux, et seule leur ambiance vire au rouge.

	Le serveur ne joue aucun effet visuel : il publie l'état du boss dans un attribut du Model,
	et BossEffectsController (client) fait le spectacle.
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local CombatRemotes = require(ReplicatedStorage.Shared.Combat.CombatRemotes)
local TimeLoopConfig = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local CombatStatus = require(script.Parent.Parent.Combat.CombatStatus)
local DamageService = require(script.Parent.Parent.Combat.DamageService)
local AnchorService = require(script.Parent.Parent.Core.AnchorService)
local EncounterService = require(script.Parent.Parent.Encounter.EncounterService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

local STATES = Config.STATES
local POLL_INTERVAL = 0.1 -- secondes entre deux vérifications pendant une attente (rewind)
local CHARGE_ANCHOR_REASON = "boss_charge"
local RETURN_HOME_DISTANCE = 8 -- studs : sans cible, il rentre à son point d'apparition s'il en est plus loin
local STATUS_SPEED_ATTRIBUTE = "StatusSpeedMultiplier" -- = StatusConfig.SPEED_ATTRIBUTE (froid, pression...)

type Boss = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	path: Path,
	walkTrack: AnimationTrack?,
	attackTrack: AnimationTrack?,
	nextAttackClock: number, -- os.clock() à partir duquel il peut refrapper
	ultimateReadyClock: number, -- os.clock() à partir duquel l'attaque fatale est disponible
	home: Vector3, -- point d'apparition
	encounterId: string, -- rencontre (timeline) du boss
}

local BossService = {}

local bosses: { [Model]: Boss } = {}
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function log(boss: Boss, message: string)
	if Config.DEBUG_LOGS then
		print(`[Boss] {boss.model.Name} : {message}`)
	end
end

local function isAlive(boss: Boss): boolean
	return bosses[boss.model] == boss and boss.model.Parent ~= nil and boss.humanoid.Health > 0
end

-- Publie l'état pour les clients et règle l'animation de marche en conséquence.
local function setState(boss: Boss, state: string)
	if boss.model:GetAttribute(Config.STATE_ATTRIBUTE) == state then
		return
	end
	boss.model:SetAttribute(Config.STATE_ATTRIBUTE, state)

	if boss.walkTrack then
		if state == STATES.Chasing then
			boss.walkTrack:Play(0.2)
		else
			boss.walkTrack:Stop(0.2)
		end
	end
end

-- Charge une animation sur l'Animator du boss. Jouée par le serveur, elle est répliquée aux clients.
local function loadTrack(animator: Animator, animationId: string, isLooped: boolean): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local isLoaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not isLoaded then
		return nil -- rig incompatible (R6...) : le boss fonctionnera sans cette animation
	end
	track.Looped = isLooped
	return track
end

-- Retourne le Humanoid et le RootPart du personnage d'un joueur s'il peut être pris pour cible.
local function getTargetParts(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 or AvatarService.isCustomizing(player) then
		return nil, nil
	end
	return humanoid, rootPart
end

-- Le PARTICIPANT vivant le plus proche dans AGGRO_RANGE, avec son RootPart et sa distance.
local function findNearestPlayer(boss: Boss): (Player?, BasePart?, number)
	local nearestPlayer: Player? = nil
	local nearestRoot: BasePart? = nil
	local nearestDistance = Config.AGGRO_RANGE

	for _, player in EncounterService.getParticipants(boss.model) do
		local _, rootPart = getTargetParts(player)
		if rootPart then
			local distance = (rootPart.Position - boss.rootPart.Position).Magnitude
			if distance <= nearestDistance then
				nearestPlayer, nearestRoot, nearestDistance = player, rootPart, distance
			end
		end
	end

	return nearestPlayer, nearestRoot, nearestDistance
end

-- Le boss doit être simulé par le serveur, sinon sa physique peut être confiée au client le plus
-- proche. (Interdit sur un assemblage ancré, d'où la vérification.)
local function claimServerOwnership(rootPart: BasePart)
	if rootPart:CanSetNetworkOwnership() then
		rootPart:SetNetworkOwner(nil)
	end
end

local function faceTowards(boss: Boss, position: Vector3)
	local origin = boss.rootPart.Position
	local flatTarget = Vector3.new(position.X, origin.Y, position.Z)
	if (flatTarget - origin).Magnitude > 0.1 then
		boss.rootPart.CFrame = CFrame.lookAt(origin, flatTarget)
	end
end

local function stopMoving(boss: Boss)
	boss.humanoid:MoveTo(boss.rootPart.Position)
end

--------------------------------------------------------------------------------
-- Comportements
--------------------------------------------------------------------------------

-- Poursuite : on recalcule un chemin vers la cible à chaque décision et on vise son prochain
-- point de passage. Comme la cible bouge sans arrêt, suivre un chemin entier n'aurait pas de sens.
local function chase(boss: Boss, targetRoot: BasePart)
	setState(boss, STATES.Chasing)
	local destination = targetRoot.Position

	local isComputed = pcall(function()
		boss.path:ComputeAsync(boss.rootPart.Position, destination) -- yield
	end)

	if isComputed and boss.path.Status == Enum.PathStatus.Success then
		local waypoints = boss.path:GetWaypoints()
		local nextWaypoint = waypoints[2] -- [1] est la position actuelle du boss
		if nextWaypoint then
			if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
				boss.humanoid.Jump = true
			end
			boss.humanoid:MoveTo(nextWaypoint.Position)
			return
		end
	end

	-- Pas de chemin (cible en l'air, zone non navigable...) : on fonce en ligne droite.
	boss.humanoid:MoveTo(destination)
end

-- Corps-à-corps : un geste annoncé (ATTACK_WINDUP), puis l'impact si la cible est toujours là.
-- Le joueur peut l'éviter en reculant hors de portée ou en dashant au bon moment.
local function performAttack(boss: Boss, target: Player, targetRoot: BasePart)
	stopMoving(boss)
	if os.clock() < boss.nextAttackClock then
		setState(boss, STATES.Idle)
		return
	end
	boss.nextAttackClock = os.clock() + Config.ATTACK_COOLDOWN

	setState(boss, STATES.Attacking)
	faceTowards(boss, targetRoot.Position)
	if boss.attackTrack then
		boss.attackTrack:Play(0.05)
	end

	task.wait(Config.ATTACK_WINDUP)
	if not isAlive(boss) or TimeLoopService.isEncounterRewinding(boss.encounterId) then
		return
	end

	local targetHumanoid, currentRoot = getTargetParts(target)
	if targetHumanoid == nil or currentRoot == nil then
		return
	end

	local distance = (currentRoot.Position - boss.rootPart.Position).Magnitude
	local isOutOfReach = distance > Config.ATTACK_RANGE + Config.ATTACK_RANGE_TOLERANCE
	if isOutOfReach or CombatStatus.isStunned(boss.model) then
		log(boss, `{target.Name} esquive le coup`)
		return
	end

	-- Dash, parade et immunités (anomalie, Hub, rembobinage) : arbitrés par DamageService (peut yield).
	local result, damage = DamageService.damagePlayer(target, Config.ATTACK_DAMAGE, { model = boss.model, kind = "enemy" })
	if result ~= "hit" then
		log(boss, `coup sur {target.Name} : {result}`)
		return
	end
	-- Même événement que pour un coup d'épée : les clients jouent impact, hit-stop et secousse.
	CombatRemotes.HitConfirmed:FireAllClients(boss.model, target.Character, damage)
end

local function waitForRewindEnd(boss: Boss)
	while TimeLoopService.isEncounterRewinding(boss.encounterId) do
		task.wait(POLL_INTERVAL)
	end
end

-- Attaque fatale : charge, puis anomalie temporelle sur le joueur le plus proche.
local function performUltimate(boss: Boss)
	boss.ultimateReadyClock = os.clock() + Config.ULTIMATE_COOLDOWN

	-- 1. Charge : immobile et intouchable. Les clients voient l'état Charging et jouent l'effet.
	log(boss, "charge son attaque fatale")
	stopMoving(boss)
	AnchorService.hold(boss.rootPart, CHARGE_ANCHOR_REASON)
	boss.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, true)
	setState(boss, STATES.Charging)
	-- Les participants basculent : ciel noir, lumière rouge sang (eux seuls, pas tout le serveur).
	EncounterService.setAnomalyMood(boss.model, true)
	task.wait(Config.CHARGE_DURATION)

	-- 2. L'attaque part : au lieu de tuer le joueur, on ouvre son anomalie temporelle.
	--    Son issue est enregistrée par TimeLoopService au moment même de la fermeture.
	local wasRewound = false
	if isAlive(boss) and not TimeLoopService.isEncounterRewinding(boss.encounterId) then
		local target = findNearestPlayer(boss)
		if target and TimeLoopService.openAnomaly(target) then
			log(boss, `anomalie ouverte sur {target.Name}`)
			wasRewound = TimeLoopService.waitForAnomalyOutcome(target) == "rewound"
		end
	end
	if wasRewound then
		-- Dès le début du rewind : l'effet de charge s'éteint chez les clients pendant que le temps recule.
		setState(boss, STATES.Staggered)
	end

	-- 3. Fin de la charge. On attend la fin d'un éventuel rewind avant de libérer le boss
	--    (ancrage compté : le rewind et la charge ne se défont pas l'un l'autre).
	waitForRewindEnd(boss)
	EncounterService.setAnomalyMood(boss.model, false) -- le danger est passé (rewind ou mort) : le ciel se rouvre
	AnchorService.release(boss.rootPart, CHARGE_ANCHOR_REASON)
	if not isAlive(boss) then
		return
	end
	claimServerOwnership(boss.rootPart)
	boss.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, false)

	-- 4. La faille : après un rewind, le boss reste sonné, vulnérable, sans attaque fatale.
	if wasRewound then
		log(boss, "sonné par le rewind")
		task.wait(Config.STAGGER_DURATION)
	end
end

--------------------------------------------------------------------------------
-- Boucle de décision
--------------------------------------------------------------------------------

local function runBoss(boss: Boss)
	while isAlive(boss) do
		local target, targetRoot, distance = findNearestPlayer(boss)
		local healthRatio = boss.humanoid.Health / boss.humanoid.MaxHealth
		local isUltimateReady = healthRatio <= Config.ULTIMATE_HEALTH_RATIO and os.clock() >= boss.ultimateReadyClock

		-- Altérations (froid, pression... : StatusService) : la vitesse de marche suit leur multiplicateur.
		local statusSpeed = boss.model:GetAttribute(STATUS_SPEED_ATTRIBUTE)
		local speedMultiplier = if type(statusSpeed) == "number" then statusSpeed else 1
		boss.humanoid.WalkSpeed = Config.WALK_SPEED * speedMultiplier

		if TimeLoopService.isEncounterRewinding(boss.encounterId) then
			-- Le temps se rembobine : le boss est entre les mains du Time-Loop, on ne décide rien.
		elseif CombatStatus.isStunned(boss.model) or speedMultiplier <= 0.05 then
			-- Paré, paralysé ou écrasé : il reste sur place, sans attaquer.
			stopMoving(boss)
		elseif target == nil or targetRoot == nil then
			-- Personne dans l'arène : il rentre à son point d'apparition et y attend.
			if (boss.rootPart.Position - boss.home).Magnitude > RETURN_HOME_DISTANCE then
				boss.humanoid:MoveTo(boss.home)
				setState(boss, STATES.Chasing)
			else
				stopMoving(boss)
				setState(boss, STATES.Idle)
			end
		elseif isUltimateReady then
			performUltimate(boss)
		elseif distance <= Config.ATTACK_RANGE then
			performAttack(boss, target, targetRoot)
		else
			chase(boss, targetRoot)
		end

		task.wait(Config.THINK_INTERVAL)
	end

	boss.model:SetAttribute(Config.STATE_ATTRIBUTE, STATES.Dead)
	boss.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, false)
	EncounterService.setAnomalyMood(boss.model, false)
	AnchorService.release(boss.rootPart, CHARGE_ANCHOR_REASON)
	EncounterService.unregisterBoss(boss.model)
	if bosses[boss.model] == boss then
		bosses[boss.model] = nil
	end
end

--------------------------------------------------------------------------------
-- Inscription des boss
--------------------------------------------------------------------------------

local function registerBoss(instance: Instance)
	-- Les tags suivent aussi les modèles rangés dans ServerStorage : on ne veut que ceux en jeu.
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or bosses[instance] then
		return
	end

	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil then
		warn(`[Boss] {instance.Name} est taggé {Config.TAG} mais n'a pas de Humanoid avec un RootPart`)
		return
	end

	humanoid.DisplayName = Config.DISPLAY_NAME
	humanoid.MaxHealth = Config.MAX_HEALTH
	humanoid.Health = Config.MAX_HEALTH
	humanoid.WalkSpeed = Config.WALK_SPEED
	-- Un rig posé dans Studio peut avoir des pièces ancrées : il ne bougerait jamais.
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	claimServerOwnership(rootPart)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end

	local boss: Boss = {
		model = instance,
		humanoid = humanoid,
		rootPart = rootPart,
		path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 6,
		}),
		walkTrack = loadTrack(animator :: Animator, Config.WALK_ANIMATION_ID, true),
		attackTrack = loadTrack(animator :: Animator, Config.ATTACK_ANIMATION_ID, false),
		nextAttackClock = 0,
		ultimateReadyClock = 0,
		home = rootPart.Position,
		encounterId = "",
	}
	bosses[instance] = boss
	instance:SetAttribute(Config.STATE_ATTRIBUTE, STATES.Idle)

	-- Un boss est une cible de combat (tag) et le cœur de sa rencontre : sa timeline enregistre sa
	-- position et ses PV, ceux des participants, et elle seule est rembobinée pendant l'anomalie.
	CollectionService:AddTag(instance, TimeLoopConfig.ENTITY_TAG)
	boss.encounterId = EncounterService.registerBoss(instance, rootPart.Position)

	task.spawn(runBoss, boss)
end

local function unregisterBoss(instance: Instance)
	if instance:IsA("Model") then
		local boss = bosses[instance]
		bosses[instance] = nil -- la boucle du boss s'arrête à sa prochaine décision (voir isAlive)
		if boss then
			AnchorService.release(boss.rootPart, CHARGE_ANCHOR_REASON)
		end
		EncounterService.unregisterBoss(instance)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function BossService.start()
	if isStarted then
		return
	end
	isStarted = true

	CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(registerBoss)
	CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(unregisterBoss)
	for _, instance in CollectionService:GetTagged(Config.TAG) do
		registerBoss(instance)
	end
end

return BossService
