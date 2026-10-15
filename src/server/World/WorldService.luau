--!strict
--[[
	WorldService
	L'état du monde, côté serveur (singleton). Il ne touche ni au Lighting ni à aucun effet :
	il DÉCIDE et publie, les clients mettent en image (voir WorldAtmosphere).
		- météo   : tirée au sort toutes les quelques minutes, publiée dans un attribut du Workspace ;
		- humeur  : "Anomaly" tant qu'au moins un système le demande (setAnomaly), sinon "Normal" ;
		- présages : de temps à autre, une phrase murmurée à tous les joueurs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.World.WorldConfig)
local Remotes = require(ReplicatedStorage.Shared.World.WorldRemotes)

local WorldService = {}

local random = Random.new()
local anomalySources: { [any]: boolean } = {} -- qui réclame l'anomalie en ce moment
local isStarted = false

--------------------------------------------------------------------------------
-- Météo
--------------------------------------------------------------------------------

-- Tire une météo au sort selon les poids, différente de `currentId`.
local function pickWeather(currentId: string): string
	local totalWeight = 0
	for id, weather in Config.WEATHERS do
		if id ~= currentId then
			totalWeight += weather.weight
		end
	end

	local roll = random:NextNumber(0, totalWeight)
	for id, weather in Config.WEATHERS do
		if id ~= currentId then
			roll -= weather.weight
			if roll <= 0 then
				return id
			end
		end
	end
	return currentId
end

local function runWeatherCycle()
	local currentId = Config.DEFAULT_WEATHER
	while true do
		workspace:SetAttribute(Config.WEATHER_ATTRIBUTE, currentId)
		task.wait(random:NextNumber(Config.WEATHER_MIN_DURATION, Config.WEATHER_MAX_DURATION))
		currentId = pickWeather(currentId)
	end
end

--------------------------------------------------------------------------------
-- Présages
--------------------------------------------------------------------------------

local function runOmenCycle()
	while true do
		task.wait(random:NextNumber(Config.OMEN_MIN_INTERVAL, Config.OMEN_MAX_INTERVAL))

		-- Pas de murmure pendant une anomalie : l'écran a déjà assez à dire.
		local isCalm = workspace:GetAttribute(Config.MOOD_ATTRIBUTE) == Config.MOODS.Normal
		if isCalm and #Players:GetPlayers() > 0 then
			Remotes.Omen:FireAllClients(Config.OMENS[random:NextInteger(1, #Config.OMENS)])
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function WorldService.start()
	if isStarted then
		return
	end
	isStarted = true

	workspace:SetAttribute(Config.MOOD_ATTRIBUTE, Config.MOODS.Normal)
	task.spawn(runWeatherCycle)
	task.spawn(runOmenCycle)
end

--[[
	Fait basculer le monde entier dans l'anomalie (ciel noir, lumière rouge sang, brouillard lourd),
	ou l'en fait sortir. `source` identifie le demandeur (par exemple le Model d'un boss) :
	le monde ne redevient normal que lorsque TOUS ceux qui l'ont demandée l'ont relâchée.
]]
function WorldService.setAnomaly(source: any, isActive: boolean)
	if isActive then
		anomalySources[source] = true
	else
		anomalySources[source] = nil
	end

	local mood = if next(anomalySources) ~= nil then Config.MOODS.Anomaly else Config.MOODS.Normal
	workspace:SetAttribute(Config.MOOD_ATTRIBUTE, mood)
end

return WorldService
