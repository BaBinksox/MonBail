--!strict
--[[
	TimeLoopService
	Façade serveur du Time-Loop (singleton). C'est le SEUL module que le reste du jeu doit appeler.
		- inscrit les joueurs et les PNJ taggés dans la session d'enregistrement ;
		- gère l'état critique "anomalie temporelle" (joueur figé, fenêtre de survie, mort à l'expiration) ;
		- valide les demandes de rewind des clients (anomalie ouverte, cooldown, joueur vivant) ;
		- prévient les clients pour qu'ils jouent leurs VFX (aucun effet visuel côté serveur).

	Prototype : une seule session globale. Pour plusieurs arènes simultanées,
	il suffira d'instancier un TimeLoopSession par combat.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)
local Remotes = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopRemotes)
local TimeLoopSession = require(script.Parent.TimeLoopSession)

-- État critique d'un joueur touché par une attaque fatale, en attente de rewind ou de mort.
type Anomaly = {
	humanoid: Humanoid,
	rootPart: BasePart,
	wasAnchored: boolean, -- état Anchored du RootPart avant le gel
}

local TimeLoopService = {}

local session = TimeLoopSession.new()
local anomalies: { [Player]: Anomaly } = {}
local lastRewindEndClock = -math.huge
local isStarted = false

--------------------------------------------------------------------------------
-- Anomalie temporelle
--------------------------------------------------------------------------------

-- La timeline est en pause tant qu'au moins une anomalie est ouverte.
local function refreshRecordingPause()
	session:setRecordingPaused(next(anomalies) ~= nil)
end

-- Ferme l'anomalie de `player` sans décider de l'issue : libère le personnage et prévient le client.
-- Sans effet si le joueur n'est pas en anomalie.
local function closeAnomaly(player: Player)
	local anomaly = anomalies[player]
	if anomaly == nil then
		return
	end

	anomalies[player] = nil
	refreshRecordingPause()

	anomaly.rootPart.Anchored = anomaly.wasAnchored
	Remotes.AnomalyClosed:FireClient(player)
end

-- Issue B : la fenêtre s'est écoulée sans rewind, le serveur applique la véritable mort.
local function onAnomalyExpired(player: Player, anomaly: Anomaly)
	-- Si ce n'est plus la même anomalie, elle a déjà été résolue (rewind, respawn, déconnexion).
	if anomalies[player] ~= anomaly then
		return
	end

	closeAnomaly(player)
	anomaly.humanoid.Health = 0

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Anomalie expirée : {player.Name} est mort`)
	end
end

--------------------------------------------------------------------------------
-- Inscription des entités
--------------------------------------------------------------------------------

local function onTaggedInstanceAdded(instance: Instance)
	-- Les tags suivent aussi les modèles rangés dans ServerStorage : on ne veut que ceux en jeu.
	if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
		session:addEntity(instance)
	end
end

local function onTaggedInstanceRemoved(instance: Instance)
	if instance:IsA("Model") then
		session:removeEntity(instance)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		session:addEntity(character)
	end)
	player.CharacterRemoving:Connect(function(character: Model)
		closeAnomaly(player)
		session:removeEntity(character)
	end)
	if player.Character then
		session:addEntity(player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	closeAnomaly(player)
end

--------------------------------------------------------------------------------
-- Validation et exécution du rewind
--------------------------------------------------------------------------------

local function canRewind(player: Player): (boolean, string)
	if session:isRewinding() then
		return false, "rewind déjà en cours"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false, "joueur mort ou sans personnage"
	end

	-- Une anomalie ouverte donne toujours le droit de rembobiner, cooldown ou non :
	-- le joueur ne doit pas mourir parce qu'il a rembobiné quelques secondes plus tôt.
	if anomalies[player] then
		return true, ""
	end

	if not Config.DEBUG_FREE_REWIND then
		return false, "aucune anomalie temporelle ouverte"
	end
	if os.clock() - lastRewindEndClock < Config.REWIND_COOLDOWN then
		return false, "cooldown"
	end

	return true, ""
end

local function onRewindRequested(player: Player)
	local isAllowed, reason = canRewind(player)
	if not isAllowed then
		if Config.DEBUG_LOGS then
			print(`[TimeLoop] Rewind refusé pour {player.Name} : {reason}`)
		end
		return
	end

	-- Issue A : le rewind annule l'attaque fatale pour toute la session, donc toutes les anomalies
	-- ouvertes se ferment. À faire AVANT session:rewind(), qui gèle lui-même les entités et
	-- mémorise leur état Anchored : il doit retrouver des personnages déjà libérés.
	for anomalyPlayer in anomalies do
		closeAnomaly(anomalyPlayer)
	end

	Remotes.RewindStarted:FireAllClients(Config.REWIND_PLAYBACK_DURATION)
	session:rewind(Config.REWIND_WINDOW, Config.REWIND_PLAYBACK_DURATION) -- yield
	lastRewindEndClock = os.clock()
	Remotes.RewindEnded:FireAllClients()

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Rewind terminé (déclenché par {player.Name})`)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function TimeLoopService.start()
	if isStarted then
		return
	end
	isStarted = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	CollectionService:GetInstanceAddedSignal(Config.ENTITY_TAG):Connect(onTaggedInstanceAdded)
	CollectionService:GetInstanceRemovedSignal(Config.ENTITY_TAG):Connect(onTaggedInstanceRemoved)
	for _, instance in CollectionService:GetTagged(Config.ENTITY_TAG) do
		onTaggedInstanceAdded(instance)
	end

	Remotes.RequestRewind.OnServerEvent:Connect(onRewindRequested)

	session:start()
end

--[[
	À appeler par le système de combat quand une attaque fatale touche `player`,
	À LA PLACE de lui retirer ses points de vie.

	Le personnage est figé et la timeline mise en pause pendant `duration` secondes
	(ANOMALY_WINDOW par défaut). Deux issues :
		A. le joueur demande un rewind à temps -> l'anomalie est annulée et le combat reprend 5 s plus tôt ;
		B. la fenêtre expire                   -> le serveur met ses PV à 0.

	Retourne false si l'anomalie n'a pas pu s'ouvrir (joueur déjà en anomalie, mort ou sans
	personnage, rewind en cours) : à l'appelant de décider quoi faire dans ce cas.
]]
function TimeLoopService.openAnomaly(player: Player, duration: number?): boolean
	if anomalies[player] or session:isRewinding() then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return false
	end

	local window = duration or Config.ANOMALY_WINDOW
	local anomaly: Anomaly = {
		humanoid = humanoid,
		rootPart = rootPart,
		wasAnchored = rootPart.Anchored,
	}
	anomalies[player] = anomaly

	-- Ancrage plutôt que WalkSpeed = 0 : il bloque aussi le saut et les poussées,
	-- et un client tricheur ne peut pas le contourner.
	rootPart.Anchored = true
	refreshRecordingPause()

	Remotes.AnomalyOpened:FireClient(player, window)
	task.delay(window, onAnomalyExpired, player, anomaly)

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Anomalie ouverte pour {player.Name} ({window} s)`)
	end
	return true
end

-- Le système de combat doit ignorer les actions et les dégâts d'un joueur en anomalie.
function TimeLoopService.isInAnomaly(player: Player): boolean
	return anomalies[player] ~= nil
end

function TimeLoopService.isRewinding(): boolean
	return session:isRewinding()
end

-- true si la timeline à laquelle appartient `player` est en train d'être rembobinée.
function TimeLoopService.isRewindingFor(_player: Player): boolean
	return session:isRewinding()
end

return TimeLoopService
