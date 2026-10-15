--!strict
--[[
	Overlook (zone)
	Le Belvédère et le Sanctuaire des Âmes, sur le plateau au sud du village.

	- Sanctuaire des Âmes (LAYOUT.creatorStage) : scène du créateur de personnage. Cercle de dalles,
	  anneau de temps (cyan pâle, éteint), menhirs, bougies, trois arches sombres au nord qui encadrent
	  le personnage vu depuis la caméra (au sud). Ancres spawn_creator et camera_creator.
	- Belvédère (LAYOUT.overlook) : terrasse de pierre au bord de la falaise, parapet, colonnes brisées,
	  arbre mort, lanterne. Ancres spawn_village et camera_overlook (plan d'arrivée).
	- Chemin : le long du plateau vers l'est, corniche taillée dans la falaise qui redescend vers
	  l'ouest (garde-corps), puis lacets sur la pente jusqu'à la porte sud (LAYOUT.southGate).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local BuildContext = require(script.Parent.BuildContext)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local TerrainSculpt = require(script.Parent.TerrainSculpt)

type Context = BuildContext.Context

local L = RegionConfig.LAYOUT
local T = Palette.terrain

local Overlook = {}

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

local function groundPoint(x: number, z: number): Vector3
	return Vector3.new(x, ground(x, z), z)
end

-- CFrame au sol (x, z), tourné de `yaw` degrés, enfoncé de `sink` studs.
local function onGround(x: number, z: number, yaw: number?, sink: number?): CFrame
	return Kit.yaw(Vector3.new(x, ground(x, z) - (sink or 0), z), yaw or 0)
end

--------------------------------------------------------------------------------
-- Chemin du belvédère à la porte sud
--------------------------------------------------------------------------------

type PathPlan = {
	plateau: { Vector3 }, -- du belvédère au haut de la corniche
	ledgeTop: Vector3,
	ledgeBottom: Vector3,
	slope: { Vector3 }, -- lacets sur la pente (du bas de la corniche à la porte sud)
}

-- Points du chemin, exprimés en décalages autour du belvédère et de la porte sud.
local function planPath(): PathPlan
	local o, gate = L.overlook, L.southGate
	local ledgeTop = Vector3.new(o.X + 82, o.Y, o.Z - 16)
	local ledgeBottomXZ = Vector3.new(o.X - 48, 0, o.Z - 22)
	return {
		plateau = { o + Vector3.new(0, 0, -4), o + Vector3.new(45, 0, -8), ledgeTop + Vector3.new(0, 0, 4) },
		ledgeTop = ledgeTop,
		ledgeBottom = Vector3.new(ledgeBottomXZ.X, ground(ledgeBottomXZ.X, ledgeBottomXZ.Z) + 0.5, ledgeBottomXZ.Z),
		slope = {
			ledgeBottomXZ,
			gate + Vector3.new(-60, 0, 120),
			gate + Vector3.new(-56, 0, 96),
			gate + Vector3.new(-20, 0, 78),
			gate + Vector3.new(20, 0, 60),
			gate + Vector3.new(34, 0, 36),
			gate + Vector3.new(16, 0, 16),
			gate + Vector3.new(0, 0, 2),
		},
	}
end

local function sculptPath(plan: PathPlan, random: Random)
	-- Corniche taillée dans la falaise (rampe de terrain, dégagée au-dessus).
	TerrainSculpt.ramp(plan.ledgeTop, plan.ledgeBottom, 10, T.slate, { thickness = 10, clearance = 14 })
	TerrainSculpt.path(plan.plateau, 6, T.mud, { random = random, widthJitter = 0.15 })
	TerrainSculpt.path({ plan.ledgeTop, plan.ledgeBottom }, 7, T.cobble, { follow = false })
	TerrainSculpt.path(plan.slope, 7, T.mud, { random = random, widthJitter = 0.2 })
	-- Herbe morte de part et d'autre des lacets.
	for i = 2, #plan.slope - 1, 2 do
		local p = plan.slope[i]
		TerrainSculpt.patch(p + Vector3.new(random:NextNumber(-14, 14), 0, random:NextNumber(-8, 8)), random:NextNumber(8, 14), T.grass)
	end
end

local function dressPath(folder: Instance, plan: PathPlan, random: Random)
	local pathFolder = Kit.folder(folder, "Path")
	-- Garde-corps solide côté vide (nord de la corniche).
	local railOffset = Vector3.new(0, 0, -5.2)
	Props.fence(pathFolder, plan.ledgeTop + railOffset, plan.ledgeBottom + railOffset, random, { solid = true, broken = 0.12, height = 3.2 })
	-- Lanternes le long de la descente (deux éclairent vraiment).
	local ledgeMid = plan.ledgeTop:Lerp(plan.ledgeBottom, 0.5)
	Props.lanternPost(pathFolder, Kit.yaw(ledgeMid + Vector3.new(0, -0.2, 5), 180), { light = true })
	Props.lanternPost(pathFolder, Kit.yaw(plan.ledgeTop + Vector3.new(-4, -0.2, 6), 200), { lit = false })
	for i, p in plan.slope do
		if i % 2 == 1 and i > 1 then
			local side = if i % 4 == 1 then 5 else -5
			local base = onGround(p.X + side, p.Z, random:NextNumber(0, 360), 0.3)
			Props.lanternPost(pathFolder, base, { light = i == 5, lit = i ~= 7 })
		end
	end
	-- Arbres morts et rochers qui cadrent les lacets.
	local decorSpots: { { dx: number, dz: number, tree: boolean } } = {
		{ dx = 18, dz = 8, tree = true },
		{ dx = -16, dz = -6, tree = false },
		{ dx = 22, dz = -10, tree = true },
		{ dx = -14, dz = 12, tree = true },
		{ dx = 16, dz = 4, tree = false },
		{ dx = -20, dz = 0, tree = true },
	}
	for i, spot in decorSpots do
		local p = plan.slope[math.clamp(i + 1, 1, #plan.slope)]
		local x, z = p.X + spot.dx, p.Z + spot.dz
		if spot.tree then
			Props.deadTree(pathFolder, onGround(x, z, 0, 0.5), random:NextNumber(12, 20), random)
		else
			Props.rockCluster(pathFolder, onGround(x, z, 0, 0.6), random:NextNumber(3, 5), 3, random)
		end
	end
	-- Chariot abandonné dans un virage, et un petit oratoire à l'horloge arrêtée.
	local turn = plan.slope[3]
	Props.cart(pathFolder, onGround(turn.X - 9, turn.Z + 3, 30, 0.2), true, random)
	Props.crate(pathFolder, onGround(turn.X - 13, turn.Z + 7, 15, 0.2), 2.6, true, random)
	local shrineBase = onGround(plan.slope[5].X + 7, plan.slope[5].Z - 4, -60, 0.3)
	local shrine = Kit.model(pathFolder, "WaysideShrine", shrineBase)
	Kit.part(shrine, Kit.at(shrineBase, 0, 1.2, 0), Vector3.new(2.6, 2.4, 2), Palette.stone)
	Kit.part(shrine, Kit.at(shrineBase, 0, 3.2, 0.2), Vector3.new(2.2, 1.8, 1.4), Palette.stoneDark)
	Kit.wedge(shrine, Kit.at(shrineBase, 0, 4.6, 0), Vector3.new(3, 1, 2.4), Palette.roofSlate, { decor = true })
	Props.clock(shrine, Kit.at(shrineBase, 0, 3.2, -0.55), 0.6, false)
	Props.candles(shrine, Kit.at(shrineBase, 0.6, 2.4, -0.7), 2, random, false)
	Props.signPost(pathFolder, onGround(plan.slope[#plan.slope].X + 7, plan.slope[#plan.slope].Z + 6, 200, 0.3), "Village des Cendres", random)
end

--------------------------------------------------------------------------------
-- Belvédère
--------------------------------------------------------------------------------

local function buildOverlook(context: Context, folder: Instance, random: Random)
	local o = L.overlook
	local model = Kit.model(folder, "Belvedere", CFrame.new(o))
	TerrainSculpt.flatten(o, 13, T.slate, 20)
	-- Terrasse : disque de pierre (marche de 0,5) et parapet en arc au-dessus du vide.
	Kit.column(model, CFrame.new(o - Vector3.new(0, 0.5, 0)), 1, 22, Palette.stoneLight, { name = "Terrace" })
	Kit.column(model, CFrame.new(o - Vector3.new(0, 0.45, 0)), 1, 8, Palette.stoneDark, { decor = true, name = "Inlay" })
	local segments = 9
	for i = 0, segments - 1 do
		local a = math.rad(-75 + 150 * (i + 0.5) / segments)
		local center = o + Vector3.new(math.sin(a) * 11.5, 1.6, -math.cos(a) * 11.5)
		local cf = Kit.facing(center, o + Vector3.new(0, 1.6, 0))
		local height = if i == 2 or i == 6 then 1.2 else 2.6 -- deux brèches basses pour la vue
		Kit.part(model, cf * CFrame.new(0, height / 2 - 1.3, 0), Vector3.new(4.4, height + 0.6, 1.2), Palette.stone)
		Kit.part(model, cf * CFrame.new(0, height - 0.95, 0), Vector3.new(4.6, 0.3, 1.5), Palette.stoneLight, { decor = true })
	end
	-- Colonnes brisées de part et d'autre, banc de pierre, arbre mort, lanterne.
	Props.brokenPillar(model, onGround(o.X - 13, o.Z - 2), 7, 2.4, random)
	Props.brokenPillar(model, onGround(o.X + 13, o.Z - 3), 4.5, 2.4, random)
	Props.bench(model, Kit.yaw(o + Vector3.new(-5, 0.5, 5), 0), 6, Palette.stone)
	Props.deadTree(model, onGround(o.X - 19, o.Z + 6, 0, 0.6), 22, random, { look = Palette.deadTreeDark, lean = 20 })
	Props.lanternPost(model, onGround(o.X + 9, o.Z + 6, 160, 0.2), { light = true })
	Props.rockCluster(model, onGround(o.X + 24, o.Z + 10, 0, 0.8), 5, 4, random)

	-- Apparition : face au village ; caméra d'arrivée derrière le joueur, qui cadre le village et le nord.
	local spawnGround = o + Vector3.new(0, 0.5, 0)
	Kit.anchor(context.anchors, "spawn_village", Kit.standing(spawnGround, L.plaza))
	local cameraPosition = o + Vector3.new(6, 11, 17)
	Kit.anchor(context.anchors, "camera_overlook", CFrame.lookAt(cameraPosition, L.chapel + Vector3.new(0, -6, 30)))
end

--------------------------------------------------------------------------------
-- Sanctuaire des Âmes (créateur de personnage)
--------------------------------------------------------------------------------

local function buildSanctuary(context: Context, folder: Instance, random: Random)
	local c = L.creatorStage
	local model = Kit.model(folder, "SanctuaryOfSouls", CFrame.new(c))
	TerrainSculpt.flatten(c, 20, T.slate, 24)
	TerrainSculpt.path({ c + Vector3.new(0, 0, -16), L.overlook + Vector3.new(-12, 0, 8) }, 4, T.ground, { random = random, widthJitter = 0.2 })

	-- Sol : disque de basalte, anneau de dalles, anneau du temps (éteint, cyan pâle).
	local floorTop = c.Y + 0.3
	Kit.column(model, CFrame.new(c - Vector3.new(0, 0.7, 0)), 1, 9, Palette.basalt, { name = "Center" })
	local ring = 12
	for i = 0, ring - 1 do
		local a = (i + 0.5) / ring * math.pi * 2
		local center = c + Vector3.new(math.cos(a) * 6.8, -0.2, math.sin(a) * 6.8)
		Kit.part(model, Kit.facing(center, c) * CFrame.Angles(0, 0, 0), Vector3.new(3.3, 1, 4.4), Palette.darken(Palette.stone, random:NextNumber(0.85, 1.05)))
	end
	Kit.column(model, CFrame.new(c + Vector3.new(0, 0.3, 0)), 0.05, 9.6, Palette.temporalInlay, { decor = true, name = "TimeRing" })
	Kit.column(model, CFrame.new(c + Vector3.new(0, 0.31, 0)), 0.06, 8.6, Palette.basalt, { decor = true, name = "TimeRingInner" })

	-- Menhirs (aucun au sud : la caméra y est placée).
	for _, degrees in { 0, 40, -40, 80, -80, 120, -120 } do
		local a = math.rad(degrees)
		local base = Vector3.new(c.X + math.sin(a) * 12.5, ground(c.X + math.sin(a) * 12.5, c.Z - math.cos(a) * 12.5) - 1, c.Z - math.cos(a) * 12.5)
		local height = random:NextNumber(6, 10)
		local cf = Kit.facing(base, c) * CFrame.Angles(math.rad(random:NextNumber(-6, 6)), 0, math.rad(random:NextNumber(-5, 5)))
		Kit.part(model, cf * CFrame.new(0, height / 2, 0), Vector3.new(2.4, height, 1.6), Palette.darken(Palette.granite, random:NextNumber(0.75, 1)), { name = "Menhir" })
		Kit.part(model, cf * CFrame.new(0, height * 0.6, -0.82), Vector3.new(0.25, height * 0.35, 0.06), Palette.temporalCyanDim, { decor = true, transparency = 0.3, name = "Glyph" })
		local lightIt = degrees == 0 or degrees == 80 or degrees == -80
		Props.candles(model, Kit.yaw(base + Vector3.new(0, 1, 0) + (c - base).Unit * 2, 0), random:NextInteger(3, 5), random, lightIt)
	end

	-- Trois arches sombres au nord, tournées vers le centre (fond du plan du créateur).
	for _, degrees in { -48, 0, 48 } do
		local a = math.rad(degrees)
		local base = Vector3.new(c.X + math.sin(a) * 17, c.Y - 0.5, c.Z - math.cos(a) * 17)
		Props.archway(model, Kit.facing(base, c), 6, 13 + (if degrees == 0 then 3 else 0), 1.6, Palette.basalt, true)
	end
	-- Bannières déchirées entre les arches, et la lisière du plateau.
	Props.deadTree(model, onGround(c.X + 26, c.Z + 4, 0, 0.6), 16, random, { look = Palette.charredWood })
	Props.deadTree(model, onGround(c.X - 27, c.Z - 8, 0, 0.6), 19, random)
	Props.rockCluster(model, onGround(c.X - 22, c.Z + 14, 0, 0.8), 4, 3, random)

	-- Ancres : centre du cercle, regard vers la caméra (au sud) ; caméra face au personnage.
	local stageGround = Vector3.new(c.X, floorTop, c.Z)
	local cameraPosition = c + Vector3.new(0, 4.6, 10)
	Kit.anchor(context.anchors, "spawn_creator", Kit.standing(stageGround, cameraPosition))
	Kit.anchor(context.anchors, "camera_creator", CFrame.lookAt(cameraPosition, stageGround + Vector3.new(0, 3, 0)))
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Overlook.build(context: Context)
	local folder = context.zone("Overlook")
	local random = context.random
	local plan = planPath()
	sculptPath(plan, random)
	buildOverlook(context, folder, random)
	buildSanctuary(context, folder, random)
	dressPath(folder, plan, random)
end

return table.freeze(Overlook)
