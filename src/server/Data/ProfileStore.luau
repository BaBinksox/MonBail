--!strict
--[[
	ProfileStore
	Sauvegarde des joueurs avec DataStoreService (singleton serveur).

	Un "profil" est une simple table par joueur, chargée à sa connexion et gardée en mémoire :
		{ version = 1, avatar = <apparence + magie choisies dans le Hub, ou nil> }
	Les autres services lisent et modifient cette table, puis appellent markDirty() et save().
	Ajouter une donnée à sauvegarder = l'ajouter au type Profile, à newProfile() et à PROFILE_FIELDS.

	Dans le DataStore, l'enregistrement d'un joueur contient le profil plus un champ technique :
		{ version = 1, avatar = {...}, _session = { sessionId, serverId, jobId, placeId, lockedAt, renewedAt } }
	`_session` est le VERROU DE SESSION : le serveur qui l'a posé est le seul à avoir le droit d'écrire.

	Garanties :
		1. Toute écriture passe par UpdateAsync et vérifie, au moment même de l'écriture, que le verrou
		   nous appartient encore. Deux serveurs ne peuvent donc jamais écrire en même temps le même
		   profil, même pendant un changement de serveur.
		2. Si le chargement a ÉCHOUÉ (DataStore en panne, accès API désactivé dans Studio, donnée
		   illisible...), le joueur joue quand même, mais rien ne sera écrit pour lui : on n'écrase
		   jamais une sauvegarde qu'on n'a pas réussi à lire.
		3. Si un autre serveur détient encore le verrou (changement de serveur rapide), on attend qu'il
		   le libère. S'il ne le fait pas à temps, le joueur joue en LECTURE SEULE avec ses vraies
		   données, et on retente de prendre le verrou à chaque sauvegarde automatique.
		4. Un verrou qui n'a pas été renouvelé depuis LOCK_EXPIRY secondes (serveur planté) est repris.
		5. Seuls les champs de PROFILE_FIELDS et `_session` sont réécrits : tout autre champ présent
		   dans l'enregistrement est conservé tel quel.
		6. Une seule écriture à la fois par joueur : save(), sauvegarde automatique et release()
		   passent l'une après l'autre, dans l'ordre.
		7. Sauvegarde automatique toutes les AUTOSAVE_INTERVAL secondes (elle renouvelle aussi le verrou),
		   et dernière sauvegarde + libération du verrou au départ du joueur et à la fermeture du serveur.

	Dans Studio, les DataStores ne marchent que si le jeu est publié et que
	Game Settings > Security > "Enable Studio Access to API Services" est coché.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ProfileSchema = require(script.Parent.ProfileSchema)

-- Changer ce nom repart d'une base vide (utile pour remettre tous les joueurs à zéro).
local STORE_NAME = "PlayerProfiles_v4"

-- Version du schéma du profil. Pour la faire évoluer : l'incrémenter ET ajouter la migration
-- correspondante dans MIGRATIONS (sinon le chargement échoue volontairement, en lecture seule).
-- La forme du profil, ses valeurs par défaut et ses migrations sont dans ProfileSchema.
local PROFILE_VERSION = ProfileSchema.VERSION

-- Champs du profil écrits dans le DataStore. Les autres champs de l'enregistrement ne sont jamais touchés.
local PROFILE_FIELDS = ProfileSchema.FIELDS

-- Champs techniques de l'enregistrement (hors profil).
local LOCK_FIELD = "_session"
local BACKUP_FIELD = "_backups" -- copies faites avant chaque migration de schéma

local MAX_ATTEMPTS = 3 -- tentatives par requête DataStore
local RELEASE_ATTEMPTS = 4 -- la dernière sauvegarde mérite une tentative de plus
local RETRY_DELAY = 1 -- secondes ; le délai double à chaque nouvelle tentative

local AUTOSAVE_INTERVAL = 60 -- secondes entre deux sauvegardes automatiques d'un joueur
local LOCK_EXPIRY = 300 -- secondes sans renouvellement après lesquelles un verrou est considéré abandonné
local LOCK_WAIT_TIME = 30 -- secondes d'attente maximum d'un verrou tenu par un autre serveur, à la connexion
local LOCK_RETRY_DELAY = 5 -- secondes entre deux essais pendant cette attente
local USER_BUSY_TIMEOUT = 30 -- secondes d'attente maximum d'un départ du même joueur encore en cours
local CLOSE_TIMEOUT = 25 -- secondes laissées aux sauvegardes à la fermeture (Roblox en accorde 30)

-- Identifiant de CE serveur. game.JobId est vide dans Studio, donc inutilisable pour distinguer deux tests.
local SERVER_ID = HttpService:GenerateGUID(false)

export type Profile = ProfileSchema.Profile

-- Pourquoi un profil n'est pas sauvegardable (nil = il l'est).
type ReadOnlyReason = "loadFailed" | "locked" | "newerVersion" | "corrupt" | "lockLost" | "closing"

type Session = {
	id: string, -- identifiant unique de cette session de jeu, inscrit dans le verrou
	player: Player,
	userId: number,
	key: string,
	profile: Profile,
	ownsLock: boolean, -- vrai seulement si le verrou du DataStore est à nous : seul cas où l'on écrit
	readOnlyReason: ReadOnlyReason?,
	isDirty: boolean, -- le profil a changé depuis la dernière écriture réussie
	isWriting: boolean, -- une requête DataStore est en cours pour ce profil (verrou local)
	isReleased: boolean, -- release() a commencé : plus de sauvegarde automatique
	isReleaseDone: boolean,
	nextAutosaveAt: number, -- os.clock()
}

-- Résultat d'une tentative de prise du verrou.
type AcquireOutcome = "acquired" | "locked" | "newerVersion" | "corrupt" | "error"

-- Migrations du schéma : MIGRATIONS[n] transforme un enregistrement de version n en version n + 1.
-- Une migration MODIFIE `record` sur place, sans yield, et ne supprime jamais une donnée du joueur :
-- elle copie vers le nouveau champ et laisse l'ancien (une copie complète est de toute façon faite
-- dans `_backups` avant de migrer).
local MIGRATIONS: { [number]: (record: { [string]: any }) -> () } = {
	[1] = ProfileSchema.migrateV1toV2, -- ajoute la progression RPG (quêtes, rang, inventaire...) sans toucher à l'avatar
	[2] = ProfileSchema.migrateV2toV3, -- peuple et teint par défaut des personnages existants, verdict du Destin
}

