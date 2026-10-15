--!strict
--[[
	AnchorService
	Ancrage COMPTÉ des RootParts : plusieurs systèmes peuvent figer le même personnage en même temps
	(Hub de création, anomalie temporelle, rembobinage, charge du boss) sans se marcher dessus.

	Avant : chacun mémorisait son propre "wasAnchored" et le remettait en partant ; si deux systèmes
	se chevauchaient, le dernier à partir pouvait laisser le joueur figé (ou libérer trop tôt).
	Maintenant : chaque système DÉCLARE une raison (hold) puis la RETIRE (release). La pièce est ancrée
	tant qu'il reste au moins une raison, et retrouve son état d'origine quand la dernière part.

		AnchorService.hold(rootPart, "hub")
		AnchorService.release(rootPart, "hub")
]]

type Hold = {
	reasons: { [string]: boolean },
	originalAnchored: boolean, -- état d'avant la première raison
}

local AnchorService = {}

local holds: { [BasePart]: Hold } = setmetatable({}, { __mode = "k" }) :: any

local function countReasons(hold: Hold): number
	local count = 0
	for _ in hold.reasons do
		count += 1
	end
	return count
end

-- Fige `part` pour la raison `reason` (sans effet si cette raison est déjà posée).
function AnchorService.hold(part: BasePart, reason: string)
	local hold = holds[part]
	if hold == nil then
		hold = { reasons = {}, originalAnchored = part.Anchored }
		holds[part] = hold
	end
	hold.reasons[reason] = true
	part.Anchored = true
end

-- Retire la raison `reason`. Quand plus aucune raison ne reste, la pièce retrouve son état d'origine.
-- Retourne true si la pièce est désormais libérée de toute raison.
function AnchorService.release(part: BasePart, reason: string): boolean
	local hold = holds[part]
	if hold == nil or not hold.reasons[reason] then
		return hold == nil
	end
	hold.reasons[reason] = nil
	if countReasons(hold) == 0 then
		holds[part] = nil
		if part.Parent then
			part.Anchored = hold.originalAnchored
		end
		return true
	end
	return false
end

-- true si `part` est figée (pour `reason` précisément, ou pour n'importe quelle raison).
function AnchorService.isHeld(part: BasePart, reason: string?): boolean
	local hold = holds[part]
	if hold == nil then
		return false
	end
	return if reason then hold.reasons[reason] == true else true
end

-- Retire toutes les raisons (personnage détruit, téléportation forcée...). Restaure l'état d'origine.
function AnchorService.releaseAll(part: BasePart)
	local hold = holds[part]
	if hold then
		holds[part] = nil
		if part.Parent then
			part.Anchored = hold.originalAnchored
		end
	end
end

return AnchorService
