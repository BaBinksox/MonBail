--!strict
--[[
	RankConfig
	Progression individuelle : expérience, rangs d'aventurier, réputation, et ce que chaque rang ouvre.
	C'est le SEUL endroit où vivent les seuils : aucun script ne doit écrire "2000 XP" ou "rang C" en dur.

	Trois notions à ne pas confondre :
		1. le RANG D'AVENTURIER (ici) : progression personnelle, de E à S ;
		2. le NIVEAU DE GUILDE (GuildConfig) : progression collective de la guilde ;
		3. le RÔLE dans la guilde (chef / officier / membre) : droits d'administration.

	Promotion : un rang s'obtient quand TOUTES ses conditions sont remplies (XP, quêtes, missions de
	validation, nombre de découvertes). ProgressionService vérifie après chaque gain et promeut
	automatiquement, d'un rang à la fois. Un rang dont une condition renvoie à un contenu qui n'existe pas
	encore est marqué `comingSoon` : il s'affiche, mais personne ne peut l'atteindre pour l'instant.
]]

export type Rank = {
	id: string, -- "E", "D"... (écrit dans le profil : ne jamais renommer)
	name: string, -- titre affiché
	order: number, -- 1 = premier rang
	xp: number, -- XP totale requise
	quests: { string }?, -- quêtes à avoir terminées
	missions: { string }?, -- missions de validation à avoir réussies au moins une fois
	discoveries: number?, -- nombre minimal de découvertes
	color: Color3,
	perk: string, -- ce que le rang apporte, en une phrase (affiché au joueur)
	comingSoon: boolean?,
}

local RANKS: { Rank } = {
	{
		id = "E",
		name = "Éveillé",
		order = 1,
		xp = 0,
		color = Color3.fromRGB(150, 150, 140),
		perk = "Contrats du village et premières pistes de la forêt.",
	},
	{
		id = "D",
		name = "Arpenteur",
		order = 2,
		xp = 600,
		quests = { "bell_silent" },
		color = Color3.fromRGB(120, 170, 120),
		perk = "Contrats de rang D, chasses aux Murmures, expéditions dans la Grotte des Échos.",
	},
	{
		id = "C",
		name = "Veilleur",
		order = 3,
		xp = 2000,
		missions = { "rank_exam_c" },
		discoveries = 8,
		color = Color3.fromRGB(110, 160, 220),
		perk = "Accès au Portail Englouti (la Cathédrale), contrats de rang C.",
	},
	{
		id = "B",
		name = "Lame du Crépuscule",
		order = 4,
		xp = 5000,
		missions = { "rank_exam_b" },
		discoveries = 16,
		color = Color3.fromRGB(170, 110, 220),
		perk = "Contrats d'élite et variantes de boss. (Contenu à venir.)",
		comingSoon = true,
	},
	{
		id = "A",
		name = "Brise-Heure",
		order = 5,
		xp = 12000,
		missions = { "rank_exam_a" },
		discoveries = 28,
		color = Color3.fromRGB(230, 150, 60),
		perk = "Expéditions de haut rang. (Contenu à venir.)",
		comingSoon = true,
	},
	{
		id = "S",
		name = "Écho Vivant",
		order = 6,
		xp = 30000,
		missions = { "rank_exam_s" },
		discoveries = 40,
		color = Color3.fromRGB(235, 70, 70),
		perk = "Ceux qui se souviennent de tout. (Contenu à venir.)",
		comingSoon = true,
	},
}

local byId: { [string]: Rank } = {}
for _, rank in RANKS do
	byId[rank.id] = rank
end

local function getRank(id: any): Rank
	return byId[id] or RANKS[1]
end

-- Rang suivant (nil si `id` est le dernier).
local function getNextRank(id: any): Rank?
	return RANKS[getRank(id).order + 1]
end

-- true si `rankId` est au moins `minRankId` (un rang inconnu compte comme le premier).
local function isAtLeast(rankId: any, minRankId: string?): boolean
	if minRankId == nil then
		return true
	end
	return getRank(rankId).order >= getRank(minRankId).order
end

return table.freeze({
	RANKS = RANKS,
	DEFAULT_RANK = "E",
	getRank = getRank,
	getNextRank = getNextRank,
	isAtLeast = isAtLeast,

	-- Expérience accordée par source (les ennemis, quêtes et missions ont la leur dans leur définition).
	DISCOVERY_XP = 25, -- première visite d'un lieu, premier écho vu, premier secret trouvé
	-- Réputation : renom auprès des habitants du village. Elle ouvre des contrats spéciaux.
	REPUTATION_NAME = "Renom",

	-- Attribut répliqué posé sur le Player (lisible par tous : affichage au-dessus des têtes, etc.).
	RANK_ATTRIBUTE = "AdventurerRank",
})
