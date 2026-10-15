--!strict
--[[
	ParryService
	Parade parfaite, validée par le serveur (réglages : Shared/Combat/ParryConfig).

	1. Le client envoie RequestParry à l'appui (et joue la posture tout de suite, pour la réactivité).
	   Le serveur l'horodate À LA RÉCEPTION (os.clock) : le client ne transmet aucun temps, il ne peut
	   donc pas prétendre avoir paré "dans le passé" au-delà de ce que sa latence explique.
	2. Toute attaque ennemie qui va toucher un joueur appelle ParryService.resolve(player, attacker)
	   AVANT d'appliquer ses dégâts (via DamageService.damagePlayer) :
	     - demande reçue au plus PERFECT_WINDOW s AVANT l'impact -> parade réussie tout de suite ;
	     - sinon, on attend au plus (latence du joueur, bornée) + LATE_SLACK : une demande qui arrive
	       pendant ce délai compte aussi (le client a vu le coup en retard, et sa demande a voyagé).
	   Coût : un coup ennemi non paré tombe au plus ~0,3 s plus tard côté serveur. C'est le prix d'une
	   validation honnête sans faire confiance à l'horloge du client.
	3. Une demande ne peut être renouvelée qu'après COOLDOWN : impossible de parer en rafale.
	4. Réussite : l'attaquant est étourdi, le défenseur gagne de la Tension, tous les clients jouent l'effet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Combat.ParryConfig)
local Remotes = require(ReplicatedStorage.Shared.Combat.ParryRemotes)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local CombatStatus = require(script.Parent.CombatStatus)

local ParryService = {}

local lastRequestClock: { [Player]: number } = {}
local cooldownUntil: { [Player]: number } = {}
local isStarted = false

local function getLivingCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if character == nil or humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return character, rootPart
end

local function onParryRequested(player: Player)
	local now = os.clock()
	if (cooldownUntil[player] or 0) > now then
		return -- demande trop rapprochée : ignorée (et ne relance pas le délai)
	end
	if getLivingCharacter(player) == nil or AvatarService.isCustomizing(player) then
		return
	end
	lastRequestClock[player] = now
	cooldownUntil[player] = now + Config.COOLDOWN
	player:SetAttribute(Config.PARRY_STANCE_ATTRIBUTE, workspace:GetServerTimeNow())
end

local function getLatencyCompensation(player: Player): number
	local isMeasured, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	local latency = if isMeasured and type(ping) == "number" then ping else 0.1
	return math.clamp(latency, 0, Config.MAX_PING_COMPENSATION) + Config.LATE_SLACK
end

local function onParrySucceeded(player: Player, attacker: Model?)
	local character, rootPart = getLivingCharacter(player)
	if character == nil or rootPart == nil then
		return
	end
	if attacker then
		CombatStatus.stun(attacker, Config.STAGGER_DURATION)
	end
	local tension = player:GetAttribute(CombatConfig.TENSION_ATTRIBUTE)
	local current = if type(tension) == "number" then tension else 0
	player:SetAttribute(CombatConfig.TENSION_ATTRIBUTE, math.clamp(current + Config.PARRY_TENSION, 0, CombatConfig.TENSION_MAX))
	Remotes.ParryResult:FireAllClients(character, attacker, rootPart.Position)
end

--[[
	À appeler au moment où une attaque ennemie va toucher `player`. YIELD au plus ~0,3 s.
	Retourne true si le coup est paré (ne PAS appliquer de dégâts), false sinon.
]]
function ParryService.resolve(player: Player, attacker: Model?): boolean
	local impactClock = os.clock()
	local requested = lastRequestClock[player]
	if requested and impactClock - requested >= 0 and impactClock - requested <= Config.PERFECT_WINDOW then
		onParrySucceeded(player, attacker)
		return true
	end

	local deadline = impactClock + getLatencyCompensation(player)
	while os.clock() < deadline do
		task.wait()
		local late = lastRequestClock[player]
		if late and late > impactClock then
			onParrySucceeded(player, attacker)
			return true
		end
		if player.Parent ~= Players then
			return false
		end
	end
	return false
end

-- À appeler une seule fois au démarrage du serveur.
function ParryService.start()
	if isStarted then
		return
	end
	isStarted = true
	Remotes.RequestParry.OnServerEvent:Connect(onParryRequested)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestClock[player] = nil
		cooldownUntil[player] = nil
	end)
end

return ParryService