local ProfileStore = {}

-- Signaux pour les autres services (voir Shared/Util/Signal) :
--   ProfileLoaded(player, profile)     le profil est chargé et rattaché au joueur (sauvegardable ou non) ;
--   ProfileRefreshed(player, profile)  un profil en lecture seule vient de redevenir sauvegardable et ses
--                                      données ont été relues (les services doivent rafraîchir leur état) ;
--   ProfileReleasing(player, profile)  le joueur part : DERNIÈRE occasion d'écrire dans le profil avant la
--                                      sauvegarde finale. Les écouteurs doivent écrire SANS yield (ils sont
--                                      appelés immédiatement, la sauvegarde part juste après).
ProfileStore.ProfileLoaded = Signal.new()
ProfileStore.ProfileRefreshed = Signal.new()
ProfileStore.ProfileReleasing = Signal.new()

local sessions: { [Player]: Session } = {} -- profils chargés
local loadingSessions: { [Player]: Session } = {} -- chargements en cours
local userBusy: { [number]: number? } = {} -- nombre d'opérations de chargement / départ en cours par UserId
local dataStore: DataStore? = nil
local hasWarnedUnavailable = false
local isStarted = false
local isClosing = false
local activeLoads = 0
local activeReleases = 0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function newProfile(): Profile
	return ProfileSchema.new()
end

local function getKey(player: Player): string
	return `Player_{player.UserId}`
end

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

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function warnUnavailable(errorMessage: any)
	if hasWarnedUnavailable then
		return
	end
	hasWarnedUnavailable = true
	warn(
		`[Data] DataStore indisponible : les joueurs concernés jouent sans sauvegarde. ({errorMessage})\n`
			.. `Dans Studio : publier le jeu, puis cocher Game Settings > Security > "Enable Studio Access to API Services".`
	)
end

local function getDataStore(): DataStore?
	if dataStore == nil then
		local isAvailable, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if isAvailable then
			dataStore = result
		else
			warnUnavailable(result)
		end
	end
	return dataStore
end

