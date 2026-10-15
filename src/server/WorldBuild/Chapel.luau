--!strict
--[[
	Chapel (zone)
	La Chapelle de la Cloche Muette sur sa butte, au nord de la place : nef gothique en ruine (toit
	effondré), clocher au nord avec la grande cloche fissurée, alcôve secrète contre la façade ouest,
	chemin pavé depuis la place et sentier vers la rive du lac.

	Contrat posé ici :
		ancres        echo_bell (+ trajet World.EchoPaths.echo_bell, 10 points)
		interactables clue_bell_inscription, clue_hymnbook, clue_frozen_clock, bell_main,
		              mech_shadow_wall, chest_shadow
		dynamics      shadow_passage (pan de mur de l'alcôve, "toggle_collide")
	(npc_bellkeeper, au pied du chemin, est posé par Village.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local BuildContext = require(script.Parent.BuildContext)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local PropsBuildings = require(script.Parent.PropsBuildings)
local PropsSacred = require(script.Parent.PropsSacred)
local TerrainSculpt = require(script.Parent.TerrainSculpt)
local Village = require(script.Parent.Village)

type Context = BuildContext.Context

local L = RegionConfig.LAYOUT
local T = Palette.terrain
local G = L.groundHeight

-- Nef : de la façade sud (NAVE_SOUTH) au clocher (NAVE_NORTH), largeur NAVE_WIDTH.
local NAVE_WIDTH = 22
local NAVE_SOUTH = L.chapel.Z + 16 -- façade (porte) ; le parvis est au sud
local NAVE_NORTH = L.bellTower.Z + 7 -- mur nord de la nef = mur sud du clocher
local WALL_HEIGHT = 15
local WALL_THICKNESS = 1.4
local TOWER_SIZE = 12
local TOWER_HEIGHT = 50
local BELL_HEIGHT = 5

local Chapel = {}

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

local function onGround(x: number, z: number, yaw: number?, sink: number?): CFrame
	return Kit.yaw(Vector3.new(x, ground(x, z) - (sink or 0), z), yaw or 0)
end

--------------------------------------------------------------------------------
-- Terrain : plateau de la butte, chemin de la place, sentier du lac
--------------------------------------------------------------------------------

local function sculpt(random: Random): number
	local floorY = L.chapel.Y
	TerrainSculpt.flatten(Vector3.new(0, floorY, (NAVE_SOUTH + L.bellTower.Z) / 2 - 2), 30, T.ground, 40)
	-- Chemin pavé : de la place (bord nord) au parvis, en rampe régulière.
	local foot = Vector3.new(0, G, -L.plazaRadius - 2)
	local parvis = Vector3.new(0, floorY, NAVE_SOUTH + 6)
	TerrainSculpt.ramp(foot, parvis, 9, T.cobble, { thickness = 10, clearance = 14 })
	TerrainSculpt.path({ parvis, Vector3.new(0, floorY, NAVE_SOUTH + 1) }, 10, T.cobble, { follow = false })
	-- Sentier vers la rive du lac, par le flanc est de la butte.
	TerrainSculpt.path({
		Vector3.new(14, floorY, L.bellTower.Z + 2),
		Vector3.new(22, floorY, L.bellTower.Z - 20),
		Vector3.new(16, floorY, L.bellTower.Z - 52),
		Vector3.new(4, floorY, L.lakeShore.Z + 6),
	}, 5, T.mud, { random = random, widthJitter = 0.2 })
	return floorY
end

--------------------------------------------------------------------------------
-- Nef
--------------------------------------------------------------------------------

type Window = { x0: number, x1: number, y0: number, y1: number, kind: "window" }

local function windowsAlong(length: number, count: number): { Window }
	local openings: { Window } = {}
	for i = 1, count do
		local x = -length / 2 + length * i / (count + 1)
		table.insert(openings, { x0 = x - 1.6, x1 = x + 1.6, y0 = 4, y1 = 11.5, kind = "window" })
	end
	return openings
end

local function buildNave(folder: Instance, floorY: number, random: Random): Model
	local length = NAVE_SOUTH - NAVE_NORTH
	local centerZ = (NAVE_SOUTH + NAVE_NORTH) / 2
	local base = CFrame.new(0, floorY, centerZ)
	local model = Kit.model(folder, "Nave", base)
	local t = WALL_THICKNESS
	-- Sol de dalles et soubassement.
	Kit.part(model, base * CFrame.new(0, -0.6, 0), Vector3.new(NAVE_WIDTH + 1, 1.6, length + 1), Palette.stoneDark, { name = "Plinth" })
	Kit.part(model, base * CFrame.new(0, 0.25, 0), Vector3.new(NAVE_WIDTH - 2 * t, 0.1, length - 2 * t), Palette.stoneLight, Kit.DECOR)

	-- Murs latéraux percés de baies (l'est est en partie écroulé), façade sud, mur nord (arche du clocher).
	-- L'ouest n'a que deux baies : le trumeau central, plein, sert de fond à l'alcôve de l'Ombre.
	local westOpenings = windowsAlong(length - 2 * t, 2)
	local sideOpenings = windowsAlong(length - 2 * t, 3)
	PropsBuildings.panelWall(model, base * CFrame.new(-(NAVE_WIDTH / 2 - t / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0), length - 2 * t, WALL_HEIGHT, westOpenings, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(NAVE_WIDTH / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), length - 2 * t, WALL_HEIGHT, sideOpenings, Palette.stone, nil, { thickness = t, jagged = 0.55, random = random })
	local door = { x0 = -2.8, x1 = 2.8, y0 = 0, y1 = 9.5, kind = "door" :: "door" }
	local facade = base * CFrame.new(0, 0, length / 2 - t / 2) * CFrame.Angles(0, math.pi, 0)
	PropsBuildings.panelWall(model, facade, NAVE_WIDTH, WALL_HEIGHT, { door }, Palette.stone, nil, { thickness = t })
	PropsBuildings.gable(model, facade * CFrame.new(0, WALL_HEIGHT, 0), NAVE_WIDTH, 8, t, Palette.stone)
	PropsBuildings.archway(model, facade * CFrame.new(0, 0, -t / 2 - 0.4), 5.6, 10.5, 1, Palette.stoneLight, true)
	local towerArch = { x0 = -3, x1 = 3, y0 = 0, y1 = 10, kind = "door" :: "door" }
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, -length / 2 + t / 2), NAVE_WIDTH, WALL_HEIGHT, { towerArch }, Palette.stone, nil, { thickness = t })

	-- Vitraux (certains brisés) dans les baies de l'ouest.
	for _, opening in westOpenings do
		local z = -(opening.x0 + opening.x1) / 2 -- X local du mur ouest = -Z du monde
		local frame = base * CFrame.new(-(NAVE_WIDTH / 2 - t / 2), opening.y0, z) * CFrame.Angles(0, math.rad(90), 0)
		local glass = if random:NextNumber() < 0.5 then Palette.stainedBlue else Palette.stainedRed
		PropsSacred.gothicWindow(model, frame, 3.2, 7.5, glass, { random = random, broken = random:NextNumber() < 0.6 })
	end

	-- Toit effondré : quelques fermes calcinées et un pan de toiture encore debout à l'ouest.
	for i = 0, 4 do
		local z = -length / 2 + 4 + i * (length - 8) / 4
		if i ~= 2 then
			local y = WALL_HEIGHT + 0.5
			Kit.beam(model, (base * CFrame.new(-NAVE_WIDTH / 2 + 0.5, y, z)).Position, (base * CFrame.new(0, y + 6.5, z)).Position, 0.9, 0.9, Palette.charredWood)
			if i % 2 == 0 then
				Kit.beam(model, (base * CFrame.new(0, y + 6.5, z)).Position, (base * CFrame.new(NAVE_WIDTH / 2 - 0.5, y, z)).Position, 0.9, 0.9, Palette.charredWood)
			end
		end
	end
	local roofCF = base * CFrame.new(-NAVE_WIDTH / 4, WALL_HEIGHT + 3.6, -length / 4) * CFrame.Angles(0, 0, math.rad(31))
	Kit.part(model, roofCF, Vector3.new(NAVE_WIDTH / 2 + 2.2, 0.6, length / 2), Palette.roofBurnt, { name = "RoofRemnant" })
	Props.charredBeams(model, base * CFrame.new(5, 0.3, 4), 11, random)
	Props.rubble(model, base * CFrame.new(7, 0.3, -4), 4, 9, random)
	return model
end

-- Mobilier de la nef et indices de la quête.
local function furnishNave(context: Context, nave: Model, floorY: number, random: Random)
	local centerZ = (NAVE_SOUTH + NAVE_NORTH) / 2
	local floorTop = floorY + 0.3
	-- Bancs de part et d'autre de l'allée centrale.
	for row = 0, 4 do
		local z = centerZ + 7 - row * 3.6
		for _, x in { -5.2, 5.2 } do
			PropsSacred.pew(nave, Kit.yaw(Vector3.new(x, floorTop, z), 0), 6.5, random, random:NextNumber() < 0.4)
		end
	end
	-- Livre d'hymnes sur un lutrin renversé (dans l'allée, côté est).
	local _, bookCFrame = PropsSacred.lectern(nave, Kit.yaw(Vector3.new(3, floorTop, centerZ - 10), 160), true)
	local book = PropsSacred.book(nave, bookCFrame, true)
	Kit.tagInteractable(book, "clue_hymnbook")
	-- Horloge figée sur le mur ouest (intérieur), à hauteur d'homme, cadran vers l'est.
	local clockPosition = Vector3.new(-NAVE_WIDTH / 2 + WALL_THICKNESS + 0.3, floorTop + 5, centerZ + 2)
	local _, dial = Props.clock(nave, Kit.facing(clockPosition, clockPosition + Vector3.new(1, 0, 0)), 1.4, true)
	Kit.tagInteractable(dial, "clue_frozen_clock")
	-- Autel, candélabres (une lumière chaude), ossements.
	PropsSacred.altar(nave, Kit.yaw(Vector3.new(0, floorTop, NAVE_NORTH + 6), 180), 6, 3)
	PropsSacred.candelabrum(nave, Kit.yaw(Vector3.new(-4, floorTop, NAVE_NORTH + 5), 0), 4.5, { light = true })
	PropsSacred.candelabrum(nave, Kit.yaw(Vector3.new(4, floorTop, NAVE_NORTH + 5), 0), 4.5, { light = false })
	PropsSacred.boneHeap(nave, Kit.yaw(Vector3.new(-7, floorTop, centerZ - 6), 0), 2, random)
	local _ = context
end

--------------------------------------------------------------------------------
-- Clocher et cloche
--------------------------------------------------------------------------------

local function buildTower(context: Context, folder: Instance, floorY: number, random: Random)
	local s = TOWER_SIZE
	local t = WALL_THICKNESS
	local centerZ = NAVE_NORTH - s / 2
	local base = CFrame.new(0, floorY, centerZ)
	local model = Kit.model(folder, "BellTower", base)
	Kit.part(model, base * CFrame.new(0, -0.6, 0), Vector3.new(s + 1, 1.6, s + 1), Palette.stoneDark, { name = "Plinth" })
	-- Quatre murs pleins jusqu'à la chambre des cloches (le sud est ouvert sur la nef par l'arche).
	local opening = { x0 = -3, x1 = 3, y0 = 0, y1 = 10, kind = "door" :: "door" }
	local belfry = { x0 = -2.6, x1 = 2.6, y0 = TOWER_HEIGHT - 12, y1 = TOWER_HEIGHT - 3, kind = "window" :: "window" }
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, s / 2 - t / 2) * CFrame.Angles(0, math.pi, 0), s, TOWER_HEIGHT, { opening, belfry }, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, -s / 2 + t / 2), s, TOWER_HEIGHT, { belfry }, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(-(s / 2 - t / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0), s - 2 * t, TOWER_HEIGHT, { belfry }, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(s / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), s - 2 * t, TOWER_HEIGHT, { belfry }, Palette.stone, nil, { thickness = t })
	-- Flèche (pyramide en coins) au sommet.
	local top = base * CFrame.new(0, TOWER_HEIGHT, 0)
	Kit.part(model, top * CFrame.new(0, 0.5, 0), Vector3.new(s + 1.2, 1, s + 1.2), Palette.stoneDark, { name = "Cornice" })
	for i = 0, 3 do
		local face = top * CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, 7.5, -s / 4)
		Kit.wedge(model, face, Vector3.new(s, 13, s / 2), Palette.roofSlate, { decor = true })
	end
	-- Poutre et grande cloche fissurée dans la chambre haute ; corde jusqu'en bas.
	local hangY = floorY + TOWER_HEIGHT - 2.5
	Kit.cylinder(model, CFrame.new(0, hangY + 0.4, centerZ), s - 2 * t, 0.9, Palette.charredWood, { name = "BellBeam" })
	PropsSacred.bell(model, Kit.yaw(Vector3.new(0, hangY, centerZ), 180), BELL_HEIGHT, { cracked = true })
	local ropeTop = Vector3.new(0.5, hangY - BELL_HEIGHT * 0.9, centerZ)
	local gripTop = Vector3.new(0.5, floorY + 7, centerZ)
	Kit.rod(model, ropeTop, gripTop, 0.28, Palette.cloth, Kit.DECOR)
	-- Le bout de la corde, à portée de main : c'est l'interactable (la cloche est trop haute).
	local grip = Kit.rod(model, gripTop, Vector3.new(0.5, floorY + 2.2, centerZ), 0.34, Palette.cloth, { name = "BellRope" })
	Kit.tagInteractable(grip, "bell_main")
	-- Socle gravé au pied du clocher (inscription).
	local socleCF = CFrame.new(-3, floorY + 1, centerZ - 2) * CFrame.Angles(0, math.rad(90), 0)
	local socle = Kit.part(model, socleCF, Vector3.new(2.6, 2, 1.6), Palette.granite, { name = "BellSocle" })
	Kit.surfaceText(socle, Enum.NormalId.Front, "3 + 1", { color = Palette.colors.chalk, pixelsPerStud = 30 })
	Kit.tagInteractable(socle, "clue_bell_inscription")
	PropsSacred.wallSconce(model, CFrame.new(s / 2 - t - 0.1, floorY + 6, centerZ) * CFrame.Angles(0, math.rad(90), 0), { light = true, range = 14 })
	Props.rubble(model, base * CFrame.new(2.5, 0.3, -2.5), 2.5, 5, random)
	local _ = context
