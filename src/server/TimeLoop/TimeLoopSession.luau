--!strict
--[[
	TimeLoopSession
	Une "timeline" partagée par un groupe d'entités (ex. : un combat de boss = 1 session).
	Deux responsabilités :
		1. Data Logger : un snapshot de chaque entité tous les RECORD_INTERVAL.
		2. Rewind     : relecture inversée de ces snapshots, pour toutes les entités en même temps.

	Le temps est mesuré en "temps de timeline" : il avance pendant l'enregistrement et recule
	pendant un rewind. Après un rewind de 5 s, la timeline reprend donc 5 s plus tôt et
	l'historique reste cohérent (on peut rembobiner plusieurs fois de suite).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)
local AnchorService = require(script.Parent.Parent.Core.AnchorService)
local EntitySnapshot = require(script.Parent.EntitySnapshot)

local REWIND_ANCHOR_REASON = "rewind"
local SnapshotBuffer = require(script.Parent.SnapshotBuffer)

type Snapshot = EntitySnapshot.Snapshot
type Buffer = SnapshotBuffer.SnapshotBuffer

-- +2 : marge pour les snapshots hors cadence pris au début et à la fin d'un rewind.
local BUFFER_CAPACITY = math.ceil(Config.BUFFER_DURATION / Config.RECORD_INTERVAL) + 2

type Entity = {
	character: Model,
	buffer: Buffer,
	isNpc: boolean,
	frozenRoot: BasePart?, -- RootPart figé pendant le rewind (ancrage compté, voir AnchorService)
}

local TimeLoopSession = {}
TimeLoopSession.__index = TimeLoopSession

type SessionData = {
	_entities: { [Model]: Entity },
	_timelineTime: number,
	_recordAccumulator: number,
	_isRewinding: boolean,
	_isRecordingPaused: boolean,
	_heartbeatConnection: RBXScriptConnection?,
}

export type TimeLoopSession = typeof(setmetatable({} :: SessionData, TimeLoopSession))

--------------------------------------------------------------------------------
-- Helpers par entité
--------------------------------------------------------------------------------

-- Un PNJ doit être simulé par le serveur, sinon sa physique peut être confiée au client le plus proche.
local function claimServerOwnership(entity: Entity)
	if not entity.isNpc then
		return
	end
	local _, rootPart = EntitySnapshot.getParts(entity.character)
	if rootPart and rootPart:CanSetNetworkOwnership() then
		rootPart:SetNetworkOwner(nil)
	end
end

-- Gèle l'entité : un RootPart ancré n'est plus simulé par son propriétaire réseau,
-- le serveur devient donc seul maître de son CFrame pendant la lecture inversée.
-- L'ancrage est COMPTÉ (AnchorService) : le Hub, l'anomalie ou la charge du boss qui figent le même
-- personnage ne sont ni annulés ni prolongés par le rewind.
local function freeze(entity: Entity)
	local _, rootPart = EntitySnapshot.getParts(entity.character)
	if rootPart and not EntitySnapshot.isDead(entity.character) then
		AnchorService.hold(rootPart, REWIND_ANCHOR_REASON)
		entity.frozenRoot = rootPart
	end
end

local function unfreeze(entity: Entity)
	local rootPart = entity.frozenRoot
	entity.frozenRoot = nil
	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		AnchorService.release(rootPart, REWIND_ANCHOR_REASON)
	end
	claimServerOwnership(entity)
end

-- Place l'entité à l'instant `cursor` de la timeline.
-- Les snapshots plus récents que le curseur sont dépilés au passage : c'est la lecture à l'envers.
local function scrub(entity: Entity, cursor: number)
	local buffer = entity.buffer

	-- Tant que l'avant-dernier snapshot est lui aussi "dans le futur" du curseur, le dernier est inutile.
	while true do
		local previous = buffer:peek(1)
		if previous == nil or previous.timestamp < cursor then
			break
		end
		buffer:popNewest()
	end

	local newer = buffer:peek(0)
	if newer == nil then
		return
	end

	-- Le curseur est maintenant encadré : older.timestamp < cursor <= newer.timestamp
	-- (ou bien il ne reste qu'un snapshot, et l'entité y reste figée).
	local older = buffer:peek(1) or newer
	local span = newer.timestamp - older.timestamp
	local alpha = if span > 0 then math.clamp((newer.timestamp - cursor) / span, 0, 1) else 0

	EntitySnapshot.applyInterpolated(entity.character, newer, older, alpha)
end

-- Fin de rewind : purge ce qui reste du "futur annulé" et applique l'état discret d'arrivée.
local function land(entity: Entity, targetTime: number)
	local buffer = entity.buffer
	local landing: Snapshot? = nil

	while true do
		local newest = buffer:peek(0)
		if newest == nil then
			break
		end
		landing = newest
		if newest.timestamp <= targetTime then
			break
		end
		buffer:popNewest()
	end

	if landing then
		EntitySnapshot.applyDiscreteState(entity.character, landing)
	end
end

--------------------------------------------------------------------------------
-- Helpers de session
--------------------------------------------------------------------------------

local function captureAll(self: TimeLoopSession)
	for character, entity in self._entities do
		if character.Parent == nil or (EntitySnapshot.isDead(character) and character:FindFirstChildOfClass("Humanoid") ~= nil) then
			-- Mort ou détruit : il quitte la timeline (son historique figé fausserait les rewinds suivants).
			if not self._isRewinding then
				self._entities[character] = nil
			end
			continue
		end
		local snapshot = EntitySnapshot.capture(entity.character, self._timelineTime)
		if snapshot then
			entity.buffer:push(snapshot)
		end
	end
end

-- Instant le plus ancien encore connu d'au moins une entité (borne basse d'un rewind).
local function getOldestTimestamp(self: TimeLoopSession): number
	local oldestTimestamp = self._timelineTime
	for _, entity in self._entities do
		local oldest = entity.buffer:peekOldest()
		if oldest then
			oldestTimestamp = math.min(oldestTimestamp, oldest.timestamp)
		end
	end
	return oldestTimestamp
end

local function onHeartbeat(self: TimeLoopSession, deltaTime: number)
	if self._isRewinding or self._isRecordingPaused then
		return
	end

	self._timelineTime += deltaTime
	self._recordAccumulator += deltaTime

	if self._recordAccumulator >= Config.RECORD_INTERVAL then
		-- Modulo plutôt que soustraction : après un gros lag on prend 1 snapshot, pas une rafale.
		self._recordAccumulator %= Config.RECORD_INTERVAL
		captureAll(self)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function TimeLoopSession.new(): TimeLoopSession
	local data: SessionData = {
		_entities = {},
		_timelineTime = 0,
		_recordAccumulator = 0,
		_isRewinding = false,
		_isRecordingPaused = false,
		_heartbeatConnection = nil,
	}
	return setmetatable(data, TimeLoopSession)
end

-- Démarre l'enregistrement.
function TimeLoopSession.start(self: TimeLoopSession)
	if self._heartbeatConnection then
		return
	end
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		onHeartbeat(self, deltaTime)
	end)