-- Exécute `request` jusqu'à `attempts` fois, avec un délai qui double. Retourne (succès, résultat ou erreur).
local function withRetries(request: () -> any, attempts: number): (boolean, any)
	local lastError: any = nil
	for attempt = 1, attempts do
		local isSuccess, result = pcall(request)
		if isSuccess then
			return true, result
		end
		lastError = result

		-- 403 = accès refusé (API désactivée dans Studio...) et "[Data]" = erreur de ce module
		-- (migration manquante) : réessayer ne changerait rien.
		local message = tostring(result)
		if attempt == attempts or string.find(message, "403", 1, true) or string.find(message, "[Data]", 1, true) then
			break
		end
		task.wait(RETRY_DELAY * 2 ^ (attempt - 1))
	end
	return false, lastError
end

-- Liste des UserIds associés à la clé (RGPD) : on garde l'existant et on y ajoute le joueur.
local function getUserIds(keyInfo: DataStoreKeyInfo?, userId: number): { number }
	local userIds = if keyInfo then keyInfo:GetUserIds() else {}
	if not table.find(userIds, userId) then
		table.insert(userIds, userId)
	end
	return userIds
end

local function getMetadata(keyInfo: DataStoreKeyInfo?): any
	return if keyInfo then keyInfo:GetMetadata() else nil
end

-- Verrou local : une seule requête DataStore à la fois par profil, dans l'ordre d'arrivée.
local function lockWrites(session: Session)
	while session.isWriting do
		task.wait()
	end
	session.isWriting = true
end

local function unlockWrites(session: Session)
	session.isWriting = false
end

local function markUserBusy(userId: number)
	userBusy[userId] = (userBusy[userId] or 0) + 1
end

local function unmarkUserBusy(userId: number)
	local count = (userBusy[userId] or 1) - 1
	userBusy[userId] = if count > 0 then count else nil
end

-- Attend la fin d'un chargement ou d'un départ du même joueur sur ce serveur (il est parti puis
-- revenu très vite) : sans ça, on pourrait relire sa sauvegarde AVANT que la dernière soit écrite.
local function waitUserIdle(userId: number)
	local deadline = os.clock() + USER_BUSY_TIMEOUT
	while userBusy[userId] and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- true si `sessionId` est une session vivante de ce serveur.
local function isLiveSession(sessionId: any): boolean
	for _, session in sessions do
		if session.id == sessionId then
			return true
		end
	end
	return false
end

-- Le verrou `lock` empêche-t-il `session` de prendre le profil ? (Appelé dans UpdateAsync : sans yield.)
local function isLockedByOther(lock: any, session: Session): boolean
	if type(lock) ~= "table" or lock.sessionId == session.id then
		return false
	end
	-- Verrou d'une ancienne session de CE serveur dont la libération a échoué : personne d'autre
	-- ne peut avoir de donnée plus récente, on peut le reprendre sans attendre.
	if lock.serverId == SERVER_ID and not isLiveSession(lock.sessionId) then
		return false
	end
	if type(lock.renewedAt) ~= "number" then
		return false -- verrou illisible : considéré comme abandonné
	end
	return os.time() - lock.renewedAt < LOCK_EXPIRY
end

-- Amène `record` à PROFILE_VERSION. Erreur (=> chargement en lecture seule) si une migration manque.
local function migrate(record: { [string]: any })
	local version = if type(record.version) == "number" then record.version else 1
	if version >= PROFILE_VERSION then
		record.version = PROFILE_VERSION
		return
	end

	-- Copie de sécurité de l'enregistrement tel qu'il était, avant toute transformation.
	local backup = deepCopy(record)
	backup[LOCK_FIELD] = nil
	backup[BACKUP_FIELD] = nil
	local backups = if type(record[BACKUP_FIELD]) == "table" then record[BACKUP_FIELD] else {}
	backups[`v{version}`] = backup
	record[BACKUP_FIELD] = backups

	for fromVersion = version, PROFILE_VERSION - 1 do
		local step = MIGRATIONS[fromVersion]
		if step == nil then
			error(`[Data] Migration manquante : version {fromVersion} -> {fromVersion + 1}`)
		end
		step(record)
		record.version = fromVersion + 1
	end
end

-- Recopie dans le profil EN PLACE (les autres services gardent une référence à cette table ; ils ne
-- doivent pas, en revanche, garder de référence aux sous-tables : elles sont remplacées ici).
local function applyRecord(profile: Profile, record: { [string]: any })
	ProfileSchema.applyRecord(profile, record)
end

--------------------------------------------------------------------------------
-- Requêtes DataStore
--------------------------------------------------------------------------------