end

--------------------------------------------------------------------------------
-- Alcôve de l'Ombre (façade ouest, à l'extérieur)
--------------------------------------------------------------------------------

local function buildShadowAlcove(context: Context, folder: Instance, floorY: number, random: Random)
	local wallX = -NAVE_WIDTH / 2
	local z = (NAVE_SOUTH + NAVE_NORTH) / 2 -- devant le trumeau plein entre les deux baies
	local depth, width, height, t = 4.4, 4.4, 7, 1
	-- Niche : sol, deux joues, toit ; le fond est le mur de la nef.
	local center = CFrame.new(wallX - depth / 2, floorY, z)
	local model = Kit.model(folder, "ShadowAlcove", center)
	Kit.part(model, center * CFrame.new(0, -0.5, 0), Vector3.new(depth + 0.4, 1.4, width + 2 * t), Palette.stoneDark, { name = "Floor" })
	for _, side in { -1, 1 } do
		Kit.part(model, center * CFrame.new(0, height / 2, side * (width / 2 + t / 2)), Vector3.new(depth, height, t), Palette.stone, { name = "Cheek" })
	end
	Kit.part(model, center * CFrame.new(0, height + 0.5, 0), Vector3.new(depth + 0.6, 1, width + 2 * t + 0.6), Palette.stone, { name = "Lintel" })
	local _, cache = Props.chest(model, Kit.facing(Vector3.new(wallX - 1.6, floorY + 0.2, z), Vector3.new(wallX - 10, floorY, z)), Palette.charredWood)
	Kit.tagInteractable(cache, "chest_shadow")
	PropsSacred.boneHeap(model, CFrame.new(wallX - 1.2, floorY + 0.2, z + 1.6), 1, random)

	-- Pan de mur qui ferme la niche (dynamic) : traversable quand l'Ombre le révèle.
	local panelCF = Kit.facing(Vector3.new(wallX - depth + t / 2, floorY + height / 2, z), Vector3.new(wallX - 20, floorY + height / 2, z))
	local panel = Kit.part(context.dynamic, panelCF, Vector3.new(width, height, t), Palette.stone, { name = "ShadowlessWall", shadow = false })
	Kit.dynamic(context.dynamic, panel, "shadow_passage")
	-- Le sceau sans ombre, gravé sur la joue sud (l'interactable de la magie de l'Ombre).
	local sigilCF = Kit.facing(Vector3.new(wallX - depth - 0.05, floorY + 3.6, z + width / 2 + t / 2), Vector3.new(wallX - 20, floorY + 3.6, z + width / 2 + t / 2))
	local sigil = Kit.part(model, sigilCF, Vector3.new(0.9, 1.3, 0.12), Palette.void, { name = "ShadowSigil" })
	Kit.tagInteractable(sigil, "mech_shadow_wall")
