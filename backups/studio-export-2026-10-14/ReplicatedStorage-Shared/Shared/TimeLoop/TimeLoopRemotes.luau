--!strict
--[[
	TimeLoopRemotes
	Point d'accès unique aux RemoteEvents du Time-Loop.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		RequestRewind  client  -> serveur   (aucun argument : le serveur ne fait confiance à rien)
		AnomalyOpened  serveur -> 1 client  (windowDuration: number)
		AnomalyClosed  serveur -> 1 client  ()   quelle que soit l'issue : rewind, mort, respawn
		RewindStarted  serveur -> clients   (playbackDuration: number)
		RewindEnded    serveur -> clients   ()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "TimeLoopRemotes"
local IS_SERVER = RunService:IsServer()

local function getFolder(): Instance
	if IS_SERVER then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local folder = getFolder()

local function getRemote(name: string): RemoteEvent
	if IS_SERVER then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return table.freeze({
	RequestRewind = getRemote("RequestRewind"),
	AnomalyOpened = getRemote("AnomalyOpened"),
	AnomalyClosed = getRemote("AnomalyClosed"),
	RewindStarted = getRemote("RewindStarted"),
	RewindEnded = getRemote("RewindEnded"),
})
