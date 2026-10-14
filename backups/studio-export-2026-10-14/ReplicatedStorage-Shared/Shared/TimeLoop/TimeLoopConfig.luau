--!strict
--[[
	TimeLoopConfig
	Constantes partagées (serveur + client) du système de Time-Loop.
	Toute valeur d'équilibrage se règle ici, jamais en dur dans la logique.
]]

local TimeLoopConfig = {
	-- Enregistrement ---------------------------------------------------------
	RECORD_INTERVAL = 0.1, -- secondes entre deux snapshots (0.1 = 10 Hz)
	BUFFER_DURATION = 6, -- secondes d'historique conservées (> REWIND_WINDOW pour garder une marge)

	-- Rembobinage ------------------------------------------------------------
	REWIND_WINDOW = 5, -- secondes de timeline remontées par un rewind
	REWIND_PLAYBACK_DURATION = 1.5, -- durée réelle de la lecture inversée (5 s rejouées en 1.5 s)
	REWIND_COOLDOWN = 3, -- secondes minimum entre la fin d'un rewind et le suivant

	-- Anomalie temporelle : état critique ouvert par TimeLoopService.openAnomaly().
	-- Le joueur est figé et a ANOMALY_WINDOW secondes pour rembobiner, sinon il meurt.
	ANOMALY_WINDOW = 4,

	-- Si true, le serveur accepte aussi un rewind hors anomalie (soumis au cooldown).
	-- À passer à false pour le vrai jeu : R ne fonctionnera alors que pendant une anomalie.
	DEBUG_FREE_REWIND = true,
	DEBUG_LOGS = true,

	-- Identification ---------------------------------------------------------
	ENTITY_TAG = "TimeLoopEntity", -- tag CollectionService des PNJ/boss à enregistrer
	COMBAT_STATE_ATTRIBUTE = "CombatState", -- attribut (string) du Model lu/restauré par le logger

	-- Client -----------------------------------------------------------------
	REWIND_KEY = Enum.KeyCode.R,

	-- Immersion du rembobinage (client) -----------------------------------------
	-- >>> SON DU TIME LOOP : mets ici l'ID de ton chœur, au format "rbxassetid://123456" ("" = silence).
	-- Placeholder : "Heavenly Presence Eerie Choral Tones Dark" (ProSoundEffects, bibliothèque Roblox),
	-- des voix chorales sombres et réverbérées. Autre piste du même catalogue : 9125439864
	-- "Choral Drone Eerie Tones Hollow Reverberant".
	REWIND_SOUND_ID = "rbxassetid://9125602726",
	REWIND_SOUND_VOLUME = 0.7,
	-- Le son se déforme pendant le rewind : sa hauteur glisse jusqu'à cette valeur (1 = normal, 0.5 = une octave plus bas).
	REWIND_SOUND_END_OCTAVE = 0.5,
	REWIND_SOUND_FADE_OUT = 1.6, -- secondes de fondu de sortie, à la fin du rembobinage
	-- Lassitude : chaque rewind lancé moins de REWIND_SOUND_FATIGUE_WINDOW secondes après le précédent
	-- joue le chœur un cran moins fort (x REWIND_SOUND_FATIGUE_FACTOR), sans descendre sous le minimum.
	REWIND_SOUND_FATIGUE_WINDOW = 90,
	REWIND_SOUND_FATIGUE_FACTOR = 0.75,
	REWIND_SOUND_MIN_VOLUME_RATIO = 0.35,

	-- >>> IMAGES DE GLITCH : des textures de "neige" plaquées sur tout l'écran pendant l'anomalie et
	-- le rembobinage. Ajoute les tiennes à la liste (une liste vide = glitch sans images).
	-- Placeholders : deux decals gratuits de la bibliothèque Roblox, lus par leur aperçu.
	GLITCH_IMAGES = {
		"rbxthumb://type=Asset&id=16174602951&w=420&h=420", -- neige cathodique à bandes
		"rbxthumb://type=Asset&id=15455049436&w=420&h=420", -- bruit de pixels
	},
	ANOMALY_MESSAGE = "ANOMALIE TEMPORELLE - REMBOBINEZ !",
}

return table.freeze(TimeLoopConfig)
