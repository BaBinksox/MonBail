--!strict
--[[
	CharacterAnimator (ModuleScript, client)
	Joue les actions d'AnimationConfig sur un personnage R15 (le sien, celui d'un autre joueur, un
	ennemi). Pour chaque action, la PREMIÈRE solution disponible est utilisée (AnimationConfig) :
		1. clip publié (animationId), joué par l'Animator du personnage local et répliqué ;
		2. séquence générée depuis PoseLibrary (Studio : vraie piste d'animation) ;
		3. clip de repli historique (épée) + accent procédural du buste et des jambes ;
		4. pose procédurale seule.

	Trois canaux : "action" (coups, sorts, dash...), "hold" (charge, Concentration, plongée en
	chute : jusqu'à stop()), "react" (sursauts). Une nouvelle action remplace la précédente du canal.

	Calque procédural : appliqué sur Motor6D.Transform à chaque RunService.Stepped, c'est-à-dire
	APRÈS que l'Animator a posé les animations de base (marche, course) : il s'y ajoute au lieu d'être
	écrasé. C0 n'est plus jamais modifié. Un Transform que l'Animator n'a pas réécrit (articulation
	qu'aucune animation ne touche) est repris depuis sa dernière valeur de base : rien ne s'accumule.

	API :
		CharacterAnimator.get(character, isLocal?): Animator          (un seul par personnage)
		animator:play(actionName, options?) -> number (durée)          options : speed, duration,
		                                                               channel, onImpact
		animator:stop(channel)   animator:isPlaying(actionName)   animator:freeze(seconds)
		animator:setLocomotion(sprint, airborne, verticalSpeed, speed)
		animator:update(dt) -> boolean      (à appeler dans RunService.Stepped)
		animator:getSource(actionName) -> string?   "published" | "generated" | "fallback" | "pose"
		animator:destroy()                  CharacterAnimator.getActive(): { Animator }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local animationFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation")
local AnimationConfig = require(animationFolder:WaitForChild("AnimationConfig") :: ModuleScript)
local PoseLibrary = require(animationFolder:WaitForChild("PoseLibrary") :: ModuleScript)
local GeneratedAnimations = require(script.Parent:WaitForChild("GeneratedAnimations") :: ModuleScript)

export type PlayOptions = {
	speed: number?,
	duration: number?, -- durée imposée (s) : la piste ou la pose est étirée pour la remplir
	channel: string?,
	onImpact: (() -> ())?,
}

-- Ce que le calque procédural dessine pour une action : tout, seulement le buste et les jambes
-- (accent sur un clip de repli), ou rien (une vraie piste joue déjà le mouvement).
type Visual = string -- "full" | "accent" | "none"

type Layer = {
	action: string,
	pose: string,
	elapsed: number,
	duration: number,
	looped: boolean,
	fadeIn: number,
	fadeOut: number,
	stopping: boolean,
	stopElapsed: number,
	impact: number,
	impactFired: boolean,
	onImpact: (() -> ())?,
	visual: Visual,
	track: AnimationTrack?,
}

type JointState = { base: CFrame, written: CFrame }

local CHANNELS = { "action", "hold", "react" }
local HOLD_ACTIONS: { [string]: boolean } = { sword_charge = true, sword_plunge_fall = true, concentrate = true }
local REACT_ACTIONS: { [string]: boolean } = { hit_react = true, stagger = true }
local ACCENT_JOINTS: { [string]: boolean } = { Root = true, Waist = true, Neck = true, RH = true, RK = true, LH = true, LK = true }
local CHANNEL_PRIORITY: { [string]: Enum.AnimationPriority } = {
	hold = Enum.AnimationPriority.Action,
	action = Enum.AnimationPriority.Action2,
	react = Enum.AnimationPriority.Action3,
}

local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

type AnimatorData = {
	character: Model,
	isLocal: boolean,
	motors: { [string]: Motor6D },
	joints: { [Motor6D]: JointState },
	layers: { [string]: Layer },
	tracks: { [string]: AnimationTrack }, -- par identifiant d'animation
	failedTracks: { [string]: boolean },
	sources: { [string]: string },
	sprint: number,
	airborne: boolean,
	verticalSpeed: number,
	speed: number,
	clock: number,
	frozenFor: number,
	destroyed: boolean,
	connections: { RBXScriptConnection },
}

export type Animator = typeof(setmetatable({} :: AnimatorData, CharacterAnimator))

local animators: { [Model]: Animator } = {}
local reportedSources: { [string]: boolean } = {}

local function channelOf(actionName: string, requested: string?): string
	if requested then
		return requested
	end
	if HOLD_ACTIONS[actionName] then
		return "hold"
	elseif REACT_ACTIONS[actionName] then
		return "react"
	end
	return "action"
end

-- Articulations R15 du personnage, par nom court (PoseLibrary.JOINTS).
local function findMotors(character: Model): { [string]: Motor6D }
	local motors: { [string]: Motor6D } = {}
	for short, motorName in PoseLibrary.JOINTS do
		local found = character:FindFirstChild(motorName, true)
		if found and found:IsA("Motor6D") then
			motors[short] = found
		end
	end
	return motors
end

local function getRobloxAnimator(self: Animator): Instance?
	local humanoid = self.character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

-- Piste chargée une fois par personnage et par identifiant.
local function getTrack(self: Animator, animationId: string, channel: string, looped: boolean): AnimationTrack?
	if self.failedTracks[animationId] then
		return nil
	end
	local cached = self.tracks[animationId]
	if cached then
		return cached
	end
	local animatorInstance = getRobloxAnimator(self)
	if animatorInstance == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local isLoaded, track = pcall(function()
		return (animatorInstance :: any):LoadAnimation(animation)
	end)
	if not isLoaded or track == nil then
		self.failedTracks[animationId] = true
		return nil
	end
	local loadedTrack = track :: AnimationTrack
	pcall(function()
		loadedTrack.Priority = CHANNEL_PRIORITY[channel] or Enum.AnimationPriority.Action
		loadedTrack.Looped = looped
	end)
	self.tracks[animationId] = loadedTrack
	return loadedTrack
end

function CharacterAnimator.get(character: Model, isLocal: boolean?): Animator
	local existing = animators[character]
	if existing and not existing.destroyed then
		return existing
	end
	local data: AnimatorData = {
		character = character,
		isLocal = isLocal == true,
		motors = findMotors(character),
		joints = {},
		layers = {},
		tracks = {},
		failedTracks = {},
		sources = {},
		sprint = 0,
		airborne = false,
		verticalSpeed = 0,
		speed = 0,
		clock = 0,
		frozenFor = 0,
		destroyed = false,
		connections = {},
	}
	local animator = setmetatable(data, CharacterAnimator)
	animators[character] = animator
	table.insert(data.connections, character.Destroying:Connect(function()
		animator:destroy()
	end))
	-- Personnage local : les clips de repli sont chargés dès l'apparition, pour être prêts au 1er coup.
	if data.isLocal then
		task.defer(function()
			for actionName, action in AnimationConfig.ACTIONS do
				if not data.destroyed and action.fallbackId ~= "" and action.animationId == "" then
					getTrack(animator, action.fallbackId, channelOf(actionName, nil), false)
				end
			end
		end)
	end
	-- Une articulation remplacée (changement d'apparence, épée refixée) est retrouvée au besoin.
	table.insert(data.connections, character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("Motor6D") then
			data.motors = findMotors(character)
		end
	end))
	return animator
end

-- Animateur déjà créé pour ce personnage, sans en créer un.
function CharacterAnimator.find(character: Model): Animator?
	local existing = animators[character]
	return if existing and not existing.destroyed then existing else nil
end

function CharacterAnimator.getActive(): { Animator }
	local list = {}
	for character, animator in animators do
		if animator.destroyed or character.Parent == nil then
			animator:destroy()
		else
			table.insert(list, animator)
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Pistes d'animation
--------------------------------------------------------------------------------

--[[
	Choisit la solution d'une action pour ce personnage. Retourne (source, identifiant de la piste à
	jouer ICI ou nil, ce que le calque procédural doit dessiner).
	Personnage d'un autre joueur : un clip publié ou de repli est déjà répliqué par Roblox, on ne le
	rejoue pas ; une séquence générée (identifiant temporaire, local) est rejouée sur place.
]]
local function resolve(self: Animator, action: any): (string, string?, Visual)
	if action.animationId ~= "" then
		return "published", if self.isLocal then action.animationId else nil, "none"
	end
	local generated = GeneratedAnimations.getId(action.pose)
	if generated then
		return "generated", generated, "none"
	end
	if action.fallbackId ~= "" then
		return "fallback", if self.isLocal then action.fallbackId else nil, "accent"
	end
	return "pose", nil, "full"
end

local function reportSource(actionName: string, source: string)
	if AnimationConfig.DEBUG_SOURCES and not reportedSources[actionName] then
		reportedSources[actionName] = true
		local labels = {
			published = "clip publié",
			generated = "séquence générée (Studio)",
			fallback = "clip historique + accent procédural",
			pose = "pose procédurale",
		}
		print(`[Animation] {actionName} : {labels[source] or source}`)
	end
end

local function stopLayerTrack(layer: Layer?, fade: number)
	local track = layer and layer.track
	if track then
		pcall(function()
			track:Stop(fade)
		end)
	end
end

-- Joue une action. Retourne sa durée (s), 0 si elle est inconnue.
function CharacterAnimator.play(self: Animator, actionName: string, options: PlayOptions?): number
	if self.destroyed then
		return 0
	end
	local action = AnimationConfig.ACTIONS[actionName]
	local definition = action and PoseLibrary.get(action.pose)
	if action == nil or definition == nil then
		return 0
	end
	local opts: PlayOptions = options or {}
	local speed = (opts.speed or 1) * action.speed
	local duration = math.max(opts.duration or definition.duration / speed, 0.05)
	local channel = channelOf(actionName, opts.channel)

	local source, trackId, visual = resolve(self, action)
	self.sources[actionName] = source
	reportSource(actionName, source)

	local previous = self.layers[channel]
	stopLayerTrack(previous, action.fadeIn)

	local track: AnimationTrack? = nil
	if trackId then
		track = getTrack(self, trackId, channel, definition.looped)
		if track and source == "fallback" and track.Length <= 0 then
			-- Clip de repli pas (encore) chargé, ou refusé : jamais de coup invisible, la pose
			-- complète le remplace ; il servira dès qu'il sera chargé (préchargé à l'apparition).
			track = nil
		end
		if track then
			-- Vitesse : la séquence générée dure exactement definition.duration ; un clip publié ou
			-- de repli a sa propre longueur (connue une fois chargé).
			local playSpeed = if source == "generated"
				then definition.duration / duration
				elseif track.Length > 0 then track.Length / duration
				else action.fallbackSpeed * (opts.speed or 1)
			pcall(function()
				(track :: AnimationTrack):Play(action.fadeIn, 1, playSpeed)
			end)
		elseif source == "fallback" then
			visual = "full" -- le clip de repli ne se charge pas : la pose complète le remplace
		end
	end

	self.layers[channel] = {
		action = actionName,
		pose = action.pose,
		elapsed = 0,
		duration = duration,
		looped = definition.looped,
		fadeIn = action.fadeIn,
		fadeOut = action.fadeOut,
		stopping = false,
		stopElapsed = 0,
		impact = definition.impact,
		impactFired = false,
		onImpact = opts.onImpact,
		visual = visual,
		track = track,
	}
	return duration
end

function CharacterAnimator.getSource(self: Animator, actionName: string): string?
	return self.sources[actionName]
end

-- Arrête en fondu l'action du canal (« hold » : charge, Concentration, plongée).
function CharacterAnimator.stop(self: Animator, channel: string)
	local layer = self.layers[channel]
	if layer and not layer.stopping then
		layer.stopping = true
		layer.stopElapsed = 0
		stopLayerTrack(layer, layer.fadeOut)
	end
end

function CharacterAnimator.isPlaying(self: Animator, actionName: string): boolean
	for _, layer in self.layers do
		if layer.action == actionName and not layer.stopping then
			return true
		end
	end
	return false
end

-- Arrêt sur image (hit-stop) : poses et pistes figées pendant `seconds`.
function CharacterAnimator.freeze(self: Animator, seconds: number)
	self.frozenFor = math.max(self.frozenFor, seconds)
end

function CharacterAnimator.setLocomotion(self: Animator, sprint: number, airborne: boolean, verticalSpeed: number, speed: number)
	self.sprint = math.clamp(sprint, 0, 1)
	self.airborne = airborne
	self.verticalSpeed = verticalSpeed
	self.speed = speed
end

local function weightOf(layer: Layer): number
	local weight = if layer.fadeIn > 0 then math.min(1, layer.elapsed / layer.fadeIn) else 1
	if layer.stopping then
		weight = math.min(weight, if layer.fadeOut > 0 then 1 - layer.stopElapsed / layer.fadeOut else 0)
	elseif not layer.looped then
		local remaining = layer.duration - layer.elapsed
		if layer.fadeOut > 0 and remaining < layer.fadeOut then
			weight = math.min(weight, remaining / layer.fadeOut)
		end
	end
	return math.clamp(weight, 0, 1)
end

--------------------------------------------------------------------------------
-- Calque procédural sur Motor6D.Transform
--------------------------------------------------------------------------------

local function writeJoint(self: Animator, motor: Motor6D, offset: CFrame?)
	local state = self.joints[motor]
	local current = motor.Transform
	if offset == nil then
		if state then
			if current == state.written then
				motor.Transform = state.base -- personne d'autre ne l'a réécrit : on rend la base
			end
			self.joints[motor] = nil
		end
		return
	end
	-- L'Animator réécrit Transform à chaque image pour les articulations qu'il anime ; s'il ne l'a
	-- pas fait (valeur identique à notre dernière écriture), on repart de la base précédente.
	local base = if state and current == state.written then state.base else current
	local target = base * offset
	motor.Transform = target
	self.joints[motor] = { base = base, written = target }
end

-- Avance d'un pas (RunService.Stepped). Retourne true s'il reste quelque chose à animer.
function CharacterAnimator.update(self: Animator, dt: number): boolean
	if self.destroyed then
		return false
	end
	self.clock += dt
	local step = dt
	if self.frozenFor > 0 then
		local frozen = math.min(self.frozenFor, dt)
		self.frozenFor -= frozen
		step = dt - frozen
	end

	local angles: { [string]: Vector3 } = {}
	local rootOffset = Vector3.zero
	local function add(name: string, value: Vector3)
		angles[name] = (angles[name] or Vector3.zero) + value
	end

	for _, channel in CHANNELS do
		local layer = self.layers[channel]
		if layer then
			layer.elapsed += step
			if layer.stopping then
				layer.stopElapsed += step
			end
			if not layer.impactFired and layer.elapsed >= layer.duration * layer.impact then
				layer.impactFired = true
				local onImpact = layer.onImpact
				if onImpact then
					task.spawn(onImpact)
				end
			end
			local finished = (layer.stopping and layer.stopElapsed >= layer.fadeOut)
				or (not layer.looped and layer.elapsed >= layer.duration)
			if finished then
				self.layers[channel] = nil
			elseif layer.visual ~= "none" then
				local weight = weightOf(layer)
				local poseAngles, poseOffset = PoseLibrary.sample(layer.pose, layer.elapsed / layer.duration)
				local accentOnly = layer.visual == "accent"
				for name, value in poseAngles do
					if not accentOnly or ACCENT_JOINTS[name] then
						add(name, value * weight)
					end
				end
				rootOffset += poseOffset * weight
			end
		end
	end

	-- Locomotion : buste penché au sprint, bras écartés en chute, respiration au repos.
	if self.sprint > 0.01 then
		local lean = math.rad(AnimationConfig.SPRINT_LEAN) * self.sprint
		add("Waist", Vector3.new(-lean, 0, 0))
		add("Neck", Vector3.new(lean * 0.5, 0, 0))
	end
	if self.airborne and self.verticalSpeed < -8 then
		local spread = math.rad(18)
		add("RS", Vector3.new(0, 0, spread))
		add("LS", Vector3.new(0, 0, -spread))
	end
	local hasAction = self.layers.action ~= nil or self.layers.hold ~= nil
	if not hasAction and not self.airborne and self.speed < 0.5 then
		local breath = math.rad(AnimationConfig.IDLE_BREATH_ANGLE) * math.sin(self.clock * 2 * math.pi / AnimationConfig.IDLE_BREATH_PERIOD)
		add("Waist", Vector3.new(breath, 0, 0))
	end

	for short, motor in self.motors do
		if motor.Parent == nil then
			self.joints[motor] = nil
			continue
		end
		local value: Vector3? = angles[short]
		local position = if short == "Root" then rootOffset else Vector3.zero
		if (value == nil or value.Magnitude < 1e-4) and position.Magnitude < 1e-4 then
			writeJoint(self, motor, nil)
		else
			local rotation = value or Vector3.zero
			writeJoint(self, motor, CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z))
		end
	end

	return next(self.layers) ~= nil or self.sprint > 0.01 or self.airborne or next(self.joints) ~= nil or self.isLocal
end

function CharacterAnimator.destroy(self: Animator)
	if self.destroyed then
		return
	end
	self.destroyed = true
	for motor, state in self.joints do
		if motor.Parent and motor.Transform == state.written then
			motor.Transform = state.base
		end
	end
	self.joints = {}
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, track in self.tracks do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	if animators[self.character] == self then
		animators[self.character] = nil
	end
end

return CharacterAnimator
