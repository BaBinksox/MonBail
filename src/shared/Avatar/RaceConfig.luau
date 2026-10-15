--!strict
--[[
	RaceConfig
	Les peuples jouables, partagés serveur + client : identité, récit, origine, et un petit avantage
	compensé par un petit inconvénient. TOUTES les valeurs d'équilibrage sont ici ; RaceService les
	applique côté SERVEUR (le client ne fait qu'afficher).

	Modificateurs (1 = aucun effet) :
		maxHealth     multiplie la vie maximale
		walkSpeed     multiplie la vitesse de marche
		tensionGain   multiplie la Tension gagnée à chaque coup porté (ultime plus ou moins vite)
		damageTaken   multiplie les dégâts reçus
		nightDamageTaken / dayDamageTaken  remplacent damageTaken la nuit / le jour (Enfant de l'Ombre)

	Origines : chaque peuple a une région natale. Seule la Région 1 (Village des Cendres et ses
	environs) existe aujourd'hui : une origine dont la région n'est pas construite est marquée
	`originAvailable = false` et le joueur commence au Belvédère, avec un texte qui le dit. Le jour où
	la région existe, renseigner `startAnchorId` (une ancre réelle de la carte) suffit : un point
	d'arrivée introuvable retombe TOUJOURS sur spawn_village, jamais dans le vide.

	IMPORTANT : `id` est écrit dans la sauvegarde (avatar.race). Ne jamais le renommer.
]]

export type Modifiers = {
	maxHealth: number,
	walkSpeed: number,
	tensionGain: number,
	damageTaken: number,
	nightDamageTaken: number?,
	dayDamageTaken: number?,
}

export type Race = {
	id: string,
	name: string,
	epithet: string, -- courte formule affichée sous le nom
	lore: string,
	advantage: string,
	drawback: string,
	modifiers: Modifiers,
	-- Identité visuelle (appliquée par AvatarAppearance, sans asset externe) :
	heightFactor: number, -- multiplie la taille choisie
	widthFactor: number, -- multiplie la carrure choisie
	pointedEars: boolean, -- oreilles effilées, sculptées en pièces simples
	shadowVeil: boolean, -- voile d'ombre discret autour du personnage
	-- Origine :
	homeRegionId: string, -- identifiant de la région natale (RegionConfig ou région future)
	originName: string,
	originAvailable: boolean, -- false : région pas encore construite (départ au Belvédère)
	startAnchorId: string, -- ancre d'arrivée après la création
}

local DEFAULT_START = "spawn_village"

local RACES: { Race } = {
	{
		id = "human",
		name = "Humain",
		epithet = "Les enfants du Village des Cendres",
		lore = "Votre peuple a bâti ce village, puis l'a vu s'arrêter à 3 h 17. Têtus, adaptables, les humains apprennent vite à frapper là où ça compte.",
		advantage = "Adaptables : +10 % de Tension gagnée à chaque coup (ultime plus tôt).",
		drawback = "Sans don naturel : +5 % de dégâts reçus.",
		modifiers = { maxHealth = 1, walkSpeed = 1, tensionGain = 1.1, damageTaken = 1.05 },
		heightFactor = 1,
		widthFactor = 1,
		pointedEars = false,
		shadowVeil = false,
		homeRegionId = "village",
		originName = "Le Village des Cendres",
		originAvailable = true,
		startAnchorId = DEFAULT_START,
	},
	{
		id = "elf",
		name = "Elfe",
		epithet = "Les veilleurs des forêts d'Ellendor",
		lore = "Les vôtres ont quitté les forêts d'Ellendor quand les arbres ont cessé de vieillir. Plus légers que les humains, plus fragiles aussi.",
		advantage = "Pas légers : +8 % de vitesse de marche.",
		drawback = "Constitution fine : −10 % de vie maximale.",
		modifiers = { maxHealth = 0.9, walkSpeed = 1.08, tensionGain = 1, damageTaken = 1 },
		heightFactor = 1.05,
		widthFactor = 0.92,
		pointedEars = true,
		shadowVeil = false,
		homeRegionId = "elf_forest",
		originName = "Les forêts d'Ellendor",
		originAvailable = false,
		startAnchorId = DEFAULT_START,
	},
	{
		id = "dwarf",
		name = "Nain",
		epithet = "Les forgerons des Monts de Brasegrise",
		lore = "Sous les Monts de Brasegrise, vos ancêtres forgeaient encore quand l'horloge s'est figée. Massifs, increvables, mais pas pressés.",
		advantage = "Robustes : +15 % de vie maximale.",
		drawback = "Jambes courtes : −7 % de vitesse de marche.",
		modifiers = { maxHealth = 1.15, walkSpeed = 0.93, tensionGain = 1, damageTaken = 1 },
		heightFactor = 0.86,
		widthFactor = 1.12,
		pointedEars = false,
		shadowVeil = false,
		homeRegionId = "dwarf_halls",
		originName = "Les Monts de Brasegrise",
		originAvailable = false,
		startAnchorId = DEFAULT_START,
	},
	{
		id = "shadowborn",
		name = "Enfant de l'Ombre",
		epithet = "Ceux que le Néant a laissés revenir",
		lore = "Vous êtes né du côté où la lumière ne va pas. L'obscurité vous protège ; le grand jour vous trouve plus vulnérable.",
		advantage = "Né de l'ombre : −12 % de dégâts reçus la nuit.",
		drawback = "Ébloui : +6 % de dégâts reçus le jour.",
		modifiers = { maxHealth = 1, walkSpeed = 1, tensionGain = 1, damageTaken = 1, nightDamageTaken = 0.88, dayDamageTaken = 1.06 },
		heightFactor = 1,
		widthFactor = 0.96,
		pointedEars = false,
		shadowVeil = true,
		homeRegionId = "umbral_marches",
		originName = "Les Marches d'Ombre",
		originAvailable = false,
		startAnchorId = DEFAULT_START,
	},
}

local function getById(id: any): Race
	for _, race in RACES do
		if race.id == id then
			return race
		end
	end
	return RACES[1]
end

local function indexOf(id: any): number
	for index, race in RACES do
		if race.id == id then
			return index
		end
	end
	return 1
end

return table.freeze({
	ATTRIBUTE = "Race", -- attribut (string = id du peuple) posé par le serveur sur le Player
	DEFAULT_RACE_ID = "human", -- profils créés avant les peuples : humains (apparence intacte)
	DEFAULT_START_ANCHOR = DEFAULT_START,
	RACES = RACES,
	getById = getById,
	indexOf = indexOf,
	-- Bornes des proportions finales (choix du joueur x facteur du peuple).
	MIN_HEIGHT_SCALE = 0.75,
	MAX_HEIGHT_SCALE = 1.2,
	MIN_WIDTH_SCALE = 0.7,
	MAX_WIDTH_SCALE = 1.25,
})
