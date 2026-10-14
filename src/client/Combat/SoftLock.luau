--!strict
--[[
	SoftLock
	Visée assistée : trouve l'ennemi le plus proche du joueur et tourne le personnage vers lui.
	Appelé par CombatController au départ de chaque coup, pour ne plus frapper dans le vide.

	C'est le client qui tourne son propre personnage (il en simule la physique) ; la rotation
	est ensuite répliquée aux autres comme n'importe quel déplacement.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("CombatConfig") :: ModuleScript)
local TimeLoopConfig = require(sharedFolder:WaitForChild("TimeLoop"):WaitForChild("TimeLoopConfig") :: ModuleScript)

local SoftLock = {}

-- Position d'un personnage s'il est vivant et dans le monde, sinon nil.
local function getLivingPosition(character: Instance): Vector3?
	if not character:IsA("Model") or not character:IsDescendantOf(workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil
	end
	return rootPart.Position
end

-- Tout ce que le joueur a le droit de frapper : les PNJ taggés, et les autres joueurs si le PvP est actif.
local function getEnemies(ownCharacter: Model): { Instance }
	local enemies = CollectionService:GetTagged(TimeLoopConfig.ENTITY_TAG)

	if CombatConfig.PVP_ENABLED then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and character ~= ownCharacter then
				table.insert(enemies, character)
			end
		end
	end

	return enemies
end

-- L'ennemi vivant le plus proche de `rootPart`, à moins de `radius` studs. nil s'il n'y en a pas.
function SoftLock.findTarget(ownCharacter: Model, rootPart: BasePart, radius: number): Model?
	local nearestEnemy: Model? = nil
	local nearestDistance = radius

	for _, enemy in getEnemies(ownCharacter) do
		local position = getLivingPosition(enemy)
		if position then
			local distance = (position - rootPart.Position).Magnitude
			if distance <= nearestDistance then
				nearestEnemy, nearestDistance = enemy :: Model, distance
			end
		end
	end

	return nearestEnemy
end

-- Tourne `rootPart` vers `target`, à plat (le personnage ne penche pas si la cible est en hauteur).
function SoftLock.face(rootPart: BasePart, target: Model)
	local origin = rootPart.Position
	local targetPosition = target:GetPivot().Position
	local flatTarget = Vector3.new(targetPosition.X, origin.Y, targetPosition.Z)
	if (flatTarget - origin).Magnitude > 0.1 then
		rootPart.CFrame = CFrame.lookAt(origin, flatTarget)
	end
end

return SoftLock
