--!strict
--[[
	CollisionGroups
	Les personnages ne se poussent pas physiquement entre eux : un villageois qui marche, ou un ennemi
	qui bondit, ne doit jamais projeter un joueur (les attaques passent par les hitbox et
	DamageService, pas par la collision des corps). Le décor, les murs et les barrières restent
	solides pour tout le monde.

	Groupes : "Players" (personnages des joueurs), "Npcs" (tag Villager), "Enemies" (tag Enemy).
	Players <-> Npcs et Players <-> Enemies : pas de collision. Players <-> Players : inchangé.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local PLAYERS_GROUP = "Players"
local NPCS_GROUP = "Npcs"
local ENEMIES_GROUP = "Enemies"
local TAG_GROUPS: { [string]: string } = { Villager = NPCS_GROUP, Enemy = ENEMIES_GROUP }

local CollisionGroups = {}
local isStarted = false

local function register(name: string)
	local isRegistered = false
	pcall(function()
		isRegistered = PhysicsService:IsCollisionGroupRegistered(name)
	end)
	if not isRegistered then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Met toutes les pièces de `model` (et celles ajoutées plus tard : accessoires, armes) dans `group`.
local function assign(model: Instance, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
	model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end)
end

function CollisionGroups.start()
	if isStarted then
		return
	end
	isStarted = true
	for _, group in { PLAYERS_GROUP, NPCS_GROUP, ENEMIES_GROUP } do
		register(group)
	end
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, NPCS_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, ENEMIES_GROUP, false)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			assign(character, PLAYERS_GROUP)
		end)
		if player.Character then
			assign(player.Character, PLAYERS_GROUP)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	for tag, group in TAG_GROUPS do
		for _, model in CollectionService:GetTagged(tag) do
			assign(model, group)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(model: Instance)
			assign(model, group)
		end)
	end
end

return CollisionGroups
