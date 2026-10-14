--!strict
--[[
	SwordFactory
	Fabrique l'épée d'un personnage et la fixe dans sa main droite par un Motor6D (pas de Tool).

	Source du modèle :
		- ServerStorage > Assets > Sword s'il existe et qu'il est conforme :
		    * un Model dont le PrimaryPart est la poignée (c'est lui qui est tenu en main) ;
		    * toutes ses pièces soudées entre elles ;
		    * deux Attachments nommés BladeStart (base de la lame) et BladeEnd (pointe) ;
		    * l'axe Y du PrimaryPart pointe de la poignée vers la pointe.
		- sinon, une épée provisoire en Parts est générée par code.

	Jointures :
		- pièces de l'épée entre elles : des Weld à décalage EXPLICITE (C0). Pas de WeldConstraint
		  ici : son décalage est déduit de la position des pièces au moment où il devient actif,
		  ce qui est fragile quand le Motor6D déplace la poignée dans la main au même instant
		  (la lame peut rester soudée loin de la poignée).
		- épée -> main : un Motor6D recréé à chaque attach(), Part0 = RightHand, Part1 = poignée.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Combat.CombatConfig)

-- Dimensions de l'épée provisoire (studs). L'axe Y de la poignée va vers la pointe.
local GRIP_SIZE = Vector3.new(0.25, 1.1, 0.25)
local GUARD_SIZE = Vector3.new(1.1, 0.18, 0.3)
local BLADE_SIZE = Vector3.new(0.32, 3.6, 0.08)
local GUARD_OFFSET_Y = GRIP_SIZE.Y / 2 + GUARD_SIZE.Y / 2
local BLADE_START_Y = GRIP_SIZE.Y / 2 + GUARD_SIZE.Y
local BLADE_END_Y = BLADE_START_Y + BLADE_SIZE.Y

-- Traînée de lame : blanc froid à la lame, violet en bout de sillage.
local TRAIL_LIFETIME = 0.18 -- secondes de persistance du sillage
local TRAIL_COLOR_HEAD = Color3.fromRGB(235, 240, 255)
local TRAIL_COLOR_TAIL = Color3.fromRGB(150, 90, 255)

-- Prise standard d'une main R15, utilisée si la main n'a pas (encore) son RightGripAttachment.
local DEFAULT_GRIP_CFRAME = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local SwordFactory = {}

--------------------------------------------------------------------------------
-- Épée provisoire
--------------------------------------------------------------------------------

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Soude `part` à la poignée, à `offset` du centre de celle-ci.
local function weldToHandle(handle: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = handle.CFrame * offset

	local weld = Instance.new("Weld")
	weld.Name = "SwordWeld"
	weld.Part0 = handle
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local function newAttachment(name: string, offsetY: number, parent: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = Vector3.new(0, offsetY, 0)
	attachment.Parent = parent
end

local function buildPlaceholder(): Model
	local sword = Instance.new("Model")
	sword.Name = Config.SWORD_NAME

	local handle = newPart("Handle", GRIP_SIZE, Color3.fromRGB(45, 32, 26), Enum.Material.Wood)
	handle.Parent = sword
	sword.PrimaryPart = handle

	local guard = newPart("Guard", GUARD_SIZE, Color3.fromRGB(70, 62, 50), Enum.Material.Metal)
	guard.Parent = sword
	weldToHandle(handle, guard, CFrame.new(0, GUARD_OFFSET_Y, 0))

	local blade = newPart("Blade", BLADE_SIZE, Color3.fromRGB(170, 175, 185), Enum.Material.Metal)
	blade.Parent = sword
	weldToHandle(handle, blade, CFrame.new(0, BLADE_START_Y + BLADE_SIZE.Y / 2, 0))

	newAttachment(Config.BLADE_START_NAME, BLADE_START_Y, handle)
	newAttachment(Config.BLADE_END_NAME, BLADE_END_Y, handle)

	return sword
end

--------------------------------------------------------------------------------
-- Modèle fourni par le développeur
--------------------------------------------------------------------------------

local function isValidTemplate(template: Instance): boolean
	return template:IsA("Model")
		and template.PrimaryPart ~= nil
		and template:FindFirstChild(Config.BLADE_START_NAME, true) ~= nil
		and template:FindFirstChild(Config.BLADE_END_NAME, true) ~= nil
end

local function cloneTemplate(): Model?
	local assets = ServerStorage:FindFirstChild(Config.ASSETS_FOLDER_NAME)
	local template = assets and assets:FindFirstChild(Config.SWORD_NAME)
	if template == nil then
		return nil
	end
	if not isValidTemplate(template) then
		warn("[Combat] ServerStorage.Assets.Sword est invalide (PrimaryPart, BladeStart ou BladeEnd manquant) : épée provisoire utilisée")
		return nil
	end
	return template:Clone() :: Model
end

--------------------------------------------------------------------------------
-- Traînée de lame
--------------------------------------------------------------------------------

-- Ajoute un Trail tendu entre la base et la pointe de la lame : un ruban lumineux qui suit le
-- mouvement. Il est créé ÉTEINT ; ce sont les clients qui l'allument pendant la fenêtre de frappe
-- (voir CombatEffects.playBladeTrail), jamais le serveur.
local function addBladeTrail(sword: Model)
	local handle = sword.PrimaryPart
	local bladeStart = sword:FindFirstChild(Config.BLADE_START_NAME, true)
	local bladeEnd = sword:FindFirstChild(Config.BLADE_END_NAME, true)
	if
		handle == nil
		or bladeStart == nil
		or bladeEnd == nil
		or not bladeStart:IsA("Attachment")
		or not bladeEnd:IsA("Attachment")
	then
		return
	end

	local trail = Instance.new("Trail")
	trail.Name = Config.BLADE_TRAIL_NAME
	trail.Enabled = false
	trail.Attachment0 = bladeStart
	trail.Attachment1 = bladeEnd
	trail.Lifetime = TRAIL_LIFETIME
	trail.MinLength = 0.02
	trail.FaceCamera = false -- le ruban garde la largeur réelle de la lame
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(TRAIL_COLOR_HEAD, TRAIL_COLOR_TAIL)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = handle
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Crée une épée prête à être fixée (non parentée). À détruire avec le personnage.
function SwordFactory.create(): Model
	local sword = cloneTemplate() or buildPlaceholder()
	sword.Name = Config.SWORD_NAME

	-- Sur l'épée provisoire comme sur un modèle fourni, sauf si celui-ci a déjà sa traînée.
	if sword:FindFirstChild(Config.BLADE_TRAIL_NAME, true) == nil then
		addBladeTrail(sword)
	end

	-- Sur TOUTES les pièces : l'épée ne doit ni heurter le décor ou le personnage (CanCollide),
	-- ni peser sur lui (Massless), ni arrêter les rayons des hitboxes (CanQuery).
	for _, descendant in sword:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	return sword
end

-- Fixe la poignée de l'épée dans `hand` (le RightHand du personnage). Peut être rappelée à
-- volonté : l'ancien Motor6D est remplacé, ce qui permet de suivre un changement de main.
function SwordFactory.attach(sword: Model, hand: BasePart): boolean
	local handle = sword.PrimaryPart
	if handle == nil then
		return false
	end

	local previousMotor = handle:FindFirstChild(Config.SWORD_MOTOR_NAME)
	if previousMotor then
		previousMotor:Destroy()
	end

	local gripAttachment = hand:FindFirstChild(Config.GRIP_ATTACHMENT_NAME)
	local gripCFrame = if gripAttachment and gripAttachment:IsA("Attachment")
		then gripAttachment.CFrame
		else DEFAULT_GRIP_CFRAME

	local motor = Instance.new("Motor6D")
	motor.Name = Config.SWORD_MOTOR_NAME
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = gripCFrame * Config.SWORD_GRIP_OFFSET
	motor.Parent = handle

	return true
end

return SwordFactory
