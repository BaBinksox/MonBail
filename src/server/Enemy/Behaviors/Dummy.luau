--!strict
--[[
	Dummy : comportement du Mannequin d'entraînement.
		- Planté au sol (RootPart ancré), il ne marche ni n'attaque pour de vrai.
		- RÉGÉNÉRATION : regen.delay s après le dernier coup reçu, il retrouve tous ses PV. Il sert à
		  remplir sa Tension et à essayer ses ultimes.
		- ATTAQUE À VIDE (entraînement à la parade) : tant que l'attribut ATTRIBUTES.practice vaut true
		  sur le Model (posé à l'apparition, un tutoriel peut le couper), il lance toutes les
		  practice.interval s un moulinet télégraphié très lent, parable et sans dégâts vers le joueur
		  à moins de practice.radius studs. Une parade réussie l'étourdit (ParryService) et donne de la
		  Tension, exactement comme contre un vrai ennemi.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local EnemyBrain = require(script.Parent.Parent.EnemyBrain)

type Enemy = EnemyBrain.Enemy

type State = {
	nextPractice: number, -- os.clock()
}

local states: { [Enemy]: State } = {}

local function init(enemy: Enemy)
	states[enemy] = { nextPractice = 0 }
end

local function think(enemy: Enemy, now: number, _dt: number)
	local humanoid = enemy.humanoid
	local regen = enemy.def.regen
	if regen and humanoid.Health < humanoid.MaxHealth and now - enemy.lastDamagedClock >= regen.delay then
		humanoid.Health = humanoid.MaxHealth
	end

	local practice = enemy.def.practice
	local state = states[enemy]
	local targetRoot = enemy.targetRoot
	enemy.state = "idle"
	if practice == nil or state == nil or enemy.target == nil or targetRoot == nil then
		return
	end
	if enemy.model:GetAttribute(Definitions.ATTRIBUTES.practice) ~= true or now < state.nextPractice then
		return
	end
	if EnemyBrain.flatDistance(enemy.rootPart.Position, targetRoot.Position) > practice.radius then
		return
	end
	local attack = EnemyBrain.getAttack(enemy, practice.attackId)
	if attack == nil then
		return
	end
	state.nextPractice = now + practice.interval
	EnemyBrain.beginAttack(enemy, attack, targetRoot.Position)
end

local function cleanup(enemy: Enemy)
	states[enemy] = nil
end

local behavior: EnemyBrain.Behavior = {
	name = "dummy",
	init = init,
	think = think,
	cleanup = cleanup,
}

return behavior
