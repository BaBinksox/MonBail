--!strict
--[[
	TerrainSculpt
	Sculpture du terrain de la Région 1 : outils réutilisables + relief de la région.

	COORDONNÉES LOCALES (repère de RegionConfig.LAYOUT), comme le Kit.

	MODÈLE DE HAUTEUR : chaque opération passée par ce module est aussi enregistrée, ce qui permet de
	demander la hauteur du sol n'importe où (heightAt) pour y poser des props sans les faire flotter.
	Toute modification du terrain DOIT donc passer par ce module (jamais workspace.Terrain directement),
	sinon heightAt l'ignore. La précision réelle est celle des voxels Roblox (4 studs) : enfoncez
	légèrement les bases des props (0,5 à 1 stud).

	ORDRE : les opérations s'appliquent dans l'ordre d'appel. Un remplissage écrase ce qui est dessous
	(l'eau aussi !), un creusement (Air) vide. Creusez les cavités (crypte, grotte) en DERNIER.

	API générique :
		TerrainSculpt.reset()                                  -- oublie le modèle (début de construction)
		TerrainSculpt.zoneBounds(): (Vector3, Vector3)         -- zone de terrain possédée par le générateur
		TerrainSculpt.clearZone()                              -- vide la zone (FillBlock Air, blocs <= 512)
		TerrainSculpt.fillBlock(cframe, size, material)        -- primitives (enregistrées)
		TerrainSculpt.fillWedge(cframe, size, material)        -- même orientation qu'un WedgePart
		TerrainSculpt.fillBall(center, radius, material)
		TerrainSculpt.fillCylinder(cframe, height, radius, material)  -- axe = Y du cframe
		TerrainSculpt.fillBox(min, max, material)              -- boîte alignée, découpée en blocs <= 512
		TerrainSculpt.carve(cframe, size) / carveBox(min, max) / carveBall(center, radius)
		TerrainSculpt.carveCylinder(cframe, height, radius)
		TerrainSculpt.hill(center, radius, height, material, options?)  -- butte en disques (profil cos²)
		TerrainSculpt.mountain(base, radius, height, material, random)  -- pic rocheux (boules)
		TerrainSculpt.ridge(points, radius, height, material, random)   -- chaîne de pics le long d'une ligne
		TerrainSculpt.incline(low, high, width, material, fillBelow?)   -- plan incliné (coin de terrain)
		TerrainSculpt.ramp(from, to, width, material, options?)         -- rampe de chemin (remplit + dégage au-dessus)
		TerrainSculpt.path(points, width, material, options?)           -- bande de matériau qui suit le sol
		TerrainSculpt.patch(center, radius, material)                   -- tache de matériau qui suit le sol
		TerrainSculpt.flatten(center, radius, material?, clearHeight?)  -- aplanit un disque à center.Y
		TerrainSculpt.heightAt(x, z): number                            -- hauteur du sol (modèle)
		TerrainSculpt.groundAt(position, sink?): Vector3                -- point ramené au sol
		TerrainSculpt.onGround(x, z, yawDegrees?, sink?): CFrame        -- CFrame posé au sol
		TerrainSculpt.onGroundFacing(position, target, sink?): CFrame   -- posé au sol, tourné vers target
		TerrainSculpt.footprint(cframe, sizeX, sizeZ): (number, number) -- hauteurs min / max d'une emprise
		TerrainSculpt.opCount(): number

	Relief de la région (appelé par WorldBuilder, avant les zones) :
		TerrainSculpt.sculptRegion(random) -- sol de base, lac au nord, montagnes de bordure, belvédère,
		                                      butte de la chapelle, pente du cimetière, col de la Porte
		                                      des Murmures, collines de l'est.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local Config = require(script.Parent.WorldBuildConfig)

export type HillOptions = {
	flatTop: number?, -- rayon du plateau sommital (0 = sommet arrondi)
	steps: number?, -- nombre de disques (par défaut : un tous les 1,6 stud de hauteur)
	random: Random?, -- pour décaler légèrement les disques (aspect naturel)
	jitter: number?, -- amplitude de ce décalage (studs)
}

export type PathOptions = {
	follow: boolean?, -- vrai (défaut) : ignore le Y des points et suit le sol (heightAt)
	thickness: number?, -- épaisseur de la bande (défaut 3)
	raise: number?, -- dépassement au-dessus du sol (défaut 0,25)
	step: number?, -- longueur max d'un tronçon (défaut 8)
	random: Random?, -- variation de largeur (bords irréguliers)
	widthJitter: number?, -- fraction de variation de largeur (défaut 0)
}

export type RampOptions = {
	thickness: number?, -- épaisseur sous la surface (défaut 8)
	clearance: number?, -- hauteur dégagée au-dessus (défaut 12)
}

type OpKind = "block" | "wedge" | "ball" | "cylinder"

type Op = {
	kind: OpKind,
	solid: boolean, -- false pour Air et Water (n'élèvent pas le sol)
	inverse: CFrame, -- repère local de la forme (inverse de son CFrame)
	half: Vector3, -- demi-taille (block / wedge / cylinder : rayon en X et Z, demi-hauteur en Y)
	center: Vector3,
	radius: number,
	vertical: boolean, -- cylindre debout (calcul exact)
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

local L = RegionConfig.LAYOUT
local ORIGIN_CFRAME = CFrame.new(RegionConfig.ORIGIN)
local AIR = Enum.Material.Air
local WATER = Enum.Material.Water
local CHUNK = Config.TERRAIN_CHUNK

local ZONE_MIN = L.playableMin - Config.TERRAIN_MARGIN_MIN
local ZONE_MAX = L.playableMax + Config.TERRAIN_MARGIN_MAX

local TerrainSculpt = {}

local ops: { Op } = {}

local function getTerrain(): Terrain
	return workspace.Terrain
end

--------------------------------------------------------------------------------
-- Modèle de hauteur
--------------------------------------------------------------------------------

local function record(kind: OpKind, material: Enum.Material, cframe: CFrame, half: Vector3, radius: number)
	local center = cframe.Position
	-- Emprise horizontale conservatrice (rayon de la sphère englobante).
	local reach = if kind == "ball" then radius else half.Magnitude
	local up = cframe.UpVector
	table.insert(ops, {
		kind = kind,
		solid = material ~= AIR and material ~= WATER,
		inverse = cframe:Inverse(),
		half = half,
		center = center,
		radius = radius,
		vertical = math.abs(up.Y) > 0.999,
		minX = center.X - reach,
		maxX = center.X + reach,
		minZ = center.Z - reach,
		maxZ = center.Z + reach,
	})
end

-- Intersection d'une droite paramétrée (o + t d) avec une "tranche" |x| <= half.
local function clipSlab(o: number, d: number, half: number, tMin: number, tMax: number): (number, number)
	if math.abs(d) < 1e-9 then
		if math.abs(o) > half then
			return 1, 0
		end
		return tMin, tMax
	end
	local t1 = (-half - o) / d
	local t2 = (half - o) / d
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	return math.max(tMin, t1), math.min(tMax, t2)
end

-- Intervalle [bas, haut] de la forme sur la verticale (x, z) ; bas > haut si vide.
local function columnInterval(op: Op, x: number, z: number): (number, number)
	if op.kind == "ball" then
		local dx, dz = x - op.center.X, z - op.center.Z
		local d2 = dx * dx + dz * dz
		local r2 = op.radius * op.radius
		if d2 > r2 then
			return 1, 0
		end
		local h = math.sqrt(r2 - d2)
		return op.center.Y - h, op.center.Y + h
	end
	if op.kind == "cylinder" and op.vertical then
		local dx, dz = x - op.center.X, z - op.center.Z
		if dx * dx + dz * dz > op.radius * op.radius then
			return 1, 0
		end
		return op.center.Y - op.half.Y, op.center.Y + op.half.Y
	end
	-- Bloc, coin ou cylindre incliné (approché par sa boîte) : droite verticale dans le repère local.
	local o = op.inverse * Vector3.new(x, 0, z)
	local d = op.inverse:VectorToWorldSpace(Vector3.new(0, 1, 0))
	local tMin, tMax = -1e6, 1e6
	tMin, tMax = clipSlab(o.X, d.X, op.half.X, tMin, tMax)
	tMin, tMax = clipSlab(o.Y, d.Y, op.half.Y, tMin, tMax)
	tMin, tMax = clipSlab(o.Z, d.Z, op.half.Z, tMin, tMax)
	if op.kind == "wedge" and tMin <= tMax then
		-- Demi-espace sous la pente : y / sy <= z / sz (arête haute à +Z local).
		local ay, az = 1 / (2 * op.half.Y), -1 / (2 * op.half.Z)
		local k0 = ay * o.Y + az * o.Z
		local k1 = ay * d.Y + az * d.Z
		if math.abs(k1) < 1e-9 then
			if k0 > 0 then
				return 1, 0
			end
		elseif k1 > 0 then
			tMax = math.min(tMax, -k0 / k1)
		else
			tMin = math.max(tMin, -k0 / k1)
		end
	end
	return tMin, tMax
end

-- Hauteur du sol solide en (x, z) d'après les opérations enregistrées (-math.huge si vide).
function TerrainSculpt.heightAt(x: number, z: number): number
	local height = -math.huge
	for _, op in ops do
		if x >= op.minX and x <= op.maxX and z >= op.minZ and z <= op.maxZ then
			local bottom, top = columnInterval(op, x, z)
			if bottom <= top then
				if op.solid then
					if top > height then
						height = top
					end
				elseif height <= top and height > bottom then
					height = bottom
				end
			end
		end
	end
	return height
end

-- Le point `position` ramené à la hauteur du sol (modèle), enfoncé de `sink` studs.
function TerrainSculpt.groundAt(position: Vector3, sink: number?): Vector3
	return Vector3.new(position.X, TerrainSculpt.heightAt(position.X, position.Z) - (sink or 0), position.Z)
end

--[[
	CFrame posé au sol en (x, z), tourné de `yawDegrees` autour de Y (0 = regarde le nord, -Z ;
	90 = l'ouest), enfoncé de `sink` studs. Le raccourci pour poser un prop sur le relief.
]]
function TerrainSculpt.onGround(x: number, z: number, yawDegrees: number?, sink: number?): CFrame
	local cframe = CFrame.new(x, TerrainSculpt.heightAt(x, z) - (sink or 0), z)
	if yawDegrees and yawDegrees ~= 0 then
		cframe *= CFrame.Angles(0, math.rad(yawDegrees), 0)
	end
	return cframe
end

-- CFrame posé au sol en `position` (Y ignoré), regard horizontal vers `target`.
function TerrainSculpt.onGroundFacing(position: Vector3, target: Vector3, sink: number?): CFrame
	local p = TerrainSculpt.groundAt(position, sink)
	local flat = Vector3.new(target.X, p.Y, target.Z)
	if (flat - p).Magnitude < 1e-3 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, flat)
end

-- Hauteurs min et max du sol sous une emprise rectangulaire (coins + milieux + centre).
function TerrainSculpt.footprint(cframe: CFrame, sizeX: number, sizeZ: number): (number, number)
	local low, high = math.huge, -math.huge
	for _, fx in { -0.5, 0, 0.5 } do
		for _, fz in { -0.5, 0, 0.5 } do
			local p = cframe * Vector3.new(sizeX * fx, 0, sizeZ * fz)
			local h = TerrainSculpt.heightAt(p.X, p.Z)
			low = math.min(low, h)
			high = math.max(high, h)
		end
	end
	return low, high
end

function TerrainSculpt.opCount(): number
	return #ops
end

function TerrainSculpt.reset()
	table.clear(ops)
end

function TerrainSculpt.zoneBounds(): (Vector3, Vector3)
	return ZONE_MIN, ZONE_MAX
end

--------------------------------------------------------------------------------
-- Primitives (toutes enregistrées)
--------------------------------------------------------------------------------

function TerrainSculpt.fillBlock(cframe: CFrame, size: Vector3, material: Enum.Material)
	getTerrain():FillBlock(ORIGIN_CFRAME * cframe, size, material)
	record("block", material, cframe, size / 2, 0)
end

function TerrainSculpt.fillWedge(cframe: CFrame, size: Vector3, material: Enum.Material)
	getTerrain():FillWedge(ORIGIN_CFRAME * cframe, size, material)
	record("wedge", material, cframe, size / 2, 0)
end

-- Boule ; le rayon est réduit si besoin pour rester dans la zone possédée (idempotence de clear).
function TerrainSculpt.fillBall(center: Vector3, radius: number, material: Enum.Material)
	local r = math.min(
		radius,
		center.X - ZONE_MIN.X,
		ZONE_MAX.X - center.X,
		center.Y - ZONE_MIN.Y,
		ZONE_MAX.Y - center.Y,
		center.Z - ZONE_MIN.Z,
		ZONE_MAX.Z - center.Z
	)
	if r < 1 then
		return
	end
	getTerrain():FillBall(RegionConfig.toWorld(center), r, material)
	record("ball", material, CFrame.new(center), Vector3.new(r, r, r), r)
end

-- Cylindre dont l'axe suit le Y du cframe (convention de Terrain:FillCylinder).
function TerrainSculpt.fillCylinder(cframe: CFrame, height: number, radius: number, material: Enum.Material)
	getTerrain():FillCylinder(ORIGIN_CFRAME * cframe, height, radius, material)
	record("cylinder", material, cframe, Vector3.new(radius, height / 2, radius), radius)
end

-- Boîte alignée sur les axes, découpée en blocs de CHUNK studs au plus par axe.
function TerrainSculpt.fillBox(min: Vector3, max: Vector3, material: Enum.Material)
	local size = max - min
	local nx = math.max(1, math.ceil(size.X / CHUNK))
	local ny = math.max(1, math.ceil(size.Y / CHUNK))
	local nz = math.max(1, math.ceil(size.Z / CHUNK))
	local chunk = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	for ix = 0, nx - 1 do
		for iy = 0, ny - 1 do
			for iz = 0, nz - 1 do
				local center = min + Vector3.new((ix + 0.5) * chunk.X, (iy + 0.5) * chunk.Y, (iz + 0.5) * chunk.Z)
				TerrainSculpt.fillBlock(CFrame.new(center), chunk, material)
			end
		end
	end
end

function TerrainSculpt.carve(cframe: CFrame, size: Vector3)
	TerrainSculpt.fillBlock(cframe, size, AIR)
end

function TerrainSculpt.carveBox(min: Vector3, max: Vector3)
	TerrainSculpt.fillBox(min, max, AIR)
end

function TerrainSculpt.carveBall(center: Vector3, radius: number)
	TerrainSculpt.fillBall(center, radius, AIR)
end

function TerrainSculpt.carveCylinder(cframe: CFrame, height: number, radius: number)
	TerrainSculpt.fillCylinder(cframe, height, radius, AIR)
end

-- Vide toute la zone possédée par le générateur (blocs de 512 studs au plus par axe).
function TerrainSculpt.clearZone()
	TerrainSculpt.fillBox(ZONE_MIN, ZONE_MAX, AIR)
end

--------------------------------------------------------------------------------
-- Reliefs
--------------------------------------------------------------------------------

--[[
	Butte : disques empilés dont le rayon suit un profil cos² (pente douce au pied et au sommet).
	`center` = centre de la BASE (Y = niveau du pied), `radius` = rayon nominal du pied.
]]
function TerrainSculpt.hill(center: Vector3, radius: number, height: number, material: Enum.Material, options: HillOptions?)
	local opts: HillOptions = options or {}
	local flatTop = opts.flatTop or 0
	local steps = opts.steps or math.max(3, math.ceil(height / 1.6))
	local jitter = opts.jitter or 0
	local bottom = center.Y - 4
	for i = 1, steps do
		local t = i / steps
		local layerTop = center.Y + height * t
		local r = flatTop + (radius - flatTop) * (2 / math.pi) * math.acos(math.sqrt(t))
		if r >= 1.5 then
			local dx, dz = 0, 0
			if opts.random and jitter > 0 and i < steps then
				dx = opts.random:NextNumber(-jitter, jitter)
				dz = opts.random:NextNumber(-jitter, jitter)
			end
			local h = layerTop - bottom
			TerrainSculpt.fillCylinder(CFrame.new(center.X + dx, bottom + h / 2, center.Z + dz), h, r, material)
		end
	end
end

-- Pic rocheux : une grosse boule et des épaulements. `base` = pied (Y = sol), sommet = base.Y + height.
function TerrainSculpt.mountain(base: Vector3, radius: number, height: number, material: Enum.Material, random: Random)
	local floor = Config.BASE_BOTTOM - 8
	local peak = base.Y + height
	local r = radius
	if peak - 2 * r < floor then
		r = (peak - floor) / 2
	end
	TerrainSculpt.fillBall(Vector3.new(base.X, peak - r, base.Z), r, material)
	local shoulders = random:NextInteger(1, 3)
	local secondary = if material == Enum.Material.Rock then Enum.Material.Slate else Enum.Material.Rock
	for _ = 1, shoulders do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = r * random:NextNumber(0.5, 0.85)
		local sr = r * random:NextNumber(0.45, 0.7)
		local speak = base.Y + height * random:NextNumber(0.45, 0.75)
		local sx = base.X + math.cos(angle) * distance
		local sz = base.Z + math.sin(angle) * distance
		TerrainSculpt.fillBall(Vector3.new(sx, speak - sr, sz), sr, if random:NextNumber() < 0.5 then secondary else material)
	end
end

-- Chaîne de pics le long d'une ligne brisée (Y des points = niveau du pied).
function TerrainSculpt.ridge(points: { Vector3 }, radius: number, height: number, material: Enum.Material, random: Random)
	local spacing = radius * 0.9
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local count = math.max(1, math.floor(length / spacing))
		for k = 0, count - 1 do
			local p = a:Lerp(b, k / count)
			local jitter = Vector3.new(random:NextNumber(-0.25, 0.25) * radius, 0, random:NextNumber(-0.25, 0.25) * radius)
			TerrainSculpt.mountain(p + jitter, radius * random:NextNumber(0.75, 1.1), height * random:NextNumber(0.7, 1.15), material, random)
		end
	end
	local last = points[#points]
	TerrainSculpt.mountain(last, radius, height * 0.9, material, random)
end

--[[
	Plan incliné : sol qui monte de `low` (bord bas) à `high` (bord haut), sur `width` studs de large.
	Le coin est posé sur le niveau de `low` ; `fillBelow` ajoute une épaisseur pleine dessous.
]]
function TerrainSculpt.incline(low: Vector3, high: Vector3, width: number, material: Enum.Material, fillBelow: number?)
	local flat = Vector3.new(high.X - low.X, 0, high.Z - low.Z)
	local length = flat.Magnitude
	local rise = high.Y - low.Y
	if length < 1 or rise <= 0 then
		return
	end
	local middle = Vector3.new((low.X + high.X) / 2, low.Y + rise / 2, (low.Z + high.Z) / 2)
	local frame = CFrame.lookAt(middle, middle - flat) -- -Z local vers le bas, +Z (arête haute) vers le haut
	local pieces = math.max(1, math.ceil(width / CHUNK))
	local pieceWidth = width / pieces
	for i = 0, pieces - 1 do
		local offset = -width / 2 + (i + 0.5) * pieceWidth
		local pieceFrame = frame * CFrame.new(offset, 0, 0)
		TerrainSculpt.fillWedge(pieceFrame, Vector3.new(pieceWidth, rise, length), material)
		if fillBelow and fillBelow > 0 then
			TerrainSculpt.fillBlock(pieceFrame * CFrame.new(0, -rise / 2 - fillBelow / 2, 0), Vector3.new(pieceWidth, fillBelow, length), material)
		end
	end
end

-- Rampe de chemin : surface plane de `from` à `to` (points AU SOL), dégagée au-dessus.
function TerrainSculpt.ramp(from: Vector3, to: Vector3, width: number, material: Enum.Material, options: RampOptions?)
	local opts: RampOptions = options or {}
	local thickness = opts.thickness or 8
	local clearance = opts.clearance or 12
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local middle = from + delta / 2
	local frame = CFrame.lookAt(middle, to)
	TerrainSculpt.carve(frame * CFrame.new(0, clearance / 2, 0), Vector3.new(width, clearance, length))
	TerrainSculpt.fillBlock(frame * CFrame.new(0, -thickness / 2, 0), Vector3.new(width, thickness, length + 1), material)
end

-- Aplanit un disque : sol exactement à center.Y (remplit dessous, dégage au-dessus).
function TerrainSculpt.flatten(center: Vector3, radius: number, material: Enum.Material?, clearHeight: number?)
	local clear = clearHeight or 30
	TerrainSculpt.carveCylinder(CFrame.new(center + Vector3.new(0, clear / 2, 0)), clear, radius)
	TerrainSculpt.fillCylinder(CFrame.new(center - Vector3.new(0, 3, 0)), 6, radius, material or Enum.Material.Ground)
end

--------------------------------------------------------------------------------
-- Peinture de sol (chemins, taches)
--------------------------------------------------------------------------------

-- Tache de matériau qui suit le sol (disque peint juste au-dessus de la surface).
function TerrainSculpt.patch(center: Vector3, radius: number, material: Enum.Material)
	local h = TerrainSculpt.heightAt(center.X, center.Z)
	if h == -math.huge then
		return
	end
	TerrainSculpt.fillCylinder(CFrame.new(center.X, h + 0.25 - 1.5, center.Z), 3, radius, material)
end

--[[
	Chemin : bande de `material` de largeur `width` le long de `points`. Par défaut elle suit le sol
	(les Y des points sont ignorés) ; avec follow = false, les Y des points donnent la surface.
	Les tronçons sont arrondis aux jonctions (disques) pour des virages propres.
]]
function TerrainSculpt.path(points: { Vector3 }, width: number, material: Enum.Material, options: PathOptions?)
	local opts: PathOptions = options or {}
	local follow = opts.follow ~= false
	local thickness = opts.thickness or 3
	local raise = opts.raise or 0.25
	local step = opts.step or 8
	local widthJitter = opts.widthJitter or 0

	-- 1) Échantillonnage (hauteurs lues AVANT de peindre).
	local samples: { Vector3 } = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local count = math.max(1, math.ceil((b - a).Magnitude / step))
		for k = 0, count - 1 do
			table.insert(samples, a:Lerp(b, k / count))
		end
	end
	table.insert(samples, points[#points])
	if follow then
		for i, p in samples do
			samples[i] = Vector3.new(p.X, TerrainSculpt.heightAt(p.X, p.Z), p.Z)
		end
	end

	-- 2) Tronçons inclinés + disques aux jonctions.
	for i, p in samples do
		local w = width
		if opts.random and widthJitter > 0 then
			w = width * (1 + opts.random:NextNumber(-widthJitter, widthJitter))
		end
		TerrainSculpt.fillCylinder(CFrame.new(p.X, p.Y + raise - thickness / 2, p.Z), thickness, w / 2, material)
		local nextPoint = samples[i + 1]
		if nextPoint then
			local length = (nextPoint - p).Magnitude
			if length > 0.5 then
				local middle = (p + nextPoint) / 2
				local frame = CFrame.lookAt(middle, nextPoint) * CFrame.new(0, raise - thickness / 2, 0)
				TerrainSculpt.fillBlock(frame, Vector3.new(w, thickness, length), material)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Relief de la Région 1
--------------------------------------------------------------------------------

local T = {
	ground = Enum.Material.Ground,
	mud = Enum.Material.Mud,
	rock = Enum.Material.Rock,
	slate = Enum.Material.Slate,
	basalt = Enum.Material.Basalt,
	grass = Enum.Material.Grass,
	water = WATER,
}

-- Sol de base : roche profonde, couche de terre (village à groundHeight, forêt un peu plus bas).
local function sculptBase()
	local g = L.groundHeight
	local forestEdge = Config.FOREST_EDGE_X
	TerrainSculpt.fillBox(Vector3.new(ZONE_MIN.X, Config.BASE_BOTTOM, ZONE_MIN.Z), Vector3.new(ZONE_MAX.X, g - 6, ZONE_MAX.Z), T.rock)
	TerrainSculpt.fillBox(Vector3.new(forestEdge, g - 6, ZONE_MIN.Z), Vector3.new(ZONE_MAX.X, g, ZONE_MAX.Z), T.ground)
	TerrainSculpt.fillBox(Vector3.new(ZONE_MIN.X, g - 6, ZONE_MIN.Z), Vector3.new(forestEdge, Config.FOREST_GROUND_HEIGHT, ZONE_MAX.Z), T.ground)
	-- Transition douce forêt -> village (la Porte des Murmures est sur cette pente).
	local zMiddle = (ZONE_MIN.Z + ZONE_MAX.Z) / 2
	TerrainSculpt.incline(
		Vector3.new(forestEdge - 40, Config.FOREST_GROUND_HEIGHT, zMiddle),
		Vector3.new(forestEdge, g, zMiddle),
		ZONE_MAX.Z - ZONE_MIN.Z,
		T.ground
	)
end

-- Lac au nord, en Water jusqu'au bord nord de la zone, avec sa rive en pente douce.
local function sculptLake()
	local g = L.groundHeight
	local south = Config.LAKE_SOUTH_Z
	local west, east = -240, ZONE_MAX.X - 30
	local shoreY = L.lakeShore.Y
	-- Cuvette et rive dégagées.
	TerrainSculpt.carveBox(Vector3.new(west, Config.LAKE_BOTTOM, ZONE_MIN.Z), Vector3.new(east, 40, south))
	TerrainSculpt.carveBox(Vector3.new(-200, shoreY, south), Vector3.new(east, 40, -160))
	-- L'eau d'abord : les formes de terrain posées ensuite la remplacent là où il faut.
	TerrainSculpt.fillBox(Vector3.new(west, Config.LAKE_BOTTOM, ZONE_MIN.Z), Vector3.new(east, Config.LAKE_SURFACE, south), T.water)
	local width = east - west
	local middleX = (west + east) / 2
	-- Haut-fond sous l'eau, grève de vase, puis la pente qui remonte vers le village.
	TerrainSculpt.incline(Vector3.new(middleX, -14, south - 60), Vector3.new(middleX, shoreY, south + 5), width, T.mud, 14)
	TerrainSculpt.fillBox(Vector3.new(-200, shoreY - 6, south), Vector3.new(east, shoreY, L.lakeShore.Z + 2), T.mud)
	TerrainSculpt.incline(Vector3.new((east - 200) / 2, shoreY, L.lakeShore.Z + 2), Vector3.new((east - 200) / 2, g, -160), east + 200, T.ground, 6)
end

-- Montagnes et falaises de bordure (au-delà des limites jouables).
local function sculptBorders(random: Random)
	local pMin, pMax = L.playableMin, L.playableMax
	-- Sud : derrière le belvédère.
	TerrainSculpt.ridge({
		Vector3.new(ZONE_MIN.X + 40, 30, pMax.Z + 55),
		Vector3.new(-200, 30, pMax.Z + 60),
		Vector3.new(ZONE_MAX.X - 40, 40, pMax.Z + 55),
	}, 62, 85, T.rock, random)
	-- Est.
	TerrainSculpt.ridge({
		Vector3.new(pMax.X + 34, 10, ZONE_MAX.Z - 40),
		Vector3.new(pMax.X + 36, 10, 0),
		Vector3.new(pMax.X + 34, 0, -400),
		Vector3.new(pMax.X + 34, 0, ZONE_MIN.Z + 40),
	}, 44, 78, T.rock, random)
	-- Ouest (au-delà de la forêt).
	TerrainSculpt.ridge({
		Vector3.new(pMin.X - 34, 8, ZONE_MAX.Z - 40),
		Vector3.new(pMin.X - 36, 8, 0),
		Vector3.new(pMin.X - 34, 8, ZONE_MIN.Z + 40),
	}, 44, 78, T.slate, random)
	-- Nord lointain : silhouette derrière la cathédrale engloutie, de l'autre côté du lac.
	TerrainSculpt.ridge({
		Vector3.new(ZONE_MIN.X + 60, -20, pMin.Z - 95),
		Vector3.new(0, -20, pMin.Z - 100),
		Vector3.new(ZONE_MAX.X - 60, -20, pMin.Z - 95),
	}, 62, 130, T.slate, random)
	-- Falaises entre la forêt et le lac (rive ouest), puis crête au nord de la forêt.
	TerrainSculpt.ridge({
		Vector3.new(-250, 0, -262),
		Vector3.new(-268, 0, -420),
		Vector3.new(-282, -10, pMin.Z - 40),
	}, 34, 52, T.basalt, random)
	TerrainSculpt.ridge({
		Vector3.new(pMin.X - 40, 8, -415),
		Vector3.new(-430, 8, -405),
		Vector3.new(-282, 8, -420),
	}, 44, 70, T.rock, random)
end

-- Belvédère : plateau au sud (y = LAYOUT.overlook.Y), falaise déchiquetée, pente vers le village.
local function sculptOverlook(random: Random)
	local g = L.groundHeight
	local top = L.overlook.Y
	local edgeZ = 236 -- bord nord du plateau (le belvédère regarde par-dessus)
	-- Pente intermédiaire entre le village et le pied de la falaise.
	TerrainSculpt.incline(Vector3.new(55, g, 120), Vector3.new(55, 30, edgeZ), 470, T.ground)
	-- Plateau.
	TerrainSculpt.fillBox(Vector3.new(-80, g, edgeZ), Vector3.new(ZONE_MAX.X, top, ZONE_MAX.Z), T.ground)
	-- Falaise nord déchiquetée (roche), et flanc ouest.
	for x = -80, L.playableMax.X, 17 do
		local r = random:NextNumber(8, 12)
		local center = Vector3.new(x + random:NextNumber(-4, 4), top - r + random:NextNumber(-5, -1), edgeZ + random:NextNumber(-2, 3))
		TerrainSculpt.fillBall(center, r, if random:NextNumber() < 0.6 then T.rock else T.slate)
	end
	for z = edgeZ, L.playableMax.Z + 60, 18 do
		local r = random:NextNumber(9, 14)
		TerrainSculpt.fillBall(Vector3.new(-80 + random:NextNumber(-3, 3), top - r - random:NextNumber(0, 6), z), r, T.rock)
	end
	-- Épaulement au sud-ouest : raccorde la pente au relief de la forêt.
	TerrainSculpt.hill(Vector3.new(-190, Config.FOREST_GROUND_HEIGHT, 205), 70, 30, T.rock, { flatTop = 12, random = random, jitter = 3 })
end

-- Reliefs du village : butte de la chapelle, pente du cimetière, col de la Porte des Murmures, collines.
local function sculptVillageRelief(random: Random)
	local g = L.groundHeight
	local chapel = L.chapel
	-- Butte de la chapelle (son pied nord descend jusqu'au lac) et l'éperon qui porte le chemin.
	TerrainSculpt.hill(Vector3.new(chapel.X, L.lakeShore.Y, chapel.Z - 8), 95, chapel.Y - L.lakeShore.Y, T.ground, {
		flatTop = 34,
		steps = 12,
		random = random,
		jitter = 1.5,
	})
	TerrainSculpt.hill(Vector3.new(chapel.X, g, chapel.Z + 42), 46, (chapel.Y - g) * 0.7, T.ground, { flatTop = 6, steps = 6 })
	-- Cimetière en pente : la colline monte vers le nord-ouest, adossée à un éperon rocheux.
	local cemetery = L.cemetery
	TerrainSculpt.hill(Vector3.new(cemetery.X - 40, g, cemetery.Z - 40), 75, 16, T.ground, { flatTop = 8, steps = 9, random = random, jitter = 2 })
	TerrainSculpt.hill(Vector3.new(cemetery.X - 68, g, cemetery.Z - 68), 38, 30, T.rock, { flatTop = 4, random = random, jitter = 3 })
	-- Col de la Porte des Murmures : deux éperons rocheux encadrent la route de la forêt.
	local gate = L.westGate
	TerrainSculpt.hill(Vector3.new(gate.X - 12, gate.Y, gate.Z - 58), 40, 26, T.rock, { flatTop = 6, random = random, jitter = 3 })
	TerrainSculpt.hill(Vector3.new(gate.X - 8, gate.Y, gate.Z + 62), 42, 22, T.rock, { flatTop = 6, random = random, jitter = 3 })
	-- Collines de l'est (elles encadrent la cour d'entraînement et le Cercle du Gardien).
	TerrainSculpt.hill(Vector3.new(215, g, -115), 60, 26, T.ground, { flatTop = 10, random = random, jitter = 3 })
	TerrainSculpt.hill(Vector3.new(228, g, 92), 55, 20, T.ground, { flatTop = 8, random = random, jitter = 3 })
	TerrainSculpt.hill(Vector3.new(120, g, -112), 42, 12, T.ground, { flatTop = 6, random = random, jitter = 2 })
	-- Champs bosselés au sud du village.
	TerrainSculpt.hill(Vector3.new(-110, g, 80), 40, 5, T.ground, { random = random, jitter = 3 })
	TerrainSculpt.hill(Vector3.new(95, g, 92), 34, 4, T.ground, { random = random, jitter = 3 })
end

--[[
	Relief complet de la région. À appeler une fois, après clearZone(), avant les zones.
	Les zones ajoutent ensuite leurs chemins, aplanissements et cavités.
]]
function TerrainSculpt.sculptRegion(random: Random)
	sculptBase()
	sculptLake()
	sculptBorders(random)
	sculptOverlook(random)
	sculptVillageRelief(random)
end

return table.freeze(TerrainSculpt)
