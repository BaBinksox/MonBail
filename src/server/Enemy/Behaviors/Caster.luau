--!strict
--[[
	Caster : comportement du Murmure (lanceur de sorts).
		- Garde ses distances : entre kite.minDistance et kite.maxDistance de sa cible, il se déplace
		  latéralement en la regardant ; trop près il recule, trop loin il s'approche (toujours dans sa
		  laisse).
		- Pose des ZONES DE DANGER : cercle télégraphié SOUS la cible (~1,2 s), non parable : il faut sortir
		  de la zone ou dasher au bon moment.
		- Se TÉLÉPORTE à l'écart quand un joueur le serre de trop près (blink.triggerDistance), au plus une
		  fois toutes les blink.cooldown s : point au sol, libre, dans la laisse, à blink.min/maxDistance
		  du joueur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local EnemyBrain = require(script.Parent.Parent.EnemyBrain)

type Enemy = EnemyBrain.Enemy

type State = {
	nextBlink: number, -- os.clock()
	strafeSide: number, -- -1 / 1
	nextStrafeSwap: number,
}

local STRAFE_STEP = 6 -- studs visés de côté à chaque décision
local STRAFE_SWAP_MIN = 1.5
local STRAFE_SWAP_MAX = 3.5
local BLINK_ATTEMPTS = 8 -- points d'arrivée essayés avant de renoncer
local BLINK_SPREAD = math.rad(70) -- écart autour de la direction "loin du joueur"

local states: { [Enemy]: State } = {}
local random = Random.new()

local function init(enemy: Enemy)
	states[enemy] = { nextBlink = 0, strafeSide = 1, nextStrafeSwap = 0 }
end

-- Point d'arrivée d'une téléportation, du côté opposé au joueur, ou nil.
local function findBlinkPoint(enemy: Enemy, targetPosition: Vector3, blink: Definitions.BlinkDef): Vector3?
	local position = enemy.rootPart.Position
	local away = EnemyBrain.flat(position - targetPosition)
	local baseAngle = if away.Magnitude > 0.1 then math.atan2(away.Z, away.X) else random:NextNumber(0, math.pi * 2)
	for _ = 1, BLINK_ATTEMPTS do
		local angle = baseAngle + random:NextNumber(-BLINK_SPREAD, BLINK_SPREAD)
		local distance = random:NextNumber(blink.minDistance, blink.maxDistance)
		local candidate = targetPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		candidate = Vector3.new(candidate.X, position.Y, candidate.Z)
		if not EnemyBrain.isOutsideLeash(enemy, candidate) then
			local standing = EnemyBrain.findStandingPoint(enemy, candidate)
			if standing then
				return standing
			end
		end
	end
	return nil
end

local function think(enemy: Enemy, now: number, _dt: number)
	local state = states[enemy]
	local kite = enemy.def.kite
	local targetRoot = enemy.targetRoot
	if state == nil or kite == nil or enemy.target == nil or targetRoot == nil then
		EnemyBrain.idle(enemy)
		return
	end
	enemy.state = "combat"

	local position = enemy.rootPart.Position
	local targetPosition = targetRoot.Position
	local distance = EnemyBrain.flatDistance(position, targetPosition)

	-- 1. Trop près : téléportation à l'écart.
	local blink = enemy.def.blink
	if blink and distance <= blink.triggerDistance and now >= state.nextBlink then
		local destination = findBlinkPoint(enemy, targetPosition, blink)
		if destination then
			state.nextBlink = now + blink.cooldown
			EnemyBrain.action(enemy, "blink", position, destination)
			EnemyBrain.teleport(enemy, destination, targetPosition)
			enemy.busyUntil = now + Definitions.AI.BLINK_RECOVERY
			return
		end
	end

	-- 2. Zone de danger dès qu'elle est prête et que la cible est visible.
	local attack = EnemyBrain.pickAttack(enemy, distance, now)
	if attack and EnemyBrain.hasLineOfSight(enemy, targetPosition) then
		EnemyBrain.beginAttack(enemy, attack, targetPosition)
		return
	end

	-- 3. Distance de sécurité.
	local away = EnemyBrain.flatUnit(position - targetPosition, -enemy.rootPart.CFrame.LookVector)
	local destination: Vector3
	if distance < kite.minDistance or distance > kite.maxDistance then
		destination = targetPosition + away * kite.preferredDistance
	else
		if now >= state.nextStrafeSwap then
			state.strafeSide = if random:NextNumber() < 0.5 then -1 else 1
			state.nextStrafeSwap = now + random:NextNumber(STRAFE_SWAP_MIN, STRAFE_SWAP_MAX)
		end
		local side = Vector3.new(-away.Z, 0, away.X) * state.strafeSide
		destination = position + side * STRAFE_STEP
	end
	destination = EnemyBrain.clampToLeash(enemy, Vector3.new(destination.X, position.Y, destination.Z))
	EnemyBrain.moveTo(enemy, destination, targetPosition)
end

local function cleanup(enemy: Enemy)
	states[enemy] = nil
end

local behavior: EnemyBrain.Behavior = {
	name = "caster",
	init = init,
	think = think,
	cleanup = cleanup,
}

return behavior
