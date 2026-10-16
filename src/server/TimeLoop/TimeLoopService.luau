--!strict
--[[
	TimeLoopService
	Façade serveur du Time-Loop (singleton). C'est le SEUL module que le reste du jeu doit appeler.

	PLUSIEURS TIMELINES (une TimeLoopSession chacune) :
		- une timeline PERSONNELLE par joueur : son seul personnage ;
		- une timeline par RENCONTRE (combat de boss, voir EncounterService) : le boss, ses alliés
		  éventuels, et les joueurs qui participent.
	Un joueur appartient à UNE timeline à la fois. Rembobiner ne touche que SA timeline : un joueur
	dans le village n'est plus ramené 5 s en arrière parce qu'un autre a rembobiné dans l'arène.

	RÈGLES DU REMBOBINAGE (R) :
		- pendant une ANOMALIE de sa rencontre : toujours permis (c'est le cœur du combat de boss) ;
		  il ferme les anomalies de cette rencontre et rembobine toute la rencontre ;
		- dans une rencontre, hors anomalie : refusé (sinon : frapper le boss, rembobiner ses PV,
		  garder sa Tension, recommencer) ;
		- hors rencontre : si un gestionnaire d'exploration (ancre temporelle proche, voir
		  setExplorationHandler) prend la main, c'est lui qui agit ; sinon, avec DEBUG_FREE_REWIND,
		  le joueur rembobine sa timeline personnelle (configuration de test) ;
		- jamais dans le Hub de création, jamais mort, cooldown par timeline.

	ANOMALIE : ouverte par le boss sur un joueur (openAnomaly). Une seule à la fois par rencontre
	(une demande concurrente est refusée). Son issue est publiée (AnomalyResolved, et
	GameEvents.AnomalyResolved pour les contrats) : "rewound", "expired" ou "cancelled".

	Le rembobinage ne touche JAMAIS aux données persistantes : seulement position, PV et attribut
	CombatState des entités de la timeline. Une entité morte n'est plus jamais modifiée.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)
local Remotes = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopRemotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local AnchorService = require(script.Parent.Parent.Core.AnchorService)
local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local TimeLoopSession = require(script.Parent.TimeLoopSession)

local ANOMALY_ANCHOR_REASON = "anomaly"
-- Attribut (boolean) d'un Model taggé ENTITY_TAG : false = jamais enregistré (ennemis ordinaires).
local REWINDABLE_ATTRIBUTE = "Rewindable"

export type Outcome = "rewound" | "expired" | "cancelled"

type Timeline = {
	id: string, -- "personal:<UserId>" ou l'identifiant de la rencontre
	session: TimeLoopSession.TimeLoopSession,
	isEncounter: boolean,
	players: { [Player]: boolean },
	lastRewindEndClock: number,
}

-- État critique d'un joueur touché par une attaque fatale, en attente de rewind ou de mort.
type Anomaly = {
	timeline: Timeline,
	humanoid: Humanoid,
	rootPart: BasePart,
}

local TimeLoopService = {}

-- AnomalyResolved(player, outcome: Outcome, rewoundBy: Player?, timelineId: string)
TimeLoopService.AnomalyResolved = Signal.new()
-- Rewound(timelineId: string, characters: { Model }, members: { Player }) : un rembobinage vient de
-- se terminer. Les états de combat qui ne sont pas enregistrés dans les instantanés (posture,
-- altérations) s'y remettent à zéro pour les personnages et joueurs concernés.
TimeLoopService.Rewound = Signal.new()

local timelines: { [string]: Timeline } = {}
local playerTimeline: { [Player]: Timeline } = {}
local anomalies: { [Player]: Anomaly } = {}
local lastOutcome: { [Player]: Outcome } = {}
local explorationHandler: ((player: Player) -> boolean)? = nil
local isStarted = false

--------------------------------------------------------------------------------
-- Timelines
--------------------------------------------------------------------------------

local function newTimeline(id: string, isEncounter: boolean): Timeline
	local timeline: Timeline = {
		id = id,
		session = TimeLoopSession.new(),
		isEncounter = isEncounter,
		players = {},
		lastRewindEndClock = -math.huge,
	}
	timelines[id] = timeline
	timeline.session:start()
	return timeline
end

local function getPersonalTimeline(player: Player): Timeline
	local id = `personal:{player.UserId}`
	return timelines[id] or newTimeline(id, false)
end

local function hasOpenAnomaly(timeline: Timeline): boolean
	for _, anomaly in anomalies do
		if anomaly.timeline == timeline then
			return true
		end
	end
	return false
end

-- La timeline est en pause tant qu'au moins une de ses anomalies est ouverte.
local function refreshRecordingPause(timeline: Timeline)
	timeline.session:setRecordingPaused(hasOpenAnomaly(timeline))
end

local function getTimelinePlayers(timeline: Timeline): { Player }
	local list = {}
	for player in timeline.players do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

-- Place `player` (et son personnage) dans `timeline`.
local function attachPlayer(player: Player, timeline: Timeline)
	local current = playerTimeline[player]
	if current == timeline then
		return
	end
	local character = player.Character
	if current then
		current.players[player] = nil
		if character then
			current.session:removeEntity(character)
		end
	end
	playerTimeline[player] = timeline
	timeline.players[player] = true
	if character then
		timeline.session:addEntity(character)
	end
end

--------------------------------------------------------------------------------
-- Anomalie temporelle
--------------------------------------------------------------------------------

-- Ferme l'anomalie de `player` et publie son issue. Sans effet si le joueur n'est pas en anomalie.
local function closeAnomaly(player: Player, outcome: Outcome, rewoundBy: Player?)
	local anomaly = anomalies[player]
	if anomaly == nil then
		return
	end

	anomalies[player] = nil
	lastOutcome[player] = outcome
	refreshRecordingPause(anomaly.timeline)
	AnchorService.release(anomaly.rootPart, ANOMALY_ANCHOR_REASON)
	if player.Parent == Players then
		Remotes.AnomalyClosed:FireClient(player)
	end

	TimeLoopService.AnomalyResolved:Fire(player, outcome, rewoundBy, anomaly.timeline.id)
	if anomaly.timeline.isEncounter then
		GameEvents.AnomalyResolved:Fire({
			encounterId = anomaly.timeline.id,
			target = player,
			participants = getTimelinePlayers(anomaly.timeline),
			outcome = outcome,
			rewoundBy = rewoundBy,
		})
	end
end

-- Issue B : la fenêtre s'est écoulée sans rewind, le serveur applique la véritable mort.
local function onAnomalyExpired(player: Player, anomaly: Anomaly)
	-- Si ce n'est plus la même anomalie, elle a déjà été résolue (rewind, respawn, déconnexion).
	if anomalies[player] ~= anomaly then
		return
	end

	closeAnomaly(player, "expired", nil)
	anomaly.humanoid.Health = 0

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Anomalie expirée : {player.Name} est mort`)
	end
end

--------------------------------------------------------------------------------
-- Joueurs et entités
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local timeline = getPersonalTimeline(player)
	playerTimeline[player] = timeline
	timeline.players[player] = true

	player.CharacterAdded:Connect(function(character: Model)
		local current = playerTimeline[player]
		if current then
			current.session:addEntity(character)
		end
	end)
	player.CharacterRemoving:Connect(function(character: Model)
		closeAnomaly(player, "cancelled", nil)
		local current = playerTimeline[player]
		if current then
			current.session:removeEntity(character)
		end
	end)
	if player.Character then
		timeline.session:addEntity(player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	closeAnomaly(player, "cancelled", nil)
	local current = playerTimeline[player]
	if current then
		current.players[player] = nil
		if player.Character then
			current.session:removeEntity(player.Character)
		end
	end
	playerTimeline[player] = nil
	lastOutcome[player] = nil

	local personal = timelines[`personal:{player.UserId}`]
	if personal then
		personal.session:stop()
		timelines[personal.id] = nil
	end
end

-- Les Models taggés ne sont plus enregistrés d'office (l'ancien prototype enregistrait tout le serveur) :
-- seuls ceux qu'une rencontre inscrit (le boss, via EncounterService) entrent dans une timeline.
-- Les ennemis ordinaires portent en plus Rewindable = false. Un Model qui perd le tag quitte toute timeline.
local function onTaggedInstanceRemoved(instance: Instance)
	if instance:IsA("Model") then
		for _, timeline in timelines do
			timeline.session:removeEntity(instance)
		end
	end
end

--------------------------------------------------------------------------------
-- Validation et exécution du rewind
--------------------------------------------------------------------------------

local function canRewind(player: Player, timeline: Timeline): (boolean, string)
	if timeline.session:isRewinding() then
		return false, "rewind déjà en cours"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false, "joueur mort ou sans personnage"
	end
	if AvatarService.isCustomizing(player) then
		return false, "joueur dans le Hub de création"
	end

	-- Une anomalie ouverte dans SA timeline donne toujours le droit de rembobiner, cooldown ou non :
	-- le joueur ne doit pas mourir parce qu'il a rembobiné quelques secondes plus tôt.
	if hasOpenAnomaly(timeline) then
		return true, ""
	end
	if timeline.isEncounter then
		return false, "rencontre en cours : le rembobinage n'est permis que pendant l'anomalie"
	end
	if not Config.DEBUG_FREE_REWIND then
		return false, "aucune anomalie temporelle ouverte"
	end
	if os.clock() - timeline.lastRewindEndClock < Config.REWIND_COOLDOWN then
		return false, "cooldown"
	end
	return true, ""
end

local function rewindTimeline(timeline: Timeline, requestedBy: Player)
	-- Issue A : le rewind annule l'attaque fatale pour toute la rencontre : ses anomalies se ferment.
	-- À faire AVANT session:rewind(), qui gèle lui-même les entités.
	for anomalyPlayer, anomaly in anomalies do
		if anomaly.timeline == timeline then
			closeAnomaly(anomalyPlayer, "rewound", requestedBy)
		end
	end

	local members = getTimelinePlayers(timeline)
	for _, member in members do
		Remotes.RewindStarted:FireClient(member, Config.REWIND_PLAYBACK_DURATION)
	end
	timeline.session:rewind(Config.REWIND_WINDOW, Config.REWIND_PLAYBACK_DURATION) -- yield
	timeline.lastRewindEndClock = os.clock()
	local finalMembers = getTimelinePlayers(timeline)
	for _, member in finalMembers do
		Remotes.RewindEnded:FireClient(member)
	end
	TimeLoopService.Rewound:Fire(timeline.id, timeline.session:getCharacters(), finalMembers)

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Rewind terminé sur {timeline.id} (déclenché par {requestedBy.Name}, {#members} joueur(s))`)
	end
end

local function onRewindRequested(player: Player)
	local timeline = playerTimeline[player]
	if timeline == nil then
		return
	end

	-- Hors rencontre et sans anomalie, une ancre temporelle proche a la priorité sur le rembobinage libre.
	if not timeline.isEncounter and not hasOpenAnomaly(timeline) and explorationHandler then
		local isHandled, handled = pcall(explorationHandler, player)
		if isHandled and handled then
			return
		end
	end

	local isAllowed, reason = canRewind(player, timeline)
	if not isAllowed then
		if Config.DEBUG_LOGS then
			print(`[TimeLoop] Rewind refusé pour {player.Name} : {reason}`)
		end
		return
	end
	rewindTimeline(timeline, player)
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

	CollectionService:GetInstanceRemovedSignal(Config.ENTITY_TAG):Connect(onTaggedInstanceRemoved)
	Remotes.RequestRewind.OnServerEvent:Connect(onRewindRequested)
end

--[[
	Crée (ou retrouve) la timeline d'une rencontre. Utilisé par EncounterService.
]]
function TimeLoopService.createEncounterTimeline(encounterId: string)
	if timelines[encounterId] == nil then
		newTimeline(encounterId, true)
	end
end

-- Détruit la timeline d'une rencontre (les joueurs encore dedans retournent à leur timeline personnelle).
function TimeLoopService.destroyEncounterTimeline(encounterId: string)
	local timeline = timelines[encounterId]
	if timeline == nil or not timeline.isEncounter then
		return
	end
	for player in timeline.players do
		closeAnomaly(player, "cancelled", nil)
		if player.Parent == Players then
			attachPlayer(player, getPersonalTimeline(player))
		end
	end
	timeline.session:stop()
	timelines[encounterId] = nil
end

-- Inscrit un PNJ (le boss) dans la timeline d'une rencontre.
function TimeLoopService.addEntityToEncounter(encounterId: string, model: Model)
	local timeline = timelines[encounterId]
	if timeline and model:GetAttribute(REWINDABLE_ATTRIBUTE) ~= false then
		timeline.session:addEntity(model)
	end
end

--[[
	Fait entrer `player` dans la timeline de la rencontre `encounterId`, ou le rend à sa timeline
	personnelle si `encounterId` est nil. Refusé (retourne false) pendant un rewind ou une anomalie
	de l'une ou l'autre timeline : on ne change pas de fil du temps en plein milieu.
]]
function TimeLoopService.setPlayerEncounter(player: Player, encounterId: string?): boolean
	local current = playerTimeline[player]
	local target = if encounterId then timelines[encounterId] else getPersonalTimeline(player)
	if target == nil or current == target then
		return current == target
	end
	if anomalies[player] or (current and (current.session:isRewinding() or hasOpenAnomaly(current) and current.isEncounter)) then
		return false
	end
	if target.session:isRewinding() then
		return false
	end
	attachPlayer(player, target)
	return true
end

-- Identifiant de la rencontre de `player`, ou nil s'il est dans sa timeline personnelle.
function TimeLoopService.getPlayerEncounter(player: Player): string?
	local timeline = playerTimeline[player]
	return if timeline and timeline.isEncounter then timeline.id else nil
end

--[[
	À appeler par le système de combat quand une attaque fatale touche `player`,
	À LA PLACE de lui retirer ses points de vie.

	Le personnage est figé et la timeline de sa rencontre mise en pause pendant `duration` secondes
	(ANOMALY_WINDOW par défaut). Deux issues :
		A. un participant demande un rewind à temps -> l'anomalie est annulée, la rencontre reprend 5 s plus tôt ;
		B. la fenêtre expire                         -> le serveur met ses PV à 0.

	Retourne false si l'anomalie n'a pas pu s'ouvrir (joueur déjà en anomalie, AUTRE anomalie déjà
	ouverte dans la même rencontre, joueur mort ou sans personnage, rewind en cours).
]]
function TimeLoopService.openAnomaly(player: Player, duration: number?): boolean
	local timeline = playerTimeline[player]
	if timeline == nil or anomalies[player] or timeline.session:isRewinding() or hasOpenAnomaly(timeline) then
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
		timeline = timeline,
		humanoid = humanoid,
		rootPart = rootPart,
	}
	anomalies[player] = anomaly
	lastOutcome[player] = nil

	-- Ancrage plutôt que WalkSpeed = 0 : il bloque aussi le saut et les poussées,
	-- et un client tricheur ne peut pas le contourner. Compté : le rewind ne le défait pas.
	AnchorService.hold(rootPart, ANOMALY_ANCHOR_REASON)
	refreshRecordingPause(timeline)

	Remotes.AnomalyOpened:FireClient(player, window)
	task.delay(window, onAnomalyExpired, player, anomaly)

	if Config.DEBUG_LOGS then
		print(`[TimeLoop] Anomalie ouverte pour {player.Name} ({window} s, {timeline.id})`)
	end
	return true
