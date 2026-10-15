--!strict
--[[
	Elite : comportement du Veilleur de Cendre (élite gardien de la crypte, plusieurs attaques).
		- "sweep" : balayage frontal en cône, parable ;
		- "crush" : écrasement en cercle autour de lui, non parable. Préféré quand plusieurs joueurs sont
		  à portée (il punit le groupe agglutiné) ;
		- INVOCATION UNIQUE à summon.healthRatio des PV : incantation de summon.channel s, puis
		  summon.count Rôdeurs apparaissent autour de lui. Un étourdissement pendant l'incantation
		  l'annule pour de bon (récompense de l'interruption) ;
		- RAGE à enrage.healthRatio : plus rapide, télégraphes et temps de recharge raccourcis (attribut
		  Enraged pour les clients).
	S'il rentre à son point d'apparition (laisse), il retrouve tous ses PV, perd sa rage, ses
	invocations disparaissent et il pourra de nouveau invoquer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local EnemyBrain = require(script.Parent.Parent.EnemyBrain)

type Enemy = EnemyBrain.Enemy

type State = {
	hasSummoned: boolean,
	hasEnraged: boolean,
	summons: { Enemy },
}

local CONTACT_DISTANCE = 7 -- studs : en deçà, il s'arrête et pivote vers sa cible
local GROUP_SIZE_FOR_CRUSH = 2 -- joueurs dans la zone d'écrasement pour la préférer au balayage

local states: { [Enemy]: State } = {}

local function init(enemy: Enemy)
	states[enemy] = { hasSummoned = false, hasEnraged = false, summons = {} }
end

local function countPlayersWithin(enemy: Enemy, radius: number): number
	local count = 0
	local position = enemy.rootPart.Position
	for _, player in EnemyBrain.getPlayersNear(position, radius) do
		if EnemyBrain.getLivingCharacter(player) then
			count += 1
		end
	end
	return count
end

local function enrage(enemy: Enemy, state: State, params: Definitions.EnrageDef)
	state.hasEnraged = true
	enemy.telegraphScale = params.telegraphMultiplier
	enemy.cooldownScale = params.cooldownMultiplier
	EnemyBrain.setBaseSpeed(enemy, enemy.def.walkSpeed * params.speedMultiplier)
	enemy.model:SetAttribute(Definitions.ATTRIBUTES.enraged, true)
	EnemyBrain.action(enemy, "enrage")
end

local function spawnSummons(enemy: Enemy, state: State, params: Definitions.SummonDef)
	local spawnSummon = EnemyBrain.hooks.spawnSummon
	if spawnSummon == nil then
		return
	end
	local origin = enemy.rootPart.Position
	local look = enemy.rootPart.CFrame.LookVector
	local baseAngle = math.atan2(look.Z, look.X)
	for index = 1, params.count do
		local angle = baseAngle + (index - 0.5) / params.count * math.pi * 2
		local candidate = origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * params.radius
		local standing = EnemyBrain.findStandingPoint(enemy, candidate) or candidate
		local facing = if enemy.targetRoot then enemy.targetRoot.Position else origin + look * 10
		local cframe = CFrame.lookAt(standing, standing + EnemyBrain.flatUnit(facing - standing, look))
		spawnSummon(enemy, params.enemyId, cframe, function(summon: Enemy)
			table.insert(state.summons, summon)
			-- Les invocations entrent directement dans le combat de leur maître.
			summon.target = enemy.target
			summon.targetRoot = enemy.targetRoot
		end)
	end
end

local function chooseAttack(enemy: Enemy, distance: number, now: number): Definitions.AttackDef?
	local crush = EnemyBrain.getAttack(enemy, "crush")
	if crush and distance <= crush.range and EnemyBrain.isAttackReady(enemy, crush, now) then
		if countPlayersWithin(enemy, crush.radius) >= GROUP_SIZE_FOR_CRUSH then
			return crush
		end
	end
	return EnemyBrain.pickAttack(enemy, distance, now)
end

local function think(enemy: Enemy, now: number, _dt: number)
	local state = states[enemy]
	if state == nil then
		return
	end
	local humanoid = enemy.humanoid
	local healthRatio = humanoid.Health / math.max(humanoid.MaxHealth, 1)

	local enrageParams = enemy.def.enrage
	if enrageParams and not state.hasEnraged and healthRatio <= enrageParams.healthRatio then
		enrage(enemy, state, enrageParams)
	end

	local targetRoot = enemy.targetRoot
	if enemy.target == nil or targetRoot == nil then
		EnemyBrain.idle(enemy)
		return
	end
	enemy.state = "combat"

	local summonParams = enemy.def.summon
	if summonParams and not state.hasSummoned and healthRatio <= summonParams.healthRatio then
		state.hasSummoned = true
		EnemyBrain.action(enemy, "summon")
		EnemyBrain.beginChannel(enemy, summonParams.channel * enemy.telegraphScale, function(owner: Enemy)
			spawnSummons(owner, state, summonParams)
		end)
		return
	end

	local targetPosition = targetRoot.Position
	local distance = EnemyBrain.flatDistance(enemy.rootPart.Position, targetPosition)
	local attack = chooseAttack(enemy, distance, now)
	if attack then
		EnemyBrain.beginAttack(enemy, attack, targetPosition)
		return
	end

	if distance > CONTACT_DISTANCE then
		EnemyBrain.moveTo(enemy, targetPosition)
	else
		EnemyBrain.stop(enemy)
		EnemyBrain.face(enemy, targetPosition)
	end
end

-- Laisse dépassée : combat remis à zéro.
local function onReset(enemy: Enemy)
	local state = states[enemy]
	if state == nil then
		return
	end
	local despawn = EnemyBrain.hooks.despawn
	for _, summon in state.summons do
		if summon.isAlive and despawn then
			despawn(summon)
		end
	end
	table.clear(state.summons)
	state.hasSummoned = false
	if state.hasEnraged then
		state.hasEnraged = false
		enemy.telegraphScale = 1
		enemy.cooldownScale = 1
		EnemyBrain.setBaseSpeed(enemy, enemy.def.walkSpeed)
		enemy.model:SetAttribute(Definitions.ATTRIBUTES.enraged, nil)
	end
end

local function cleanup(enemy: Enemy)
	-- Ses invocations vivantes restent en jeu (sans réapparition) : on ne garde que la référence.
	states[enemy] = nil
end

local behavior: EnemyBrain.Behavior = {
	name = "elite",
	init = init,
	think = think,
	onReset = onReset,
	cleanup = cleanup,
}

return behavior
