--!strict
--[[
	CombatService
	Façade serveur du combat à l'épée (singleton), Combat 2.0.
		- équipe chaque personnage de son épée (Motor6D, voir SwordFactory) ;
		- valide les demandes d'attaque (RequestAttack) selon leur nature :
			1..5       coup du combo : ordre, cadence (un coup ne part pas avant la fin du précédent),
			           délai d'enchaînement (COMBO_RESET_DELAY) ;
			"charged"  frappe chargée : une charge doit avoir commencé (RequestChargeStart) ; sa
			           PUISSANCE (0..1) est calculée ICI, d'après la durée de charge vue par le serveur.
			           Pendant la charge : ralenti, ni sprint, ni parade, ni Concentration, plus de
			           dégâts reçus ; recharge CHARGE_COOLDOWN après la frappe ;
			"counter"  riposte : seulement dans la fenêtre ouverte par une parade parfaite ;
			"plunge"   attaque plongeante : seulement en l'air (raycast serveur), avec recharge ;
		- valide chaque impact signalé par le client (ReportHit) : fenêtre de frappe, cible autorisée,
		  portée (zone devant le joueur ou centrée sur lui), ligne de vue, une touche par cible et par coup ;
		- applique les dégâts (DamageService : contributions, élimination unique, garde, parade PvP),
		  la posture (PostureService), l'éjection et la Tension (ResourceService, une fois par coup).
		  C'est le SEUL endroit du jeu où un coup d'épée blesse ;
		- élan d'esquive parfaite (MOMENTUM : coups un peu plus forts quelques secondes) ;
		- déclenche le pouvoir ultime de la Magie Innée (Tension pleine, vérifiée et vidée ici).

	Le client détecte les impacts (zone de frappe, sans latence), mais il ne fait que DEMANDER :
	il n'envoie ni dégâts, ni position, ni puissance de charge, seulement « j'ai touché ce Model ».
	Le serveur ne vérifie pas l'orientation de l'attaquant (le soft-lock le tourne instantanément
	vers sa cible, rotation pas encore répliquée) : il vérifie que la cible était à portée.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local Remotes = require(ReplicatedStorage.Shared.Combat.CombatRemotes)
local SpatialHitbox = require(ReplicatedStorage.Shared.Combat.SpatialHitbox)
local TimeLoopConfig = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local DamageService = require(script.Parent.DamageService)
local MovementService = require(script.Parent.Parent.Movement.MovementService)
local ParryService = require(script.Parent.ParryService)
local PostureService = require(script.Parent.PostureService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local ResourceService = require(script.Parent.ResourceService)
local SwordFactory = require(script.Parent.SwordFactory)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)
local UltimateBehaviors = require(script.Parent.UltimateBehaviors)

-- Dernière attaque acceptée d'un joueur.
type AttackState = {
	kind: string, -- "combo" | "charged" | "counter" | "plunge"
	comboIndex: number, -- 1..5 pour le combo, 0 sinon
	step: Config.AttackStep,
	startClock: number,
	power: number, -- 0..1 (charge) ; 1 pour les autres attaques
	hitTargets: { [Model]: boolean }, -- cibles déjà touchées par cette attaque
	tensionGiven: boolean, -- la Tension n'est gagnée qu'une fois par attaque, pas par cible
}

type PlayerState = {
	attack: AttackState?,
	chargeStart: number?, -- os.clock() du début de la charge en cours
	chargeToken: number, -- identifie la charge en cours (annulation automatique)
	chargeReadyAt: number,
	plungeReadyAt: number,
	counterUntil: number,
	momentumUntil: number,
}

local HAND_READY_TIMEOUT = 10 -- secondes d'attente maximum pour qu'une main (ou son point de prise) existe
local KNOCKBACK_MAX_FORCE = 1e6 -- assez pour imposer la vitesse d'éjection malgré le Humanoid de la cible
local FULL_CHARGE_TOLERANCE = 0.1 -- s : une charge relâchée à peine avant le plein est comptée pleine
local PLUNGE_MIN_HEIGHT = 2.5 -- studs de vide sous les pieds pour accepter une plongée
local BLOCKED_POSTURE_FACTOR = 0.5 -- un coup bloqué par une garde n'entame que la moitié de la posture
local BLOCKED_TENSION_FACTOR = 0.5

local CombatService = {}

local states: { [Player]: PlayerState } = {}
local attackLimiter = RateLimiter.new(8, 10)
local hitLimiter = RateLimiter.new(30, 40) -- plusieurs cibles par coup
local chargeLimiter = RateLimiter.new(3, 4)
local ultimateLimiter = RateLimiter.new(2, 3)
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function logRejection(player: Player, reason: string)
	if Config.DEBUG_LOGS then
		print(`[Combat] Refusé pour {player.Name} : {reason}`)
	end
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if state == nil then
		state = {
			attack = nil,
			chargeStart = nil,
			chargeToken = 0,
			chargeReadyAt = 0,
			plungeReadyAt = 0,
			counterUntil = 0,
			momentumUntil = 0,
		}
		states[player] = state
	end
	return state
end

-- Retourne le Humanoid et le RootPart d'un personnage vivant, sinon nil.
local function getLivingParts(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, rootPart
end

-- Un joueur figé par un autre système (Hub, anomalie, rewind) est hors combat :
-- il ne peut ni frapper ni être frappé.
local function isOutOfCombat(player: Player): boolean
	return AvatarService.isCustomizing(player) or TimeLoopService.isInAnomaly(player) or TimeLoopService.isRewindingFor(player)
end

local function isInvulnerable(target: Model): boolean
	return target:GetAttribute(Config.INVULNERABLE_ATTRIBUTE) == true
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- L'attaque précédente est-elle terminée (à la marge de latence près) ?
local function isPreviousFinished(state: PlayerState, now: number): boolean
	local attack = state.attack
	return attack == nil or now >= attack.startClock + attack.step.duration - Config.CADENCE_TOLERANCE
end

--------------------------------------------------------------------------------
-- Épée
--------------------------------------------------------------------------------

local function equipSword(character: Model)
	local sword = SwordFactory.create()

	-- YIELD : attend que la main ait son point de prise avant d'y fixer l'épée.
	local function attachTo(hand: Instance)
		if not hand:IsA("BasePart") then
			return
		end
		hand:WaitForChild(Config.GRIP_ATTACHMENT_NAME, HAND_READY_TIMEOUT)

		-- Entre-temps la main a pu être remplacée à son tour : seule la main actuelle compte.
		if hand.Parent == character and SwordFactory.attach(sword, hand) then
			sword.Parent = character -- seulement une fois fixée : libre, elle tomberait dans le vide
		end
	end

	-- ApplyDescription remplace le RightHand quand l'avatar change de bras (et détruit avec lui
	-- le Motor6D qui y était relié) : on refixe l'épée chaque fois qu'une main droite apparaît.
	character.ChildAdded:Connect(function(child: Instance)
		if child.Name == Config.HAND_NAME then
			attachTo(child)
		end
	end)

	task.spawn(function()
		local hand = character:WaitForChild(Config.HAND_NAME, HAND_READY_TIMEOUT)
		if hand then
			attachTo(hand)
		else
			warn(`[Combat] {character.Name} n'a pas de {Config.HAND_NAME} (rig R15 requis) : pas d'épée`)
		end
	end)

	character.Destroying:Connect(function()
		sword:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Charge
--------------------------------------------------------------------------------

-- Attaque en cours (ou dernière acceptée) : nature, coup du combo, puissance. Pour les tests et le débogage.
function CombatService.getCurrentAttack(player: Player): (string?, number, number)
	local state = states[player]
	local attack = state and state.attack
	if attack == nil then
		return nil, 0, 0
	end
	return attack.kind, attack.comboIndex, attack.power
end

function CombatService.isCharging(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.chargeStart ~= nil
end

local function endCharge(player: Player, state: PlayerState)
	if state.chargeStart == nil then
		return
	end
	state.chargeStart = nil
	state.chargeToken += 1
	player:SetAttribute(Config.CHARGING_ATTRIBUTE, false)
	MovementService.refreshSpeed(player)
end

local function onChargeStartRequested(player: Player)
	if not chargeLimiter:allow(player) then
		return
	end
	local state = getState(player)
	local now = os.clock()
	if getLivingParts(player.Character) == nil or isOutOfCombat(player) then
		return
	end
	if state.chargeStart ~= nil or now < state.chargeReadyAt - Config.LATENCY_TOLERANCE then
		logRejection(player, "charge déjà en cours ou en recharge")
		return
	end
	if not isPreviousFinished(state, now) or ResourceService.isConcentrating(player) then
		logRejection(player, "charge impossible maintenant")
		return
	end

	state.chargeStart = now
	state.chargeToken += 1
	local token = state.chargeToken
	player:SetAttribute(Config.CHARGING_ATTRIBUTE, true)
	MovementService.stopSprint(player)
	MovementService.refreshSpeed(player)

	-- Charge jamais relâchée (client déconnecté, entrée perdue) : elle tombe d'elle-même.
	task.delay(Config.CHARGE_MAX_HOLD + Config.LATENCY_TOLERANCE * 2, function()
		if state.chargeToken == token and state.chargeStart ~= nil then
			endCharge(player, state)
			state.chargeReadyAt = os.clock() + Config.CHARGE_COOLDOWN * 0.5
		end
	end)
end

--------------------------------------------------------------------------------
-- Validation d'une attaque
--------------------------------------------------------------------------------

-- Vérifie qu'un coup de combo `comboIndex` est un enchaînement plausible. Retourne (ok, raison du refus).
local function isComboStepAllowed(state: PlayerState, comboIndex: number, now: number): (boolean, string)
	if not isPreviousFinished(state, now) then
		return false, "coup précédent encore en cours"
	end
	if comboIndex == 1 then
		return true, ""
	end
	local last = state.attack
	if last == nil or last.kind ~= "combo" then
		return false, "le combo doit commencer par le coup 1"
	end
	local lastEndClock = last.startClock + last.step.duration
	local isNextStep = comboIndex == last.comboIndex + 1
	local isInTime = now - lastEndClock <= Config.COMBO_RESET_DELAY + Config.LATENCY_TOLERANCE
	return isNextStep and isInTime, "enchaînement de combo invalide"
end

-- Le personnage est-il en l'air ? Raycast serveur sous ses pieds (le client simule son personnage :
-- son état Humanoid n'est pas une preuve).
local function isAirborne(character: Model, humanoid: Humanoid, rootPart: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local feet = rootPart.Size.Y / 2 + humanoid.HipHeight
	local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -(feet + PLUNGE_MIN_HEIGHT), 0), params)
	return result == nil
end

local function startAttack(player: Player, state: PlayerState, kind: string, comboIndex: number, step: Config.AttackStep, power: number)
	state.attack = {
		kind = kind,
		comboIndex = comboIndex,
		step = step,
		startClock = os.clock(),
		power = power,
		hitTargets = {},
		tensionGiven = false,
	}
	-- Les poses sont calculées par chaque client : les autres sont prévenus pour animer l'attaquant
	-- et allumer la traînée de sa lame. L'attaquant, lui, l'a déjà fait.
	local character = player.Character
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			Remotes.AttackStarted:FireClient(otherPlayer, character, comboIndex, step.action, power)
		end
	end
	if Config.DEBUG_LOGS then
		print(`[Combat] {player.Name} : {step.name}{if kind == "charged" then ` (puissance {math.floor(power * 100)} %)` else ""}`)
	end
end

local function onAttackRequested(player: Player, kind: any)
	if not attackLimiter:allow(player) then
		return
	end
	local character = player.Character
	local humanoid, rootPart = getLivingParts(character)
	if character == nil or humanoid == nil or rootPart == nil or isOutOfCombat(player) then
		logRejection(player, "joueur hors combat")
		return
	end
	local state = getState(player)
	local now = os.clock()

	if type(kind) == "number" then
		if Config.COMBO[kind] == nil then
			return
		end
		if state.chargeStart ~= nil then
			logRejection(player, "coup de combo pendant une charge")
			return
		end
		local isAllowed, reason = isComboStepAllowed(state, kind, now)
		if not isAllowed then
			logRejection(player, reason)
			return
		end
		startAttack(player, state, "combo", kind, Config.COMBO[kind], 1)
	elseif kind == "charged" then
		local chargeStart = state.chargeStart
		if chargeStart == nil then
			logRejection(player, "frappe chargée sans charge")
			return
		end
		local held = now - chargeStart
		endCharge(player, state)
		local power = if held >= Config.CHARGE_FULL_TIME - FULL_CHARGE_TOLERANCE then 1 else math.clamp(held / Config.CHARGE_FULL_TIME, 0, 1)
		state.chargeReadyAt = now + Config.CHARGE_COOLDOWN
		startAttack(player, state, "charged", 0, Config.CHARGED, power)
	elseif kind == "counter" then
		if now > state.counterUntil + Config.LATENCY_TOLERANCE then
			logRejection(player, "riposte hors de la fenêtre de parade")
			return
		end
		state.counterUntil = 0
		player:SetAttribute(Config.COUNTER_ATTRIBUTE, 0)
		endCharge(player, state)
		startAttack(player, state, "counter", 0, Config.COUNTER, 1)
	elseif kind == "plunge" then
		if now < state.plungeReadyAt - Config.LATENCY_TOLERANCE or not isPreviousFinished(state, now) then
			logRejection(player, "plongée en recharge")
			return
		end
		if not isAirborne(character, humanoid, rootPart) then
			logRejection(player, "plongée demandée au sol")
			return
		end
		state.plungeReadyAt = now + Config.PLUNGE_COOLDOWN
		endCharge(player, state)
		startAttack(player, state, "plunge", 0, Config.PLUNGE, 1)
	end
end

--------------------------------------------------------------------------------
-- Validation d'un impact
--------------------------------------------------------------------------------

-- Une cible valide est un ennemi blessable (PNJ taggé, vivant, pas encore éliminé), ou le personnage
-- d'un autre joueur si le PvP est actif. Une cible invulnérable (boss en charge) est épargnée.
-- (Le dash et la parade d'un joueur ciblé sont gérés par DamageService.damagePlayer.)
local function isTargetAllowed(target: Model): boolean
	if isInvulnerable(target) then
		return false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer then
		return Config.PVP_ENABLED and not isOutOfCombat(targetPlayer)
	end
	return DamageService.isDamageableEnemy(target)
end

-- Taille de la zone de frappe d'une attaque (identique côté client : CombatController).
local function getHitboxSize(step: Config.AttackStep): Vector3
	return Config.HITBOX_SIZE + Vector3.new(step.widthBonus, 0, step.reachBonus)
end
CombatService.getHitboxSize = getHitboxSize

-- Distance maximale (studs) entre l'attaquant et le bord d'une cible pour qu'elle ait pu se trouver
-- dans la zone de frappe : le coin le plus éloigné de la boîte, plus la marge du serveur.
local function getMaxHitDistance(step: Config.AttackStep): number
	local size = getHitboxSize(step)
	local halfWidth = size.X / 2
	local depth = if step.centered then size.Z / 2 else size.Z
	return math.sqrt(depth * depth + halfWidth * halfWidth) + Config.HITBOX_RANGE_TOLERANCE
end

-- Distance mesurée jusqu'au bord de la cible (et non son centre), pour rester juste face à un gros boss.
local function isInRange(attackerRoot: BasePart, target: Model, targetRoot: BasePart, maxDistance: number): boolean
	local extents = target:GetExtentsSize()
	local targetRadius = math.max(extents.X, extents.Z) / 2
	local distance = (targetRoot.Position - attackerRoot.Position).Magnitude - targetRadius
	return distance <= maxDistance
end

-- Raycast serveur attaquant -> cible : aucun élément de décor solide ne doit les séparer.
local function hasLineOfSight(attacker: Model, attackerRoot: BasePart, target: Model, targetRoot: BasePart): boolean
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { attacker, target }
	raycastParams.RespectCanCollide = true

	local result = workspace:Raycast(attackerRoot.Position, targetRoot.Position - attackerRoot.Position, raycastParams)
	-- Un autre personnage sur la trajectoire ne protège pas la cible : seul le décor compte.
	return result == nil or SpatialHitbox.getCharacterFromPart(result.Instance) ~= nil
end

-- Éjecte `targetRoot` à l'opposé de l'attaquant : une LinearVelocity posée par le serveur le
-- temps de KNOCKBACK_DURATION. Elle agit aussi sur un joueur, dont le client simule la physique
-- (la contrainte lui est répliquée).
local function applyKnockback(attackerRoot: BasePart, targetRoot: BasePart, speed: number)
	if targetRoot.Anchored then
		return
	end

	local direction = (targetRoot.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = attackerRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = targetRoot

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "KnockbackVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = direction.Unit * speed + Vector3.new(0, Config.KNOCKBACK_LIFT, 0)
	velocity.MaxForce = KNOCKBACK_MAX_FORCE
	velocity.Parent = targetRoot

	Debris:AddItem(velocity, Config.KNOCKBACK_DURATION)
	Debris:AddItem(attachment, Config.KNOCKBACK_DURATION)
end

-- Valeurs effectives d'une attaque : la charge interpole entre la frappe minimale et maximale.
local function resolveStrike(attack: AttackState, state: PlayerState): (number, number, number, boolean)
	local step = attack.step
	local damage, posture, knockback, heavy = step.damage, step.posture, step.knockback, step.heavy
	if attack.kind == "charged" then
		local power = attack.power
		damage = lerp(step.damage, Config.CHARGE_MAX_DAMAGE, power)
		posture = lerp(step.posture, Config.CHARGE_MAX_POSTURE, power)
		knockback = lerp(step.knockback, Config.CHARGE_MAX_KNOCKBACK, power)
		heavy = power >= 1 -- seule une charge pleine brise les gardes frontales
	end
	if os.clock() < state.momentumUntil then
		damage *= Config.MOMENTUM_DAMAGE
	end
	return damage, posture, knockback, heavy
end

local function onHitReported(player: Player, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not hitLimiter:allow(player) then
		return
	end

	local state = getState(player)
	local attack = state.attack
	local attacker = player.Character
	local _, attackerRoot = getLivingParts(attacker)
	if attack == nil or attacker == nil or attackerRoot == nil or isOutOfCombat(player) then
		return
	end

	-- 1. Le coup doit être dans sa fenêtre de frappe.
	local step = attack.step
	local elapsed = os.clock() - attack.startClock
	if elapsed < step.hitStart - Config.LATENCY_TOLERANCE or elapsed > step.hitEnd + Config.LATENCY_TOLERANCE then
		logRejection(player, "impact hors de la fenêtre de frappe")
		return
	end

	-- 2. La cible doit être légitime, vivante, et pas encore touchée par ce coup.
	local targetHumanoid, targetRoot = getLivingParts(target)
	if
		target == attacker
		or attack.hitTargets[target]
		or targetHumanoid == nil
		or targetRoot == nil
		or not isTargetAllowed(target)
	then
		return
	end

	-- 3. La géométrie doit rendre l'impact possible.
	if not isInRange(attackerRoot, target, targetRoot, getMaxHitDistance(step)) then
		logRejection(player, "cible hors de portée")
		return
	end
	if not hasLineOfSight(attacker, attackerRoot, target, targetRoot) then
		logRejection(player, "cible derrière un obstacle")
		return
	end

	attack.hitTargets[target] = true
	local damage, posture, knockback, heavy = resolveStrike(attack, state)
	local source: DamageService.DamageSource = {
		player = player,
		model = attacker,
		kind = "melee",
		heavy = heavy,
	}

	local applied = 0
	local isBroken = false
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer then
		-- PvP : dash, parade et immunités du défenseur sont arbitrés par DamageService (peut yield).
		local result, dealt = DamageService.damagePlayer(targetPlayer, damage, source)
		if result ~= "hit" then
			logRejection(player, `coup sur {targetPlayer.Name} : {result}`)
			return
		end
		applied = dealt
	else
		applied = DamageService.dealDamage(target, damage, source)
	end
	local isBlocked = source.blocked == true
	if applied <= 0 and not isBlocked then
		return -- cible éliminée entre-temps, immunisée... : ni Tension ni éjection
	end

	-- Posture (ennemis seulement), puis éjection si la garde n'a pas tenu.
	if targetPlayer == nil and targetHumanoid.Health > 0 and posture > 0 then
		isBroken = PostureService.damage(target, posture * (if isBlocked then BLOCKED_POSTURE_FACTOR else 1), player)
	end
	if knockback > 0 and not isBlocked and targetHumanoid.Health > 0 then
		applyKnockback(attackerRoot, targetRoot, knockback)
	end

	-- Tension : une fois par attaque (frapper un groupe ne remplit pas la jauge d'un coup).
	if not attack.tensionGiven then
		attack.tensionGiven = true
		local scale = if attack.kind == "charged" and attack.power >= 1 then 1.5 else 1
		if isBlocked then
			scale *= BLOCKED_TENSION_FACTOR
		end
		ResourceService.addTension(player, step.tension, scale)
	end
	if isBroken then
		ResourceService.addTension(player, "postureBreak")
	end

	local result = if isBroken then "broken" elseif isBlocked then "blocked" else "hit"
	Remotes.HitConfirmed:FireAllClients(attacker, target, applied, result, step.hitStop)

	if Config.DEBUG_LOGS then
		print(`[Combat] {player.Name} touche {target.Name} ({step.name}, {result}) : -{math.floor(applied * 10) / 10} PV (reste {math.floor(targetHumanoid.Health)})`)
	end
end

--------------------------------------------------------------------------------
-- Parade parfaite et esquive parfaite
--------------------------------------------------------------------------------

local function onParried(player: Player, attacker: Model?)
	local state = getState(player)
	state.counterUntil = os.clock() + Config.COUNTER_WINDOW
	player:SetAttribute(Config.COUNTER_ATTRIBUTE, workspace:GetServerTimeNow() + Config.COUNTER_WINDOW)
	if attacker and Players:GetPlayerFromCharacter(attacker) == nil then
		PostureService.damage(attacker, Config.POSTURE.PARRY_DAMAGE, player)
	end
end

local function onDodged(player: Player, isPerfect: boolean)
	if not isPerfect then
		return
	end
	getState(player).momentumUntil = os.clock() + Config.MOMENTUM_DURATION
	player:SetAttribute(Config.MOMENTUM_ATTRIBUTE, workspace:GetServerTimeNow() + Config.MOMENTUM_DURATION)
end

--------------------------------------------------------------------------------
-- Pouvoir ultime
--------------------------------------------------------------------------------

-- Tous les ennemis blessables (vivants, pas éliminés, pas invulnérables) à moins de `radius` studs de `origin`.
local function findUltimateTargets(origin: Vector3, radius: number): { Model }
	local targets = {}
	for _, instance in CollectionService:GetTagged(TimeLoopConfig.ENTITY_TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) and DamageService.isDamageableEnemy(instance) then
			local _, rootPart = getLivingParts(instance)
			if rootPart and (rootPart.Position - origin).Magnitude <= radius then
				table.insert(targets, instance)
			end
		end
	end
	return targets
end

local function onUltimateRequested(player: Player)
	if not ultimateLimiter:allow(player) then
		return
	end
	local caster = player.Character
	local _, casterRoot = getLivingParts(caster)
	if caster == nil or casterRoot == nil or isOutOfCombat(player) then
		logRejection(player, "ultime demandé hors combat")
		return
	end
	-- La jauge est vérifiée ET vidée d'un seul geste : deux demandes rapprochées ne donnent qu'un ultime.
	if not ResourceService.spendTension(player, Config.TENSION_MAX) then
		logRejection(player, "ultime demandé sans Tension pleine")
		return
	end
	endCharge(player, getState(player))

	-- L'ultime est celui de la Magie Innée du joueur : l'attribut est écrit par AvatarService,
	-- côté serveur, donc le client ne peut pas s'en attribuer une autre.
	local magic = MagicConfig.getById(player:GetAttribute(MagicConfig.ATTRIBUTE))
	local origin = casterRoot.Position
	local targets = findUltimateTargets(origin, magic.radius)
	Remotes.UltimateFired:FireAllClients(caster, origin, targets, magic.id)

	if Config.DEBUG_LOGS then
		print(`[Combat] {player.Name} déclenche {magic.ultimateName} : {#targets} cible(s)`)
	end

	-- Les dégâts tombent à la fin de l'arrêt sur image des clients, quand l'onde de choc part.
	task.wait(Config.ULTIMATE_HIT_STOP)
	if TimeLoopService.isRewindingFor(player) or isOutOfCombat(player) or getLivingParts(caster) == nil then
		return -- rembobinage, anomalie ou mort du lanceur entre-temps : l'explosion n'a "pas eu lieu"
	end
	local damageDealt = 0
	local source: DamageService.DamageSource = { player = player, model = caster, kind = "ultimate", element = magic.id }
	for _, target in targets do
		-- DamageService revérifie tout (éliminé, devenu invulnérable pendant l'arrêt sur image...).
		damageDealt += DamageService.dealDamage(target, magic.damage, source)
	end

	-- Effet propre à la magie (implosion, brûlure, paralysie, gel, drain) : voir UltimateBehaviors.
	local casterHumanoid = getLivingParts(caster)
	if casterHumanoid then
		task.spawn(UltimateBehaviors.run, {
			caster = player,
			casterHumanoid = casterHumanoid,
			origin = origin,
			targets = targets,
			magic = magic,
			damageDealt = damageDealt,
		})
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie des joueurs
--------------------------------------------------------------------------------

local function resetPlayer(player: Player)
	local state = getState(player)
	endCharge(player, state)
	state.attack = nil
	state.counterUntil = 0
	state.momentumUntil = 0
	player:SetAttribute(Config.CHARGING_ATTRIBUTE, false)
	player:SetAttribute(Config.COUNTER_ATTRIBUTE, 0)
	player:SetAttribute(Config.MOMENTUM_ATTRIBUTE, 0)
end

local function onPlayerAdded(player: Player)
	resetPlayer(player)
	player.CharacterAdded:Connect(function(character: Model)
		resetPlayer(player)
		equipSword(character)
	end)
	if player.Character then
		equipSword(player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur (après ResourceService et PostureService).
function CombatService.start()
	if isStarted then
		return
	end
	isStarted = true

	Remotes.RequestAttack.OnServerEvent:Connect(onAttackRequested)
	Remotes.RequestChargeStart.OnServerEvent:Connect(onChargeStartRequested)
	Remotes.ReportHit.OnServerEvent:Connect(onHitReported)
	Remotes.RequestUltimate.OnServerEvent:Connect(onUltimateRequested)

	ParryService.Parried:Connect(onParried)
	DamageService.Dodged:Connect(onDodged)

	-- Contreparties de la charge : ralenti, ni sprint, ni parade, ni Concentration, plus vulnérable.
	MovementService.addSpeedProvider(function(player: Player): number
		return if CombatService.isCharging(player) then Config.CHARGE_MOVE_MULTIPLIER else 1
	end)
	MovementService.addSprintBlocker(CombatService.isCharging)
	ParryService.addBlocker(CombatService.isCharging)
	ResourceService.addConcentrationBlocker(CombatService.isCharging)
	DamageService.addPlayerModifier(function(player: Player, amount: number): number
		return if CombatService.isCharging(player) then amount * Config.CHARGE_DAMAGE_TAKEN else amount
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CombatService
