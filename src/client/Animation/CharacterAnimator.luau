--!strict
--[[
	CharacterAnimator (ModuleScript, client)
	Joue les actions d'AnimationConfig sur un personnage R15 (le sien, celui d'un autre joueur, un
	ennemi), par-dessus les animations de base de Roblox.

	Trois canaux, qui s'additionnent :
		"action"  coups d'épée, sorts, parade, dash, double saut, atterrissage (un à la fois : une
		          nouvelle action remplace la précédente en fondu) ;
		"hold"    postures maintenues (attaque chargée, Concentration) jusqu'à stop() ;
		"react"   réactions aux coups (sursaut, déséquilibre) ;
	plus une couche de LOCOMOTION continue : inclinaison du buste au sprint, bras en chute,
	respiration au repos (setLocomotion).

	Application : chaque articulation Motor6D reçoit C0 = C0 d'origine x décalage. Le C0 d'origine est
	relu dès qu'un autre système le modifie (reconstruction du rig, changement d'apparence) : rien ne
	s'accumule, et une articulation revient exactement à son état d'origine quand plus rien ne
	l'anime. Une action dont AnimationConfig fournit un clip (animationId) est jouée par l'Animator
	du personnage LOCAL (Roblox la réplique aux autres) au lieu de la pose procédurale.

	API :
		CharacterAnimator.get(character, isLocal?): Animator          (un seul par personnage)
		animator:play(actionName, options?) -> number (durée)          options : speed, duration,
		                                                               channel, onImpact
		animator:stop(channel)              animator:freeze(seconds)   (arrêt sur image)
		animator:setLocomotion(sprint, airborne, verticalSpeed, speed)
		animator:update(dt) -> boolean      (true tant qu'il reste quelque chose à animer)
		animator:destroy()                  CharacterAnimator.getActive(): { Animator }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"):WaitForChild("AnimationConfig") :: ModuleScript)
local PoseLibrary = require(script.Parent:WaitForChild("PoseLibrary") :: ModuleScript)

export type PlayOptions = {
	speed: number?,
	duration: number?, -- durée imposée (s) : la pose est étirée pour la remplir
	channel: string?,
	onImpact: (() -> ())?,
}

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
}

type JointState = { base: CFrame, written: CFrame }

local CHANNELS = { "action", "hold", "react" }
local HOLD_ACTIONS: { [string]: boolean } = { sword_charge = true, sword_plunge_fall = true, concentrate = true }
local REACT_ACTIONS: { [string]: boolean } = { hit_react = true, stagger = true }

local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

type AnimatorData = {
	character: Model,
	isLocal: boolean,
	motors: { [string]: Motor6D },
	joints: { [Motor6D]: JointState },
	layers: { [string]: Layer },
	tracks: { [string]: AnimationTrack },
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
	-- Une articulation remplacée (changement d'apparence) est retrouvée au besoin.
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

-- Clip Roblox de l'action, chargé une fois par personnage (personnage local seulement).
local function getTrack(self: Animator, actionName: string, animationId: string): AnimationTrack?
	local cached = self.tracks[actionName]
	if cached then
		return cached
	end
	local humanoid = self.character:FindFirstChildOfClass("Humanoid")
	local animatorInstance = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animatorInstance == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local isLoaded, track = pcall(function()
		return animatorInstance:LoadAnimation(animation)
	end)
	if not isLoaded or typeof(track) ~= "Instance" then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	self.tracks[actionName] = track
	return track
end

-- Joue une action. Retourne sa durée (s), 0 si elle est inconnue.
function CharacterAnimator.play(self: Animator, actionName: string, options: PlayOptions?): number
	if self.destroyed then
		return 0
	end
	local action = AnimationConfig.ACTIONS[actionName]
	if action == nil then
		return 0
	end
	local opts: PlayOptions = options or {}
	local speed = (opts.speed or 1) * action.speed

	if action.animationId ~= "" then
		if self.isLocal then
			local track = getTrack(self, actionName, action.animationId)
			if track then
				track:Play(action.fadeIn, 1, speed)
				local length = if track.Length > 0 then track.Length / speed else 0.5
				local onImpact = opts.onImpact
				if onImpact then
					task.delay(length * 0.4, onImpact)
				end
				return length
			end
		else
			return 0 -- le clip du personnage distant est répliqué par Roblox
		end
	end

	local definition = PoseLibrary.get(action.pose)
	if definition == nil then
		return 0
	end
	local duration = opts.duration or definition.duration / speed
	local channel = channelOf(actionName, opts.channel)
	self.layers[channel] = {
		action = actionName,
		pose = action.pose,
		elapsed = 0,
		duration = math.max(duration, 0.05),
		looped = definition.looped,
		fadeIn = action.fadeIn,
		fadeOut = action.fadeOut,
		stopping = false,
		stopElapsed = 0,
		impact = definition.impact,
		impactFired = false,
		onImpact = opts.onImpact,
	}
	return duration
end

-- Arrête en fondu l'action du canal (« hold » : charge, Concentration).
function CharacterAnimator.stop(self: Animator, channel: string)
	local layer = self.layers[channel]
	if layer and not layer.stopping then
		layer.stopping = true
		layer.stopElapsed = 0
	end
	local track = nil
	for actionName, cachedTrack in self.tracks do
		if channelOf(actionName, nil) == channel and cachedTrack.IsPlaying then
			track = cachedTrack
		end
	end
	if track then
		track:Stop(0.15)
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

-- Arrêt sur image (hit-stop) : les poses ne progressent plus pendant `seconds`.
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

-- Écrit le C0 d'une articulation (C0 d'origine relu si quelqu'un d'autre l'a changé).
local function writeJoint(self: Animator, motor: Motor6D, offset: CFrame?)
	local state = self.joints[motor]
	if offset == nil then
		if state then
			if motor.C0 == state.written then
				motor.C0 = state.base
			end
			self.joints[motor] = nil
		end
		return
	end
	if state == nil then
		state = { base = motor.C0, written = motor.C0 }
		self.joints[motor] = state
	elseif motor.C0 ~= state.written then
		state.base = motor.C0
	end
	local target = state.base * offset
	motor.C0 = target
	state.written = target
end

-- Avance d'un pas. Retourne true s'il reste quelque chose à animer.
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
			else
				local weight = weightOf(layer)
				local poseAngles, poseOffset = PoseLibrary.sample(layer.pose, layer.elapsed / layer.duration)
				for name, value in poseAngles do
					add(name, value * weight)
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
		if motor.Parent and motor.C0 == state.written then
			motor.C0 = state.base
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
