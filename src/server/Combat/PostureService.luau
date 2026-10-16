--!strict
--[[
	PostureService
	Posture des ENNEMIS (et du boss), tenue par le serveur (voir CombatConfig.POSTURE) :
		- une jauge discrète que les coups lourds, la parade parfaite et certaines magies entament
		  (damage). Le maximum dépend des PV max de l'ennemi, avec un bonus pour les élites et le boss ;
		- pleine : la posture est BRISÉE. L'ennemi est étourdi (CombatStatus.stun, respecté par toutes
		  les IA) et prend plus de dégâts pendant BREAK_DURATION s ; le boss se remet plus vite et ne
		  peut pas être brisé de nouveau avant BOSS_BREAK_COOLDOWN s (pas de boss verrouillé à vie) ;
		- elle se reconstitue toute seule après REGEN_DELAY s sans pression.
	Les joueurs n'ont pas de posture (le PvP reste arbitré par la parade et l'esquive).

	Attributs (lecture seule pour les clients) : Posture (0..1, arrondi, sur le Model de l'ennemi) et
	PostureBrokenUntil (heure serveur). Remise à zéro : mort, disparition, rembobinage.

	API :
		PostureService.damage(model, amount, player?) -> boolean   (true = la posture vient de se briser)
		PostureService.isBroken(model) -> boolean
		PostureService.getRatio(model) -> number                   PostureService.reset(model)
		PostureService.Broken : Signal (model, player?)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local CombatStatus = require(script.Parent.CombatStatus)
local DamageService = require(script.Parent.DamageService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

local Config = CombatConfig.POSTURE

local UPDATE_INTERVAL = 0.25 -- s entre deux reconstitutions
local PUBLISH_STEP = 0.02 -- l'attribut n'est réécrit que si la jauge bouge d'au moins 2 %

type State = {
	value: number, -- posture entamée (0 = intacte, max = brisée)
	max: number,
	lastHitClock: number,
	brokenUntil: number, -- os.clock()
	nextBreakAt: number, -- os.clock() : avant, la posture ne peut pas se briser (boss)
	published: number, -- dernier ratio écrit dans l'attribut
}

local PostureService = {}
PostureService.Broken = Signal.new()

local states: { [Model]: State } = {}
local isStarted = false

local function isBoss(model: Model): boolean
	return CollectionService:HasTag(model, BossConfig.TAG)
end

local function computeMax(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local maxHealth = if humanoid then humanoid.MaxHealth else 100
	local multiplier = if isBoss(model)
		then Config.BOSS_MULTIPLIER
		elseif model:GetAttribute(DamageService.ELITE_ATTRIBUTE) == true then Config.ELITE_MULTIPLIER
		else 1
	return math.clamp(maxHealth * Config.HEALTH_RATIO * multiplier, Config.MIN, Config.MAX)
end

local function publish(model: Model, state: State, force: boolean?)
	local ratio = math.clamp(state.value / state.max, 0, 1)
	if force or math.abs(ratio - state.published) >= PUBLISH_STEP or (ratio == 0 and state.published ~= 0) then
		state.published = ratio
		model:SetAttribute(Config.ATTRIBUTE, math.floor(ratio * 100 + 0.5) / 100)
	end
end

local function getState(model: Model): State
	local state = states[model]
	if state == nil then
		state = {
			value = 0,
			max = computeMax(model),
			lastHitClock = 0,
			brokenUntil = 0,
			nextBreakAt = 0,
			published = 0,
		}
		states[model] = state
	end
	return state
end

function PostureService.isBroken(model: Model): boolean
	local state = states[model]
	return state ~= nil and os.clock() < state.brokenUntil
end

function PostureService.getRatio(model: Model): number
	local state = states[model]
	return if state then math.clamp(state.value / state.max, 0, 1) else 0
end

function PostureService.reset(model: Model)
	if states[model] == nil then
		return
	end
	states[model] = nil
	model:SetAttribute(Config.ATTRIBUTE, nil)
	model:SetAttribute(Config.BROKEN_ATTRIBUTE, nil)
end

-- Entame la posture de `model` de `amount`. Retourne true si elle vient de se briser.
function PostureService.damage(model: Model, amount: number, player: Player?): boolean
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount or not DamageService.isDamageableEnemy(model) then
		return false
	end
	local state = getState(model)
	local now = os.clock()
	if now < state.brokenUntil then
		return false -- déjà sans défense : rien à briser de plus
	end
	state.lastHitClock = now
	state.value += amount
	if state.value < state.max then
		publish(model, state)
		return false
	end
	if now < state.nextBreakAt then
		-- Boss encore en récupération d'une rupture : la jauge reste au bord, sans se briser.
		state.value = state.max * 0.99
		publish(model, state)
		return false
	end

	local boss = isBoss(model)
	local duration = if boss then Config.BOSS_BREAK_DURATION else Config.BREAK_DURATION
	state.value = 0
	state.brokenUntil = now + duration
	state.nextBreakAt = if boss then now + Config.BOSS_BREAK_COOLDOWN else 0
	CombatStatus.stun(model, duration)
	model:SetAttribute(Config.BROKEN_ATTRIBUTE, workspace:GetServerTimeNow() + duration)
	publish(model, state, true)
	PostureService.Broken:Fire(model, player)
	if CombatConfig.DEBUG_LOGS then
		print(`[Posture] {model.Name} : posture brisée ({duration} s)`)
	end
	return true
end

local function update(dt: number)
	local now = os.clock()
	for model, state in states do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if model.Parent == nil or humanoid == nil or humanoid.Health <= 0 or model:GetAttribute(DamageService.DEFEATED_ATTRIBUTE) == true then
			states[model] = nil -- mort ou disparu : plus de jauge (le Model est peut-être détruit)
			continue
		end
		if state.value > 0 and now >= state.brokenUntil and now - state.lastHitClock >= Config.REGEN_DELAY then
			state.value = math.max(0, state.value - state.max * Config.REGEN_RATE * dt)
			publish(model, state)
		end
		if state.value <= 0 and now >= state.brokenUntil and now >= state.nextBreakAt and state.published == 0 then
			PostureService.reset(model) -- jauge intacte : on n'entretient plus rien pour cet ennemi
		end
	end
end

function PostureService.start()
	if isStarted then
		return
	end
	isStarted = true

	-- Posture brisée : les coups font plus mal.
	DamageService.addModifier(function(target: Model, amount: number): number
		return if PostureService.isBroken(target) then amount * Config.BREAK_DAMAGE_MULTIPLIER else amount
	end)

	-- Le rembobinage ramène les ennemis enregistrés à un état antérieur : leur posture repart d'intacte.
	TimeLoopService.Rewound:Connect(function(_timelineId: string, characters: { Model })
		for _, character in characters do
			PostureService.reset(character)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= UPDATE_INTERVAL then
			update(elapsed)
			elapsed = 0
		end
	end)
end

return PostureService
