--!strict
--[[
	EchoService
	Les échos temporels (Shared/World/EchoConfig) : des scènes effacées que le temps rejoue.

	Le SERVEUR décide : un joueur qui s'approche de l'ancre d'un écho (triggerRadius), pour qui l'écho
	est pertinent (étape de quête, ou écho libre), et dont le délai de revisionnage est passé, reçoit
	PlayEcho. Pendant la durée de l'écho, il doit rester à proximité du trajet (watchRadius) ; sinon
	l'écho se dissipe (StopEcho) et ne compte pas. À la fin : GameEvents.EchoWitnessed (objectif "echo"
	des quêtes) et la découverte de l'écho. Le client ne fait que l'afficher : il ne peut pas
	prétendre avoir vu un écho.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EchoConfig = require(ReplicatedStorage.Shared.World.EchoConfig)
local Remotes = require(ReplicatedStorage.Shared.World.EchoRemotes)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local QuestService = require(script.Parent.Parent.Quest.QuestService)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local WorldAnchors = require(script.Parent.WorldAnchors)

local POLL_INTERVAL = 0.5
local FINAL_LINGER = 2.5 -- secondes après le dernier point (la silhouette s'efface)
local FAILED_RETRY_DELAY = 6 -- secondes avant de pouvoir revoir un écho interrompu

type Viewing = {
	echoId: string,
	points: { Vector3 },
	endsAt: number, -- os.clock()
}

local EchoService = {}

local viewing: { [Player]: Viewing } = {}
local nextAllowed: { [Player]: { [string]: number } } = {}
local isStarted = false

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil
	end
	return rootPart
end

-- Durée de l'écho : marche entre les points + pauses des actions + effacement final.
local function computeDuration(echo: EchoConfig.Echo, points: { Vector3 }): number
	local duration = FINAL_LINGER
	for index = 2, #points do
		duration += (points[index] - points[index - 1]).Magnitude / echo.walkSpeed
	end
	for _, action in echo.actions do
		duration += action.pause
	end
	return duration
end

local function distanceToPath(position: Vector3, points: { Vector3 }): number
	local best = math.huge
	for _, point in points do
		best = math.min(best, (point - position).Magnitude)
	end
	return best
end

local function isRelevant(player: Player, echo: EchoConfig.Echo): boolean
	local requirement = echo.requiresQuest
	if requirement == nil then
		return true
	end
	return QuestService.isAtStage(player, requirement.quest, requirement.stage)
end

local function setNextAllowed(player: Player, echoId: string, delay: number)
	local perPlayer = nextAllowed[player]
	if perPlayer == nil then
		perPlayer = {}
		nextAllowed[player] = perPlayer
	end
	perPlayer[echoId] = os.clock() + delay
end

local function tryStart(player: Player, rootPart: BasePart)
	for echoId, echo in EchoConfig.ECHOES do
		local anchor = WorldAnchors.getCFrame(echo.anchor)
		if anchor == nil or (anchor.Position - rootPart.Position).Magnitude > echo.triggerRadius then
			continue
		end
		local perPlayer = nextAllowed[player]
		if perPlayer and (perPlayer[echoId] or 0) > os.clock() then
			continue
		end
		if not isRelevant(player, echo) then
			continue
		end
		local points = WorldAnchors.getEchoPath(echo.pathFolder)
		if #points < 2 then
			continue
		end
		viewing[player] = { echoId = echoId, points = points, endsAt = os.clock() + computeDuration(echo, points) }
		Remotes.PlayEcho:FireClient(player, echoId, points, workspace:GetServerTimeNow())
		return
	end
end

local function update(player: Player)
	local rootPart = getRoot(player)
	local current = viewing[player]
	if current then
		local echo = EchoConfig.ECHOES[current.echoId]
		if rootPart == nil or distanceToPath(rootPart.Position, current.points) > echo.watchRadius then
			viewing[player] = nil
			setNextAllowed(player, current.echoId, FAILED_RETRY_DELAY)
			Remotes.StopEcho:FireClient(player, current.echoId)
		elseif os.clock() >= current.endsAt then
			viewing[player] = nil
			setNextAllowed(player, current.echoId, echo.replayCooldown)
			GameEvents.EchoWitnessed:Fire(player, current.echoId)
			if echo.discovery then
				RewardService.discover(player, echo.discovery)
			end
		end
		return
	end
	if rootPart and not AvatarService.isCustomizing(player) then
		tryStart(player, rootPart)
	end
end

-- À appeler une seule fois au démarrage du serveur (après QuestService).
function EchoService.start()
	if isStarted then
		return
	end
	isStarted = true
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			for _, player in Players:GetPlayers() do
				local isUpdated, message = pcall(function()
					update(player)
				end)
				if not isUpdated then
					warn(`[Echo] {player.Name} : {message}`)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		viewing[player] = nil
		nextAllowed[player] = nil
	end)
end

return EchoService