-- Tente de poser notre verrou sur l'enregistrement. YIELD.
-- Retourne l'issue et l'enregistrement lu (copie), même quand le verrou est tenu par un autre.
local function tryAcquire(store: DataStore, session: Session): (AcquireOutcome, any)
	local outcome: AcquireOutcome = "error"
	local seenRecord: any = nil

	local isSuccess, errorMessage = withRetries(function()
		return store:UpdateAsync(session.key, function(current: any, keyInfo: DataStoreKeyInfo?)
			-- UpdateAsync peut appeler cette fonction plusieurs fois : on repart de zéro à chaque appel.
			outcome, seenRecord = "error", nil

			if current ~= nil and type(current) ~= "table" then
				outcome = "corrupt"
				return nil -- nil = annuler l'écriture
			end

			local record: { [string]: any } = if current then deepCopy(current) else { version = PROFILE_VERSION }
			seenRecord = deepCopy(record)

			if isLockedByOther(record[LOCK_FIELD], session) then
				outcome = "locked"
				return nil
			end
			if type(record.version) == "number" and record.version > PROFILE_VERSION then
				outcome = "newerVersion" -- écrit par une version plus récente du jeu : on ne le rétrograde pas
				return nil
			end

			migrate(record)
			local now = os.time()
			record[LOCK_FIELD] = {
				sessionId = session.id,
				serverId = SERVER_ID,
				jobId = game.JobId,
				placeId = game.PlaceId,
				lockedAt = now,
				renewedAt = now,
			}
			seenRecord = deepCopy(record)
			outcome = "acquired"
			return record, getUserIds(keyInfo, session.userId), getMetadata(keyInfo)
		end)
	end, MAX_ATTEMPTS)

	if not isSuccess then
		return "error", errorMessage
	end
	return outcome, seenRecord
end

type WriteMode = "save" | "renew" | "release"

-- Écrit le profil si le verrou est encore à nous. YIELD. Retourne false si rien n'a pu être écrit.
--   "save"    : seulement si le profil a changé ;
--   "renew"   : sauvegarde automatique, écrit toujours (renouvelle le verrou) ;
--   "release" : dernière écriture, puis libère le verrou.
local function writeSession(session: Session, mode: WriteMode, attempts: number): boolean
	lockWrites(session)

	local store = getDataStore()
	if store == nil or not session.ownsLock then
		unlockWrites(session)
		return false
	end
	if mode == "save" and not session.isDirty then
		unlockWrites(session)
		return true
	end

	-- On écrit l'état du profil À CET INSTANT. Un changement fait pendant la requête remet
	-- isDirty à true et partira à l'écriture suivante.
	local snapshot: { [string]: any } = {}
	for _, field in PROFILE_FIELDS do
		snapshot[field] = deepCopy((session.profile :: any)[field])
	end
	local wasDirty = session.isDirty
	session.isDirty = false

	local outcome: "ok" | "lockLost" | "error" = "error"
	local isSuccess, errorMessage = withRetries(function()
		return store:UpdateAsync(session.key, function(current: any, keyInfo: DataStoreKeyInfo?)
			outcome = "error"
			local lock = if type(current) == "table" then current[LOCK_FIELD] else nil
			if type(lock) ~= "table" or lock.sessionId ~= session.id then
				outcome = "lockLost"
				return nil
			end

			local record = deepCopy(current)
			for _, field in PROFILE_FIELDS do
				record[field] = deepCopy(snapshot[field])
			end
			if mode == "release" then
				record[LOCK_FIELD] = nil
			else
				record[LOCK_FIELD].renewedAt = os.time()
			end
			outcome = "ok"
			return record, getUserIds(keyInfo, session.userId), getMetadata(keyInfo)
		end)
	end, attempts)

	local isSaved = isSuccess and outcome == "ok"
	if isSaved then
		if mode == "release" then
			session.ownsLock = false
		end
	elseif isSuccess and outcome == "lockLost" then
		-- Un autre serveur a repris ce profil (notre verrou avait expiré) : on ne doit plus rien écrire.
		session.ownsLock = false
		session.readOnlyReason = "lockLost"
		session.isDirty = session.isDirty or wasDirty
		warn(`[Data] Verrou perdu pour {session.player.Name} : un autre serveur a repris son profil, plus rien ne sera écrit ici.`)
	else
		session.isDirty = session.isDirty or wasDirty
		warn(`[Data] Sauvegarde impossible pour {session.player.Name} ({mode}) : {errorMessage}`)
	end

	unlockWrites(session)
	return isSaved
