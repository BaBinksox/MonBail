--!strict
--[[
	ProfileSchema
	Forme du profil joueur (version 2), valeurs par défaut, migration v1 -> v2 et nettoyage des données
	lues dans le DataStore. Utilisé par ProfileStore ; les services passent par PlayerData.

	Version 1 (prototype) : { version = 1, avatar = {...} }
	Version 2 : on AJOUTE la progression RPG, sans toucher à `avatar` :
		progression  { xp, rank, reputation, promotions = { [rankId] = date } }
		quests       { active = { [questId] = { stage, progress = { [objectiveId] = n }, startedAt } },
		               completed = { [questId] = date } }
		missions     { active = { [missionId] = { progress = { [objectiveId] = n }, acceptedAt, cycle } },
		               completions = { [missionId] = n } }
		discoveries  { [discoveryId] = date }
		unlocks      { [unlockId] = date }
		inventory    { [itemId] = quantité }
		guild        { guildId, joinedAt }   (pointeur : la vérité est l'enregistrement de la guilde)
		ledger       { [rewardKey] = date }  (récompenses déjà versées : jamais deux fois)
		settings     { music, ambience, sfx, uiScale, reducedEffects }
		stats        { kills = { [enemyId] = n }, deaths }

	Règles de prudence :
		- la migration n'ENLÈVE rien : elle complète ce qui manque ;
		- le nettoyage (applyRecord) accepte des données abîmées : une valeur du mauvais type est
		  remplacée par la valeur par défaut DE CE CHAMP seulement, jamais tout le profil ;
		- les dates sont des os.time() (secondes UTC).
]]

export type Progression = {
	xp: number,
	rank: string,
	reputation: number,
	promotions: { [string]: number },
}

export type QuestProgress = {
	stage: number,
	progress: { [string]: number },
	startedAt: number,
}

export type Quests = {
	active: { [string]: QuestProgress },
	completed: { [string]: number },
}

export type MissionProgress = {
	progress: { [string]: number },
	acceptedAt: number,
	cycle: string,
}

export type Missions = {
	active: { [string]: MissionProgress },
	completions: { [string]: number },
}

export type GuildRef = {
	guildId: string?,
	joinedAt: number?,
}

export type Settings = {
	music: number,
	ambience: number, -- volume des ambiances (vent, bourdon) ; absent des anciens profils -> 1
	sfx: number,
	uiScale: number,
	reducedEffects: boolean,
}

export type Stats = {
	kills: { [string]: number },
	deaths: number,
}

export type Profile = {
	version: number,
	avatar: any?, -- écrit et relu par AvatarSerializer (inchangé depuis la v1)
	progression: Progression,
	quests: Quests,
	missions: Missions,
	discoveries: { [string]: number },
	unlocks: { [string]: number },
	inventory: { [string]: number },
	guild: GuildRef,
	ledger: { [string]: number },
	settings: Settings,
	stats: Stats,
}

local VERSION = 2

-- Champs du profil écrits dans le DataStore par ProfileStore (les autres champs de l'enregistrement
-- ne sont jamais touchés).
local FIELDS = {
	"version",
	"avatar",
	"progression",
	"quests",
	"missions",
	"discoveries",
	"unlocks",
	"inventory",
	"guild",
	"ledger",
	"settings",
	"stats",
}

local DEFAULT_RANK = "E"

local ProfileSchema = {}

--------------------------------------------------------------------------------
-- Valeurs par défaut
--------------------------------------------------------------------------------

local function newProgression(): Progression
	return { xp = 0, rank = DEFAULT_RANK, reputation = 0, promotions = {} }
end

local function newSettings(): Settings
	return { music = 1, ambience = 1, sfx = 1, uiScale = 1, reducedEffects = false }
end

function ProfileSchema.new(): Profile
	return {
		version = VERSION,
		avatar = nil,
		progression = newProgression(),
		quests = { active = {}, completed = {} },
		missions = { active = {}, completions = {} },
		discoveries = {},
		unlocks = {},
		inventory = {},
		guild = { guildId = nil, joinedAt = nil },
		ledger = {},
		settings = newSettings(),
		stats = { kills = {}, deaths = 0 },
	}
end

--------------------------------------------------------------------------------
-- Nettoyage (données lues dans le DataStore)
--------------------------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function asNumber(value: any, default: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return default
end

local function asString(value: any, default: string): string
	return if type(value) == "string" then value else default
end

-- Table { [string] = number } : garde les seules paires valides.
local function asNumberMap(value: any): { [string]: number }
	local result: { [string]: number } = {}
	if type(value) == "table" then
		for key, amount in value do
			if type(key) == "string" and type(amount) == "number" and amount == amount then
				result[key] = amount
			end
		end
	end
	return result
end

local function asProgression(value: any): Progression
	local raw = if type(value) == "table" then value else {}
	return {
		xp = math.max(0, asNumber(raw.xp, 0)),
		rank = asString(raw.rank, DEFAULT_RANK),
		reputation = math.max(0, asNumber(raw.reputation, 0)),
		promotions = asNumberMap(raw.promotions),
	}
end

local function asQuests(value: any): Quests
	local raw = if type(value) == "table" then value else {}
	local active: { [string]: QuestProgress } = {}
	if type(raw.active) == "table" then
		for questId, entry in raw.active do
			if type(questId) == "string" and type(entry) == "table" then
				active[questId] = {
					stage = math.max(1, math.floor(asNumber(entry.stage, 1))),
					progress = asNumberMap(entry.progress),
					startedAt = asNumber(entry.startedAt, 0),
				}
			end
		end
	end
	return { active = active, completed = asNumberMap(raw.completed) }
end

local function asMissions(value: any): Missions
	local raw = if type(value) == "table" then value else {}
	local active: { [string]: MissionProgress } = {}
	if type(raw.active) == "table" then
		for missionId, entry in raw.active do
			if type(missionId) == "string" and type(entry) == "table" then
				active[missionId] = {
					progress = asNumberMap(entry.progress),
					acceptedAt = asNumber(entry.acceptedAt, 0),
					cycle = asString(entry.cycle, ""),
				}
			end
		end
	end
	return { active = active, completions = asNumberMap(raw.completions) }
end

local function asGuildRef(value: any): GuildRef
	local raw = if type(value) == "table" then value else {}
	return {
		guildId = if type(raw.guildId) == "string" and raw.guildId ~= "" then raw.guildId else nil,
		joinedAt = if type(raw.joinedAt) == "number" then raw.joinedAt else nil,
	}
end

local function asSettings(value: any): Settings
	local raw = if type(value) == "table" then value else {}
	local defaults = newSettings()
	return {
		music = math.clamp(asNumber(raw.music, defaults.music), 0, 1),
		ambience = math.clamp(asNumber(raw.ambience, defaults.ambience), 0, 1),
		sfx = math.clamp(asNumber(raw.sfx, defaults.sfx), 0, 1),
		uiScale = math.clamp(asNumber(raw.uiScale, defaults.uiScale), 0.75, 1.5),
		reducedEffects = if type(raw.reducedEffects) == "boolean" then raw.reducedEffects else defaults.reducedEffects,
	}
end

local function asStats(value: any): Stats
	local raw = if type(value) == "table" then value else {}
	return { kills = asNumberMap(raw.kills), deaths = math.max(0, asNumber(raw.deaths, 0)) }
end

-- Recopie un enregistrement du DataStore dans `profile`, EN PLACE (les services gardent une
-- référence à cette table). Chaque champ est nettoyé indépendamment.
function ProfileSchema.applyRecord(profile: Profile, record: { [string]: any })
	profile.version = if type(record.version) == "number" then record.version else VERSION
	profile.avatar = deepCopy(record.avatar)
	profile.progression = asProgression(record.progression)
	profile.quests = asQuests(record.quests)
	profile.missions = asMissions(record.missions)
	profile.discoveries = asNumberMap(record.discoveries)
	profile.unlocks = asNumberMap(record.unlocks)
	profile.inventory = asNumberMap(record.inventory)
	profile.guild = asGuildRef(record.guild)
	profile.ledger = asNumberMap(record.ledger)
	profile.settings = asSettings(record.settings)
	profile.stats = asStats(record.stats)
end

--------------------------------------------------------------------------------
-- Migrations
--------------------------------------------------------------------------------

-- v1 -> v2 : ajoute les champs RPG absents. Ne supprime ni ne modifie rien d'existant (avatar inclus).
-- Appelée par ProfileStore DANS UpdateAsync : ne doit pas yield.
function ProfileSchema.migrateV1toV2(record: { [string]: any })
	local defaults = ProfileSchema.new()
	for _, field in FIELDS do
		if field ~= "version" and field ~= "avatar" and record[field] == nil then
			record[field] = deepCopy((defaults :: any)[field])
		end
	end
end

ProfileSchema.VERSION = VERSION
ProfileSchema.FIELDS = FIELDS

return ProfileSchema