end

--------------------------------------------------------------------------------
-- Écho du sonneur : du parvis au puits aux runes
--------------------------------------------------------------------------------

local function buildBellEcho(context: Context, floorY: number)
	local parvis = Vector3.new(0, floorY, NAVE_SOUTH + 5)
	Kit.anchor(context.anchors, "echo_bell", Kit.standing(parvis, L.plaza))
	local function groundAt(x: number, z: number): Vector3
		return Vector3.new(x, ground(x, z), z)
	end
	local points: { Vector3 } = {
		Vector3.new(0, floorY, NAVE_SOUTH + 4), -- 1 parvis
		groundAt(0, NAVE_SOUTH + 12), -- 2 haut du chemin
		groundAt(0, (NAVE_SOUTH - L.plazaRadius) / 2), -- 3 mi-pente
		groundAt(0, -L.plazaRadius), -- 4 pied du chemin (« Trois, puis un »)
		groundAt(-10, -12), -- 5 la place
		groundAt(-24, 4), -- 6 vers le puits
		Village.wellRuneStand(3), -- 7 rune ouest (Soir)
		Village.wellRuneStand(1), -- 8 rune est (Matin)
		Village.wellRuneStand(4), -- 9 rune nord (Minuit)
		Village.wellRuneStand(2), -- 10 rune sud (Midi)
	}
	for index, point in points do
		local nextPoint = points[index + 1] or L.well
		context.addEchoPoint("echo_bell", index, Kit.facing(point, nextPoint))
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Chapel.build(context: Context)
	local folder = context.zone("Chapel")
	local random = context.random
	local floorY = sculpt(random)
	local nave = buildNave(folder, floorY, random)
	furnishNave(context, nave, floorY, random)
	buildTower(context, folder, floorY, random)
	buildShadowAlcove(context, folder, floorY, random)
	buildBellEcho(context, floorY)
	-- Abords : arbres morts, tombes anciennes, lanterne au parvis.
	Props.lanternPost(folder, Kit.yaw(Vector3.new(6, floorY - 0.2, NAVE_SOUTH + 5), 180), { light = true })
	Props.deadTree(folder, onGround(-20, NAVE_SOUTH + 2, 0, 0.6), 18, random, { look = Palette.deadTreeDark })
	Props.deadTree(folder, onGround(19, L.bellTower.Z - 4, 0, 0.6), 14, random)
	for i = 1, 5 do
		local x, z = 16 + i * 2.4, NAVE_SOUTH - 6 - i * 4
		Props.tomb(folder, Kit.yaw(Vector3.new(x, ground(x, z) - 0.4, z), 90 + random:NextNumber(-15, 15)), if i % 2 == 0 then "cross" else "rounded", random)
	end
end

return table.freeze(Chapel)