end

function TimeLoopSession.stop(self: TimeLoopSession)
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
end

-- Ajoute un personnage (joueur ou PNJ) à la timeline. Le Model peut être encore incomplet :
-- il sera simplement ignoré par le logger tant qu'il n'a pas de Humanoid + RootPart.
function TimeLoopSession.addEntity(self: TimeLoopSession, character: Model)
	if self._entities[character] then
		return
	end

	local entity: Entity = {
		character = character,
		buffer = SnapshotBuffer.new(BUFFER_CAPACITY),
		isNpc = Players:GetPlayerFromCharacter(character) == nil,
		frozenRoot = nil,
	}
	self._entities[character] = entity
	claimServerOwnership(entity)
end

function TimeLoopSession.removeEntity(self: TimeLoopSession, character: Model)
	local entity = self._entities[character]
	if entity == nil then
		return
	end
	if self._isRewinding then
		unfreeze(entity)
	end
	self._entities[character] = nil
end

function TimeLoopSession.isRewinding(self: TimeLoopSession): boolean
	return self._isRewinding
end

function TimeLoopSession.hasEntity(self: TimeLoopSession, character: Model): boolean
	return self._entities[character] ~= nil
end

-- Personnages actuellement enregistrés (joueurs et PNJ).
function TimeLoopSession.getCharacters(self: TimeLoopSession): { Model }
	local characters = {}
	for character in self._entities do
		table.insert(characters, character)
	end
	return characters
end

-- Arrête / reprend l'horloge de la timeline (et donc l'enregistrement).
-- Utilisé pendant une anomalie : sans cette pause, les secondes passées figé seraient enregistrées
-- et un rewind de 5 s ne ramènerait le joueur qu'à 1 s avant l'attaque fatale.
function TimeLoopSession.setRecordingPaused(self: TimeLoopSession, isPaused: boolean)
	self._isRecordingPaused = isPaused
end

--[[
	Rembobine toutes les entités de `window` secondes de timeline, en `playbackDuration` secondes réelles.
	YIELD jusqu'à la fin de la lecture. Retourne false si un rewind est déjà en cours.

	S'il y a moins de `window` secondes d'historique, on remonte aussi loin que possible
	à la même vitesse (la lecture est alors plus courte).
]]
function TimeLoopSession.rewind(self: TimeLoopSession, window: number, playbackDuration: number): boolean
	if self._isRewinding then
		return false
	end
	self._isRewinding = true -- suspend aussi l'enregistrement (voir onHeartbeat)

	-- 1. Snapshot de l'instant présent, pour que la lecture parte exactement de la pose actuelle.
	captureAll(self)
	for _, entity in self._entities do
		freeze(entity)
	end

	-- 2. Lecture inversée : un curseur recule sur la timeline à vitesse constante.
	local startTime = self._timelineTime
	local targetTime = math.max(startTime - window, getOldestTimestamp(self))
	local speed = window / playbackDuration
	local cursor = startTime

	while cursor > targetTime do
		local deltaTime = RunService.Heartbeat:Wait()
		cursor = math.max(cursor - deltaTime * speed, targetTime)
		for _, entity in self._entities do
			scrub(entity, cursor)
		end
	end

	-- 3. Atterrissage : la timeline reprend à targetTime.
	self._timelineTime = targetTime
	self._recordAccumulator = 0
	for _, entity in self._entities do
		land(entity, targetTime)
		unfreeze(entity)
	end
	captureAll(self)

	self._isRewinding = false
	return true
end

return TimeLoopSession
