--!strict
--[[
	ProfileStore
	Sauvegarde des joueurs avec DataStoreService (singleton serveur).

	Un "profil" est une simple table par joueur, chargée à sa connexion et gardée en mémoire :
		{ version = 1, avatar = <apparence + magie choisies dans le Hub, ou nil> }
	Les autres services lisent et modifient cette table, puis appellent save().
	Ajouter une donnée à sauvegarder = ajouter un champ au profil (et à newProfile()).

	Garde-fou essentiel : si le chargement a ÉCHOUÉ (DataStore en panne, accès API désactivé dans
	Studio...), le joueur joue quand même avec un profil vide, mais rien ne sera écrit pour lui :
	on n'écrase jamais une sauvegarde qu'on n'a pas réussi à lire.

	Dans Studio, les DataStores ne marchent que si le jeu est publié et que
	Game Settings > Security > "Enable Studio Access to API Services" est coché.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Changer ce nom repart d'une base vide (utile pour remettre tous les joueurs à zéro).
local STORE_NAME = "PlayerProfiles_v4"
local PROFILE_VERSION = 1
local MAX_ATTEMPTS = 3
local RETRY_DELAY = 1.5 -- secondes entre deux tentatives

export type Profile = {
	version: number,
	avatar: any?, -- écrit et relu par AvatarSerializer
}

type Session = {
	profile: Profile,
	canSave: boolean, -- false si le chargement a échoué
	isDirty: boolean, -- le profil a changé depuis la dernière écriture
}

local ProfileStore = {}

local sessions: { [Player]: Session } = {}
local dataStore: DataStore? = nil
local hasWarnedUnavailable = false
local isStarted = false

--------------------------------------------------------------------------------
-- Accès au DataStore
--------------------------------------------------------------------------------

local function newProfile(): Profile
	return {
		version = PROFILE_VERSION,
		avatar = nil,
	}
end

local function getKey(player: Player): string
	return `Player_{player.UserId}`
end

local function warnUnavailable(errorMessage: any)
	if hasWarnedUnavailable then
		return
	end
	hasWarnedUnavailable = true
	warn(
		`[Data] DataStore indisponible : rien ne sera sauvegardé pendant cette session. ({errorMessage})\n`
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

-- Exécute `request` jusqu'à MAX_ATTEMPTS fois. Retourne (succès, résultat ou message d'erreur).
local function withRetries(request: () -> any): (boolean, any)
	local lastError: any = nil
	for attempt = 1, MAX_ATTEMPTS do
		local isSuccess, result = pcall(request)
		if isSuccess then
			return true, result
		end
		lastError = result

		-- Dans Studio, un échec vient presque toujours de l'accès API désactivé : réessayer
		-- ne ferait que retarder l'ouverture du jeu de plusieurs secondes.
		if RunService:IsStudio() or attempt == MAX_ATTEMPTS then
			break
		end
		task.wait(RETRY_DELAY * attempt)
	end
	return false, lastError
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Charge le profil de `player`. YIELD. Retourne toujours un profil utilisable :
-- celui de la sauvegarde, ou un profil vide (nouveau joueur, ou chargement impossible).
function ProfileStore.load(player: Player): Profile
	local existingSession = sessions[player]
	if existingSession then
		return existingSession.profile
	end

	local session: Session = {
		profile = newProfile(),
		canSave = false,
		isDirty = false,
	}

	local store = getDataStore()
	if store then
		local isLoaded, data = withRetries(function()
			return store:GetAsync(getKey(player))
		end)
		if isLoaded then
			session.canSave = true
			if type(data) == "table" then
				session.profile.avatar = data.avatar
			end
		else
			warnUnavailable(data)
		end
	end

	-- Le joueur a pu partir pendant le chargement : on ne garde rien pour un absent.
	if player:IsDescendantOf(Players) then
		sessions[player] = session
	end
	return session.profile
end

-- Profil déjà chargé de `player`, ou nil s'il ne l'est pas (encore).
function ProfileStore.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.profile
end

-- À appeler après avoir modifié le profil : il sera écrit au prochain save().
function ProfileStore.markDirty(player: Player)
	local session = sessions[player]
	if session then
		session.isDirty = true
	end
end

-- Écrit le profil de `player` s'il a changé. YIELD. Retourne false si rien n'a pu être écrit.
function ProfileStore.save(player: Player): boolean
	local session = sessions[player]
	local store = getDataStore()
	if session == nil or store == nil or not session.canSave then
		return false
	end
	if not session.isDirty then
		return true
	end

	session.isDirty = false -- avant l'écriture : un changement fait pendant qu'elle a lieu reste à sauver
	local isSaved, errorMessage = withRetries(function()
		store:SetAsync(getKey(player), session.profile)
		return nil
	end)
	if not isSaved then
		session.isDirty = true
		warn(`[Data] Sauvegarde impossible pour {player.Name} : {errorMessage}`)
	end
	return isSaved
end

-- Départ du joueur : dernière sauvegarde, puis oubli du profil. YIELD.
function ProfileStore.release(player: Player)
	ProfileStore.save(player)
	sessions[player] = nil
end

-- À appeler une seule fois au démarrage du serveur.
function ProfileStore.start()
	if isStarted then
		return
	end
	isStarted = true

	-- Fermeture du serveur : on écrit tous les profils modifiés avant de rendre la main
	-- (PlayerRemoving n'a pas toujours le temps de finir quand le serveur s'arrête).
	game:BindToClose(function()
		local pendingSaves = 0
		for player in sessions do
			pendingSaves += 1
			task.spawn(function()
				ProfileStore.save(player)
				pendingSaves -= 1
			end)
		end
		while pendingSaves > 0 do
			task.wait()
		end
	end)
end

return ProfileStore
