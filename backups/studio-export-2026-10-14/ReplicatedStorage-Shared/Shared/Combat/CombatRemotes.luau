--!strict
--[[
	CombatRemotes
	Point d'accès unique aux RemoteEvents du combat.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		RequestAttack    client  -> serveur          (comboIndex: number)
		ReportHit        client  -> serveur          (target: Model)   simple demande, le serveur vérifie tout
		RequestUltimate  client  -> serveur          ()                le serveur vérifie la Tension
		AttackStarted    serveur -> autres clients   (attacker: Model, comboIndex: number)   pour leurs VFX
		HitConfirmed     serveur -> clients          (attacker: Model, target: Model, damage: number)
		UltimateFired    serveur -> clients          (caster: Model, origin: Vector3, targets: { Model }, magicId: string)

	La Tension ne passe par aucun remote : c'est un attribut du Player (voir CombatConfig).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CombatRemotes"
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
	RequestAttack = getRemote("RequestAttack"),
	ReportHit = getRemote("ReportHit"),
	RequestUltimate = getRemote("RequestUltimate"),
	AttackStarted = getRemote("AttackStarted"),
	HitConfirmed = getRemote("HitConfirmed"),
	UltimateFired = getRemote("UltimateFired"),
})
