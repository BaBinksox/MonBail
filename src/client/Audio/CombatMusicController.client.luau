--!strict
--[[
	CombatMusicController (LocalScript)
	La musique suit le danger, sans à-coups (réglages : AudioConfig.COMBAT_MUSIC) :
		exploration      musique de la région (MusicController), rien à faire ici ;
		présence hostile un ennemi vivant à moins de HOSTILE_RADIUS pendant HOSTILE_ENTER_TIME s
		                 (et jusqu'à HOSTILE_EXIT_TIME s après le dernier) : couche « alert » ;
		combat           attribut InCombat du joueur (posé par le SERVEUR quand il frappe ou est
		                 frappé), gardé COMBAT_EXIT_TIME s après sa fin : couche « combat » ;
		boss             un boss réveillé à moins de BOSS_RADIUS : couche « boss » ;
		anomalie         anomalie temporelle ouverte (TimeLoopRemotes) : couche « anomaly » ;
		victoire / calme fin d'un combat où un ennemi proche a été vaincu : courte phrase, puis la
		                 région revient (là où elle s'était arrêtée, voir MusicDirector).
	Chaque état est une couche de MusicDirector : priorités, fondus croisés et reprise des pistes
	y sont gérés. Les hystérésis empêchent toute alternance rapide (frontière, ennemi qui va et vient).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(sharedFolder:WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local BossConfig = require(sharedFolder:WaitForChild("Boss"):WaitForChild("BossConfig") :: ModuleScript)
local ResourceConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ResourceConfig") :: ModuleScript)
local TimeLoopRemotes = require(sharedFolder:WaitForChild("TimeLoop"):WaitForChild("TimeLoopRemotes") :: ModuleScript)
local MusicDirector = require(script.Parent:WaitForChild("MusicDirector") :: ModuleScript)

local Config = AudioConfig.COMBAT_MUSIC
local TIME_LOOP_ENTITY_TAG = "TimeLoopEntity"
local DEFEATED_ATTRIBUTE = "Defeated"
local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local TRAINING_DUMMY_ID = "training_dummy"

local localPlayer = Players.LocalPlayer

local hostileSince: number? = nil -- os.clock() du début de la présence hostile continue
local lastHostileClock = -math.huge
local lastCombatClock = -math.huge
local wasInCombat = false
local engaged: { [Model]: boolean } = {} -- ennemis proches pendant le combat en cours
local victoryToken = 0

local function rootPosition(): Vector3?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function isLivingEnemy(model: Instance): boolean
	if not model:IsA("Model") or model:GetAttribute(DEFEATED_ATTRIBUTE) == true or not model:IsDescendantOf(workspace) then
		return false
	end
	if model:GetAttribute(ENEMY_ID_ATTRIBUTE) == TRAINING_DUMMY_ID then
		return false -- le mannequin d'entraînement n'est pas une menace
	end
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function distanceTo(model: Model, position: Vector3): number
	return (model:GetPivot().Position - position).Magnitude
end

-- Un boss réveillé (pas au repos) est-il assez proche pour imposer sa musique ?
local function isBossActive(position: Vector3, inCombat: boolean): boolean
	for _, boss in CollectionService:GetTagged(BossConfig.TAG) do
		if boss:IsA("Model") and isLivingEnemy(boss) and distanceTo(boss, position) <= Config.BOSS_RADIUS then
			local state = boss:GetAttribute(BossConfig.STATE_ATTRIBUTE)
			if inCombat or (state ~= nil and state ~= BossConfig.STATES.Idle and state ~= BossConfig.STATES.Dead) then
				return true
			end
		end
	end
	return false
end

local function playVictory()
	victoryToken += 1
	local token = victoryToken
	MusicDirector.set("victory", "victory")
	task.delay(Config.VICTORY_DURATION, function()
		if token == victoryToken then
			MusicDirector.set("victory", nil)
		end
	end)
end

local function update()
	local position = rootPosition()
	local now = os.clock()
	if position == nil or localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true then
		MusicDirector.set("alert", nil)
		MusicDirector.set("combat", nil)
		MusicDirector.set("boss", nil)
		hostileSince = nil
		return
	end

	-- Présence hostile (avec hystérésis d'entrée et de sortie).
	local hostileNear = false
	for _, model in CollectionService:GetTagged(TIME_LOOP_ENTITY_TAG) do
		if isLivingEnemy(model) and distanceTo(model :: Model, position) <= Config.HOSTILE_RADIUS then
			hostileNear = true
			break
		end
	end
	if hostileNear then
		lastHostileClock = now
		hostileSince = hostileSince or now
	elseif now - lastHostileClock > Config.HOSTILE_EXIT_TIME then
		hostileSince = nil
	end
	local isAlert = hostileSince ~= nil and now - (hostileSince :: number) >= Config.HOSTILE_ENTER_TIME

	-- Combat (état du serveur, gardé quelques secondes).
	local serverInCombat = localPlayer:GetAttribute(ResourceConfig.IN_COMBAT_ATTRIBUTE) == true
	if serverInCombat then
		lastCombatClock = now
	end
	local inCombat = now - lastCombatClock <= Config.COMBAT_EXIT_TIME
	if inCombat then
		for _, model in CollectionService:GetTagged(TIME_LOOP_ENTITY_TAG) do
			if model:IsA("Model") and isLivingEnemy(model) and distanceTo(model, position) <= Config.VICTORY_RADIUS then
				engaged[model] = true
			end
		end
	end
	if wasInCombat and not inCombat then
		-- Fin du combat : victoire si un ennemi engagé est tombé (vaincu ou disparu).
		local hasVictory = false
		for model in engaged do
			if model:GetAttribute(DEFEATED_ATTRIBUTE) == true or not model:IsDescendantOf(workspace) then
				hasVictory = true
			end
		end
		engaged = {}
		if hasVictory then
			playVictory()
		end
	end
	wasInCombat = inCombat

	local bossActive = isBossActive(position, inCombat)
	MusicDirector.set("boss", if bossActive then "boss" else nil)
	MusicDirector.set("combat", if inCombat and not bossActive then "combat" else nil)
	MusicDirector.set("alert", if isAlert and not inCombat then "hostile" else nil)
	if inCombat or bossActive then
		victoryToken += 1 -- un nouveau combat coupe la phrase de victoire
		MusicDirector.set("victory", nil)
	end
end

TimeLoopRemotes.AnomalyOpened.OnClientEvent:Connect(function()
	MusicDirector.set("anomaly", "anomaly")
end)
TimeLoopRemotes.AnomalyClosed.OnClientEvent:Connect(function()
	MusicDirector.set("anomaly", nil)
end)
localPlayer.CharacterAdded:Connect(function()
	MusicDirector.set("anomaly", nil)
	engaged = {}
end)

task.spawn(function()
	while true do
		local isOk, message = pcall(function()
			update()
		end)
		if not isOk then
			warn(`[Musique] {message}`)
		end
		task.wait(Config.UPDATE_INTERVAL)
	end
end)
