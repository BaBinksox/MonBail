--!strict
--[[
	ArrivalPath (ModuleScript, client)
	Trajectoires de la cinématique d'arrivée, VALIDÉES contre la géométrie avant d'être jouées.
	Fonctions pures : la détection d'obstacles est fournie par l'appelant (`cast`), ce qui permet de
	vérifier les mêmes trajectoires dans le simulateur, avec le vrai relief de la carte.

	Un plan (Shot) = des points de passage pour la caméra et pour le point regardé, parcourus en
	spline de Catmull-Rom (courbe douce qui passe par chaque point). Une trajectoire est jouable si :
		- chaque tronçon entre deux échantillons voisins est libre (rayon caméra -> caméra) ;
		- au-dessus de chaque échantillon, rien de solide plus haut que lui - clearance (rayon tombé
		  du ciel jusque sous la caméra) : la caméra n'est jamais dans le terrain, une montagne, un
		  toit ou un arbre, et garde une marge au-dessus du sol.
	Plan bloqué : on relève ses points de passage (RAISE_STEP, jusqu'à RAISE_TRIES fois) ; s'il l'est
	encore, il est abandonné et la cinématique passe au plan suivant par un fondu au noir.

	API :
		ArrivalPath.buildShots(context, cast): { panorama: Shot, approach: Shot }
		ArrivalPath.resolve(shot, cast): Shot?            plan jouable (éventuellement relevé), ou nil
		ArrivalPath.isClear(shot, cast): (boolean, Vector3?)  + premier point bloqué
		ArrivalPath.sample(points, alpha): Vector3
		ArrivalPath.gameplayPose(subject, lookToward, cast): CFrame  caméra de jeu derrière le personnage
	`cast(origin, direction): Vector3?` : point du premier obstacle sur ce segment, ou nil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World"):WaitForChild("RegionConfig") :: ModuleScript)

export type Cast = (origin: Vector3, direction: Vector3) -> Vector3?

export type Shot = {
	name: string,
	points: { Vector3 }, -- positions de la caméra
	targets: { Vector3 }, -- points regardés (même nombre, parcourus au même rythme)
	duration: number,
	clearance: number, -- marge minimale au-dessus de ce qui est sous la caméra
	finalClearance: number?, -- marge du dernier quart (descente vers le joueur)
	raisable: boolean, -- peut être relevé si bloqué
}

export type Context = {
	cameraAnchor: CFrame, -- ancre camera_overlook (au-dessus et derrière le belvédère)
	focus: Vector3, -- point du village visé par le serveur (la place)
	subject: Vector3, -- tête du personnage (ou centre du RootPart + 1,5)
	lookToward: Vector3, -- là où le personnage regarde (le village)
}

local SAMPLE_SPACING = 2.5 -- studs entre deux échantillons vérifiés
local MIN_SAMPLES = 24
local SKY_HEIGHT = 400 -- d'où part le rayon qui cherche ce qu'il y a au-dessus de la caméra
local RAISE_STEP = 12
local RAISE_TRIES = 4

local PANORAMA_DURATION = 10
local APPROACH_DURATION = 3.6
local GAMEPLAY_DISTANCE = 12.5
local GAMEPLAY_PITCH = 14 -- degrés
local GAMEPLAY_MIN_DISTANCE = 3
local GAMEPLAY_MARGIN = 0.8 -- recul devant un obstacle entre le personnage et la caméra

local ArrivalPath = {}

local function world(localPosition: Vector3): Vector3
	return RegionConfig.toWorld(localPosition)
end

-- Catmull-Rom uniforme, extrémités dupliquées : passe par tous les points, sans à-coups.
function ArrivalPath.sample(points: { Vector3 }, alpha: number): Vector3
	local count = #points
	if count == 1 then
		return points[1]
	end
	local scaled = math.clamp(alpha, 0, 1) * (count - 1)
	local index = math.min(math.floor(scaled) + 1, count - 1)
	local t = scaled - (index - 1)
	local p0 = points[math.max(index - 1, 1)]
	local p1 = points[index]
	local p2 = points[index + 1]
	local p3 = points[math.min(index + 2, count)]
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

local function pathLength(points: { Vector3 }): number
	local length = 0
	for index = 2, #points do
		length += (points[index] - points[index - 1]).Magnitude
	end
	return length
end

-- Vérifie la trajectoire échantillon par échantillon. Retourne aussi le premier point bloqué.
function ArrivalPath.isClear(shot: Shot, cast: Cast): (boolean, Vector3?)
	local samples = math.max(MIN_SAMPLES, math.ceil(pathLength(shot.points) * 1.15 / SAMPLE_SPACING))
	local previous: Vector3? = nil
	for step = 0, samples do
		local alpha = step / samples
		local position = ArrivalPath.sample(shot.points, alpha)
		local clearance = if alpha > 0.75 and shot.finalClearance then shot.finalClearance else shot.clearance
		-- Rien de solide au-dessus de (position - clearance) : ni terrain, ni toit, ni rocher.
		local top = Vector3.new(position.X, math.max(position.Y, 0) + SKY_HEIGHT, position.Z)
		local floor = position - Vector3.new(0, clearance, 0)
		if cast(top, floor - top) ~= nil then
			return false, position
		end
		-- Et rien entre deux échantillons voisins (murs, piliers, troncs).
		if previous and cast(previous, position - previous) ~= nil then
			return false, position
		end
		previous = position
	end
	return true, nil
end

local function raised(shot: Shot, amount: number): Shot
	local points = table.clone(shot.points)
	-- Seuls les plans « relevables » (le panorama) passent ici : on relève toute la trajectoire.
	for index = 1, #points do
		points[index] += Vector3.new(0, amount, 0)
	end
	local copy = table.clone(shot)
	copy.points = points
	return copy
end

function ArrivalPath.resolve(shot: Shot, cast: Cast): Shot?
	if ArrivalPath.isClear(shot, cast) then
		return shot
	end
	if not shot.raisable then
		return nil
	end
	for attempt = 1, RAISE_TRIES do
		local candidate = raised(shot, RAISE_STEP * attempt)
		if ArrivalPath.isClear(candidate, cast) then
			return candidate
		end
	end
	return nil
end

-- Caméra de jeu : derrière le personnage, légèrement plongeante, tournée vers lui. Rapprochée si un
-- obstacle se trouve entre le personnage et cette place (comme la caméra Roblox par défaut).
function ArrivalPath.gameplayPose(subject: Vector3, lookToward: Vector3, cast: Cast): CFrame
	local flat = Vector3.new(lookToward.X - subject.X, 0, lookToward.Z - subject.Z)
	local direction = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local pitch = math.rad(GAMEPLAY_PITCH)
	local back = (-direction * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)).Unit
	local distance = GAMEPLAY_DISTANCE
	local hit = cast(subject, back * distance)
	if hit then
		distance = math.max((hit - subject).Magnitude - GAMEPLAY_MARGIN, GAMEPLAY_MIN_DISTANCE)
	end
	return CFrame.lookAt(subject + back * distance, subject)
end

--[[
	Les deux plans de la découverte :
	1. PANORAMA : très haut derrière le belvédère, le village au loin ; lente descente en arc vers
	   l'est du village, le regard glissant de la place vers la chapelle sur sa butte et le lac de la
	   cathédrale engloutie. Tous les points sont bien au-dessus des toits et des collines.
	2. APPROCHE : depuis l'ancre camera_overlook (au-dessus et derrière le joueur, qui contemple le
	   village), descente douce jusqu'à la caméra de jeu derrière lui.
	Entre les deux : un fondu au noir (on ne fait jamais traverser la colline à la caméra).
]]
function ArrivalPath.buildShots(context: Context, cast: Cast): { panorama: Shot, approach: Shot }
	local L = RegionConfig.LAYOUT
	local overlook = world(L.overlook)
	local plaza = world(L.plaza)
	local chapel = world(L.chapel)
	local lake = world(L.lakeShore)
	local panorama: Shot = {
		name = "panorama",
		points = {
			overlook + Vector3.new(-30, 58, 30),
			overlook + Vector3.new(-8, 46, -45),
			world(Vector3.new(40, 64, 150)),
			world(Vector3.new(66, 58, 72)),
		},
		targets = {
			plaza + Vector3.new(0, 0, 20),
			plaza,
			plaza + Vector3.new(0, 6, -50),
			chapel + Vector3.new(0, 14, 0) + (lake - chapel) * 0.25,
		},
		duration = PANORAMA_DURATION,
		clearance = 14,
		raisable = true,
	}

	local finish = ArrivalPath.gameplayPose(context.subject, context.lookToward, cast)
	local start = context.cameraAnchor.Position
	local middle = start:Lerp(finish.Position, 0.5) + Vector3.new(0, 3, 0)
	local approach: Shot = {
		name = "approach",
		points = { start, middle, finish.Position },
		targets = {
			context.focus,
			context.subject:Lerp(context.focus, 0.35),
			context.subject,
		},
		duration = APPROACH_DURATION,
		clearance = 3,
		finalClearance = 1,
		raisable = false,
	}
	return { panorama = panorama, approach = approach }
end

return ArrivalPath
