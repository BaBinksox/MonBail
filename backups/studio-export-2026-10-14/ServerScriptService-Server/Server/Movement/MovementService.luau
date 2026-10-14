--!strict
--[[
	MovementService
	Façade serveur de la mobilité (singleton).

	Le déplacement d'un personnage est simulé par le client de son joueur : c'est donc lui qui
	se propulse (voir DashController). Le serveur, lui :
		- valide chaque dash annoncé (joueur en état d'agir, cooldown respecté) ;
		- prévient les autres clients pour qu'ils jouent l'effet visuel ;
		- accorde une courte invulnérabilité, que les sources de dégâts consultent avec isDashing().

	Sans dash validé ici, pas d'invulnérabilité : un client ne peut pas se la donner tout seul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Movement.MovementConfig)
local Remotes = require(ReplicatedStorage.Shared.Movement.MovementRemotes)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

local MovementService = {}

local lastDashClock: { [Player]: number } = {} -- os.clock() du dernier dash accepté
local isStarted = false

local function canAct(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	return not (AvatarService.isCustomizing(player) or TimeLoopService.isInAnomaly(player) or TimeLoopService.isRewinding())
end

local function onDashRequested(player: Player)
	if not canAct(player) then
		return
	end

	local now = os.clock()
	local lastClock = lastDashClock[player]
	if lastClock and now - lastClock < Config.DASH_COOLDOWN - Config.LATENCY_TOLERANCE then
		if Config.DEBUG_LOGS then
			print(`[Movement] Dash refusé pour {player.Name} : cooldown`)
		end
		return
	end
	lastDashClock[player] = now

	-- Le joueur joue déjà son effet en local : seuls les autres clients sont prévenus.
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			Remotes.DashStarted:FireClient(otherPlayer, player.Character)
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function MovementService.start()
	if isStarted then
		return
	end
	isStarted = true

	Remotes.RequestDash.OnServerEvent:Connect(onDashRequested)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastDashClock[player] = nil
	end)
end

-- true pendant la fenêtre d'invulnérabilité d'un dash validé. Toute source de dégâts
-- (épée d'un autre joueur, coups du boss...) doit épargner un joueur pour qui c'est vrai.
function MovementService.isDashing(player: Player): boolean
	local lastClock = lastDashClock[player]
	return lastClock ~= nil and os.clock() - lastClock <= Config.DASH_INVULNERABILITY
end

return MovementService
