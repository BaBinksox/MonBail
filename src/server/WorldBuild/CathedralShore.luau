--!strict
--[[
	CathedralShore (zone)
	Les Rives de la Cathédrale Engloutie, au nord de la chapelle : grève de vase, chaussée de pierre
	à demi submergée qui traverse le lac, et au bout le Portail Englouti, scellé. Au-delà, les flèches
	de la cathédrale émergent de l'eau noire (repère visuel, inaccessible pour l'instant).

	Contrat posé ici :
		interactables cathedral_gate (porte de région : rang C + quête bell_silent ; zone « à venir »)
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

local CAUSEWAY_WIDTH = 9
local CAUSEWAY_TOP = L.causewayEnd.Y
local GATE_WIDTH = 12
local GATE_HEIGHT = 22

local CathedralShore = {}

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

-- Chaussée : dalles successives de la rive au parvis du portail, quelques-unes affaissées.
local function buildCauseway(folder: Instance, random: Random)
	local model = Kit.model(folder, "Causeway", CFrame.new(L.lakeShore))
	local startZ = L.lakeShore.Z - 4
	local endZ = L.causewayEnd.Z
	local length = startZ - endZ
	local slabs = math.floor(length / 6)
	for i = 0, slabs - 1 do
		local z = startZ - (i + 0.5) * (length / slabs)
		local sag = if random:NextNumber() < 0.15 then random:NextNumber(0.3, 0.9) else 0
		local tilt = if sag > 0 then random:NextNumber(-3, 3) else 0
		local cf = CFrame.new(L.causewayEnd.X + random:NextNumber(-0.3, 0.3), CAUSEWAY_TOP - 0.5 - sag, z) * CFrame.Angles(0, 0, math.rad(tilt))
		Kit.part(model, cf, Vector3.new(CAUSEWAY_WIDTH, 1, length / slabs - 0.15), Palette.darken(Palette.stoneLight, random:NextNumber(0.75, 0.95)), { name = "Slab" })
		-- Piles qui plongent dans l'eau (une sur deux), parapet bas par endroits.
		if i % 2 == 0 then
			Kit.part(model, CFrame.new(L.causewayEnd.X, (CAUSEWAY_TOP - 1 + Config.LAKE_BOTTOM) / 2, z), Vector3.new(CAUSEWAY_WIDTH - 1, CAUSEWAY_TOP - 1 - Config.LAKE_BOTTOM, 3), Palette.stoneDark, { name = "Pier", shadow = false })
		end
		if random:NextNumber() < 0.45 then
			for _, side in { -1, 1 } do
				if random:NextNumber() < 0.6 then
					Kit.part(model, CFrame.new(L.causewayEnd.X + side * (CAUSEWAY_WIDTH / 2 - 0.4), CAUSEWAY_TOP + 0.6, z), Vector3.new(0.8, 1.2, length / slabs * 0.8), Palette.stone, { name = "Parapet" })
				end
			end
		end
	end
	-- Lanternes mortes et statues de veilleurs le long de la chaussée.
	for i = 1, 4 do
		local z = startZ - i * length / 5
		local side = if i % 2 == 0 then 1 else -1
		local x = L.causewayEnd.X + side * (CAUSEWAY_WIDTH / 2 - 0.6)
		if i % 2 == 0 then
			PropsSacred.statue(model, Kit.facing(Vector3.new(x, CAUSEWAY_TOP, z), Vector3.new(0, CAUSEWAY_TOP, z)), 6, random, { broken = i == 4, plinth = 1.2, look = Palette.darken(Palette.granite, 0.8) })
		else
			Props.lanternPost(model, Kit.facing(Vector3.new(x, CAUSEWAY_TOP, z), Vector3.new(0, CAUSEWAY_TOP, z)), { lit = false })
		end
	end
end

-- Parvis et Portail Englouti (scellé, solide).
local function buildGate(folder: Instance, random: Random)
	local gatePos = L.cathedralGate
	local base = Kit.yaw(Vector3.new(gatePos.X, CAUSEWAY_TOP, gatePos.Z), 180) -- la façade regarde le sud (la rive)
	local model = Kit.model(folder, "SunkenPortal", base)
	-- Parvis : plateforme carrée sur pilotis.
	local apronCenter = CFrame.new(gatePos.X, CAUSEWAY_TOP - 0.5, (L.causewayEnd.Z + gatePos.Z) / 2 - 2)
	Kit.part(model, apronCenter, Vector3.new(30, 1, 26), Palette.stoneLight, { name = "Apron" })
	Kit.part(model, apronCenter * CFrame.new(0, (Config.LAKE_BOTTOM - CAUSEWAY_TOP) / 2, 0), Vector3.new(28, CAUSEWAY_TOP - Config.LAKE_BOTTOM, 24), Palette.stoneDark, { name = "Foundation", shadow = false })
	-- Massif de façade : deux tours trapues, la grande arche brisée, les vantaux fermés.
	local facade = base * CFrame.new(0, 0, 2)
	for _, side in { -1, 1 } do
		Kit.part(model, facade * CFrame.new(side * (GATE_WIDTH / 2 + 5), 15, 3), Vector3.new(9, 30, 8), Palette.basalt, { name = "Tower" })
		Kit.part(model, facade * CFrame.new(side * (GATE_WIDTH / 2 + 5), 31.5, 3), Vector3.new(10, 3, 9), Palette.stoneDark, { name = "Crown" })
		Kit.wedge(model, facade * CFrame.new(side * (GATE_WIDTH / 2 + 5), 37, 3), Vector3.new(9, 8, 8), Palette.roofSlate, { decor = true })
	end
	PropsBuildings.archway(model, facade, GATE_WIDTH, GATE_HEIGHT, 4, Palette.basalt, true)
	Kit.part(model, facade * CFrame.new(0, GATE_HEIGHT + 4, 3), Vector3.new(GATE_WIDTH + 2, 8, 8), Palette.basalt, { name = "Tympanum" })
	local doors = Kit.part(model, facade * CFrame.new(0, (GATE_HEIGHT - 4) / 2, 0.5), Vector3.new(GATE_WIDTH, GATE_HEIGHT - 4, 1.2), Palette.bronzeDark, { name = "SealedDoors" })
	Kit.part(model, facade * CFrame.new(0, (GATE_HEIGHT - 4) / 2, -0.15), Vector3.new(0.25, GATE_HEIGHT - 4.4, 0.1), Palette.temporalCyanDim, { decor = true, name = "SealSeam", transparency = 0.2 })
	Kit.cylinder(model, facade * CFrame.new(0, GATE_HEIGHT * 0.45, -0.2) * CFrame.Angles(0, math.rad(90), 0), 0.12, 5, Palette.temporalCyan, { decor = true, name = "Seal", transparency = 0.35 })
	Kit.light(doors, { color = Palette.colors.temporalLight, brightness = 1.1, range = 18, face = Enum.NormalId.Front, kind = "surface", angle = 80 })
	Kit.tagInteractable(doors, "cathedral_gate")
	-- Vitrail en rosace au-dessus de l'arche, braseros éteints au parvis.
	PropsSacred.gothicWindow(model, facade * CFrame.new(0, GATE_HEIGHT + 1.5, -1.05), 4, 5, Palette.stainedBlue, { random = random, broken = true })
	for _, side in { -1, 1 } do
		Props.brazier(model, facade * CFrame.new(side * 9, 0, -9), { lit = false, light = false, stone = true })
	end
end

-- Flèches de la cathédrale qui émergent de l'eau, loin au nord (silhouettes inaccessibles).
local function buildSpires(folder: Instance, random: Random)
	local s = L.cathedralSpires
	local model = Kit.model(folder, "SunkenSpires", CFrame.new(s))
	local spires = {
		{ dx = 0, dz = 0, height = 95, width = 14, lean = 4 },
		{ dx = -34, dz = 14, height = 66, width = 10, lean = -9 },
		{ dx = 32, dz = 10, height = 72, width = 10, lean = 7 },
		{ dx = -12, dz = 30, height = 40, width = 18, lean = 0 },
		{ dx = 16, dz = 28, height = 34, width = 16, lean = 12 },
	}
	for _, spire in spires do
		local foot = CFrame.new(s.X + spire.dx, Config.LAKE_BOTTOM, s.Z + spire.dz) * CFrame.Angles(math.rad(spire.lean * 0.4), 0, math.rad(spire.lean))
		local shaft = spire.height * 0.72
		Kit.part(model, foot * CFrame.new(0, shaft / 2, 0), Vector3.new(spire.width, shaft, spire.width), Palette.basalt, { name = "Spire", collide = false })
		for i = 0, 3 do
			local face = foot * CFrame.new(0, shaft, 0) * CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, spire.height * 0.14, -spire.width / 4)
			Kit.wedge(model, face, Vector3.new(spire.width, spire.height * 0.28, spire.width / 2), Palette.roofSlate, { decor = true })
		end
		-- Fenêtres hautes encore éclairées d'une lueur froide.
		for _, y in { shaft * 0.55, shaft * 0.8 } do
			Kit.part(model, foot * CFrame.new(0, y, -spire.width / 2 - 0.05), Vector3.new(spire.width * 0.25, spire.width * 0.6, 0.1), Palette.temporalCyanDim, { decor = true, transparency = 0.25 })
		end
	end
	local _ = random
