--!strict
--[[
	CombatService
	Façade serveur du combat (singleton).
		- équipe chaque personnage de son épée (Motor6D, voir SwordFactory) ;
		- valide les demandes d'attaque : état du joueur, ordre et cadence du combo ;
		- valide chaque impact signalé par le client : fenêtre de frappe, cible autorisée, distance,
		  ligne de vue (raycast serveur), une seule touche par cible et par coup ;
		- applique les dégâts (via DamageService : contributions, élimination unique, parade en PvP)
		  et l'éjection. C'est le SEUL endroit du jeu où un coup d'épée blesse ;
		- tient la Tension de chaque joueur (gagnée à chaque impact validé) et déclenche le pouvoir
		  ultime de sa Magie Innée : jauge vérifiée ici, vidée ici, dégâts de zone infligés ici.

	Le client détecte les impacts (zone de frappe devant lui, sans latence), mais il ne fait que
	DEMANDER : il n'envoie ni dégâts ni position, seulement "j'ai touché ce Model".

	Le serveur ne vérifie pas l'orientation de l'attaquant : avec le soft-lock, il se tourne
	instantanément vers sa cible, et cette rotation n'est pas encore répliquée quand l'impact
	arrive. Ce qui compte, et qui est vérifié, c'est que la cible soit à portée de sa zone de frappe.
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
local SwordFactory = require(script.Parent.SwordFactory)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)
local UltimateBehaviors = require(script.Parent.UltimateBehaviors)

-- Dernier coup accepté d'un joueur.
type AttackState = {
	comboIndex: number,
	startClock: number,
	hitTargets: { [Model]: boolean }, -- cibles déjà blessées par ce coup
}

local HAND_READY_TIMEOUT = 10 -- secondes d'attente maximum pour qu'une main (ou son point de prise) existe
local KNOCKBACK_MAX_FORCE = 1e6 -- assez pour imposer la vitesse d'éjection malgré le Humanoid de la cible

local CombatService = {}

local attacks: { [Player]: AttackState } = {}
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function logRejection(player: Player, reason: string)
	if Config.DEBUG_LOGS then
		print(`[Combat] Refusé pour {player.Name} : {reason}`)
	end
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

--------------------------------------------------------------------------------
-- Tension
--------------------------------------------------------------------------------
-- La Tension vit dans un attribut du Player : écrite ici, répliquée automatiquement au client
-- pour sa jauge. Une modification faite par un client reste chez lui, le serveur ne la voit pas.

local function getTension(player: Player): number
	local tension = player:GetAttribute(Config.TENSION_ATTRIBUTE)
	return if type(tension) == "number" then tension else 0
end

local function setTension(player: Player, tension: number)
	player:SetAttribute(Config.TENSION_ATTRIBUTE, math.clamp(tension, 0, Config.TENSION_MAX))
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
-- Validation d'une attaque
--------------------------------------------------------------------------------

-- Vérifie que `comboIndex` est un enchaînement plausible après `last`. Retourne (ok, raison du refus).
local function isComboStepAllowed(last: AttackState?, comboIndex: number, now: number): (boolean, string)
	if last == nil then
		return comboIndex == 1, "le combo doit commencer par le coup 1"
	end

	local lastEndClock = last.startClock + Config.COMBO[last.comboIndex].duration
	if now < lastEndClock - Config.LATENCY_TOLERANCE then
		return false, "coup précédent encore en cours"
	end
	if comboIndex == 1 then
		return true, ""
	end

	local isNextStep = comboIndex == last.comboIndex + 1
	local isInTime = now - lastEndClock <= Config.COMBO_RESET_DELAY + Config.LATENCY_TOLERANCE
	return isNextStep and isInTime, "enchaînement de combo invalide"
end

local function onAttackRequested(player: Player, comboIndex: any)
	if type(comboIndex) ~= "number" or Config.COMBO[comboIndex] == nil then
		return
	end

	local character = player.Character
	if getLivingParts(character) == nil or isOutOfCombat(player) then
		logRejection(player, "joueur hors combat")
		return
	end

	local now = os.clock()
	local isAllowed, reason = isComboStepAllowed(attacks[player], comboIndex, now)
	if not isAllowed then
		logRejection(player, reason)
		return
	end

	attacks[player] = {
		comboIndex = comboIndex,
		startClock = now,
		hitTargets = {},
	}

	-- L'animation de l'attaquant est répliquée par Roblox, mais pas ses VFX (traînée de lame) :
	-- les autres clients sont prévenus pour les jouer chez eux. L'attaquant, lui, l'a déjà fait.
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			Remotes.AttackStarted:FireClient(otherPlayer, character, comboIndex)
		end
	end

	if Config.DEBUG_LOGS then
		print(`[Combat] {player.Name} lance le coup {comboIndex} ({Config.COMBO[comboIndex].name})`)
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

-- Distance maximale (studs) entre l'attaquant et le bord d'une cible pour qu'elle ait pu se trouver
-- dans la zone de frappe de ce coup : le coin le plus éloigné de la boîte, plus la marge du serveur.
local function getMaxHitDistance(step: Config.ComboStep): number
	local halfWidth = Config.HITBOX_SIZE.X / 2
	local depth = Config.HITBOX_SIZE.Z + step.reachBonus
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

local function onHitReported(player: Player, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end

	local attack = attacks[player]
	local attacker = player.Character
	local _, attackerRoot = getLivingParts(attacker)
	if attack == nil or attacker == nil or attackerRoot == nil or isOutOfCombat(player) then
		return
	end

	-- 1. Le coup doit être dans sa fenêtre de frappe.
	local step = Config.COMBO[attack.comboIndex]
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
	local source: DamageService.DamageSource = {
		player = player,
		model = attacker,
		kind = "melee",
		heavy = step.knockback > 0, -- le coup final du combo brise les gardes
	}

	local applied = 0
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer then
		-- PvP : dash, parade et immunités du défenseur sont arbitrés par DamageService (peut yield).
		local result, damage = DamageService.damagePlayer(targetPlayer, step.damage, source)
		if result ~= "hit" then
			logRejection(player, `coup sur {targetPlayer.Name} : {result}`)
			return
		end
		applied = damage
	else
		applied = DamageService.dealDamage(target, step.damage, source)
	end
	if applied <= 0 then
		return -- garde intégrale, cible éliminée entre-temps... : ni Tension ni éjection
	end

	if step.knockback > 0 and targetHumanoid.Health > 0 then
		applyKnockback(attackerRoot, targetRoot, step.knockback)
	end
	setTension(player, getTension(player) + Config.TENSION_PER_HIT)
	Remotes.HitConfirmed:FireAllClients(attacker, target, applied)

	if Config.DEBUG_LOGS then
		print(`[Combat] {player.Name} touche {target.Name} : -{applied} PV (reste {targetHumanoid.Health})`)
	end
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
	local caster = player.Character
	local _, casterRoot = getLivingParts(caster)
	if caster == nil or casterRoot == nil or isOutOfCombat(player) then
		logRejection(player, "ultime demandé hors combat")
		return
	end
	if getTension(player) < Config.TENSION_MAX then
		logRejection(player, "ultime demandé sans Tension pleine")
		return
	end

	-- La jauge est vidée AVANT tout le reste : deux demandes rapprochées ne donnent qu'un ultime.
	setTension(player, 0)

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
	local source: DamageService.DamageSource = { player = player, model = caster, kind = "ultimate" }
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

local function onPlayerAdded(player: Player)
	setTension(player, 0)

	player.CharacterAdded:Connect(function(character: Model)
		attacks[player] = nil
		setTension(player, 0) -- la Tension accumulée est perdue à la mort
		equipSword(character)
	end)
	if player.Character then
		equipSword(player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	attacks[player] = nil
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function CombatService.start()
	if isStarted then
		return
	end
	isStarted = true

	Remotes.RequestAttack.OnServerEvent:Connect(onAttackRequested)
	Remotes.ReportHit.OnServerEvent:Connect(onHitReported)
	Remotes.RequestUltimate.OnServerEvent:Connect(onUltimateRequested)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CombatService
