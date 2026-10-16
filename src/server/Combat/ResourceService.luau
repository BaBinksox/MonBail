--!strict
--[[
	ResourceService
	Les ressources de combat de chaque joueur, tenues par le SERVEUR (voir ResourceConfig) :
		- TENSION : gagnée par le jeu (addTension avec une source de TENSION_SOURCES, multipliée par
		  le peuple), dépensée par l'ultime (spendTension). Attribut Player « Tension » ;
		- MANA : réserve des sorts, régénérée toutes les REGEN_INTERVAL s, plus vite hors combat.
		  spendMana vérifie ET débite d'un coup : deux demandes rapprochées ne paient pas un seul coût.
		  Attributs Player « Mana » et « ManaMax » ;
		- COMBAT : un joueur qui inflige ou subit des dégâts est « en combat » COMBAT_TIMEOUT s
		  (attribut « InCombat », lu aussi par la musique) ;
		- CONCENTRATION : demandée par le client (RequestConcentrate), accordée ici si rien ne s'y
		  oppose (recharge, Mana plein, charge en cours...). Pendant la posture : Mana rapide,
		  déplacement très ralenti, pas de sprint ni de parade, dégâts reçus augmentés ; elle cesse
		  au relâchement, à la durée maximale, au premier coup reçu ou quand le Mana est plein.
	Le client ne peut qu'afficher ces valeurs : il n'envoie jamais un montant de Mana ou de Tension.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local CombatRemotes = require(ReplicatedStorage.Shared.Combat.CombatRemotes)
local Config = require(ReplicatedStorage.Shared.Combat.ResourceConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local RaceService = require(script.Parent.Parent.Avatar.RaceService)
local DamageService = require(script.Parent.DamageService)
local MovementService = require(script.Parent.Parent.Movement.MovementService)
local ParryService = require(script.Parent.ParryService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

type State = {
	inCombatUntil: number,
	concentrating: boolean,
	concentrationStart: number,
	concentrationReadyAt: number, -- os.clock()
}

local ResourceService = {}

local states: { [Player]: State } = {}
local concentrationBlockers: { (player: Player) -> boolean } = {}
local regenMultipliers: { (player: Player) -> number } = {}
local concentrateLimiter = RateLimiter.new(4, 6)
local isStarted = false

local function getState(player: Player): State
	local state = states[player]
	if state == nil then
		state = { inCombatUntil = 0, concentrating = false, concentrationStart = 0, concentrationReadyAt = 0 }
		states[player] = state
	end
	return state
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function canAct(player: Player): boolean
	return isAlive(player)
		and not AvatarService.isCustomizing(player)
		and not TimeLoopService.isInAnomaly(player)
		and not TimeLoopService.isRewindingFor(player)
end

--------------------------------------------------------------------------------
-- Tension
--------------------------------------------------------------------------------

function ResourceService.getTension(player: Player): number
	local tension = player:GetAttribute(CombatConfig.TENSION_ATTRIBUTE)
	return if type(tension) == "number" then tension else 0
end

function ResourceService.setTension(player: Player, value: number)
	player:SetAttribute(CombatConfig.TENSION_ATTRIBUTE, math.clamp(value, 0, CombatConfig.TENSION_MAX))
end

-- Ajoute la Tension d'une source de TENSION_SOURCES (x `scale`, x multiplicateur du peuple).
function ResourceService.addTension(player: Player, source: string, scale: number?): number
	local base = Config.TENSION_SOURCES[source]
	if base == nil then
		warn(`[Resources] Source de Tension inconnue : {source}`)
		return 0
	end
	local gain = base * (scale or 1) * RaceService.getTensionGainMultiplier(player)
	ResourceService.setTension(player, ResourceService.getTension(player) + gain)
	return gain
end

-- Débite `amount` si la jauge le permet. Retourne true si c'est fait.
function ResourceService.spendTension(player: Player, amount: number): boolean
	local current = ResourceService.getTension(player)
	if current < amount then
		return false
	end
	ResourceService.setTension(player, current - amount)
	return true
end

--------------------------------------------------------------------------------
-- Mana
--------------------------------------------------------------------------------

function ResourceService.getManaMax(player: Player): number
	local max = player:GetAttribute(Config.MANA_MAX_ATTRIBUTE)
	return if type(max) == "number" then max else Config.MANA_MAX
end

function ResourceService.getMana(player: Player): number
	local mana = player:GetAttribute(Config.MANA_ATTRIBUTE)
	return if type(mana) == "number" then mana else ResourceService.getManaMax(player)
end

local function setMana(player: Player, value: number)
	player:SetAttribute(Config.MANA_ATTRIBUTE, math.clamp(value, 0, ResourceService.getManaMax(player)))
end

-- Vérifie et débite `cost` d'un seul geste. Retourne false (rien n'est débité) si le Mana manque.
function ResourceService.spendMana(player: Player, cost: number): boolean
	if type(cost) ~= "number" or cost < 0 or cost ~= cost then
		return false
	end
	local mana = ResourceService.getMana(player)
	if mana + 1e-6 < cost then
		return false
	end
	setMana(player, mana - cost)
	return true
end

function ResourceService.restoreMana(player: Player, amount: number)
	setMana(player, ResourceService.getMana(player) + math.max(0, amount))
end

-- Multiplicateur de régénération (équipements, compétences futures). 1 = aucun effet.
function ResourceService.addRegenMultiplier(provider: (player: Player) -> number)
	table.insert(regenMultipliers, provider)
end

--------------------------------------------------------------------------------
-- Combat
--------------------------------------------------------------------------------

function ResourceService.markCombat(player: Player)
	getState(player).inCombatUntil = os.clock() + Config.COMBAT_TIMEOUT
	if player:GetAttribute(Config.IN_COMBAT_ATTRIBUTE) ~= true then
		player:SetAttribute(Config.IN_COMBAT_ATTRIBUTE, true)
	end
end

function ResourceService.isInCombat(player: Player): boolean
	return os.clock() < getState(player).inCombatUntil
end

--------------------------------------------------------------------------------
-- Concentration
--------------------------------------------------------------------------------

function ResourceService.isConcentrating(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.concentrating
end

function ResourceService.addConcentrationBlocker(blocker: (player: Player) -> boolean)
	table.insert(concentrationBlockers, blocker)
end

local function stopConcentration(player: Player)
	local state = getState(player)
	if not state.concentrating then
		return
	end
	state.concentrating = false
	state.concentrationReadyAt = os.clock() + Config.CONCENTRATION_COOLDOWN
	player:SetAttribute(Config.CONCENTRATING_ATTRIBUTE, false)
	player:SetAttribute(Config.CONCENTRATION_READY_ATTRIBUTE, workspace:GetServerTimeNow() + Config.CONCENTRATION_COOLDOWN)
	MovementService.refreshSpeed(player)
end
ResourceService.stopConcentration = stopConcentration

local function startConcentration(player: Player): boolean
	local state = getState(player)
	if state.concentrating or not canAct(player) or os.clock() < state.concentrationReadyAt then
		return false
	end
	if ResourceService.getMana(player) >= ResourceService.getManaMax(player) - 0.5 then
		return false -- rien à récupérer
	end
	for _, blocker in concentrationBlockers do
		local isOk, blocked = pcall(blocker, player)
		if isOk and blocked then
			return false
		end
	end
	state.concentrating = true
	state.concentrationStart = os.clock()
	player:SetAttribute(Config.CONCENTRATING_ATTRIBUTE, true)
	MovementService.stopSprint(player)
	MovementService.refreshSpeed(player)
	return true
end

local function onConcentrateRequested(player: Player, wants: any)
	if type(wants) ~= "boolean" or not concentrateLimiter:allow(player) then
		return
	end
	if wants then
		startConcentration(player)
	else
		stopConcentration(player)
	end
end

--------------------------------------------------------------------------------
-- Boucle de régénération
--------------------------------------------------------------------------------

local function regenerate(player: Player, dt: number)
	local state = getState(player)
	local now = os.clock()
	local inCombat = now < state.inCombatUntil
	if (player:GetAttribute(Config.IN_COMBAT_ATTRIBUTE) == true) ~= inCombat then
		player:SetAttribute(Config.IN_COMBAT_ATTRIBUTE, inCombat)
	end
	if not isAlive(player) then
		stopConcentration(player)
		return
	end
	if state.concentrating then
		if now - state.concentrationStart >= Config.CONCENTRATION_MAX_DURATION or not canAct(player) then
			stopConcentration(player)
		end
	end
	local rate = if state.concentrating
		then Config.CONCENTRATION_REGEN
		elseif inCombat then Config.MANA_REGEN_IN_COMBAT
		else Config.MANA_REGEN_OUT_OF_COMBAT
	for _, provider in regenMultipliers do
		local isOk, value = pcall(provider, player)
		if isOk and type(value) == "number" and value == value then
			rate *= math.max(0, value)
		end
	end
	local max = ResourceService.getManaMax(player)
	local mana = ResourceService.getMana(player)
	if mana < max then
		setMana(player, mana + rate * dt)
	elseif state.concentrating then
		stopConcentration(player) -- Mana plein : la posture n'a plus de raison d'être
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function resetPlayer(player: Player)
	local state = getState(player)
	state.concentrating = false
	state.inCombatUntil = 0
	player:SetAttribute(Config.MANA_MAX_ATTRIBUTE, Config.MANA_MAX)
	player:SetAttribute(Config.MANA_ATTRIBUTE, Config.MANA_MAX)
	player:SetAttribute(Config.CONCENTRATING_ATTRIBUTE, false)
	player:SetAttribute(Config.IN_COMBAT_ATTRIBUTE, false)
	ResourceService.setTension(player, 0) -- la Tension accumulée est perdue à la mort
end

function ResourceService.start()
	if isStarted then
		return
	end
	isStarted = true

	CombatRemotes.RequestConcentrate.OnServerEvent:Connect(onConcentrateRequested)

	-- Un joueur qui frappe ou qui est frappé est en combat ; un coup reçu rompt la Concentration.
	DamageService.Damaged:Connect(function(_target: Model, _applied: number, source: any, targetPlayer: Player?)
		if source.player then
			ResourceService.markCombat(source.player)
		end
		if targetPlayer then
			ResourceService.markCombat(targetPlayer)
			stopConcentration(targetPlayer)
		end
	end)
	DamageService.Dodged:Connect(function(player: Player, isPerfect: boolean)
		ResourceService.markCombat(player)
		if isPerfect then
			ResourceService.addTension(player, "perfectDodge")
		end
	end)
	ParryService.Parried:Connect(function(player: Player)
		ResourceService.markCombat(player)
		ResourceService.addTension(player, "perfectParry")
	end)

	-- Contreparties de la Concentration.
	DamageService.addPlayerModifier(function(player: Player, amount: number): number
		return if ResourceService.isConcentrating(player) then amount * Config.CONCENTRATION_DAMAGE_TAKEN else amount
	end)
	MovementService.addSpeedProvider(function(player: Player): number
		return if ResourceService.isConcentrating(player) then Config.CONCENTRATION_MOVE_MULTIPLIER else 1
	end)
	MovementService.addSprintBlocker(ResourceService.isConcentrating)
	ParryService.addBlocker(ResourceService.isConcentrating)

	local function onPlayerAdded(player: Player)
		resetPlayer(player)
		player.CharacterAdded:Connect(function()
			resetPlayer(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Config.REGEN_INTERVAL then
			return
		end
		local step = elapsed
		elapsed = 0
		for _, player in Players:GetPlayers() do
			regenerate(player, step)
		end
	end)
end

return ResourceService
