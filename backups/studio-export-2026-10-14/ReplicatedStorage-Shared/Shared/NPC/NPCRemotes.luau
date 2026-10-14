--!strict
--[[
	NPCRemotes
	Point d'accès unique aux RemoteEvents des PNJ.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Le dialogue lui-même est entièrement local au joueur. Ces événements servent seulement à ce que
	le villageois, côté serveur, s'arrête et se tourne vers lui :
		TalkStarted  client -> serveur  (villager: Model)
		TalkEnded    client -> serveur  ()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "NPCRemotes"
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
	TalkStarted = getRemote("TalkStarted"),
	TalkEnded = getRemote("TalkEnded"),
})
