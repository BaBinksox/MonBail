--!strict
--[[
	VillagerService
	La vie du village, côté serveur (singleton). Tout Model taggé "Villager" qui a un Humanoid :
		- se promène autour de l'endroit où il a été posé (sauf attribut Wanders = false) ;
		- s'arrête et se tourne vers le joueur qui lui adresse la parole, puis reprend sa route.

	Le dialogue (texte, son, interface) est géré par chaque client : voir NPCInteraction.
	Une seule boucle fait bouger tous les villageois, quel que soit leur nombre.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage.Shared.Avatar.AvatarConfig)
local Config = require(ReplicatedStorage.Shared.NPC.DialogueConfig)
local Remotes = require(ReplicatedStorage.Shared.NPC.NPCRemotes)

local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)

local THINK_INTERVAL = 0.5 -- secondes entre deux passages de la boucle
local TALK_DISTANCE_TOLERANCE = 6 -- studs de marge sur la distance d'interaction (latence, déplacement)

type Villager = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	home: Vector3, -- point autour duquel il se promène
	canWander: boolean,
	nextMoveClock: number,
	talkingUntil: number, -- os.clock() jusqu'auquel il reste auprès d'un joueur
	talkers: { [Player]: boolean }, -- joueurs qui lui parlent en ce moment (il attend que tous aient fini)
}

local VillagerService = {}

local random = Random.new()
local villagers: { [Model]: Villager } = {}
local talkingWith: { [Player]: Villager } = {}
local talkLimiter = RateLimiter.new(1, 3) -- un client ne peut pas faire pivoter un villageois en boucle
local isStarted = false

--------------------------------------------------------------------------------
-- Inscription
--------------------------------------------------------------------------------

-- Animation de marche, jouée par le serveur dès que le villageois avance (répliquée aux clients).
local function setupWalkAnimation(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local animation = Instance.new("Animation")
	animation.AnimationId = Config.WALK_ANIMATION_ID

	local isLoaded, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not isLoaded then
		return -- rig incompatible (R6...) : il glissera sans animation
	end

	humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			if not track.IsPlaying then
				track:Play(0.2)
			end
		else
			track:Stop(0.2)
		end
	end)
end

local function registerVillager(instance: Instance)
	-- Les tags suivent aussi les modèles rangés dans ServerStorage : on ne veut que ceux en jeu.
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or villagers[instance] then
		return
	end

	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil then
		return -- simple décor parlant (statue, panneau...) : rien à animer côté serveur
	end

	humanoid.WalkSpeed = Config.WANDER_SPEED
	-- Un villageois ancré dans Studio ne peut pas marcher : il reste sur place, mais se tournera vers le joueur.
	local canWander = instance:GetAttribute(Config.WANDER_ATTRIBUTE) ~= false and not rootPart.Anchored
	if canWander then
		-- Simulé par le serveur, pas par le client le plus proche. (Interdit si une autre pièce
		-- du rig est ancrée, d'où la vérification.)
		if rootPart:CanSetNetworkOwnership() then
			rootPart:SetNetworkOwner(nil)
		end
		setupWalkAnimation(humanoid)
	end

	villagers[instance] = {
		model = instance,
		humanoid = humanoid,
		rootPart = rootPart,
		home = rootPart.Position,
		canWander = canWander,
		nextMoveClock = os.clock() + random:NextNumber(0, Config.WANDER_PAUSE_MAX),
		talkingUntil = 0,
		talkers = {},
	}
end

local function unregisterVillager(instance: Instance)
	if instance:IsA("Model") then
		villagers[instance] = nil
	end
end

--------------------------------------------------------------------------------
-- Promenade
--------------------------------------------------------------------------------

local function wander(villager: Villager)
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(Config.WANDER_RADIUS * 0.3, Config.WANDER_RADIUS)
	local destination = villager.home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	villager.humanoid:MoveTo(destination)
end

local function runVillage()
	while true do
		local now = os.clock()
		for model, villager in villagers do
			if model.Parent == nil or villager.humanoid.Health <= 0 then
				villagers[model] = nil
			elseif villager.canWander and now >= villager.talkingUntil and now >= villager.nextMoveClock then
				villager.nextMoveClock = now + random:NextNumber(Config.WANDER_PAUSE_MIN, Config.WANDER_PAUSE_MAX)
				wander(villager)
			end
		end
		task.wait(THINK_INTERVAL)
	end
end

--------------------------------------------------------------------------------
-- Conversation
--------------------------------------------------------------------------------

local function onTalkEnded(player: Player)
	local villager = talkingWith[player]
	if villager == nil then
		return
	end
	talkingWith[player] = nil
	villager.talkers[player] = nil
	if next(villager.talkers) == nil then
		villager.talkingUntil = 0
		villager.nextMoveClock = os.clock() + Config.WANDER_PAUSE_MIN -- il ne repart pas dans la seconde
	end
end

local function onTalkStarted(player: Player, target: any)
	if typeof(target) ~= "Instance" or not talkLimiter:allow(player) then
		return
	end
	if player:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true then
		return
	end
	local villager = villagers[target :: any]
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if villager == nil or playerRoot == nil or not playerRoot:IsA("BasePart") then
		return
	end

	-- Le client ne peut pas immobiliser un villageois à l'autre bout du monde.
	local distance = (playerRoot.Position - villager.rootPart.Position).Magnitude
	if distance > Config.INTERACT_DISTANCE + TALK_DISTANCE_TOLERANCE then
		return
	end

	-- Parler à un autre villageois termine la conversation précédente (il n'attend pas 45 s pour rien).
	if talkingWith[player] and talkingWith[player] ~= villager then
		onTalkEnded(player)
	end
	villager.talkingUntil = os.clock() + Config.TALK_TIMEOUT
	villager.talkers[player] = true
	talkingWith[player] = villager

	-- Il s'arrête et fait face au joueur.
	local origin = villager.rootPart.Position
	villager.humanoid:MoveTo(origin)
	local lookTarget = Vector3.new(playerRoot.Position.X, origin.Y, playerRoot.Position.Z)
	if (lookTarget - origin).Magnitude > 0.1 then
		villager.rootPart.CFrame = CFrame.lookAt(origin, lookTarget)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function VillagerService.start()
	if isStarted then
		return
	end
	isStarted = true

	CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(registerVillager)
	CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(unregisterVillager)
	for _, instance in CollectionService:GetTagged(Config.TAG) do
		registerVillager(instance)
	end

	Remotes.TalkStarted.OnServerEvent:Connect(onTalkStarted)
	Remotes.TalkEnded.OnServerEvent:Connect(onTalkEnded)
	Players.PlayerRemoving:Connect(onTalkEnded)

	task.spawn(runVillage)
end

return VillagerService
