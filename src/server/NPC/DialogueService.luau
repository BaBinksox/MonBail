--!strict
--[[
	DialogueService
	Ce que disent les PNJ, décidé par le SERVEUR selon la progression du joueur (quêtes, rôle du PNJ).
	Le client garde l'affichage (machine à écrire, voir NPCInteraction) et son texte habituel de repli.

	- GetDialogue(npc) : vérifie le PNJ (tag Villager, identifiant NpcId posé par NpcSpawner, distance,
	  fréquence), demande à QuestService les répliques contextuelles, ajoute les choix liés au rôle du
	  PNJ (contrats, guildes), retient les choix proposés, PUIS émet GameEvents.Talked (une étape de
	  quête qui attendait ce PNJ avance après qu'il a parlé).
	- ChooseOption(npc, optionId) : n'accepte qu'un choix proposé il y a moins de OFFER_LIFETIME s,
	  pour ce PNJ, et à portée. Accepter une quête passe par QuestService.accept (qui revérifie tout).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueConfig = require(ReplicatedStorage.Shared.NPC.DialogueConfig)
local NpcConfig = require(ReplicatedStorage.Shared.NPC.NpcConfig)
local Remotes = require(ReplicatedStorage.Shared.NPC.DialogueRemotes)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local QuestService = require(script.Parent.Parent.Quest.QuestService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)

type Option = { id: string, label: string }

type Offer = {
	npc: Model,
	options: { [string]: boolean },
	expiresAt: number,
}

local DISTANCE_TOLERANCE = 6 -- studs de marge (latence, déplacement)
local OFFER_LIFETIME = 120 -- secondes

local ROLE_OPTIONS: { [string]: Option } = {
	missions = { id = "open:missions", label = "Voir les contrats" },
	guild = { id = "open:guild", label = "Les guildes et leurs serments" },
}

local DialogueService = {}

local offers: { [Player]: Offer } = {}
local limiter = RateLimiter.new(1.5, 4)
local isStarted = false

local function isNpcInReach(player: Player, npc: any): boolean
	if typeof(npc) ~= "Instance" or not npc:IsA("Model") or not CollectionService:HasTag(npc, DialogueConfig.TAG) then
		return false
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
	if playerRoot == nil or not playerRoot:IsA("BasePart") or npcRoot == nil or not npcRoot:IsA("BasePart") then
		return false
	end
	return (playerRoot.Position - npcRoot.Position).Magnitude <= DialogueConfig.INTERACT_DISTANCE + DISTANCE_TOLERANCE
end

local function onGetDialogue(player: Player, npc: any): any
	if not limiter:allow(player, "get") or not isNpcInReach(player, npc) then
		return nil
	end
	local model = npc :: Model
	local npcId = model:GetAttribute(NpcConfig.NPC_ID_ATTRIBUTE)
	if type(npcId) ~= "string" then
		return nil -- villageois posé à la main, inconnu des quêtes : texte habituel côté client
	end
	local definition = NpcConfig.NPCS[npcId]

	local questDialogue = QuestService.getNpcDialogue(player, npcId)
	local options: { Option } = {}
	if questDialogue and questDialogue.options then
		for _, option in questDialogue.options do
			table.insert(options, option)
		end
	end
	local roleOption = definition and definition.role and ROLE_OPTIONS[definition.role]
	if roleOption then
		table.insert(options, 1, roleOption)
		if #options == 1 then
			table.insert(options, { id = "close", label = "Au revoir" })
		end
	end

	local allowed: { [string]: boolean } = {}
	for _, option in options do
		allowed[option.id] = true
	end
	offers[player] = { npc = model, options = allowed, expiresAt = os.clock() + OFFER_LIFETIME }

	-- Après avoir choisi les répliques : parler à ce PNJ fait avancer une étape qui l'attendait.
	GameEvents.Talked:Fire(player, npcId)

	return {
		npcId = npcId,
		name = if definition then definition.name else model.Name,
		lines = if questDialogue then questDialogue.lines else nil,
		options = options,
	}
end

local function onChooseOption(player: Player, npc: any, optionId: any): any
	if not limiter:allow(player, "choose") or type(optionId) ~= "string" then
		return { ok = false }
	end
	local offer = offers[player]
	if offer == nil or offer.npc ~= npc or os.clock() > offer.expiresAt or not offer.options[optionId] then
		return { ok = false, message = "Ce choix n'est plus proposé." }
	end
	if not isNpcInReach(player, npc) then
		return { ok = false, message = "Vous êtes trop loin." }
	end
	offers[player] = nil

	if optionId == "close" then
		return { ok = true, action = "close" }
	elseif optionId == "open:missions" then
		return { ok = true, action = "open_missions" }
	elseif optionId == "open:guild" then
		return { ok = true, action = "open_guild" }
	end

	local questId = string.match(optionId, "^quest_accept:(.+)$")
	if questId then
		local isAccepted, reason = QuestService.accept(player, questId)
		if isAccepted then
			return { ok = true, action = "close" }
		end
		return { ok = false, action = "close", message = `Impossible d'accepter cette quête ({reason}).` }
	end
	return { ok = false }
end

-- À appeler une seule fois au démarrage du serveur (après QuestService).
function DialogueService.start()
	if isStarted then
		return
	end
	isStarted = true
	Remotes.GetDialogue.OnServerInvoke = onGetDialogue
	Remotes.ChooseOption.OnServerInvoke = onChooseOption
	Players.PlayerRemoving:Connect(function(player: Player)
		offers[player] = nil
	end)
end

return DialogueService
