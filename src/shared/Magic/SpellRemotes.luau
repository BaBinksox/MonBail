--!strict
--[[
	SpellRemotes
	RemoteEvents des sorts et des réactions élémentaires. Le serveur les crée au premier require ;
	le client attend leur réplication.

		RequestCast       client  -> serveur   (spellId: string, aimPoint: Vector3)
		                                       simple demande : le serveur vérifie la magie du joueur,
		                                       le Mana, la recharge, la portée, la ligne de vue...
		SpellCast         serveur -> clients   (caster: Model, spellId: string, castId: number,
		                                        origin: Vector3, aimPoint: Vector3)   pour les VFX
		SpellImpact       serveur -> clients   (castId: number, spellId: string, position: Vector3,
		                                        targets: { Model })
		ReactionTriggered serveur -> clients   (target: Model, reactionId: string, position: Vector3)
		CastDenied        serveur -> client    (spellId: string, reason: string)  "mana" | "cooldown" | ...
	Aucun montant de dégâts, de Mana ou d'état d'ennemi ne vient du client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SpellRemotes"
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
	RequestCast = getRemote("RequestCast"),
	SpellCast = getRemote("SpellCast"),
	SpellImpact = getRemote("SpellImpact"),
	ReactionTriggered = getRemote("ReactionTriggered"),
	CastDenied = getRemote("CastDenied"),
})
