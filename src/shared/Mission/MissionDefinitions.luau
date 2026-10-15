--!strict
--[[
	MissionDefinitions
	Les contrats du tableau du village (Ysolde). Données uniquement : MissionService les exécute.

	Cycle de vie d'un contrat pour un joueur :
		verrouillé -> DISPONIBLE (rang, quêtes, déblocages, groupe) -> ACCEPTÉ (actif) -> objectifs
		atteints = TERMINÉ -> le joueur le rend au tableau -> RÉCOMPENSÉ.
	La récompense a une clé unique : "mission:<id>" (contrat unique) ou "cycle:mission:<id>:<cycle>"
	(contrat répétable) : impossible d'être payé deux fois pour le même cycle, même après une
	reconnexion ou des requêtes répétées.

	Rotation (`rotation`) :
		"once"    une seule fois ;
		"daily"   une fois par jour (cycle = date UTC, voir MissionConfig.DAILY_RESET_HOUR_UTC) ;
		"weekly"  une fois par semaine (cycle = numéro de semaine UTC).

	Objectifs : mêmes types que les quêtes (talk, examine, interact, collect, explore, echo, puzzle,
	kill, item) + "mechanism" (activer le mécanisme `target`, voir MechanismConfig).
	`deliver` : objets RETIRÉS de l'inventaire au moment de rendre le contrat (contrats de récupération).
	`group` : contrat de groupe, accepté seulement dans un groupe d'au moins `minMembers` joueurs.
	Les éliminations profitent à tout le groupe à proximité (voir DamageService / PartyService).
	`validatesRank` : mission de validation exigée par RankConfig pour ce rang.
]]

export type Objective = {
	id: string,
	type: string,
	target: string,
	count: number,
	text: string,
}

export type Mission = {
	id: string,
	name: string,
	category: "elimination" | "exploration" | "relic" | "investigation" | "group" | "boss" | "validation",
	description: string,
	minRank: string,
	prerequisites: { quests: { string }?, unlocks: { string }? },
	rotation: "once" | "daily" | "weekly",
	objectives: { Objective },
	deliver: { [string]: number }?,
	group: { minMembers: number }?,
	validatesRank: string?,
	rewards: { xp: number?, reputation: number?, items: { [string]: number }? },
}

local function objective(id: string, kind: string, target: string, count: number, text: string): Objective
	return { id = id, type = kind, target = target, count = count, text = text }
end

