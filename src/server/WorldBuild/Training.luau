--!strict
--[[
	Training (zone)
	À l'est du village : la cour d'entraînement de Bran (mannequins, râteliers) et, plus loin, le
	Cercle du Gardien, anneau de piliers brisés où se tient le boss d'entraînement (rencontre à
	rembobinage, voir EncounterService / TimeLoopService).

	Contrat posé ici :
		ancres  enemy_training_dummy_1..3 (mannequins combattants, créés par EnemyService),
		        npc_trainer, boss_training, volume_boss_arena
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

local YARD_HALF = Vector2.new(20, 15) -- demi-dimensions de la cour (X, Z)
local ARENA_PILLARS = 12
local ARENA_HEIGHT = 30 -- hauteur du volume de la rencontre

local Training = {}

local function ground(x: number, z: number): number
	return TerrainSculpt.heightAt(x, z)
end

local function buildYard(context: Context, folder: Instance, random: Random)
	local y = L.trainingYard
	TerrainSculpt.flatten(y, 24, T.mud, 20)
	local model = Kit.model(folder, "TrainingYard", CFrame.new(y))
	local g = y.Y
	-- Palissade basse sur trois côtés (l'ouest, côté village, reste ouvert).
	local nw = Vector3.new(y.X - YARD_HALF.X, g, y.Z - YARD_HALF.Y)
	local ne = Vector3.new(y.X + YARD_HALF.X, g, y.Z - YARD_HALF.Y)
	local se = Vector3.new(y.X + YARD_HALF.X, g, y.Z + YARD_HALF.Y)
	local sw = Vector3.new(y.X - YARD_HALF.X, g, y.Z + YARD_HALF.Y)
	Props.fence(model, nw, ne, random, { broken = 0.15 })
	Props.fence(model, ne, se, random, { broken = 0.15 })
	Props.fence(model, se, sw, random, { broken = 0.15 })
	-- Râteliers, mannequins décoratifs brisés, bancs, brasero.
	Props.weaponRack(model, Kit.yaw(Vector3.new(y.X + YARD_HALF.X - 2, g, y.Z - 4), -90), random)
	Props.weaponRack(model, Kit.yaw(Vector3.new(y.X + YARD_HALF.X - 2, g, y.Z + 4), -90), random)
	Props.trainingDummy(model, Kit.yaw(Vector3.new(y.X + 12, g, y.Z + 10), 200), random, true)
	Props.trainingDummy(model, Kit.yaw(Vector3.new(y.X - 14, g, y.Z + 11), 160), random, true)
	Props.bench(model, Kit.yaw(Vector3.new(y.X - 6, g, y.Z + YARD_HALF.Y - 2), 0), 6, Palette.oldWood)
	Props.brazier(model, Kit.yaw(Vector3.new(y.X - YARD_HALF.X + 2, g, y.Z - YARD_HALF.Y + 2), 0), { lit = true, light = true })
	Props.crate(model, Kit.yaw(Vector3.new(y.X + 16, g, y.Z + 12), 15), 2.4, false, random)
	Props.signPost(model, Kit.yaw(Vector3.new(y.X - YARD_HALF.X - 2, g, y.Z + 6), 90), "Cour d'entraînement", random)

	-- Mannequins combattants (ancres) : alignés au nord de la cour, tournés vers le sud.
	local facing = Vector3.new(y.X, g, y.Z + 20)
	for i, dx in { -8, 0, 8 } do
		Kit.anchor(context.anchors, "enemy_training_dummy_" .. i, Kit.standing(Vector3.new(y.X + dx, g, y.Z - 6), facing))
	end
	Kit.anchor(context.anchors, "npc_trainer", Kit.standing(Vector3.new(y.X - 4, g, y.Z + 6), Vector3.new(y.X, g, y.Z - 6)))
end

local function buildArena(context: Context, folder: Instance, random: Random)
	local a = L.bossArena
	local r = L.bossArenaRadius
	TerrainSculpt.flatten(a, r + 6, T.slate, 30)
	local model = Kit.model(folder, "GuardianCircle", CFrame.new(a))
	local floorTop = a.Y + 0.3
	-- Dallage de basalte, anneau gravé (cyan éteint : l'anomalie du temps s'y réveille), rosace.
	Kit.column(model, CFrame.new(a.X, a.Y - 0.6, a.Z), 0.9, r * 2 - 2, Palette.basalt, { name = "Floor" })
	Kit.column(model, CFrame.new(a.X, floorTop - 0.01, a.Z), 0.05, r * 1.2, Palette.temporalCyanDim, { decor = true, transparency = 0.5, name = "TimeRing" })
	Kit.column(model, CFrame.new(a.X, floorTop, a.Z), 0.06, r * 1.2 - 1.2, Palette.basalt, { decor = true, name = "TimeRingInner" })
	for i = 0, 7 do
		local cf = Kit.radial(Vector3.new(a.X, floorTop + 0.02, a.Z), r * 0.32, i * 45)
		Kit.part(model, cf, Vector3.new(r * 0.5, 0.04, 0.5), Palette.temporalCyanDim, { decor = true, transparency = 0.4, name = "Spoke" })
	end
	-- Piliers brisés en anneau (l'entrée, à l'ouest, reste dégagée).
	for i = 0, ARENA_PILLARS - 1 do
		local angle = i * (360 / ARENA_PILLARS)
		if math.abs(angle - 180) > 20 then
			local p = Kit.ringPoint(a, r - 1, angle)
			Props.brokenPillar(model, Kit.yaw(Vector3.new(p.X, ground(p.X, p.Z) - 0.3, p.Z), random:NextNumber(0, 360)), random:NextNumber(6, 13), 3, random, Palette.basalt)
		end
	end
	Props.rubble(model, CFrame.new(a.X + 10, floorTop, a.Z - 12), 5, 8, random, Palette.basalt)
	Props.rubble(model, CFrame.new(a.X - 14, floorTop, a.Z + 9), 4, 6, random, Palette.basalt)
	for _, angle in { 150, 210 } do
		local p = Kit.ringPoint(a, r + 3, angle)
		Props.brazier(model, Kit.yaw(Vector3.new(p.X, ground(p.X, p.Z), p.Z), 0), { lit = true, light = angle == 150, stone = true })
	end

	-- Boss au centre, tourné vers l'entrée (ouest) ; volume = cylindre du cercle (boîte englobante).
	Kit.anchor(context.anchors, "boss_training", Kit.standing(Vector3.new(a.X, floorTop, a.Z), Vector3.new(a.X - r, floorTop, a.Z)))
	Kit.anchor(context.anchors, "volume_boss_arena", CFrame.new(a.X, a.Y + ARENA_HEIGHT / 2, a.Z), Vector3.new(r * 2, ARENA_HEIGHT, r * 2))
end

function Training.build(context: Context)
	local folder = context.zone("Training")
	local random = context.random
	buildYard(context, folder, random)
	buildArena(context, folder, random)
end

return table.freeze(Training)
