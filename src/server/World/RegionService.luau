--!strict
--[[
	RegionService
	Où se trouve chaque joueur dans la Région 1, et qui a le droit de passer quelles portes.

	- Toutes les POLL_INTERVAL s : région courante (RegionConfig.regionAt) publiée dans l'attribut
	  Player "Region" (lu par le client pour l'ambiance et le titre de lieu). À chaque entrée :
	  GameEvents.RegionEntered (objectifs "explore" des quêtes) et, la première fois, la découverte
	  de la région (RewardService.discover).
	- canPassGate(player, gateId) : conditions d'une porte (RegionConfig.GATES : rang minimal, quêtes
	  terminées, déblocages, niveau de guilde). Vérifiées par le SERVEUR quand le joueur interagit avec
	  la porte (InteractionService) ; le client n'affiche que le résultat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RankConfig = require(ReplicatedStorage.Shared.Progression.RankConfig)
local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local RewardService = require(script.Parent.Parent.Progression.RewardService)

local POLL_INTERVAL = 0.5
local REGION_ATTRIBUTE = "Region"

local RegionService = {}

local currentRegion: { [Player]: string } = {}
local guildLevelProvider: ((player: Player) -> number?)? = nil
local isStarted = false

local function updatePlayer(player: Player)
	-- Pas avant le chargement du profil : la découverte de la première région serait perdue.
	if PlayerData.get(player) == nil then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end
	local region = RegionConfig.regionAt(rootPart.Position)
	local regionId = region and region.id
	if regionId == currentRegion[player] then
		return
	end
	currentRegion[player] = regionId :: any
	player:SetAttribute(REGION_ATTRIBUTE, regionId)
	if region then
		GameEvents.RegionEntered:Fire(player, region.id)
		if region.discoveryId then
			RewardService.discover(player, region.discoveryId)
		end
	end
end

-- Région courante de `player` (id de RegionConfig.REGIONS), ou nil hors de la Région 1.
function RegionService.getRegion(player: Player): string?
	return currentRegion[player]
end

-- Le niveau de guilde est fourni par GuildService (branché au démarrage) : RegionService n'en dépend pas.
function RegionService.setGuildLevelProvider(provider: (player: Player) -> number?)
	guildLevelProvider = provider
end

--[[
	Le joueur peut-il franchir la porte `gateId` ? Retourne (autorisé, texte à afficher).
	Le texte est celui de la porte (lockedText / openText) : le client ne connaît pas les conditions.
]]
function RegionService.canPassGate(player: Player, gateId: string): (boolean, string)
	local gate = RegionConfig.GATES[gateId]
	if gate == nil then
		return false, "Ce passage ne mène nulle part."
	end
	local profile = PlayerData.get(player)
	if profile == nil then
		return false, "Votre progression n'est pas encore chargée."
	end
	if gate.minRank and not RankConfig.isAtLeast(profile.progression.rank, gate.minRank) then
		return false, gate.lockedText
	end
	if gate.quests then
		for _, questId in gate.quests do
			if profile.quests.completed[questId] == nil then
				return false, gate.lockedText
			end
		end
	end
	if gate.unlocks then
		for _, unlockId in gate.unlocks do
			if profile.unlocks[unlockId] == nil then
				return false, gate.lockedText
			end
		end
	end
	if gate.guildLevel then
		local level = if guildLevelProvider then guildLevelProvider(player) else nil
		if level == nil or level < gate.guildLevel then
			return false, gate.lockedText
		end
	end
	return true, gate.openText or gate.name
end

-- À appeler une seule fois au démarrage du serveur.
function RegionService.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			for _, player in Players:GetPlayers() do
				local isUpdated, message = pcall(function()
					updatePlayer(player)
				end)
				if not isUpdated then
					warn(`[Region] {player.Name} : {message}`)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		currentRegion[player] = nil
	end)
end

return RegionService