end

-- Joueur en lecture seule parce qu'un autre serveur tenait son verrou : on retente de le prendre.
-- Seulement si rien n'a changé ici, pour ne jamais mélanger deux versions du profil.
local function retryAcquire(session: Session)
	local store = getDataStore()
	if store == nil or session.isDirty then
		return
	end

	lockWrites(session)
	if session.isReleased or session.ownsLock or session.readOnlyReason ~= "locked" then
		unlockWrites(session)
		return
	end

	local outcome, record = tryAcquire(store, session)
	if outcome == "acquired" then
		session.ownsLock = true
		session.readOnlyReason = nil
		-- Si le joueur a modifié son profil pendant la requête, sa version en mémoire est la plus
		-- récente : elle sera écrite. Sinon on reprend la donnée du DataStore, peut-être plus fraîche.
		if not session.isDirty then
			applyRecord(session.profile, record)
		end
		print(`[Data] Profil de {session.player.Name} de nouveau sauvegardable.`)
		ProfileStore.ProfileRefreshed:Fire(session.player, session.profile)
	end
	unlockWrites(session)
end

-- Dernière sauvegarde et libération du verrou. YIELD. Sans effet si déjà fait ; si une
-- libération est déjà en cours, attend qu'elle se termine.
local function releaseSession(session: Session)
	if session.isReleased then
		while not session.isReleaseDone do
			task.wait()
		end
		return
	end
	session.isReleased = true
	activeReleases += 1
	markUserBusy(session.userId)

	-- writeSession attend une éventuelle écriture en cours, puis vérifie lui-même qu'on a le verrou.
	writeSession(session, "release", RELEASE_ATTEMPTS)

	session.isReleaseDone = true
	unmarkUserBusy(session.userId)
	activeReleases -= 1
end

local function autosave(session: Session)
	if session.isReleased then
		return
	end
	if session.ownsLock then
		writeSession(session, "renew", MAX_ATTEMPTS)
	elseif session.readOnlyReason == "locked" then
		retryAcquire(session)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Charge le profil de `player` et pose son verrou de session. YIELD. Retourne toujours un profil
-- utilisable : celui de la sauvegarde, ou un profil vide (nouveau joueur, ou chargement impossible).
function ProfileStore.load(player: Player): Profile
	local existingSession = sessions[player]
	if existingSession then
		return existingSession.profile
	end
	local pendingSession = loadingSessions[player]
	if pendingSession then
		while loadingSessions[player] == pendingSession do
			task.wait()
		end
		return pendingSession.profile
	end

	local session: Session = {
		id = HttpService:GenerateGUID(false),
		player = player,
		userId = player.UserId,
		key = getKey(player),
		profile = newProfile(),
		ownsLock = false,
		readOnlyReason = nil,
		isDirty = false,
		isWriting = false,
		isReleased = false,
		isReleaseDone = false,
		nextAutosaveAt = 0,
	}
	loadingSessions[player] = session
	activeLoads += 1

	waitUserIdle(session.userId)
	markUserBusy(session.userId)

	local store = getDataStore()
	if isClosing then
		session.readOnlyReason = "closing"
	elseif store == nil then
		session.readOnlyReason = "loadFailed"
	else
		lockWrites(session)
		local lockDeadline = os.clock() + LOCK_WAIT_TIME
		while true do
			local outcome, result = tryAcquire(store, session)
			if outcome == "acquired" then
				session.ownsLock = true
				applyRecord(session.profile, result)
				break
			elseif outcome == "locked" then
				-- Lire est sans risque : le joueur retrouve ses données, même si on ne peut pas encore écrire.
				applyRecord(session.profile, result)
				if os.clock() >= lockDeadline or isClosing or not isInGame(player) then
					session.readOnlyReason = "locked"
					warn(
						`[Data] Le profil de {player.Name} est encore verrouillé par un autre serveur : `
							.. `lecture seule pour l'instant, nouvel essai à chaque sauvegarde automatique.`
					)
					break
				end
				task.wait(LOCK_RETRY_DELAY)
			elseif outcome == "newerVersion" then
				applyRecord(session.profile, result)
				session.readOnlyReason = "newerVersion"
				warn(`[Data] Le profil de {player.Name} vient d'une version plus récente du jeu : lecture seule.`)
				break
			elseif outcome == "corrupt" then
				session.readOnlyReason = "corrupt"
				warn(`[Data] Sauvegarde illisible pour {player.Name} : profil vide en lecture seule, la donnée n'est pas touchée.`)
				break
			else
				session.readOnlyReason = "loadFailed"
				warn(`[Data] Chargement impossible pour {player.Name} : profil vide, rien ne sera écrit pour lui. ({result})`)
				warnUnavailable(result)
				break
			end
		end
		unlockWrites(session)
	end

	loadingSessions[player] = nil
	if isInGame(player) and not isClosing then
		session.nextAutosaveAt = os.clock() + AUTOSAVE_INTERVAL * (0.5 + math.random() * 0.5) -- étalé dans le temps
		sessions[player] = session
		ProfileStore.ProfileLoaded:Fire(player, session.profile)
	else
		-- Parti pendant le chargement (ou serveur en fermeture) : on rend le verrou tout de suite,
		-- sinon il bloquerait sa prochaine connexion pendant LOCK_EXPIRY secondes.
		releaseSession(session)
	end

	unmarkUserBusy(session.userId)
	activeLoads -= 1
	return session.profile
