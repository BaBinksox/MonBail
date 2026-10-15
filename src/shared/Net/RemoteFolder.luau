--!strict
--[[
	RemoteFolder
	Fabrique des dossiers de Remotes des NOUVEAUX systèmes, sur le même principe que les modules
	*Remotes existants : le serveur crée le dossier et ses objets au premier require, le client
	attend leur réplication.

		local remotes = RemoteFolder.new("QuestRemotes")
		local QuestUpdated = remotes:event("QuestUpdated")      -- RemoteEvent
		local GetJournal = remotes:func("GetJournal")           -- RemoteFunction

	Un nom de dossier doit être unique dans ReplicatedStorage (préfixe = nom du système).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local CLIENT_WAIT_TIMEOUT = 30 -- secondes avant d'avertir qu'un Remote n'arrive pas (le client continue d'attendre)

local RemoteFolder = {}
RemoteFolder.__index = RemoteFolder

type FolderData = {
	_folder: Instance,
}

export type RemoteFolder = typeof(setmetatable({} :: FolderData, RemoteFolder))

local function waitForChildWarned(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	if child == nil then
		warn(`[Net] {parent:GetFullName()}.{name} n'existe toujours pas : le serveur l'a-t-il créé ?`)
		child = parent:WaitForChild(name)
	end
	return child :: Instance
end

function RemoteFolder.new(folderName: string): RemoteFolder
	local folder: Instance
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(folderName)
		if existing then
			folder = existing
		else
			local newFolder = Instance.new("Folder")
			newFolder.Name = folderName
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
	else
		folder = waitForChildWarned(ReplicatedStorage, folderName)
	end
	local data: FolderData = { _folder = folder }
	return setmetatable(data, RemoteFolder)
end

local function getOrCreate(self: RemoteFolder, className: string, name: string): Instance
	if IS_SERVER then
		local existing = self._folder:FindFirstChild(name)
		if existing and existing.ClassName == className then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = self._folder
		return remote
	end
	return waitForChildWarned(self._folder, name)
end

function RemoteFolder.event(self: RemoteFolder, name: string): RemoteEvent
	return getOrCreate(self, "RemoteEvent", name) :: RemoteEvent
end

function RemoteFolder.unreliable(self: RemoteFolder, name: string): UnreliableRemoteEvent
	return getOrCreate(self, "UnreliableRemoteEvent", name) :: UnreliableRemoteEvent
end

function RemoteFolder.func(self: RemoteFolder, name: string): RemoteFunction
	return getOrCreate(self, "RemoteFunction", name) :: RemoteFunction
end

return RemoteFolder
