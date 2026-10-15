--!strict
--[[
	Guardian : comportement du Gardien de Pierre (lent, massif, garde frontale).
		- Il marche vers sa cible ; une fois au contact, il PIVOTE LENTEMENT vers elle (turnSpeed) : on
		  peut le contourner pour le frapper de côté ou de dos.
		- GARDE FRONTALE (modifyDamage, appelé par DamageService avant chaque dégât) : un coup venu de face
		  (cône guard.angle, d'après la position du Model attaquant) perd guard.reduction de ses dégâts.
		- Le COUP LOURD du combo (source.kind == "melee" et source.heavy == true, voir le compte rendu
		  d'intégration de CombatService) venu de face BRISE la garde : pleins dégâts et étourdissement
		  de guard.breakStun s (CombatStatus.stun), qui annule aussi l'attaque en préparation.
		- La garde tombe pendant les attaques marquées guardDown (coup de masse) et quand il est étourdi.
		- Attaques : "slam" (cercle autour de lui, non parable) et "strike" (cône frontal, parable). Il
		  frappe là où il REGARDE : le cône ne part que si la cible est devant lui.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local CombatStatus = require(script.Parent.Parent.Parent.Combat.CombatStatus)
local DamageService = require(script.Parent.Parent.Parent.Combat.DamageService)
local EnemyBrain = require(script.Parent.Parent.EnemyBrain)

type Enemy = EnemyBrain.Enemy

type State = {
	guardBrokenUntil: number, -- os.clock()
	lastFxClock: number,
}

local CONTACT_DISTANCE = 5 -- studs : en deçà, il s'arrête et pivote au lieu de marcher

local states: { [Enemy]: State } = {}

local function init(enemy: Enemy)
	states[enemy] = { guardBrokenUntil = 0, lastFxClock = 0 }
end

local function isGuardUp(enemy: Enemy, state: State, now: number): boolean
	if now < state.guardBrokenUntil or CombatStatus.isStunned(enemy.model) then
		return false
	end
	local attack = enemy.currentAttack
	return not (attack and attack.guardDown == true)
end

local function think(enemy: Enemy, now: number, _dt: number)
	local targetRoot = enemy.targetRoot
	if enemy.target == nil or targetRoot == nil then
		EnemyBrain.idle(enemy)
		return
	end
	enemy.state = "combat"

	local targetPosition = targetRoot.Position
	local distance = EnemyBrain.flatDistance(enemy.rootPart.Position, targetPosition)

	-- Un cône ne part que vers l'avant : contourné, le Gardien doit d'abord se retourner.
	local attack = EnemyBrain.pickAttack(enemy, distance, now, function(candidate: Definitions.AttackDef): boolean
		return candidate.shape ~= "cone" or EnemyBrain.isInFront(enemy, targetPosition, candidate.angle or 90)
	end)
	if attack then
		local facing = enemy.rootPart.CFrame.LookVector
		EnemyBrain.beginAttack(enemy, attack, targetPosition, facing)
		return
	end

	if distance > CONTACT_DISTANCE then
		EnemyBrain.moveTo(enemy, targetPosition)
	else
		EnemyBrain.stop(enemy)
		EnemyBrain.face(enemy, targetPosition)
	end
end

local function getRootPosition(model: Model?): Vector3?
	if model == nil then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if rootPart then
		return rootPart.Position
	end
	local primary = model.PrimaryPart
	return primary and primary.Position
end

local function breakGuard(enemy: Enemy, state: State, guard: Definitions.GuardDef, attackerPosition: Vector3)
	state.guardBrokenUntil = os.clock() + guard.breakStun
	CombatStatus.stun(enemy.model, guard.breakStun)
	enemy.model:SetAttribute(Definitions.ATTRIBUTES.guardBrokenUntil, workspace:GetServerTimeNow() + guard.breakStun)
	EnemyBrain.action(enemy, "guard_break", attackerPosition)
end

-- Appelé par DamageService (via EnemyService) avant chaque dégât infligé au Gardien. Ne yield pas.
local function modifyDamage(enemy: Enemy, amount: number, source: DamageService.DamageSource): number
	local guard = enemy.def.guard
	local state = states[enemy]
	if guard == nil or state == nil or guard.affectedKinds[source.kind] ~= true then
		return amount
	end
	local now = os.clock()
	if not isGuardUp(enemy, state, now) then
		return amount
	end
	local attackerPosition = getRootPosition(source.model)
	if attackerPosition == nil or not EnemyBrain.isInFront(enemy, attackerPosition, guard.angle) then
		return amount -- de côté ou de dos : la garde ne couvre pas
	end

	-- Champ proposé dans DamageSource : `heavy` (coup lourd du combo). Absent = coup normal.
	local isHeavy = source.kind == "melee" and (source :: any).heavy == true
	if isHeavy then
		breakGuard(enemy, state, guard, attackerPosition)
		return amount
	end

	if now - state.lastFxClock >= Definitions.AI.GUARD_FX_INTERVAL then
		state.lastFxClock = now
		local rootPosition = enemy.rootPart.Position
		local towards = EnemyBrain.flatUnit(attackerPosition - rootPosition, enemy.rootPart.CFrame.LookVector)
		EnemyBrain.action(enemy, "guard_block", rootPosition + towards * (1.5 * enemy.def.appearance.modelScale))
	end
	return amount * (1 - guard.reduction)
end

local function cleanup(enemy: Enemy)
	states[enemy] = nil
end

local behavior: EnemyBrain.Behavior = {
	name = "guardian",
	init = init,
	think = think,
	modifyDamage = modifyDamage,
	cleanup = cleanup,
}

return behavior
