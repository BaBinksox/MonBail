--!strict
--[[
	MovementRemotes
	Point d'accès unique aux RemoteEvents de la mobilité.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		RequestDash  client  -> serveur          ()                  le serveur vérifie le cooldown
		DashStarted  serveur -> autres clients   (character: Model)  pour leurs VFX
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "MovementRemotes"
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
	RequestDash = getRemote("RequestDash"),
	DashStarted = getRemote("DashStarted"),
})
