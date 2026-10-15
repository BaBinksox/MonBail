--!strict
--[[
	SpawnService
	Où apparaissent les personnages dans la Région 1 :
		- nouveau joueur : sur la scène du créateur (Sanctuaire des Âmes, ancre spawn_creator), JUSTE
		  avant que le Hub ne fige le personnage (crochet AvatarService.setStagePlacer) ; le client
		  reçoit CreatorStageReady pour cadrer la scène ;
		- à la validation du personnage : au belvédère (spawn_village), puis ArrivalCinematic (plan
		  d'arrivée cadrant le village et la cathédrale) ;
		- joueur qui a déjà un personnage : belvédère à la première apparition de la session ;
		- réapparition après une mort : bord de la place (spawn_plaza).
	Si la carte n'est pas construite (aucune ancre), rien n'est déplacé : les SpawnLocation de la
	place gardent leur rôle habituel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local SpawnRemotes = require(ReplicatedStorage.Shared.World.SpawnRemotes)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local CharacterPlacement = require(script.Parent.Parent.Core.CharacterPlacement)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local WorldAnchors = require(script.Parent.WorldAnchors)

local PROFILE_WAIT = 30 -- secondes d'attente du profil avant de décider où apparaître
local CAMERA_FALLBACK_OFFSET = Vector3.new(0, 18, 34) -- plan d'arrivée si l'ancre camera_overlook manque

local SpawnService = {}

local hasSpawnedInWorld: { [Player]: boolean } = {}
local isStarted = false

-- Charge la zone autour de `position` avant d'y déplacer un joueur (utile avec le streaming).
local function streamAround(player: Player, position: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(position)
	end)
end

-- Pose le personnage debout sur le sol réel sous l'ancre (proportions, vitesse et état du Humanoid
-- pris en compte : voir CharacterPlacement), après avoir chargé la zone chez le client.
local function placeCharacter(player: Player, character: Model, target: CFrame)
	streamAround(player, target.Position)
	if character.Parent then
		CharacterPlacement.place(character, target)
	end
end

-- Crochet du Hub : appelé par AvatarService juste avant de figer le personnage d'un nouveau joueur.
local function placeOnCreatorStage(player: Player, character: Model)
	local stage = WorldAnchors.getCFrame("spawn_creator")
	if stage == nil then
		return
	end
	placeCharacter(player, character, stage)
	SpawnRemotes.CreatorStageReady:FireClient(player, stage, WorldAnchors.getCFrame("camera_creator"))
end

-- Belvédère + plan d'arrivée (première création, ou première apparition de la session).
local function arriveAtOverlook(player: Player, withCinematic: boolean)
	local character = player.Character
	local spawn = WorldAnchors.getCFrame("spawn_village")
	if character == nil or spawn == nil then
		return
	end
	placeCharacter(player, character, spawn)
	hasSpawnedInWorld[player] = true
	if not withCinematic then
		return
	end
	local focus = RegionConfig.toWorld(RegionConfig.LAYOUT.plaza)
	local camera = WorldAnchors.getCFrame("camera_overlook")
		or CFrame.lookAt(spawn.Position + spawn:VectorToWorldSpace(CAMERA_FALLBACK_OFFSET), focus)
	local village = RegionConfig.getRegion("village")
	SpawnRemotes.ArrivalCinematic:FireClient(player, camera, focus, if village then village.name else "Le Village des Cendres")
end

local function onCharacterAdded(player: Player, character: Model)
	if ProfileStore.waitForProfile(player, PROFILE_WAIT) == nil or character.Parent == nil then
		return
	end
	task.wait() -- AvatarService finit de traiter le profil chargé dans la même frame
	if player.Character ~= character or AvatarService.isCustomizing(player) or not AvatarService.hasCharacter(player) then
		return -- nouveau joueur : la scène du créateur s'en charge (placeOnCreatorStage)
	end
	if not hasSpawnedInWorld[player] then
		arriveAtOverlook(player, false)
		return
	end
	local plaza = WorldAnchors.getCFrame("spawn_plaza")
	if plaza then
		placeCharacter(player, character, plaza)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

-- À appeler une seule fois au démarrage du serveur (avant AvatarService).
function SpawnService.start()
	if isStarted then
		return
	end
	isStarted = true

	AvatarService.setStagePlacer(placeOnCreatorStage)
	AvatarService.CreatorConfirmed:Connect(function(player: Player)
		arriveAtOverlook(player, true)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		hasSpawnedInWorld[player] = nil
	end)
end

return SpawnService
