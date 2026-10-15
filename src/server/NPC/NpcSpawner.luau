--!strict
--[[
	NpcSpawner
	Fait apparaître les habitants de la Région 1 sur les marqueurs "npc_*" de la carte (voir
	Shared/NPC/NpcConfig). Chaque PNJ est un rig R15 créé à partir d'une HumanoidDescription habillée
	avec des options DÉJÀ présentes dans AvatarConfig (tenue, coiffure, corps), puis taggé "Villager" :
	VillagerService (promenade, conversation) et NPCInteraction (dialogue) le prennent en charge comme
	n'importe quel villageois posé à la main.

	- Idempotent : un PNJ déjà présent (même NpcId) n'est pas recréé.
	- Sans carte construite (aucun marqueur), rien n'apparaît (un avertissement l'explique).
	- Modèles personnalisés : si ServerStorage.Assets.NPCs.<NpcId> existe, il est cloné à la place.
	- Un PNJ qui disparaît (détruit par erreur) réapparaît après RESPAWN_DELAY.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AvatarConfig = require(ReplicatedStorage.Shared.Avatar.AvatarConfig)
local DialogueConfig = require(ReplicatedStorage.Shared.NPC.DialogueConfig)
local NpcConfig = require(ReplicatedStorage.Shared.NPC.NpcConfig)

local WorldAnchors = require(script.Parent.Parent.World.WorldAnchors)

local FOLDER_NAME = "NPCs"
local RESPAWN_DELAY = 20 -- secondes
local CUSTOM_MODELS_PATH = { "Assets", "NPCs" }

local NpcSpawner = {}

local spawned: { [string]: Model } = {}
local isStarted = false

local function findById(options: { any }, id: string?): any?
	if id == nil then
		return nil
	end
	for _, option in options do
		if option.id == id then
			return option
		end
	end
	return nil
end

local function getFolder(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function findCustomModel(npcId: string): Model?
	local node: Instance? = ServerStorage
	for _, name in CUSTOM_MODELS_PATH do
		node = node and node:FindFirstChild(name)
	end
	local model = node and node:FindFirstChild(npcId)
	return if model and model:IsA("Model") then model else nil
end

-- Description d'apparence à partir de la fiche du PNJ (options d'AvatarConfig uniquement).
local function buildDescription(definition: NpcConfig.Npc): HumanoidDescription
	local look = definition.look
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = look.skin
	description.TorsoColor = look.skin
	description.LeftArmColor = look.skin
	description.RightArmColor = look.skin
	description.LeftLegColor = look.skin
	description.RightLegColor = look.skin
	description.HeightScale = look.height
	description.WidthScale = look.width
	description.DepthScale = look.width

	local base = findById(AvatarConfig.BASE_OPTIONS, look.base)
	if base then
		description.Torso = base.torsoId
		description.RightArm = base.rightArmId
		description.LeftArm = base.leftArmId
		description.LeftLeg = base.leftLegId
		description.RightLeg = base.rightLegId
	end
	local outfit = findById(AvatarConfig.OUTFIT_OPTIONS, look.outfit)
	if outfit then
		description.Shirt = outfit.shirtId
		description.Pants = outfit.pantsId
		if outfit.backAccessoryId and outfit.backAccessoryId > 0 then
			description.BackAccessory = tostring(outfit.backAccessoryId)
		end
	end
	local hair = findById(AvatarConfig.HAIR_OPTIONS, look.hair)
	if hair then
		description.HairAccessory = tostring(hair.assetId)
	end
	return description
end

-- Crée le Model du PNJ (YIELD : chargement des assets de l'apparence). nil en cas d'échec.
local function createModel(npcId: string, definition: NpcConfig.Npc): Model?
	local custom = findCustomModel(npcId)
	if custom then
		return custom:Clone()
	end
	local isCreated, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(buildDescription(definition), Enum.HumanoidRigType.R15)
	end)
	if not isCreated then
		warn(`[NPC] Impossible de créer {npcId} : {result}`)
		return nil
	end
	return result
end

local function spawnNpc(npcId: string, definition: NpcConfig.Npc)
	local anchor = WorldAnchors.getCFrame(npcId)
	if anchor == nil or spawned[npcId] then
		return
	end
	local model = createModel(npcId, definition)
	if model == nil or spawned[npcId] then
		if model then
			model:Destroy()
		end
		return
	end

	model.Name = definition.name
	model:SetAttribute(NpcConfig.NPC_ID_ATTRIBUTE, npcId)
	model:SetAttribute(DialogueConfig.NAME_ATTRIBUTE, definition.name)
	model:SetAttribute(DialogueConfig.DIALOGUE_ATTRIBUTE, definition.dialogueId)
	model:SetAttribute(DialogueConfig.WANDER_ATTRIBUTE, definition.wanders)
	if definition.role then
		model:SetAttribute(NpcConfig.ROLE_ATTRIBUTE, definition.role)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = definition.name
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 30
	end
	model:PivotTo(anchor)
	model.Parent = getFolder()
	spawned[npcId] = model
	-- Le tag en dernier : VillagerService mémorise sa position d'origine à l'inscription.
	CollectionService:AddTag(model, DialogueConfig.TAG)

	model.Destroying:Connect(function()
		if spawned[npcId] == model then
			spawned[npcId] = nil
			task.delay(RESPAWN_DELAY, spawnNpc, npcId, definition)
		end
	end)
end

-- Modèle actuel du PNJ `npcId`, ou nil.
function NpcSpawner.getNpc(npcId: string): Model?
	return spawned[npcId]
end

-- À appeler une seule fois au démarrage du serveur (après la construction éventuelle de la carte).
function NpcSpawner.start()
	if isStarted then
		return
	end
	isStarted = true

	-- PNJ déjà présents (place sauvegardée avec eux) : on les reconnaît au lieu de les dupliquer.
	for _, instance in CollectionService:GetTagged(DialogueConfig.TAG) do
		local npcId = instance:GetAttribute(NpcConfig.NPC_ID_ATTRIBUTE)
		if type(npcId) == "string" and instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			spawned[npcId] = instance
		end
	end

	if not WorldAnchors.isWorldBuilt() then
		warn("[NPC] Workspace.World est absent : les habitants de la Région 1 n'apparaîtront pas (construire la carte, voir WorldBuilder).")
		return
	end
	for npcId, definition in NpcConfig.NPCS do
		task.spawn(spawnNpc, npcId, definition)
	end
end

return NpcSpawner
