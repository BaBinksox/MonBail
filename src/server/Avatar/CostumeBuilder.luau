--!strict
--[[
	CostumeBuilder
	Pose sur un personnage R15 (joueur ou PNJ) un vêtement et un ornement de GarmentLibrary :
		1. remet chaque membre à la couleur de peau (BodyColors) et à sa matière d'origine, puis
		   teint les membres couverts par le vêtement (couleur + matière : tissu, cuir...) ;
		2. sculpte les pièces (pourpoint, cape, plastron, pans...) et les soude aux membres.

	Toutes les pièces sont rangées dans un dossier « Costume » du personnage, détruit et refait à
	chaque changement : jamais deux tenues superposées. Elles sont décoratives et sûres :
		- sans masse (n'altèrent ni la marche, ni le saut, ni HipHeight) ;
		- sans collision, sans requête, sans contact (ne poussent personne, n'arrêtent aucun coup) ;
		- soudées à leur membre (elles suivent les animations d'épée et de magie) ;
		- créées par le serveur : visibles par tous les joueurs, refaites au respawn avec l'apparence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarmentLibrary = require(ReplicatedStorage.Shared.Avatar.GarmentLibrary)

type Piece = GarmentLibrary.Piece

local FOLDER_NAME = "Costume"
local MIN_SIZE = 0.02

-- Couleur de peau d'origine de chaque membre : le champ BodyColors qui le colore.
local BODY_COLOR_FIELD: { [string]: string } = {
	Head = "HeadColor3",
	UpperTorso = "TorsoColor3",
	LowerTorso = "TorsoColor3",
	LeftUpperArm = "LeftArmColor3",
	LeftLowerArm = "LeftArmColor3",
	LeftHand = "LeftArmColor3",
	RightUpperArm = "RightArmColor3",
	RightLowerArm = "RightArmColor3",
	RightHand = "RightArmColor3",
	LeftUpperLeg = "LeftLegColor3",
	LeftLowerLeg = "LeftLegColor3",
	LeftFoot = "LeftLegColor3",
	RightUpperLeg = "RightLegColor3",
	RightLowerLeg = "RightLegColor3",
	RightFoot = "RightLegColor3",
}

local CostumeBuilder = {}

local function decorate(part: BasePart, color: Color3, material: Enum.Material, transparency: number?)
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function scaled(value: Vector3, frame: Vector3, refY: number): Vector3
	return Vector3.new(frame.X * value.X, refY * value.Y, frame.Z * value.Z)
end

local function newShape(shape: string): BasePart
	if shape == "wedge" then
		return Instance.new("WedgePart")
	end
	local part = Instance.new("Part")
	if shape == "ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif shape == "cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
	return part
end

--[[
	Construit une pièce (et ses enfants) dans le repère `frame` de taille `frameSize`.
	`anchorPart` est le membre auquel tout est soudé (pour les enfants : le même membre).
]]
local function build(spec: Piece, model: Model, anchorPart: BasePart, frame: CFrame, frameSize: Vector3, isChild: boolean, folder: Folder, name: string)
	local refY = frameSize.Y
	if not isChild and spec.yRef then
		local reference = model:FindFirstChild(spec.yRef)
		if reference and reference:IsA("BasePart") then
			refY = reference.Size.Y
		end
	end
	local size = if spec.studs then spec.size else scaled(spec.size, frameSize, refY)
	size = Vector3.new(math.max(size.X, MIN_SIZE), math.max(size.Y, MIN_SIZE), math.max(size.Z, MIN_SIZE))
	local offset = if spec.studs then spec.offset else scaled(spec.offset, frameSize, refY)
	local rotation = spec.rotation or Vector3.zero
	local pieceFrame = frame * CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))

	local part = newShape(spec.shape)
	part.Name = name
	decorate(part, spec.color, spec.material, spec.transparency)
	if spec.shape == "cylinder" then
		-- Le cylindre de Roblox est couché sur l'axe X : on le redresse sur l'axe Y du repère.
		part.Size = Vector3.new(size.Y, size.X, size.Z)
		part.CFrame = pieceFrame * CFrame.Angles(0, 0, math.rad(90))
	else
		part.Size = size
		part.CFrame = pieceFrame
	end
	local weld = Instance.new("Weld")
	weld.Name = "CostumeWeld"
	weld.Part0 = anchorPart
	weld.Part1 = part
	weld.C0 = anchorPart.CFrame:ToObjectSpace(part.CFrame)
	weld.Parent = part
	part.Parent = folder

	local children = spec.children
	if children then
		for index, child in children do
			build(child, model, anchorPart, pieceFrame, size, true, folder, `{name}_{index}`)
		end
	end
end

-- Remet les membres à la peau et à leur matière d'origine (avant une nouvelle tenue).
local function restoreBody(model: Model)
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	for partName, field in BODY_COLOR_FIELD do
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			if bodyColors then
				part.Color = (bodyColors :: any)[field]
			end
			if part:GetAttribute("CostumeDyed") then
				local original = part:GetAttribute("OriginalMaterial")
				part.Material = if type(original) == "string" and (Enum.Material :: any)[original] then (Enum.Material :: any)[original] else Enum.Material.Plastic
				part:SetAttribute("CostumeDyed", nil)
			end
		end
	end
end

local function applyDye(model: Model, garment: GarmentLibrary.Garment)
	for key, layer in garment.dye do
		local targets: { string } = GarmentLibrary.DYE_TARGETS[key] or {}
		for _, partName in targets do
			local part = model:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				if not part:GetAttribute("CostumeDyed") then
					part:SetAttribute("OriginalMaterial", part.Material.Name)
				end
				part:SetAttribute("CostumeDyed", true)
				part.Color = layer.color
				part.Material = layer.material
			end
		end
	end
end

local function buildPieces(model: Model, pieces: { Piece }, folder: Folder, prefix: string)
	for index, spec in pieces do
		local anchorPart = model:FindFirstChild(spec.attach)
		if anchorPart and anchorPart:IsA("BasePart") then
			build(spec, model, anchorPart, anchorPart.CFrame, anchorPart.Size, false, folder, `{prefix}{index}`)
		end
	end
end

-- Retire la tenue fabriquée (pièces et teinture). Sans effet sur un personnage qui n'en porte pas.
function CostumeBuilder.clear(model: Model)
	local existing = model:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	restoreBody(model)
end

--[[
	Habille `model` du vêtement `garmentId` (GarmentLibrary) et de l'ornement `ornamentId`.
	nil ou inconnu = rien de ce côté (une tenue du catalogue Roblox, par exemple, reste telle quelle).
	Rend le nombre de pièces posées.
]]
function CostumeBuilder.dress(model: Model, garmentId: string?, ornamentId: string?): number
	CostumeBuilder.clear(model)
	local garment = GarmentLibrary.get(garmentId)
	local ornament = GarmentLibrary.getOrnament(ornamentId)
	if garment == nil and (ornament == nil or #ornament.pieces == 0) then
		return 0
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	if garment then
		applyDye(model, garment)
		buildPieces(model, garment.pieces, folder, `Garment_{garment.id}_`)
	end
	if ornament then
		buildPieces(model, ornament.pieces, folder, `Ornament_{ornament.id}_`)
	end
	folder.Parent = model
	return #folder:GetChildren()
end

CostumeBuilder.FOLDER_NAME = FOLDER_NAME

return CostumeBuilder
