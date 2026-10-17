--!strict
--[[
	VfxKit (ModuleScript, client)
	Boîte à outils des effets de magie « 3.0 » : des FORMES (pointes de cristal, éclats, sphères à
	couches, fragments en orbite, liens d'énergie) plutôt que des disques colorés. Utilisée par les
	modules de Client/Magic/Vfx (un par magie).

	Règles communes, garanties ici :
		- tout est local, ancré (ou soudé à une racine ancrée), sans collision, sans requête, sans
		  contact, sans ombre, et détruit tout seul (Debris) : rien ne reste dans le Workspace ;
		- aucune modification du terrain ni de la carte ;
		- niveau de détail : `detail(position)` vaut 1 près de la caméra, moins loin, et moitié moins
		  en « effets réduits » ; il baisse encore si beaucoup d'effets sont déjà à l'écran (budget
		  global : dix joueurs qui lancent leurs sorts en même temps restent lisibles) ;
		- les animations image par image (`animate`) se coupent seules à la fin, ou si leur pièce
		  disparaît, ou en cas d'erreur.

	Textures de particules : uniquement celles LIVRÉES AVEC ROBLOX et utilisées par ses effets
	intégrés (Fire, Sparkles, Smoke, Explosion, ForceField), présentes sur tous les clients.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MagicFx = require(script.Parent:WaitForChild("MagicFx") :: ModuleScript)

local VfxKit = {}

VfxKit.TEXTURES = table.freeze({
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	fireSparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	implosion = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
})

local random = MagicFx.random
VfxKit.random = random

local NEAR_DISTANCE = 90 -- studs : détail complet en deçà
local FAR_DISTANCE = 200 -- studs : détail minimal au-delà
local BUDGET_SOFT = 220 -- objets d'effet déjà présents : au-delà, détail divisé par deux
local BUDGET_HARD = 420 -- au-delà, détail minimal

--------------------------------------------------------------------------------
-- Niveau de détail et budget
--------------------------------------------------------------------------------

local function liveObjects(): number
	local folder = MagicFx.getFolder()
	return #folder:GetChildren()
end

-- 0 < detail <= 1 : multiplicateur des quantités (pièces décoratives, particules).
function VfxKit.detail(position: Vector3?): number
	local factor = if MagicFx.reduced() then 0.5 else 1
	local camera = workspace.CurrentCamera
	if position and camera then
		local distance = (camera.CFrame.Position - position).Magnitude
		if distance > FAR_DISTANCE then
			factor *= 0.25
		elseif distance > NEAR_DISTANCE then
			factor *= 0.6
		end
	end
	local live = liveObjects()
	if live > BUDGET_HARD then
		factor *= 0.25
	elseif live > BUDGET_SOFT then
		factor *= 0.5
	end
	return factor
end

-- Quantité ajustée au détail, jamais sous `minimum` (1 par défaut).
function VfxKit.count(value: number, detail: number, minimum: number?): number
	return math.max(minimum or 1, math.floor(value * detail + 0.5))
end

-- Faut-il ajouter les détails coûteux (lumières, couches supplémentaires) ?
function VfxKit.rich(detail: number): boolean
	return detail >= 0.5
end

--------------------------------------------------------------------------------
-- Pièces
--------------------------------------------------------------------------------

local function decorate(part: BasePart, color: Color3, material: Enum.Material)
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Pièce racine : ancrée, rangée dans le dossier des effets, détruite après `lifetime`.
function VfxKit.part(name: string, size: Vector3, color: Color3, material: Enum.Material, lifetime: number, shape: Enum.PartType?): Part
	local part = MagicFx.part(name, shape or Enum.PartType.Block, size, color, material, lifetime)
	part.Parent = MagicFx.getFolder()
	return part
end

-- Pièce soudée à `root` (suit ses déplacements) ; détruite avec elle.
function VfxKit.attach(root: BasePart, class: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Size = size
	decorate(part, color, material)
	part.Anchored = false
	part.Massless = true
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = root
	return part
end

function VfxKit.tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	TweenService:Create(instance, TweenInfo.new(math.max(duration, 0.01), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
end

-- Fondu de toutes les pièces d'un groupe (racine comprise), vers la transparence totale.
function VfxKit.fadeGroup(root: BasePart, duration: number)
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			VfxKit.tween(item, duration, { Transparency = 1 })
		end
	end
	if root.Transparency < 1 then
		VfxKit.tween(root, duration, { Transparency = 1 })
	end
end

-- Animation image par image ; s'arrête à la fin (alpha = 1), si `guard` disparaît, ou sur erreur.
function VfxKit.animate(duration: number, step: (alpha: number, elapsed: number, dt: number) -> (), guard: Instance?, onDone: (() -> ())?): RBXScriptConnection
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.min(elapsed / math.max(duration, 1e-3), 1)
		local alive = guard == nil or guard.Parent ~= nil
		local ok = alive and pcall(step, alpha, elapsed, dt)
		if alpha >= 1 or not ok then
			connection:Disconnect()
			if onDone then
				onDone()
			end
		end
	end)
	return connection
end

--------------------------------------------------------------------------------
-- Particules et lumières
--------------------------------------------------------------------------------

-- Émetteur réglé par une table de propriétés ; `rate` est ajusté au détail par l'appelant.
function VfxKit.emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 1
	emitter.SpreadAngle = Vector2.new(180, 180)
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

-- Gerbe ponctuelle à `position` (porteur invisible détruit tout seul).
function VfxKit.burst(position: Vector3, amount: number, props: { [string]: any })
	local anchor = VfxKit.part("Burst", Vector3.one * 0.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 3)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	local emitter = VfxKit.emitter(anchor, props)
	emitter.Enabled = false
	task.delay(0.03, function()
		emitter:Emit(math.max(1, math.floor(amount)))
	end)
end

-- Lumière brève (montée instantanée, extinction en `duration`). Ignorée si le détail est bas.
function VfxKit.flash(position: Vector3, color: Color3, range: number, brightness: number, duration: number, detail: number)
	if not VfxKit.rich(detail) then
		return
	end
	local anchor = VfxKit.part("Flash", Vector3.one * 0.2, color, Enum.Material.SmoothPlastic, duration + 0.2)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = anchor
	VfxKit.tween(light, duration, { Brightness = 0 })
end

-- Lien d'énergie (Beam) entre deux attachements, avec une courbe ; détruit après `lifetime`.
function VfxKit.tether(from: Attachment, to: Attachment, color: ColorSequence, width0: number, width1: number, lifetime: number, curve: number?): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = color
	beam.LightEmission = 1
	beam.Width0 = width0
	beam.Width1 = width1
	beam.Segments = 16
	beam.FaceCamera = true
	beam.CurveSize0 = curve or 0
	beam.CurveSize1 = -(curve or 0)
	beam.Transparency = NumberSequence.new(0.1, 0.4)
	beam.Parent = from
	Debris:AddItem(beam, lifetime)
	return beam
end

-- Attachement porté par une pièce invisible ancrée (point fixe du monde).
function VfxKit.point(position: Vector3, lifetime: number): Attachment
	local anchor = VfxKit.part("Point", Vector3.one * 0.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, lifetime)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	return attachment
end

--------------------------------------------------------------------------------
-- Formes
--------------------------------------------------------------------------------

-- Rotation qui pose un cube sur une pointe (diagonale du cube vers le haut) : un diamant.
local DIAMOND = CFrame.fromAxisAngle(Vector3.new(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))
VfxKit.DIAMOND = DIAMOND

--[[
	Cristal soudé à `root` : une colonne de verre à section en losange, coiffée d'une pyramide (deux
	paires de coins croisées), avec un cœur lumineux facultatif. `base` : repère de la BASE du
	cristal relatif à la racine ; son axe Y est la direction de la pointe.
	Coins Roblox : la face inclinée est la face avant (-Z), la face verticale à l'arrière (+Z).
]]
function VfxKit.attachCrystal(root: BasePart, base: CFrame, height: number, width: number, color: Color3, transparency: number, core: Color3?)
	local tipHeight = math.min(width * 1.7, height * 0.5)
	local bodyHeight = math.max(height - tipHeight, 0.1)
	local spin = CFrame.Angles(0, math.rad(45), 0)
	local body = VfxKit.attach(root, "Part", "Body", Vector3.new(width, bodyHeight, width), base * CFrame.new(0, bodyHeight / 2, 0) * spin, color, Enum.Material.Glass)
	body.Transparency = transparency
	body.Reflectance = 0.08
	-- Pyramide : chaque arête de faîte est faite de deux coins dos à dos.
	local top = base * CFrame.new(0, bodyHeight + tipHeight / 2, 0) * spin
	for _, yaw in { 0, 90 } do
		local ridge = top * CFrame.Angles(0, math.rad(yaw), 0)
		local front = VfxKit.attach(root, "WedgePart", "Tip", Vector3.new(width, tipHeight, width / 2), ridge * CFrame.new(0, 0, -width / 4), color, Enum.Material.Glass)
		local back = VfxKit.attach(root, "WedgePart", "Tip", Vector3.new(width, tipHeight, width / 2), ridge * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Glass)
		front.Transparency = transparency
		back.Transparency = transparency
	end
	if core then
		local heart = VfxKit.attach(root, "Part", "Core", Vector3.new(width * 0.3, bodyHeight * 0.85, width * 0.3), base * CFrame.new(0, bodyHeight / 2, 0), core, Enum.Material.Neon)
		heart.Transparency = 0.35
	end
end

-- Pointe de cristal autonome. Pivot : la base (axe Y vers la pointe). Rend sa racine invisible.
function VfxKit.spire(pivot: CFrame, height: number, width: number, color: Color3, lifetime: number, core: Color3?): Part
	local root = VfxKit.part("Spire", Vector3.one * 0.2, color, Enum.Material.SmoothPlastic, lifetime)
	root.Transparency = 1
	root.CFrame = pivot
	VfxKit.attachCrystal(root, CFrame.new(), height, width, color, 0.22, core)
	return root
end

-- Fait jaillir une pointe du sol : elle part enfouie et monte de toute sa hauteur en `rise` s.
function VfxKit.erupt(root: BasePart, height: number, rise: number)
	local final = root.CFrame
	local up = root.CFrame.UpVector
	root.CFrame = final - up * height
	VfxKit.tween(root, rise, { CFrame = final }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Éclats projetés : petits fragments lancés depuis `origin`, retombant sous la gravité, puis fondus.
function VfxKit.shatter(origin: Vector3, amount: number, color: Color3, material: Enum.Material, size: number, speed: number, lifetime: number)
	local shards: { { part: Part, velocity: Vector3, spin: CFrame } } = {}
	for _ = 1, amount do
		local shard = VfxKit.part("Shard", Vector3.new(size * 0.45, size * 0.45, size * random:NextNumber(0.8, 1.6)), color, material, lifetime + 0.2)
		shard.Transparency = if material == Enum.Material.Glass then 0.2 else 0
		shard.CFrame = CFrame.new(origin) * CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), 0)
		local direction = random:NextUnitVector()
		direction = Vector3.new(direction.X, math.abs(direction.Y) * 0.8 + 0.3, direction.Z).Unit
		table.insert(shards, {
			part = shard,
			velocity = direction * speed * random:NextNumber(0.5, 1),
			spin = CFrame.Angles(random:NextNumber(-8, 8), random:NextNumber(-8, 8), 0),
		})
		VfxKit.tween(shard, lifetime, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	local gravity = Vector3.new(0, -workspace.Gravity * 0.35, 0)
	VfxKit.animate(lifetime, function(_alpha: number, _elapsed: number, dt: number)
		for _, shard in shards do
			if shard.part.Parent then
				shard.velocity += gravity * dt
				local cf = shard.part.CFrame
				shard.part.CFrame = (cf + shard.velocity * dt) * CFrame.new():Lerp(shard.spin, dt)
			end
		end
	end)
end

-- Sol qui se couvre de givre : plaques de glace fines et irrégulières, de proche en proche.
function VfxKit.frostSpread(center: Vector3, radius: number, color: Color3, amount: number, spread: number, hold: number)
	for index = 1, amount do
		local ring = math.sqrt(index / amount)
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = ring * radius * random:NextNumber(0.7, 1)
		local position = center + Vector3.new(math.cos(angle) * distance, 0.04 + index * 0.002, math.sin(angle) * distance)
		local length = random:NextNumber(1.2, 2.6) * math.max(radius / 6, 0.6)
		local plate = VfxKit.part("Frost", Vector3.new(0.05, 0.05, 0.05), color, Enum.Material.Ice, spread + hold + 1.6)
		plate.Transparency = 0.25
		plate.Reflectance = 0.15
		plate.CFrame = CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		task.delay(spread * ring, function()
			if plate.Parent then
				VfxKit.tween(plate, 0.25, { Size = Vector3.new(length * random:NextNumber(0.35, 0.7), 0.06, length) })
			end
		end)
		task.delay(spread + hold + random:NextNumber(0, 0.3), function()
			if plate.Parent then
				VfxKit.tween(plate, 1.2, { Transparency = 1 }, Enum.EasingStyle.Sine)
			end
		end)
	end
end

-- Position de la main droite d'un personnage (ou de son centre).
function VfxKit.handOf(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return MagicFx.rootOf(character)
end

-- Fait suivre la main (ou une pièce) à une pièce ancrée pendant `duration` s.
function VfxKit.follow(part: BasePart, target: BasePart, offset: CFrame, duration: number)
	VfxKit.animate(duration, function()
		if target.Parent then
			part.CFrame = target.CFrame * offset
		end
	end, part)
end

VfxKit.groundBelow = MagicFx.groundBelow
VfxKit.rootOf = MagicFx.rootOf
VfxKit.folder = MagicFx.getFolder

return VfxKit
