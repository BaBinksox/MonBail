--!strict
--[[
	CombatRemotes
	Point d'accès unique aux RemoteEvents du combat.
	Le serveur les crée au premier require ; le client attend leur réplication.

	Sens des événements :
		RequestAttack      client  -> serveur          (kind: number | "charged" | "counter" | "plunge")
		                                               1..5 = coup du combo ; le serveur vérifie l'ordre,
		                                               la cadence, la charge, la fenêtre de riposte...
		RequestChargeStart client  -> serveur          ()                début d'une attaque chargée
		ReportHit          client  -> serveur          (target: Model)   simple demande, le serveur vérifie tout
		RequestUltimate    client  -> serveur          ()                le serveur vérifie la Tension
		RequestConcentrate client  -> serveur          (wants: boolean)  posture de Concentration
		AttackStarted      serveur -> autres clients   (attacker: Model, comboIndex: number, action: string, power: number?)
		HitConfirmed       serveur -> clients          (attacker: Model, target: Model, damage: number, result: string?, hitStop: number?)
		                                               result : "hit" | "blocked" (garde) | "broken" (posture brisée)
		UltimateFired      serveur -> clients          (caster: Model, origin: Vector3, targets: { Model }, magicId: string)

	Mana, Tension et Concentration ne passent par aucun remote de valeur : ce sont des attributs du
	Player écrits par le serveur (voir ResourceConfig). Le client ne fait que demander.
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
	RequestChargeStart = getRemote("RequestChargeStart"),
	ReportHit = getRemote("ReportHit"),
	RequestUltimate = getRemote("RequestUltimate"),
	RequestConcentrate = getRemote("RequestConcentrate"),
	AttackStarted = getRemote("AttackStarted"),
	HitConfirmed = getRemote("HitConfirmed"),
	UltimateFired = getRemote("UltimateFired"),
})
