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
	looped: boolean, -- false = courte phrase jouée une fois (victoire)
}

export type RegionMusic = {
	day: string, -- clé de TRACKS
	night: string?, -- clé de TRACKS la nuit (absente : `day` toute la journée)
}

local DEFAULT_FADE_IN = 3
local DEFAULT_FADE_OUT = 2.5

local function track(id: string, volume: number, criteria: string, fadeIn: number?, fadeOut: number?, looped: boolean?): Track
	return { id = id, volume = volume, fadeIn = fadeIn or DEFAULT_FADE_IN, fadeOut = fadeOut or DEFAULT_FADE_OUT, criteria = criteria, looped = looped ~= false }
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

	-- États de combat (CombatMusicController) : même famille sonore que les thèmes de région
	-- (piano, cordes, harpe, chœur féminin discret), plus d'élan ; jamais de métal ni d'électro.
	hostile = track("", 0.28, "Présence hostile : nappe de cordes tendue, pulsation grave très discrète, quelques notes de piano ; sans percussion forte ; boucle.", 2.5, 3),
	combat = track("", 0.36, "Combat : cordes rythmées (ostinato), piano qui martèle sobrement, chœur féminin en appui, percussions orchestrales mesurées ; épique mais mélancolique ; boucle de 1 à 3 min.", 1.2, 3.5),
	boss = track("", 0.42, "Boss : orchestre complet, chœur plus présent, thème grave et tragique ; montée progressive ; boucle.", 1.5, 4),
	anomaly = track("", 0.34, "Anomalie temporelle : cordes suspendues, chœur féminin aigu et lointain, piano à l'envers ou étiré ; tension sans horreur.", 0.6, 1.5),
	victory = track("", 0.38, "Victoire / accalmie : courte phrase de piano et cordes (5 à 10 s), résolution douce, soulagement ; jouée une fois.", 0.8, 2.5, false),
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

--[[
	Petits sons de retour (catégorie Effets), courts et doux. Vides = silence.
	>>> Chercher des sons de 0,5 à 2 s, sans attaque brutale :
		mechanism   « soft chime », « magic sparkle soft », « stone click resonant »
		secret      « mystery reveal soft », « harp glissando short »
		regionEnter « soft whoosh airy » (facultatif : le titre suffit souvent)
]]
local FEEDBACK_SOUNDS = {
	mechanism = { id = "", volume = 0.35 },
	secret = { id = "", volume = 0.3 },
	regionEnter = { id = "", volume = 0.2 },
}

--[[
	EFFETS SONORES DE COMBAT, DE MAGIE ET DE MOBILITÉ (catégorie Effets, joués par SfxPlayer).
	Deux sortes de sources :
		- "rbxasset://sounds/..." : sons LIVRÉS AVEC ROBLOX (épée classique, sons du personnage par
		  défaut), présents dans toute installation, sans ID de catalogue. À confirmer en jeu : un
		  fichier absent est simplement silencieux (avertissement dans la sortie) ;
		- "" : emplacement vide, à remplir avec un son vérifié (critères dans `criteria`).
	pitch / pitchVariance : hauteur de base et variation aléatoire (évite la répétition mécanique) ;
	minInterval : délai minimal entre deux lectures du même son ; maxConcurrent : copies simultanées.
]]
export type Sfx = {
	id: string,
	volume: number,
	pitch: number,
	pitchVariance: number,
	minInterval: number,
	maxConcurrent: number,
	criteria: string,
}
local function sfx(id: string, volume: number, criteria: string, pitch: number?, variance: number?, minInterval: number?, maxConcurrent: number?): Sfx
	return { id = id, volume = volume, pitch = pitch or 1, pitchVariance = variance or 0.05, minInterval = minInterval or 0.04, maxConcurrent = maxConcurrent or 3, criteria = criteria }
end
local CLASSIC_SLASH = "rbxasset://sounds/swordslash.wav"
local CLASSIC_LUNGE = "rbxasset://sounds/swordlunge.wav"
local CLASSIC_UNSHEATH = "rbxasset://sounds/unsheath.wav"
local CHARACTER_JUMP = "rbxasset://sounds/action_jump.mp3"

