--!strict
--[[
	GuildStore
	Accès DataStore des guildes (singleton serveur, sans état de jeu) :
		- enregistrements de guilde       : DataStore DataConfig.storeName(GUILD_STORE), clé = guildId ("G_...") ;
		- indices d'appartenance joueur   : même DataStore, clé "U_<userId>" (invitations reçues,
		                                    création en cours ; voir GuildRules.UserHints) ;
		- index des noms                  : DataStore DataConfig.storeName(GUILD_NAME_STORE), clé = nom
		                                    normalisé (GuildRules.normalizeName).
	Avec USE_TEST_STORES (Studio), tous ces noms sont préfixés TEST_ : aucun test n'écrit en production.

	Garanties :
		1. Toute écriture passe par UpdateAsync ; la fonction de transformation appelle GuildRules (pure,
		   sans yield) sur la valeur RÉELLEMENT stockée. UpdateAsync peut l'appeler plusieurs fois : les
		   résultats sont recalculés à chaque appel.
		2. Tentatives limitées comme ProfileStore : 3 essais, délai qui double, pas de nouvel essai sur
		   une erreur 403 (accès API refusé). Une transformation REFUSÉE (règle de guilde) n'est pas
		   une erreur et n'est jamais réessayée.
		3. Une transformation qui rend le record inchangé (opération déjà appliquée) n'écrit rien.
		4. Cache mémoire des guildes lues ou écrites, avec horodatage (os.clock) : les services lisent le
		   cache pour l'affichage, et relisent le DataStore pour décider.

	Index des noms (une entrée = { guildId, status = "reserved" | "active" | "released", at }) :
		- reserveName : refus si le nom est réservé par une autre création récente (moins de
		  NAME_RESERVATION_TTL) ou porté par une autre guilde ACTIVE. Une entrée « active » ou une
		  réservation expirée n'est reprise qu'après avoir relu la guilde qu'elle désigne : si cette guilde
		  existe et est active, le nom reste pris (et l'entrée est confirmée).
		- confirmName : la réservation devient « active » (guilde créée) ;
		- releaseName : le nom redevient libre (dissolution, création abandonnée).
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local GuildConfig = require(ReplicatedStorage.Shared.Guild.GuildConfig)
local GuildRules = require(script.Parent.GuildRules)

export type GuildRecord = GuildRules.GuildRecord
export type UserHints = GuildRules.UserHints

-- Transformation d'une guilde : (valeur stockée nettoyée ou nil) -> (nouvelle valeur | nil, erreur).
-- Rendre la MÊME table que `current` = rien à écrire (succès).
export type Transform = (current: GuildRecord?) -> (GuildRecord?, string?)
export type HintsTransform = (current: UserHints) -> UserHints

type NameStatus = "reserved" | "active" | "released"
type NameEntry = {
	guildId: string,
	status: NameStatus,
	at: number,
}

type CacheEntry = {
	record: GuildRecord?, -- nil : la guilde n'existe pas
	readAt: number, -- os.clock() de la dernière lecture / écriture réussie
}

local MAX_ATTEMPTS = 3 -- tentatives par requête DataStore
local RETRY_DELAY = 1 -- secondes ; le délai double à chaque nouvelle tentative

local GuildStore = {}

local guildDataStore: DataStore? = nil
local nameDataStore: DataStore? = nil
local hasWarnedUnavailable = false
local getOptions: DataStoreGetOptions? = nil
local cache: { [string]: CacheEntry } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function warnUnavailable(errorMessage: any)
	if hasWarnedUnavailable then
		return
	end
	hasWarnedUnavailable = true
	warn(`[Guild] DataStore des guildes indisponible : les guildes sont en lecture seule sur ce serveur. ({errorMessage})`)
end

local function openStore(baseName: string): DataStore?
	local isOpened, result = pcall(function()
		return DataStoreService:GetDataStore(DataConfig.storeName(baseName))
	end)
	if isOpened then
		return result
	end
	warnUnavailable(result)
	return nil
end

local function getGuildStore(): DataStore?
	if guildDataStore == nil then
		guildDataStore = openStore(DataConfig.GUILD_STORE)
	end
	return guildDataStore
end

local function getNameStore(): DataStore?
	if nameDataStore == nil then
		nameDataStore = openStore(DataConfig.GUILD_NAME_STORE)
	end
	return nameDataStore
end

-- Options de lecture sans le cache local de 4 s de GetAsync (on veut la valeur à jour).
local function getReadOptions(): DataStoreGetOptions?
	if getOptions == nil then
		local isCreated, options = pcall(function()
			local created = Instance.new("DataStoreGetOptions")
			created.UseCache = false
			return created
		end)
		if isCreated then
			getOptions = options
		end
	end
	return getOptions
end

-- Exécute `request` jusqu'à MAX_ATTEMPTS fois, avec un délai qui double. Retourne (succès, résultat ou erreur).
local function withRetries(request: () -> any): (boolean, any)
	local lastError: any = nil
	for attempt = 1, MAX_ATTEMPTS do
		local isSuccess, result = pcall(request)
		if isSuccess then
			return true, result
		end
		lastError = result
		-- 403 = accès refusé (API désactivée dans Studio...) : réessayer ne changerait rien.
		if attempt == MAX_ATTEMPTS or string.find(tostring(result), "403", 1, true) then
			break
		end
		task.wait(RETRY_DELAY * 2 ^ (attempt - 1))
	end
	return false, lastError
end

local function userKey(userId: number): string
	return `U_{GuildRules.userKey(userId)}`
end

-- Met la copie en mémoire à jour et retourne la version la plus récente connue : une lecture partie
-- AVANT une écriture de ce serveur (et revenue après) ne remplace pas le résultat de l'écriture.
local function remember(guildId: string, record: GuildRecord?): GuildRecord?
	local entry = cache[guildId]
	local cached = entry and entry.record
	if record ~= nil and cached ~= nil and cached.rev > record.rev then
		entry.readAt = os.clock()
		return cached
	end
	cache[guildId] = { record = record, readAt = os.clock() }
	return record
end

local function asNameEntry(raw: any): NameEntry?
	if type(raw) ~= "table" or not GuildRules.isGuildId(raw.guildId) or type(raw.at) ~= "number" then
		return nil
	end
	if raw.status ~= "reserved" and raw.status ~= "active" and raw.status ~= "released" then
		return nil
	end
	return { guildId = raw.guildId, status = raw.status, at = raw.at }
end

--------------------------------------------------------------------------------
-- Guildes
--------------------------------------------------------------------------------

-- true si le DataStore des guildes est utilisable sur ce serveur.
function GuildStore.isAvailable(): boolean
	return getGuildStore() ~= nil
end

--[[
	Lit la guilde `guildId` dans le DataStore. YIELD.
	Retourne (true, record) ou (true, nil) si elle n'existe pas, (false, nil) si la lecture a échoué ou
	si la valeur est illisible : dans ce cas, on ne décide RIEN sur cette guilde.
]]
function GuildStore.read(guildId: string): (boolean, GuildRecord?)
	local store = getGuildStore()
	if store == nil or not GuildRules.isGuildId(guildId) then
		return false, nil
	end
	local isSuccess, value = withRetries(function()
		return store:GetAsync(guildId, getReadOptions())
	end)
	if not isSuccess then
		warn(`[Guild] Lecture impossible de {guildId} : {value}`)
		return false, nil
	end
	local record = GuildRules.sanitize(value)
	if value ~= nil and record == nil then
		-- Illisible = comme une lecture en échec : surtout pas « la guilde n'existe pas » (on effacerait
		-- les pointeurs de ses membres).
		warn(`[Guild] Enregistrement illisible pour {guildId} : ignoré (la donnée n'est pas touchée).`)
		return false, nil
	end
	return true, remember(guildId, record)
end

--[[
	Applique `transform` à la guilde `guildId` via UpdateAsync. YIELD.
	Retourne (true, record écrit ou inchangé, nil) ou (false, nil, erreur) :
		"datastore" / "unavailable" : la requête n'a pas abouti (rien n'est sûr : réessayer avec le même opId) ;
		"corrupt"                   : la valeur stockée est illisible (jamais écrasée) ;
		autre code                  : refus de GuildRules (définitif).
]]
function GuildStore.update(guildId: string, transform: Transform): (boolean, GuildRecord?, string?)
	local store = getGuildStore()
	if store == nil then
		return false, nil, "unavailable"
	end
	if not GuildRules.isGuildId(guildId) then
		return false, nil, "bad_params"
	end

	local resultRecord: GuildRecord? = nil
	local ruleError: string? = nil
	local isSuccess, errorMessage = withRetries(function()
		return store:UpdateAsync(guildId, function(current: any): any
			-- UpdateAsync peut appeler cette fonction plusieurs fois : on repart de zéro à chaque appel.
			resultRecord, ruleError = nil, nil
			local record = GuildRules.sanitize(current)
			if current ~= nil and record == nil then
				ruleError = "corrupt"
				return nil -- nil = annuler l'écriture
			end
			local nextRecord, code = transform(record)
			if nextRecord == nil then
				ruleError = code or "rejected"
				return nil
			end
			resultRecord = nextRecord
			if nextRecord == record then
				return nil -- déjà appliqué : rien à écrire
			end
			return nextRecord
		end)
	end)

	if not isSuccess then
		warn(`[Guild] Écriture impossible de {guildId} : {errorMessage}`)
		return false, nil, "datastore"
	end
	if ruleError ~= nil or resultRecord == nil then
		return false, nil, ruleError or "rejected"
	end
	return true, remember(guildId, resultRecord), nil
