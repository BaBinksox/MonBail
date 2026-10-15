--!strict
--[[
	MissionService
	Le tableau des contrats (Shared/Mission/MissionDefinitions).

	- Le client DEMANDE (accepter, abandonner, rendre) ; le serveur vérifie tout : proximité du tableau
	  ou d'Ysolde, rang, quêtes et déblocages requis, groupe minimal, nombre de contrats actifs,
	  objectifs atteints et objets à remettre au moment de rendre.
	- La progression vient du bus GameEvents (faits validés par le serveur), comme pour les quêtes.
	- Rendre un contrat verse la récompense avec une clé unique ("mission:<id>" ou
	  "cycle:mission:<id>:<cycle>") : une seule fois par cycle, quoi qu'il arrive.
	- État client : tranche StateSync "missions" (disponibles, verrouillés avec la raison, actifs avec
	  progression et statut, rendus dans le cycle, prochain renouvellement).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MissionDefinitions = require(ReplicatedStorage.Shared.Mission.MissionDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Mission.MissionRemotes)
local RankConfig = require(ReplicatedStorage.Shared.Progression.RankConfig)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PartyService = require(script.Parent.Parent.Party.PartyService)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local ProgressionService = require(script.Parent.Parent.Progression.ProgressionService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local StateSync = require(script.Parent.Parent.State.StateSync)
local WorldAnchors = require(script.Parent.Parent.World.WorldAnchors)

type Mission = MissionDefinitions.Mission
type Profile = PlayerData.Profile

local SECONDS_PER_DAY = 86400
local SECONDS_PER_WEEK = 7 * SECONDS_PER_DAY
local WEEK_EPOCH_OFFSET = 3 * SECONDS_PER_DAY -- le 1/1/1970 était un jeudi : semaines du lundi au dimanche
local INTERACTABLE_TYPES = { examine = true, interact = true, collect = true }

local MissionService = {}

local limiter = RateLimiter.new(2, 5)
local isStarted = false

--------------------------------------------------------------------------------
-- Cycles
--------------------------------------------------------------------------------

local function getShiftedTime(): number
	return os.time() - MissionDefinitions.DAILY_RESET_HOUR_UTC * 3600
end

-- Identifiant du cycle en cours pour une rotation ("once", date du jour, ou numéro de semaine).
function MissionService.getCycleId(rotation: string): string
	if rotation == "daily" then
		return os.date("!%Y-%m-%d", getShiftedTime()) :: string
	elseif rotation == "weekly" then
		return `W{math.floor((getShiftedTime() + WEEK_EPOCH_OFFSET) / SECONDS_PER_WEEK)}`
	end
	return "once"
end

local function getRewardKey(mission: Mission, cycleId: string): string
	if mission.rotation == "once" then
		return `mission:{mission.id}`
	end
	return `cycle:mission:{mission.id}:{cycleId}`
end

-- Secondes avant le prochain renouvellement quotidien.
local function getSecondsToDailyReset(): number
	local shifted = getShiftedTime()
	return SECONDS_PER_DAY - (shifted % SECONDS_PER_DAY)
end

--------------------------------------------------------------------------------
-- Disponibilité
--------------------------------------------------------------------------------

-- Pourquoi `mission` n'est pas disponible pour ce profil (nil = disponible).
local function getLockReason(player: Player, profile: Profile, mission: Mission): string?
	if not RankConfig.isAtLeast(profile.progression.rank, mission.minRank) then
		return `Rang {mission.minRank} requis`
	end
	if mission.prerequisites.quests then
		for _, questId in mission.prerequisites.quests do
			if profile.quests.completed[questId] == nil then
				return "Une quête doit d'abord être terminée"
			end
		end
	end
	if mission.prerequisites.unlocks then
		for _, unlockId in mission.prerequisites.unlocks do
			if profile.unlocks[unlockId] == nil then
				return "Un lieu doit d'abord être ouvert"
			end
		end
	end
	if profile.ledger[getRewardKey(mission, MissionService.getCycleId(mission.rotation))] then
		return if mission.rotation == "once" then "Déjà accompli" else "Déjà accompli pour ce cycle"
	end
	if mission.group then
		local members = PartyService.getMembers(player)
		if #members < mission.group.minMembers then
			return `Groupe d'au moins {mission.group.minMembers} joueurs requis`
		end
	end
	return nil
end

local function areObjectivesDone(entry: { progress: { [string]: number } }, mission: Mission): boolean
	for _, objective in mission.objectives do
		if (entry.progress[objective.id] or 0) < objective.count then
			return false
		end
	end
	return true
end

local function isNearBoard(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end
	local board = WorldAnchors.getInteractable("board_missions")
	local quartermaster = WorldAnchors.get("npc_quartermaster")
	for _, part in { board, quartermaster } do
		if part and (part.Position - rootPart.Position).Magnitude <= MissionDefinitions.BOARD_RANGE then
			return true
		end
	end
	-- Sans carte construite, le tableau n'existe pas : on n'impose pas la proximité.
	return board == nil and quartermaster == nil
end

--------------------------------------------------------------------------------
-- Progression
--------------------------------------------------------------------------------

local function progress(player: Player, objectiveType: string, target: string, amount: number, typeSet: { [string]: boolean }?)
	local profile = PlayerData.get(player)
	if profile == nil then
		return
	end
	for missionId, entry in profile.missions.active do
		local mission = MissionDefinitions.getMission(missionId)
		if mission == nil then
			continue
		end
		for _, objective in mission.objectives do
			local isTypeMatch = if typeSet then typeSet[objective.type] == true else objective.type == objectiveType
			if isTypeMatch and objective.target == target and (entry.progress[objective.id] or 0) < objective.count then
				PlayerData.mutate(player, "missions", function(p)
					local current = p.missions.active[missionId]
					if current then
						current.progress[objective.id] = math.min(objective.count, (current.progress[objective.id] or 0) + amount)
					end
				end)
				if areObjectivesDone(profile.missions.active[missionId] or entry, mission) then
					StateSync.notify(player, "mission", { event = "ready", missionId = missionId, name = mission.name })
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function accept(player: Player, mission: Mission): (boolean, string?)
	local profile = PlayerData.get(player)
	if profile == nil then
		return false, "Votre progression n'est pas chargée."
	end
	if profile.missions.active[mission.id] then
		return false, "Ce contrat est déjà accepté."
	end
	local count = 0
	for _ in profile.missions.active do
		count += 1
	end
	if count >= MissionDefinitions.MAX_ACTIVE then
		return false, `Pas plus de {MissionDefinitions.MAX_ACTIVE} contrats à la fois.`
	end
	local reason = getLockReason(player, profile, mission)
	if reason then
		return false, reason
	end
	PlayerData.mutate(player, "missions", function(p)
		p.missions.active[mission.id] = { progress = {}, acceptedAt = os.time(), cycle = MissionService.getCycleId(mission.rotation) }
	end)
	StateSync.notify(player, "mission", { event = "accepted", missionId = mission.id, name = mission.name })
	return true
end

local function abandon(player: Player, mission: Mission): (boolean, string?)
	local profile = PlayerData.get(player)
	if profile == nil or profile.missions.active[mission.id] == nil then
		return false, "Ce contrat n'est pas en cours."
	end
	PlayerData.mutate(player, "missions", function(p)
		p.missions.active[mission.id] = nil
	end)
	return true
end

local function claim(player: Player, mission: Mission): (boolean, string?)
	local profile = PlayerData.get(player)
	local entry = profile and profile.missions.active[mission.id]
	if profile == nil or entry == nil then
		return false, "Ce contrat n'est pas en cours."
	end
	if not areObjectivesDone(entry, mission) then
		return false, "Les objectifs ne sont pas encore atteints."
	end
	local key = getRewardKey(mission, entry.cycle)
	if profile.ledger[key] then
		-- Déjà payé (requête répétée) : on retire seulement le contrat actif.
		PlayerData.mutate(player, "missions", function(p)
			p.missions.active[mission.id] = nil
		end)
		return false, "Ce contrat a déjà été payé."
	end
	if mission.deliver and not RewardService.takeItems(player, mission.deliver) then
		return false, "Il vous manque des objets à remettre."
	end
	local cycleId = entry.cycle
	local isGranted = RewardService.grant(player, key, mission.rewards :: any, { reason = mission.name })
	if not isGranted then
		return false, "Ce contrat a déjà été payé."
	end
	PlayerData.mutate(player, "missions", function(p)
		p.missions.active[mission.id] = nil
		p.missions.completions[mission.id] = (p.missions.completions[mission.id] or 0) + 1
	end)
	GameEvents.MissionCompleted:Fire(player, mission.id, cycleId)
	-- Une mission de validation peut débloquer le rang suivant.
	ProgressionService.checkPromotion(player)
	return true
end

local function onRequest(player: Player, action: any, missionId: any): any
	if not limiter:allow(player) or type(action) ~= "string" then
		return { ok = false, error = "Trop de demandes." }
	end
	local mission = MissionDefinitions.getMission(missionId)
	if mission == nil then
		return { ok = false, error = "Contrat inconnu." }
	end
	if action ~= "abandon" and not isNearBoard(player) then
		return { ok = false, error = "Approchez-vous du tableau des contrats." }
	end
	local isDone, message
	if action == "accept" then
		isDone, message = accept(player, mission)
	elseif action == "abandon" then
		isDone, message = abandon(player, mission)
	elseif action == "claim" then
		isDone, message = claim(player, mission)
	else
		return { ok = false, error = "Action inconnue." }
	end
	StateSync.push(player, "missions")
	return { ok = isDone, error = message }
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function MissionService.start()
	if isStarted then
		return
	end
	isStarted = true

	StateSync.register("missions", function(player: Player): any
		local profile = PlayerData.get(player)
		if profile == nil then
			return nil
		end
		local available, locked, active = {}, {}, {}
		for _, mission in MissionDefinitions.MISSIONS do
			local entry = profile.missions.active[mission.id]
			if entry then
				table.insert(active, {
					id = mission.id,
					progress = entry.progress,
					cycle = entry.cycle,
					ready = areObjectivesDone(entry, mission),
				})
			else
				local reason = getLockReason(player, profile, mission)
				if reason then
					table.insert(locked, { id = mission.id, reason = reason })
				else
					table.insert(available, mission.id)
				end
			end
		end
		return {
			available = available,
			locked = locked,
			active = active,
			completions = profile.missions.completions,
			secondsToDailyReset = getSecondsToDailyReset(),
		}
	end)

	Remotes.MissionRequest.OnServerInvoke = onRequest

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
	GameEvents.MechanismActivated:Connect(function(player: Player, mechanismId: string)
		progress(player, "mechanism", mechanismId, 1)
	end)
	GameEvents.EnemyDefeated:Connect(function(info: GameEvents.DefeatInfo)
		for _, player in info.eligible do
			progress(player, "kill", info.enemyId, 1)
		end
	end)
	GameEvents.ItemCollected:Connect(function(player: Player, itemId: string, count: number)
		progress(player, "item", itemId, count)
	end)
	-- Une quête terminée, une promotion ou un groupe formé peuvent rendre des contrats disponibles.
	GameEvents.QuestCompleted:Connect(function(player: Player)
		StateSync.push(player, "missions")
	end)
	ProfileStore.ProfileLoaded:Connect(function(player: Player)
		StateSync.push(player, "missions")
	end)
end

return MissionService
