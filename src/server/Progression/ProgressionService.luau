--!strict
--[[
	ProgressionService
	Expérience et rang d'aventurier (règles dans Shared/Progression/RankConfig).

	- addXp(player, amount) : seul RewardService l'appelle (les autres passent par une récompense) ;
	- checkPromotion(player) : vérifie les conditions du rang suivant (XP, quêtes, missions de
	  validation, découvertes) et promeut, un rang à la fois, tant que c'est possible. Appelé après
	  chaque gain ; idempotent ;
	- publie le rang dans l'attribut RankConfig.RANK_ATTRIBUTE du Player (visible par tous) ;
	- fournit à StateSync la tranche "progression" enrichie (rang, prochain rang, conditions remplies).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RankConfig = require(ReplicatedStorage.Shared.Progression.RankConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local StateSync = require(script.Parent.Parent.State.StateSync)

type Profile = PlayerData.Profile

export type Requirement = {
	kind: "xp" | "quest" | "mission" | "discoveries",
	id: string?, -- quête / mission concernée
	label: string,
	current: number,
	target: number,
	done: boolean,
}

local ProgressionService = {}

-- Promoted(player, newRankId: string, oldRankId: string)
ProgressionService.Promoted = Signal.new()

local isStarted = false

--------------------------------------------------------------------------------
-- Conditions de rang
--------------------------------------------------------------------------------

-- Liste des conditions du rang `rank` pour ce profil, avec leur avancement.
local function getRequirements(profile: Profile, rank: RankConfig.Rank): { Requirement }
	local requirements: { Requirement } = {}
	table.insert(requirements, {
		kind = "xp",
		label = "Expérience",
		current = profile.progression.xp,
		target = rank.xp,
		done = profile.progression.xp >= rank.xp,
	})
	if rank.quests then
		for _, questId in rank.quests do
			local isDone = profile.quests.completed[questId] ~= nil
			table.insert(requirements, { kind = "quest", id = questId, label = questId, current = if isDone then 1 else 0, target = 1, done = isDone })
		end
	end
	if rank.missions then
		for _, missionId in rank.missions do
			local count = profile.missions.completions[missionId] or 0
			table.insert(requirements, { kind = "mission", id = missionId, label = missionId, current = math.min(count, 1), target = 1, done = count >= 1 })
		end
	end
	if rank.discoveries then
		local have = PlayerData.countDiscoveries(profile)
		table.insert(requirements, { kind = "discoveries", label = "Découvertes", current = have, target = rank.discoveries, done = have >= rank.discoveries })
	end
	return requirements
end

local function areMet(requirements: { Requirement }): boolean
	for _, requirement in requirements do
		if not requirement.done then
			return false
		end
	end
	return true
end

local function publishRank(player: Player, profile: Profile)
	player:SetAttribute(RankConfig.RANK_ATTRIBUTE, RankConfig.getRank(profile.progression.rank).id)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function ProgressionService.addXp(player: Player, amount: number)
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return
	end
	PlayerData.mutate(player, "progression", function(profile)
		profile.progression.xp += math.floor(amount)
	end)
	ProgressionService.checkPromotion(player)
end

-- Promeut `player` autant de rangs que ses conditions le permettent. Retourne le nombre de promotions.
function ProgressionService.checkPromotion(player: Player): number
	local promotions = 0
	while true do
		local profile = PlayerData.get(player)
		if profile == nil then
			return promotions
		end
		local nextRank = RankConfig.getNextRank(profile.progression.rank)
		if nextRank == nil or nextRank.comingSoon or not areMet(getRequirements(profile, nextRank)) then
			return promotions
		end

		local oldRankId = profile.progression.rank
		PlayerData.mutate(player, "progression", function(p)
			p.progression.rank = nextRank.id
			p.progression.promotions[nextRank.id] = os.time()
		end)
		promotions += 1
		publishRank(player, profile)
		StateSync.notify(player, "promotion", { rank = nextRank.id, name = nextRank.name, perk = nextRank.perk })
		ProgressionService.Promoted:Fire(player, nextRank.id, oldRankId)
		PlayerData.saveSoon(player)
	end
end

function ProgressionService.getRankId(player: Player): string
	local profile = PlayerData.get(player)
	return if profile then RankConfig.getRank(profile.progression.rank).id else RankConfig.DEFAULT_RANK
end

function ProgressionService.isAtLeast(player: Player, minRankId: string?): boolean
	return RankConfig.isAtLeast(ProgressionService.getRankId(player), minRankId)
end

-- À appeler une seule fois au démarrage du serveur (après StateSync).
function ProgressionService.start()
	if isStarted then
		return
	end
	isStarted = true

	StateSync.register("progression", function(player: Player): any
		local profile = PlayerData.get(player)
		if profile == nil then
			return nil
		end
		local rank = RankConfig.getRank(profile.progression.rank)
		local nextRank = RankConfig.getNextRank(rank.id)
		return {
			xp = profile.progression.xp,
			reputation = profile.progression.reputation,
			rank = rank.id,
			discoveries = PlayerData.countDiscoveries(profile),
			nextRank = if nextRank
				then {
					id = nextRank.id,
					comingSoon = nextRank.comingSoon == true,
					requirements = getRequirements(profile, nextRank),
				}
				else nil,
		}
	end)

	ProfileStore.ProfileLoaded:Connect(function(player: Player, profile: Profile)
		publishRank(player, profile)
		ProgressionService.checkPromotion(player) -- règles de rang modifiées depuis la dernière visite
	end)
	ProfileStore.ProfileRefreshed:Connect(function(player: Player, profile: Profile)
		publishRank(player, profile)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		player:SetAttribute(RankConfig.RANK_ATTRIBUTE, nil)
	end)
end

return ProgressionService