end

-- Grève : barques échouées, pieux, ossements, sentier depuis la chapelle (posé par Chapel).
local function buildShore(folder: Instance, random: Random)
	local shore = L.lakeShore
	local model = Kit.model(folder, "Shore", CFrame.new(shore))
	for i = 1, 3 do
		local x, z = shore.X - 22 + i * 13, shore.Z + random:NextNumber(-2, 4)
		local base = Kit.yaw(Vector3.new(x, ground(x, z) - 0.3, z), random:NextNumber(-40, 40))
		local boat = Kit.model(model, "Wreck", base)
		Kit.part(boat, base * CFrame.new(0, 0.5, 0), Vector3.new(3, 1, 9), Palette.charredWood, { name = "Hull" })
		for _, side in { -1, 1 } do
			Kit.part(boat, base * CFrame.new(side * 1.5, 1, 0) * CFrame.Angles(0, 0, math.rad(side * 18)), Vector3.new(0.3, 1.4, 8.6), Palette.burntWood, Kit.DECOR)
		end
	end
	for i = 0, 9 do
		local x = shore.X - 30 + i * 6.5 + random:NextNumber(-1, 1)
		local z = shore.Z - 6 + random:NextNumber(-2, 2)
		Kit.part(model, CFrame.new(x, ground(x, z) + 1, z) * CFrame.Angles(math.rad(random:NextNumber(-12, 12)), 0, math.rad(random:NextNumber(-12, 12))), Vector3.new(0.6, 3.5, 0.6), Palette.charredWood, Kit.DECOR)
	end
	Props.signPost(model, Kit.yaw(Vector3.new(shore.X + 7, ground(shore.X + 7, shore.Z + 4) - 0.3, shore.Z + 4), 180), "Portail Englouti  ↑", random)
	PropsSacred.boneHeap(model, CFrame.new(shore.X - 9, ground(shore.X - 9, shore.Z - 2), shore.Z - 2), 1.4, random)
end

function CathedralShore.build(context: Context)
	local folder = context.zone("CathedralShore")
	local random = context.random
	buildShore(folder, random)
	buildCauseway(folder, random)
	buildGate(folder, random)
	buildSpires(folder, random)
end

return table.freeze(CathedralShore)