local MISSIONS: { Mission } = {
	-- Rang E ----------------------------------------------------------------------------------
	{
		id = "hunt_prowlers",
		name = "Cendres errantes",
		category = "elimination",
		description = "Les Rôdeurs des Cendres rôdent jusqu'à la Porte des Murmures. Repoussez-les.",
		minRank = "E",
		prerequisites = {},
		rotation = "daily",
		objectives = { objective("kill", "kill", "ash_prowler", 5, "Vaincre 5 Rôdeurs des Cendres") },
		rewards = { xp = 120, reputation = 15 },
	},
	{
		id = "relic_ashes",
		name = "Ce qui reste du feu",
		category = "relic",
		description = "Le forgeron paie bien les éclats de cendre : ils gardent la chaleur d'un incendie qui n'a jamais fini.",
		minRank = "E",
		prerequisites = {},
		rotation = "daily",
		objectives = { objective("gather", "item", "ash_shard", 3, "Récupérer 3 Éclats de cendre") },
		deliver = { ash_shard = 3 },
		rewards = { xp = 90, reputation = 20 },
	},
	{
		id = "scout_forest",
		name = "Ce que cache la forêt",
		category = "exploration",
		description = "Personne n'est revenu de la forêt avec une carte. Allez voir, et revenez.",
		minRank = "E",
		prerequisites = {},
		rotation = "once",
		objectives = {
			objective("enter", "explore", "forest", 1, "Entrer dans la Forêt des Murmures"),
			objective("witness", "echo", "echo_forest", 1, "Assister à l'écho de la clairière de la statue"),
		},
		rewards = { xp = 150, reputation = 20 },
	},
	{
		id = "circle_daily",
		name = "Le Gardien revient toujours",
		category = "boss",
		description = "Le Gardien du Cercle s'est relevé. Faites-le tomber, et rembobinez si le ciel rougit.",
		minRank = "E",
		prerequisites = { quests = { "circle_trial" } },
		rotation = "daily",
		objectives = { objective("boss", "kill", "training_boss", 1, "Vaincre le Gardien de l'Anomalie") },
		rewards = { xp = 200, reputation = 20 },
	},
	{
		id = "group_guardians",
		name = "Briser la pierre",
		category = "group",
		description = "Les Gardiens de Pierre bloquent les chemins de la forêt. À plusieurs, leur garde ne tient pas.",
		minRank = "E",
		prerequisites = {},
		rotation = "weekly",
		group = { minMembers = 2 },
		objectives = { objective("kill", "kill", "stone_guardian", 3, "Vaincre 3 Gardiens de Pierre (en groupe)") },
		rewards = { xp = 260, reputation = 35 },
	},

	-- Rang D ----------------------------------------------------------------------------------
	{
		id = "hunt_whispers",
		name = "Faire taire les Murmures",
		category = "elimination",
		description = "Les Murmures sèment des zones de mort dans les clairières. Dispersez-les.",
		minRank = "D",
		prerequisites = {},
		rotation = "daily",
		objectives = { objective("kill", "kill", "whisper", 4, "Vaincre 4 Murmures") },
		rewards = { xp = 180, reputation = 20 },
	},
	{
		id = "investigate_bridge",
		name = "Le pont qui se souvient",
		category = "investigation",
		description = "Un voyageur jure avoir traversé le ravin sur un pont qui n'existe plus. Trouvez comment.",
		minRank = "D",
		prerequisites = { quests = { "bell_silent" } },
		rotation = "once",
		objectives = {
			objective("anchor", "mechanism", "bridge_anchor", 1, "Rembobiner l'instant près de l'ancre du pont rompu"),
			objective("shrine", "examine", "chest_bridge_shrine", 1, "Atteindre l'autel de l'autre rive"),
		},
		rewards = { xp = 220, reputation = 25 },
	},
	{
		id = "relic_hollow",
		name = "L'Écrin des Échos",
		category = "relic",
		description = "Les racines se sont retirées. Au cœur de la Grotte des Échos, quelque chose attend d'être trouvé.",
		minRank = "D",
		prerequisites = { unlocks = { "forest_hollow" } },
		rotation = "once",
		objectives = { objective("hollow", "examine", "chest_hollow", 1, "Ouvrir l'Écrin des Échos") },
		rewards = { xp = 200, reputation = 25 },
	},
	{
		id = "rank_exam_c",
		name = "Examen du Veilleur",
		category = "validation",
		description = "Ysolde ne recommande au rang C que ceux qui ont tenu face au Veilleur et brisé la pierre.",
		minRank = "D",
		prerequisites = { quests = { "bell_silent" } },
		rotation = "once",
		validatesRank = "C",
		objectives = {
			objective("watcher", "kill", "ash_watcher", 1, "Vaincre le Veilleur de Cendre"),
			objective("stone", "kill", "stone_guardian", 2, "Vaincre 2 Gardiens de Pierre"),
			objective("hollow", "explore", "hollow", 1, "Entrer dans la Grotte des Échos"),
		},
		rewards = { xp = 300, reputation = 40 },
	},

	-- Rang C ----------------------------------------------------------------------------------
	{
		id = "cathedral_scouting",
		name = "Le Portail Englouti",
		category = "exploration",
		description = "Approchez le Portail Englouti et voyez s'il vous reconnaît.",
		minRank = "C",
		prerequisites = { quests = { "bell_silent" } },
		rotation = "once",
		objectives = { objective("gate", "examine", "cathedral_gate", 1, "Faire reconnaître votre rang par le Portail Englouti") },
		rewards = { xp = 300, reputation = 40 },
	},
}

local byId: { [string]: Mission } = {}
for _, mission in MISSIONS do
	byId[mission.id] = mission
end

return table.freeze({
	MISSIONS = MISSIONS,
	getMission = function(id: any): Mission?
		return if type(id) == "string" then byId[id] else nil
	end,
	MAX_ACTIVE = 5, -- contrats actifs en même temps
	DAILY_RESET_HOUR_UTC = 4, -- le "jour" des contrats change à 4 h UTC
	BOARD_RANGE = 24, -- studs : accepter / rendre un contrat se fait près du tableau ou d'Ysolde
	CATEGORY_NAMES = {
		elimination = "Élimination",
		exploration = "Exploration",
		relic = "Récupération",
		investigation = "Enquête temporelle",
		group = "Groupe",
		boss = "Boss",
		validation = "Validation de rang",
	},
})
