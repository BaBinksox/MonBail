--!strict
--[[
	GuildRules
	Règles PURES des guildes : aucune instance, aucun service, aucun yield. Seule dépendance : la
	configuration partagée GuildConfig. Testable hors de Studio (tests/guild).

	Contenu :
		- validation de FORME des noms et descriptions (la modération Roblox est faite par GuildService) ;
		- normalisation d'un nom pour l'index des noms (minuscules, accents retirés, espaces compactés) ;
		- permissions : can(rôle, action, rôle de la cible) ;
		- nettoyage d'un enregistrement lu dans le DataStore (sanitize) ;
		- FONCTIONS DE TRANSFORMATION des enregistrements de guilde, appelées DANS UpdateAsync :
			applyX(record, acteur, paramètres, now, opId) -> (nouveauRecord | nil, codeErreur?)
		  Chacune :
			1. retourne le record INCHANGÉ (même table) avec succès si `opId` est déjà dans record.ops
			   (idempotence : une requête rejouée après une réponse perdue ne s'applique pas deux fois) ;
			2. RE-VÉRIFIE permissions et règles sur l'état stocké (pas sur une copie en mémoire) ;
			3. ne modifie jamais `record` : elle travaille sur une copie ;
			4. enregistre opId dans ops, tient le journal (LOG_SIZE derniers événements), élague les
			   opérations trop anciennes (OPS_RETENTION, au plus MAX_OPS) et les invitations expirées ;
		- indices d'appartenance par joueur (UserHints : invitations reçues, création en cours) ;
		- décision de réconciliation pointeur de profil <-> guilde (reconcilePointer).

	Succession : le chef ne peut pas quitter tant qu'il reste des membres (il doit transférer) ; seul et
	chef, il dissout (pierre tombale, status = "dissolved") après avoir retapé le nom exact.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuildConfig = require(ReplicatedStorage.Shared.Guild.GuildConfig)

export type Role = GuildConfig.Role
export type Action = GuildConfig.Action

export type Actor = {
	userId: number,
	name: string,
}

export type Member = {
	role: Role,
	joinedAt: number,
	name: string,
	kickTimes: { number }?, -- officier : dates de ses exclusions de la dernière heure
}

export type Invite = {
	by: number,
	byName: string,
	name: string, -- nom du joueur invité (affichage)
	at: number,
	expiresAt: number,
}

export type ContractResult = {
	cycle: string,
	completedAt: number,
	contributors: { [string]: number },
}

export type ContractEntry = {
	cycle: string,
	progress: number,
	completedAt: number?,
	contributors: { [string]: number }, -- ["<userId>"] = nombre de contributions
	startedAt: number?, -- contrat manuel : lancé à cette date
	startedBy: number?,
	lastCompleted: ContractResult?, -- résultat du cycle précédent (récompenses encore réclamables)
}

export type LogEntry = {
	t: number,
	kind: string,
	by: number?,
	byName: string?,
	target: number?,
	targetName: string?,
	detail: string?,
}

export type Status = "active" | "dissolved"

export type GuildRecord = {
	schema: number,
	id: string,
	name: string,
	nameKey: string, -- nom normalisé (clé de l'index des noms)
	description: string,
	createdAt: number,
	status: Status,
	dissolvedAt: number?,
	leaderId: number,
	members: { [string]: Member },
	invites: { [string]: Invite },
	xp: number,
	level: number,
	contracts: { [string]: ContractEntry },
	unlocks: { [string]: number },
	log: { LogEntry },
	ops: { [string]: number },
	rev: number, -- révision : +1 à chaque écriture (une lecture plus ancienne ne remplace jamais une plus récente)
}

-- Lot de contributions accumulées par un serveur : progression collective + contributeurs.
export type ContractIncrement = {
	progress: number,
	contributors: { [string]: number },
}

export type ProgressBatch = {
	cycle: string, -- cycle au moment des événements
	contracts: { [string]: ContractIncrement },
}

-- Indices d'appartenance d'un joueur (clé "U_<userId>") : où chercher une guilde qui le liste.
export type HintInvite = {
	expiresAt: number,
	guildName: string,
	byName: string,
}

export type UserHints = {
	invites: { [string]: HintInvite }, -- [guildId] = invitation reçue (indice : la vérité est la guilde)
	pending: { [string]: number }, -- [guildId] = date d'une création en cours
}

-- Réconciliation du pointeur profile.guild avec un enregistrement de guilde relu :
--   "keep"     le pointeur est juste ;
--   "clear"    le pointeur désigne cette guilde, qui ne liste plus le joueur (ou est dissoute) ;
--   "restore"  la guilde liste le joueur mais le profil l'ignore (opération interrompue) ;
--   "conflict" la guilde liste le joueur alors que le pointeur désigne une AUTRE guilde ;
--   "none"     rien à faire (guilde sans rapport avec le joueur).
export type PointerDecision = "keep" | "clear" | "restore" | "conflict" | "none"

local SCHEMA_VERSION = 1
local MAX_ID_LENGTH = 48
local MAX_OP_ID_LENGTH = 64
local MAX_PLAYER_NAME_LENGTH = 32
local MAX_RAW_TEXT_BYTES = 1000

local GuildRules = {}

GuildRules.SCHEMA_VERSION = SCHEMA_VERSION

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy :: any
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isUserId(value: any): boolean
	return isFiniteNumber(value) and value >= 1 and value % 1 == 0 and value < 2 ^ 53
end

local function userKey(userId: number): string
	return string.format("%d", userId)
end

local function isValidOpId(opId: any): boolean
	return type(opId) == "string" and #opId > 0 and #opId <= MAX_OP_ID_LENGTH
end

-- Identifiant de guilde : "G_" suivi de caractères alphanumériques.
local function isGuildId(value: any): boolean
	return type(value) == "string"
		and #value >= 3
		and #value <= MAX_ID_LENGTH
		and string.match(value, "^G_[%w]+$") ~= nil
end
GuildRules.isGuildId = isGuildId
GuildRules.isUserId = isUserId
GuildRules.userKey = userKey

local function countKeys(map: { [string]: any }): number
	local count = 0
	for _ in map do
		count += 1
	end
	return count
end

local function countRole(record: GuildRecord, role: Role): number
	local count = 0
	for _, member in record.members do
		if member.role == role then
			count += 1
		end
	end
	return count
end

local function cleanPlayerName(value: any): string
	if type(value) ~= "string" then
		return "?"
	end
	local trimmed = string.sub(value, 1, MAX_PLAYER_NAME_LENGTH)
	return if trimmed == "" then "?" else trimmed
end

local function pruneInvites(record: GuildRecord, now: number)
	for key, invite in record.invites do
		if invite.expiresAt <= now then
			record.invites[key] = nil
		end
	end
end

-- Élague record.ops : plus vieux que OPS_RETENTION, puis au plus MAX_OPS (les plus anciens d'abord).
local function pruneOps(record: GuildRecord, now: number)
	local entries: { { id: string, t: number } } = {}
	for opId, appliedAt in record.ops do
		if now - appliedAt > GuildConfig.OPS_RETENTION then
			record.ops[opId] = nil
		else
			table.insert(entries, { id = opId, t = appliedAt })
		end
	end
	local excess = #entries - GuildConfig.MAX_OPS
	if excess > 0 then
		table.sort(entries, function(a, b)
			return a.t < b.t
		end)
		for index = 1, excess do
			record.ops[entries[index].id] = nil
		end
	end
end

local function pushLog(record: GuildRecord, entry: LogEntry)
	table.insert(record.log, entry)
	while #record.log > GuildConfig.LOG_SIZE do
		table.remove(record.log, 1)
	end
end

-- Copie de travail d'un enregistrement, invitations expirées retirées.
local function begin(record: GuildRecord, now: number): GuildRecord
	local nextRecord = deepCopy(record)
	pruneInvites(nextRecord, now)
	return nextRecord
end

-- Fin d'une transformation réussie : opération enregistrée, révision incrémentée, journal tenu.
local function finish(record: GuildRecord, opId: string, now: number, entry: LogEntry?)
	record.rev += 1
	record.ops[opId] = now
	pruneOps(record, now)
	if entry then
		pushLog(record, entry)
	end
end

local function getMember(record: GuildRecord, userId: number): Member?
	return record.members[userKey(userId)]
end

-- Premières vérifications communes : (record déjà appliqué ?) puis guilde active.
-- Retourne (recordInchangé, nil) si l'opération est déjà appliquée, (nil, erreur) en cas de refus,
-- ou (nil, nil) pour continuer.
local function precheck(record: GuildRecord?, opId: string): (GuildRecord?, string?)
	if not isValidOpId(opId) then
		return nil, "bad_params"
	end
	if record == nil then
		return nil, "guild_not_found"
	end
	if record.ops[opId] ~= nil then
		return record, nil
	end
	if record.status ~= "active" then
		return nil, "guild_dissolved"
	end
	return nil, nil
end

--------------------------------------------------------------------------------
-- Noms et descriptions (forme)
--------------------------------------------------------------------------------

-- Lettres accentuées -> lettres de base (normalisation de l'index des noms).
local ACCENT_FOLD: { [string]: string } = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ã"] = "a", ["å"] = "a",
	["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Á"] = "a", ["Ã"] = "a", ["Å"] = "a",
	["ç"] = "c", ["Ç"] = "c",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ì"] = "i",
	["Î"] = "i", ["Ï"] = "i", ["Í"] = "i", ["Ì"] = "i",
	["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["ò"] = "o", ["õ"] = "o",
	["Ô"] = "o", ["Ö"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Õ"] = "o",
	["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u",
	["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ú"] = "u",
	["ÿ"] = "y", ["ý"] = "y", ["Ÿ"] = "y", ["Ý"] = "y",
	["ñ"] = "n", ["Ñ"] = "n",
	["œ"] = "oe", ["Œ"] = "oe",
	["æ"] = "ae", ["Æ"] = "ae",
}
GuildRules.ACCENT_FOLD = ACCENT_FOLD

-- Ensembles de caractères autorisés (construits depuis GuildConfig).
local accentedLetters: { [string]: boolean } = {}
for _, codepoint in utf8.codes(GuildConfig.NAME_ACCENTED_LETTERS) do
	accentedLetters[utf8.char(codepoint)] = true
end
local punctuation: { [string]: boolean } = {}
for index = 1, #GuildConfig.NAME_PUNCTUATION do
	punctuation[string.sub(GuildConfig.NAME_PUNCTUATION, index, index)] = true
end

-- Espaces (et blancs) de début / fin retirés, suites de blancs réduites à une espace.
local function compactSpaces(text: string): string
	local collapsed = string.gsub(text, "%s+", " ")
	local trimmed = string.match(collapsed, "^%s*(.-)%s*$")
	return trimmed or ""
end

local function isAsciiAlnum(char: string): boolean
	return #char == 1 and string.match(char, "^%w$") ~= nil
end

local function isLetter(char: string): boolean
	return (#char == 1 and string.match(char, "^%a$") ~= nil) or accentedLetters[char] == true
end

--[[
	Valide la FORME d'un nom de guilde. Retourne (nomNettoyé) ou (nil, codeErreur).
	Nettoyage : blancs de début / fin retirés, suites de blancs réduites à une espace.
]]
function GuildRules.validateName(raw: any): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "name_invalid"
	end
	if #raw > MAX_RAW_TEXT_BYTES or utf8.len(raw) == nil then
		return nil, "name_invalid_chars"
	end
	local name = compactSpaces(raw)
	local length = utf8.len(name) or 0
	if length < GuildConfig.NAME_MIN_LENGTH or length > GuildConfig.NAME_MAX_LENGTH then
		return nil, "name_invalid_length"
	end

	local previousWasPunctuation = false
	local letterCount = 0
	local index = 0
	for _, codepoint in utf8.codes(name) do
		index += 1
		local char = utf8.char(codepoint)
		local isPunct = punctuation[char] == true
		if not (isAsciiAlnum(char) or accentedLetters[char] or isPunct) then
			return nil, "name_invalid_chars"
		end
		if isPunct and (index == 1 or previousWasPunctuation) then
			return nil, "name_invalid_format"
		end
		if isLetter(char) then
			letterCount += 1
		end
		previousWasPunctuation = isPunct
	end
	if letterCount == 0 then
		return nil, "name_invalid_format"
	end
	return name, nil
end

-- Clé de l'index des noms : minuscules, accents retirés, espaces compactés. Deux noms qui ne
-- diffèrent que par la casse, les accents ou les espaces désignent la même guilde.
function GuildRules.normalizeName(name: string): string
	local parts: { string } = {}
	if utf8.len(name) == nil then
		return string.lower(compactSpaces(name))
	end
	for _, codepoint in utf8.codes(name) do
		local char = utf8.char(codepoint)
		table.insert(parts, ACCENT_FOLD[char] or string.lower(char))
	end
	return compactSpaces(table.concat(parts))
end

--[[
	Valide la FORME d'une description. Retourne (descriptionNettoyée) ou (nil, codeErreur).
	Les caractères de contrôle (retours à la ligne, tabulations...) deviennent des espaces.
]]
function GuildRules.validateDescription(raw: any): (string?, string?)
	if raw == nil then
		return "", nil
	end
	if type(raw) ~= "string" or #raw > MAX_RAW_TEXT_BYTES or utf8.len(raw) == nil then
		return nil, "description_invalid"
	end
	local cleaned = compactSpaces((string.gsub(raw, "%c", " ")))
	if (utf8.len(cleaned) or 0) > GuildConfig.DESCRIPTION_MAX_LENGTH then
		return nil, "description_too_long"
	end
	return cleaned, nil
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

--[[
	true si un membre de rôle `role` peut faire `action` (sur une cible de rôle `targetRole` pour les
	actions qui visent un membre : kick, promote, demote, transferLeadership).
]]
function GuildRules.can(role: Role?, action: Action, targetRole: Role?): boolean
	if role == nil then
		return false
	end
	local allowed = GuildConfig.PERMISSIONS[action]
	if allowed == nil or allowed[role] ~= true then
		return false
	end
	local targets = GuildConfig.TARGET_RULES[action]
	if targets ~= nil then
		if targetRole == nil then
			return false
		end
		local byRole = targets[role]
		return byRole ~= nil and byRole[targetRole] == true
	end
	return true
end

-- Rôle de `userId` dans `record` (nil s'il n'est pas membre ou si la guilde est dissoute).
function GuildRules.getRole(record: GuildRecord?, userId: number): Role?
	if record == nil or record.status ~= "active" then
		return nil
	end
	local member = getMember(record, userId)
	if member == nil then
		return nil
	end
	local role: Role = member.role
	return role
end

-- Actions générales permises au rôle de `userId` (pour l'interface ; les cibles sont revérifiées).
function GuildRules.allowedActions(record: GuildRecord?, userId: number): { [string]: boolean }
	local role: Role? = GuildRules.getRole(record, userId)
	local result: { [string]: boolean } = {}
	for action, byRole in GuildConfig.PERMISSIONS do
		result[action] = false
		if role ~= nil then
			local actorRole: Role = role
			result[action] = byRole[actorRole] == true
		end
	end
	if record and role == "leader" then
		local isAlone = countKeys(record.members) <= 1
		result.leave = false -- le chef ne quitte pas : il transfère (s'il reste des membres) ou dissout
		result.dissolve = isAlone -- la dissolution exige d'être le dernier membre
		result.transferLeadership = not isAlone
	end
	return result
end

-- Nombre d'exclusions faites par cet officier dans l'heure qui précède `now`.
local function recentKicks(member: Member, now: number): number
	local count = 0
	if member.kickTimes then
		for _, kickedAt in member.kickTimes do
			if now - kickedAt < 3600 then
				count += 1
			end
		end
	end
	return count
end

-- Vérifie qu'`actor` peut faire `action` sur `targetId` dans `record`. Retourne (acteur, cible) ou erreur.
local function checkTargeted(record: GuildRecord, actor: Actor, action: Action, targetId: any): (Member?, Member?, string?)
	local actorMember = getMember(record, actor.userId)
	if actorMember == nil then
		return nil, nil, "not_member"
	end
	if not isUserId(targetId) then
		return nil, nil, "bad_params"
	end
	if targetId == actor.userId then
		return nil, nil, "target_is_self"
	end
	local allowed = GuildConfig.PERMISSIONS[action]
	if allowed == nil or allowed[actorMember.role] ~= true then
		return nil, nil, "no_permission"
	end
	local target = getMember(record, targetId)
	if target == nil then
		return nil, nil, "target_not_member"
	end
	if not GuildRules.can(actorMember.role, action, target.role) then
		return nil, nil, "target_role_forbidden"
	end
	return actorMember, target, nil
end

--------------------------------------------------------------------------------
-- Nettoyage d'un enregistrement lu dans le DataStore
--------------------------------------------------------------------------------

local function asNumberMap(value: any): { [string]: number }
	local result: { [string]: number } = {}
	if type(value) == "table" then
		for key, amount in value do
			if type(key) == "string" and isFiniteNumber(amount) then
				result[key] = amount
			end
		end
	end
	return result
end

local function asRole(value: any): Role?
	if value == "leader" or value == "officer" or value == "member" then
		return value
	end
	return nil
end

local function asContractResult(value: any): ContractResult?
	if type(value) ~= "table" or type(value.cycle) ~= "string" or not isFiniteNumber(value.completedAt) then
		return nil
	end
	return { cycle = value.cycle, completedAt = value.completedAt, contributors = asNumberMap(value.contributors) }
end

--[[
	Nettoie un enregistrement de guilde lu dans le DataStore (types vérifiés champ par champ).
	Retourne nil si ce n'est pas une guilde lisible (pas de table, pas d'id). Ne modifie pas `raw`.
]]
function GuildRules.sanitize(raw: any): GuildRecord?
	if type(raw) ~= "table" or not isGuildId(raw.id) then
		return nil
	end
	local members: { [string]: Member } = {}
	if type(raw.members) == "table" then
		for key, entry in raw.members do
			local role: Role? = if type(entry) == "table" then asRole(entry.role) else nil
			if type(key) == "string" and string.match(key, "^%d+$") ~= nil and role ~= nil then
				local kickTimes: { number }? = nil
				if type(entry.kickTimes) == "table" then
					local times: { number } = {}
					for _, kickedAt in entry.kickTimes do
						if isFiniteNumber(kickedAt) then
							table.insert(times, kickedAt)
						end
					end
					kickTimes = times
				end
				members[key] = {
					role = role,
					joinedAt = if isFiniteNumber(entry.joinedAt) then entry.joinedAt else 0,
					name = cleanPlayerName(entry.name),
					kickTimes = kickTimes,
				}
			end
		end
	end

	local invites: { [string]: Invite } = {}
	if type(raw.invites) == "table" then
		for key, entry in raw.invites do
			if type(key) == "string" and type(entry) == "table" and isFiniteNumber(entry.expiresAt) then
				invites[key] = {
					by = if isUserId(entry.by) then entry.by else 0,
					byName = cleanPlayerName(entry.byName),
					name = cleanPlayerName(entry.name),
					at = if isFiniteNumber(entry.at) then entry.at else 0,
					expiresAt = entry.expiresAt,
				}
			end
		end
	end

	local contracts: { [string]: ContractEntry } = {}
	if type(raw.contracts) == "table" then
		for contractId, entry in raw.contracts do
			if type(contractId) == "string" and type(entry) == "table" and type(entry.cycle) == "string" then
				contracts[contractId] = {
					cycle = entry.cycle,
					progress = if isFiniteNumber(entry.progress) then math.max(0, entry.progress) else 0,
					completedAt = if isFiniteNumber(entry.completedAt) then entry.completedAt else nil,
					contributors = asNumberMap(entry.contributors),
					startedAt = if isFiniteNumber(entry.startedAt) then entry.startedAt else nil,
					startedBy = if isUserId(entry.startedBy) then entry.startedBy else nil,
					lastCompleted = asContractResult(entry.lastCompleted),
				}
			end
		end
	end

	local log: { LogEntry } = {}
	if type(raw.log) == "table" then
		for _, entry in raw.log do
			if type(entry) == "table" and isFiniteNumber(entry.t) and type(entry.kind) == "string" then
				table.insert(log, {
					t = entry.t,
					kind = entry.kind,
					by = if isUserId(entry.by) then entry.by else nil,
					byName = if type(entry.byName) == "string" then entry.byName else nil,
					target = if isUserId(entry.target) then entry.target else nil,
					targetName = if type(entry.targetName) == "string" then entry.targetName else nil,
					detail = if type(entry.detail) == "string" then entry.detail else nil,
				})
			end
		end
	end

	local xp = if isFiniteNumber(raw.xp) then math.max(0, raw.xp) else 0
	local name = if type(raw.name) == "string" then raw.name else "?"
	local status: Status = if raw.status == "dissolved" then "dissolved" else "active"
	return {
		schema = if isFiniteNumber(raw.schema) then raw.schema else SCHEMA_VERSION,
		id = raw.id,
		name = name,
		nameKey = if type(raw.nameKey) == "string" then raw.nameKey else GuildRules.normalizeName(name),
		description = if type(raw.description) == "string" then raw.description else "",
		createdAt = if isFiniteNumber(raw.createdAt) then raw.createdAt else 0,
		status = status,
		dissolvedAt = if isFiniteNumber(raw.dissolvedAt) then raw.dissolvedAt else nil,
		leaderId = if isUserId(raw.leaderId) then raw.leaderId else 0,
		members = members,
		invites = invites,
		xp = xp,
		level = GuildConfig.levelForXp(xp), -- toujours déduit de l'XP : jamais incohérent
		contracts = contracts,
		unlocks = asNumberMap(raw.unlocks),
		log = log,
		ops = asNumberMap(raw.ops),
		rev = if isFiniteNumber(raw.rev) then raw.rev else 0,
	}
end

--------------------------------------------------------------------------------
-- Création
--------------------------------------------------------------------------------

export type CreateParams = {
	guildId: string,
	name: string,
	description: string?,
}

--[[
	Crée l'enregistrement d'une nouvelle guilde dont `actor` est le chef. `existing` = valeur actuelle
	de la clé (nil attendu). Idempotent : si la guilde existe déjà avec ce même opId, elle est rendue.
]]
function GuildRules.createRecord(existing: GuildRecord?, actor: Actor, params: CreateParams, now: number, opId: string): (GuildRecord?, string?)
	if not isValidOpId(opId) or not isUserId(actor.userId) or not isGuildId(params.guildId) then
		return nil, "bad_params"
	end
	if existing ~= nil then
		if existing.ops[opId] ~= nil then
			return existing, nil
		end
		return nil, "exists"
	end
	local name, nameError = GuildRules.validateName(params.name)
	if name == nil then
		return nil, nameError
	end
	local description, descriptionError = GuildRules.validateDescription(params.description)
	if description == nil then
		return nil, descriptionError
	end

	local record: GuildRecord = {
		schema = SCHEMA_VERSION,
		id = params.guildId,
		name = name,
		nameKey = GuildRules.normalizeName(name),
		description = description,
		createdAt = now,
		status = "active",
		dissolvedAt = nil,
		leaderId = actor.userId,
		members = {
			[userKey(actor.userId)] = { role = "leader", joinedAt = now, name = cleanPlayerName(actor.name) },
		},
		invites = {},
		xp = 0,
		level = 1,
		contracts = {},
		unlocks = {},
		log = {},
		ops = {},
		rev = 0,
	}
	finish(record, opId, now, { t = now, kind = "created", by = actor.userId, byName = actor.name })
	return record, nil
end

--------------------------------------------------------------------------------
-- Invitations
--------------------------------------------------------------------------------

export type TargetParams = {
	targetId: number,
	targetName: string?,
}

-- Invite `targetId` (refait l'invitation si elle existe déjà : nouvelle échéance).
function GuildRules.applyInvite(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember = getMember(current, actor.userId)
	if actorMember == nil then
		return nil, "not_member"
	end
	if not GuildRules.can(actorMember.role, "invite") then
		return nil, "no_permission"
	end
	if not isUserId(params.targetId) then
		return nil, "bad_params"
	end
	if params.targetId == actor.userId then
		return nil, "target_is_self"
	end
	if getMember(current, params.targetId) then
		return nil, "already_member"
	end
	if countKeys(current.members) >= GuildConfig.MAX_MEMBERS then
		return nil, "guild_full"
	end

	local nextRecord = begin(current, now)
	local key = userKey(params.targetId)
	if nextRecord.invites[key] == nil and countKeys(nextRecord.invites) >= GuildConfig.MAX_PENDING_INVITES then
		return nil, "invites_full"
	end
	local targetName = cleanPlayerName(params.targetName)
	nextRecord.invites[key] = {
		by = actor.userId,
		byName = cleanPlayerName(actor.name),
		name = targetName,
		at = now,
		expiresAt = now + GuildConfig.INVITE_DURATION,
	}
	finish(nextRecord, opId, now, {
		t = now,
		kind = "invited",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = targetName,
	})
	return nextRecord, nil
end

-- Annule une invitation en attente (chef / officier).
function GuildRules.applyCancelInvite(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember = getMember(current, actor.userId)
	if actorMember == nil then
		return nil, "not_member"
	end
	if not GuildRules.can(actorMember.role, "cancelInvite") then
		return nil, "no_permission"
	end
	if not isUserId(params.targetId) then
		return nil, "bad_params"
	end
	local nextRecord = begin(current, now)
	local key = userKey(params.targetId)
	local invite = nextRecord.invites[key]
	if invite == nil then
		return nil, "invite_not_found"
	end
	nextRecord.invites[key] = nil
	finish(nextRecord, opId, now, {
		t = now,
		kind = "invite_cancelled",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = invite.name,
	})
	return nextRecord, nil
end

-- L'invité (`actor`) accepte : il devient membre. Déjà membre = succès sans changement.
function GuildRules.applyAcceptInvite(record: GuildRecord?, actor: Actor, _params: {}?, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	if getMember(current, actor.userId) then
		return current, nil
	end
	local key = userKey(actor.userId)
	local invite = current.invites[key]
	if invite == nil then
		return nil, "invite_not_found"
	end
	if invite.expiresAt <= now then
		return nil, "invite_expired"
	end
	if countKeys(current.members) >= GuildConfig.MAX_MEMBERS then
		return nil, "guild_full"
	end

	local nextRecord = begin(current, now)
	nextRecord.invites[key] = nil
	nextRecord.members[key] = { role = "member", joinedAt = now, name = cleanPlayerName(actor.name) }
	finish(nextRecord, opId, now, {
		t = now,
		kind = "joined",
		by = actor.userId,
		byName = actor.name,
		target = invite.by,
		targetName = invite.byName,
	})
	return nextRecord, nil
end

-- L'invité refuse. Invitation absente = succès sans changement (déjà refusée ou expirée).
function GuildRules.applyDeclineInvite(record: GuildRecord?, actor: Actor, _params: {}?, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local key = userKey(actor.userId)
	if current.invites[key] == nil then
		return current, nil
	end
	local nextRecord = begin(current, now)
	nextRecord.invites[key] = nil
	finish(nextRecord, opId, now, { t = now, kind = "declined", by = actor.userId, byName = actor.name })
	return nextRecord, nil
end

--------------------------------------------------------------------------------
-- Départs et rôles
--------------------------------------------------------------------------------

-- `actor` quitte la guilde. Le chef ne peut pas partir : il transfère (s'il reste des membres) ou dissout.
function GuildRules.applyLeave(record: GuildRecord?, actor: Actor, _params: {}?, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local member = getMember(current, actor.userId)
	if member == nil then
		return nil, "not_member"
	end
	if member.role == "leader" then
		return nil, if countKeys(current.members) > 1 then "leader_must_transfer" else "leader_must_dissolve"
	end
	local nextRecord = begin(current, now)
	nextRecord.members[userKey(actor.userId)] = nil
	finish(nextRecord, opId, now, { t = now, kind = "left", by = actor.userId, byName = actor.name })
	return nextRecord, nil
end

-- Exclusion. Chef : officiers et membres ; officier : membres seulement, OFFICER_KICKS_PER_HOUR par heure.
function GuildRules.applyKick(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember, target, targetError = checkTargeted(current, actor, "kick", params.targetId)
	if actorMember == nil or target == nil then
		return nil, targetError
	end
	if actorMember.role == "officer" and recentKicks(actorMember, now) >= GuildConfig.OFFICER_KICKS_PER_HOUR then
		return nil, "kick_limit"
	end

	local nextRecord = begin(current, now)
	nextRecord.members[userKey(params.targetId)] = nil
	if actorMember.role == "officer" then
		local stored = nextRecord.members[userKey(actor.userId)]
		local times: { number } = {}
		local previousKicks: { number } = stored.kickTimes or {}
		for _, kickedAt in previousKicks do
			if now - kickedAt < 3600 then
				table.insert(times, kickedAt)
			end
		end
		table.insert(times, now)
		stored.kickTimes = times
	end
	finish(nextRecord, opId, now, {
		t = now,
		kind = "kicked",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = target.name,
	})
	return nextRecord, nil
end

-- Membre -> officier (chef seulement, au plus MAX_OFFICERS officiers).
function GuildRules.applyPromote(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember, target, targetError = checkTargeted(current, actor, "promote", params.targetId)
	if actorMember == nil or target == nil then
		return nil, targetError
	end
	if countRole(current, "officer") >= GuildConfig.MAX_OFFICERS then
		return nil, "officer_limit"
	end
	local nextRecord = begin(current, now)
	nextRecord.members[userKey(params.targetId)].role = "officer"
	finish(nextRecord, opId, now, {
		t = now,
		kind = "promoted",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = target.name,
	})
	return nextRecord, nil
end

-- Officier -> membre (chef seulement).
function GuildRules.applyDemote(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember, target, targetError = checkTargeted(current, actor, "demote", params.targetId)
	if actorMember == nil or target == nil then
		return nil, targetError
	end
	local nextRecord = begin(current, now)
	local stored = nextRecord.members[userKey(params.targetId)]
	stored.role = "member"
	stored.kickTimes = nil
	finish(nextRecord, opId, now, {
		t = now,
		kind = "demoted",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = target.name,
	})
	return nextRecord, nil
end

-- Le chef transmet la direction ; il devient officier (ou membre si le quota d'officiers est plein).
function GuildRules.applyTransfer(record: GuildRecord?, actor: Actor, params: TargetParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember, target, targetError = checkTargeted(current, actor, "transferLeadership", params.targetId)
	if actorMember == nil or target == nil then
		return nil, targetError
	end
	local nextRecord = begin(current, now)
	local newLeader = nextRecord.members[userKey(params.targetId)]
	local oldLeader = nextRecord.members[userKey(actor.userId)]
	newLeader.role = "leader"
	newLeader.kickTimes = nil
	-- Le nouveau chef libère éventuellement une place d'officier.
	oldLeader.role = if countRole(nextRecord, "officer") < GuildConfig.MAX_OFFICERS then "officer" else "member"
	nextRecord.leaderId = params.targetId
	finish(nextRecord, opId, now, {
		t = now,
		kind = "leader_changed",
		by = actor.userId,
		byName = actor.name,
		target = params.targetId,
		targetName = target.name,
	})
	return nextRecord, nil
end

export type DescriptionParams = {
	description: string,
}

-- Nouvelle description (chef / officier). Le texte doit déjà avoir passé le filtre Roblox.
function GuildRules.applySetDescription(record: GuildRecord?, actor: Actor, params: DescriptionParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember = getMember(current, actor.userId)
	if actorMember == nil then
		return nil, "not_member"
	end
	if not GuildRules.can(actorMember.role, "editDescription") then
		return nil, "no_permission"
	end
	local description, descriptionError = GuildRules.validateDescription(params.description)
	if description == nil then
		return nil, descriptionError
	end
	local nextRecord = begin(current, now)
	nextRecord.description = description
	finish(nextRecord, opId, now, { t = now, kind = "description", by = actor.userId, byName = actor.name })
	return nextRecord, nil
end

export type DissolveParams = {
	confirmName: string,
}

-- Dissolution : chef, seul membre restant, nom retapé à l'identique. Pierre tombale (rien n'est effacé
-- hormis les membres et les invitations).
function GuildRules.applyDissolve(record: GuildRecord?, actor: Actor, params: DissolveParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember = getMember(current, actor.userId)
	if actorMember == nil then
		return nil, "not_member"
	end
	if not GuildRules.can(actorMember.role, "dissolve") then
		return nil, "no_permission"
	end
	if countKeys(current.members) > 1 then
		return nil, "dissolve_not_alone"
	end
	if type(params.confirmName) ~= "string" or params.confirmName ~= current.name then
		return nil, "dissolve_name_mismatch"
	end
	local nextRecord = begin(current, now)
	nextRecord.status = "dissolved"
	nextRecord.dissolvedAt = now
	nextRecord.members = {}
	nextRecord.invites = {}
	finish(nextRecord, opId, now, { t = now, kind = "dissolved", by = actor.userId, byName = actor.name })
	return nextRecord, nil
end

--------------------------------------------------------------------------------
-- Contrats de guilde
--------------------------------------------------------------------------------

-- Entrée neuve d'un contrat pour `cycle` ; garde le résultat du cycle précédent s'il était accompli.
local function freshEntry(previous: ContractEntry?, cycle: string): ContractEntry
	local lastCompleted: ContractResult? = nil
	if previous then
		if previous.completedAt ~= nil and previous.cycle ~= cycle then
			lastCompleted = {
				cycle = previous.cycle,
				completedAt = previous.completedAt,
				contributors = deepCopy(previous.contributors),
			}
		else
			lastCompleted = deepCopy(previous.lastCompleted)
		end
	end
	return { cycle = cycle, progress = 0, completedAt = nil, contributors = {}, lastCompleted = lastCompleted }
end

-- Le contrat est-il ouvert à la progression pour cette guilde, à ce cycle ? (manuel : lancé ce cycle)
function GuildRules.isContractActive(record: GuildRecord, contract: GuildConfig.Contract, cycle: string): boolean
	if record.status ~= "active" or record.level < contract.guildLevel then
		return false
	end
	if contract.activation == "manual" then
		local entry = record.contracts[contract.id]
		return entry ~= nil and entry.cycle == cycle and entry.startedAt ~= nil
	end
	return true
end

-- Ajoute de l'XP de guilde et applique les montées de niveau (déblocages, journal).
local function addGuildXp(record: GuildRecord, amount: number, now: number)
	local oldLevel = record.level
	record.xp += amount
	record.level = GuildConfig.levelForXp(record.xp)
	for level = oldLevel + 1, record.level do
		for _, unlockId in GuildConfig.getLevelDef(level).unlocks do
			if record.unlocks[unlockId] == nil then
				record.unlocks[unlockId] = now
			end
		end
		pushLog(record, { t = now, kind = "level_up", detail = tostring(level) })
	end
end

-- Marque le contrat accompli s'il a atteint sa cible (une seule fois par cycle) et verse l'XP de guilde.
local function completeIfReached(record: GuildRecord, contract: GuildConfig.Contract, entry: ContractEntry, now: number): boolean
	if entry.completedAt ~= nil or entry.progress < contract.target then
		return false
	end
	entry.completedAt = now
	pushLog(record, { t = now, kind = "contract_completed", detail = contract.id })
	addGuildXp(record, contract.guildXp, now)
	return true
end

export type ContractParams = {
	contractId: string,
}

-- Lance un contrat manuel pour le cycle en cours (chef / officier, niveau de guilde suffisant).
function GuildRules.applyStartContract(record: GuildRecord?, actor: Actor, params: ContractParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local actorMember = getMember(current, actor.userId)
	if actorMember == nil then
		return nil, "not_member"
	end
	if not GuildRules.can(actorMember.role, "startContract") then
		return nil, "no_permission"
	end
	local contract = GuildConfig.getContract(params.contractId)
	if contract == nil then
		return nil, "contract_unknown"
	end
	if contract.activation ~= "manual" then
		return nil, "contract_not_manual"
	end
	if current.level < contract.guildLevel then
		return nil, "contract_locked"
	end
	local cycle = GuildConfig.getCycle(now).id
	local existing = current.contracts[contract.id]
	if existing and existing.cycle == cycle and existing.startedAt ~= nil then
		return nil, "contract_already_started"
	end
	local nextRecord = begin(current, now)
	local entry = freshEntry(nextRecord.contracts[contract.id], cycle)
	entry.startedAt = now
	entry.startedBy = actor.userId
	nextRecord.contracts[contract.id] = entry
	finish(nextRecord, opId, now, {
		t = now,
		kind = "contract_started",
		by = actor.userId,
		byName = actor.name,
		detail = contract.id,
	})
	return nextRecord, nil
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 1 and value % 1 == 0
end

--[[
	Applique un lot de contributions (accumulé par UN serveur) : progression ADDITIONNÉE à la valeur
	stockée, donc aucune perte quand deux serveurs écrivent en même temps. La complétion et l'XP de
	guilde sont calculées ici, sur l'état stocké : un contrat n'est accompli (et son XP versée) qu'une
	fois. Les contributions de joueurs qui ne sont plus membres, d'un contrat verrouillé, inactif ou
	d'un autre cycle sont ignorées. `actor` est ignoré (écriture du système, pas d'un joueur).
]]
function GuildRules.applyContractProgress(record: GuildRecord?, _actor: Actor?, batch: ProgressBatch, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	if type(batch) ~= "table" or type(batch.cycle) ~= "string" or type(batch.contracts) ~= "table" then
		return nil, "bad_params"
	end
	local cycle = GuildConfig.getCycle(now).id
	local nextRecord = begin(current, now)

	for contractId, increment in batch.contracts do
		local contract = GuildConfig.getContract(contractId)
		if contract == nil or type(increment) ~= "table" or nextRecord.level < contract.guildLevel then
			continue
		end
		local entry = nextRecord.contracts[contract.id]
		if contract.activation == "manual" then
			-- Un contrat manuel ne progresse que s'il a été lancé pour le cycle des événements.
			if entry == nil or entry.cycle ~= batch.cycle or entry.startedAt == nil then
				continue
			end
		elseif entry == nil or entry.cycle ~= batch.cycle then
			-- Contrat automatique : on n'ouvre une entrée que pour le cycle EN COURS (un lot arrivé
			-- après le changement de cycle ne crédite pas le nouveau cycle avec d'anciens événements).
			if batch.cycle ~= cycle or (entry ~= nil and entry.cycle > batch.cycle) then
				continue
			end
			entry = freshEntry(entry, batch.cycle)
			nextRecord.contracts[contract.id] = entry
		end
		local stored = entry :: ContractEntry
		if stored.completedAt ~= nil then
			continue
		end

		-- Seuls les membres actuels comptent (vérifié sur l'état stocké).
		local hasMember = false
		if type(increment.contributors) == "table" then
			for key, count in increment.contributors do
				if type(key) == "string" and nextRecord.members[key] ~= nil and isPositiveInteger(count) then
					stored.contributors[key] = (stored.contributors[key] or 0) + math.min(count, contract.target)
					hasMember = true
				end
			end
		end
		if hasMember and isPositiveInteger(increment.progress) then
			stored.progress = math.min(contract.target, stored.progress + increment.progress)
			completeIfReached(nextRecord, contract, stored, now)
		end
	end

	finish(nextRecord, opId, now, nil)
	return nextRecord, nil
end

-- Enregistre la complétion d'un contrat dont la progression a atteint la cible (rattrapage : la
-- complétion est normalement faite par applyContractProgress). Sans effet s'il est déjà accompli.
function GuildRules.applyRecordContractCompletion(record: GuildRecord?, _actor: Actor?, params: ContractParams, now: number, opId: string): (GuildRecord?, string?)
	local done, refusal = precheck(record, opId)
	if done or refusal then
		return done, refusal
	end
	local current = record :: GuildRecord
	local contract = GuildConfig.getContract(params.contractId)
	if contract == nil then
		return nil, "contract_unknown"
	end
	local entry = current.contracts[contract.id]
	if entry == nil or entry.cycle ~= GuildConfig.getCycle(now).id or entry.completedAt ~= nil or entry.progress < contract.target then
		return current, nil
	end
	local nextRecord = begin(current, now)
	completeIfReached(nextRecord, contract, nextRecord.contracts[contract.id], now)
	finish(nextRecord, opId, now, nil)
	return nextRecord, nil
end

export type ClaimableReward = {
	contractId: string,
	cycle: string,
	contributions: number,
}

--[[
	Parts de contrat que `userId` peut recevoir : contrats accomplis (cycle en cours ou précédent) où il
	a au moins une contribution. La clé de récompense (unicité) est construite par GuildService.
]]
function GuildRules.claimableRewards(record: GuildRecord?, userId: number, now: number): { ClaimableReward }
	local result: { ClaimableReward } = {}
	if record == nil then
		return result
	end
	local key = userKey(userId)
	local allowedCycles = {
		[GuildConfig.getCycle(now).id] = true,
		[GuildConfig.getPreviousCycle(now).id] = true,
	}
	for contractId, entry in record.contracts do
		if GuildConfig.getContract(contractId) == nil then
			continue
		end
		if entry.completedAt ~= nil and allowedCycles[entry.cycle] and (entry.contributors[key] or 0) >= 1 then
			table.insert(result, { contractId = contractId, cycle = entry.cycle, contributions = entry.contributors[key] })
		end
		local last = entry.lastCompleted
		if last and last.cycle ~= entry.cycle and allowedCycles[last.cycle] and (last.contributors[key] or 0) >= 1 then
			table.insert(result, { contractId = contractId, cycle = last.cycle, contributions = last.contributors[key] })
		end
	end
	table.sort(result, function(a, b)
		return a.contractId < b.contractId or (a.contractId == b.contractId and a.cycle < b.cycle)
	end)
	return result
end

--------------------------------------------------------------------------------
-- Réconciliation pointeur de profil <-> guilde
--------------------------------------------------------------------------------

--[[
	Décide quoi faire du pointeur profile.guild (`pointer` = guildId ou nil) de `userId` après une
	lecture RÉUSSIE de la guilde `guildId` (`record` = nil si elle n'existe pas). Ne jamais appeler
	après une lecture en échec : on ne décide rien sur une donnée qu'on n'a pas pu lire.
]]
function GuildRules.reconcilePointer(record: GuildRecord?, guildId: string, userId: number, pointer: string?): PointerDecision
	local isListed = record ~= nil and record.status == "active" and getMember(record, userId) ~= nil
	if pointer == guildId then
		return if isListed then "keep" else "clear"
	end
	if not isListed then
		return "none"
	end
	return if pointer == nil then "restore" else "conflict"
end

--------------------------------------------------------------------------------
-- Indices d'appartenance (clé "U_<userId>")
--------------------------------------------------------------------------------

function GuildRules.sanitizeHints(raw: any): UserHints
	local hints: UserHints = { invites = {}, pending = {} }
	if type(raw) ~= "table" then
		return hints
	end
	if type(raw.invites) == "table" then
		for guildId, entry in raw.invites do
			if isGuildId(guildId) and type(entry) == "table" and isFiniteNumber(entry.expiresAt) then
				hints.invites[guildId] = {
					expiresAt = entry.expiresAt,
					guildName = if type(entry.guildName) == "string" then entry.guildName else "?",
					byName = cleanPlayerName(entry.byName),
				}
			end
		end
	end
	if type(raw.pending) == "table" then
		for guildId, at in raw.pending do
			if isGuildId(guildId) and isFiniteNumber(at) then
				hints.pending[guildId] = at
			end
		end
	end
	return hints
end

local function pruneHints(hints: UserHints, now: number)
	for guildId, entry in hints.invites do
		if entry.expiresAt <= now then
			hints.invites[guildId] = nil
		end
	end
	for guildId, at in hints.pending do
		if now - at > GuildConfig.PENDING_HINT_TTL then
			hints.pending[guildId] = nil
		end
	end
	-- Au plus MAX_INCOMING_INVITES : les invitations qui expirent le plus tôt sautent en premier.
	local entries: { { id: string, expiresAt: number } } = {}
	for guildId, entry in hints.invites do
		table.insert(entries, { id = guildId, expiresAt = entry.expiresAt })
	end
	local excess = #entries - GuildConfig.MAX_INCOMING_INVITES
	if excess > 0 then
		table.sort(entries, function(a, b)
			return a.expiresAt < b.expiresAt
		end)
		for index = 1, excess do
			hints.invites[entries[index].id] = nil
		end
	end
end

function GuildRules.applyHintInvite(hints: UserHints, guildId: string, info: HintInvite, now: number): UserHints
	local nextHints = deepCopy(hints)
	nextHints.invites[guildId] = deepCopy(info)
	pruneHints(nextHints, now)
	return nextHints
end

function GuildRules.applyHintRemove(hints: UserHints, guildId: string, now: number): UserHints
	local nextHints = deepCopy(hints)
	nextHints.invites[guildId] = nil
	nextHints.pending[guildId] = nil
	pruneHints(nextHints, now)
	return nextHints
end

function GuildRules.applyHintPending(hints: UserHints, guildId: string, now: number): UserHints
	local nextHints = deepCopy(hints)
	nextHints.pending[guildId] = now
	pruneHints(nextHints, now)
	return nextHints
end

-- Guildes à consulter pour retrouver l'appartenance d'un joueur dont le pointeur est vide.
function GuildRules.hintGuildIds(hints: UserHints): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for guildId in hints.pending do
		if not seen[guildId] then
			seen[guildId] = true
			table.insert(ids, guildId)
		end
	end
	for guildId in hints.invites do
		if not seen[guildId] then
			seen[guildId] = true
			table.insert(ids, guildId)
		end
	end
	table.sort(ids)
	return ids
end

GuildRules.deepCopy = deepCopy
GuildRules.countMembers = function(record: GuildRecord): number
	return countKeys(record.members)
end
GuildRules.countOfficers = function(record: GuildRecord): number
	return countRole(record, "officer")
end

return GuildRules
