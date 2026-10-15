--!strict
--[[
	Kit
	Primitives de construction du générateur de carte : Parts avec des réglages sûrs, ancres,
	interactables, dynamics, points d'échos, lumières budgétées, textes sur surface.

	COORDONNÉES : toutes les fonctions prennent des CFrame / Vector3 LOCAUX à la région, c'est-à-dire
	dans le repère de RegionConfig.LAYOUT. La conversion vers le monde (RegionConfig.ORIGIN) est faite
	ici, au moment de poser la Part. Les zones et les props n'ont donc jamais à appeler toWorld().
	Ne lisez pas part.CFrame pour reconstruire autre chose : gardez vos CFrame locaux.

	RÉGLAGES PAR DÉFAUT d'une Part :
		Anchored = true ; TopSurface / BottomSurface = Smooth ; CanTouch = false ;
		CanCollide = true, CanQuery = true ; CastShadow seulement si sa plus grande dimension
		atteint WorldBuildConfig.SHADOW_MIN_EXTENT.
		Option `decor = true` (petits débris, détails) : CanCollide, CanQuery, CastShadow = false.

	API (toutes les positions en LOCAL) :
		Kit.part(parent, cframe, size, look, options?): Part
		Kit.wedge(parent, cframe, size, look, options?): WedgePart     -- pente vers -Z local, arête haute à +Z
		Kit.cornerWedge(parent, cframe, size, look, options?): CornerWedgePart
		Kit.cylinder(parent, cframe, length, diameter, look, options?): Part   -- axe = X local du cframe
		Kit.column(parent, baseCFrame, height, diameter, look, options?): Part -- cylindre debout, posé sur baseCFrame
		Kit.ball(parent, position, diameter, look, options?): Part
		Kit.beam(parent, from, to, width, height, look, options?): Part        -- poutre de `from` à `to`
		Kit.rod(parent, from, to, diameter, look, options?): Part              -- corde / tige cylindrique
		Kit.model(parent, name, pivot?): Model ; Kit.folder(parent, name): Folder (trouve ou crée)
		Kit.anchor(anchorsFolder, id, cframe, size?): Part
		Kit.tagInteractable(part, id) ; Kit.dynamic(dynamicFolder, instance, id)
		Kit.echoPoint(echoPathsFolder, pathName, index, cframe): Part
		Kit.light(parent, options?): Light? (nil si le budget est épuisé)
		Kit.fire / Kit.smoke / Kit.particles ; Kit.surfaceText(part, face, text, options?)
		Placement : Kit.at, Kit.yaw, Kit.facing, Kit.flatLook, Kit.standing, Kit.groundPoint,
		            Kit.ringPoint(center, radius, degrés), Kit.radial(center, radius, degrés)
		Kit.DECOR : options prêtes à l'emploi pour un petit décor ({ decor = true })
		Suivi : Kit.reset(), Kit.stats(), Kit.lightsRemaining()
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local MechanismConfig = require(ReplicatedStorage.Shared.World.MechanismConfig)
local Palette = require(script.Parent.Palette)
local Config = require(script.Parent.WorldBuildConfig)

export type Look = Palette.Look

export type PartOptions = {
	name: string?,
	decor: boolean?, -- petit décor : pas de collision, de requête ni d'ombre
	collide: boolean?, -- force CanCollide
	shadow: boolean?, -- force CastShadow
	query: boolean?, -- force CanQuery
	transparency: number?,
	reflectance: number?,
	color: Color3?, -- remplace la couleur du look
	material: Enum.Material?, -- remplace le matériau du look
}

export type LightOptions = {
	kind: ("point" | "spot" | "surface")?,
	color: Color3?,
	brightness: number?,
	range: number?,
	shadows: boolean?, -- accordé seulement s'il reste du budget d'ombres
	enabled: boolean?,
	face: Enum.NormalId?, -- spot / surface
	angle: number?, -- spot / surface (degrés)
}

export type FireOptions = {
	size: number?,
	heat: number?,
	color: Color3?,
	secondaryColor: Color3?,
	enabled: boolean?,
}

export type TextOptions = {
	color: Color3?,
	font: Enum.Font?,
	background: Color3?, -- nil = fond transparent
	pixelsPerStud: number?,
	rotation: number?, -- degrés (graffiti penché)
	transparency: number?,
}

export type Stats = {
	parts: number,
	lights: number,
	shadowLights: number,
	refusedLights: number,
}

local ORIGIN_CFRAME = CFrame.new(RegionConfig.ORIGIN)
local DEFAULT_ANCHOR_SIZE = Vector3.new(2, 2, 2)
local CHARACTER_ROOT_HEIGHT = 3 -- une ancre de personnage est 3 studs au-dessus du sol
local SMOOTH = Enum.SurfaceType.Smooth

local Kit = {}

local stats: Stats = { parts = 0, lights = 0, shadowLights = 0, refusedLights = 0 }

--------------------------------------------------------------------------------
-- Suivi
--------------------------------------------------------------------------------

-- Remet les compteurs à zéro (appelé par WorldBuilder au début de chaque construction).
function Kit.reset()
	stats.parts = 0
	stats.lights = 0
	stats.shadowLights = 0
	stats.refusedLights = 0
end

function Kit.stats(): Stats
	return table.clone(stats)
end

-- Lumières encore disponibles dans le budget de la région.
function Kit.lightsRemaining(): number
	return math.max(0, Config.LIGHT_BUDGET - stats.lights)
end

--------------------------------------------------------------------------------
-- Placement (repère LOCAL)
--------------------------------------------------------------------------------

-- CFrame monde d'un CFrame local (usage interne ; exposé pour les cas particuliers).
function Kit.toWorld(localCFrame: CFrame): CFrame
	return ORIGIN_CFRAME * localCFrame
end

-- origin * décalage (x, y, z) * rotation autour de Y (degrés). Le raccourci de tous les props.
function Kit.at(origin: CFrame, x: number, y: number, z: number, yawDegrees: number?): CFrame
	local cframe = origin * CFrame.new(x, y, z)
	if yawDegrees and yawDegrees ~= 0 then
		cframe *= CFrame.Angles(0, math.rad(yawDegrees), 0)
	end
	return cframe
end

-- CFrame à `position`, tourné de `yawDegrees` autour de Y (0 = regarde vers -Z, le nord).
function Kit.yaw(position: Vector3, yawDegrees: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yawDegrees), 0)
end

-- CFrame à `position` qui regarde HORIZONTALEMENT vers `target`.
function Kit.facing(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flatTarget)
end

-- CFrame à `position` qui regarde horizontalement dans la direction `direction`.
function Kit.flatLook(position: Vector3, direction: Vector3): CFrame
	return Kit.facing(position, position + Vector3.new(direction.X, 0, direction.Z))
end

-- CFrame d'ancre de personnage : `groundPosition` + 3 studs, regard horizontal vers `lookTarget`.
function Kit.standing(groundPosition: Vector3, lookTarget: Vector3): CFrame
	local position = groundPosition + Vector3.new(0, CHARACTER_ROOT_HEIGHT, 0)
	return Kit.facing(position, Vector3.new(lookTarget.X, position.Y, lookTarget.Z))
end

-- Point (x, y, z) avec y remplacé par `height` (raccourci pour poser au sol).
function Kit.groundPoint(position: Vector3, height: number): Vector3
	return Vector3.new(position.X, height, position.Z)
end

--[[
	Point d'un cercle horizontal autour de `center`. Angle en degrés mesuré depuis l'est (+X) vers
	le sud (+Z) : 0 = est, 90 = sud, 180 = ouest, -90 = nord. Le Y est celui de `center`.
]]
function Kit.ringPoint(center: Vector3, radius: number, degrees: number): Vector3
	local a = math.rad(degrees)
	return center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
end

-- Repère dont l'axe X pointe vers l'extérieur du cercle (angle en degrés, même convention).
-- Pratique pour les pièces disposées en anneau (margelles, dallages, marches en colimaçon).
function Kit.radial(center: Vector3, radius: number, degrees: number): CFrame
	return CFrame.new(Kit.ringPoint(center, radius, degrees)) * CFrame.Angles(0, -math.rad(degrees), 0)
end

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

local NO_OPTIONS: PartOptions = {}

-- Options partagées des petits décors (pas de collision, de requête ni d'ombre).
Kit.DECOR = table.freeze({ decor = true }) :: PartOptions

local function finishPart(part: BasePart, parent: Instance, cframe: CFrame, size: Vector3, look: Look, options: PartOptions?)
	local opts = options or NO_OPTIONS
	local decor = opts.decor == true
	local largest = math.max(size.X, size.Y, size.Z)
	part.Anchored = true
	part.Size = size
	part.CFrame = ORIGIN_CFRAME * cframe
	part.Color = opts.color or look.color
	part.Material = opts.material or look.material
	part.TopSurface = SMOOTH
	part.BottomSurface = SMOOTH
	part.CanTouch = false
	part.CanCollide = if opts.collide ~= nil then opts.collide else not decor
	part.CanQuery = if opts.query ~= nil then opts.query else not decor
	local transparency = opts.transparency or 0
	part.Transparency = transparency
	if opts.shadow ~= nil then
		part.CastShadow = opts.shadow
	else
		part.CastShadow = not decor and transparency < 0.5 and largest >= Config.SHADOW_MIN_EXTENT
	end
	if opts.reflectance then
		part.Reflectance = opts.reflectance
	end
	if opts.name then
		part.Name = opts.name
	end
	part.Parent = parent
	stats.parts += 1
end

-- Bloc. `cframe` = centre du bloc (LOCAL).
function Kit.part(parent: Instance, cframe: CFrame, size: Vector3, look: Look, options: PartOptions?): Part
	local part = Instance.new("Part")
	finishPart(part, parent, cframe, size, look, options)
	return part
end

-- Coin (WedgePart) : la pente descend vers -Z local, l'arête haute est à +Z local (arrière).
function Kit.wedge(parent: Instance, cframe: CFrame, size: Vector3, look: Look, options: PartOptions?): WedgePart
	local part = Instance.new("WedgePart")
	finishPart(part, parent, cframe, size, look, options)
	return part
end

function Kit.cornerWedge(parent: Instance, cframe: CFrame, size: Vector3, look: Look, options: PartOptions?): CornerWedgePart
	local part = Instance.new("CornerWedgePart")
	finishPart(part, parent, cframe, size, look, options)
	return part
end

-- Cylindre dont l'axe suit le X local de `cframe` (convention Roblox).
function Kit.cylinder(parent: Instance, cframe: CFrame, length: number, diameter: number, look: Look, options: PartOptions?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	finishPart(part, parent, cframe, Vector3.new(length, diameter, diameter), look, options)
	return part
end

-- Cylindre DEBOUT posé sur `baseCFrame` (le centre de sa face inférieure).
function Kit.column(parent: Instance, baseCFrame: CFrame, height: number, diameter: number, look: Look, options: PartOptions?): Part
	local cframe = baseCFrame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	return Kit.cylinder(parent, cframe, height, diameter, look, options)
end

function Kit.ball(parent: Instance, position: Vector3, diameter: number, look: Look, options: PartOptions?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	finishPart(part, parent, CFrame.new(position), Vector3.new(diameter, diameter, diameter), look, options)
	return part
end

-- Repère qui va de `from` à `to` (-Z local vers `to`), avec un "haut" stable même à la verticale.
local function segmentFrame(from: Vector3, to: Vector3): (CFrame, number)
	local delta = to - from
	local length = delta.Magnitude
	local middle = from + delta / 2
	if length < 1e-4 then
		return CFrame.new(middle), 0
	end
	local direction = delta / length
	local up = if math.abs(direction.Y) > 0.98 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(middle, middle + direction, up), length
end

-- Poutre (bloc) de `from` à `to` ; `width` = épaisseur latérale, `height` = épaisseur verticale.
function Kit.beam(parent: Instance, from: Vector3, to: Vector3, width: number, height: number, look: Look, options: PartOptions?): Part
	local frame, length = segmentFrame(from, to)
	return Kit.part(parent, frame, Vector3.new(width, height, math.max(length, 0.05)), look, options)
end

-- Tige cylindrique de `from` à `to` (corde, chaîne, tuyau).
function Kit.rod(parent: Instance, from: Vector3, to: Vector3, diameter: number, look: Look, options: PartOptions?): Part
	local frame, length = segmentFrame(from, to)
	return Kit.cylinder(parent, frame * CFrame.Angles(0, math.rad(90), 0), math.max(length, 0.05), diameter, look, options)
end

--------------------------------------------------------------------------------
-- Conteneurs
--------------------------------------------------------------------------------

-- Model nommé ; `pivot` (LOCAL) fixe son WorldPivot (sinon : centre de ses pièces).
function Kit.model(parent: Instance, name: string, pivot: CFrame?): Model
	local model = Instance.new("Model")
	model.Name = name
	if pivot then
		model.WorldPivot = ORIGIN_CFRAME * pivot
	end
	model.Parent = parent
	return model
end

-- Dossier `name` sous `parent` : le réutilise s'il existe, sinon le crée.
function Kit.folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--------------------------------------------------------------------------------
-- Marqueurs du contrat (ancres, interactables, dynamics, échos)
--------------------------------------------------------------------------------

local function invisibleMarker(name: string, cframe: CFrame, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = ORIGIN_CFRAME * cframe
	part.TopSurface = SMOOTH
	part.BottomSurface = SMOOTH
	return part
end

--[[
	Ancre du contrat (RegionConfig.ANCHORS / MechanismConfig.EXTRA_ANCHORS).
	`cframe` : position ET orientation (LookVector = direction du regard). Pour un personnage,
	utilisez Kit.standing(sol, cible) qui ajoute les 3 studs. `size` : seulement pour les ancres "volume".
	Les ancres d'ennemis reçoivent EnemyId / Group depuis WorldBuildConfig.ENEMY_SPAWNS.
]]
function Kit.anchor(anchorsFolder: Instance, id: string, cframe: CFrame, size: Vector3?): Part
	local part = invisibleMarker(id, cframe, size or DEFAULT_ANCHOR_SIZE)
	part:SetAttribute(RegionConfig.ANCHOR_ATTRIBUTE, id)
	local spawn = Config.ENEMY_SPAWNS[id]
	if spawn then
		part:SetAttribute(Config.ENEMY_ID_ATTRIBUTE, spawn.enemyId)
		part:SetAttribute(Config.ENEMY_GROUP_ATTRIBUTE, spawn.group)
	end
	CollectionService:AddTag(part, RegionConfig.ANCHOR_TAG)
	part.Parent = anchorsFolder
	return part
end

--[[
	Marque la Part à viser d'un objet interactif (tag "Interactable" + attribut InteractableId).
	Si la Part est dans un Model, elle est renommée "PromptPart". Une seule Part par identifiant.
]]
function Kit.tagInteractable(part: BasePart, id: string)
	part:SetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE, id)
	CollectionService:AddTag(part, RegionConfig.INTERACTABLE_TAG)
	part.CanQuery = true
	local parent = part.Parent
	if parent and parent:IsA("Model") then
		part.Name = "PromptPart"
	end
end

--[[
	Range un objet à états dans World.Dynamic avec l'attribut DynamicId (MechanismConfig.DYNAMICS).
	Construisez-le dans son état INITIAL. Un Model "slide" doit avoir un PrimaryPart (son pivot).
]]
function Kit.dynamic(dynamicFolder: Instance, instance: Instance, id: string)
	instance:SetAttribute(MechanismConfig.DYNAMIC_ATTRIBUTE, id)
	instance.Parent = dynamicFolder
end

-- Point de trajet d'écho : World.EchoPaths.<pathName>.<index> (Part invisible, posée AU SOL).
function Kit.echoPoint(echoPathsFolder: Instance, pathName: string, index: number, cframe: CFrame): Part
	local folder = Kit.folder(echoPathsFolder, pathName)
	local part = invisibleMarker(tostring(index), cframe, DEFAULT_ANCHOR_SIZE)
	part.Parent = folder
	return part
end

--------------------------------------------------------------------------------
-- Lumières et effets
--------------------------------------------------------------------------------

--[[
	Lumière budgétée (WorldBuildConfig.LIGHT_BUDGET pour toute la région, SHADOW_LIGHT_BUDGET avec ombres).
	Retourne nil quand le budget est épuisé : le décor doit rester lisible sans (Neon chaud).
]]
function Kit.light(parent: Instance, options: LightOptions?): Light?
	local opts: LightOptions = options or {}
	if stats.lights >= Config.LIGHT_BUDGET then
		stats.refusedLights += 1
		return nil
	end
	local kind = opts.kind or "point"
	local range = opts.range or 16
	-- Range n'existe que sur les classes concrètes (pas sur Light) : on le règle avant de généraliser.
	local light: Light
	if kind == "spot" then
		local spot = Instance.new("SpotLight")
		spot.Face = opts.face or Enum.NormalId.Front
		spot.Angle = opts.angle or 60
		spot.Range = range
		light = spot
	elseif kind == "surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Face = opts.face or Enum.NormalId.Front
		surface.Angle = opts.angle or 90
		surface.Range = range
		light = surface
	else
		local point = Instance.new("PointLight")
		point.Range = range
		light = point
	end
	light.Color = opts.color or Palette.colors.warmLight
	light.Brightness = opts.brightness or 1.2
	local wantsShadows = opts.shadows == true and stats.shadowLights < Config.SHADOW_LIGHT_BUDGET
	light.Shadows = wantsShadows
	light.Enabled = if opts.enabled ~= nil then opts.enabled else true
	light.Parent = parent
	stats.lights += 1
	if wantsShadows then
		stats.shadowLights += 1
	end
	return light
end

-- Feu natif (aucune texture). `enabled = false` pour un brasero éteint.
function Kit.fire(parent: Instance, options: FireOptions?): Fire
	local opts: FireOptions = options or {}
	local fire = Instance.new("Fire")
	fire.Size = opts.size or 4
	fire.Heat = opts.heat or 6
	fire.Color = opts.color or Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = opts.secondaryColor or Color3.fromRGB(120, 30, 10)
	fire.Enabled = if opts.enabled ~= nil then opts.enabled else true
	fire.Parent = parent
	return fire
end

-- Fumée native lente (cheminées, ruines qui couvent).
function Kit.smoke(parent: Instance, color: Color3?, opacity: number?, enabled: boolean?): Smoke
	local smoke = Instance.new("Smoke")
	smoke.Color = color or Palette.colors.smoke
	smoke.Opacity = opacity or 0.12
	smoke.RiseVelocity = 2
	smoke.Size = 4
	smoke.Enabled = if enabled ~= nil then enabled else true
	smoke.Parent = parent
	return smoke
end

-- Émetteur de particules avec la texture par défaut de Roblox (aucun asset ajouté).
function Kit.particles(parent: Instance, color: Color3, rate: number, enabled: boolean?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(1.5, 3)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new(0.15)
	emitter.Transparency = NumberSequence.new(0.3)
	emitter.Enabled = if enabled ~= nil then enabled else true
	emitter.Parent = parent
	return emitter
end

-- Texte peint sur une face d'une Part (SurfaceGui + TextLabel), pour panneaux et graffitis.
function Kit.surfaceText(part: BasePart, face: Enum.NormalId, text: string, options: TextOptions?): SurfaceGui
	local opts: TextOptions = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.pixelsPerStud or 40
	gui.LightInfluence = 1
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if opts.background then 0 else 1
	label.BackgroundColor3 = opts.background or Color3.new(0, 0, 0)
	label.TextColor3 = opts.color or Palette.colors.chalk
	label.TextTransparency = opts.transparency or 0
	label.Font = opts.font or Enum.Font.Antique
	label.TextScaled = true
	label.TextWrapped = true
	label.Rotation = opts.rotation or 0
	label.Text = text
	label.Parent = gui
	return gui
end

return table.freeze(Kit)
