--!strict
--[[
	Village (zone)
	Le Village des Cendres : place de l'Horloger, rues, maisons brûlées, taverne, forge, tableaux,
	Salle des Serments et ses Archives, puits aux runes (entrée de la crypte), portes sud et ouest,
	Cimetière des Oubliés et son mausolée.

	Contrat posé ici :
		ancres      spawn_plaza, npc_elder, npc_blacksmith, npc_child, npc_quartermaster,
		            npc_guildmaster, npc_wanderer, npc_villager_1/2/3, well_cover_open, crypt_exit_top,
		            gate_archive_inside, gate_archive_outside
		interactables board_missions, board_guild, well_rune_1..4, guild_archive_door,
		            chest_guild_archive, mech_barrier_cemetery, chest_cemetery, shadow_presence
		dynamics    well_cover (dalle du puits, "slide"), barrier_cemetery (voile, "toggle_collide")
	Le puits est creusé jusqu'à la crypte (escalier en colimaçon) : la salle elle-même est dans Crypt.

	Village.wellRuneStand(index) : point au sol face à la rune `index` (utilisé par l'écho du sonneur).
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

type Context = BuildContext.Context

local L = RegionConfig.LAYOUT
local T = Palette.terrain
local G = L.groundHeight

-- Puits aux runes : margelle, runes (1 est, 2 sud, 3 ouest, 4 nord, voir MechanismConfig) et dalle.
local WELL_MARGIN_RADIUS = 4.3
local WELL_MARGIN_HEIGHT = 1.6
local WELL_RUNE_RADIUS = 5.6
local WELL_STAND_RADIUS = 8
local WELL_SHAFT_RADIUS = 4
local RUNE_ANGLES = { 0, 90, 180, -90 } -- degrés (convention Kit.ringPoint : 0 = est, 90 = sud)
local COVER_OPEN_ANGLE = 135 -- la dalle glisse entre les runes sud et ouest...
local COVER_OPEN_DISTANCE = 9.5 -- ...assez loin pour ne pas recouvrir ces deux runes
local CRYPT_FLOOR = L.cryptHall.Y

local Village = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

local function groundPoint(x: number, z: number): Vector3
	return Vector3.new(x, ground(x, z), z)
end

-- CFrame au sol (x, z) qui regarde horizontalement vers `target`, enfoncé de `sink`.
local function facingGround(x: number, z: number, target: Vector3, sink: number?): CFrame
	return Kit.facing(Vector3.new(x, ground(x, z) - (sink or 0), z), target)
end

local function onGround(x: number, z: number, yaw: number?, sink: number?): CFrame
	return Kit.yaw(Vector3.new(x, ground(x, z) - (sink or 0), z), yaw or 0)
end

-- Ancre de PNJ / d'apparition posée au sol, regard vers `target`.
local function standing(context: Context, id: string, x: number, z: number, target: Vector3)
	Kit.anchor(context.anchors, id, Kit.standing(groundPoint(x, z), target))
end

function Village.wellRuneStand(index: number): Vector3
	local p = Kit.ringPoint(L.well, WELL_STAND_RADIUS, RUNE_ANGLES[index] or 0)
	return Vector3.new(p.X, ground(p.X, p.Z), p.Z)
end

--------------------------------------------------------------------------------
-- Terrain : place, emplacements des bâtiments, rues
--------------------------------------------------------------------------------

type Lot = {
	x: number,
	z: number,
	width: number,
	depth: number,
	floors: number,
	state: PropsBuildings.HouseState,
	lit: boolean?,
	roof: PropsBuildings.RoofStyle?,
	face: Vector3?, -- point regardé par la façade (défaut : la place)
}

-- Maisons du village (hors bâtiments nommés). Façade tournée vers la place ou la rue la plus proche.
local LOTS: { Lot } = {
	{ x = -22, z = -60, width = 13, depth = 11, floors = 2, state = "damaged", lit = false },
	{ x = 24, z = -64, width = 12, depth = 12, floors = 2, state = "damaged", lit = true, roof = "side" },
	{ x = 66, z = -10, width = 13, depth = 11, floors = 2, state = "intact", lit = true },
	{ x = 70, z = 58, width = 12, depth = 10, floors = 1, state = "collapsed" },
	{ x = -72, z = 6, width = 12, depth = 12, floors = 2, state = "damaged", roof = "side" },
	{ x = -58, z = 48, width = 13, depth = 11, floors = 2, state = "intact", lit = true },
	{ x = -24, z = 54, width = 12, depth = 10, floors = 2, state = "damaged", face = Vector3.new(4, G, 54) },
	{ x = 30, z = 60, width = 12, depth = 11, floors = 2, state = "intact", lit = true, face = Vector3.new(6, G, 60) },
	{ x = -26, z = 80, width = 11, depth = 10, floors = 1, state = "collapsed", face = Vector3.new(8, G, 80) },
	{ x = 36, z = 84, width = 12, depth = 10, floors = 2, state = "damaged", face = Vector3.new(9, G, 84) },
	{ x = 84, z = -44, width = 12, depth = 12, floors = 1, state = "collapsed", face = Vector3.new(60, G, -30) },
	{ x = -112, z = 18, width = 12, depth = 10, floors = 2, state = "damaged", face = Vector3.new(-112, G, -6) },
	{ x = -142, z = -30, width = 11, depth = 10, floors = 1, state = "collapsed", face = Vector3.new(-142, G, -8) },
	{ x = -84, z = -26, width = 12, depth = 10, floors = 2, state = "damaged", face = Vector3.new(-60, G, -40) },
}

local TAVERN_SIZE = Vector2.new(18, 14)
local GUILD_HALL_SIZE = Vector2.new(20, 16)

local function flattenSite(x: number, z: number, radius: number, height: number?)
	TerrainSculpt.flatten(Vector3.new(x, height or G, z), radius, T.ground, 26)
end

local function sculpt(random: Random)
	-- Place pavée, puis les emplacements (aplanis à la hauteur du village).
	TerrainSculpt.flatten(L.plaza, L.plazaRadius + 4, T.cobble, 26)
	for _, lot in LOTS do
		flattenSite(lot.x, lot.z, math.max(lot.width, lot.depth) * 0.75)
	end
	flattenSite(L.tavern.X, L.tavern.Z, 14)
	flattenSite(L.guildHall.X, L.guildHall.Z, 17)
	flattenSite(L.forge.X, L.forge.Z, 10)
	flattenSite(L.well.X, L.well.Z, 9)
	flattenSite(L.southGate.X, L.southGate.Z, 10)

	-- Rues (bandes de pavés ou de boue qui suivent le sol).
	local streets: { { points: { Vector3 }, width: number, material: Enum.Material } } = {
		{ points = { Vector3.new(0, G, 28), Vector3.new(5, G, 58), Vector3.new(10, G, 92) }, width = 9, material = T.cobble },
		{ points = { Vector3.new(-28, G, -4), Vector3.new(-80, G, -6), Vector3.new(-140, G, -8), L.westGate }, width = 8, material = T.mud },
		{ points = { Vector3.new(30, G, 6), Vector3.new(72, G, 12), Vector3.new(104, G, 18) }, width = 8, material = T.cobble },
		{ points = { Vector3.new(104, G, 18), Vector3.new(136, G, -6), L.bossArena }, width = 7, material = T.mud },
		{ points = { Vector3.new(22, G, -20), L.missionBoard, L.tavern }, width = 7, material = T.cobble },
		{ points = { Vector3.new(-24, G, -22), L.guildBoard, L.guildHall }, width = 7, material = T.cobble },
		{ points = { Vector3.new(-30, G, -28), Vector3.new(-62, G, -52), L.cemetery }, width = 6, material = T.mud },
		{ points = { Vector3.new(26, G, 20), L.forge }, width = 6, material = T.cobble },
		{ points = { Vector3.new(-26, G, 8), L.well }, width = 6, material = T.cobble },
	}
	for _, street in streets do
		TerrainSculpt.path(street.points, street.width, street.material, { random = random, widthJitter = 0.12 })
	end
	-- Herbe morte et cendre dans les terrains vagues.
	for _ = 1, 14 do
		local angle = random:NextNumber(0, 360)
		local radius = random:NextNumber(60, 110)
		local p = Kit.ringPoint(L.plaza, radius, angle)
		TerrainSculpt.patch(p, random:NextNumber(6, 12), if random:NextNumber() < 0.6 then T.grass else T.mud)
	end
end

--------------------------------------------------------------------------------
-- Place de l'Horloger
--------------------------------------------------------------------------------

local function buildPlaza(context: Context, folder: Instance, random: Random)
	local model = Kit.model(folder, "Plaza", CFrame.new(L.plaza))
	local center = L.plaza
	-- Statue de l'Horloger (cadran arrêté sur 3 h 17), tournée vers le sud (le belvédère).
	PropsSacred.statue(model, Kit.yaw(center, 180), 12, random, {
		holds = "clock",
		inscription = "À l'Horloger, qui retint l'heure",
	})
	-- Bassin sec autour du socle, bancs, lanternes aux quatre coins.
	for i = 0, 11 do
		local cf = Kit.radial(center + Vector3.new(0, 0.5, 0), 7.5, i * 30)
		Kit.part(model, cf, Vector3.new(1.2, 1.1, 4.1), Palette.stoneLight, { name = "BasinRim" })
	end
	Kit.column(model, CFrame.new(center + Vector3.new(0, -0.3, 0)), 0.5, 14.4, Palette.cobble, { decor = true, name = "BasinFloor" })
	for _, angle in { 30, 150, 210, 330 } do
		local p = Kit.ringPoint(center, 13, angle)
		Props.bench(model, Kit.facing(Vector3.new(p.X, ground(p.X, p.Z), p.Z), center), 6, Palette.oldWood)
	end
	for i, angle in { 45, 135, 225, 315 } do
		local p = Kit.ringPoint(center, 27, angle)
		Props.lanternPost(model, facingGround(p.X, p.Z, center, 0.2), { light = i ~= 4, lit = true })
	end
	-- Restes de l'incendie : chariot renversé, tonneaux, cendres, poutres.
	Props.cart(model, facingGround(-18, 22, center, 0.2), true, random)
	Props.barrel(model, onGround(-14, 26, 20, 0.1), false)
	Props.barrel(model, onGround(-12, 24, 70, 0.1), true)
	Props.ashPile(model, onGround(17, 18, 0, 0.3), 3, random)
	Props.ashPile(model, onGround(-20, -16, 0, 0.3), 2.5, random)
	Props.charredBeams(model, onGround(19, -14, 35, 0.2), 9, random)
	Props.crate(model, onGround(-6, -27, 10, 0.1), 2.6, true, random)
	Props.signPost(model, facingGround(-26, -6, center, 0.3), "Porte des Murmures  ←", random)

	-- PNJ de la place et réapparition.
	standing(context, "spawn_plaza", 0, 26, center)
	standing(context, "npc_elder", 9, 9, center)
	standing(context, "npc_bellkeeper", 5, -30, center)
end

--------------------------------------------------------------------------------
-- Maisons, taverne, forge
--------------------------------------------------------------------------------

local function buildHouses(folder: Instance, random: Random)
	local houses = Kit.folder(folder, "Houses")
	for i, lot in LOTS do
		local face = lot.face or L.plaza
		local base = facingGround(lot.x, lot.z, face, 0)
		local result = Props.house(houses, base, random, {
			width = lot.width,
			depth = lot.depth,
			floors = lot.floors,
			state = lot.state,
			lit = lot.lit,
			roof = lot.roof,
			name = "House" .. i,
		})
		-- Quelques détails devant les portes.
		if lot.state ~= "collapsed" and random:NextNumber() < 0.7 then
			Props.barrel(houses, result.door * CFrame.new(result.width / 2 - 1.5, 0, -1), random:NextNumber() < 0.3)
		end
		if lot.state == "collapsed" then
			Props.ashPile(houses, result.door * CFrame.new(0, 0, -3), 2.5, random)
		end
	end
	-- Corde à linge entre deux maisons de la rue sud, et un chariot de bois.
	Props.laundryLine(houses, Vector3.new(-17, G + 7, 46), Vector3.new(-8, G + 7, 64), random)
	Props.woodpile(houses, onGround(42, 70, 20, 0.2), random)
end

local function buildTavern(context: Context, folder: Instance, random: Random)
	local base = facingGround(L.tavern.X, L.tavern.Z, L.plaza, 0)
	local result = Props.house(folder, base, random, {
		width = TAVERN_SIZE.X,
		depth = TAVERN_SIZE.Y,
		floors = 2,
		state = "intact",
		lit = true,
		roof = "side",
		name = "Tavern",
	})
	Props.hangingSign(folder, result.door * CFrame.new(4.2, 7.6, 1.1), "Le Sablier Brisé")
	Props.hangingLantern(folder, (result.door * CFrame.new(-3.2, 7.8, 0.4)).Position, true, true)
	-- Terrasse.
	Props.tableSet(folder, result.door * CFrame.new(-5, 0, -6), random)
	Props.tableSet(folder, result.door * CFrame.new(5.5, 0, -7), random)
	Props.barrel(folder, result.door * CFrame.new(8, 0, -1.5), false)
	Props.barrel(folder, result.door * CFrame.new(9.3, 0, -2.8), false)
	local villager = (result.door * CFrame.new(2, 0, -9)).Position
	standing(context, "npc_villager_2", villager.X, villager.Z, (result.door * CFrame.new(-5, 0, -6)).Position)
end

local function buildMissionBoard(context: Context, folder: Instance, random: Random)
	local p = L.missionBoard
	local base = facingGround(p.X, p.Z, L.plaza, 0.1)
	local _, board = Props.noticeBoard(folder, base, random, "CONTRATS")
	Kit.tagInteractable(board, "board_missions")
	local side = (base * CFrame.new(5.5, 0, -1.5)).Position
	standing(context, "npc_quartermaster", side.X, side.Z, L.plaza)
	Props.crate(folder, base * CFrame.new(-5, 0, 0.5), 2.4, false, random)
end

local function buildForge(context: Context, folder: Instance, random: Random)
	local p = L.forge
	local base = facingGround(p.X, p.Z, L.plaza, 0)
	local model = Kit.model(folder, "Forge", base)
	-- Appentis ouvert : poteaux, toit à deux pans, sol de pierre.
	Kit.part(model, base * CFrame.new(0, 0.1, 0), Vector3.new(13, 0.6, 11), Palette.stoneDark, { name = "Floor" })
	for _, x in { -6, 6 } do
		for _, z in { -5, 5 } do
			Kit.part(model, base * CFrame.new(x, 4.5, z), Vector3.new(0.9, 9, 0.9), Palette.charredWood)
		end
	end
	PropsBuildings.gableRoof(model, base * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.rad(90), 0), 12, 14, 3.5, Palette.roofShingle, { damage = 0.3, random = random })
	-- Foyer de pierre au fond, cheminée, enclume, braises.
	Kit.part(model, base * CFrame.new(0, 1.6, 3.6), Vector3.new(6, 3.2, 3), Palette.brickDark, { name = "Hearth" })
	PropsBuildings.chimney(model, base * CFrame.new(0, 3.2, 4), 10, Palette.brickDark)
	Props.brazier(model, base * CFrame.new(0, 3.2, 3.4), { lit = true, light = true, scale = 0.8 })
	Props.anvil(model, base * CFrame.new(-1.5, 0.4, -1))
	Props.trough(model, base * CFrame.new(4.5, 0.4, 0) * CFrame.Angles(0, math.rad(90), 0), 4)
	Props.weaponRack(model, base * CFrame.new(-5, 0.4, 2.5) * CFrame.Angles(0, math.rad(90), 0), random)
	Props.woodpile(folder, base * CFrame.new(9, 0, 3), random)
	local smith = (base * CFrame.new(2.5, 0, -6)).Position
	standing(context, "npc_blacksmith", smith.X, smith.Z, L.plaza)
end

--------------------------------------------------------------------------------
-- Puits aux runes (et descente vers la crypte)
--------------------------------------------------------------------------------

local function buildWell(context: Context, folder: Instance, random: Random)
	local w = L.well
	local top = w.Y + WELL_MARGIN_HEIGHT
	local model = Kit.model(folder, "RuneWell", CFrame.new(w))

	-- Puits creusé jusqu'au niveau de la crypte, et couloir vers la salle (au nord).
	TerrainSculpt.carveCylinder(CFrame.new(w.X, (CRYPT_FLOOR - 1 + w.Y + 1) / 2, w.Z), (w.Y + 1) - (CRYPT_FLOOR - 1), WELL_SHAFT_RADIUS)
	TerrainSculpt.carveBox(Vector3.new(w.X - 3, CRYPT_FLOOR - 0.5, -1), Vector3.new(w.X + 3, CRYPT_FLOOR + 8, w.Z - 1))

	-- Margelle : douze pierres en anneau, un dallage tout autour.
	for i = 0, 11 do
		local cf = Kit.radial(Vector3.new(w.X, w.Y + WELL_MARGIN_HEIGHT / 2, w.Z), WELL_MARGIN_RADIUS, i * 30 + 15)
		Kit.part(model, cf, Vector3.new(1.3, WELL_MARGIN_HEIGHT, 2.5), Palette.darken(Palette.stoneLight, random:NextNumber(0.8, 1)), { name = "Margin" })
	end
	for i = 0, 15 do
		local cf = Kit.radial(Vector3.new(w.X, w.Y - 0.15, w.Z), 6.6, i * 22.5)
		Kit.part(model, cf, Vector3.new(3.4, 0.5, 2.7), Palette.cobble, { decor = true })
	end
	-- Quatre pierres runiques (éteintes), face vers l'extérieur.
	for index, angle in RUNE_ANGLES do
		local p = Kit.ringPoint(w, WELL_RUNE_RADIUS, angle)
		local outward = p + (p - w).Unit
		local base = Kit.facing(Vector3.new(p.X, w.Y - 0.3, p.Z), Vector3.new(outward.X, w.Y, outward.Z))
		local _, stone = PropsSacred.runeStone(model, base, Vector3.new(2.2, 2.4, 1.2), { lit = false })
		Kit.tagInteractable(stone, "well_rune_" .. index)
	end

	-- Escalier en colimaçon autour d'un noyau, de la margelle au fond du puits.
	local stairTop = w.Y - 0.2
	local steps = math.floor(stairTop - CRYPT_FLOOR)
	Kit.column(model, CFrame.new(w.X, CRYPT_FLOOR, w.Z), stairTop - CRYPT_FLOOR, 1.6, Palette.stoneDark, { name = "Newel" })
	for i = 0, steps - 1 do
		local y = stairTop - i - 0.4
		local cf = Kit.radial(Vector3.new(w.X, y, w.Z), 2.3, -90 + i * 30)
		Kit.part(model, cf, Vector3.new(2.8, 0.8, 2.1), Palette.stone, { name = "Step" })
	end
	Kit.part(model, CFrame.new(w.X, CRYPT_FLOOR - 0.5, w.Z), Vector3.new(8, 1, 8), Palette.basalt, { name = "ShaftFloor" })
	Kit.part(model, CFrame.new(w.X, CRYPT_FLOOR - 0.5, (w.Z - 1) / 2), Vector3.new(6, 1, w.Z + 1), Palette.basalt, { name = "Passage" })

	-- Dalle (dynamic "slide") : posée sur la margelle ; ouverte = glissée entre les runes sud et ouest.
	local coverCFrame = CFrame.new(w.X, top + 0.4, w.Z)
	local cover = Kit.model(context.dynamic, "WellCover", coverCFrame)
	local slab = Kit.part(cover, coverCFrame, Vector3.new(9.2, 0.8, 9.2), Palette.stone, { name = "Slab" })
	Kit.part(cover, coverCFrame * CFrame.new(0, 0.42, 0), Vector3.new(5, 0.06, 5), Palette.temporalCyanDim, { decor = true, name = "Seal", transparency = 0.3 })
	Kit.part(cover, coverCFrame * CFrame.new(0, 0.43, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.4, 0.07, 3.4), Palette.stoneDark, { decor = true })
	cover.PrimaryPart = slab
	Kit.dynamic(context.dynamic, cover, "well_cover")
	local openPoint = Kit.ringPoint(Vector3.new(w.X, top + 0.4, w.Z), COVER_OPEN_DISTANCE, COVER_OPEN_ANGLE)
	Kit.anchor(context.anchors, "well_cover_open", CFrame.new(openPoint))

	-- Sortie de la crypte (échelle) : à côté du puits, regard vers la place.
	local exitPoint = Kit.ringPoint(w, 10, -20)
	Kit.anchor(context.anchors, "crypt_exit_top", Kit.standing(groundPoint(exitPoint.X, exitPoint.Z), L.plaza))
	standing(context, "npc_child", w.X + 7, w.Z + 9, w)
end

--------------------------------------------------------------------------------
-- Salle des Serments, tableau des guildes, Archives
--------------------------------------------------------------------------------

local function buildGuildQuarter(context: Context, folder: Instance, random: Random)
	local hallBase = facingGround(L.guildHall.X, L.guildHall.Z, L.plaza, 0)
	local hall = Props.house(folder, hallBase, random, {
		width = GUILD_HALL_SIZE.X,
		depth = GUILD_HALL_SIZE.Y,
		floors = 2,
		state = "intact",
		lit = true,
		roof = "front",
		pitch = 1.1,
		chimney = false,
		name = "HallOfOaths",
		wallLook = Palette.stone,
	})
	-- Bannières de part et d'autre de la porte, braseros.
	for _, side in { -1, 1 } do
		Props.banner(folder, hall.door * CFrame.new(side * 5.5, 11, 0.6), 2.4, 5, Palette.bannerBlue, Palette.bronze)
		Props.brazier(folder, hall.door * CFrame.new(side * 4, 0, -2.5), { lit = true, light = side == 1, scale = 0.8 })
	end
	local master = (hall.door * CFrame.new(-2.5, 0, -5)).Position
	standing(context, "npc_guildmaster", master.X, master.Z, L.plaza)

	-- Tableau des guildes : stèle de pierre gravée de blasons.
	local p = L.guildBoard
	local boardBase = facingGround(p.X, p.Z, L.plaza, 0.2)
	local stele = Kit.model(folder, "GuildBoard", boardBase)
	Kit.part(stele, boardBase * CFrame.new(0, 0.5, 0), Vector3.new(6, 1, 2.4), Palette.stoneDark, { name = "Plinth" })
	local slab = Kit.part(stele, boardBase * CFrame.new(0, 3.9, 0), Vector3.new(5.2, 5.8, 0.9), Palette.granite, { name = "Slab" })
	for i, look in { Palette.bannerBlue, Palette.banner, Palette.bronze } do
		local x = (i - 2) * 1.6
		Kit.cylinder(stele, boardBase * CFrame.new(x, 3.4, -0.5) * CFrame.Angles(0, math.rad(90), 0), 0.12, 1.2, look, Kit.DECOR)
	end
	local title = Kit.part(stele, boardBase * CFrame.new(0, 5.9, -0.47), Vector3.new(4.6, 0.8, 0.05), Palette.stoneDark, { decor = true, name = "Title" })
	Kit.surfaceText(title, Enum.NormalId.Front, "SERMENTS", { color = Palette.colors.chalk, pixelsPerStud = 40 })
	Kit.tagInteractable(slab, "board_guild")

	-- Archives des Serments : salle de pierre adossée au fond de la Salle, porte basse sur le côté.
	local annex = hallBase * CFrame.new(0, 0, GUILD_HALL_SIZE.Y / 2 + 6.5)
	local annexModel = Kit.model(folder, "GuildArchive", annex)
	local W, D, H, t = 12, 10, 8, 1.2
	local floorY = 0.9
	local floor = annex * CFrame.new(0, floorY, 0)
	Kit.part(annexModel, annex * CFrame.new(0, (floorY - 1.5) / 2, 0), Vector3.new(W + 0.6, floorY + 1.5, D + 0.6), Palette.cobble, { name = "Plinth" })
	local door = { x0 = -1.6, x1 = 1.6, y0 = 0, y1 = 5.6, kind = "door" :: "door" }
	-- Murs : avant (côté Salle) et arrière pleins, porte sur le flanc +X (une ruelle).
	PropsBuildings.panelWall(annexModel, floor * CFrame.new(0, 0, -D / 2 + t / 2), W, H, {}, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(annexModel, floor * CFrame.new(0, 0, D / 2 - t / 2) * CFrame.Angles(0, math.pi, 0), W, H, {}, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(annexModel, floor * CFrame.new(-(W / 2 - t / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0), D - 2 * t, H, {}, Palette.stone, nil, { thickness = t })
	PropsBuildings.panelWall(annexModel, floor * CFrame.new(W / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), D - 2 * t, H, { door }, Palette.stone, nil, { thickness = t })
	Kit.part(annexModel, floor * CFrame.new(0, H + 0.4, 0), Vector3.new(W + 1, 0.8, D + 1), Palette.roofSlate, { name = "Roof" })
	Kit.part(annexModel, floor * CFrame.new(0, 0.1, 0), Vector3.new(W - 2 * t, 0.2, D - 2 * t), Palette.oldWood, Kit.DECOR)
	-- Porte cerclée de fer (l'interactable, solide : on ne passe que par la serrure).
	local doorCFrame = floor * CFrame.new(W / 2 - t / 2, 2.8, 0) * CFrame.Angles(0, math.rad(-90), 0)
	local doorPart = Kit.part(annexModel, doorCFrame, Vector3.new(3.2, 5.6, 0.5), Palette.oldWood, { name = "ArchiveDoor" })
	for _, y in { -1.6, 1.6 } do
		Kit.part(annexModel, doorCFrame * CFrame.new(0, y, -0.3), Vector3.new(3.3, 0.3, 0.1), Palette.iron, Kit.DECOR)
	end
	Kit.part(annexModel, doorCFrame * CFrame.new(1, 0, -0.32), Vector3.new(0.4, 0.6, 0.1), Palette.bronze, Kit.DECOR)
	Kit.tagInteractable(doorPart, "guild_archive_door")
	-- Intérieur : étagères, coffre, candélabre.
	PropsSacred.bookshelf(annexModel, floor * CFrame.new(-1.5, 0, D / 2 - t - 0.7) * CFrame.Angles(0, math.pi, 0), 6, 6, random)
	PropsSacred.bookshelf(annexModel, floor * CFrame.new(-(W / 2 - t - 0.7), 0, 0) * CFrame.Angles(0, math.rad(-90), 0), 5, 6, random)
	local _, chest = Props.chest(annexModel, floor * CFrame.new(-2, 0, -D / 2 + t + 1.4) * CFrame.Angles(0, math.pi, 0), Palette.oldWood)
	Kit.tagInteractable(chest, "chest_guild_archive")
	PropsSacred.candelabrum(annexModel, floor * CFrame.new(2.5, 0, 2.5), 4, { light = true })
	local insidePoint = (floor * CFrame.new(1.5, 0, 0)).Position
	Kit.anchor(context.anchors, "gate_archive_inside", Kit.standing(insidePoint, (floor * CFrame.new(-4, 0, 0)).Position))
	local outsidePoint = (floor * CFrame.new(W / 2 + 3, -floorY, 0)).Position
	Kit.anchor(context.anchors, "gate_archive_outside", Kit.standing(Vector3.new(outsidePoint.X, ground(outsidePoint.X, outsidePoint.Z), outsidePoint.Z), (floor * CFrame.new(W / 2 + 10, 0, 0)).Position))
end

--------------------------------------------------------------------------------
-- Portes du village
--------------------------------------------------------------------------------

local function buildGates(context: Context, folder: Instance, random: Random)
	-- Porte sud : arche de bois entre deux palissades.
	local s = L.southGate
	local southBase = Kit.yaw(Vector3.new(s.X, ground(s.X, s.Z) - 0.3, s.Z), 180)
	local south = Kit.model(folder, "SouthGate", southBase)
	PropsBuildings.archway(south, southBase, 9, 11, 1.4, Palette.charredWood, false)
	Props.palisade(south, (southBase * CFrame.new(-6, 0, 0)).Position, (southBase * CFrame.new(-34, 0, 4)).Position, 7, random, 0.3)
	Props.palisade(south, (southBase * CFrame.new(6, 0, 0)).Position, (southBase * CFrame.new(32, 0, 6)).Position, 7, random, 0.25)
	Props.brazier(south, southBase * CFrame.new(-7, 0, 3), { lit = true, light = true })
	standing(context, "npc_villager_1", s.X - 4, s.Z - 30, L.plaza)

	-- Porte des Murmures (ouest) : arche de pierre gothique, murs écroulés, vers la forêt.
	local g = L.westGate
	local westBase = Kit.facing(Vector3.new(g.X, ground(g.X, g.Z) - 0.3, g.Z), g + Vector3.new(-10, 0, 0))
	local west = Kit.model(folder, "WhisperGate", westBase)
	PropsBuildings.archway(west, westBase, 10, 14, 2, Palette.stone, true)
	Props.ruinedWall(west, (westBase * CFrame.new(-7, 0, 0)).Position, (westBase * CFrame.new(-26, 0, 2)).Position, 7, 1.6, random)
	Props.ruinedWall(west, (westBase * CFrame.new(7, 0, 0)).Position, (westBase * CFrame.new(28, 0, 3)).Position, 6, 1.6, random)
	Props.lanternPost(west, westBase * CFrame.new(-7.5, 0, 3) * CFrame.Angles(0, math.pi, 0), { light = true })
	Props.signPost(west, westBase * CFrame.new(8, 0, 4) * CFrame.Angles(0, math.pi, 0), "Forêt des Murmures", random)
	local wanderer = (westBase * CFrame.new(4, 0, 6)).Position
	standing(context, "npc_wanderer", wanderer.X, wanderer.Z, L.plaza)
end

--------------------------------------------------------------------------------
-- Cimetière des Oubliés
--------------------------------------------------------------------------------

local function buildCemetery(context: Context, folder: Instance, random: Random)
	local c = L.cemetery
	local model = Kit.model(folder, "Cemetery", CFrame.new(c))
	local variants: { Props.TombVariant } = { "rounded", "cross", "slab", "broken", "obelisk" }
	-- Tombes en rangées irrégulières, face au sud-est (vers le village).
	local facingPoint = Vector3.new(c.X + 60, c.Y, c.Z + 60)
	for row = 0, 4 do
		for col = 0, 5 do
			if random:NextNumber() < 0.85 then
				local x = c.X - 14 + col * 5.5 + random:NextNumber(-1, 1)
				local z = c.Z - 12 + row * 6 + random:NextNumber(-1, 1)
				if not (x < c.X - 8 and z < c.Z - 6) then -- l'angle nord-ouest est réservé au mausolée
					local variant: any = variants[random:NextInteger(1, #variants)]
					Props.tomb(model, facingGround(x, z, facingPoint, 0.4), variant, random)
					if random:NextNumber() < 0.25 then
						Props.flowers(model, facingGround(x, z + 1.4, facingPoint, 0.1), random)
					end
				end
			end
		end
	end
	-- Clôture brisée sur trois côtés, arbre mort, lanterne morte.
	local nw, ne = Vector3.new(c.X - 30, 0, c.Z - 28), Vector3.new(c.X + 22, 0, c.Z - 28)
	local se, sw = Vector3.new(c.X + 22, 0, c.Z + 22), Vector3.new(c.X - 30, 0, c.Z + 22)
	local function at(p: Vector3): Vector3
		return Vector3.new(p.X, ground(p.X, p.Z), p.Z)
	end
	Props.fence(model, at(nw), at(ne), random, { broken = 0.35 })
	Props.fence(model, at(ne), at(se), random, { broken = 0.3 })
	Props.fence(model, at(sw), at(nw), random, { broken = 0.3 })
	Props.deadTree(model, onGround(c.X + 14, c.Z - 18, 0, 0.6), 20, random, { look = Palette.deadTreeDark, lean = 18 })
	Props.deadTree(model, onGround(c.X - 24, c.Z + 14, 0, 0.6), 15, random)
	Props.lanternPost(model, facingGround(c.X + 18, c.Z + 18, c, 0.2), { lit = false })

	-- Mausolée (angle nord-ouest) fermé par le voile maudit.
	local mx, mz = c.X - 18, c.Z - 18
	local mHeight = ground(mx, mz)
	TerrainSculpt.flatten(Vector3.new(mx, mHeight, mz), 13, T.ground, 20)
	local mBase = Kit.facing(Vector3.new(mx, mHeight - 0.2, mz), Vector3.new(c.X + 10, mHeight, c.Z + 10))
	local mausoleum = PropsSacred.mausoleum(model, mBase, random, { inscription = "QVI DORMIVNT" })
	local veil = Kit.part(context.dynamic, mausoleum.doorway * CFrame.new(0, mausoleum.doorSize.Y / 2, 0), Vector3.new(mausoleum.doorSize.X, mausoleum.doorSize.Y, 0.4), Palette.curseViolet, {
		name = "CurseVeil",
		transparency = 0.35,
		collide = true,
		shadow = false,
	})
	Kit.light(veil, { color = Palette.colors.curseLight, brightness = 1.2, range = 12 })
	Kit.dynamic(context.dynamic, veil, "barrier_cemetery")
	-- Socle runique devant les marches (antimatière).
	local socleBase = mausoleum.approach * CFrame.new(2.5, 0, 0)
	local socle = Kit.model(model, "CurseSocle", socleBase)
	local socleStone = Kit.part(socle, socleBase * CFrame.new(0, 1.1, 0), Vector3.new(2, 2.2, 2), Palette.basalt, { name = "Socle" })
	Kit.part(socle, socleBase * CFrame.new(0, 2.25, 0), Vector3.new(1.4, 0.08, 1.4), Palette.curseGlyph, { decor = true, name = "Glyph" })
	Kit.tagInteractable(socleStone, "mech_barrier_cemetery")
	-- Reliquaire au fond du mausolée.
	local _, reliquary = Props.chest(model, mausoleum.interior * CFrame.new(0, 0, 3.5), Palette.bronzeDark)
	Kit.tagInteractable(reliquary, "chest_cemetery")
	Props.candles(model, mausoleum.interior * CFrame.new(-2.5, 0, 4), 4, random, false)

	-- Présence (Ombre) : petite pierre noire entre deux tombes.
	local presence = Kit.part(model, onGround(c.X + 4, c.Z - 3, 20, 0.3) * CFrame.new(0, 0.5, 0), Vector3.new(1, 1, 0.8), Palette.void, { name = "BlackStone" })
	Kit.tagInteractable(presence, "shadow_presence")

	standing(context, "npc_villager_3", c.X + 10, c.Z + 14, c)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Village.build(context: Context)
	local folder = context.zone("Village")
	local random = context.random
	sculpt(random)
	buildPlaza(context, folder, random)
	buildHouses(folder, random)
	buildTavern(context, folder, random)
	buildMissionBoard(context, folder, random)
	buildForge(context, folder, random)
	buildWell(context, folder, random)
	buildGuildQuarter(context, folder, random)
	buildGates(context, folder, random)
	buildCemetery(context, folder, random)
end

return table.freeze(Village)
