--!strict
--[[
	Crypt (zone)
	La Crypte des Veilleurs, sous le village : la salle du gardien (≈ 40 x 40, hauteur 16), creusée
	dans la roche à LAYOUT.cryptHall. On y descend par le puits aux runes (escalier et couloir posés
	par Village) ; on en remonte par l'échelle de fer (téléportation vers crypt_exit_top).

	Contrat posé ici :
		ancres        enemy_crypt_guardian (Veilleur de Cendre), volume_crypt_hall
		interactables crypt_relic (battant de la cloche, sur l'autel), crypt_exit (échelle)
	Éclairage : flammes froides blanc acier (pas le cyan du temps), quatre appliques budgétées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local BuildContext = require(script.Parent.BuildContext)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local PropsBuildings = require(script.Parent.PropsBuildings)
local PropsSacred = require(script.Parent.PropsSacred)
local Props = require(script.Parent.Props)
local TerrainSculpt = require(script.Parent.TerrainSculpt)

type Context = BuildContext.Context

local L = RegionConfig.LAYOUT

local HALL_SIZE = 40
local HALL_HEIGHT = 16
local WALL_THICKNESS = 1.6
local PASSAGE_WIDTH = 6 -- ouverture du couloir du puits dans le mur sud (aligné sur le puits)

local Crypt = {}

function Crypt.build(context: Context)
	local folder = context.zone("Crypt")
	local random = context.random
	local h = L.cryptHall
	local floorY = h.Y
	local half = HALL_SIZE / 2
	local t = WALL_THICKNESS
	local base = CFrame.new(h.X, floorY, h.Z)
	local model = Kit.model(folder, "WatchersHall", base)

	-- Cavité (creusée en dernier dans le terrain du village : Crypt est construit après Village).
	TerrainSculpt.carveBox(
		Vector3.new(h.X - half - 1, floorY - 1, h.Z - half - 1),
		Vector3.new(h.X + half + 1, floorY + HALL_HEIGHT + 1, h.Z + half + 1)
	)

	-- Sol, plafond voûté (dalles + arcs doubleaux), murs de basalte.
	Kit.part(model, base * CFrame.new(0, -0.5, 0), Vector3.new(HALL_SIZE + 2, 1, HALL_SIZE + 2), Palette.basalt, { name = "Floor" })
	Kit.part(model, base * CFrame.new(0, HALL_HEIGHT + 0.5, 0), Vector3.new(HALL_SIZE + 2, 1, HALL_SIZE + 2), Palette.stoneDark, { name = "Ceiling" })
	local passageX = L.well.X - h.X
	local passage = { x0 = passageX - PASSAGE_WIDTH / 2, x1 = passageX + PASSAGE_WIDTH / 2, y0 = 0, y1 = 8, kind = "door" :: "door" }
	-- Mur sud (vers le puits, +Z), percé du couloir ; repère retourné : X local = -X du monde.
	local southFrame = base * CFrame.new(0, 0, half - t / 2) * CFrame.Angles(0, math.pi, 0)
	local mirrored = { x0 = -passage.x1, x1 = -passage.x0, y0 = passage.y0, y1 = passage.y1, kind = passage.kind }
	PropsBuildings.panelWall(model, southFrame, HALL_SIZE, HALL_HEIGHT, { mirrored }, Palette.basalt, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(0, 0, -half + t / 2), HALL_SIZE, HALL_HEIGHT, {}, Palette.basalt, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(-(half - t / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0), HALL_SIZE - 2 * t, HALL_HEIGHT, {}, Palette.basalt, nil, { thickness = t })
	PropsBuildings.panelWall(model, base * CFrame.new(half - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), HALL_SIZE - 2 * t, HALL_HEIGHT, {}, Palette.basalt, nil, { thickness = t })
	for i = -1, 1 do
		local z = i * 12
		Kit.part(model, base * CFrame.new(0, HALL_HEIGHT - 0.8, z), Vector3.new(HALL_SIZE - 2 * t, 1.6, 1.4), Palette.stone, { decor = true, name = "Rib" })
	end

	-- Deux rangées de piliers ; entre eux, des sarcophages (gisants des Veilleurs).
	for _, x in { -11, 11 } do
		for _, z in { -12, 0, 12 } do
			PropsBuildings.pillar(model, base * CFrame.new(x, 0, z), HALL_HEIGHT, 2.4, Palette.stone)
		end
	end
	for i, z in { -6, 6 } do
		for _, x in { -16, 16 } do
			PropsSacred.sarcophagus(model, base * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(90), 0), random, { open = i == 2 and x > 0 })
		end
	end
	PropsSacred.boneHeap(model, base * CFrame.new(-6, 0, 14), 2.5, random)
	PropsSacred.boneHeap(model, base * CFrame.new(8, 0, -4), 1.6, random)
	Props.rubble(model, base * CFrame.new(-15, 0, 15), 3, 6, random)

	-- Appliques à flammes froides sur les murs est et ouest.
	for _, side in { -1, 1 } do
		for _, z in { -10, 10 } do
			local mount = base * CFrame.new(side * (half - t - 0.1), 7, z) * CFrame.Angles(0, math.rad(side * 90), 0)
			PropsSacred.wallSconce(model, mount, { light = true, cold = true, range = 22 })
		end
	end

	-- Autel du fond (nord) : le battant de la cloche, rivé par la cendre tant que le Veilleur veille.
	local altarBase = base * CFrame.new(0, 0, -half + 5)
	local _, altarTop = PropsSacred.altar(model, altarBase, 7, 3.5)
	local topY = PropsSacred.ALTAR_HEIGHT
	local relicModel = Kit.model(folder, "BellClapper", altarBase * CFrame.new(0, topY, 0))
	local relic = Kit.part(relicModel, altarBase * CFrame.new(0, topY + 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(3.4, 0.7, 0.7), Palette.bronze, { name = "Clapper" })
	Kit.ball(relicModel, (altarBase * CFrame.new(1.9, topY + 0.6, 0)).Position, 1.3, Palette.bronze, Kit.DECOR)
	Kit.tagInteractable(relic, "crypt_relic")
	PropsSacred.candelabrum(model, altarBase * CFrame.new(-5, 0, 0.5), 4, { cold = true })
	PropsSacred.candelabrum(model, altarBase * CFrame.new(5, 0, 0.5), 4, { cold = true })
	Props.ashPile(model, altarBase * CFrame.new(0, 0, 3), 2.5, random)
	local _ = altarTop

	-- Échelle de fer contre le mur sud, à côté du couloir (on regarde vers la salle en la prenant).
	local ladderFoot = base * CFrame.new(passageX + PASSAGE_WIDTH / 2 + 4, 0, half - t - 0.2)
	local _, rail = PropsSacred.ladder(model, ladderFoot, 12)
	Kit.tagInteractable(rail, "crypt_exit")

	-- Le Veilleur se tient au centre, face à l'entrée ; volume de la rencontre = toute la salle.
	Kit.anchor(context.anchors, "enemy_crypt_guardian", Kit.standing(Vector3.new(h.X, floorY, h.Z - 4), Vector3.new(h.X, floorY, h.Z + half)))
	Kit.anchor(context.anchors, "volume_crypt_hall", CFrame.new(h.X, floorY + HALL_HEIGHT / 2, h.Z), Vector3.new(HALL_SIZE, HALL_HEIGHT, HALL_SIZE))
end

return table.freeze(Crypt)
