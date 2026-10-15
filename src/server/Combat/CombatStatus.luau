--!strict
--[[
	CombatStatus
	États de combat partagés par tous les systèmes serveur (aucune dépendance : évite les cycles).
		- étourdissement : attribut ParryConfig.STUNNED_UNTIL_ATTRIBUTE (heure serveur de fin) sur le Model.
		  Posé par la parade, la paralysie de la Foudre, l'effondrement de la Gravité... ; respecté par
		  toutes les IA (ennemis, boss) : un Model étourdi n'attaque pas et ne se déplace pas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParryConfig = require(ReplicatedStorage.Shared.Combat.ParryConfig)

local CombatStatus = {}

-- Étourdit `model` pendant `duration` secondes (prolonge un étourdissement plus court déjà en cours).
function CombatStatus.stun(model: Model, duration: number)
	local now = workspace:GetServerTimeNow()
	local current = model:GetAttribute(ParryConfig.STUNNED_UNTIL_ATTRIBUTE)
	local untilTime = now + duration
	if type(current) == "number" and current > untilTime then
		return
	end
	model:SetAttribute(ParryConfig.STUNNED_UNTIL_ATTRIBUTE, untilTime)
end

function CombatStatus.isStunned(model: Model): boolean
	local untilTime = model:GetAttribute(ParryConfig.STUNNED_UNTIL_ATTRIBUTE)
	return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

-- Secondes d'étourdissement restantes (0 si aucun).
function CombatStatus.getStunRemaining(model: Model): number
	local untilTime = model:GetAttribute(ParryConfig.STUNNED_UNTIL_ATTRIBUTE)
	if type(untilTime) ~= "number" then
		return 0
	end
	return math.max(0, untilTime - workspace:GetServerTimeNow())
end

return CombatStatus
