--!strict
--[[
	GuildConfig
	Règles de données des guildes : limites, rôles et permissions, niveaux de guilde, contrats de guilde
	et cycle de rotation. Aucune logique ici (sauf de petits accesseurs) : les seuils ne sont jamais
	écrits en dur dans les services.

	Trois notions à ne pas confondre (voir aussi RankConfig) :
		1. le RANG D'AVENTURIER (RankConfig) : progression PERSONNELLE de chaque joueur, de E à S ;
		2. le NIVEAU DE GUILDE (LEVELS ci-dessous) : progression COLLECTIVE de la guilde, de 1 à 5,
		   gagnée avec l'XP de guilde des contrats de guilde accomplis ;
		3. le RÔLE dans la guilde (ROLES : chef / officier / membre) : droits d'administration.
	Un contrat de guilde a un PALIER (= niveau de guilde requis). On dit « palier » et non « rang »
	pour ne pas confondre avec le rang d'aventurier.

	Rôles et permissions (PERMISSIONS + TARGET_RULES, revérifiés par GuildRules sur l'état stocké) :
		- un membre ne gère rien (il peut quitter la guilde et recevoir sa part des contrats) ;
		- un officier invite, annule une invitation, exclut des MEMBRES seulement (jamais un officier ni
		  le chef), modifie la description et lance un contrat manuel ; au plus OFFICER_KICKS_PER_HOUR
		  exclusions par heure ;
		- seul le chef promeut / rétrograde, transfère la direction et dissout la guilde.

	Le cycle des contrats est hebdomadaire et calculé en UTC (CYCLE) : tous les serveurs obtiennent le
	même identifiant de cycle au même instant, sans se concerter.

	IMPORTANT : les `id` (contrats, déblocages, rôles) sont écrits dans les sauvegardes. Ne jamais les
	renommer une fois en ligne.
]]

export type Role = "leader" | "officer" | "member"

export type Action =
	"invite"
	| "cancelInvite"
	| "kick"
	| "promote"
	| "demote"
	| "editDescription"
	| "transferLeadership"
	| "dissolve"
	| "startContract"
	| "leave"
	| "claimContractReward"

export type RoleDef = {
	id: Role,
	name: string, -- affiché
	order: number, -- 3 = chef (tri de la liste des membres)
}

export type LevelDef = {
	level: number,
	xp: number, -- XP de guilde TOTALE requise pour atteindre ce niveau
	name: string,
	unlocks: { string }, -- déblocages obtenus en atteignant ce niveau (clés de UNLOCKS)
	comingSoon: boolean?, -- vrai : le niveau s'atteint, mais ce qu'il ouvre n'existe pas encore
}

export type UnlockDef = {
	id: string,
	name: string,
	description: string,
	level: number,
	comingSoon: boolean?,
}

-- Événements de GameEvents qui font progresser un contrat de guilde.
export type ContractEvent = "EnemyDefeated" | "Discovered" | "AnomalyResolved" | "MissionCompleted"

export type ContractObjective = {
	event: ContractEvent,
	-- EnemyDefeated
	enemyIds: { string }?, -- ids d'ennemis acceptés (nil = tous)
	regions: { string }?, -- régions (RegionConfig) où l'ennemi doit tomber (nil = partout)
	bossOnly: boolean?, -- seulement les boss
	minEligibleMembers: number?, -- membres ÉLIGIBLES de la même guilde requis sur l'élimination
	-- AnomalyResolved
	outcome: string?, -- issue exigée ("rewound" = anomalie résolue par rembobinage)
	-- MissionCompleted
	missionIds: { string }?, -- missions acceptées (nil = toutes)
}

export type ContractReward = {
	xp: number?,
	reputation: number?,
	items: { [string]: number }?, -- ids de ItemConfig
}

export type Contract = {
	id: string,
	name: string,
	description: string,
	guildLevel: number, -- palier : niveau de guilde requis
	-- "auto"   : actif automatiquement à chaque cycle pour toute guilde du niveau requis ;
	-- "manual" : un chef ou un officier doit le lancer (action startContract) pendant le cycle.
	activation: "auto" | "manual",
	objective: ContractObjective,
	target: number, -- progression collective à atteindre
	guildXp: number, -- XP de guilde gagnée UNE fois à la complétion
	reward: ContractReward, -- part individuelle de chaque contributeur (au moins 1 contribution)
}

--------------------------------------------------------------------------------
-- Rôles et permissions
--------------------------------------------------------------------------------

local ROLES: { [Role]: RoleDef } = {
	leader = { id = "leader", name = "Chef", order = 3 },
	officer = { id = "officer", name = "Officier", order = 2 },
	member = { id = "member", name = "Membre", order = 1 },
}

-- Qui peut faire quoi (sans regarder la cible). Une action absente = interdite à tous.
local PERMISSIONS: { [Action]: { [Role]: boolean } } = {
	invite = { leader = true, officer = true, member = false },
	cancelInvite = { leader = true, officer = true, member = false },
	kick = { leader = true, officer = true, member = false },
	promote = { leader = true, officer = false, member = false },
	demote = { leader = true, officer = false, member = false },
	editDescription = { leader = true, officer = true, member = false },
	transferLeadership = { leader = true, officer = false, member = false },
	dissolve = { leader = true, officer = false, member = false },
	startContract = { leader = true, officer = true, member = false },
	leave = { leader = true, officer = true, member = true }, -- le chef : seulement s'il est seul (voir GuildRules)
	claimContractReward = { leader = true, officer = true, member = true },
}

-- Actions qui visent un autre membre : TARGET_RULES[action][rôle de l'acteur][rôle de la cible].
-- Personne ne peut viser le chef ; un officier ne vise que des membres.
local TARGET_RULES: { [Action]: { [Role]: { [Role]: boolean } } } = {
	kick = {
		leader = { officer = true, member = true },
		officer = { member = true },
	},
	promote = {
		leader = { member = true }, -- membre -> officier
	},
	demote = {
		leader = { officer = true }, -- officier -> membre
	},
	transferLeadership = {
		leader = { officer = true, member = true },
	},
}

--------------------------------------------------------------------------------
-- Niveaux de guilde et déblocages
--------------------------------------------------------------------------------

local LEVELS: { LevelDef } = {
	{ level = 1, xp = 0, name = "Serment prêté", unlocks = {} },
	{ level = 2, xp = 300, name = "Bannière levée", unlocks = { "guild_contracts_tier2", "guild_banner" } },
	-- Niveau 3 : RegionConfig.GATES.guild_archive exige guildLevel = 3 (Archives des Serments).
	{ level = 3, xp = 900, name = "Gardiens des Archives", unlocks = { "guild_expeditions", "guild_archive" } },
	{ level = 4, xp = 2000, name = "Voix du Cercle", unlocks = { "guild_hall_wing" }, comingSoon = true },
	{ level = 5, xp = 4000, name = "Mémoire Vivante", unlocks = { "guild_relic_vault" }, comingSoon = true },
}

local UNLOCKS: { [string]: UnlockDef } = {
	guild_contracts_tier2 = {
		id = "guild_contracts_tier2",
		name = "Contrats de palier 2",
		description = "Nouveaux contrats de guilde : découvertes et anomalies résolues.",
		level = 2,
	},
	guild_banner = {
		id = "guild_banner",
		name = "Bannière de guilde",
		-- L'affichage de la bannière (Salle des Serments, au-dessus des têtes) n'existe pas encore :
		-- ce déblocage est le droit, que l'interface ou le monde pourront consulter (hasGuildUnlock).
		description = "Le droit d'arborer la bannière de la guilde.",
		level = 2,
	},
	guild_expeditions = {
		id = "guild_expeditions",
		name = "Expéditions",
		description = "Contrat d'expédition : vaincre le Gardien du Cercle avec au moins trois membres de la guilde.",
		level = 3,
	},
	guild_archive = {
		id = "guild_archive",
		name = "Archives des Serments",
		description = "La porte des Archives des Serments reconnaît le serment de la guilde.",
		level = 3,
	},
	guild_hall_wing = {
		id = "guild_hall_wing",
		name = "Aile de la Salle des Serments",
		description = "Contenu à venir.",
		level = 4,
		comingSoon = true,
	},
	guild_relic_vault = {
		id = "guild_relic_vault",
		name = "Chambre des Reliques",
		description = "Contenu à venir.",
		level = 5,
		comingSoon = true,
	},
}

--------------------------------------------------------------------------------
-- Contrats de guilde
--------------------------------------------------------------------------------

local CONTRACTS: { Contract } = {
	{
		id = "gc_cull_forest",
		name = "Éclaircir les Murmures",
		description = "Éliminer ensemble 60 ennemis dans la Forêt des Murmures.",
		guildLevel = 1,
		activation = "auto",
		objective = { event = "EnemyDefeated", regions = { "forest", "hollow" } },
		target = 60,
		guildXp = 120,
		reward = { xp = 120, items = { guild_seal = 1 } },
	},
	{
		id = "gc_crypt_watch",
		name = "La Garde de la Crypte",
		description = "Vaincre 5 fois le Veilleur de Cendre, dans la Crypte des Veilleurs.",
		guildLevel = 1,
		activation = "auto",
		-- "ash_watcher" : id demandé pour le Veilleur de Cendre ; "ash_warden" : id posé aujourd'hui par
		-- le générateur sur l'ancre enemy_crypt_guardian (WorldBuildConfig). Garder les deux tant
		-- qu'EnemyDefinitions n'a pas tranché ; retirer ensuite celui qui n'existe pas.
		objective = { event = "EnemyDefeated", enemyIds = { "ash_watcher", "ash_warden" } },
		target = 5,
		guildXp = 150,
		reward = { xp = 150, items = { guild_seal = 1 } },
	},
	{
		id = "gc_discoveries",
		name = "Cartographes du Néant",
		description = "Faire 10 découvertes (lieux, secrets, échos) entre membres de la guilde.",
		guildLevel = 2,
		activation = "auto",
		objective = { event = "Discovered" },
		target = 10,
		guildXp = 140,
		reward = { xp = 140, items = { guild_seal = 1, echo_fragment = 1 } },
	},
	{
		id = "gc_anomaly",
		name = "Recoudre le Temps",
		description = "Résoudre 3 anomalies de boss par le rembobinage.",
		guildLevel = 2,
		activation = "auto",
		objective = { event = "AnomalyResolved", outcome = "rewound" },
		target = 3,
		guildXp = 180,
		reward = { xp = 180, items = { guild_seal = 2 } },
	},
	{
		id = "gc_expedition",
		name = "Expédition au Cercle du Gardien",
		description = "Vaincre le boss d'entraînement avec au moins 3 membres de la guilde éligibles.",
		guildLevel = 3,
		activation = "manual",
		objective = { event = "EnemyDefeated", enemyIds = { "training_boss" }, minEligibleMembers = 3 },
		target = 1,
		guildXp = 300,
		reward = { xp = 250, items = { guild_seal = 3, echo_fragment = 2 } },
	},
}

--------------------------------------------------------------------------------
-- Cycle de rotation (UTC)
--------------------------------------------------------------------------------

local SECONDS_PER_DAY = 86400

-- Le 1er janvier 1970 (jour 0) était un jeudi : lundi = jour 4.
local EPOCH_MONDAY_DAY = 4

local CYCLE = {
	LENGTH_DAYS = 7, -- durée d'un cycle
	START_WEEKDAY = 1, -- 1 = lundi ... 7 = dimanche (jour où le cycle recommence)
	RESET_HOUR_UTC = 0, -- heure UTC du changement de cycle
	ID_PREFIX = "w", -- identifiant = préfixe + date UTC du début du cycle ("w2026-10-12")
}

export type CycleInfo = {
	id: string,
	startsAt: number, -- os.time() du début du cycle
	endsAt: number, -- os.time() du début du cycle suivant
}

--------------------------------------------------------------------------------
-- Messages d'erreur (codes renvoyés par GuildRequest -> texte affiché)
--------------------------------------------------------------------------------

local ERRORS: { [string]: string } = {
	unknown_action = "Action inconnue.",
	bad_params = "Requête invalide.",
	rate_limited = "Trop de demandes : patientez un instant.",
	busy = "Une demande est déjà en cours.",
	not_loaded = "Votre profil n'est pas encore chargé.",
	not_saveable = "Sauvegarde indisponible : les guildes sont en lecture seule pour vous.",
	internal = "Erreur interne.",
	datastore = "Le registre des guildes ne répond pas. Réessayez plus tard.",
	unavailable = "Le registre des guildes est indisponible sur ce serveur.",
	corrupt = "Les données de cette guilde sont illisibles.",
	exists = "Cette guilde existe déjà.",
	name_invalid = "Nom invalide.",
	name_invalid_length = "Le nom doit compter de 3 à 24 caractères.",
	name_invalid_chars = "Le nom contient des caractères non autorisés (lettres, chiffres, espace, apostrophe et tiret).",
	name_invalid_format = "Le nom doit commencer par une lettre ou un chiffre, sans ponctuation doublée.",
	name_taken = "Ce nom est déjà pris par une autre guilde.",
	description_invalid = "Description invalide.",
	description_too_long = "La description ne doit pas dépasser 140 caractères.",
	text_filtered = "Ce texte a été refusé par le filtre de Roblox.",
	filter_unavailable = "Le filtre de texte ne répond pas : réessayez plus tard.",
	already_in_guild = "Vous faites déjà partie d'une guilde.",
	not_in_guild = "Vous ne faites partie d'aucune guilde.",
	guild_not_found = "Cette guilde n'existe pas.",
	guild_dissolved = "Cette guilde a été dissoute.",
	not_member = "Vous n'êtes pas membre de cette guilde.",
	no_permission = "Votre rôle ne permet pas cette action.",
	target_not_member = "Ce joueur n'est pas membre de la guilde.",
	target_is_self = "Vous ne pouvez pas vous viser vous-même.",
	target_role_forbidden = "Vous ne pouvez pas faire cela à ce membre (rôle trop élevé).",
	officer_limit = "La guilde a déjà le nombre maximal d'officiers.",
	kick_limit = "Limite d'exclusions atteinte pour cette heure.",
	guild_full = "La guilde est complète.",
	invites_full = "Trop d'invitations en attente.",
	already_member = "Ce joueur est déjà membre de la guilde.",
	invite_not_found = "Invitation introuvable.",
	invite_expired = "Cette invitation a expiré.",
	unknown_player = "Joueur introuvable.",
	target_in_guild = "Ce joueur fait déjà partie d'une guilde.",
	leader_must_transfer = "Le chef doit transférer la direction avant de quitter la guilde.",
	leader_must_dissolve = "Vous êtes seul : dissolvez la guilde pour la quitter.",
	dissolve_not_alone = "La dissolution exige que le chef soit le dernier membre.",
	dissolve_name_mismatch = "Retapez exactement le nom de la guilde pour confirmer.",
	contract_unknown = "Contrat inconnu.",
	contract_locked = "Le niveau de la guilde est insuffisant pour ce contrat.",
	contract_not_manual = "Ce contrat est actif automatiquement.",
	contract_already_started = "Ce contrat est déjà lancé pour ce cycle.",
	nothing_to_claim = "Aucune récompense de contrat à recevoir.",
}

--------------------------------------------------------------------------------
-- Index et accesseurs
--------------------------------------------------------------------------------

local contractsById: { [string]: Contract } = {}
for _, contract in CONTRACTS do
	contractsById[contract.id] = contract
end

local function getContract(id: any): Contract?
	return if type(id) == "string" then contractsById[id] else nil
end

local function getUnlock(id: any): UnlockDef?
	return if type(id) == "string" then UNLOCKS[id] else nil
end

local function getLevelDef(level: number): LevelDef
	return LEVELS[math.clamp(math.floor(level), 1, #LEVELS)]
end

-- Niveau de guilde correspondant à une XP de guilde totale.
local function levelForXp(xp: number): number
	local level = 1
	for _, def in LEVELS do
		if xp >= def.xp then
			level = def.level
		end
	end
	return level
end

-- XP totale requise pour le niveau suivant (nil au niveau maximal).
local function nextLevelXp(level: number): number?
	local nextDef = LEVELS[math.floor(level) + 1]
	return if nextDef then nextDef.xp else nil
end

-- Tous les déblocages acquis à `level` (niveaux 1..level).
local function unlocksUpTo(level: number): { string }
	local result: { string } = {}
	for _, def in LEVELS do
		if def.level <= level then
			for _, unlockId in def.unlocks do
				table.insert(result, unlockId)
			end
		end
	end
	return result
end

-- Cycle de contrats qui contient l'instant `now` (os.time(), UTC).
local function getCycle(now: number): CycleInfo
	local length = math.max(1, math.floor(CYCLE.LENGTH_DAYS))
	local shifted = now - CYCLE.RESET_HOUR_UTC * 3600
	local day = math.floor(shifted / SECONDS_PER_DAY)
	local anchorDay = EPOCH_MONDAY_DAY + (CYCLE.START_WEEKDAY - 1)
	local startDay = day - ((day - anchorDay) % length)
	local startsAt = startDay * SECONDS_PER_DAY + CYCLE.RESET_HOUR_UTC * 3600
	return {
		id = CYCLE.ID_PREFIX .. os.date("!%Y-%m-%d", startDay * SECONDS_PER_DAY),
		startsAt = startsAt,
		endsAt = startsAt + length * SECONDS_PER_DAY,
	}
end

-- Cycle précédent (les récompenses du cycle qui vient de finir restent réclamables pendant un cycle).
local function getPreviousCycle(now: number): CycleInfo
	local current = getCycle(now)
	return getCycle(current.startsAt - 1)
end

local function getRoleDef(role: any): RoleDef?
	return if type(role) == "string" then (ROLES :: any)[role] else nil
end

local function errorMessage(code: string?): string
	return if code then ERRORS[code] or code else ""
end

return table.freeze({
	ROLES = ROLES,
	PERMISSIONS = PERMISSIONS,
	TARGET_RULES = TARGET_RULES,
	LEVELS = LEVELS,
	UNLOCKS = UNLOCKS,
	CONTRACTS = CONTRACTS,
	CYCLE = CYCLE,
	ERRORS = ERRORS,

	-- Limites
	MAX_MEMBERS = 30,
	MAX_OFFICERS = 4,
	OFFICER_KICKS_PER_HOUR = 5, -- exclusions par officier et par heure (le chef n'est pas limité)
	NAME_MIN_LENGTH = 3, -- caractères (et non octets)
	NAME_MAX_LENGTH = 24,
	DESCRIPTION_MAX_LENGTH = 140,
	-- Caractères autorisés dans un nom : lettres ASCII, chiffres, NAME_PUNCTUATION et les lettres
	-- accentuées ci-dessous. Un nom commence par une lettre ou un chiffre, sans ponctuation doublée.
	NAME_PUNCTUATION = " '-",
	NAME_ACCENTED_LETTERS = "àâäáãåçéèêëîïíìôöóòõùûüúÿýñœæÀÂÄÁÃÅÇÉÈÊËÎÏÍÌÔÖÓÒÕÙÛÜÚŸÝÑŒÆ",

	-- Invitations
	INVITE_DURATION = 48 * 3600, -- secondes
	MAX_PENDING_INVITES = 15, -- invitations en attente par guilde
	MAX_INCOMING_INVITES = 10, -- invitations reçues gardées par joueur (les plus anciennes sautent)

	-- Journal et idempotence
	LOG_SIZE = 30, -- derniers événements gardés dans record.log
	OPS_RETENTION = 7 * 24 * 3600, -- secondes de rétention des opérations appliquées (record.ops)
	MAX_OPS = 400, -- et au plus autant d'entrées (les plus anciennes sautent en premier)

	-- Réglages des services (secondes)
	NAME_RESERVATION_TTL = 600, -- un nom réservé sans guilde créée est libéré au bout de 10 min
	PENDING_HINT_TTL = 24 * 3600, -- indice "création en cours" gardé au plus un jour
	REFRESH_INTERVAL = 60, -- relecture des guildes qui ont des membres sur ce serveur
	FLUSH_INTERVAL = 30, -- écriture par lots des contributions aux contrats
	INVITES_REFRESH_INTERVAL = 120, -- relecture des invitations reçues (joueurs sans guilde)
	INFO_REFRESH_MIN_AGE = 10, -- getInfo relit la guilde si la copie en mémoire a plus de 10 s
	MESSAGING_MAX_PER_MINUTE = 60, -- publications MessagingService par serveur et par minute
	MAX_QUEUED_BATCHES = 10, -- lots de contributions en attente d'écriture par guilde (DataStore en panne)

	getContract = getContract,
	getUnlock = getUnlock,
	getLevelDef = getLevelDef,
	levelForXp = levelForXp,
	nextLevelXp = nextLevelXp,
	unlocksUpTo = unlocksUpTo,
	getCycle = getCycle,
	getPreviousCycle = getPreviousCycle,
	getRoleDef = getRoleDef,
	errorMessage = errorMessage,
})
