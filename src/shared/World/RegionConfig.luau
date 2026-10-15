--!strict
--[[
	RegionConfig
	Plan de la Région 1 ("Les Terres de la Cloche") : régions, lieux, portes et ancres.

	C'est le CONTRAT entre le générateur de carte (Server/WorldBuild) et les systèmes de jeu :
		- le générateur construit la géométrie AUTOUR des positions clés de LAYOUT, et pose une ancre
		  (Part invisible taggée ANCHOR_TAG, attribut AnchorId) pour chaque entrée de ANCHORS ;
		- les systèmes (quêtes, PNJ, ennemis, mécanismes...) ne connaissent AUCUNE coordonnée :
		  ils cherchent leurs ancres par AnchorId (voir WorldAnchors côté serveur).
	Changer une position ici déplace le lieu pour tout le monde après une reconstruction de la carte.

	Coordonnées : LOCALES à la région, en studs. Monde = ORIGIN + locale. Y = hauteur.
	Le nord est -Z (le village regarde vers le nord : chapelle, puis la cathédrale au loin).

	La région est construite loin de l'origine (ORIGIN) pour ne rien toucher de ce qui existe déjà
	autour du Baseplate d'origine (le Baseplate par défaut de Roblox couvre ±1024 studs).
]]

export type Box = { min: Vector3, max: Vector3 }

export type Region = {
	id: string,
	name: string,
	subtitle: string, -- affiché à l'entrée de la région
	box: Box, -- volume LOCAL de la région (le plus petit qui contient le point gagne, voir regionAt)
	ambience: string, -- clé de préréglage d'ambiance client (RegionAmbience)
	weathers: { string }?, -- météos autorisées (clés de WorldConfig.WEATHERS) ; nil = toutes
	discoveryId: string?, -- découverte accordée à la première entrée
	priority: number, -- plus grand = prioritaire quand deux volumes se chevauchent (crypte sous le village)
}

export type Poi = {
	id: string,
	name: string,
	region: string,
	position: Vector3, -- LOCALE
	icon: string, -- "village" | "chapel" | "well" | "board" | "guild" | "training" | "gate" | "forest" | "secret" | "danger" | "cathedral" | "spawn"
	hiddenUntil: string?, -- id de découverte : le lieu n'apparaît sur la carte qu'une fois découvert
}

