--!strict
--[[
	UltimateBehaviors
	Ce qui rend les six ultimes DIFFÉRENTS en jeu, au-delà de leur rayon et de leurs dégâts.

	CombatService inflige les dégâts de zone communs, puis appelle run() : l'effet propre à la magie
	du lanceur s'applique alors aux cibles encore en vie.
		antimatter : implosion   - les survivants sont aspirés vers le lanceur (à portée d'épée) ;
		pyromancy  : brûlure     - ils continuent de perdre des PV pendant quelques secondes ;
		lightning  : paralysie   - ils ne peuvent plus bouger un court instant ;
		ice        : gel         - ils sont fortement ralentis, longtemps ;
		shadow     : drain       - le lanceur récupère une part des dégâts infligés ;
		gravity    : effondrement - les survivants sont arrachés du sol puis écrasés, et restent cloués un instant.
	Les dégâts secondaires (brûlure, écrasement) passent par DamageService : ils sont attribués au lanceur
	(contributions, élimination) ; les immobilisations passent par CombatStatus : les IA les respectent.

	Ajouter ou changer un effet : une fonction dans BEHAVIORS, rangée sous l'`id` de la magie.
	Une magie sans entrée n'a simplement pas d'effet secondaire.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)

local CombatStatus = require(script.Parent.CombatStatus)
local DamageService = require(script.Parent.DamageService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

export type Context = {
	caster: Player, -- joueur qui a lancé l'ultime (attribution des dégâts secondaires)
	casterHumanoid: Humanoid,
	origin: Vector3, -- position du lanceur au moment de l'ultime
	targets: { Model }, -- cibles touchées par les dégâts de zone
	magic: MagicConfig.Magic,
	damageDealt: number, -- total des PV retirés par les dégâts de zone
}

-- Antimatière
local PULL_SPEED = 45 -- studs/s
local PULL_DURATION = 0.3
local PULL_STOP_DISTANCE = 5 -- studs : on n'aspire pas une cible déjà au contact
-- Pyromancie
local BURN_TICKS = 5
local BURN_TICK_INTERVAL = 1
local BURN_TICK_DAMAGE = 6
-- Foudre
local STUN_DURATION = 1.5
-- Glace
local SLOW_FACTOR = 0.35 -- vitesse restante
local SLOW_DURATION = 5
-- Ombre
local DRAIN_RATIO = 0.4 -- part des dégâts rendue au lanceur
-- Gravité
local LIFT_SPEED = 38 -- studs/s vers le haut
local LIFT_DURATION = 0.35
local SLAM_SPEED = 90 -- studs/s vers le bas
local SLAM_DURATION = 0.2
local SLAM_DAMAGE = 12
local PIN_DURATION = 1.2 -- secondes cloué au sol après l'écrasement

-- Attributs posés sur le Humanoid ralenti, pour que deux effets de vitesse ne se marchent pas dessus.
local BASE_SPEED_ATTRIBUTE = "BaseWalkSpeed"
local SPEED_TOKEN_ATTRIBUTE = "SpeedEffectToken"

local UltimateBehaviors = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Humanoid et RootPart d'une cible encore vivante et vulnérable, sinon nil.
local function getAffectableParts(target: Model): (Humanoid?, BasePart?)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	if target:GetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE) == true then
		return nil, nil
	end
	return humanoid, rootPart
end

-- Multiplie la vitesse de marche de `humanoid` par `factor` pendant `duration` secondes.
-- Un effet plus récent remplace le précédent ; la vitesse d'origine est toujours rendue à la fin.
local function applySpeedFactor(humanoid: Humanoid, factor: number, duration: number)
	local baseSpeed = humanoid:GetAttribute(BASE_SPEED_ATTRIBUTE)
	if type(baseSpeed) ~= "number" then
		baseSpeed = humanoid.WalkSpeed
		humanoid:SetAttribute(BASE_SPEED_ATTRIBUTE, baseSpeed)
	end

	local token = ((humanoid:GetAttribute(SPEED_TOKEN_ATTRIBUTE) :: number?) or 0) + 1
	humanoid:SetAttribute(SPEED_TOKEN_ATTRIBUTE, token)
	humanoid.WalkSpeed = (baseSpeed :: number) * factor

	task.delay(duration, function()
		if humanoid:GetAttribute(SPEED_TOKEN_ATTRIBUTE) == token then
			humanoid.WalkSpeed = baseSpeed :: number
			humanoid:SetAttribute(BASE_SPEED_ATTRIBUTE, nil)
		end
	end)
end

--------------------------------------------------------------------------------
-- Effets par magie
--------------------------------------------------------------------------------

local BEHAVIORS: { [string]: (Context) -> () } = {
	-- Implosion : une LinearVelocity brève tire chaque survivant vers le point d'origine.
	antimatter = function(context: Context)
		for _, target in context.targets do
			local _, rootPart = getAffectableParts(target)
			if rootPart and not rootPart.Anchored then
				local toOrigin = (context.origin - rootPart.Position) * Vector3.new(1, 0, 1)
				if toOrigin.Magnitude > PULL_STOP_DISTANCE then
					local attachment = Instance.new("Attachment")
					attachment.Name = "PullAttachment"
					attachment.Parent = rootPart

					local velocity = Instance.new("LinearVelocity")
					velocity.Name = "PullVelocity"
					velocity.Attachment0 = attachment
					velocity.RelativeTo = Enum.ActuatorRelativeTo.World
					velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
					velocity.VectorVelocity = toOrigin.Unit * PULL_SPEED
					velocity.MaxForce = 1e6
					velocity.Parent = rootPart

					Debris:AddItem(velocity, PULL_DURATION)
					Debris:AddItem(attachment, PULL_DURATION)
				end
			end
		end
	end,

	-- Brûlure : des dégâts répétés, attribués au lanceur. Ils s'interrompent si le temps est rembobiné.
	pyromancy = function(context: Context)
		local source: DamageService.DamageSource = { player = context.caster, model = context.casterHumanoid.Parent :: Model?, kind = "burn" }
		for _ = 1, BURN_TICKS do
			task.wait(BURN_TICK_INTERVAL)
			if TimeLoopService.isRewindingFor(context.caster) then
				return
			end
			for _, target in context.targets do
				DamageService.dealDamage(target, BURN_TICK_DAMAGE, source)
			end
		end
	end,

	-- Paralysie : vitesse nulle ET étourdissement (les IA n'attaquent plus) un court instant.
	lightning = function(context: Context)
		for _, target in context.targets do
			local humanoid = getAffectableParts(target)
			if humanoid then
				applySpeedFactor(humanoid, 0, STUN_DURATION)
				CombatStatus.stun(target, STUN_DURATION)
			end
		end
	end,

	-- Gel : fort ralentissement, plus long.
	ice = function(context: Context)
		for _, target in context.targets do
			local humanoid = getAffectableParts(target)
			if humanoid then
				applySpeedFactor(humanoid, SLOW_FACTOR, SLOW_DURATION)
			end
		end
	end,

	-- Drain : le lanceur se soigne d'une part des dégâts qu'il vient d'infliger.
	shadow = function(context: Context)
		local humanoid = context.casterHumanoid
		if humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.Health + context.damageDealt * DRAIN_RATIO, humanoid.MaxHealth)
		end
	end,

	-- Effondrement : chaque survivant est soulevé, puis plaqué au sol (dégâts attribués) et cloué.
	gravity = function(context: Context)
		local lifted: { Model } = {}
		for _, target in context.targets do
			local _, rootPart = getAffectableParts(target)
			if rootPart and not rootPart.Anchored then
				local attachment = Instance.new("Attachment")
				attachment.Name = "GravityAttachment"
				attachment.Parent = rootPart

				local velocity = Instance.new("LinearVelocity")
				velocity.Name = "GravityLift"
				velocity.Attachment0 = attachment
				velocity.RelativeTo = Enum.ActuatorRelativeTo.World
				velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
				velocity.VectorVelocity = Vector3.new(0, LIFT_SPEED, 0)
				velocity.MaxForce = 1e6
				velocity.Parent = rootPart

				Debris:AddItem(attachment, LIFT_DURATION + SLAM_DURATION)
				task.delay(LIFT_DURATION, function()
					if velocity.Parent then
						velocity.VectorVelocity = Vector3.new(0, -SLAM_SPEED, 0)
					end
				end)
				table.insert(lifted, target)
			end
			-- Même un ennemi qu'on ne peut pas soulever (ancré, très lourd) est cloué sur place.
			if getAffectableParts(target) then
				CombatStatus.stun(target, LIFT_DURATION + SLAM_DURATION + PIN_DURATION)
			end
		end

		task.wait(LIFT_DURATION + SLAM_DURATION)
		if TimeLoopService.isRewindingFor(context.caster) then
			return
		end
		local source: DamageService.DamageSource = { player = context.caster, model = context.casterHumanoid.Parent :: Model?, kind = "ultimate" }
		for _, target in lifted do
			DamageService.dealDamage(target, SLAM_DAMAGE, source)
			local humanoid = getAffectableParts(target)
			if humanoid then
				applySpeedFactor(humanoid, 0, PIN_DURATION)
			end
		end
	end,
}

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Applique l'effet secondaire de `context.magic`. Peut YIELD (brûlure) : à lancer avec task.spawn.
function UltimateBehaviors.run(context: Context)
	local behavior = BEHAVIORS[context.magic.id]
	if behavior then
		behavior(context)
	end
end

return UltimateBehaviors
