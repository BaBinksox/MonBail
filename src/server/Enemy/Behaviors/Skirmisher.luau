--!strict
--[[
	Skirmisher : comportement du Rôdeur des Cendres (harceleur rapide).
		1. APPROCHE EN ZIGZAG : il avance vers sa cible en ondulant latéralement (skirmish.zigzag*) ;
		2. BOND : à portée, ligne télégraphiée au sol (~0,45 s). À l'impact, le serveur résout la ligne
		   PUIS l'ennemi fonce le long de celle-ci (EnemyBrain.dash) ;
		3. REPLI : il reprend skirmish.retreatDistance en reculant face à sa cible, puis tourne autour
		   d'elle (orbitDistance) le temps que le bond recharge.
	Interface commune : voir EnemyBrain.Behavior.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local EnemyBrain = require(script.Parent.Parent.EnemyBrain)

type Enemy = EnemyBrain.Enemy

type State = {
	phase: number, -- phase du zigzag (radians)
	side: number, -- -1 / 1 : sens du repli et de l'orbite
	retreatUntil: number, -- os.clock()
	nextSideSwap: number,
}

local ZIGZAG_STEP = 10 -- studs visés devant lui à chaque décision pendant l'approche
local SIDE_SWAP_MIN = 2 -- secondes entre deux changements de sens d'orbite
local SIDE_SWAP_MAX = 4

local states: { [Enemy]: State } = {}
local random = Random.new()

local function randomSide(): number
	return if random:NextNumber() < 0.5 then -1 else 1
end

local function init(enemy: Enemy)
	states[enemy] = {
		phase = random:NextNumber(0, math.pi * 2),
		side = randomSide(),
		retreatUntil = 0,
		nextSideSwap = 0,
	}
end

local function think(enemy: Enemy, now: number, dt: number)
	local params = enemy.def.skirmish
	local state = states[enemy]
	local targetRoot = enemy.targetRoot
	if params == nil or state == nil or enemy.target == nil or targetRoot == nil then
		EnemyBrain.idle(enemy)
		return
	end
	enemy.state = "combat"

	local position = enemy.rootPart.Position
	local targetPosition = targetRoot.Position
	local distance = EnemyBrain.flatDistance(position, targetPosition)
	local forward = EnemyBrain.flatUnit(targetPosition - position, enemy.rootPart.CFrame.LookVector)
	local side = Vector3.new(-forward.Z, 0, forward.X)

	if now >= state.nextSideSwap then
		state.side = randomSide()
		state.nextSideSwap = now + random:NextNumber(SIDE_SWAP_MIN, SIDE_SWAP_MAX)
	end

	-- 1. Repli après un bond : reculer en gardant la cible en face.
	if now < state.retreatUntil then
		local away = targetPosition - forward * params.retreatDistance + side * state.side * 3
		local destination = EnemyBrain.clampToLeash(enemy, Vector3.new(away.X, position.Y, away.Z))
		EnemyBrain.moveTo(enemy, destination, targetPosition)
		return
	end

	-- 2. Bond dès qu'il est prêt et que la cible est visible.
	local attack = EnemyBrain.pickAttack(enemy, distance, now)
	if attack and EnemyBrain.hasLineOfSight(enemy, targetPosition) then
		EnemyBrain.beginAttack(enemy, attack, targetPosition)
		return
	end

	-- 3. Approche en zigzag de loin, orbite de près pendant la recharge.
	state.phase += dt * (2 * math.pi / params.zigzagPeriod)
	local destination: Vector3
	if distance > params.orbitDistance + 2 then
		local sway = math.sin(state.phase) * params.zigzagAmplitude
		destination = position + forward * math.min(distance - params.orbitDistance, ZIGZAG_STEP) + side * sway
	else
		destination = targetPosition - forward * params.orbitDistance + side * state.side * params.zigzagAmplitude
	end
	destination = EnemyBrain.clampToLeash(enemy, Vector3.new(destination.X, position.Y, destination.Z))
	EnemyBrain.moveTo(enemy, destination)
end

local function onImpact(enemy: Enemy, attack: Definitions.AttackDef, geometry: EnemyBrain.Geometry)
	local lunge = attack.lunge
	if lunge and lunge > 0 then
		EnemyBrain.dash(enemy, geometry.direction, lunge, Definitions.AI.LUNGE_DURATION)
	end
	local state = states[enemy]
	local params = enemy.def.skirmish
	if state and params then
		state.retreatUntil = os.clock() + attack.recovery + params.retreatDuration
		state.side = randomSide()
	end
end

local function cleanup(enemy: Enemy)
	states[enemy] = nil
end

local behavior: EnemyBrain.Behavior = {
	name = "skirmisher",
	init = init,
	think = think,
	onImpact = onImpact,
	cleanup = cleanup,
}

return behavior
