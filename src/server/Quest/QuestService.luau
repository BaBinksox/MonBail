--!strict
--[[
	QuestService
	Moteur de quêtes : exécute les définitions de Shared/Quest/QuestDefinitions.

	- Progression : écoute le bus GameEvents (PNJ, objets, régions, échos, puzzles, éliminations,
	  objets obtenus) et fait avancer les objectifs de l'étape EN COURS des quêtes actives du joueur.
	  Le client n'envoie jamais "j'ai fini l'objectif" : seuls des faits validés par le serveur comptent.
	- Une étape est finie quand tous ses objectifs sont atteints ; un objectif "talk" d'une étape qui
	  en a d'autres ne compte qu'en DERNIER (on revient voir le PNJ une fois le reste accompli).
	- Fin de quête : profile.quests.completed[id], puis RewardService.grant(player, "quest:<id>", ...) :
	  la récompense ne peut être versée qu'une fois, même après une reconnexion ou une double requête.
	- Dialogues : getNpcDialogue(player, npcId) choisit ce que dit un PNJ selon les quêtes du joueur
	  (proposition, étape en cours, après la quête). Utilisé par DialogueService.
	- État client : tranche StateSync "quests" (actives avec étape et progression, terminées, disponibles).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestDefinitions = require(ReplicatedStorage.Shared.Quest.QuestDefinitions)
local RankConfig = require(ReplicatedStorage.Shared.Progression.RankConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local StateSync = require(script.Parent.Parent.State.StateSync)

type Quest = QuestDefinitions.Quest
type Stage = QuestDefinitions.Stage
type Objective = QuestDefinitions.Objective
type Profile = PlayerData.Profile

export type QuestState = "locked" | "available" | "active" | "completed"

export type DialogueOption = { id: string, label: string }
export type NpcDialogue = { lines: { string }, options: { DialogueOption }? }

-- Types d'objectifs que fait avancer une utilisation d'objet interactif.
local INTERACTABLE_TYPES = { examine = true, interact = true, collect = true }

local QuestService = {}

-- QuestCompleted(player, questId)
QuestService.QuestCompleted = Signal.new()
-- StageAdvanced(player, questId, newStageIndex)
QuestService.StageAdvanced = Signal.new()

local isStarted = false

--------------------------------------------------------------------------------
-- Lecture de l'état
--------------------------------------------------------------------------------

local function arePrerequisitesMet(profile: Profile, quest: Quest): boolean
	local prerequisites = quest.prerequisites
	if not RankConfig.isAtLeast(profile.progression.rank, prerequisites.minRank) then
		return false
	end
	if prerequisites.quests then
		for _, questId in prerequisites.quests do
			if profile.quests.completed[questId] == nil then
				return false
			end
		end
	end
	if prerequisites.unlocks then
		for _, unlockId in prerequisites.unlocks do
			if profile.unlocks[unlockId] == nil then
				return false
			end
		end
	end
	return true
end

local function getStateFromProfile(profile: Profile, quest: Quest): QuestState
	if profile.quests.completed[quest.id] then
		return "completed"
	end
	if profile.quests.active[quest.id] then
		return "active"
	end
	return if arePrerequisitesMet(profile, quest) then "available" else "locked"
end

local function isObjectiveComplete(entry: { progress: { [string]: number } }, objective: Objective): boolean
	return (entry.progress[objective.id] or 0) >= objective.count
end

-- Un objectif "talk" ne compte qu'une fois les AUTRES objectifs de l'étape atteints.
local function isObjectiveCreditable(entry: { progress: { [string]: number } }, stage: Stage, objective: Objective): boolean
	if objective.type ~= "talk" then
		return true
	end
	for _, other in stage.objectives do
		if other ~= objective and other.type ~= "talk" and not isObjectiveComplete(entry, other) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Progression
--------------------------------------------------------------------------------

local completeQuest: (player: Player, quest: Quest) -> ()

-- Passe à l'étape suivante si l'étape en cours est finie (en boucle : une étape peut être déjà
-- remplie en y arrivant, par exemple un objet déjà possédé).
local function checkStageCompletion(player: Player, quest: Quest)
	while true do
		local profile = PlayerData.get(player)
		local entry = profile and profile.quests.active[quest.id]
		if profile == nil or entry == nil then
			return
		end
		local stage = quest.stages[entry.stage]
		if stage == nil then
			completeQuest(player, quest)
			return
		end
		for _, objective in stage.objectives do
			if not isObjectiveComplete(entry, objective) then
				return
			end
		end

		local nextIndex = entry.stage + 1
		if nextIndex > #quest.stages then
			completeQuest(player, quest)
			return
		end
		PlayerData.mutate(player, "quests", function(p)
			local current = p.quests.active[quest.id]
			if current then
				current.stage = nextIndex
				current.progress = {}
			end
		end)
		local nextStage = quest.stages[nextIndex]
		-- Objectifs "item" déjà satisfaits par l'inventaire en arrivant sur l'étape.
		for _, objective in nextStage.objectives do
			if objective.type == "item" then
				local owned = profile.inventory[objective.target] or 0
				if owned > 0 then
					PlayerData.mutate(player, "quests", function(p)
						local current = p.quests.active[quest.id]
						if current then
							current.progress[objective.id] = math.min(objective.count, owned)
						end
					end)
				end
			end
		end
		StateSync.notify(player, "quest", { event = "stage", questId = quest.id, name = quest.name, stage = nextStage.title, journal = nextStage.journal })
		QuestService.StageAdvanced:Fire(player, quest.id, nextIndex)
	end
end

completeQuest = function(player: Player, quest: Quest)
	local profile = PlayerData.get(player)
	if profile == nil or profile.quests.completed[quest.id] then
		return
	end
	PlayerData.mutate(player, "quests", function(p)
		p.quests.active[quest.id] = nil
		p.quests.completed[quest.id] = os.time()
	end)
	StateSync.notify(player, "quest", { event = "completed", questId = quest.id, name = quest.name, rewardText = quest.rewardText })
	-- Clé unique : même si la fin était rejouée (requête répétée, reconnexion), rien n'est versé deux fois.
	RewardService.grant(player, `quest:{quest.id}`, quest.rewards, { reason = quest.name })
	QuestService.QuestCompleted:Fire(player, quest.id)
	GameEvents.QuestCompleted:Fire(player, quest.id)
	PlayerData.saveSoon(player)
	-- Une quête terminée peut en rendre d'autres disponibles.
	StateSync.push(player, "quests")
end

--[[
	Fait avancer, pour `player`, tous les objectifs de type `objectiveType` qui visent `target` dans
	l'étape EN COURS de ses quêtes actives. `matches` (facultatif) remplace le test d'égalité du target.
]]
local function progress(player: Player, objectiveType: string, target: string, amount: number, typeSet: { [string]: boolean }?)
	local profile = PlayerData.get(player)
	if profile == nil then
		return
	end
	for questId, entry in profile.quests.active do
		local quest = QuestDefinitions.getQuest(questId)
		local stage = quest and quest.stages[entry.stage]
		if quest == nil or stage == nil then
			continue
		end
		local changed = false
		for _, objective in stage.objectives do
			local isTypeMatch = if typeSet then typeSet[objective.type] == true else objective.type == objectiveType
			if isTypeMatch and objective.target == target and not isObjectiveComplete(entry, objective) and isObjectiveCreditable(entry, stage, objective) then
				PlayerData.mutate(player, "quests", function(p)
					local current = p.quests.active[questId]
					if current then
						current.progress[objective.id] = math.min(objective.count, (current.progress[objective.id] or 0) + amount)
					end
				end)
				changed = true
			end
		end
		if changed then
			checkStageCompletion(player, quest)
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function QuestService.getState(player: Player, questId: string): QuestState
	local profile = PlayerData.get(player)
	local quest = QuestDefinitions.getQuest(questId)
	if profile == nil or quest == nil then
		return "locked"
	end
	return getStateFromProfile(profile, quest)
end

function QuestService.isCompleted(player: Player, questId: string): boolean
	return QuestService.getState(player, questId) == "completed"
end

-- true si la quête est active et à l'étape `stageId`.
function QuestService.isAtStage(player: Player, questId: string, stageId: string): boolean
	local profile = PlayerData.get(player)
	local quest = QuestDefinitions.getQuest(questId)
	local entry = profile and profile.quests.active[questId]
	if quest == nil or entry == nil then
		return false
	end
	local stage = quest.stages[entry.stage]
	return stage ~= nil and stage.id == stageId
end

-- true si, à l'étape en cours, l'objectif `objectiveId` est atteint.
function QuestService.isObjectiveDone(player: Player, questId: string, objectiveId: string): boolean
	local profile = PlayerData.get(player)
	local quest = QuestDefinitions.getQuest(questId)
	local entry = profile and profile.quests.active[questId]
	local stage = if quest and entry then quest.stages[entry.stage] else nil
	if entry == nil or stage == nil then
		return false
	end
	for _, objective in stage.objectives do
		if objective.id == objectiveId then
			return isObjectiveComplete(entry, objective)
		end
	end
	return false
end

-- Démarre une quête. Retourne (false, raison) si c'est impossible : "unknown", "no_profile",
-- "already_active", "already_completed", "locked".
function QuestService.accept(player: Player, questId: string): (boolean, string?)
	local quest = QuestDefinitions.getQuest(questId)
	if quest == nil then
		return false, "unknown"
	end
	local profile = PlayerData.get(player)
	if profile == nil then
		return false, "no_profile"
	end
	local state = getStateFromProfile(profile, quest)
	if state == "active" then
		return false, "already_active"
	elseif state == "completed" then
		return false, "already_completed"
	elseif state == "locked" then
		return false, "locked"
	end

	PlayerData.mutate(player, "quests", function(p)
		p.quests.active[questId] = { stage = 1, progress = {}, startedAt = os.time() }
	end)
	StateSync.notify(player, "quest", { event = "started", questId = questId, name = quest.name, stage = quest.stages[1].title, journal = quest.stages[1].journal })
	-- En acceptant, le joueur vient d'écouter le donneur : l'objectif "talk" qui le vise est rempli.
	progress(player, "talk", quest.giver, 1)
	PlayerData.saveSoon(player)
	return true
end

--[[
	Ce que dit le PNJ `npcId` à `player`, selon ses quêtes (nil = rien de lié aux quêtes : le PNJ dit
	son texte habituel). Les options proposées sont des identifiants "quest_accept:<id>" et "close".
]]
function QuestService.getNpcDialogue(player: Player, npcId: string): NpcDialogue?
	local profile = PlayerData.get(player)
	if profile == nil then
		return nil
	end

	-- 1. Étape en cours qui attend ce PNJ (objectif "talk" atteignable), puis 2. indices d'étape.
	local hint: { string }? = nil
	for _, questId in QuestDefinitions.ORDER do
		local quest = QuestDefinitions.QUESTS[questId]
		local entry = profile.quests.active[questId]
		local stage = entry and quest.stages[entry.stage]
		if entry == nil or stage == nil then
			continue
		end
		for _, objective in stage.objectives do
			if objective.type == "talk" and objective.target == npcId and not isObjectiveComplete(entry, objective) then
				if isObjectiveCreditable(entry, stage, objective) then
					local lines = (stage.dialogue and stage.dialogue[npcId]) or { stage.journal }
					return { lines = lines }
				end
				hint = { `Il vous reste à faire : {stage.journal}` }
			end
		end
		if hint == nil and stage.dialogue and stage.dialogue[npcId] then
			hint = stage.dialogue[npcId]
		end
	end

	-- 3. Quête proposée par ce PNJ.
	for _, questId in QuestDefinitions.ORDER do
		local quest = QuestDefinitions.QUESTS[questId]
		if quest.giver == npcId and getStateFromProfile(profile, quest) == "available" then
			return {
				lines = quest.offer.lines,
				options = {
					{ id = `quest_accept:{quest.id}`, label = quest.offer.accept },
					{ id = "close", label = quest.offer.decline },
				},
			}
		end
	end

	if hint then
		return { lines = hint }
	end

	-- 4. Après une quête terminée.
	for index = #QuestDefinitions.ORDER, 1, -1 do
		local quest = QuestDefinitions.QUESTS[QuestDefinitions.ORDER[index]]
		if profile.quests.completed[quest.id] and quest.after and quest.after[npcId] then
			return { lines = quest.after[npcId] }
		end
	end
	return nil
end

-- À appeler une seule fois au démarrage du serveur (après StateSync et RewardService).
function QuestService.start()
	if isStarted then
		return
	end
	isStarted = true

	StateSync.register("quests", function(player: Player): any
		local profile = PlayerData.get(player)
		if profile == nil then
			return nil
		end
		local available = {}
		for _, questId in QuestDefinitions.ORDER do
			local quest = QuestDefinitions.QUESTS[questId]
			if getStateFromProfile(profile, quest) == "available" then
				table.insert(available, questId)
			end
		end
		return {
			active = profile.quests.active,
			completed = profile.quests.completed,
			available = available,
		}
	end)

	GameEvents.Talked:Connect(function(player: Player, npcId: string)
		progress(player, "talk", npcId, 1)
	end)
	GameEvents.InteractableUsed:Connect(function(player: Player, interactableId: string, _kind: string)
		progress(player, "examine", interactableId, 1, INTERACTABLE_TYPES)
	end)
	GameEvents.RegionEntered:Connect(function(player: Player, regionId: string)
		progress(player, "explore", regionId, 1)
	end)
	GameEvents.EchoWitnessed:Connect(function(player: Player, echoId: string)
		progress(player, "echo", echoId, 1)
	end)
	GameEvents.PuzzleSolved:Connect(function(players: { Player }, mechanismId: string)
		for _, player in players do
			progress(player, "puzzle", mechanismId, 1)
		end
	end)
	GameEvents.EnemyDefeated:Connect(function(info: GameEvents.DefeatInfo)
		for _, player in info.eligible do
			progress(player, "kill", info.enemyId, 1)
		end
	end)
	GameEvents.ItemCollected:Connect(function(player: Player, itemId: string, count: number)
		progress(player, "item", itemId, count)
	end)

	-- Données d'une ancienne version : une quête active dont la définition a changé est revérifiée.
	ProfileStore.ProfileLoaded:Connect(function(player: Player, profile: Profile)
		for questId in profile.quests.active do
			local quest = QuestDefinitions.getQuest(questId)
			if quest then
				checkStageCompletion(player, quest)
			end
		end
	end)
end

return QuestService