end

-- Attend la fin de l'anomalie de `player` et retourne son issue. YIELD. (Remplace la devinette par
-- sondage de l'ancien BossService : l'issue est enregistrée au moment même de la fermeture.)
function TimeLoopService.waitForAnomalyOutcome(player: Player): Outcome
	while anomalies[player] do
		task.wait(0.05)
	end
	return lastOutcome[player] or "cancelled"
end

-- Le système de combat doit ignorer les actions et les dégâts d'un joueur en anomalie.
function TimeLoopService.isInAnomaly(player: Player): boolean
	return anomalies[player] ~= nil
end

-- true si AU MOINS une timeline est en train d'être rembobinée (compatibilité avec l'ancien code).
function TimeLoopService.isRewinding(): boolean
	for _, timeline in timelines do
		if timeline.session:isRewinding() then
			return true
		end
	end
	return false
end

-- true si la timeline à laquelle appartient `player` est en train d'être rembobinée.
function TimeLoopService.isRewindingFor(player: Player): boolean
	local timeline = playerTimeline[player]
	return timeline ~= nil and timeline.session:isRewinding()
end

-- true si la timeline de la rencontre `encounterId` est en train d'être rembobinée.
function TimeLoopService.isEncounterRewinding(encounterId: string): boolean
	local timeline = timelines[encounterId]
	return timeline ~= nil and timeline.session:isRewinding()
end

--[[
	Enregistre le gestionnaire d'exploration : appelé quand un joueur HORS rencontre et sans anomalie
	appuie sur R. S'il retourne true (une ancre temporelle proche a agi), le rembobinage libre n'a
	pas lieu. Utilisé par MechanismService (ancres temporelles). Ne doit pas yield longtemps.
]]
function TimeLoopService.setExplorationHandler(handler: (player: Player) -> boolean)
	explorationHandler = handler
end

return TimeLoopService
