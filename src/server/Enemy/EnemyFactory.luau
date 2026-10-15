--!strict
--[[
	EnemyFactory
	Fabrique les Models des ennemis côté serveur (aucune IA ici).

	build(def) -> Model (YIELD), par ordre de préférence :
		1. ServerStorage.Assets.Enemies.<enemyId> s'il existe (modèle du créateur, Humanoid + RootPart) :
		   cloné tel quel, sans habillage ;
		2. un rig R15 généré par Players:CreateHumanoidModelFromDescriptionAsync (pcall, YIELD : appelé
		   hors de la boucle d'IA), habillé par EnemyDefinitions.appearance : couleurs du corps, matière,
		   échelles, décorations en Parts soudées, particules (texture par défaut), lumières ;
		3. si la génération échoue (service indisponible...), un rig R6 en blocs aux mêmes couleurs :
		   l'ennemi existe quand même, sans animation.
	configure(model, def, anchorId) pose les réglages de jeu (PV, vitesse, nom affiché, attributs) ;
	placeAt(model, anchorCFrame, params) le pose au sol sur son ancre, tourné comme elle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local DamageService = require(script.Parent.Parent.Combat.DamageService)

type EnemyDef = Definitions.EnemyDef
type AppearanceDef = Definitions.AppearanceDef

local ROOT_PART_NAME = "HumanoidRootPart"
local GROUND_PROBE_UP = 4 -- studs au-dessus de l'ancre d'où l'on sonde le sol
local GROUND_PROBE_DOWN = 40
local ANCHOR_ROOT_HEIGHT = 3 -- une ancre de personnage est posée 3 studs au-dessus du sol (Kit.standing)
local SPAWN_CLEARANCE = 0.15 -- studs de marge sous les pieds à l'apparition
local R6_LEG_HEIGHT = 2

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

-- Pièces R15 -> pièce équivalente du rig R6 de secours.
local R6_FALLBACK: { [string]: string } = {
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	LeftUpperArm = "Left Arm",
	LeftLowerArm = "Left Arm",
	LeftHand = "Left Arm",
	RightUpperArm = "Right Arm",
	RightLowerArm = "Right Arm",
	RightHand = "Right Arm",
	LeftUpperLeg = "Left Leg",
	LeftLowerLeg = "Left Leg",
	LeftFoot = "Left Leg",
	RightUpperLeg = "Right Leg",
	RightLowerLeg = "Right Leg",
	RightFoot = "Right Leg",
}

local EnemyFactory = {}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

--------------------------------------------------------------------------------
-- Accès
--------------------------------------------------------------------------------

-- Humanoid (enfant direct) et RootPart d'un Model d'ennemi, sinon nil.
function EnemyFactory.getParts(model: Model): (Humanoid?, BasePart?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil, nil
	end
	local rootPart = humanoid.RootPart
	if rootPart == nil then
		local named = model:FindFirstChild(ROOT_PART_NAME)
		if named and named:IsA("BasePart") then
			rootPart = named
		end
	end
	return humanoid, rootPart
end

local function findBodyPart(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	if part == nil then
		local fallback = R6_FALLBACK[name]
		part = fallback and model:FindFirstChild(fallback)
	end
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

--------------------------------------------------------------------------------
-- 1. Modèle du créateur
--------------------------------------------------------------------------------

local function findAsset(enemyId: string): Model?
	local assets = ServerStorage:FindFirstChild(CombatConfig.ASSETS_FOLDER_NAME)
	local folder = assets and assets:FindFirstChild(Definitions.ASSETS_FOLDER_NAME)
	local asset = folder and folder:FindFirstChild(enemyId)
	if asset == nil then
		return nil
	end
	if not asset:IsA("Model") then
		warnOnce(`asset:{enemyId}`, `[Enemy] ServerStorage.Assets.Enemies.{enemyId} n'est pas un Model : ignoré`)
		return nil
	end
	local humanoid, rootPart = EnemyFactory.getParts(asset)
	if humanoid == nil or rootPart == nil then
		warnOnce(`asset:{enemyId}`, `[Enemy] ServerStorage.Assets.Enemies.{enemyId} n'a pas de Humanoid avec un HumanoidRootPart : ignoré`)
		return nil
	end
	return asset
end

--------------------------------------------------------------------------------
-- 2. Rig R15 généré
--------------------------------------------------------------------------------

local function buildDescription(appearance: AppearanceDef): HumanoidDescription
	local colors = appearance.bodyColors
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = colors.head
	description.TorsoColor = colors.torso
	description.LeftArmColor = colors.leftArm
	description.RightArmColor = colors.rightArm
	description.LeftLegColor = colors.leftLeg
	description.RightLegColor = colors.rightLeg
	description.HeightScale = appearance.heightScale
	description.WidthScale = appearance.widthScale
	description.DepthScale = appearance.depthScale or 1
	description.HeadScale = appearance.headScale or 1
	return description
end

-- YIELD. nil si la génération est impossible.
local function createRig(def: EnemyDef): Model?
	local description = buildDescription(def.appearance)
	local isCreated, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not isCreated then
		-- Ancien nom de la même API (moteurs plus anciens).
		isCreated, result = pcall(function(): Model
			return (Players :: any):CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
	end
	description:Destroy()
	if isCreated and typeof(result) == "Instance" and result:IsA("Model") then
		return result
	end
	warnOnce(`rig:{def.id}`, `[Enemy] Rig R15 de {def.id} impossible à générer ({result}) : rig de secours en blocs`)
	return nil
end

--------------------------------------------------------------------------------
-- 3. Rig R6 de secours
--------------------------------------------------------------------------------

local function newBodyPart(model: Model, name: string, size: Vector3, color: Color3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = CFrame.new(position)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function newMotor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

local function buildBlockyRig(def: EnemyDef): Model
	local colors = def.appearance.bodyColors
	local model = Instance.new("Model")

	local rootPart = newBodyPart(model, ROOT_PART_NAME, Vector3.new(2, 2, 1), colors.torso, Vector3.new(0, 3, 0))
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	local torso = newBodyPart(model, "Torso", Vector3.new(2, 2, 1), colors.torso, Vector3.new(0, 3, 0))
	local head = newBodyPart(model, "Head", Vector3.new(2, 1, 1), colors.head, Vector3.new(0, 4.5, 0))
	local leftArm = newBodyPart(model, "Left Arm", Vector3.new(1, 2, 1), colors.leftArm, Vector3.new(-1.5, 3, 0))
	local rightArm = newBodyPart(model, "Right Arm", Vector3.new(1, 2, 1), colors.rightArm, Vector3.new(1.5, 3, 0))
	local leftLeg = newBodyPart(model, "Left Leg", Vector3.new(1, 2, 1), colors.leftLeg, Vector3.new(-0.5, 1, 0))
	local rightLeg = newBodyPart(model, "Right Leg", Vector3.new(1, 2, 1), colors.rightLeg, Vector3.new(0.5, 1, 0))

	newMotor("RootJoint", rootPart, torso, CFrame.new(), CFrame.new())
	newMotor("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	newMotor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	newMotor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	newMotor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0), CFrame.new(-0.5, 1, 0))
	newMotor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0), CFrame.new(0.5, 1, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = rootPart
	return model
end

--------------------------------------------------------------------------------
-- Habillage
--------------------------------------------------------------------------------

-- Retire le visage souriant par défaut (Decal, ou texture d'une tête en MeshPart).
local function stripFace(model: Model)
	local head = model:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	for _, child in head:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	if head:IsA("MeshPart") then
		pcall(function()
			head.TextureID = ""
		end)
	end
end

-- Décalage d'un élément par rapport à sa pièce porteuse (relatif à sa taille + studs).
local function getOffset(host: BasePart, relative: Vector3?, studs: Vector3?, rotation: Vector3?): CFrame
	local position = host.Size * (relative or Vector3.zero) + (studs or Vector3.zero)
	local angles = rotation or Vector3.zero
	return CFrame.new(position) * CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

local function addDecoration(model: Model, decoration: Definitions.DecorationDef)
	local host = findBodyPart(model, decoration.attachTo)
	if host == nil then
		return
	end
	local part: BasePart
	if decoration.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = SHAPES[decoration.shape] or Enum.PartType.Block
		part = block
	end
	part.Name = decoration.name
	part.Size = decoration.size
	part.Color = decoration.color
	part.Material = decoration.material
	part.Transparency = decoration.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true

	local offset = getOffset(host, decoration.position, decoration.offset, decoration.rotation)
	part.CFrame = host.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "DecorationWeld"
	weld.Part0 = host
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = model
end

local function addEmitter(model: Model, emitterDef: Definitions.EmitterDef)
	local host = findBodyPart(model, emitterDef.attachTo)
	if host == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = emitterDef.name .. "Attachment"
	attachment.CFrame = getOffset(host, emitterDef.position, emitterDef.offset, nil)
	attachment.Parent = host

	local emitter = Instance.new("ParticleEmitter") -- texture par défaut : aucun asset
	emitter.Name = emitterDef.name
	emitter.Color = emitterDef.color
	emitter.Rate = emitterDef.rate
	emitter.Lifetime = emitterDef.lifetime
	emitter.Speed = emitterDef.speed
	emitter.Size = emitterDef.size
	emitter.Transparency = emitterDef.transparency or NumberSequence.new(0, 1)
	emitter.LightEmission = emitterDef.lightEmission or 0
	local spread = emitterDef.spread or 30
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = emitterDef.acceleration or Vector3.zero
	emitter.Parent = attachment
end

local function addLight(model: Model, lightDef: Definitions.LightDef)
	local host = findBodyPart(model, lightDef.attachTo)
	if host == nil then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = lightDef.color
	light.Range = lightDef.range
	light.Brightness = lightDef.brightness
	light.Shadows = false
	light.Parent = host
end

local function applyAppearance(model: Model, def: EnemyDef)
	local appearance = def.appearance
	if appearance.hideFace then
		stripFace(model)
	end

	-- Matière et transparence des pièces du corps (avant d'ajouter les décorations).
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= ROOT_PART_NAME then
			if appearance.bodyMaterial then
				child.Material = appearance.bodyMaterial
			end
			if appearance.bodyTransparency then
				child.Transparency = appearance.bodyTransparency
			end
		end
	end

	for _, decoration in appearance.decorations do
		addDecoration(model, decoration)
	end
	for _, emitterDef in appearance.emitters do
		addEmitter(model, emitterDef)
	end
	for _, lightDef in appearance.lights or {} do
		addLight(model, lightDef)
	end

	-- Mise à l'échelle globale en dernier : décorations, soudures et HipHeight suivent.
	if math.abs(appearance.modelScale - 1) > 1e-3 then
		local isScaled, message = pcall(function()
			model:ScaleTo(appearance.modelScale)
		end)
		if not isScaled then
			warnOnce(`scale:{def.id}`, `[Enemy] Mise à l'échelle de {def.id} impossible : {message}`)
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

--[[
	Construit le Model de `def` (non parenté, non configuré). YIELD (génération du rig) : à appeler
	depuis un thread dédié, jamais depuis la boucle d'IA.
]]
function EnemyFactory.build(def: EnemyDef): Model
	local asset = findAsset(def.id)
	if asset then
		local clone = asset:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false -- un modèle posé dans Studio a souvent des pièces ancrées
			end
		end
		return clone
	end

	local rig = createRig(def) or buildBlockyRig(def)
	applyAppearance(rig, def)
	return rig
end

-- Réglages de jeu : PV, vitesse, nom affiché, attributs lus par les autres systèmes.
function EnemyFactory.configure(model: Model, def: EnemyDef, anchorId: string?)
	local humanoid, rootPart = EnemyFactory.getParts(model)
	if humanoid == nil or rootPart == nil then
		return
	end
	model.Name = def.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- jamais à moitié chez un client
	model.PrimaryPart = rootPart

	model:SetAttribute(DamageService.ENEMY_ID_ATTRIBUTE, def.id)
	if def.elite then
		model:SetAttribute(DamageService.ELITE_ATTRIBUTE, true)
	end
	if not def.rewindable then
		-- Hors de la timeline du rembobinage (voir le compte rendu : TimeLoopService doit le respecter).
		model:SetAttribute(Definitions.ATTRIBUTES.rewindable, false)
	end
	if anchorId then
		model:SetAttribute(Definitions.ATTRIBUTES.spawnAnchor, anchorId)
	end
	if def.practice then
		model:SetAttribute(Definitions.ATTRIBUTES.practice, true)
	end

	-- Le boss garde les PV de BossConfig (BossService les impose aussi à son inscription).
	local maxHealth = if def.behavior == "boss" then BossConfig.MAX_HEALTH else def.maxHealth
	humanoid.DisplayName = def.displayName
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = def.walkSpeed
	-- Le nom et la barre de vie sont dessinés par le client (EnemyEffectsController).
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false -- le corps reste entier jusqu'à son fondu

	if humanoid:FindFirstChildOfClass("Animator") == nil then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
end

-- Distance entre le RootPart et le dessous des pieds.
function EnemyFactory.getRootHeight(model: Model, humanoid: Humanoid, rootPart: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = model:FindFirstChild("Left Leg")
		local legHeight = if leg and leg:IsA("BasePart") then leg.Size.Y else R6_LEG_HEIGHT
		return rootPart.Size.Y / 2 + legHeight
	end
	return humanoid.HipHeight + rootPart.Size.Y / 2
end

--[[
	Pose `model` au sol sous `anchorCFrame` (sol sondé par rayon ; à défaut, 3 studs sous l'ancre),
	tourné comme l'ancre. Retourne la hauteur du RootPart au-dessus du sol.
]]
function EnemyFactory.placeAt(model: Model, anchorCFrame: CFrame, params: RaycastParams): number
	local humanoid, rootPart = EnemyFactory.getParts(model)
	if humanoid == nil or rootPart == nil then
		return ANCHOR_ROOT_HEIGHT
	end
	local rootHeight = EnemyFactory.getRootHeight(model, humanoid, rootPart)
	local anchorPosition = anchorCFrame.Position
	local result = workspace:Raycast(anchorPosition + Vector3.new(0, GROUND_PROBE_UP, 0), Vector3.new(0, -GROUND_PROBE_DOWN, 0), params)
	local groundY = if result then result.Position.Y else anchorPosition.Y - ANCHOR_ROOT_HEIGHT

	local position = Vector3.new(anchorPosition.X, groundY + rootHeight + SPAWN_CLEARANCE, anchorPosition.Z)
	local look = Vector3.new(anchorCFrame.LookVector.X, 0, anchorCFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	local rootTarget = CFrame.lookAt(position, position + look.Unit)
	model:PivotTo(rootTarget * rootPart.CFrame:ToObjectSpace(model:GetPivot()))
	return rootHeight
end

return EnemyFactory
