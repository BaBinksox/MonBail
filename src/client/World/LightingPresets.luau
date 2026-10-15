--!strict
--[[
	LightingPresets
	Les "tableaux" de lumière du monde, et de quoi passer de l'un à l'autre. Données + fonctions pures.

	Un préréglage (Preset) décrit TOUT le rendu à un instant : pour chaque objet (Lighting, Atmosphere,
	ColorCorrection, Bloom, SunRays, Clouds), la valeur de chacune de ses propriétés animées.
	Tous les préréglages ont exactement les mêmes clés : on peut donc toujours en mélanger deux.

	La journée est une suite d'étapes (KEYFRAMES) entre lesquelles on interpole selon l'heure.
	ANOMALY est à part : il écrase tout quand un boss charge son attaque fatale.

	Pour changer l'ambiance du jeu, c'est ici : retoucher DAY, DUSK, NIGHT, DAWN ou ANOMALY.
]]

export type Preset = { [string]: { [string]: any } }

local function rgb(red: number, green: number, blue: number): Color3
	return Color3.fromRGB(red, green, blue)
end

-- Plein jour : lumière claire mais froide, couleurs un peu éteintes, lointain noyé de brume.
local DAY: Preset = {
	Lighting = {
		Ambient = rgb(70, 72, 80),
		OutdoorAmbient = rgb(128, 130, 138),
		Brightness = 2.6,
		ColorShift_Top = rgb(255, 240, 214),
		ExposureCompensation = 0.1,
	},
	Atmosphere = { Density = 0.32, Offset = 0.25, Color = rgb(199, 205, 214), Decay = rgb(106, 112, 125), Glare = 0.15, Haze = 1.6 },
	ColorCorrection = { TintColor = rgb(255, 248, 238), Saturation = -0.08, Contrast = 0.12, Brightness = 0 },
	Bloom = { Intensity = 0.6, Threshold = 1.6, Size = 28 },
	SunRays = { Intensity = 0.12, Spread = 0.6 },
	Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(235, 235, 240) },
}

-- Aube : rose et or, soleil rasant, rayons marqués.
local DAWN: Preset = {
	Lighting = {
		Ambient = rgb(86, 70, 78),
		OutdoorAmbient = rgb(150, 120, 110),
		Brightness = 1.8,
		ColorShift_Top = rgb(255, 196, 150),
		ExposureCompensation = 0,
	},
	Atmosphere = { Density = 0.42, Offset = 0.2, Color = rgb(232, 190, 170), Decay = rgb(140, 100, 110), Glare = 0.4, Haze = 2.2 },
	ColorCorrection = { TintColor = rgb(255, 236, 224), Saturation = 0.02, Contrast = 0.1, Brightness = 0 },
	Bloom = { Intensity = 0.9, Threshold = 1.3, Size = 36 },
	SunRays = { Intensity = 0.3, Spread = 0.9 },
	Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(255, 214, 196) },
}

-- Crépuscule : orange qui vire au violet, ombres longues.
local DUSK: Preset = {
	Lighting = {
		Ambient = rgb(80, 60, 84),
		OutdoorAmbient = rgb(140, 104, 110),
		Brightness = 1.6,
		ColorShift_Top = rgb(255, 160, 110),
		ExposureCompensation = 0,
	},
	Atmosphere = { Density = 0.44, Offset = 0.2, Color = rgb(214, 150, 130), Decay = rgb(110, 70, 100), Glare = 0.5, Haze = 2.4 },
	ColorCorrection = { TintColor = rgb(255, 226, 214), Saturation = 0, Contrast = 0.14, Brightness = 0 },
	Bloom = { Intensity = 1, Threshold = 1.2, Size = 40 },
	SunRays = { Intensity = 0.35, Spread = 1 },
	Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(240, 180, 170) },
}