-- Conditions d'accès d'une porte de région (vérifiées par le serveur, voir RegionService).
export type GateRule = {
	name: string,
	minRank: string?, -- rang d'aventurier minimal (voir RankConfig)
	quests: { string }?, -- quêtes à avoir terminées
	unlocks: { string }?, -- déblocages requis
	guildLevel: number?, -- niveau de guilde minimal (le joueur doit être membre d'une guilde de ce niveau)
	lockedText: string, -- ce que voit le joueur qui n'a pas le droit d'entrer
	openText: string?, -- message à l'ouverture
	comingSoon: boolean?, -- vrai : même conditions remplies, la zone derrière n'est pas encore construite
}

export type AnchorSpec = {
	kind: string, -- "spawn" | "npc" | "interactable" | "enemy" | "echo" | "volume" | "camera"
	description: string,
}

local ORIGIN = Vector3.new(3000, 0, 0)

-- Positions clés (LOCALES). Le générateur compose ses décors autour d'elles.
local LAYOUT = table.freeze({
	groundHeight = 10, -- hauteur du sol du village (surface du terrain)

	-- Arrivée
	overlook = Vector3.new(20, 46, 250), -- belvédère : point d'apparition, vue plongeante vers le nord
	creatorStage = Vector3.new(-30, 46, 292), -- Sanctuaire des Âmes : scène du créateur de personnage
	southGate = Vector3.new(10, 10, 92), -- entrée sud du village (le chemin du belvédère y descend)

	-- Village des Cendres
	plaza = Vector3.new(0, 10, 0), -- place centrale (rayon ~32), statue de l'Horloger au centre
	plazaRadius = 32,
	well = Vector3.new(-38, 10, 14), -- le puits aux runes (entrée de la crypte)
	chapel = Vector3.new(0, 22, -118), -- chapelle en ruines sur sa butte (entrée au sud, clocher au nord)
	bellTower = Vector3.new(0, 22, -142), -- base du clocher ; la grande cloche fissurée pend en haut (~y 70)
	tavern = Vector3.new(44, 10, -40), -- taverne "Le Sablier Brisé"
	missionBoard = Vector3.new(26, 10, -22), -- tableau des contrats (devant la taverne)
	guildHall = Vector3.new(-46, 10, -44), -- Salle des Serments (guildes)
	guildBoard = Vector3.new(-30, 10, -30), -- tableau des contrats de guilde
	forge = Vector3.new(40, 10, 34),
	cemetery = Vector3.new(-95, 12, -75),
	trainingYard = Vector3.new(115, 10, 20), -- cour d'entraînement (mannequins)
	bossArena = Vector3.new(165, 10, -25), -- cercle de piliers brisés du boss d'entraînement (rayon ~32)
	bossArenaRadius = 32,
	westGate = Vector3.new(-175, 9, -10), -- Porte des Murmures, vers la forêt

	-- Crypte des Veilleurs (sous le village, accès par le puits)
	cryptHall = Vector3.new(-40, -22, -20), -- salle du gardien (≈ 40 x 40, hauteur 16)

	-- Forêt des Murmures
	forestEntrance = Vector3.new(-200, 8, -10),
	forestFork = Vector3.new(-300, 8, -20), -- le chemin se divise : nord (statue), sud (ravin), ouest (profondeurs)
	statueClearing = Vector3.new(-330, 10, -170), -- clairière de la statue ancienne, 3 braziers
	flameSanctum = Vector3.new(-362, 12, -204), -- porte du Sanctuaire des Flammes, dans la paroi
	ravineBridge = Vector3.new(-320, 8, 125), -- milieu du pont détruit (axe nord-sud, ravin profond)
	bridgeShrine = Vector3.new(-320, 9, 178), -- autel caché de l'autre côté du ravin
	frozenPond = Vector3.new(-430, 6, -90), -- étang (Glace), îlot au centre
	conduitTower = Vector3.new(-470, 8, 95), -- tour de guet en ruine (Foudre)
	gravityRuins = Vector3.new(-245, 8, 62), -- ruines au bloc déplaçable (Gravité)
	hollowGate = Vector3.new(-520, 8, 20), -- grille de racines de la Grotte des Échos
	hollowCave = Vector3.new(-575, -6, 20), -- intérieur de la grotte

	-- Approche de la Cathédrale Engloutie (au nord, derrière la chapelle)
	lakeShore = Vector3.new(0, 2, -230),
	causewayEnd = Vector3.new(0, 4, -462),
	cathedralGate = Vector3.new(0, 4, -480), -- Portail Englouti (scellé)
	cathedralSpires = Vector3.new(0, 0, -600), -- silhouette de la cathédrale à demi engloutie (repère visuel)

	-- Limites jouables (murs invisibles + reliefs)
	playableMin = Vector3.new(-700, -60, -640),
	playableMax = Vector3.new(260, 200, 340),
})

local function box(minX: number, minY: number, minZ: number, maxX: number, maxY: number, maxZ: number): Box
	return { min = Vector3.new(minX, minY, minZ), max = Vector3.new(maxX, maxY, maxZ) }
end

local REGIONS: { Region } = {
	{
		id = "overlook",
		name = "Le Belvédère",
		subtitle = "Là où l'on se réveille",
		box = box(-90, 20, 180, 120, 160, 340),
		ambience = "overlook",
		weathers = nil,
		discoveryId = nil,
		priority = 2,
	},
	{
		id = "village",
		name = "Le Village des Cendres",
		subtitle = "Il a déjà brûlé. Il brûlera encore.",
		box = box(-190, -4, -200, 260, 160, 180),
		ambience = "village",
		weathers = nil,
		discoveryId = "region_village",
		priority = 1,
	},
	{
		id = "crypt",
		name = "La Crypte des Veilleurs",
		subtitle = "Ceux qui gardaient l'heure",
		box = box(-85, -45, -65, 5, -4, 30),
		ambience = "crypt",
		weathers = {},
		discoveryId = "region_crypt",
		priority = 5,
	},
	{
		id = "forest",
		name = "La Forêt des Murmures",
		subtitle = "Les arbres répètent ce qu'ils ont entendu",
		box = box(-700, -60, -330, -190, 160, 270),
		ambience = "forest",
		weathers = { "clear", "mist" },
		discoveryId = "region_forest",
		priority = 1,
	},
	{
		id = "hollow",
		name = "La Grotte des Échos",
		subtitle = "Ici, même le silence se répète",
		box = box(-640, -30, -25, -530, 20, 65),
		ambience = "crypt",
		weathers = {},
		discoveryId = "region_hollow",
		priority = 5,
	},
	{
		id = "cathedral",
		name = "Les Rives de la Cathédrale Engloutie",
		subtitle = "Une prière que l'eau n'a pas su éteindre",
		box = box(-200, -60, -640, 200, 200, -200),
		ambience = "lake",
		weathers = { "mist", "clear" },
		discoveryId = "region_cathedral_shore",
		priority = 1,
	},
}

local POIS: { Poi } = {
	{ id = "overlook", name = "Le Belvédère", region = "overlook", position = LAYOUT.overlook, icon = "spawn" },
	{ id = "plaza", name = "Place de l'Horloger", region = "village", position = LAYOUT.plaza, icon = "village" },
	{ id = "well", name = "Le Puits aux Runes", region = "village", position = LAYOUT.well, icon = "well" },
	{ id = "chapel", name = "Chapelle de la Cloche Muette", region = "village", position = LAYOUT.chapel, icon = "chapel" },
	{ id = "tavern", name = "Le Sablier Brisé", region = "village", position = LAYOUT.tavern, icon = "village" },
	{ id = "missions", name = "Tableau des contrats", region = "village", position = LAYOUT.missionBoard, icon = "board" },
	{ id = "guild_hall", name = "Salle des Serments", region = "village", position = LAYOUT.guildHall, icon = "guild" },
	{ id = "training", name = "Cour d'entraînement", region = "village", position = LAYOUT.trainingYard, icon = "training" },
	{ id = "arena", name = "Cercle du Gardien", region = "village", position = LAYOUT.bossArena, icon = "danger" },
	{ id = "cemetery", name = "Cimetière des Oubliés", region = "village", position = LAYOUT.cemetery, icon = "chapel" },
	{ id = "west_gate", name = "Porte des Murmures", region = "village", position = LAYOUT.westGate, icon = "gate" },
	{ id = "crypt", name = "Crypte des Veilleurs", region = "crypt", position = LAYOUT.cryptHall, icon = "secret", hiddenUntil = "region_crypt" },
	{ id = "forest_fork", name = "La Fourche", region = "forest", position = LAYOUT.forestFork, icon = "forest" },
	{ id = "statue", name = "Clairière de la Statue", region = "forest", position = LAYOUT.statueClearing, icon = "forest" },
	{ id = "ravine", name = "Le Pont Rompu", region = "forest", position = LAYOUT.ravineBridge, icon = "danger" },
	{ id = "bridge_shrine", name = "Autel de l'Autre Rive", region = "forest", position = LAYOUT.bridgeShrine, icon = "secret", hiddenUntil = "secret_bridge_shrine" },
	{ id = "pond", name = "L'Étang Figé", region = "forest", position = LAYOUT.frozenPond, icon = "forest" },
	{ id = "tower", name = "Tour du Guetteur", region = "forest", position = LAYOUT.conduitTower, icon = "forest" },
	{ id = "hollow", name = "Grotte des Échos", region = "forest", position = LAYOUT.hollowGate, icon = "secret", hiddenUntil = "region_forest" },
	{ id = "cathedral", name = "Portail Englouti", region = "cathedral", position = LAYOUT.cathedralGate, icon = "cathedral" },
}

-- Portes de région : vérifiées par le serveur quand un joueur interagit avec la porte.
local GATES: { [string]: GateRule } = {
	hollow_gate = {
		name = "Grille de Racines",
		quests = { "bell_silent" },
		lockedText = "Des racines vivantes se resserrent sur la grille. Elles semblent attendre un son qu'elles n'ont pas entendu depuis longtemps.",
		openText = "Au souvenir de la cloche, les racines se retirent en grinçant.",
	},
	cathedral_gate = {
		name = "Portail Englouti",
		minRank = "C",
		quests = { "bell_silent" },
		lockedText = "Le portail est scellé par une lumière froide. Il faut le rang C d'aventurier, et avoir rendu sa voix à la cloche.",
		openText = "Le sceau vous reconnaît... mais au-delà, l'eau noire monte encore. (Région en construction.)",
		comingSoon = true,
	},
	guild_archive = {
		name = "Archives des Serments",
		guildLevel = 3,
		lockedText = "Une serrure à sept blasons. Seuls les membres d'une guilde de niveau 3 en connaissent le secret.",
		openText = "La serrure reconnaît le serment de votre guilde.",
	},
}

--[[
	Ancres que le générateur DOIT poser. Une ancre = une Part invisible (Anchored, CanCollide = false,
	Transparency = 1) taggée ANCHOR_TAG avec l'attribut AnchorId, rangée dans Workspace.World.Anchors.
	Son CFrame donne la position ET l'orientation (LookVector = direction du regard / de l'ouverture).

	Les objets interactifs (tableaux, runes, coffres...) sont des Parts / Models VISIBLES taggés
	INTERACTABLE_TAG avec l'attribut InteractableId : InteractionService y pose son ProximityPrompt.
	La liste des InteractableId attendus est dans MechanismConfig et QuestDefinitions ; le générateur
	reçoit la liste complète via REQUIRED_INTERACTABLES ci-dessous.
]]
local ANCHORS: { [string]: AnchorSpec } = {
	-- Apparition
	spawn_creator = { kind = "spawn", description = "Centre du cercle du Sanctuaire des Âmes (créateur). LookVector vers la caméra du créateur." },
	spawn_village = { kind = "spawn", description = "Belvédère, face au village (LookVector vers le nord, -Z)." },
	spawn_plaza = { kind = "spawn", description = "Réapparition après la mort : bord sud de la place." },
	camera_creator = { kind = "camera", description = "Position de caméra du créateur (regarde spawn_creator)." },
	camera_overlook = { kind = "camera", description = "Plan d'arrivée : caméra derrière le joueur au belvédère, cadrant le village et la cathédrale." },

	-- PNJ (marqueurs ; NpcSpawner y fait apparaître un villageois)
	npc_bellkeeper = { kind = "npc", description = "Aldric le Sonneur, au pied du chemin de la chapelle (bord nord de la place)." },
	npc_elder = { kind = "npc", description = "L'Ancienne, assise près de la statue de l'Horloger." },
	npc_blacksmith = { kind = "npc", description = "Le Forgeron, devant sa forge." },
	npc_child = { kind = "npc", description = "L'Enfant, près du puits." },
	npc_quartermaster = { kind = "npc", description = "Ysolde, maîtresse des contrats, à côté du tableau des contrats." },
	npc_guildmaster = { kind = "npc", description = "Corvin l'Archiviste, devant la Salle des Serments." },
	npc_trainer = { kind = "npc", description = "Bran, maître d'armes, dans la cour d'entraînement." },
	npc_wanderer = { kind = "npc", description = "Le Voyageur Répété, à la Porte des Murmures." },
	npc_villager_1 = { kind = "npc", description = "Villageois de la rue sud." },
	npc_villager_2 = { kind = "npc", description = "Villageois près de la taverne." },
	npc_villager_3 = { kind = "npc", description = "Villageois du cimetière." },

	-- Ennemis (points d'apparition). Attributs posés par le générateur : EnemyId (string), Group (string).
	enemy_forest_1 = { kind = "enemy", description = "Rôdeur des Cendres, chemin de la forêt après la porte." },
	enemy_forest_2 = { kind = "enemy", description = "Rôdeur des Cendres, près de la Fourche." },
	enemy_forest_3 = { kind = "enemy", description = "Gardien de Pierre, sur le chemin nord (statue)." },
	enemy_forest_4 = { kind = "enemy", description = "Murmure (lanceur de sorts), clairière de la statue." },
	enemy_forest_5 = { kind = "enemy", description = "Rôdeur des Cendres, chemin sud vers le ravin." },
	enemy_forest_6 = { kind = "enemy", description = "Murmure, près de l'étang." },
	enemy_forest_7 = { kind = "enemy", description = "Gardien de Pierre, chemin ouest vers la grotte." },
	enemy_crypt_guardian = { kind = "enemy", description = "Le Veilleur de Cendre (élite), au centre de la salle de la crypte." },
	enemy_training_dummy_1 = { kind = "enemy", description = "Mannequin d'entraînement 1." },
	enemy_training_dummy_2 = { kind = "enemy", description = "Mannequin d'entraînement 2." },
	enemy_training_dummy_3 = { kind = "enemy", description = "Mannequin d'entraînement 3." },
	boss_training = { kind = "enemy", description = "Centre du Cercle du Gardien : boss d'entraînement (taggé Boss à l'apparition)." },

	-- Échos : chaque écho a un dossier Workspace.World.EchoPaths.<echoId> avec des Parts "1", "2"...
	-- (invisibles) ; l'ancre marque l'endroit où il commence (déclencheur de proximité).
	echo_bell = { kind = "echo", description = "Début de l'écho du sonneur : parvis de la chapelle." },
	echo_forest = { kind = "echo", description = "Début de l'écho de la fugitive : clairière de la statue." },

	-- Volumes (Parts invisibles dont la taille compte)
	volume_crypt_hall = { kind = "volume", description = "Volume de la salle du gardien (participation au combat de la crypte)." },
	volume_boss_arena = { kind = "volume", description = "Volume du Cercle du Gardien (rencontre du boss d'entraînement)." },
}

local ANCHOR_TAG = "WorldAnchor"
local INTERACTABLE_TAG = "Interactable"

local function toWorld(localPosition: Vector3): Vector3
	return ORIGIN + localPosition
end

local function toLocal(worldPosition: Vector3): Vector3
	return worldPosition - ORIGIN
end

local function isInBox(localPosition: Vector3, b: Box): boolean
	return localPosition.X >= b.min.X
		and localPosition.X <= b.max.X
		and localPosition.Y >= b.min.Y
		and localPosition.Y <= b.max.Y
		and localPosition.Z >= b.min.Z
		and localPosition.Z <= b.max.Z
end

-- Région qui contient la position MONDE donnée (la plus prioritaire), ou nil hors de la région 1.
local function regionAt(worldPosition: Vector3): Region?
	local localPosition = toLocal(worldPosition)
	local best: Region? = nil
	for _, region in REGIONS do
		if isInBox(localPosition, region.box) and (best == nil or region.priority > best.priority) then
			best = region
		end
	end
	return best
end

local function getRegion(id: string): Region?
	for _, region in REGIONS do
		if region.id == id then
			return region
		end
	end
	return nil
end

return table.freeze({
	ORIGIN = ORIGIN,
	LAYOUT = LAYOUT,
	REGIONS = REGIONS,
	POIS = POIS,
	GATES = GATES,
	ANCHORS = ANCHORS,
	ANCHOR_TAG = ANCHOR_TAG,
	INTERACTABLE_TAG = INTERACTABLE_TAG,
	ANCHOR_ATTRIBUTE = "AnchorId",
	INTERACTABLE_ATTRIBUTE = "InteractableId",

	WORLD_FOLDER_NAME = "World", -- Workspace.World (tout ce que le générateur construit)
	STATIC_FOLDER_NAME = "Static",
	ANCHORS_FOLDER_NAME = "Anchors",
	ECHO_PATHS_FOLDER_NAME = "EchoPaths",
	DYNAMIC_FOLDER_NAME = "Dynamic", -- objets dont l'état change (portes, pont, barrière...), manipulés par MechanismService

	toWorld = toWorld,
	toLocal = toLocal,
	isInBox = isInBox,
	regionAt = regionAt,
	getRegion = getRegion,
})
