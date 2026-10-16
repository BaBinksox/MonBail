--!strict
--[[
	CombatEffects
	Tous les effets visuels du combat, joués localement par chaque client :
		- playBladeTrail  : allume la traînée de la lame pendant la fenêtre de frappe (plus large si lourd) ;
		- playHitImpact   : flash de la cible + gerbe d'étincelles ;
		- playSwordHit    : coup d'épée qui porte = impact + arrêt sur image (durée propre à chaque
		                    coup) + légère secousse de caméra ;
		- playHitResult   : ce que seul le serveur sait : coup BLOQUÉ par une garde (étincelles
		                    métalliques, son mat) ou posture BRISÉE (onde, éclat, son sourd) ;
		- setChargeGlow / playChargeReady : lueur de la lame pendant l'attaque chargée ;
		- playPlungeImpact : onde au sol de l'attaque plongeante ;
		- playUltimate    : le pouvoir ultime, aux couleurs de la Magie Innée du lanceur
		                    (arrêt sur image, onde de choc, flash, secousse).
	Mode « effets réduits » : secousses à 30 %, gerbes de particules réduites de moitié.

	Rien ici n'a d'effet sur le jeu : pas de dégâts, pas de collision. Toutes les pièces créées
	sont locales (invisibles pour le serveur et les autres joueurs), ancrées, intangibles,
	et se détruisent toutes seules. Particules et lumières sont générées par script, sans asset.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat")
local Config = require(sharedFolder:WaitForChild("CombatConfig") :: ModuleScript)
local ClientSettings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local CharacterAnimator = require(script.Parent.Parent:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)

local REDUCED_SHAKE = 0.3 -- « effets réduits » : secousses de caméra à 30 %

-- Palette ----------------------------------------------------------------------
-- (Les couleurs d'un ultime ne sont pas ici : elles viennent de la palette de la magie du lanceur.)
local COLOR_WHITE = Color3.new(1, 1, 1)

-- Textures de particules livrées avec le client Roblox (aucun asset à importer).
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Impact d'épée ----------------------------------------------------------------
local HIT_FLASH_DURATION = 0.2
local HIT_SPARK_COUNT = 14
local HIT_SHAKE_DURATION = 0.15 -- secousse très courte...
local HIT_SHAKE_AMPLITUDE = 0.22 -- ...et légère (l'ultime monte à SHAKE_AMPLITUDE)
local HEAVY_SHAKE_AMPLITUDE = 0.45 -- coup final, frappe chargée, riposte
local BLOCKED_SPARK_COLOR = Color3.fromRGB(255, 196, 120) -- métal contre pierre
local BREAK_COLOR = Color3.fromRGB(255, 226, 150) -- posture brisée : éclat doré
local CHARGE_COLOR_LOW = Color3.fromRGB(190, 200, 255)
local CHARGE_COLOR_FULL = Color3.fromRGB(255, 240, 200)
local TRAIL_HEAVY_WIDTH_SCALE = 1.6 -- traînée plus ample pour les coups lourds

-- Ultime -----------------------------------------------------------------------
local CORE_SIZE = 11 -- diamètre de la sphère de vide à la fin de l'arrêt sur image
local CORE_COLLAPSE_DURATION = 0.1
local SHOCKWAVE_DURATION = 0.55
local GROUND_RING_DURATION = 0.7
local PILLAR_HEIGHT = 90
local PILLAR_DURATION = 0.5
local LIGHT_DURATION = 0.8
local FLASH_FADE_DURATION = 0.9
local SHAKE_DURATION = 0.9
local SHAKE_AMPLITUDE = 1.6 -- studs de décalage de caméra au plus fort
local SHAKE_ROLL = 4 -- degrés de roulis au plus fort
local FOV_PUNCH = 22 -- degrés ajoutés au champ de vision au moment de l'explosion
local FOV_RECOVER_DURATION = 0.6
-- Un spectateur ressent l'ultime à pleine force dans son rayon, puis de moins en moins jusqu'à 3 rayons.
local FALLOFF_RADIUS_FACTOR = 3

type ScreenLook = { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 }

local NEUTRAL_LOOK: ScreenLook = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = COLOR_WHITE }
-- Arrêt sur image : noir et blanc brutal, façon "impact frame" d'anime.
local IMPACT_FRAME_LOOK: ScreenLook = { Brightness = -0.12, Contrast = 1, Saturation = -1, TintColor = COLOR_WHITE }
-- Explosion : écran brûlé de blanc violet.
local FLASH_LOOK: ScreenLook = { Brightness = 0.9, Contrast = 0.5, Saturation = 0.4, TintColor = COLOR_WHITE }

local random = Random.new()

local CombatEffects = {}

--------------------------------------------------------------------------------
-- Briques de base
--------------------------------------------------------------------------------

local effectsFolder: Folder? = nil

local function getEffectsFolder(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "CombatEffects"
	folder.Parent = workspace
	effectsFolder = folder
	return folder
end

local function tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local tweenInfo = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local newTween = TweenService:Create(instance, tweenInfo, goal)
	newTween:Play()
	return newTween
end

-- Pièce purement décorative : ancrée, intangible, détruite au bout de `lifetime` secondes.
local function newEffectPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	Debris:AddItem(part, lifetime)
	return part
end

-- Point invisible dans le monde, support des particules et des lumières.
local function newAnchorPoint(position: Vector3, lifetime: number): Part
	local anchor = newEffectPart("EffectAnchor", Enum.PartType.Block, Vector3.one * 0.2, COLOR_WHITE, lifetime)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = getEffectsFolder()
	return anchor
end

-- Projette `count` particules d'un coup depuis `position`. `configure` règle l'émetteur.
local function emitBurst(position: Vector3, count: number, maxLifetime: number, configure: (ParticleEmitter) -> ())
	local anchor = newAnchorPoint(position, maxLifetime + 0.5)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false -- pas d'émission continue : uniquement la gerbe ci-dessous
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(maxLifetime * 0.5, maxLifetime)
	configure(emitter)
	emitter.Parent = anchor

	-- Un émetteur tout juste créé n'émet rien dans la même frame : on attend la suivante.
	task.delay(0.03, function()
		emitter:Emit(count)
	end)
end

-- Sol sous `origin` (pour poser l'anneau de l'onde de choc), ou une estimation s'il n'y en a pas.
local function findGroundPosition(origin: Vector3, ignore: { Instance }): Vector3
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(origin, Vector3.new(0, -20, 0), raycastParams)
	return if result then result.Position else origin - Vector3.new(0, 3, 0)
end

--------------------------------------------------------------------------------
-- Écran (ColorCorrection locale)
--------------------------------------------------------------------------------

local screenCorrection: ColorCorrectionEffect? = nil
local screenTween: Tween? = nil

local function getScreenCorrection(): ColorCorrectionEffect
	if screenCorrection and screenCorrection.Parent then
		return screenCorrection
	end
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "CombatColorCorrection"
	correction.Parent = Lighting
	screenCorrection = correction
	return correction
end

-- Rendu intermédiaire entre l'image normale (intensity = 0) et `look` (intensity = 1).
local function blendLook(look: ScreenLook, intensity: number): ScreenLook
	return {
		Brightness = look.Brightness * intensity,
		Contrast = look.Contrast * intensity,
		Saturation = look.Saturation * intensity,
		TintColor = COLOR_WHITE:Lerp(look.TintColor, intensity),
	}
end

-- Applique `look` à l'écran : instantanément si duration = 0, sinon en fondu.
local function setScreenLook(look: ScreenLook, duration: number)
	local correction = getScreenCorrection()
	if screenTween then
		screenTween:Cancel()
		screenTween = nil
	end

	if duration <= 0 then
		correction.Brightness = look.Brightness
		correction.Contrast = look.Contrast
		correction.Saturation = look.Saturation
		correction.TintColor = look.TintColor
	else
		screenTween = tween(correction, duration, look :: any, Enum.EasingStyle.Sine)
	end
end

--------------------------------------------------------------------------------
-- Caméra
--------------------------------------------------------------------------------

local SHAKE_RENDER_STEP = "CombatCameraShake"

local shakeStartClock = 0
local shakeDuration = 0
local shakeAmplitude = 0
local isShakeBound = false

-- S'exécute juste après la caméra par défaut, qui recalcule sa position à chaque frame :
-- le décalage ajouté ici ne s'accumule donc pas d'une frame à l'autre.
local function updateShake()
	local elapsed = os.clock() - shakeStartClock
	local camera = workspace.CurrentCamera
	if elapsed >= shakeDuration or camera == nil then
		RunService:UnbindFromRenderStep(SHAKE_RENDER_STEP)
		isShakeBound = false
		return
	end

	local strength = (1 - elapsed / shakeDuration) ^ 2 -- violent au début, s'éteint vite
	local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0) * shakeAmplitude * strength
	local roll = math.rad(random:NextNumber(-1, 1) * SHAKE_ROLL * strength * (shakeAmplitude / SHAKE_AMPLITUDE))
	camera.CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, roll)
end

local function shakeCamera(duration: number, amplitude: number)
	if ClientSettings.isReducedEffects() then
		amplitude *= REDUCED_SHAKE
	end
	if amplitude <= 0 then
		return
	end

	-- Une secousse plus forte est peut-être encore en cours (ultime) : un petit coup ne l'écrase pas.
	if isShakeBound then
		local remaining = math.max(1 - (os.clock() - shakeStartClock) / shakeDuration, 0)
		if amplitude < shakeAmplitude * remaining ^ 2 then
			return
		end
	end

	shakeStartClock = os.clock()
	shakeDuration = duration
	shakeAmplitude = amplitude

	if not isShakeBound then
		isShakeBound = true
		RunService:BindToRenderStep(SHAKE_RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, updateShake)
	end
end

local fovTween: Tween? = nil
local restingFieldOfView = 70

-- Élargit d'un coup le champ de vision, puis le laisse revenir : l'image "recule" sous le souffle.
local function punchFieldOfView(extraDegrees: number)
	local camera = workspace.CurrentCamera
	if camera == nil or extraDegrees <= 0 then
		return
	end

	if fovTween then
		fovTween:Cancel() -- un coup précédent n'était pas fini : on repart de la même valeur de repos
	else
		restingFieldOfView = camera.FieldOfView
	end

	camera.FieldOfView = restingFieldOfView + extraDegrees
	local recoverTween = tween(camera, FOV_RECOVER_DURATION, { FieldOfView = restingFieldOfView })
	fovTween = recoverTween
	recoverTween.Completed:Once(function()
		if fovTween == recoverTween then
			fovTween = nil
		end
	end)
end

-- Force (0..1) avec laquelle ce client ressent un effet centré sur `origin` et de rayon `radius`.
local function getIntensity(origin: Vector3, radius: number): number
	local camera = workspace.CurrentCamera
	if camera == nil then
		return 0
	end
	local distance = (camera.CFrame.Position - origin).Magnitude
	local falloffEnd = radius * FALLOFF_RADIUS_FACTOR
	return math.clamp((falloffEnd - distance) / (falloffEnd - radius), 0, 1)
end

--------------------------------------------------------------------------------
-- Arrêt sur image
--------------------------------------------------------------------------------

-- Fige les animations en cours de `characters`. Retourne la fonction qui les relance.
local function freezeAnimations(characters: { Model }): () -> ()
	local frozenTracks: { { track: AnimationTrack, speed: number } } = {}

	for _, character in characters do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				-- Une piste déjà à l'arrêt est figée par un autre effet : on la lui laisse,
				-- sinon on la "relancerait" à vitesse 0 et elle resterait bloquée.
				if track.Speed ~= 0 then
					table.insert(frozenTracks, { track = track, speed = track.Speed })
					track:AdjustSpeed(0)
				end
			end
		end
	end

	return function()
		for _, frozen in frozenTracks do
			if frozen.track.IsPlaying then
				frozen.track:AdjustSpeed(frozen.speed)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- API publique : épée
--------------------------------------------------------------------------------

local function particleCount(count: number): number
	return if ClientSettings.isReducedEffects() then math.max(1, math.floor(count / 2)) else count
end

-- Allume la traînée de lame de `sword` pendant `duration` secondes (la fenêtre de frappe).
-- `heavy` : traînée plus ample et plus durable (coup final, frappe chargée, riposte, plongée).
function CombatEffects.playBladeTrail(sword: Instance, duration: number, heavy: boolean?)
	local trail = sword:FindFirstChild(Config.BLADE_TRAIL_NAME, true)
	if trail == nil or not trail:IsA("Trail") then
		return
	end

	local baseWidth = trail:GetAttribute("BaseWidthScale")
	if type(baseWidth) ~= "number" then
		local current = trail.WidthScale
		local scale = if typeof(current) == "NumberSequence" then current.Keypoints[1].Value else 1
		trail:SetAttribute("BaseWidthScale", scale)
		baseWidth = scale
	end
	local width = (baseWidth :: number) * (if heavy then TRAIL_HEAVY_WIDTH_SCALE else 1)
	trail.WidthScale = NumberSequence.new(width, 0)
	trail.Enabled = true
	task.delay(duration, function()
		trail.Enabled = false -- le sillage déjà tracé finit de s'estomper tout seul
	end)
end

-- Impact sur `target` : flash du personnage et gerbe d'étincelles.
-- `position` : point d'impact précis s'il est connu, sinon le centre de la cible.
function CombatEffects.playHitImpact(target: Model, position: Vector3?, color: Color3?, sparkCount: number?)
	local flashColor = color or COLOR_WHITE

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = flashColor
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.Parent = target
	tween(highlight, HIT_FLASH_DURATION, { FillTransparency = 1 })
	Debris:AddItem(highlight, HIT_FLASH_DURATION)

	emitBurst(position or target:GetPivot().Position, particleCount(sparkCount or HIT_SPARK_COUNT), 0.35, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.Color = ColorSequence.new(COLOR_WHITE, flashColor)
		emitter.Speed = NumberRange.new(12, 28)
		emitter.Drag = 4
		emitter.Size = NumberSequence.new(0.5, 0)
		emitter.Transparency = NumberSequence.new(0, 1)
	end)
end

-- Fige les poses (procédurales et clips) de `characters` pendant `seconds`.
local function hitStop(characters: { Model }, seconds: number)
	if seconds <= 0 then
		return
	end
	for _, character in characters do
		local animator = CharacterAnimator.find(character)
		if animator then
			animator:freeze(seconds)
		end
	end
	local resumeAnimations = freezeAnimations(characters)
	task.delay(seconds, resumeAnimations)
end

export type HitOptions = {
	hitStop: number?, -- arrêt sur image (s) ; défaut : HIT_STOP_DURATION
	heavy: boolean?, -- coup lourd : secousse et gerbe plus fortes
}

--[[
	Coup d'épée qui porte : impact, arrêt sur image et, si demandé, légère secousse de caméra.
	L'arrêt sur image fige les poses de l'attaquant et de la cible : la lame « accroche » un instant
	dans la cible avant de finir sa course.
	`shouldShake` : true pour le client qui donne le coup ou qui le reçoit.
]]
function CombatEffects.playSwordHit(attacker: Model?, target: Model, position: Vector3?, shouldShake: boolean, options: HitOptions?)
	local opts: HitOptions = options or {}
	local isHeavy = opts.heavy == true
	CombatEffects.playHitImpact(target, position, nil, if isHeavy then HIT_SPARK_COUNT * 2 else HIT_SPARK_COUNT)
	hitStop(if attacker then { attacker, target } else { target }, opts.hitStop or Config.HIT_STOP_DURATION)

	local root = target:FindFirstChild("HumanoidRootPart")
	SfxPlayer.play("swordHit", if root and root:IsA("BasePart") then root else position, { pitch = if isHeavy then 0.85 else 1 })
	if shouldShake then
		shakeCamera(HIT_SHAKE_DURATION * (if isHeavy then 1.6 else 1), if isHeavy then HEAVY_SHAKE_AMPLITUDE else HIT_SHAKE_AMPLITUDE)
	end
end

-- Résultat que seul le serveur connaît : "blocked" (garde) ou "broken" (posture brisée).
function CombatEffects.playHitResult(target: Model, result: string, isAttacker: boolean)
	local position = target:GetPivot().Position
	if result == "blocked" then
		emitBurst(position, particleCount(18), 0.3, function(emitter: ParticleEmitter)
			emitter.Texture = SPARK_TEXTURE
			emitter.Color = ColorSequence.new(COLOR_WHITE, BLOCKED_SPARK_COLOR)
			emitter.Speed = NumberRange.new(16, 34)
			emitter.Drag = 6
			emitter.Acceleration = Vector3.new(0, -40, 0)
			emitter.Size = NumberSequence.new(0.35, 0)
			emitter.Transparency = NumberSequence.new(0, 1)
		end)
		SfxPlayer.play("swordBlocked", position)
		if isAttacker then
			-- Le bras de l'attaquant « rebondit » : un court sursaut de son personnage.
			local localCharacter = Players.LocalPlayer.Character
			if localCharacter then
				CharacterAnimator.get(localCharacter, true):play("hit_react", { speed = 1.6 })
			end
			shakeCamera(0.12, HIT_SHAKE_AMPLITUDE * 0.6)
		end
	elseif result == "broken" then
		CombatEffects.playHitImpact(target, position, BREAK_COLOR, HIT_SPARK_COUNT * 2)
		local folder = getEffectsFolder()
		local ring = newEffectPart("PostureBreakRing", Enum.PartType.Cylinder, Vector3.new(0.2, 3, 3), BREAK_COLOR, 0.5)
		ring.Transparency = 0.2
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		tween(ring, 0.45, { Size = Vector3.new(0.2, 14, 14), Transparency = 1 }, Enum.EasingStyle.Quart)
		SfxPlayer.play("postureBreak", position)
		if isAttacker then
			shakeCamera(0.3, HEAVY_SHAKE_AMPLITUDE)
		end
	end
end

-- Lueur de la lame pendant l'attaque chargée. `ratio` : 0..1, nil = éteinte.
function CombatEffects.setChargeGlow(character: Model, ratio: number?)
	local sword = character:FindFirstChild(Config.SWORD_NAME)
	local bladeEnd = sword and sword:FindFirstChild(Config.BLADE_END_NAME, true)
	if bladeEnd == nil or not bladeEnd:IsA("Attachment") then
		return
	end
	local light = bladeEnd:FindFirstChild("ChargeGlow")
	if ratio == nil then
		if light then
			light:Destroy()
		end
		return
	end
	if light == nil then
		local newLight = Instance.new("PointLight")
		newLight.Name = "ChargeGlow"
		newLight.Range = 6
		newLight.Shadows = false
		newLight.Parent = bladeEnd
		light = newLight
	end
	if light and light:IsA("PointLight") then
		light.Color = CHARGE_COLOR_LOW:Lerp(CHARGE_COLOR_FULL, ratio)
		light.Brightness = 0.5 + ratio * 2.5
		light.Range = 5 + ratio * 5
	end
end

-- Charge pleine : un éclat bref sur la lame.
function CombatEffects.playChargeReady(character: Model)
	local sword = character:FindFirstChild(Config.SWORD_NAME)
	local bladeEnd = sword and sword:FindFirstChild(Config.BLADE_END_NAME, true)
	if bladeEnd and bladeEnd:IsA("Attachment") then
		emitBurst(bladeEnd.WorldPosition, particleCount(10), 0.35, function(emitter: ParticleEmitter)
			emitter.Texture = SPARK_TEXTURE
			emitter.Color = ColorSequence.new(CHARGE_COLOR_FULL)
			emitter.Speed = NumberRange.new(4, 9)
			emitter.Size = NumberSequence.new(0.6, 0)
			emitter.Transparency = NumberSequence.new(0, 1)
		end)
	end
end

-- Atterrissage de l'attaque plongeante : anneau au sol, poussière, secousse.
function CombatEffects.playPlungeImpact(_character: Model, groundPosition: Vector3)
	local folder = getEffectsFolder()
	local diameter = (Config.HITBOX_SIZE.X + Config.PLUNGE.widthBonus) * 1.2
	local ring = newEffectPart("PlungeRing", Enum.PartType.Cylinder, Vector3.new(0.3, 2, 2), CHARGE_COLOR_LOW, 0.6)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(groundPosition + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	tween(ring, 0.5, { Size = Vector3.new(0.3, diameter, diameter), Transparency = 1 }, Enum.EasingStyle.Quart)
	emitBurst(groundPosition + Vector3.new(0, 0.5, 0), particleCount(24), 0.9, function(emitter: ParticleEmitter)
		emitter.Texture = SMOKE_TEXTURE
		emitter.LightEmission = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(170, 160, 150))
		emitter.SpreadAngle = Vector2.new(80, 10)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.Drag = 3
		emitter.Size = NumberSequence.new(1.5, 4)
		emitter.Transparency = NumberSequence.new(0.4, 1)
	end)
	shakeCamera(0.25, HEAVY_SHAKE_AMPLITUDE)
end

--------------------------------------------------------------------------------
-- API publique : pouvoir ultime
--------------------------------------------------------------------------------
-- Les couleurs, le rayon et le nom viennent de la Magie Innée du lanceur (MagicConfig) :
-- `magic` est une entrée de MagicConfig.MAGICS, `magic.palette` ses trois couleurs.

-- Phase 2 de l'ultime : tout ce qui part de `origin` au moment de l'explosion.
local function spawnEruption(origin: Vector3, groundPosition: Vector3, radius: number, palette: any)
	local folder = getEffectsFolder()
	local diameter = radius * 2

	-- Onde de choc : une sphère qui enfle jusqu'au rayon réel de l'attaque en se dissipant.
	local shockwave = newEffectPart("Shockwave", Enum.PartType.Ball, Vector3.one * CORE_SIZE, palette.glow, SHOCKWAVE_DURATION)
	shockwave.Material = Enum.Material.ForceField
	shockwave.CFrame = CFrame.new(origin)
	shockwave.Parent = folder
	tween(shockwave, SHOCKWAVE_DURATION, { Size = Vector3.one * diameter, Transparency = 1 }, Enum.EasingStyle.Quart)

	-- Anneau au sol : un disque plat qui court jusqu'au bord de la zone.
	-- (L'axe d'un cylindre Roblox est X : on le redresse pour le coucher au sol.)
	local ring = newEffectPart("GroundRing", Enum.PartType.Cylinder, Vector3.new(0.3, 4, 4), palette.main, GROUND_RING_DURATION)
	ring.Transparency = 0.15
	ring.CFrame = CFrame.new(groundPosition + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	tween(ring, GROUND_RING_DURATION, { Size = Vector3.new(0.3, diameter, diameter), Transparency = 1 }, Enum.EasingStyle.Quart)

	-- Colonne de lumière : un trait vertical qui s'élargit et s'efface.
	local pillar = newEffectPart("Pillar", Enum.PartType.Cylinder, Vector3.new(PILLAR_HEIGHT, 3, 3), palette.glow, PILLAR_DURATION)
	pillar.Transparency = 0.1
	pillar.CFrame = CFrame.new(groundPosition + Vector3.new(0, PILLAR_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = folder
	tween(pillar, PILLAR_DURATION, { Size = Vector3.new(PILLAR_HEIGHT, 14, 14), Transparency = 1 })

	-- Éclats lumineux projetés dans toutes les directions.
	emitBurst(origin, 160, 0.7, function(emitter: ParticleEmitter)
		emitter.Texture = SPARK_TEXTURE
		emitter.Color = ColorSequence.new(COLOR_WHITE, palette.main)
		emitter.Speed = NumberRange.new(radius * 1.5, radius * 3.5)
		emitter.Drag = 3
		emitter.Size = NumberSequence.new(2.2, 0)
		emitter.Transparency = NumberSequence.new(0, 1)
	end)

	-- Volutes de matière sombre, plus lentes, qui restent un instant après l'éclair.
	emitBurst(origin, 45, 1.4, function(emitter: ParticleEmitter)
		emitter.Texture = SMOKE_TEXTURE
		emitter.LightEmission = 0
		emitter.Color = ColorSequence.new(palette.main, palette.void)
		emitter.Speed = NumberRange.new(radius * 0.4, radius * 1.1)
		emitter.Drag = 2
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.Size = NumberSequence.new(4, 12)
		emitter.Transparency = NumberSequence.new(0.35, 1)
	end)

	-- Éclair : une lumière qui éclaire réellement le décor et les personnages.
	local lightAnchor = newAnchorPoint(origin, LIGHT_DURATION)
	local light = Instance.new("PointLight")
	light.Color = palette.main
	light.Range = 60
	light.Brightness = 12
	light.Parent = lightAnchor
	tween(light, LIGHT_DURATION, { Brightness = 0 })
end

--[[
	Chorégraphie commune à toutes les magies, teintée par leur palette. YIELD pendant l'arrêt sur image.
		Phase 1 (ULTIMATE_HIT_STOP) : le temps se fige. Image en noir et blanc, animations gelées,
		                              une sphère sombre enfle autour du lanceur.
		Phase 2                     : la sphère s'effondre et tout explose (voir spawnEruption),
		                              flash d'écran, secousse et recul de caméra.
	`caster` peut manquer (personnage non répliqué chez ce client) : `origin` suffit à tout placer.
]]
local function playEruption(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local palette = magic.palette
	local radius = magic.radius
	local intensity = getIntensity(origin, radius)

	local involvedCharacters = table.clone(targets)
	if caster then
		table.insert(involvedCharacters, caster)
	end

	-- Phase 1 : arrêt sur image ------------------------------------------------
	local resumeAnimations = freezeAnimations(involvedCharacters)
	if intensity > 0 then
		setScreenLook(blendLook(IMPACT_FRAME_LOOK, intensity), 0)
	end

	local core = newEffectPart("VoidCore", Enum.PartType.Ball, Vector3.one, palette.void, Config.ULTIMATE_HIT_STOP + 1)
	core.CFrame = CFrame.new(origin)
	core.Parent = getEffectsFolder()
	tween(core, Config.ULTIMATE_HIT_STOP, { Size = Vector3.one * CORE_SIZE })

	task.wait(Config.ULTIMATE_HIT_STOP)

	-- Phase 2 : éruption ---------------------------------------------------------
	resumeAnimations()
	tween(core, CORE_COLLAPSE_DURATION, { Size = Vector3.one * 0.1, Transparency = 1 })

	spawnEruption(origin, findGroundPosition(origin, involvedCharacters :: { any }), radius, palette)

	if intensity > 0 then
		-- L'écran est brûlé par la couleur claire de la magie, puis revient à la normale.
		local flashLook = table.clone(FLASH_LOOK)
		flashLook.TintColor = palette.glow
		setScreenLook(blendLook(flashLook, intensity), 0)
		setScreenLook(NEUTRAL_LOOK, FLASH_FADE_DURATION)
		shakeCamera(SHAKE_DURATION, SHAKE_AMPLITUDE * intensity)
		punchFieldOfView(FOV_PUNCH * intensity)
	end

	for _, target in targets do
		CombatEffects.playHitImpact(target, nil, palette.main)
	end
end

type UltimatePlayer = (caster: Model?, origin: Vector3, targets: { Model }, magic: any) -> ()

--[[
	>>> POINT D'EXTENSION DES 5 ULTIMES.
	Chorégraphies dédiées, rangées par `id` de magie. Une magie absente de cette table joue la
	chorégraphie commune (playEruption) avec ses propres couleurs : les cinq sont donc déjà
	distinctes à l'écran. Pour donner un spectacle unique à l'une d'elles, écrire une fonction
	de même signature que playEruption et l'enregistrer ici, par exemple :
		pyromancy = playInferno,
		lightning = playThunderJudgement,
]]
local ULTIMATE_PLAYERS: { [string]: UltimatePlayer } = {}

-- Joue l'ultime de `magic` (une entrée de MagicConfig.MAGICS). YIELD pendant l'arrêt sur image.
function CombatEffects.playUltimate(caster: Model?, origin: Vector3, targets: { Model }, magic: any)
	local play: UltimatePlayer = ULTIMATE_PLAYERS[magic.id] or playEruption :: any
	play(caster, origin, targets, magic)
end

return CombatEffects
