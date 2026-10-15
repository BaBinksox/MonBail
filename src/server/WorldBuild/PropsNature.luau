--!strict
--[[
	PropsNature
	Props naturels paramétrés : arbres morts tordus, rochers, buissons secs, souches, troncs couchés.

	Convention commune à tous les props (voir aussi PropsVillage et PropsBuildings) :
		- `base` est un CFrame LOCAL posé AU SOL (centre de l'emprise), LookVector = l'avant du prop ;
		- `random` est le Random partagé de la construction (context.random) : même graine, même forme ;
		- chaque prop retourne son Model (rangé dans `parent`).
	Les petites branches et brindilles sont des décors (CanCollide = false) ; troncs et rochers sont solides.

	API :
		PropsNature.deadTree(parent, base, height, random, options?): Model
		PropsNature.rock(parent, base, size, random, look?): Model
		PropsNature.rockCluster(parent, center, radius, count, random, look?): Model
		PropsNature.deadBush(parent, base, size, random): Model
		PropsNature.stump(parent, base, diameter, random): Model
		PropsNature.log(parent, from, to, diameter, look?): Model
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

type Look = Palette.Look

export type TreeOptions = {
	look: Look?, -- écorce (par défaut gris mort ; Palette.charredWood pour un arbre calciné)
	lean: number?, -- inclinaison max du tronc (degrés, défaut 12)
	branches: number?, -- nombre de branches maîtresses (défaut 3 à 5)
	collide: boolean?, -- tronc solide (défaut vrai)
}

local PropsNature = {}

--------------------------------------------------------------------------------
-- Arbre mort tordu
--------------------------------------------------------------------------------

-- Fait tourner `direction` d'angles aléatoires (degrés) pour tordre une branche.
local function bend(direction: Vector3, random: Random, maxDegrees: number): Vector3
	local yaw = math.rad(random:NextNumber(-maxDegrees, maxDegrees))
	local pitch = math.rad(random:NextNumber(-maxDegrees, maxDegrees))
	local rotated = (CFrame.Angles(pitch, yaw, 0) * CFrame.Angles(0, 0, pitch * 0.5)):VectorToWorldSpace(direction)
	return rotated.Unit
end

-- Branche en 2 ou 3 segments, de plus en plus fine ; brindilles au bout.
local function growBranch(model: Model, origin: Vector3, direction: Vector3, length: number, diameter: number, random: Random, look: Look, depth: number)
	local segments = if depth == 0 then 3 else 2
	local point = origin
	local dir = direction
	local d = diameter
	for s = 1, segments do
		local segLength = length / segments * random:NextNumber(0.8, 1.2)
		local nextPoint = point + dir * segLength
		Kit.rod(model, point, nextPoint, d, look, { decor = true })
		-- Rameau secondaire au milieu de la branche principale.
		if depth == 0 and s == 2 then
			local sideDir = bend(Vector3.new(dir.X, dir.Y + 0.4, dir.Z).Unit, random, 55)
			growBranch(model, nextPoint, sideDir, length * 0.45, d * 0.6, random, look, depth + 1)
		end
		point = nextPoint
		dir = bend(Vector3.new(dir.X, dir.Y + 0.12, dir.Z).Unit, random, 22)
		d = math.max(0.18, d * 0.68)
	end
end

--[[
	Arbre mort tordu : tronc en segments qui se tordent, branches maîtresses noueuses, racines.
	`height` : hauteur approximative du tronc (studs). ~15 Parts.
]]
function PropsNature.deadTree(parent: Instance, base: CFrame, height: number, random: Random, options: TreeOptions?): Model
	local opts: TreeOptions = options or {}
	local look = opts.look or (if random:NextNumber() < 0.5 then Palette.deadTree else Palette.deadTreeDark)
	local model = Kit.model(parent, "DeadTree", base)
	local lean = math.rad(opts.lean or 12)
	local trunkDiameter = math.clamp(height * 0.1, 1, 4)
	local segments = if height > 14 then 4 else 3
	local point = (base * CFrame.new(0, -1, 0)).Position
	local leanDir = base:VectorToWorldSpace(Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)))
	local dir = (Vector3.new(0, 1, 0) + leanDir * math.tan(random:NextNumber(0, lean))).Unit
	local d = trunkDiameter
	local branchCount = opts.branches or random:NextInteger(3, 5)
	local trunkPoints: { Vector3 } = {}

	for s = 1, segments do
		local segLength = (height + 1) / segments
		local nextPoint = point + dir * segLength
		Kit.rod(model, point, nextPoint, d, look, { collide = opts.collide ~= false, name = "Trunk" })
		table.insert(trunkPoints, nextPoint)
		point = nextPoint
		dir = bend(dir, random, 16)
		dir = Vector3.new(dir.X, math.max(dir.Y, 0.55), dir.Z).Unit
		d *= 0.78
	end

	-- Branches maîtresses, réparties sur la moitié haute du tronc.
	for b = 1, branchCount do
		local anchorIndex = math.clamp(segments - (b - 1) % 2, 2, #trunkPoints)
		local origin = trunkPoints[anchorIndex]
		local angle = (b / branchCount) * math.pi * 2 + random:NextNumber(-0.6, 0.6)
		local outward = Vector3.new(math.cos(angle), random:NextNumber(0.25, 0.9), math.sin(angle)).Unit
		growBranch(model, origin, outward, height * random:NextNumber(0.3, 0.5), trunkDiameter * 0.45, random, look, 0)
	end

	-- Racines qui s'agrippent au sol.
	local groundPoint = base.Position
	for r = 1, 3 do
		local angle = r * 2.1 + random:NextNumber(-0.4, 0.4)
		local tip = groundPoint + Vector3.new(math.cos(angle) * trunkDiameter * 1.6, -0.6, math.sin(angle) * trunkDiameter * 1.6)
		Kit.rod(model, groundPoint + Vector3.new(0, trunkDiameter * 0.4, 0), tip, trunkDiameter * 0.45, look, { decor = true })
	end
	return model
end

--------------------------------------------------------------------------------
-- Rochers
--------------------------------------------------------------------------------

-- Rocher anguleux : 2 ou 3 blocs inclinés qui s'interpénètrent. `size` = encombrement approximatif.
function PropsNature.rock(parent: Instance, base: CFrame, size: Vector3, random: Random, look: Look?): Model
	local rockLook = look or (if random:NextNumber() < 0.7 then Palette.rock else Palette.rockMossy)
	local model = Kit.model(parent, "Rock", base)
	local small = math.max(size.X, size.Y, size.Z) < 3
	local pieces = if small then 1 else random:NextInteger(2, 3)
	for i = 1, pieces do
		local scale = if i == 1 then 1 else random:NextNumber(0.5, 0.75)
		local pieceSize = Vector3.new(size.X * scale * random:NextNumber(0.75, 1), size.Y * scale * random:NextNumber(0.7, 1), size.Z * scale * random:NextNumber(0.75, 1))
		local offset = if i == 1
			then Vector3.zero
			else Vector3.new(random:NextNumber(-0.4, 0.4) * size.X, 0, random:NextNumber(-0.4, 0.4) * size.Z)
		local tilt = CFrame.Angles(math.rad(random:NextNumber(-18, 18)), math.rad(random:NextNumber(0, 360)), math.rad(random:NextNumber(-18, 18)))
		local cframe = base * CFrame.new(offset.X, pieceSize.Y * 0.32, offset.Z) * tilt
		local shade = Palette.darken(rockLook, random:NextNumber(0.85, 1.1))
		if random:NextNumber() < 0.35 and i > 1 then
			Kit.wedge(model, cframe, pieceSize, shade, { decor = small })
		else
			Kit.part(model, cframe, pieceSize, shade, { decor = small })
		end
	end
	return model
end

-- Amas de rochers dispersés dans un disque (le plus gros au centre).
function PropsNature.rockCluster(parent: Instance, center: CFrame, radius: number, count: number, random: Random, look: Look?): Model
	local model = Kit.model(parent, "RockCluster", center)
	for i = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = if i == 1 then 0 else random:NextNumber(0.3, 1) * radius
		local s = (if i == 1 then radius * 0.8 else radius * random:NextNumber(0.25, 0.5))
		local cframe = center * CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		PropsNature.rock(model, cframe, Vector3.new(s * 1.3, s, s * 1.1), random, look)
	end
	return model
end

--------------------------------------------------------------------------------
-- Végétation sèche
--------------------------------------------------------------------------------

-- Buisson sec : brindilles noires en éventail (décor pur).
function PropsNature.deadBush(parent: Instance, base: CFrame, size: number, random: Random): Model
	local model = Kit.model(parent, "DeadBush", base)
	local root = base.Position
	local count = random:NextInteger(4, 6)
	for i = 1, count do
		local angle = i / count * math.pi * 2 + random:NextNumber(-0.4, 0.4)
		local tip = root + Vector3.new(math.cos(angle) * size * 0.6, size * random:NextNumber(0.6, 1), math.sin(angle) * size * 0.6)
		Kit.rod(model, root, tip, 0.18, Palette.deadTreeDark, { decor = true })
	end
	return model
end

-- Souche noircie, coupée en biseau.
function PropsNature.stump(parent: Instance, base: CFrame, diameter: number, random: Random): Model
	local model = Kit.model(parent, "Stump", base)
	local height = diameter * random:NextNumber(0.6, 1)
	Kit.column(model, base * CFrame.new(0, -0.5, 0), height + 0.5, diameter, Palette.charredWood)
	Kit.wedge(model, base * CFrame.new(0, height + diameter * 0.15, 0) * CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0), Vector3.new(diameter * 0.7, diameter * 0.3, diameter * 0.7), Palette.charredWood, { decor = true })
	return model
end

-- Tronc couché entre deux points au sol.
function PropsNature.log(parent: Instance, from: Vector3, to: Vector3, diameter: number, look: Look?): Model
	local model = Kit.model(parent, "Log", CFrame.new((from + to) / 2))
	local lift = Vector3.new(0, diameter * 0.4, 0)
	Kit.rod(model, from + lift, to + lift, diameter, look or Palette.deadTreeDark)
	return model
end

return table.freeze(PropsNature)
