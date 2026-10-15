--!strict
--[[
	RaceService
	Applique, côté SERVEUR, l'avantage et l'inconvénient du peuple de chaque joueur (RaceConfig).
	Le peuple est publié dans l'attribut Player "Race" par AvatarService ; ce module en déduit :
		- la vie maximale et la vitesse de marche du personnage (apply, à chaque apparition) ;
		- le multiplicateur des dégâts reçus (DamageService) et de la Tension gagnée (CombatService).
	Les valeurs de base du Humanoid sont mémorisées une fois par personnage : réappliquer ne cumule
	jamais les bonus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaceConfig = require(ReplicatedStorage.Shared.Avatar.RaceConfig)
local WorldConfig = require(ReplicatedStorage.Shared.World.WorldConfig)

local BASE_HEALTH_ATTRIBUTE = "RaceBaseMaxHealth"
local BASE_SPEED_ATTRIBUTE = "RaceBaseWalkSpeed"

local RaceService = {}

local function raceOf(player: Player): RaceConfig.Race
	return RaceConfig.getById(player:GetAttribute(RaceConfig.ATTRIBUTE))
end

local function isNight(): boolean
	local clock = WorldConfig.getClockTime()
	return clock >= WorldConfig.NIGHT_START or clock < WorldConfig.NIGHT_END
end

-- Publie le peuple du joueur et met son personnage actuel à jour.
function RaceService.setRace(player: Player, raceId: string)
	player:SetAttribute(RaceConfig.ATTRIBUTE, RaceConfig.getById(raceId).id)
	RaceService.apply(player)
end

-- Vie maximale et vitesse du personnage actuel, d'après son peuple.
function RaceService.apply(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local modifiers = raceOf(player).modifiers
	local baseHealth = humanoid:GetAttribute(BASE_HEALTH_ATTRIBUTE)
	if type(baseHealth) ~= "number" then
		baseHealth = humanoid.MaxHealth
		humanoid:SetAttribute(BASE_HEALTH_ATTRIBUTE, baseHealth)
	end
	local baseSpeed = humanoid:GetAttribute(BASE_SPEED_ATTRIBUTE)
	if type(baseSpeed) ~= "number" then
		baseSpeed = humanoid.WalkSpeed
		humanoid:SetAttribute(BASE_SPEED_ATTRIBUTE, baseSpeed)
	end

	local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	local maxHealth = math.floor((baseHealth :: number) * modifiers.maxHealth + 0.5)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = math.clamp(maxHealth * ratio, 1, maxHealth)
	humanoid.WalkSpeed = (baseSpeed :: number) * modifiers.walkSpeed
end

-- Multiplicateur des dégâts reçus (jour / nuit pour les Enfants de l'Ombre).
function RaceService.getDamageTakenMultiplier(player: Player): number
	local modifiers = raceOf(player).modifiers
	if modifiers.nightDamageTaken and isNight() then
		return modifiers.nightDamageTaken
	elseif modifiers.dayDamageTaken and not isNight() then
		return modifiers.dayDamageTaken
	end
	return modifiers.damageTaken
end

function RaceService.getTensionGainMultiplier(player: Player): number
	return raceOf(player).modifiers.tensionGain
end

-- Ancre d'arrivée après la création : celle du peuple si elle existe VRAIMENT sur la carte.
function RaceService.getStartAnchorId(player: Player, anchorExists: (anchorId: string) -> boolean): string
	local anchorId = raceOf(player).startAnchorId
	if anchorExists(anchorId) then
		return anchorId
	end
	return RaceConfig.DEFAULT_START_ANCHOR
end

return RaceService
