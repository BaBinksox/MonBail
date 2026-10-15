--!strict
--[[
	AvatarAppearance
	Applique un Selection sur un personnage. C'est le seul module qui touche au corps du personnage ;
	il ne sait rien du Hub, des joueurs ni de la sauvegarde.

	Trois étapes, dans apply() :
		1. corps, cheveux, tenue, taille : un HumanoidDescription (API officielle) ;
		2. tête classique : remplace la tête animée de Roblox, sur laquelle un Decal s'affiche déformé ;
		3. visage (Decal) et marque (cicatrice, tatouage : image sur un SurfaceGui, placée librement).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage.Shared.Avatar.AvatarConfig)

local CharacterPlacement = require(script.Parent.Parent.Core.CharacterPlacement)

type Selection = AvatarConfig.Selection

-- Tête classique de Roblox : un bloc 2x1x1 arrondi par un SpecialMesh.
local CLASSIC_HEAD_SIZE = Vector3.new(2, 1, 1)
local CLASSIC_HEAD_MESH_SCALE = Vector3.new(1.25, 1.25, 1.25)
local CLASSIC_HEAD_ATTACHMENTS: { [string]: Vector3 } = {
	NeckRigAttachment = Vector3.new(0, -0.5, 0),
	FaceCenterAttachment = Vector3.new(0, 0, 0),
	FaceFrontAttachment = Vector3.new(0, 0, -0.6),
	HairAttachment = Vector3.new(0, 0.6, 0),
	HatAttachment = Vector3.new(0, 0.6, 0),
}

-- Panneau des marques (voir addMark).
local MARK_CANVAS_NAME = "FaceCanvas"
local MARK_CANVAS_THICKNESS = 0.05 -- studs
local MARK_CANVAS_PIXELS = 420 -- résolution du SurfaceGui (celle des images de marque)

local AvatarAppearance = {}

--------------------------------------------------------------------------------
-- 1. HumanoidDescription
--------------------------------------------------------------------------------

local function buildDescription(humanoid: Humanoid, selection: Selection): HumanoidDescription
	local base = AvatarConfig.BASE_OPTIONS[selection.baseIndex]
	local hair = AvatarConfig.HAIR_OPTIONS[selection.hairIndex]
	local outfit = AvatarConfig.OUTFIT_OPTIONS[selection.outfitIndex]

	-- On part de l'apparence actuelle pour conserver la couleur de peau du joueur.
	local description = humanoid:GetAppliedDescription()

	-- Les accessoires de l'avatar Roblox (chapeaux, vêtements 3D, ailes...) jurent avec l'univers :
	-- on les retire tous, puis on ne repose que ceux du jeu.
	description:SetAccessories({}, true)
	description.GraphicTShirt = 0

	-- Corps : les 5 parties de la base choisie.
	description.Torso = base.torsoId
	description.RightArm = base.rightArmId
	description.LeftArm = base.leftArmId
	description.LeftLeg = base.leftLegId
	description.RightLeg = base.rightLegId

	-- Tête et visage par défaut : ils sont de toute façon remplacés ensuite (étapes 2 et 3).
	-- Les garder constants évite qu'ApplyDescription refasse la tête à chaque changement d'option.
	description.Head = 0
	description.Face = 0

	description.HairAccessory = tostring(hair.assetId)
	description.BackAccessory = if outfit.backAccessoryId > 0 then tostring(outfit.backAccessoryId) else ""
	description.Shirt = outfit.shirtId
	description.Pants = outfit.pantsId
	description.HeightScale = selection.heightScale
	description.WidthScale = selection.widthScale

	return description
end

--------------------------------------------------------------------------------
-- 2. Tête classique
--------------------------------------------------------------------------------
-- Les têtes actuelles de Roblox (y compris la tête par défaut et celles des bundles Man / Woman)
-- sont des MeshParts "animées" : leur visage est peint dans la texture du mesh et leurs UV ne
-- sont pas prévus pour un Decal. La tête classique (Part + SpecialMesh de type Head) est la
-- seule sur laquelle un Decal de visage 2D se plaque correctement.

local function isClassicHead(head: Instance): boolean
	return head:IsA("Part") and head:FindFirstChildOfClass("SpecialMesh") ~= nil
end

local function buildClassicHead(color: Color3): Part
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = CLASSIC_HEAD_SIZE
	head.Color = color
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Mesh"
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = CLASSIC_HEAD_MESH_SCALE
	mesh.Parent = head

	-- Points d'ancrage standard d'une tête R15 : le cou (indispensable au rig) et les accessoires.
	for name, position in CLASSIC_HEAD_ATTACHMENTS do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Parent = head
	end

	return head
end

-- Un accessoire soudé à l'ancienne tête (les cheveux) perd sa soudure quand elle disparaît :
-- on redonne au Humanoid ceux qui ne tiennent plus à rien pour qu'il les ressoude.
local function isHeldByCharacter(accessory: Accessory, character: Model): boolean
	local handle = accessory:FindFirstChild("Handle")
	local weld = handle and handle:FindFirstChild("AccessoryWeld")
	if weld == nil or not weld:IsA("Weld") then
		return false
	end

	-- Une pièce détruite n'est plus dans le personnage : la soudure qui la référence ne tient plus rien.
	local part0, part1 = weld.Part0, weld.Part1
	return part0 ~= nil and part1 ~= nil and part0:IsDescendantOf(character) and part1:IsDescendantOf(character)
end

local function reattachLooseAccessories(character: Model, humanoid: Humanoid)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and not isHeldByCharacter(child, character) then
			child.Parent = nil
			humanoid:AddAccessory(child)
		end
	end
end

-- Garantit que le personnage porte la tête classique et la retourne (nil si ce n'est pas possible).
local function ensureClassicHead(character: Model, humanoid: Humanoid): BasePart?
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	if isClassicHead(head) then
		return head
	end

	local classicHead = buildClassicHead(head.Color)
	classicHead.CFrame = head.CFrame

	-- Un Humanoid meurt s'il se retrouve sans cou : on suspend cette règle le temps de l'échange.
	local requiredNeck = humanoid.RequiresNeck
	humanoid.RequiresNeck = false

	if not humanoid:ReplaceBodyPartR15(Enum.BodyPartR15.Head, classicHead) then
		classicHead:Destroy()
		humanoid.RequiresNeck = requiredNeck
		return nil
	end
	if head.Parent ~= nil then
		head:Destroy()
	end
	if classicHead:FindFirstChild("Neck") == nil then
		humanoid:BuildRigFromAttachments()
	end

	if classicHead:FindFirstChild("Neck") then
		humanoid.RequiresNeck = requiredNeck
	else
		warn(`[Avatar] Cou non reconstruit pour {character.Name} : RequiresNeck reste désactivé`)
	end

	reattachLooseAccessories(character, humanoid)
	return classicHead
end

--------------------------------------------------------------------------------
-- 3. Calques du visage
--------------------------------------------------------------------------------

-- Visage : un Decal sur l'avant de la tête. Il suit la courbure de la tête classique.
local function addFace(head: BasePart, texture: string)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = texture
	face.Parent = head
end

--[[
	Marque : un Decal ne se déplace pas et ne se redimensionne pas (il est étiré sur toute la face,
	enroulé autour de la tête), d'où des cicatrices décentrées. On utilise donc un SurfaceGui :
		Head
		└── FaceCanvas (Part invisible, soudée juste devant le visage)
		    └── MarkSurface (SurfaceGui, face avant)
		        └── Mark (ImageLabel : Position, Size et Rotation réglables au pixel)
	Position, taille et rotation viennent de la MarkOption (offset, scale, rotation).
]]
local function addMark(head: BasePart, mark: AvatarConfig.MarkOption)
	if mark.texture == "" then
		return
	end

	local size = AvatarConfig.FACE_CANVAS_SIZE
	-- La face avant du panneau (celle qui porte l'image) se trouve à FACE_CANVAS_DEPTH du centre de la tête.
	local offset = CFrame.new(0, 0, -(AvatarConfig.FACE_CANVAS_DEPTH - MARK_CANVAS_THICKNESS / 2))

	local canvas = Instance.new("Part")
	canvas.Name = MARK_CANVAS_NAME
	canvas.Size = Vector3.new(size, size, MARK_CANVAS_THICKNESS)
	canvas.Transparency = 1
	canvas.CanCollide = false
	canvas.CanQuery = false
	canvas.CanTouch = false
	canvas.Massless = true
	canvas.CastShadow = false
	canvas.CFrame = head.CFrame * offset

	local weld = Instance.new("Weld")
	weld.Name = "FaceCanvasWeld"
	weld.Part0 = head
	weld.Part1 = canvas
	weld.C0 = offset
	weld.Parent = canvas

	local surface = Instance.new("SurfaceGui")
	surface.Name = "MarkSurface"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(MARK_CANVAS_PIXELS, MARK_CANVAS_PIXELS)
	surface.LightInfluence = 1 -- éclairée comme le reste du visage, pas comme une interface
	surface.Parent = canvas

	local image = Instance.new("ImageLabel")
	image.Name = "Mark"
	image.BackgroundTransparency = 1
	image.Image = mark.texture
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5 + mark.offset.X, 0.5 + mark.offset.Y)
	image.Size = UDim2.fromScale(mark.scale, mark.scale)
	image.Rotation = mark.rotation
	image.Parent = surface

	canvas.Parent = head
end

-- Pose le visage puis la marque. Tout ce qui restait d'un choix précédent est d'abord détruit,
-- pour ne jamais superposer deux visages ou deux marques.
local function applyFaceLayers(character: Model, humanoid: Humanoid, selection: Selection)
	local head = ensureClassicHead(character, humanoid)
	if head == nil then
		return
	end

	for _, child in head:GetChildren() do
		if child:IsA("Decal") or child.Name == MARK_CANVAS_NAME then
			child:Destroy()
		end
	end

	addFace(head, AvatarConfig.FACE_OPTIONS[selection.faceIndex].texture)
	addMark(head, AvatarConfig.MARK_OPTIONS[selection.markIndex])
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Applique `selection` sur `character`. YIELD (chargement des assets).
-- Retourne false si le HumanoidDescription n'a pas pu être appliqué.
function AvatarAppearance.apply(character: Model, selection: Selection): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end

	local isApplied, errorMessage = pcall(function()
		humanoid:ApplyDescription(buildDescription(humanoid, selection))
	end)
	if not isApplied then
		warn(`[Avatar] Apparence non appliquée pour {character.Name} (ID d'asset invalide ?) : {errorMessage}`)
	end
	-- HipHeight calculé par la mise à l'échelle de Roblox pour ce corps : BuildRigFromAttachments
	-- (tête classique, ci-dessous) peut le recalculer de travers, et le Humanoid se tiendrait alors
	-- avec les jambes dans le sol. On le rétablit après l'échange de tête.
	local expectedHipHeight = humanoid.HipHeight

	-- Après ApplyDescription (qui peut remettre une tête animée), et à l'abri d'une erreur :
	-- un visage raté ne doit pas empêcher la suite (recalage au sol, fermeture du Hub).
	local isFaceApplied, faceError = pcall(function()
		applyFaceLayers(character, humanoid, selection)
	end)
	if not isFaceApplied then
		warn(`[Avatar] Visage non appliqué pour {character.Name} : {faceError}`)
	end
	CharacterPlacement.repairHipHeight(character, expectedHipHeight)

	return isApplied
end

return AvatarAppearance