end

-- Profil déjà chargé de `player`, ou nil s'il ne l'est pas (encore).
function ProfileStore.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.profile
end

-- À appeler après avoir modifié le profil : il sera écrit au prochain save() ou à la sauvegarde automatique.
function ProfileStore.markDirty(player: Player)
	local session = sessions[player]
	if session then
		session.isDirty = true
	end
end

-- Écrit le profil de `player` s'il a changé. YIELD. Retourne false si rien n'a pu être écrit
-- (profil en lecture seule, DataStore en panne...). Les modifications restent alors en mémoire
-- et seront retentées par la sauvegarde automatique.
function ProfileStore.save(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	return writeSession(session, "save", MAX_ATTEMPTS)
end

-- Départ du joueur : dernière sauvegarde, libération du verrou, puis oubli du profil. YIELD.
-- Si le chargement est encore en cours, c'est load() qui libérera le verrou en voyant le joueur parti.
function ProfileStore.release(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	-- Les services écrivent leurs dernières données (sans yield) avant la sauvegarde finale.
	ProfileStore.ProfileReleasing:Fire(player, session.profile)
	sessions[player] = nil
	releaseSession(session)
end

-- Attend que le profil de `player` soit chargé. YIELD. Retourne nil si le joueur part ou si
-- `timeout` secondes (30 par défaut) s'écoulent avant.
function ProfileStore.waitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while sessions[player] == nil and isInGame(player) and os.clock() < deadline do
		task.wait(0.1)
	end
	local session = sessions[player]
	return session and session.profile
end

-- true si le profil de `player` est chargé ET sera réellement écrit (verrou détenu). Sert à prévenir
-- le joueur ("sauvegarde désactivée") et à refuser les actions qui n'auraient de sens que sauvegardées
-- (création de guilde...).
function ProfileStore.isSaveable(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.ownsLock and not session.isReleased
end

-- À appeler une seule fois au démarrage du serveur.
function ProfileStore.start()
	if isStarted then
		return
	end
	isStarted = true

	-- Sauvegarde automatique : chaque profil a sa propre échéance, étalée pour lisser les requêtes.
	task.spawn(function()
		while not isClosing do
			task.wait(1)
			local now = os.clock()
			local dueSessions: { Session } = {}
			for _, session in sessions do
				if not session.isReleased and not session.isWriting and now >= session.nextAutosaveAt then
					session.nextAutosaveAt = now + AUTOSAVE_INTERVAL
					table.insert(dueSessions, session)
				end
			end
			for _, session in dueSessions do
				task.spawn(autosave, session)
			end
		end
	end)

	-- Fermeture du serveur : on sauvegarde et libère tous les profils avant de rendre la main
	-- (PlayerRemoving n'a pas toujours le temps de finir quand le serveur s'arrête).
	game:BindToClose(function()
		isClosing = true
		local players: { Player } = {}
		for player in sessions do
			table.insert(players, player)
		end
		for _, player in players do
			task.spawn(ProfileStore.release, player)
		end

		-- On attend aussi les départs et les chargements déjà en cours (ils libèrent leur verrou).
		local deadline = os.clock() + CLOSE_TIMEOUT
		while (next(sessions) ~= nil or activeReleases > 0 or activeLoads > 0) and os.clock() < deadline do
			task.wait()
		end
	end)
end

return ProfileStore
