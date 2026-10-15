--!strict
--[[
	AvatarRemotes
	Point d'accès unique aux RemoteEvents de la création de personnage.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		OpenCreator    serveur -> 1 client  ()                      ouvre l'écran de création
		PreviewAvatar  client  -> serveur   (selection: Selection)  aperçu en direct, sans valider
		ApplyAvatar    client  -> serveur   (selection: Selection)  choix final
		CreatorClosed  serveur -> 1 client  ()                      choix appliqué, le joueur est libéré
		RequestDestinySpin  client -> serveur   ()                  tourner la Roulette du Destin
		DestinyRevealed     serveur -> 1 client (magicId: string?, reason: string?)
		                    verdict de la roue (tiré par le serveur, une fois par personnage), renvoyé
		                    aussi à l'ouverture du créateur si la roue a déjà parlé ; nil + raison = refus
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "AvatarRemotes"
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
	OpenCreator = getRemote("OpenCreator"),
	PreviewAvatar = getRemote("PreviewAvatar"),
	ApplyAvatar = getRemote("ApplyAvatar"),
	CreatorClosed = getRemote("CreatorClosed"),
	RequestDestinySpin = getRemote("RequestDestinySpin"),
	DestinyRevealed = getRemote("DestinyRevealed"),
})
