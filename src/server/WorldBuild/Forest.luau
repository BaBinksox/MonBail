--!strict
--[[
	Forest (zone)
	Le début de la Forêt des Murmures, à l'ouest de la Porte des Murmures. Le chemin se divise à la
	Fourche : au nord la clairière de la statue (trois braseros, Sanctuaire des Flammes dans la paroi),
	au sud le ravin et son pont rompu (ancre temporelle, autel de l'autre rive), à l'ouest l'étang figé,
	la tour du guetteur et la Grotte des Échos ; à l'est du chemin sud, les ruines du bloc gravé.

	Contrat posé ici :
		ancres        enemy_forest_1..7, echo_forest (+ trajet, 8 points), door_flame_sanctum_open,
		              door_conduit_gate_open, gravity_block_open, gate_hollow_inside, gate_hollow_outside
		interactables mech_brazier_1..3, chest_flame_sanctum, anchor_bridge, chest_bridge_shrine,
		              mech_frozen_pond, chest_pond, mech_conduit_forest, chest_conduit,
		              mech_gravity_block, chest_gravity, hollow_gate, chest_hollow
		dynamics      brazier_1..3 ("light"), door_flame_sanctum, door_conduit_gate, gravity_block
		              ("slide"), pond_ice, bridge_restorable ("appear")

	Chaque secret n'est atteignable que par son mécanisme : le ravin (26 studs) ne se saute pas et
	s'étend d'un bord à l'autre de la forêt (une crête ferme son extrémité est) ; l'îlot de l'étang
	est une colonne lisse 9 studs au-dessus de l'eau ; la corniche des ruines est à 10 studs du sol ;
	la salle de la tour et le sanctuaire sont clos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local BuildContext = require(script.Parent.BuildContext)
local Config = require(script.Parent.WorldBuildConfig)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local PropsBuildings = require(script.Parent.PropsBuildings)
local PropsSacred = require(script.Parent.PropsSacred)
local TerrainSculpt = require(script.Parent.TerrainSculpt)

type Context = BuildContext.Context

local L = RegionConfig.LAYOUT
local T = Palette.terrain
local FG = Config.FOREST_GROUND_HEIGHT

-- Ravin : coupe la forêt d'ouest en est, sur toute sa largeur.
local RAVINE_NORTH = L.ravineBridge.Z - 13
local RAVINE_SOUTH = L.ravineBridge.Z + 13
local RAVINE_WEST = L.playableMin.X - 4
local RAVINE_EAST = -198
local RAVINE_FLOOR = -22
local RAVINE_WATER = -17

-- Étang figé.
local POND_RADIUS = 24
local POND_WATER = 5
local POND_BOTTOM = -8
local ISLET_RADIUS = 4
local ISLET_TOP = POND_WATER + 9

-- Ruines du bloc gravé.
local LEDGE_HEIGHT = 10 -- au-dessus du sol : hors de portée d'un saut
local BLOCK_SIZE = Vector3.new(6, 5, 6)

-- Grotte des Échos.
local HOLLOW_HILL_RADIUS = 75
local HOLLOW_HILL_TOP = 45
local TUNNEL_PORTAL_X = L.hollowGate.X + 15 -- le tunnel s'ouvre à l'est de la grille
local CAVE_FLOOR = L.hollowCave.Y

local Forest = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

local function groundPoint(x: number, z: number): Vector3
	return Vector3.new(x, ground(x, z), z)
end

local function onGround(x: number, z: number, yaw: number?, sink: number?): CFrame
	return Kit.yaw(Vector3.new(x, ground(x, z) - (sink or 0), z), yaw or 0)
end

local function enemyAnchor(context: Context, id: string, x: number, z: number, lookAt: Vector3)
	Kit.anchor(context.anchors, id, Kit.standing(groundPoint(x, z), lookAt))
end

-- Surface d'une rampe linéaire de `from` à `to` (pour poser les ancres dans le tunnel de la grotte).
local function rampHeight(from: Vector3, to: Vector3, x: number): number
	local alpha = math.clamp((x - from.X) / (to.X - from.X), 0, 1)
	return from.Y + (to.Y - from.Y) * alpha
end

--------------------------------------------------------------------------------
-- Plan des chemins
--------------------------------------------------------------------------------

local TRAILS: { { points: { Vector3 }, width: number } } = {
	{ points = { L.westGate, L.forestEntrance, Vector3.new(-250, FG, -14), L.forestFork }, width = 8 },
	{ points = { L.forestFork, Vector3.new(-312, FG, -80), Vector3.new(-322, FG, -130), L.statueClearing }, width = 6 },
	{ points = { L.forestFork, Vector3.new(-305, FG, 30), Vector3.new(-316, FG, 80), Vector3.new(L.ravineBridge.X, FG, RAVINE_NORTH - 10) }, width = 6 },
	{ points = { Vector3.new(-303, FG, 38), Vector3.new(-272, FG, 52), Vector3.new(L.gravityRuins.X - 4, FG, L.gravityRuins.Z + 14) }, width = 4 },
	{ points = { L.forestFork, Vector3.new(-360, FG, -30), Vector3.new(-404, FG, -72) }, width = 5 },
	{ points = { Vector3.new(-360, FG, -30), Vector3.new(-450, FG, -14), Vector3.new(-490, FG, 14), Vector3.new(TUNNEL_PORTAL_X + 2, FG, L.hollowGate.Z) }, width = 5 },
	{ points = { Vector3.new(-450, FG, -14), Vector3.new(-462, FG, 40), Vector3.new(L.conduitTower.X, FG, L.conduitTower.Z - 14) }, width = 4 },
	{ points = { Vector3.new(L.ravineBridge.X, FG, RAVINE_SOUTH + 10), L.bridgeShrine }, width = 4 },
}

-- Zones à garder libres d'arbres (centre, rayon).
local KEEP_OUT: { { center: Vector3, radius: number } } = {
	{ center = L.statueClearing, radius = 30 },
	{ center = L.flameSanctum, radius = 22 },
	{ center = L.frozenPond, radius = POND_RADIUS + 8 },
	{ center = L.conduitTower, radius = 18 },
	{ center = L.gravityRuins, radius = 22 },
	{ center = L.bridgeShrine, radius = 14 },
	{ center = L.forestFork, radius = 14 },
}

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local lengthSquared = ab:Dot(ab)
	local t = if lengthSquared > 0 then math.clamp(ap:Dot(ab) / lengthSquared, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

local function isFree(p: Vector3, margin: number): boolean
	for _, zone in KEEP_OUT do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(zone.center.X, 0, zone.center.Z)).Magnitude < zone.radius + margin then
			return false
		end
	end
	for _, trail in TRAILS do
		for i = 1, #trail.points - 1 do
			if distanceToSegment(p, trail.points[i], trail.points[i + 1]) < trail.width / 2 + margin then
				return false
			end
		end
	end
	if p.Z > RAVINE_NORTH - 6 and p.Z < RAVINE_SOUTH + 6 then
		return false
	end
	-- Colline de la grotte : pas d'arbres sur ses flancs raides.
	if (Vector3.new(p.X, 0, p.Z) - Vector3.new(L.hollowCave.X, 0, L.hollowCave.Z)).Magnitude < HOLLOW_HILL_RADIUS - 10 then
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------------------

local function sculpt(random: Random)
	-- Ravin d'ouest en est, eau noire au fond ; une éboulis remonte vers la rive nord (on n'y reste
	-- pas coincé), et une crête ferme son extrémité est.
	TerrainSculpt.carveBox(Vector3.new(RAVINE_WEST, RAVINE_FLOOR, RAVINE_NORTH), Vector3.new(RAVINE_EAST, 60, RAVINE_SOUTH))
	TerrainSculpt.fillBox(Vector3.new(RAVINE_WEST, RAVINE_FLOOR - 6, RAVINE_NORTH), Vector3.new(RAVINE_EAST, RAVINE_FLOOR, RAVINE_SOUTH), T.rock)
	TerrainSculpt.fillBox(Vector3.new(RAVINE_WEST, RAVINE_FLOOR, RAVINE_NORTH), Vector3.new(RAVINE_EAST, RAVINE_WATER, RAVINE_SOUTH), T.water)
	TerrainSculpt.ramp(Vector3.new(-262, RAVINE_WATER, RAVINE_NORTH + 5), Vector3.new(-214, FG, RAVINE_NORTH + 5), 9, T.rock, { thickness = 30, clearance = 10 })
	-- Crête de l'extrémité est jusqu'à la limite sud : la rive sud ne se rejoint pas en contournant.
	-- (hauteur <= 1,3 x rayon : les pics de `ridge` touchent toujours le sol, sans passage dessous)
	TerrainSculpt.ridge({
		Vector3.new(-186, FG, RAVINE_NORTH - 6),
		Vector3.new(-182, FG, 185),
		Vector3.new(-174, FG, 265),
		Vector3.new(-166, FG, L.playableMax.Z + 8),
	}, 26, 32, T.rock, random)

	-- Clairière de la statue (légère butte) et terrasse du sanctuaire, adossée à une paroi.
	TerrainSculpt.flatten(L.statueClearing, 24, T.ground, 24)

	-- Étang : cuvette profonde, eau dormante.
	local pond = L.frozenPond
	TerrainSculpt.carveCylinder(CFrame.new(pond.X, (POND_BOTTOM + FG + 2) / 2, pond.Z), FG + 2 - POND_BOTTOM, POND_RADIUS)
	TerrainSculpt.fillCylinder(CFrame.new(pond.X, (POND_BOTTOM - 4 + POND_BOTTOM) / 2, pond.Z), 4, POND_RADIUS, T.mud)
	TerrainSculpt.fillCylinder(CFrame.new(pond.X, (POND_BOTTOM + POND_WATER) / 2, pond.Z), POND_WATER - POND_BOTTOM, POND_RADIUS, T.water)

	-- Colline de la Grotte des Échos : plateau rocheux, chambre creusée, tunnel en pente.
	local cave = L.hollowCave
	TerrainSculpt.hill(Vector3.new(cave.X, FG, cave.Z), HOLLOW_HILL_RADIUS, HOLLOW_HILL_TOP, T.rock, { flatTop = 45, random = random, jitter = 2 })
	TerrainSculpt.carveBall(Vector3.new(cave.X - 8, CAVE_FLOOR + 8, cave.Z), 17)
	TerrainSculpt.fillBox(Vector3.new(cave.X - 26, CAVE_FLOOR - 10, cave.Z - 18), Vector3.new(cave.X + 10, CAVE_FLOOR, cave.Z + 18), T.rock)
	TerrainSculpt.ramp(Vector3.new(TUNNEL_PORTAL_X, FG, cave.Z), Vector3.new(cave.X + 8, CAVE_FLOOR, cave.Z), 8, T.slate, { thickness = 8, clearance = 12 })

	-- Chemins (après les reliefs : ils suivent le sol).
	for _, trail in TRAILS do
		TerrainSculpt.path(trail.points, trail.width, T.mud, { random = random, widthJitter = 0.18 })
	end
	for _ = 1, 18 do
		local p = Vector3.new(random:NextNumber(-680, -210), FG, random:NextNumber(-300, 100))
		TerrainSculpt.patch(p, random:NextNumber(8, 16), if random:NextNumber() < 0.5 then T.grass else T.leafyGrass)
	end
end

--------------------------------------------------------------------------------
-- Végétation
--------------------------------------------------------------------------------

local function plantTrees(folder: Instance, random: Random)
	local trees = Kit.folder(folder, "Trees")
	local planted = 0
	local attempts = 0
	while planted < 130 and attempts < 1600 do
		attempts += 1
		local x = random:NextNumber(-690, -205)
		local z = random:NextNumber(-320, 330)
		local p = Vector3.new(x, 0, z)
		if isFree(p, 3) then
			planted += 1
			local look = if random:NextNumber() < 0.3 then Palette.charredWood else nil
			Props.deadTree(trees, onGround(x, z, random:NextNumber(0, 360), 0.8), random:NextNumber(16, 30), random, { look = look, lean = 16 })
		end
	end
	for _ = 1, 26 do
		local x = random:NextNumber(-690, -205)
		local z = random:NextNumber(-320, 330)
		if isFree(Vector3.new(x, 0, z), 1) then
			if random:NextNumber() < 0.5 then
				Props.rockCluster(trees, onGround(x, z, 0, 0.8), random:NextNumber(3, 6), random:NextInteger(2, 4), random, Palette.rockMossy)
			else
				Props.deadBush(trees, onGround(x, z, random:NextNumber(0, 360), 0.2), random:NextNumber(2, 4), random)
			end
		end
	end
	-- Troncs couchés le long du chemin principal.
	Props.log(trees, groundPoint(-232, -24), groundPoint(-240, -34), 2.4)
	Props.log(trees, groundPoint(-286, 4), groundPoint(-280, 14), 2)
end

--------------------------------------------------------------------------------
-- Clairière de la statue, braseros, Sanctuaire des Flammes
--------------------------------------------------------------------------------

local function buildClearing(context: Context, folder: Instance, random: Random)
	local c = L.statueClearing
	local model = Kit.model(folder, "StatueClearing", CFrame.new(c))
	PropsSacred.statue(model, Kit.yaw(Vector3.new(c.X, c.Y - 0.2, c.Z), 180), 14, random, {
		holds = "hourglass",
		broken = true,
		inscription = "Elle a gardé la flamme",
	})
	-- Trois braseros antiques éteints (ouest, nord, est) : dynamics "light" + interactables.
	for index, angle in { 180, -90, 0 } do
		local p = Kit.ringPoint(c, 13, angle)
		local base = Kit.facing(Vector3.new(p.X, c.Y - 0.2, p.Z), c)
		local brazier = Props.brazier(context.dynamic, base, { lit = false, light = true, stone = true, scale = 1.2 })
		local bowl = brazier:FindFirstChild("Bowl")
		if bowl and bowl:IsA("BasePart") then
			Kit.tagInteractable(bowl, "mech_brazier_" .. index)
		end
		brazier.PrimaryPart = brazier:FindFirstChild("Plinth") :: BasePart?
		Kit.dynamic(context.dynamic, brazier, "brazier_" .. index)
	end
	Props.rubble(model, CFrame.new(c.X + 8, c.Y, c.Z + 9), 4, 7, random)
	Props.brokenPillar(model, onGround(c.X - 17, c.Z + 12, 0, 0.3), 7, 2.2, random)
	Props.brokenPillar(model, onGround(c.X + 18, c.Z - 10, 40, 0.3), 5, 2.2, random)

	-- Écho de la fugitive : au centre, puis course vers le nord-est (la cathédrale).
	Kit.anchor(context.anchors, "echo_forest", Kit.standing(Vector3.new(c.X + 4, c.Y, c.Z + 6), L.cathedralSpires))
	local direction = Vector3.new(L.cathedralSpires.X - c.X, 0, L.cathedralSpires.Z - c.Z).Unit
	local points: { Vector3 } = { Vector3.new(c.X + 4, c.Y, c.Z + 6), Vector3.new(c.X + 7, c.Y, c.Z - 1) }
	for i = 1, 6 do
		local p = Vector3.new(c.X + 7, 0, c.Z - 1) + direction * (14 * i)
		table.insert(points, groundPoint(p.X, p.Z))
	end
	for index, point in points do
		local nextPoint = points[index + 1] or (point + direction * 10)
		context.addEchoPoint("echo_forest", index, Kit.facing(point, nextPoint))
	end

	-- Sanctuaire des Flammes : porte de basalte dans une paroi rocheuse, face à la clairière.
	local s = L.flameSanctum
	local door = Kit.facing(s, Vector3.new(c.X, s.Y, c.Z))
	TerrainSculpt.fillBlock(door * CFrame.new(0, 8, 14), Vector3.new(54, 40, 28), T.rock)
	-- Rochers qui cassent l'arête de la paroi (sans toucher la façade de la porte).
	for i = -2, 2 do
		local corner = door * CFrame.new(i * 12 + random:NextNumber(-3, 3), 26 + random:NextNumber(-4, 4), 18 + random:NextNumber(-3, 5))
		TerrainSculpt.fillBall(corner.Position, random:NextNumber(9, 14), if i % 2 == 0 then T.rock else T.slate)
	end
	for _, side in { -1, 1 } do
		local flank = door * CFrame.new(side * 30, 6, 10)
		TerrainSculpt.fillBall(flank.Position, random:NextNumber(12, 16), T.rock)
	end
	TerrainSculpt.fillBlock(door * CFrame.new(0, -3, -6), Vector3.new(18, 6, 12), T.rock)
	TerrainSculpt.ramp(Vector3.new(c.X - 12, c.Y, c.Z - 12), (door * CFrame.new(0, 0, -10)).Position, 7, T.rock, { thickness = 6, clearance = 10 })
	TerrainSculpt.carve(door * CFrame.new(0, 4.5, 3), Vector3.new(6, 9, 6))
	TerrainSculpt.carve(door * CFrame.new(0, 5, 11), Vector3.new(13, 10, 12))
	local sanctum = Kit.model(folder, "FlameSanctum", door)
	PropsBuildings.archway(sanctum, door * CFrame.new(0, 0, -0.6), 6, 9, 2, Palette.basalt, true)
	Kit.part(sanctum, door * CFrame.new(0, -0.5, 8), Vector3.new(13, 1, 18), Palette.basalt, { name = "Floor" })
	Kit.part(sanctum, door * CFrame.new(0, 10.5, 8), Vector3.new(13, 1, 18), Palette.stoneDark, { name = "Ceiling" })
	for _, side in { -1, 1 } do
		Kit.part(sanctum, door * CFrame.new(side * 6.8, 5, 11), Vector3.new(0.8, 10, 12), Palette.basalt, { name = "Wall" })
		Kit.part(sanctum, door * CFrame.new(side * 3.4, 5, 2.5), Vector3.new(0.8, 10, 5), Palette.basalt, { name = "Jamb" })
	end
	Kit.part(sanctum, door * CFrame.new(0, 5, 17.4), Vector3.new(13, 10, 0.8), Palette.basalt, { name = "Back" })
	local _, chest = Props.chest(sanctum, door * CFrame.new(0, 0, 14.5), Palette.bronzeDark)
	Kit.tagInteractable(chest, "chest_flame_sanctum")
	Props.brazier(sanctum, door * CFrame.new(-4.2, 0, 14), { lit = true, light = true, stone = true, scale = 0.7 })
	Props.candles(sanctum, door * CFrame.new(4, 0, 14.5), 5, random, false)
	-- Dalle (dynamic "slide") : ouverte = enfoncée dans le sol.
	local slabCFrame = door * CFrame.new(0, 4.5, 0.6)
	local slabModel = Kit.model(context.dynamic, "SanctumDoor", slabCFrame)
	local slab = Kit.part(slabModel, slabCFrame, Vector3.new(6.2, 9, 1.2), Palette.basalt, { name = "Slab" })
	Kit.part(slabModel, slabCFrame * CFrame.new(0, 1, -0.65), Vector3.new(2.2, 2.2, 0.1), Palette.emberDim, { decor = true, name = "FlameSigil" })
	slabModel.PrimaryPart = slab
	Kit.dynamic(context.dynamic, slabModel, "door_flame_sanctum")
	Kit.anchor(context.anchors, "door_flame_sanctum_open", slabCFrame * CFrame.new(0, -9.6, 0))

	enemyAnchor(context, "enemy_forest_4", c.X - 8, c.Z + 14, Vector3.new(c.X, c.Y, c.Z + 40))
	enemyAnchor(context, "enemy_forest_3", -318, -104, L.forestFork)
end

--------------------------------------------------------------------------------
-- Ravin, pont rompu, ancre temporelle, autel de l'autre rive
--------------------------------------------------------------------------------

local function buildRavine(context: Context, folder: Instance, random: Random)
	local b = L.ravineBridge
	local x = b.X
	local deckY = FG + 0.3
	local model = Kit.model(folder, "BrokenBridge", CFrame.new(b))
	-- Culées de pierre sur chaque rive (Static), avec quelques planches cassées.
	for _, side in { -1, 1 } do
		local edgeZ = if side < 0 then RAVINE_NORTH else RAVINE_SOUTH
		local abutment = CFrame.new(x, FG - 6, edgeZ + side * 5)
		Kit.part(model, abutment, Vector3.new(9, 13, 10), Palette.stone, { name = "Abutment" })
		Kit.part(model, CFrame.new(x, deckY - 0.2, edgeZ - side * 1.4), Vector3.new(6, 0.6, 2.8), Palette.charredWood, { name = "BrokenPlanks" })
		for _, px in { -3.4, 3.4 } do
			Kit.part(model, CFrame.new(x + px, deckY + 1.8, edgeZ + side * 2), Vector3.new(0.6, 4, 0.6), Palette.charredWood, { name = "Post" })
		end
	end
	-- Le pont tel qu'il était (dynamic "appear") : à peine visible, traversable seulement rembobiné.
	local span = RAVINE_SOUTH - RAVINE_NORTH
	local bridge = Kit.model(context.dynamic, "RestorableBridge", CFrame.new(x, deckY, b.Z))
	local ghost: Kit.PartOptions = { transparency = 0.9, collide = false, shadow = false }
	local deck = Kit.part(bridge, CFrame.new(x, deckY - 0.2, b.Z), Vector3.new(6, 0.6, span), Palette.oldWood, ghost)
	deck.Name = "Deck"
	for _, px in { -3.2, 3.2 } do
		local rail = Kit.part(bridge, CFrame.new(x + px, deckY + 2.6, b.Z), Vector3.new(0.4, 0.4, span), Palette.oldWood, ghost)
		rail.Name = "Rail"
	end
	for i = 0, 4 do
		local z = RAVINE_NORTH + span * (i + 0.5) / 5
		for _, px in { -3.2, 3.2 } do
			Kit.part(bridge, CFrame.new(x + px, deckY + 1.3, z), Vector3.new(0.4, 2.6, 0.4), Palette.oldWood, ghost)
		end
	end
	for _, part in bridge:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("ActiveTransparency", 0)
		end
	end
	Kit.dynamic(context.dynamic, bridge, "bridge_restorable")

	-- Ancre temporelle : sablier de pierre (sable vers le haut) sur la rive nord, près de la culée.
	local anchorBase = onGround(x + 9, RAVINE_NORTH - 8, 0, 0.2)
	local plinth = Kit.model(model, "TemporalAnchor", anchorBase)
	Kit.part(plinth, anchorBase * CFrame.new(0, 0.6, 0), Vector3.new(3.4, 1.2, 3.4), Palette.basalt, { name = "Plinth" })
	local _, bulb = PropsSacred.hourglass(plinth, anchorBase * CFrame.new(0, 1.2, 0), 4.5, { temporal = true, inverted = true })
	Kit.light(bulb, { color = Palette.colors.temporalLight, brightness = 1.4, range = 14 })
	Kit.tagInteractable(bulb, "anchor_bridge")

	-- Autel de l'autre rive.
	local shrine = L.bridgeShrine
	TerrainSculpt.flatten(shrine, 9, T.ground, 16)
	local shrineBase = Kit.facing(Vector3.new(shrine.X, ground(shrine.X, shrine.Z), shrine.Z), Vector3.new(x, FG, RAVINE_SOUTH))
	local altarModel, _ = PropsSacred.altar(model, shrineBase, 5, 3)
	local _, offering = Props.chest(altarModel, shrineBase * CFrame.new(0, PropsSacred.ALTAR_HEIGHT, 0), Palette.bronzeDark)
	Kit.tagInteractable(offering, "chest_bridge_shrine")
	Props.candles(model, shrineBase * CFrame.new(-3.4, 0, 0.5), 4, random, true)
	Props.brokenPillar(model, shrineBase * CFrame.new(5, 0, 2), 6, 2, random)
	PropsSacred.statue(model, shrineBase * CFrame.new(-5, 0, 3), 7, random, { broken = true, plinth = 1.5 })

	enemyAnchor(context, "enemy_forest_5", -312, 72, L.forestFork)
end

--------------------------------------------------------------------------------
-- Étang figé (Glace)
--------------------------------------------------------------------------------

local function buildPond(context: Context, folder: Instance, random: Random)
	local p = L.frozenPond
	local model = Kit.model(folder, "FrozenPond", CFrame.new(p))
	-- Îlot : colonne lisse (on ne s'y hisse pas depuis l'eau), coffre au sommet.
	Kit.column(model, CFrame.new(p.X, POND_BOTTOM, p.Z), ISLET_TOP - POND_BOTTOM, ISLET_RADIUS * 2, Palette.rock, { name = "Islet" })
	Kit.column(model, CFrame.new(p.X, ISLET_TOP - 0.1, p.Z), 0.2, ISLET_RADIUS * 2 - 0.6, Palette.moss, Kit.DECOR)
	local _, chest = Props.chest(model, Kit.facing(Vector3.new(p.X, ISLET_TOP, p.Z), Vector3.new(p.X + 10, ISLET_TOP, p.Z)), Palette.oldWood)
	Kit.tagInteractable(chest, "chest_pond")
	-- Pierre plate de la rive est (interactable de la Glace).
	local shoreX = p.X + POND_RADIUS + 2
	local stone = Kit.part(model, CFrame.new(shoreX, FG + 0.3, p.Z), Vector3.new(3.6, 1, 3.6), Palette.stoneLight, { name = "ShoreStone" })
	Kit.part(model, CFrame.new(shoreX, FG + 0.82, p.Z), Vector3.new(1.6, 0.05, 1.6), Palette.ice, { decor = true, name = "FrostMark", transparency = 0.3 })
	Kit.tagInteractable(stone, "mech_frozen_pond")
	-- Plaques de glace (dynamic "appear") : un escalier de glace de la rive jusqu'au sommet de l'îlot.
	local ice = Kit.model(context.dynamic, "PondIce", CFrame.new(p))
	local first, last = shoreX - 3.5, p.X + ISLET_RADIUS + 1.6
	local count = 6
	for i = 0, count - 1 do
		local alpha = i / (count - 1)
		local x = first + (last - first) * alpha
		local top = FG + 0.6 + (ISLET_TOP - 0.4 - (FG + 0.6)) * alpha
		local plate = Kit.part(ice, CFrame.new(x, top - 0.4, p.Z + random:NextNumber(-0.6, 0.6)), Vector3.new(3.6, 0.8, 4.2), Palette.ice, {
			name = "IcePlate",
			transparency = 0.85,
			collide = false,
			shadow = false,
		})
		plate:SetAttribute("ActiveTransparency", 0.15)
	end
	Kit.dynamic(context.dynamic, ice, "pond_ice")
	-- Roseaux morts sur la berge.
	for i = 1, 8 do
		local q = Kit.ringPoint(p, POND_RADIUS + 3, i * 45 + random:NextNumber(-10, 10))
		Props.deadBush(model, onGround(q.X, q.Z, random:NextNumber(0, 360), 0.2), 2, random)
	end
	enemyAnchor(context, "enemy_forest_6", p.X + 18, p.Z + 28, p)
end

--------------------------------------------------------------------------------
-- Tour du guetteur (Foudre)
--------------------------------------------------------------------------------

local function buildTower(context: Context, folder: Instance, random: Random)
	local tPos = L.conduitTower
	local g = ground(tPos.X, tPos.Z)
	TerrainSculpt.flatten(Vector3.new(tPos.X, g, tPos.Z), 11, T.ground, 30)
	local base = CFrame.new(tPos.X, g, tPos.Z) -- la grille est au nord (-Z), vers le chemin
	local model = Kit.model(folder, "WatchTower", base)
	local s, t, roomHeight, height = 12, 1.4, 8, 22
	Kit.part(model, base * CFrame.new(0, -0.5, 0), Vector3.new(s + 1, 1.4, s + 1), Palette.stoneDark, { name = "Plinth" })
	local gate = { x0 = -2.6, x1 = 2.6, y0 = 0, y1 = 7, kind = "door" :: "door" }
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, -s / 2 + t / 2), s, height, { gate }, Palette.stone, nil, { thickness = t, jagged = 0.25, random = random })
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, s / 2 - t / 2) * CFrame.Angles(0, math.pi, 0), s, height, {}, Palette.stone, nil, { thickness = t, jagged = 0.3, random = random })
	PropsBuildings.panelWall(model, base * CFrame.new(-(s / 2 - t / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0), s - 2 * t, height, {}, Palette.stone, nil, { thickness = t, jagged = 0.25, random = random })
	PropsBuildings.panelWall(model, base * CFrame.new(s / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), s - 2 * t, height, {}, Palette.stone, nil, { thickness = t, jagged = 0.3, random = random })
	-- Plafond de la salle basse : la salle reste close même si les murs hauts sont écroulés.
	Kit.part(model, base * CFrame.new(0, roomHeight + 0.5, 0), Vector3.new(s - 0.2, 1, s - 0.2), Palette.stoneDark, { name = "RoomCeiling" })
	Kit.part(model, base * CFrame.new(0, 0.25, 0), Vector3.new(s - 2 * t, 0.1, s - 2 * t), Palette.oldWood, Kit.DECOR)
	local _, chest = Props.chest(model, base * CFrame.new(0, 0.2, 2.6), Palette.iron)
	Kit.tagInteractable(chest, "chest_conduit")
	Props.crate(model, base * CFrame.new(-3, 0.2, 2.8), 2, false, random)
	-- Herse (dynamic "slide") dans l'ouverture ; ouverte = levée dans le mur.
	local gateCFrame = base * CFrame.new(0, 3.5, -s / 2 + t / 2)
	local portcullis = Kit.model(context.dynamic, "Portcullis", gateCFrame)
	local frame = Kit.part(portcullis, gateCFrame * CFrame.new(0, 3.3, 0), Vector3.new(5.2, 0.4, 0.4), Palette.iron, { name = "TopBar" })
	for i = 0, 5 do
		local bx = -2.2 + i * 0.88
		Kit.part(portcullis, gateCFrame * CFrame.new(bx, 0, 0), Vector3.new(0.3, 7, 0.3), Palette.iron, { name = "Bar" })
	end
	for _, by in { -1.6, 1.4 } do
		Kit.part(portcullis, gateCFrame * CFrame.new(0, by, 0), Vector3.new(5.2, 0.25, 0.25), Palette.iron, { name = "CrossBar" })
	end
	portcullis.PrimaryPart = frame
	Kit.dynamic(context.dynamic, portcullis, "door_conduit_gate")
	Kit.anchor(context.anchors, "door_conduit_gate_open", gateCFrame * CFrame.new(0, 3.3 + 7, 0))
	-- Conduit ancien : pilier de métal verdi couvert de glyphes, au pied de la tour.
	local conduitBase = CFrame.new(tPos.X + 7, ground(tPos.X + 7, tPos.Z - 12) - 0.3, tPos.Z - 12)
	local conduit = Kit.model(model, "Conduit", conduitBase)
	local pillar = Kit.column(conduit, conduitBase, 6, 1.6, Palette.tint(Palette.bronze, Color3.fromRGB(78, 120, 104)), { name = "Pillar" })
	for i = 0, 2 do
		Kit.part(conduit, conduitBase * CFrame.new(0, 1.6 + i * 1.5, -0.82), Vector3.new(0.5, 0.5, 0.06), Palette.temporalCyanDim, { decor = true, name = "Glyph" })
	end
	Kit.tagInteractable(pillar, "mech_conduit_forest")
	Props.rubble(model, base * CFrame.new(8, 0, 6), 4, 7, random)
end

--------------------------------------------------------------------------------
-- Ruines du bloc gravé (Gravité)
--------------------------------------------------------------------------------

local function buildGravityRuins(context: Context, folder: Instance, random: Random)
	local r = L.gravityRuins
	local g = ground(r.X, r.Z)
	TerrainSculpt.flatten(Vector3.new(r.X, g, r.Z), 18, T.ground, 24)
	local model = Kit.model(folder, "GravityRuins", CFrame.new(r.X, g, r.Z))
	-- Bastion lisse dont le sommet est la corniche (10 studs : aucun saut n'y monte).
	local bastionCenter = Vector3.new(r.X, g + LEDGE_HEIGHT / 2, r.Z - 10)
	Kit.part(model, CFrame.new(bastionCenter), Vector3.new(12, LEDGE_HEIGHT, 6), Palette.stone, { name = "Bastion" })
	Kit.part(model, CFrame.new(bastionCenter + Vector3.new(0, LEDGE_HEIGHT / 2 + 0.25, 0)), Vector3.new(12.6, 0.5, 6.6), Palette.stoneLight, { name = "Ledge" })
	local _, cache = Props.chest(model, Kit.yaw(bastionCenter + Vector3.new(2, LEDGE_HEIGHT / 2 + 0.5, -0.5), 180), Palette.oldWood)
	Kit.tagInteractable(cache, "chest_gravity")
	-- Murs écroulés bas, à distance du bastion (ils ne servent pas de marchepied).
	Props.ruinedWall(model, Vector3.new(r.X - 16, g, r.Z - 2), Vector3.new(r.X - 15, g, r.Z + 12), 4, 1.4, random)
	Props.ruinedWall(model, Vector3.new(r.X + 14, g, r.Z + 10), Vector3.new(r.X + 4, g, r.Z + 16), 3.5, 1.4, random)
	Props.brokenPillar(model, Kit.yaw(Vector3.new(r.X - 12, g, r.Z + 14), 0), 4, 2, random)
	-- Bloc gravé (dynamic "slide") : position A à l'écart, position B au pied de la corniche.
	local closed = CFrame.new(r.X + 14, g + BLOCK_SIZE.Y / 2, r.Z + 7)
	local blockModel = Kit.model(context.dynamic, "EngravedBlock", closed)
	local block = Kit.part(blockModel, closed, BLOCK_SIZE, Palette.granite, { name = "Block" })
	Kit.part(blockModel, closed * CFrame.new(0, 0, -BLOCK_SIZE.Z / 2 - 0.03), Vector3.new(2.6, 2.6, 0.05), Palette.temporalCyanDim, { decor = true, name = "Glyph" })
	blockModel.PrimaryPart = block
	Kit.tagInteractable(block, "mech_gravity_block")
	Kit.dynamic(context.dynamic, blockModel, "gravity_block")
	Kit.anchor(context.anchors, "gravity_block_open", CFrame.new(r.X, g + BLOCK_SIZE.Y / 2, bastionCenter.Z + 3 + BLOCK_SIZE.Z / 2 + 0.2))
end

--------------------------------------------------------------------------------
-- Grotte des Échos
--------------------------------------------------------------------------------

local function buildHollow(context: Context, folder: Instance, random: Random)
	local cave = L.hollowCave
	local portal = Vector3.new(TUNNEL_PORTAL_X, FG, cave.Z)
	local bottom = Vector3.new(cave.X + 8, CAVE_FLOOR, cave.Z)
	local model = Kit.model(folder, "EchoHollow", CFrame.new(cave))
	-- Grille de racines vivantes en travers du tunnel (solide) ; l'une d'elles est l'interactable.
	local gateX = L.hollowGate.X + 5
	local floorAtGate = rampHeight(portal, bottom, gateX)
	local grille = Kit.model(model, "RootGrille", CFrame.new(gateX, floorAtGate, cave.Z))
	local main: Part? = nil
	for i = 0, 6 do
		local z = cave.Z - 3.6 + i * 1.2
		local root = Kit.part(grille, CFrame.new(gateX, floorAtGate + 6, z) * CFrame.Angles(math.rad(random:NextNumber(-6, 6)), 0, math.rad(random:NextNumber(-8, 8))), Vector3.new(0.9, 12.5, 0.9), Palette.deadTreeDark, { name = "Root" })
		if i == 3 then
			main = root
		end
	end
	for _, y in { 2.5, 6.5, 10 } do
		Kit.part(grille, CFrame.new(gateX, floorAtGate + y, cave.Z) * CFrame.Angles(math.rad(random:NextNumber(-10, 10)), 0, 0), Vector3.new(0.7, 0.7, 8.6), Palette.deadTree, { name = "Tangle" })
	end
	if main then
		Kit.tagInteractable(main, "hollow_gate")
	end
	local outsideX, insideX = gateX + 6, gateX - 7
	Kit.anchor(context.anchors, "gate_hollow_outside", Kit.standing(Vector3.new(outsideX, rampHeight(portal, bottom, outsideX), cave.Z), portal + Vector3.new(20, 0, 0)))
	Kit.anchor(context.anchors, "gate_hollow_inside", Kit.standing(Vector3.new(insideX, rampHeight(portal, bottom, insideX), cave.Z), bottom))
	-- Entrée : arche de pierre moussue et racines au portail.
	PropsBuildings.archway(model, Kit.facing(Vector3.new(TUNNEL_PORTAL_X - 1, FG - 0.2, cave.Z), Vector3.new(TUNNEL_PORTAL_X + 10, FG, cave.Z)), 8, 11, 2, Palette.rockMossy, false)
	-- Cœur de la grotte : cristaux du temps (cyan), écrin, ossements.
	local heart = Vector3.new(cave.X - 10, CAVE_FLOOR, cave.Z)
	local _, chest = Props.chest(model, Kit.facing(heart, bottom), Palette.bronzeDark)
	Kit.tagInteractable(chest, "chest_hollow")
	for i = 0, 6 do
		local q = Kit.ringPoint(heart, random:NextNumber(5, 11), i * 51)
		local h = random:NextNumber(2, 5)
		local crystal = Kit.part(model, CFrame.new(q + Vector3.new(0, h / 2 - 0.3, 0)) * CFrame.Angles(math.rad(random:NextNumber(-20, 20)), math.rad(random:NextNumber(0, 90)), math.rad(random:NextNumber(-20, 20))), Vector3.new(0.9, h, 0.9), Palette.temporalCyan, { decor = true, transparency = 0.25, name = "Crystal" })
		if i == 0 then
			Kit.light(crystal, { color = Palette.colors.temporalLight, brightness = 1.2, range = 24 })
		end
	end
	PropsSacred.boneHeap(model, CFrame.new(heart + Vector3.new(4, 0, -5)), 1.6, random)

	enemyAnchor(context, "enemy_forest_7", -488, 16, Vector3.new(-450, FG, -14))
end

--------------------------------------------------------------------------------
-- Entrée de la forêt
--------------------------------------------------------------------------------

local function buildEntrance(context: Context, folder: Instance, random: Random)
	local e = L.forestEntrance
	Props.signPost(folder, onGround(e.X + 2, e.Z + 6, 90, 0.3), "La Fourche  →", random)
	Props.lanternPost(folder, onGround(e.X - 4, e.Z - 6, 90, 0.2), { light = true })
	local fork = L.forestFork
	Props.signPost(folder, onGround(fork.X + 8, fork.Z - 6, 70, 0.3), "Statue ↑   Ravin ↓   Étang ←", random)
	Props.cart(folder, onGround(fork.X + 10, fork.Z + 10, 30, 0.2), true, random)
	enemyAnchor(context, "enemy_forest_1", -222, -8, L.westGate)
	enemyAnchor(context, "enemy_forest_2", -292, -34, L.forestEntrance)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Forest.build(context: Context)
	local folder = context.zone("Forest")
	local random = context.random
	sculpt(random)
	buildEntrance(context, folder, random)
	buildClearing(context, folder, random)
	buildRavine(context, folder, random)
	buildPond(context, folder, random)
	buildTower(context, folder, random)
	buildGravityRuins(context, folder, random)
	buildHollow(context, folder, random)
	plantTrees(folder, random)
end

return table.freeze(Forest)