-- Nuit : clair de lune. Bleu froid, couleurs retenues, mais le relief, les chemins et les ennemis
-- restent lisibles sans lanterne : la lumière vient du ciel (ambiantes et exposition), pas de lampes.
local NIGHT: Preset = {
	Lighting = {
		Ambient = rgb(62, 70, 98),
		OutdoorAmbient = rgb(104, 118, 160),
		Brightness = 1.5,
		ColorShift_Top = rgb(150, 170, 220),
		ExposureCompensation = 0.3,
	},
	Atmosphere = { Density = 0.3, Offset = 0.12, Color = rgb(78, 92, 130), Decay = rgb(42, 50, 82), Glare = 0, Haze = 1 },
	ColorCorrection = { TintColor = rgb(222, 232, 255), Saturation = -0.12, Contrast = 0.08, Brightness = 0.03 },
	Bloom = { Intensity = 0.5, Threshold = 1.4, Size = 24 },
	SunRays = { Intensity = 0.04, Spread = 0.3 },
	Clouds = { Cover = 0.45, Density = 0.55, Color = rgb(104, 116, 146) },
}

-- Anomalie : ciel bouché, lumière rouge sang, brouillard si lourd qu'on ne voit plus l'horizon.
local ANOMALY: Preset = {
	Lighting = {
		Ambient = rgb(60, 0, 6),
		OutdoorAmbient = rgb(90, 6, 10),
		Brightness = 0.35,
		ColorShift_Top = rgb(255, 30, 30),
		ExposureCompensation = -0.35,
	},
	Atmosphere = { Density = 0.62, Offset = 0, Color = rgb(120, 8, 12), Decay = rgb(30, 0, 2), Glare = 0.9, Haze = 6 },
	ColorCorrection = { TintColor = rgb(255, 140, 140), Saturation = -0.25, Contrast = 0.45, Brightness = -0.08 },
	Bloom = { Intensity = 1.4, Threshold = 0.9, Size = 48 },
	SunRays = { Intensity = 0, Spread = 0 },
	Clouds = { Cover = 1, Density = 0.95, Color = rgb(60, 4, 8) },
}

-- La journée : (heure, préréglage), par heures croissantes, de 0 à 24.
local KEYFRAMES: { { hour: number, preset: Preset } } = {
	{ hour = 0, preset = NIGHT },
	{ hour = 5.2, preset = NIGHT },
	{ hour = 6.5, preset = DAWN },
	{ hour = 9, preset = DAY },
	{ hour = 16.5, preset = DAY },
	{ hour = 18.3, preset = DUSK },
	{ hour = 20, preset = NIGHT },
	{ hour = 24, preset = NIGHT },
}

local LightingPresets = {}

LightingPresets.ANOMALY = ANOMALY
-- Heure affichée par le ciel pendant l'anomalie : minuit, pour que le soleil disparaisse d'un coup.
LightingPresets.ANOMALY_CLOCK_TIME = 0

local function lerpValue(from: any, to: any, alpha: number): any
	if typeof(from) == "Color3" then
		return from:Lerp(to, alpha)
	end
	return from + (to - from) * alpha
end

-- Mélange deux préréglages : alpha = 0 donne `from`, alpha = 1 donne `to`. Retourne une nouvelle table.
function LightingPresets.blend(from: Preset, to: Preset, alpha: number): Preset
	local result: Preset = {}
	for groupName, properties in from do
		local group = {}
		for property, value in properties do
			group[property] = lerpValue(value, to[groupName][property], alpha)
		end
		result[groupName] = group
	end
	return result
end

-- Préréglage de la journée à l'heure `clockTime` (0 à 24). Retourne une nouvelle table, modifiable.
function LightingPresets.atClockTime(clockTime: number): Preset
	for index = 1, #KEYFRAMES - 1 do
		local current, following = KEYFRAMES[index], KEYFRAMES[index + 1]
		if clockTime >= current.hour and clockTime <= following.hour then
			local alpha = (clockTime - current.hour) / (following.hour - current.hour)
			return LightingPresets.blend(current.preset, following.preset, alpha)
		end
	end
	return LightingPresets.blend(NIGHT, NIGHT, 0)
end

return LightingPresets
