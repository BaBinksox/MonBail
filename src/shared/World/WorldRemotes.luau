--!strict
--[[
	WorldRemotes
	Point d'accès unique aux RemoteEvents du monde.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		Omen            serveur -> clients  (text: string)        un présage à afficher chez tous les joueurs
		MechanismPulse  serveur -> clients  (position: Vector3)   un mécanisme vient de répondre : petite
		                lueur et carillon discret à cet endroit (retour d'un bon geste)

	(La météo et l'humeur du monde ne passent par aucun remote : ce sont des attributs du Workspace.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "WorldRemotes"
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
	Omen = getRemote("Omen"),
	MechanismPulse = getRemote("MechanismPulse"),
})
