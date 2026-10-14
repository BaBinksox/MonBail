--!strict
--[[
	UltimateBehaviors
	Ce qui rend les cinq ultimes DIFFÉRENTS en jeu, au-delà de leur rayon et de leurs dégâts.

	CombatService inflige les dégâts de zone communs, puis appelle run() : l'effet propre à la magie
	du lanceur s'applique alors aux cibles encore en vie.
		antimatter : implosion   - les survivants sont aspirés vers le lanceur (à portée d'épée) ;
		pyromancy  : brûlure     - ils continuent de perdre des PV pendant quelques secondes ;
		lightning  : paralysie   - ils ne peuvent plus bouger un court instant ;
		ice        : gel         - ils sont fortement ralentis, longtemps ;
		shadow     : drain       - le lanceur récupère une part des dégâts infligés.

	Ajouter ou changer un effet : une fonction dans BEHAVIORS, rangée sous l'`id` de la magie.
	Une magie sans entrée n'a simplement pas d'effet secondaire.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)

local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

export type Context = {
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

	-- Brûlure : des dégâts répétés. Ils s'interrompent si le temps est rembobiné entre-temps.
	pyromancy = function(context: Context)
		for _ = 1, BURN_TICKS do
			task.wait(BURN_TICK_INTERVAL)
			if TimeLoopService.isRewinding() then
				return
			end
			for _, target in context.targets do
				local humanoid = getAffectableParts(target)
				if humanoid then
					humanoid:TakeDamage(BURN_TICK_DAMAGE)
				end
			end
		end
	end,

	-- Paralysie : vitesse nulle un court instant.
	lightning = function(context: Context)
		for _, target in context.targets do
			local humanoid = getAffectableParts(target)
			if humanoid then
				applySpeedFactor(humanoid, 0, STUN_DURATION)
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
