--!strict
--[[
	WorldConfig
	Constantes partagées (serveur + client) du monde : heure, météo, humeur et présages.

	Répartition des rôles :
		- le SERVEUR décide de l'état du monde et le publie dans des attributs du Workspace
		  (répliqués à tous les joueurs) : la météo en cours et l'humeur (normale / anomalie) ;
		- chaque CLIENT met cet état en image chez lui (WorldAtmosphere) : lumière, brouillard,
		  nuages, vent, particules, son. Tous voient donc le même monde, sans aucun effet visuel
		  calculé par le serveur.
	L'heure, elle, n'est même pas transmise : elle se déduit de l'horloge du serveur, que Roblox
	synchronise déjà chez tous les clients (voir getClockTime).
]]

export type Weather = {
	name: string,
	weight: number, -- chances d'être tirée au sort, par rapport aux autres
	fog: number, -- brouillard ajouté (Atmosphere.Density, 0 à 1)
	haze: number, -- voile ajouté (Atmosphere.Haze)
	cloudCover: number, -- couverture nuageuse (0 = ciel vide, 1 = ciel bouché)
	windSpeed: number, -- studs/s : agite l'herbe, les nuages et les particules
}

local MOODS = table.freeze({
	Normal = "Normal",
	Anomaly = "Anomaly", -- un boss charge son attaque fatale : le monde entier bascule
})

local WEATHERS: { [string]: Weather } = {
	clear = { name = "Ciel dégagé", weight = 5, fog = 0, haze = 0, cloudCover = 0.45, windSpeed = 6 },
	mist = { name = "Brume", weight = 3, fog = 0.22, haze = 2.5, cloudCover = 0.8, windSpeed = 2 },
	gale = { name = "Vent des plaines", weight = 2, fog = 0.04, haze = 0.6, cloudCover = 0.65, windSpeed = 28 },
}

--[[
	Cycle jour / nuit : LE SEUL endroit où régler sa durée.
	Le JOUR (de DAY_START à NIGHT_START, heures de jeu) et la NUIT (le reste) ont chacun leur durée
	réelle : la journée dure bien plus longtemps que la nuit, sans que l'heure saute. Le soleil
	avance simplement plus vite la nuit. Aube et crépuscule sont fondus par LightingPresets.
	Valeurs par défaut : 28 min de jour + 10 min de nuit = un cycle complet de 38 min réelles.
]]
local DAY_REAL_SECONDS = 28 * 60
local NIGHT_REAL_SECONDS = 10 * 60
local DAY_START = 5.8 -- heure de jeu où le jour commence (aube)
local NIGHT_START = 19.6 -- heure de jeu où la nuit commence (après le crépuscule)
-- Décalage (secondes réelles) dans le cycle. À changer pour décider de l'heure qu'il est maintenant.
local CYCLE_OFFSET = 0

local CYCLE_LENGTH = DAY_REAL_SECONDS + NIGHT_REAL_SECONDS
local DAY_HOURS = NIGHT_START - DAY_START
local NIGHT_HOURS = 24 - DAY_HOURS

-- Heure du monde (0 à 24) pour un instant `serverTime` (secondes, horloge du serveur).
local function clockTimeAt(serverTime: number): number
	local phase = (serverTime + CYCLE_OFFSET) % CYCLE_LENGTH
	if phase < DAY_REAL_SECONDS then
		return DAY_START + phase / DAY_REAL_SECONDS * DAY_HOURS
	end
	return (NIGHT_START + (phase - DAY_REAL_SECONDS) / NIGHT_REAL_SECONDS * NIGHT_HOURS) % 24
end

-- Heure du monde (0 à 24), identique sur le serveur et chez tous les clients au même instant.
local function getClockTime(): number
	return clockTimeAt(workspace:GetServerTimeNow())
end

return table.freeze({
	-- Attributs du Workspace écrits par WorldService.
	MOOD_ATTRIBUTE = "WorldMood",
	WEATHER_ATTRIBUTE = "WorldWeather",
	MOODS = MOODS,

	-- Heure ------------------------------------------------------------------------
	DAY_REAL_SECONDS = DAY_REAL_SECONDS,
	NIGHT_REAL_SECONDS = NIGHT_REAL_SECONDS,
	DAY_LENGTH = CYCLE_LENGTH, -- durée réelle d'un cycle complet (compatibilité)
	getClockTime = getClockTime,
	clockTimeAt = clockTimeAt,
	NIGHT_START = NIGHT_START, -- à partir de cette heure (et jusqu'à NIGHT_END) : lucioles, etc.
	NIGHT_END = DAY_START,

	-- Météo ------------------------------------------------------------------------
	WEATHERS = WEATHERS,
	DEFAULT_WEATHER = "clear",
	WEATHER_MIN_DURATION = 150, -- secondes avant un nouveau tirage
	WEATHER_MAX_DURATION = 330,
	WIND_DIRECTION = Vector3.new(1, 0, 0.35).Unit,

	-- Présages : de temps à autre, quelque chose murmure à tous les joueurs ---------------
	OMEN_MIN_INTERVAL = 240, -- secondes entre deux présages
	OMEN_MAX_INTERVAL = 540,
	OMEN_DURATION = 5, -- secondes d'affichage
	OMENS = {
		"Elle vous regarde.",
		"Vous êtes déjà mort ici.",
		"Ne vous retournez pas.",
		"Combien de fois, cette fois-ci ?",
		"L'odeur revient.",
		"Je t'aime. Je t'aime. Je t'aime.",
		"Le temps se souvient de vous.",
	},

	-- Sons d'ambiance (joués par les clients) --------------------------------------------
	-- Bourdon grave pendant l'anomalie. Placeholder : "DARK DRONE 13" (APM Music, bibliothèque Roblox).
	ANOMALY_DRONE_ID = "rbxassetid://9043359885",
	ANOMALY_DRONE_VOLUME = 0.55,
	-- >>> VENT : mets ici une boucle de vent ("rbxassetid://123456"). Vide = pas de son de vent.
	-- Son volume suit la force du vent de la météo en cours.
	WIND_SOUND_ID = "",
	WIND_SOUND_MAX_VOLUME = 0.5,
})
