--!strict
--[[
	EntitySnapshot
	Définit ce qu'est un snapshot et sait le lire / l'écrire sur un personnage.
	Fonctions pures vis-à-vis du reste du système : aucune notion de buffer ni de temps réel ici.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

export type Snapshot = {
	timestamp: number, -- temps de timeline (pas os.clock) auquel le snapshot a été pris
	cframe: CFrame, -- CFrame du HumanoidRootPart
	health: number,
	humanoidState: Enum.HumanoidStateType, -- conservé pour l'étape combat/animation, non réappliqué ici
	combatState: string?, -- valeur de l'attribut CombatState (nil si absent)
}

local EntitySnapshot = {}

-- Retourne le Humanoid et son RootPart, ou nil si le personnage n'est pas (encore) complet.
function EntitySnapshot.getParts(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil, nil
	end
	return humanoid, humanoid.RootPart
end

-- Photographie l'état courant. Retourne nil si le personnage est incomplet ou mort
-- (un Humanoid mort est irréversible : on ne veut pas de frames mortes dans l'historique).
function EntitySnapshot.capture(character: Model, timestamp: number): Snapshot?
	local humanoid, rootPart = EntitySnapshot.getParts(character)
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil
	end

	local combatState = character:GetAttribute(Config.COMBAT_STATE_ATTRIBUTE)

	return {
		timestamp = timestamp,
		cframe = rootPart.CFrame,
		health = humanoid.Health,
		humanoidState = humanoid:GetState(),
		combatState = if typeof(combatState) == "string" then combatState else nil,
	}
end

-- Applique l'état continu (position, santé) interpolé entre deux snapshots.
-- alpha = 0 -> `newer`, alpha = 1 -> `older`.
function EntitySnapshot.applyInterpolated(character: Model, newer: Snapshot, older: Snapshot, alpha: number)
	local humanoid, rootPart = EntitySnapshot.getParts(character)
	if humanoid == nil or rootPart == nil then
		return
	end

	rootPart.CFrame = newer.cframe:Lerp(older.cframe, alpha)
	humanoid.Health = newer.health + (older.health - newer.health) * alpha
end

-- Applique l'état discret (non interpolable) du snapshot d'arrivée, une seule fois en fin de rewind.
function EntitySnapshot.applyDiscreteState(character: Model, snapshot: Snapshot)
	character:SetAttribute(Config.COMBAT_STATE_ATTRIBUTE, snapshot.combatState)
end

return EntitySnapshot
