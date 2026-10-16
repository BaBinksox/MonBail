--!strict
--[[
	StatusService
	Le système COMMUN des altérations d'état (voir StatusConfig), utilisé par les sorts (SpellService)
	et les ultimes (UltimateBehaviors). Le serveur seul les pose, les fait vivre et les retire :
		- durée maximale, intensité, empilement (rafraîchir / cumuler), une altération par cible
		  quel que soit le nombre de joueurs qui l'alimentent (attribuée au dernier) ;
		- boss (durée réduite, immunité ou conversion), élites (durée réduite) ;
		- contrôles durs à rendement décroissant (jamais de verrouillage permanent) ;
		- vitesse : multiplicateur publié sur le Model (EnemyBrain et le boss l'appliquent), et
		  fournisseur de vitesse pour les personnages des joueurs (MovementService) ;
		- dégâts périodiques (brûlure, drain) via DamageService : contributions et élimination unique,
		  donc jamais de récompense en double ; le drain soigne le joueur source ;
		- électrisation : interrompt l'action ennemie en préparation (micro-étourdissement, limité
		  sur un boss) ; aspiration : déplacement bref et borné vers un point ;
		- RÉACTIONS élémentaires (tryReaction) : consomment l'altération présente, dégâts et posture
		  bonus, Tension « elementalReaction » au joueur qui les déclenche ;
		- nettoyage à la mort, à la disparition et au rembobinage (TimeLoopService.Rewound).

	API :
		StatusService.apply(target, statusId, options?) -> boolean
			options : source (Player), duration, stacks, center (Vector3, aspiration)
		StatusService.has(target, statusId) -> boolean      StatusService.getLevel(target, statusId) -> number
		StatusService.remove(target, statusId)              StatusService.clear(target)
		StatusService.getSpeedMultiplier(target) -> number
		StatusService.tryReaction(target, element, hitDamage, player?) -> string?   (id de la réaction)
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Combat.StatusConfig)
local SpellRemotes = require(ReplicatedStorage.Shared.Magic.SpellRemotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local CombatStatus = require(script.Parent.CombatStatus)
local DamageService = require(script.Parent.DamageService)
local MovementService = require(script.Parent.Parent.Movement.MovementService)
local PostureService = require(script.Parent.PostureService)
local ResourceService = require(script.Parent.ResourceService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

export type ApplyOptions = {
	source: Player?,
	duration: number?,
	stacks: number?,
	center: Vector3?,
}

type ActiveStatus = {
	id: string,
	level: number,
	untilClock: number,
	source: Player?,
	nextTick: number,
}

type TargetState = {
	statuses: { [string]: ActiveStatus },
	controlTimes: { number }, -- applications récentes de contrôles durs (rendement décroissant)
	lastReactionClock: number,
	lastInterruptClock: number,
	speed: number,
	connections: { RBXScriptConnection },
}

local StatusService = {}
StatusService.Applied = Signal.new() -- (target, statusId, source: Player?)
StatusService.Removed = Signal.new() -- (target, statusId)
StatusService.Reacted = Signal.new() -- (target, reactionId, player: Player?)

local targets: { [Model]: TargetState } = {}
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getHumanoid(target: Model): Humanoid?
	return target:FindFirstChildOfClass("Humanoid")
end

local function isAlive(target: Model): boolean
	local humanoid = getHumanoid(target)
	return humanoid ~= nil and humanoid.Health > 0 and target:IsDescendantOf(workspace) and target:GetAttribute(DamageService.DEFEATED_ATTRIBUTE) ~= true
end

local function isBoss(target: Model): boolean
	return CollectionService:HasTag(target, BossConfig.TAG)
end

local function attributeName(statusId: string): string
	return Config.ATTRIBUTE_PREFIX .. statusId
end

local function publish(target: Model, active: ActiveStatus?, statusId: string)
	if active then
		target:SetAttribute(attributeName(statusId), workspace:GetServerTimeNow() + (active.untilClock - os.clock()))
		target:SetAttribute(attributeName(statusId) .. "Level", active.level)
	else
		target:SetAttribute(attributeName(statusId), nil)
		target:SetAttribute(attributeName(statusId) .. "Level", nil)
	end
end

local function refreshSpeed(target: Model, state: TargetState)
	local speed = 1
	for id, active in state.statuses do
		local def = Config.STATUSES[id]
		if def and def.speedMultiplier then
			local value = def.speedMultiplier - (active.level - 1) * (def.speedPerStack or 0)
			speed *= math.max(0, value)
		end
	end
	speed = math.clamp(speed, 0, 2)
	if math.abs(speed - state.speed) < 1e-3 then
		return
	end
	state.speed = speed
	target:SetAttribute(Config.SPEED_ATTRIBUTE, if math.abs(speed - 1) < 1e-3 then nil else speed)
	local player = Players:GetPlayerFromCharacter(target)
	if player then
		MovementService.refreshSpeed(player)
	end
end

local function removeState(target: Model)
	local state = targets[target]
	if state == nil then
		return
	end
	targets[target] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
	for id in state.statuses do
		publish(target, nil, id)
		StatusService.Removed:Fire(target, id)
	end
	target:SetAttribute(Config.SPEED_ATTRIBUTE, nil)
	local player = Players:GetPlayerFromCharacter(target)
	if player then
		MovementService.refreshSpeed(player)
	end
end

local function getState(target: Model): TargetState
	local state = targets[target]
	if state then
		return state
	end
	local newState: TargetState = {
		statuses = {},
		controlTimes = {},
		lastReactionClock = -math.huge,
		lastInterruptClock = -math.huge,
		speed = 1,
		connections = {},
	}
	targets[target] = newState
	local humanoid = getHumanoid(target)
	if humanoid then
		table.insert(newState.connections, humanoid.Died:Connect(function()
			removeState(target)
		end))
	end
	table.insert(newState.connections, target.AncestryChanged:Connect(function()
		if not target:IsDescendantOf(workspace) then
			removeState(target)
		end
	end))
	return newState
end

-- Aspiration : une poussée brève et bornée vers `center` (rien ne traverse les murs : c'est la
-- physique qui déplace la cible).
local function pullTowards(target: Model, center: Vector3, duration: number)
	local humanoid = getHumanoid(target)
	local rootPart = humanoid and humanoid.RootPart
	if rootPart == nil or rootPart.Anchored then
		return
	end
	local offset = (center - rootPart.Position) * Vector3.new(1, 0, 1)
	local distance = offset.Magnitude
	if distance <= Config.PULL_STOP_DISTANCE then
		return
	end
	local speed = math.min(Config.PULL_SPEED, (distance - Config.PULL_STOP_DISTANCE) / math.max(duration, 0.1))
	local attachment = Instance.new("Attachment")
	attachment.Name = "StatusPullAttachment"
	attachment.Parent = rootPart
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "StatusPullVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = offset.Unit * speed
	velocity.MaxForce = 1e6
	velocity.Parent = rootPart
	Debris:AddItem(velocity, duration)
	Debris:AddItem(attachment, duration)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StatusService.has(target: Model, statusId: string): boolean
	local state = targets[target]
	local active = state and state.statuses[statusId]
	return active ~= nil and os.clock() < active.untilClock
end

function StatusService.getLevel(target: Model, statusId: string): number
	local state = targets[target]
	local active = state and state.statuses[statusId]
	return if active and os.clock() < active.untilClock then active.level else 0
end

function StatusService.getSpeedMultiplier(target: Model): number
	local state = targets[target]
	return if state then state.speed else 1
end

function StatusService.remove(target: Model, statusId: string)
	local state = targets[target]
	if state == nil or state.statuses[statusId] == nil then
		return
	end
	state.statuses[statusId] = nil
	publish(target, nil, statusId)
	refreshSpeed(target, state)
	StatusService.Removed:Fire(target, statusId)
end

function StatusService.clear(target: Model)
	removeState(target)
end

-- Pose (ou renforce) l'altération `statusId` sur `target`. Retourne true si elle a pris.
function StatusService.apply(target: Model, statusId: string, options: ApplyOptions?): boolean
	local opts: ApplyOptions = options or {}
	local def = Config.STATUSES[statusId]
	if def == nil or not isAlive(target) or target:GetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE) == true then
		return false
	end

	local duration = math.min(opts.duration or def.maxDuration, def.maxDuration)
	if isBoss(target) then
		if def.bossConvertTo then
			local converted = Config.STATUSES[def.bossConvertTo]
			if converted == nil then
				return false
			end
			def = converted
			duration = converted.maxDuration
		end
		duration *= def.bossDuration
		if duration <= 0 then
			return false -- immunité du boss
		end
	elseif target:GetAttribute(DamageService.ELITE_ATTRIBUTE) == true then
		duration *= Config.ELITE_DURATION
	end

	local state = getState(target)
	local now = os.clock()
	if def.hardControl then
		local recent = {}
		for _, clock in state.controlTimes do
			if now - clock < Config.DR_WINDOW then
				table.insert(recent, clock)
			end
		end
		state.controlTimes = recent
		if #recent >= 2 then
			return false -- rendement décroissant : la cible résiste
		elseif #recent == 1 then
			duration *= Config.DR_FACTOR
		end
		table.insert(state.controlTimes, now)
	end

	local id = def.id
	local existing = state.statuses[id]
	local active: ActiveStatus
	if existing and now < existing.untilClock then
		active = existing
		if def.stacking == "stack" then
			active.level = math.min(active.level + (opts.stacks or 1), def.maxStacks)
			active.untilClock = now + duration
		else
			active.untilClock = math.max(active.untilClock, now + duration)
		end
		active.source = opts.source or active.source
	else
		active = {
			id = id,
			level = math.clamp(opts.stacks or 1, 1, def.maxStacks),
			untilClock = now + duration,
			source = opts.source,
			nextTick = now + (def.tickInterval or math.huge),
		}
		state.statuses[id] = active
	end

	publish(target, active, id)
	refreshSpeed(target, state)
	if def.stun then
		CombatStatus.stun(target, duration)
	end
	if id == "shock" then
		-- Interrompt l'action en préparation ; un boss ne se laisse pas interrompre en boucle.
		if not isBoss(target) or now - state.lastInterruptClock >= Config.BOSS_INTERRUPT_COOLDOWN then
			state.lastInterruptClock = now
			CombatStatus.stun(target, Config.SHOCK_INTERRUPT_STUN)
		end
	elseif id == "pull" and opts.center then
		pullTowards(target, opts.center, duration)
	end
	StatusService.Applied:Fire(target, id, opts.source)
	return true
end

-- Réaction élémentaire : un coup de l'élément `element` sur une cible qui porte une altération
-- compatible. À appeler AVANT de poser les altérations du coup. Retourne l'id de la réaction.
function StatusService.tryReaction(target: Model, element: string, hitDamage: number, player: Player?): string?
	local state = targets[target]
	if state == nil or not isAlive(target) then
		return nil
	end
	local now = os.clock()
	if now - state.lastReactionClock < Config.REACTION_COOLDOWN then
		return nil
	end
	for _, reaction in Config.REACTIONS do
		if reaction.trigger == element then
			for _, consumed in reaction.consumes do
				if StatusService.has(target, consumed) then
					state.lastReactionClock = now
					StatusService.remove(target, consumed)
					local character = player and player.Character
					local source: DamageService.DamageSource = { player = player, model = character, kind = "reaction", element = element }
					DamageService.dealDamage(target, reaction.bonusDamage + hitDamage * reaction.bonusDamageRatio, source)
					if isAlive(target) then
						if reaction.posture > 0 then
							PostureService.damage(target, reaction.posture, player)
						end
						if reaction.stun > 0 then
							CombatStatus.stun(target, reaction.stun)
						end
					end
					if player then
						ResourceService.addTension(player, "elementalReaction")
					end
					local humanoid = getHumanoid(target)
					local rootPart = humanoid and humanoid.RootPart
					SpellRemotes.ReactionTriggered:FireAllClients(target, reaction.id, if rootPart then rootPart.Position else target:GetPivot().Position)
					StatusService.Reacted:Fire(target, reaction.id, player)
					if CombatConfig.DEBUG_LOGS then
						print(`[Statuts] Réaction {reaction.name} sur {target.Name}`)
					end
					return reaction.id
				end
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Boucle : expirations et dégâts périodiques
--------------------------------------------------------------------------------

local function step()
	local now = os.clock()
	for target, state in targets do
		if not isAlive(target) then
			removeState(target)
			continue
		end
		local changed = false
		for id, active in state.statuses do
			local def = Config.STATUSES[id]
			if def == nil or now >= active.untilClock then
				state.statuses[id] = nil
				publish(target, nil, id)
				StatusService.Removed:Fire(target, id)
				changed = true
			elseif def.tickInterval and def.tickDamage and now >= active.nextTick then
				active.nextTick += def.tickInterval
				local source = active.source
				local isPaused = source ~= nil and TimeLoopService.isRewindingFor(source)
				if not isPaused and Players:GetPlayerFromCharacter(target) == nil then
					local character = source and source.Character
					local damageSource: DamageService.DamageSource = { player = source, model = character, kind = "status", element = def.element }
					local applied = DamageService.dealDamage(target, def.tickDamage * active.level, damageSource)
					if applied > 0 and def.healSourceRatio and character then
						local humanoid = getHumanoid(character)
						if humanoid and humanoid.Health > 0 then
							humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + applied * def.healSourceRatio)
						end
					end
				end
			end
		end
		if changed then
			refreshSpeed(target, state)
		end
		if next(state.statuses) == nil then
			removeState(target)
		end
	end
end

function StatusService.start()
	if isStarted then
		return
	end
	isStarted = true

	-- Joueurs : vitesse (voile) et dégâts reçus (voile) selon leurs altérations.
	MovementService.addSpeedProvider(function(player: Player): number
		local character = player.Character
		return if character then StatusService.getSpeedMultiplier(character) else 1
	end)
	DamageService.addPlayerModifier(function(player: Player, amount: number): number
		local character = player.Character
		local state = character and targets[character]
		if state == nil then
			return amount
		end
		local now = os.clock()
		for id, active in state.statuses do
			local def = Config.STATUSES[id]
			if def and def.damageTakenMultiplier and now < active.untilClock then
				amount *= def.damageTakenMultiplier
			end
		end
		return amount
	end)

	-- Le rembobinage efface les altérations des personnages et joueurs concernés.
	TimeLoopService.Rewound:Connect(function(_timelineId: string, characters: { Model }, members: { Player })
		for _, character in characters do
			removeState(character)
		end
		for _, member in members do
			if member.Character then
				removeState(member.Character)
			end
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= Config.TICK_INTERVAL then
			elapsed = 0
			step()
		end
	end)
end

return StatusService
