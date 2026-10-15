--!strict
--[[
	AudioConfig
	TOUTE la musique et les sons d'ambiance du jeu, réglés ici (et nulle part ailleurs).
	Lu par les clients : MusicDirector (pistes et fondus), AudioMixer (volumes par catégorie),
	MusicController (musique de région), TimeLoopAudio (chœur du rembobinage).

	IDENTITÉ MUSICALE VISÉE : fantasy médiévale émotionnelle, à la manière des bandes originales
	d'anime de fantasy — piano ou harpe, cordes, chœur discret, mélodies mélancoliques et lumineuses.
	PAS d'horreur, pas de comptine inquiétante. Ne JAMAIS reprendre l'opening d'une œuvre existante
	(sa mélodie, son enregistrement ou une imitation trop proche).

	>>> COMMENT REMPLIR UNE PISTE
		1. Dans Studio : Toolbox > Audio (ou Creator Store), filtrer par durée (pistes de 1 à 4 min,
		   faites pour boucler) et par genre (« Fantasy », « Orchestral », « Ambient », « Cinematic »).
		2. Écouter EN JEU (Play) : une piste visible dans la Toolbox peut être privée ou bloquée pour
		   cette expérience. Si elle ne joue pas, la console affiche un échec de chargement.
		3. Copier l'ID dans `id` au format "rbxassetid://123456". "" = silence (aucune erreur).
	Aucun ID n'est inventé ici : les champs vides attendent une piste choisie et ÉCOUTÉE en jeu.
]]

export type Track = {
	id: string, -- "rbxassetid://..." ; "" = silence
	volume: number, -- volume propre de la piste (0 à 1), avant le réglage « Musique » du joueur
	fadeIn: number, -- secondes
	fadeOut: number, -- secondes
	criteria: string, -- ce qu'il faut chercher pour remplir ce champ
}

export type RegionMusic = {
	day: string, -- clé de TRACKS
	night: string?, -- clé de TRACKS la nuit (absente : `day` toute la journée)
}

local DEFAULT_FADE_IN = 3
local DEFAULT_FADE_OUT = 2.5

local function track(id: string, volume: number, criteria: string, fadeIn: number?, fadeOut: number?): Track
	return { id = id, volume = volume, fadeIn = fadeIn or DEFAULT_FADE_IN, fadeOut = fadeOut or DEFAULT_FADE_OUT, criteria = criteria }
end

local TRACKS: { [string]: Track } = {
	-- Créateur de personnage : le thème principal, celui qu'on associe au jeu.
	-- (L'ancienne piste, « rbxassetid://1839911004 », sonnait comme une comptine d'horreur : retirée.)
	creator = track("", 0.45, "Thème principal : piano solo ou piano + cordes, lent, mélancolique et lumineux, chœur féminin très discret ; 2 à 4 min, boucle propre.", 4, 3),
	overlook = track("", 0.35, "Belvédère : harpe ou piano clair, sentiment d'arrivée, d'espace ; calme.", 4, 3),
	village = track("", 0.3, "Village de jour : luth, flûte ou harpe, cordes douces ; paisible, un peu nostalgique ; pas de percussion forte."),
	village_night = track("", 0.28, "Village de nuit : piano lent, cordes en sourdine ; tranquille, jamais angoissant."),
	forest = track("", 0.3, "Forêt : cordes et bois (flûte, hautbois), mystère doux, nappe aérienne ; peu de rythme."),
	forest_night = track("", 0.26, "Forêt de nuit : nappe aérienne, harpe espacée, chœur très lointain."),
	crypt = track("", 0.26, "Crypte : nappe grave, chœur lointain, cloches feutrées ; tension mesurée, pas de jump-scare."),
	lake = track("", 0.3, "Lac gelé / Portail Englouti : piano cristallin, célesta ou boîte à musique adulte (pas de comptine), cordes froides."),
	-- Régions futures : les clés existent pour qu'une région ajoutée n'ait qu'à les remplir.
	elf_village = track("", 0.3, "Village elfe (futur) : harpe, flûte, chœur éthéré ; lumineux."),
	dwarf_halls = track("", 0.3, "Continent nain (futur) : cuivres graves, cordes, chœur d'hommes discret ; solennel."),
}

-- Région (RegionConfig.REGIONS[].id) -> pistes. Une région absente garde la musique en cours.
local REGION_MUSIC: { [string]: RegionMusic } = {
	overlook = { day = "overlook" },
	village = { day = "village", night = "village_night" },
	forest = { day = "forest", night = "forest_night" },
	crypt = { day = "crypt" },
	hollow = { day = "crypt" },
	cathedral = { day = "lake" },
}

--[[
	Chœur du rembobinage (touche R) : court, féminin, discret. Joué par CHAQUE client quand le
	SERVEUR confirme un rembobinage (TimeLoopRemotes.RewindStarted), jamais sur la simple touche.
	>>> CHŒUR : chercher « Choir Aah female », « Angelic choir short », « Soprano choir swell » :
	    une nappe de 2 à 5 s, sans paroles, sans percussion. "" = rembobinage silencieux.
	    (L'ancien son, « rbxassetid://9125602726 », chœur sombre et inquiétant, ne correspond plus
	    à cette direction ; il peut être remis ici si on préfère l'ambiance d'avant.)
]]
local REWIND_CHOIR = {
	id = "",
	volume = 0.32, -- modéré : un souffle, pas une alarme
	fadeIn = 0.25,
	fadeOut = 1.2,
	maxDuration = 3, -- secondes : le chœur s'efface même si le rembobinage dure plus longtemps
	endOctave = 0.88, -- légère retombée de hauteur pendant le rembobinage (1 = aucune)
	minInterval = 1.5, -- secondes : deux rembobinages rapprochés ne relancent pas le chœur
	fatigueWindow = 60, -- rembobinages rapprochés : de moins en moins fort...
	fatigueFactor = 0.8,
	minVolumeRatio = 0.4, -- ...sans descendre sous ce ratio
}

-- Catégories de volume (multipliées par les réglages du joueur : musique, ambiance, effets).
local CATEGORIES = table.freeze({
	music = "Music",
	ambience = "Ambience",
	sfx = "Sfx",
})

return table.freeze({
	TRACKS = TRACKS,
	REGION_MUSIC = REGION_MUSIC,
	REWIND_CHOIR = REWIND_CHOIR,
	CATEGORIES = CATEGORIES,
	-- Volume maximal de chaque catégorie (réglage du joueur à 100 %).
	CATEGORY_MAX_VOLUME = table.freeze({ Music = 1, Ambience = 1, Sfx = 1 }),
	-- Musique de région : délai avant de changer de piste après un passage de frontière (évite les
	-- allers-retours sonores quand on longe une limite).
	REGION_SETTLE_TIME = 2,
	-- Enchaînement de deux pistes différentes : part du fondu de sortie de l'ancienne pendant
	-- laquelle la nouvelle entre déjà. 0 = la nouvelle attend que l'ancienne se soit tue ; 1 = fondu
	-- croisé complet. Jamais deux pistes à plein volume en même temps.
	CROSSFADE_OVERLAP = 0.6,
})