end

-- Copie en mémoire de la guilde (nil si jamais lue ou si elle n'existe pas). Ne jamais la modifier.
function GuildStore.getCached(guildId: string): GuildRecord?
	local entry = cache[guildId]
	return entry and entry.record
end

-- Âge (secondes) de la copie en mémoire, ou nil si la guilde n'a jamais été lue sur ce serveur.
function GuildStore.getCacheAge(guildId: string): number?
	local entry = cache[guildId]
	return entry and (os.clock() - entry.readAt)
end

-- Oublie la copie en mémoire (plus aucun membre sur ce serveur).
function GuildStore.forget(guildId: string)
	cache[guildId] = nil
end

--------------------------------------------------------------------------------
-- Indices d'appartenance joueur ("U_<userId>")
--------------------------------------------------------------------------------

-- Lit les indices de `userId`. YIELD. (false, nil) si la lecture a échoué.
function GuildStore.readUser(userId: number): (boolean, UserHints?)
	local store = getGuildStore()
	if store == nil or not GuildRules.isUserId(userId) then
		return false, nil
	end
	local isSuccess, value = withRetries(function()
		return store:GetAsync(userKey(userId), getReadOptions())
	end)
	if not isSuccess then
		return false, nil
	end
	return true, GuildRules.sanitizeHints(value)
end

-- Modifie les indices de `userId` (transformation pure). YIELD. Retourne (succès, indices écrits).
function GuildStore.updateUser(userId: number, transform: HintsTransform): (boolean, UserHints?)
	local store = getGuildStore()
	if store == nil or not GuildRules.isUserId(userId) then
		return false, nil
	end
	local written: UserHints? = nil
	local isSuccess = withRetries(function()
		return store:UpdateAsync(userKey(userId), function(current: any): any
			written = transform(GuildRules.sanitizeHints(current))
			return written, { userId } -- clé associée au joueur (RGPD)
		end)
	end)
	return isSuccess, if isSuccess then written else nil
end

--------------------------------------------------------------------------------
-- Index des noms
--------------------------------------------------------------------------------

-- Une tentative de réservation. Retourne (réservé, entrée qui bloque, requête aboutie).
local function tryReserve(store: DataStore, nameKey: string, guildId: string, now: number, overridable: string?): (boolean, NameEntry?, boolean)
	local isReserved = false
	local blocking: NameEntry? = nil
	local isSuccess = withRetries(function()
		return store:UpdateAsync(nameKey, function(current: any): any
			isReserved, blocking = false, nil
			local entry = asNameEntry(current)
			local isFree = entry == nil
				or entry.status == "released"
				or entry.guildId == guildId
				or entry.guildId == overridable
			if not isFree then
				blocking = entry
				return nil
			end
			isReserved = true
			local reserved: NameEntry = { guildId = guildId, status = "reserved", at = now }
			return reserved
		end)
	end)
	return isReserved, blocking, isSuccess
end

--[[
	Réserve le nom normalisé `nameKey` pour la future guilde `guildId`. YIELD.
	Retourne (true) ou (false, "name_taken" | "datastore" | "unavailable").
]]
function GuildStore.reserveName(nameKey: string, guildId: string, now: number): (boolean, string?)
	local store = getNameStore()
	if store == nil then
		return false, "unavailable"
	end
	local isReserved, blocking, isSuccess = tryReserve(store, nameKey, guildId, now, nil)
	if not isSuccess then
		return false, "datastore"
	end
	if isReserved then
		return true, nil
	end
	if blocking == nil then
		return false, "datastore"
	end

	-- Une création est peut-être en cours ailleurs : la réservation récente fait foi.
	if blocking.status == "reserved" and now - blocking.at < GuildConfig.NAME_RESERVATION_TTL then
		return false, "name_taken"
	end

	-- Entrée « active » ou réservation expirée : on vérifie la guilde qu'elle désigne.
	local isRead, record = GuildStore.read(blocking.guildId)
	if not isRead then
		return false, "datastore"
	end
	if record ~= nil and record.status == "active" and record.nameKey == nameKey then
		if blocking.status == "reserved" then
			GuildStore.confirmName(nameKey, blocking.guildId) -- création réussie mais jamais confirmée
		end
		return false, "name_taken"
	end

	-- La guilde désignée n'existe pas ou n'est plus active : le nom est libre, on le reprend.
	local isRetried, _, isRetrySuccess = tryReserve(store, nameKey, guildId, now, blocking.guildId)
	if not isRetrySuccess then
		return false, "datastore"
	end
	return isRetried, if isRetried then nil else "name_taken"
end

-- La guilde `guildId` est créée : son nom devient « actif ». YIELD. Retourne false si non écrit.
function GuildStore.confirmName(nameKey: string, guildId: string): boolean
	local store = getNameStore()
	if store == nil then
		return false
	end
	local isConfirmed = false
	local isSuccess = withRetries(function()
		return store:UpdateAsync(nameKey, function(current: any): any
			isConfirmed = false
			local entry = asNameEntry(current)
			if entry == nil or entry.guildId ~= guildId then
				return nil -- le nom a été repris entre-temps : ne rien écraser
			end
			isConfirmed = true
			if entry.status == "active" then
				return nil
			end
			local active: NameEntry = { guildId = guildId, status = "active", at = entry.at }
			return active
		end)
	end)
	return isSuccess and isConfirmed
end

-- Libère le nom s'il appartient encore à `guildId` (dissolution, création abandonnée). YIELD.
function GuildStore.releaseName(nameKey: string, guildId: string, now: number): boolean
	local store = getNameStore()
	if store == nil then
		return false
	end
	local isSuccess = withRetries(function()
		return store:UpdateAsync(nameKey, function(current: any): any
			local entry = asNameEntry(current)
			if entry == nil or entry.guildId ~= guildId or entry.status == "released" then
				return nil
			end
			local released: NameEntry = { guildId = guildId, status = "released", at = now }
			return released
		end)
	end)
	return isSuccess
end

return GuildStore
