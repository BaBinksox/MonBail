--!strict
--[[
	WorldAnchors
	Trouve les ancres, objets interactifs et objets dynamiques posés par le générateur de carte,
	par IDENTIFIANT (jamais par coordonnée). Voir RegionConfig (ancres) et MechanismConfig.

		local spawn = WorldAnchors.getCFrame("spawn_village")  -- CFrame?, nil si la carte n'est pas construite
		local part = WorldAnchors.get("boss_training")          -- BasePart?
		local rune = WorldAnchors.getInteractable("well_rune_3") -- BasePart portant l'InteractableId
		local door = WorldAnchors.getDynamic("door_flame_sanctum") -- Model ou BasePart

	Les résultats sont mis en cache ; un objet détruit (reconstruction de la carte) est recherché à nouveau.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MechanismConfig = require(ReplicatedStorage.Shared.World.MechanismConfig)
local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)

local WorldAnchors = {}

local anchorCache: { [string]: BasePart } = {}
local interactableCache: { [string]: BasePart } = {}
local dynamicCache: { [string]: Instance } = {}

local function isAlive(instance: Instance?): boolean
	return instance ~= nil and instance:IsDescendantOf(workspace)
end

local function getWorldFolder(): Instance?
	return workspace:FindFirstChild(RegionConfig.WORLD_FOLDER_NAME)
end

-- Ancre (Part invisible) d'identifiant `anchorId`, ou nil.
function WorldAnchors.get(anchorId: string): BasePart?
	local cached = anchorCache[anchorId]
	if cached and isAlive(cached) then
		return cached
	end
	for _, instance in CollectionService:GetTagged(RegionConfig.ANCHOR_TAG) do
		if instance:IsA("BasePart") and instance:GetAttribute(RegionConfig.ANCHOR_ATTRIBUTE) == anchorId and isAlive(instance) then
			anchorCache[anchorId] = instance
			return instance
		end
	end
	return nil
end

function WorldAnchors.getCFrame(anchorId: string): CFrame?
	local anchor = WorldAnchors.get(anchorId)
	return anchor and anchor.CFrame
end

-- BasePart taggée "Interactable" portant cet InteractableId, ou nil.
function WorldAnchors.getInteractable(interactableId: string): BasePart?
	local cached = interactableCache[interactableId]
	if cached and isAlive(cached) then
		return cached
	end
	for _, instance in CollectionService:GetTagged(RegionConfig.INTERACTABLE_TAG) do
		if instance:IsA("BasePart") and instance:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE) == interactableId and isAlive(instance) then
			interactableCache[interactableId] = instance
			return instance
		end
	end
	return nil
end

-- Objet dynamique (Model ou BasePart) de Workspace.World.Dynamic portant ce DynamicId, ou nil.
function WorldAnchors.getDynamic(dynamicId: string): Instance?
	local cached = dynamicCache[dynamicId]
	if cached and isAlive(cached) then
		return cached
	end
	local world = getWorldFolder()
	local folder = world and world:FindFirstChild(RegionConfig.DYNAMIC_FOLDER_NAME)
	if folder == nil then
		return nil
	end
	for _, instance in folder:GetDescendants() do
		if instance:GetAttribute(MechanismConfig.DYNAMIC_ATTRIBUTE) == dynamicId then
			dynamicCache[dynamicId] = instance
			return instance
		end
	end
	return nil
end

-- Points d'un trajet d'écho (Parts "1".."n" de Workspace.World.EchoPaths.<folderName>), dans l'ordre.
function WorldAnchors.getEchoPath(folderName: string): { Vector3 }
	local points = {}
	local world = getWorldFolder()
	local paths = world and world:FindFirstChild(RegionConfig.ECHO_PATHS_FOLDER_NAME)
	local folder = paths and paths:FindFirstChild(folderName)
	if folder == nil then
		return points
	end
	local index = 1
	while true do
		local point = folder:FindFirstChild(tostring(index))
		if point == nil or not point:IsA("BasePart") then
			break
		end
		table.insert(points, point.Position)
		index += 1
	end
	return points
end

-- true si la carte de la Région 1 est construite dans ce Workspace.
function WorldAnchors.isWorldBuilt(): boolean
	return getWorldFolder() ~= nil
end

return WorldAnchors
