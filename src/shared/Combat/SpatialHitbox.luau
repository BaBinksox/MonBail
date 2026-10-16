--!strict
--[[
	SpatialHitbox
	Zone de frappe spatiale : une boîte posée juste devant un personnage, interrogée avec
	workspace:GetPartBoundsInBox (aucun événement .Touched, aucun rayon le long de la lame).

	Tant que la hitbox est active, à chaque frame :
		1. la boîte est replacée devant le RootPart (elle suit le joueur qui avance ou pivote) ;
		2. toutes les pièces qui la touchent sont récupérées, et ramenées à leur personnage ;
		3. chaque personnage vivant trouvé est signalé UNE fois par activation.

	La forme de l'épée n'entre plus en jeu : si l'ennemi est dans la zone, le coup porte.
	Seul le décor protège encore : un mur entre l'attaquant et la cible bloque le coup.
]]

local RunService = game:GetService("RunService")

export type HitCallback = (character: Model, position: Vector3) -> ()

local SpatialHitbox = {}
SpatialHitbox.__index = SpatialHitbox

type HitboxData = {
	_rootPart: BasePart,
	_size: Vector3,
	_centered: boolean,
	_overlapParams: OverlapParams,
	_raycastParams: RaycastParams,
	_hitCharacters: { [Model]: boolean },
	_connection: RBXScriptConnection?,
}

export type SpatialHitbox = typeof(setmetatable({} :: HitboxData, SpatialHitbox))

-- Remonte la hiérarchie depuis une pièce jusqu'au personnage (Model avec Humanoid) qui la contient.
function SpatialHitbox.getCharacterFromPart(part: Instance): Model?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Position de la boîte de taille `size` pour un personnage dont le RootPart est en `rootCFrame` :
-- collée devant lui, centrée sur sa hauteur. `centered` : centrée sur lui (coup tournoyant, plongée).
function SpatialHitbox.getBoxCFrame(rootCFrame: CFrame, size: Vector3, centered: boolean?): CFrame
	if centered then
		return rootCFrame
	end
	return rootCFrame * CFrame.new(0, 0, -size.Z / 2)
end

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Vrai si aucun élément de décor solide ne sépare le RootPart de `part`.
local function isReachable(self: SpatialHitbox, character: Model, part: BasePart): boolean
	local origin = self._rootPart.Position
	local result = workspace:Raycast(origin, part.Position - origin, self._raycastParams)
	if result == nil or result.Instance:IsDescendantOf(character) then
		return true
	end
	-- Un autre personnage sur la trajectoire ne protège pas la cible : seul le décor compte.
	return SpatialHitbox.getCharacterFromPart(result.Instance) ~= nil
end

local function step(self: SpatialHitbox, onHit: HitCallback)
	local boxCFrame = SpatialHitbox.getBoxCFrame(self._rootPart.CFrame, self._size, self._centered)

	for _, part in workspace:GetPartBoundsInBox(boxCFrame, self._size, self._overlapParams) do
		local character = SpatialHitbox.getCharacterFromPart(part)
		if character and not self._hitCharacters[character] and isAlive(character) and isReachable(self, character, part) then
			self._hitCharacters[character] = true
			onHit(character, part.Position)
		end
	end
end

-- `rootPart` : le HumanoidRootPart de l'attaquant. `ignoreList` : instances jamais touchées
-- (typiquement son propre personnage).
function SpatialHitbox.new(rootPart: BasePart, ignoreList: { Instance }): SpatialHitbox
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignoreList

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.RespectCanCollide = true

	local data: HitboxData = {
		_rootPart = rootPart,
		_size = Vector3.one,
		_centered = false,
		_overlapParams = overlapParams,
		_raycastParams = raycastParams,
		_hitCharacters = {},
		_connection = nil,
	}
	return setmetatable(data, SpatialHitbox)
end

-- Active une zone de taille `size` (largeur, hauteur, profondeur) pour `duration` secondes, puis
-- elle se coupe TOUTE SEULE : aucune détection n'a lieu en dehors de cette fenêtre.
-- `onHit` est appelé une fois par personnage touché, avec la position de la pièce atteinte.
-- `centered` : la boîte est centrée sur le personnage au lieu d'être posée devant lui.
function SpatialHitbox.start(self: SpatialHitbox, duration: number, size: Vector3, onHit: HitCallback, centered: boolean?)
	self:stop()
	self._size = size
	self._centered = centered == true
	self._hitCharacters = {}

	local stopClock = os.clock() + duration

	-- Heartbeat : après la physique, le personnage est à sa position finale de la frame.
	self._connection = RunService.Heartbeat:Connect(function()
		if os.clock() >= stopClock then
			self:stop()
			return
		end
		step(self, onHit)
	end)
	step(self, onHit) -- dès la première frame : un ennemi déjà au contact est touché sans délai
end

function SpatialHitbox.stop(self: SpatialHitbox)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return SpatialHitbox
