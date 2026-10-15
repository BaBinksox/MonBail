--!strict
--[[
	EncounterService
	Les RENCONTRES de boss : qui participe, dans quelle timeline, et qui voit la phase d'anomalie.

	Une rencontre = un boss + une zone (le volume volume_boss_arena de la carte si le boss en est le
	gardien, sinon un cercle autour de son point d'apparition). Toutes les ENCOUNTER_POLL secondes :
		- un joueur vivant (hors Hub) qui entre dans la zone devient PARTICIPANT : son personnage passe
		  dans la timeline de la rencontre (TimeLoopService) ;
		- un participant qui s'éloigne au-delà de la zone + LEAVE_MARGIN retourne à sa timeline
		  personnelle (sauf pendant un rewind ou une anomalie : il est retenu jusqu'à la fin).
	Le boss ne cible QUE les participants : impossible d'ouvrir une anomalie sur un joueur qui
	n'est pas dans la même timeline que lui.

	Humeur d'anomalie : au lieu de rougir le ciel du serveur entier, setAnomalyMood pose l'attribut
	"EncounterMood" = "Anomaly" sur les seuls participants ; leur client (WorldAtmosphere) bascule.

	Attributs posés sur le Player : "EncounterId" (string) pendant la participation, "EncounterMood".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.World.WorldConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)
local WorldAnchors = require(script.Parent.Parent.World.WorldAnchors)

local ENCOUNTER_POLL = 0.5 -- secondes
local DEFAULT_RADIUS = 70 -- studs autour du point d'apparition du boss
local ARENA_MARGIN = 18 -- studs ajoutés au volume de l'arène
local LEAVE_MARGIN = 15 -- studs au-delà de la zone avant de quitter la rencontre (pas d'aller-retour au bord)
local ARENA_ANCHOR = "volume_boss_arena"

local ENCOUNTER_ATTRIBUTE = "EncounterId"
local MOOD_ATTRIBUTE = "EncounterMood"

type Encounter = {
	id: string,
	boss: Model,
	center: Vector3,
	radius: number,
	participants: { [Player]: boolean },
	isAnomalyMood: boolean,
}

local EncounterService = {}

local encounters: { [string]: Encounter } = {}
local encounterByBoss: { [Model]: Encounter } = {}
local isStarted = false
local nextIndex = 0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getRootPosition(player: Player): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil
	end
	return rootPart.Position
end

local function flatDistance(a: Vector3, b: Vector3): number
	return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

local function setMoodAttribute(player: Player, isAnomaly: boolean)
	player:SetAttribute(MOOD_ATTRIBUTE, if isAnomaly then WorldConfig.MOODS.Anomaly else nil)
end

local function join(encounter: Encounter, player: Player)
	if TimeLoopService.setPlayerEncounter(player, encounter.id) then
		encounter.participants[player] = true
		player:SetAttribute(ENCOUNTER_ATTRIBUTE, encounter.id)
		setMoodAttribute(player, encounter.isAnomalyMood)
	end
end

local function leave(encounter: Encounter, player: Player, force: boolean?)
	if force or TimeLoopService.setPlayerEncounter(player, nil) then
		encounter.participants[player] = nil
		if player.Parent == Players then
			player:SetAttribute(ENCOUNTER_ATTRIBUTE, nil)
			setMoodAttribute(player, false)
		end
	end
end

-- Zone de la rencontre : l'arène de la carte si le boss y est, sinon un cercle autour de lui.
local function computeZone(home: Vector3): (Vector3, number)
	local arena = WorldAnchors.get(ARENA_ANCHOR)
	if arena then
		local arenaRadius = math.max(arena.Size.X, arena.Size.Z) / 2
		if flatDistance(arena.Position, home) <= arenaRadius then
			return arena.Position, arenaRadius + ARENA_MARGIN
		end
	end
	return home, DEFAULT_RADIUS
end

local function updateEncounter(encounter: Encounter)
	if encounter.boss.Parent == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		local position = getRootPosition(player)
		local isParticipant = encounter.participants[player] == true
		if position == nil or AvatarService.isCustomizing(player) then
			if isParticipant and position == nil then
				leave(encounter, player) -- mort : il réapparaîtra loin, dans sa timeline personnelle
			end
			continue
		end
		local distance = flatDistance(position, encounter.center)
		if not isParticipant and distance <= encounter.radius then
			-- Un joueur ne participe qu'à une rencontre à la fois.
			if TimeLoopService.getPlayerEncounter(player) == nil then
				join(encounter, player)
			end
		elseif isParticipant and distance > encounter.radius + LEAVE_MARGIN then
			leave(encounter, player)
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Crée la rencontre du boss `boss` (appelé par BossService à l'inscription). Retourne son identifiant.
function EncounterService.registerBoss(boss: Model, home: Vector3): string
	local existing = encounterByBoss[boss]
	if existing then
		return existing.id
	end
	nextIndex += 1
	local id = `encounter:{boss.Name}:{nextIndex}`
	local center, radius = computeZone(home)
	local encounter: Encounter = {
		id = id,
		boss = boss,
		center = center,
		radius = radius,
		participants = {},
		isAnomalyMood = false,
	}
	encounters[id] = encounter
	encounterByBoss[boss] = encounter
	TimeLoopService.createEncounterTimeline(id)
	TimeLoopService.addEntityToEncounter(id, boss)
	return id
end

-- Termine la rencontre du boss (mort définitive, retrait du tag). Les participants retrouvent leur timeline.
function EncounterService.unregisterBoss(boss: Model)
	local encounter = encounterByBoss[boss]
	if encounter == nil then
		return
	end
	encounterByBoss[boss] = nil
	encounters[encounter.id] = nil
	for player in encounter.participants do
		leave(encounter, player, true)
	end
	TimeLoopService.destroyEncounterTimeline(encounter.id)
end

function EncounterService.getEncounterId(boss: Model): string?
	local encounter = encounterByBoss[boss]
	return encounter and encounter.id
end

-- Participants actuels (vivants ou non) de la rencontre du boss.
function EncounterService.getParticipants(boss: Model): { Player }
	local list = {}
	local encounter = encounterByBoss[boss]
	if encounter then
		for player in encounter.participants do
			if player.Parent == Players then
				table.insert(list, player)
			end
		end
	end
	return list
end

function EncounterService.isParticipant(boss: Model, player: Player): boolean
	local encounter = encounterByBoss[boss]
	return encounter ~= nil and encounter.participants[player] == true
end

-- Bascule l'ambiance d'anomalie chez les participants de la rencontre du boss (et ceux qui la rejoignent).
function EncounterService.setAnomalyMood(boss: Model, isActive: boolean)
	local encounter = encounterByBoss[boss]
	if encounter == nil then
		return
	end
	encounter.isAnomalyMood = isActive
	for player in encounter.participants do
		if player.Parent == Players then
			setMoodAttribute(player, isActive)
		end
	end
end

-- À appeler une seule fois au démarrage du serveur (après TimeLoopService).
function EncounterService.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		while true do
			task.wait(ENCOUNTER_POLL)
			for _, encounter in encounters do
				local isUpdated, message = pcall(function()
					updateEncounter(encounter)
				end)
				if not isUpdated then
					warn(`[Encounter] {encounter.id} : {message}`)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, encounter in encounters do
			encounter.participants[player] = nil
		end
	end)
end

return EncounterService