local SFX: { [string]: Sfx } = {
	-- Épée
	swordSwing = sfx(CLASSIC_SLASH, 0.45, "Souffle de lame court (whoosh), sans impact.", 1.05, 0.08),
	swordSwingHeavy = sfx(CLASSIC_LUNGE, 0.55, "Souffle de lame lourd, plus grave.", 0.9, 0.05),
	swordHit = sfx("", 0.6, "Lame qui entaille (chair / tissu), court, sans cri.", 1, 0.08),
	swordBlocked = sfx("", 0.6, "Métal contre métal ou pierre, sec et mat (coup arrêté par une garde).", 1, 0.06),
	parryPerfect = sfx(CLASSIC_UNSHEATH, 0.65, "Tintement métallique clair et réverbéré (parade parfaite).", 1.35, 0.03, 0.1, 2),
	postureBreak = sfx("", 0.7, "Craquement sourd + souffle (garde brisée).", 1, 0.05, 0.2, 2),
	chargeReady = sfx(CLASSIC_UNSHEATH, 0.4, "Montée métallique brève (attaque chargée prête).", 1.6, 0.02, 0.3, 1),
	plungeImpact = sfx("", 0.6, "Impact lourd au sol + poussière (attaque plongeante).", 1, 0.05, 0.2, 2),
	-- Mobilité
	dodge = sfx("", 0.45, "Souffle d'air rapide (esquive / dash).", 1, 0.08),
	dodgePerfect = sfx("", 0.5, "Souffle + éclat cristallin discret (esquive parfaite).", 1, 0.03, 0.2, 1),
	doubleJump = sfx(CHARACTER_JUMP, 0.5, "Impulsion d'énergie courte, légèrement magique.", 1.35, 0.05, 0.15, 2),
	sprintStart = sfx("", 0.25, "Pas qui s'accélèrent / souffle léger (démarrage du sprint).", 1, 0.05, 0.5, 1),
	-- Ressources
	manaFull = sfx("", 0.25, "Note cristalline douce (Mana plein).", 1, 0.02, 1, 1),
	manaEmpty = sfx("", 0.3, "Souffle étouffé (sort impossible : Mana insuffisant).", 1, 0.03, 0.4, 1),
	concentrate = sfx("", 0.3, "Nappe magique montante, très douce (Concentration).", 1, 0.02, 0.5, 1),
	ultimateReady = sfx("", 0.4, "Accord bref et lumineux (jauge de Tension pleine).", 1, 0, 2, 1),
	ultimateActivate = sfx("", 0.7, "Montée puissante + impact (technique ultime).", 1, 0.02, 0.5, 2),
	-- Sorts : lancement et impact par élément
	cast_pyromancy = sfx("", 0.5, "Souffle de flamme projeté (whoosh enflammé).", 1, 0.06),
	impact_pyromancy = sfx("", 0.55, "Explosion de feu courte, crépitement.", 1, 0.06),
	cast_ice = sfx("", 0.45, "Cristallisation, givre qui se forme (aigu, fin).", 1, 0.05),
	impact_ice = sfx("", 0.5, "Éclat de glace qui se brise.", 1, 0.06),
	cast_lightning = sfx("", 0.5, "Crépitement électrique sec.", 1, 0.08),
	impact_lightning = sfx("", 0.55, "Claquement de foudre court (pas de tonnerre long).", 1, 0.06),
	cast_shadow = sfx("", 0.45, "Murmure grave, souffle sombre (pas de cri).", 1, 0.05),
	impact_shadow = sfx("", 0.5, "Impact étouffé et aspirant.", 1, 0.05),
	cast_antimatter = sfx("", 0.45, "Distorsion, son inversé qui se contracte.", 1, 0.04),
	impact_antimatter = sfx("", 0.55, "Implosion sourde.", 1, 0.05),
	cast_gravity = sfx("", 0.5, "Grondement grave, pression.", 1, 0.04),
	impact_gravity = sfx("", 0.55, "Écrasement lourd, sol qui tremble.", 1, 0.05),
	reaction = sfx("", 0.55, "Éclat bref, mélange de deux éléments (réaction élémentaire).", 1, 0.05, 0.25, 2),
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
	FEEDBACK_SOUNDS = FEEDBACK_SOUNDS,
	SFX = SFX,
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
	-- Une piste interrompue (exploration coupée par un combat) reprend où elle en était si on y
	-- revient dans ce délai (s), au lieu de repartir du début.
	RESUME_MEMORY = 180,
	-- Musique dynamique de combat (CombatMusicController) : priorités
	-- créateur > anomalie > boss > combat > victoire > présence hostile > région.
	COMBAT_MUSIC = table.freeze({
		UPDATE_INTERVAL = 0.5, -- s entre deux évaluations
		HOSTILE_RADIUS = 32, -- studs : un ennemi vivant plus près = présence hostile
		HOSTILE_ENTER_TIME = 1.5, -- s de présence continue avant d'en changer la musique
		HOSTILE_EXIT_TIME = 6, -- s sans ennemi proche avant de revenir à la région
		COMBAT_EXIT_TIME = 3, -- s après la fin de l'état « en combat » (serveur) avant d'en sortir
		BOSS_RADIUS = 90, -- studs : distance à laquelle un boss réveillé impose sa musique
		VICTORY_DURATION = 8, -- s de phrase de victoire avant le retour au calme
		VICTORY_RADIUS = 60, -- studs : un ennemi vaincu dans ce rayon pendant le combat = victoire
	}),
})
