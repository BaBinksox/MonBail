-- Non-régression des deux défauts vus dans Roblox Studio (simulation, hors Roblox) :
--   1. la caméra de la cinématique d'arrivée traversait le sol / le décor ;
--   2. les trois teints les plus clairs étaient surexposés dans le créateur.
-- Les trajectoires sont vérifiées contre la carte générée : relief réel (TerrainSculpt) et boîtes de
-- toutes les pièces visibles ou solides, indépendamment des raycasts utilisés par le jeu.
local H = require("./helpers")()
local runtime, mock = H.runtime, H.mock
local V3 = mock.Vector3
local ORIGIN_X = 3000

H.boot()
local TerrainSculpt = H.server("WorldBuild/TerrainSculpt")
runtime.realRaycast = true
runtime.terrainHeight = function(x, z)
	return TerrainSculpt.heightAt(x - ORIGIN_X, z)
end
local ArrivalPath = H.env.require("StarterPlayer/StarterPlayerScripts/Client/World/ArrivalPath")
local RaceConfig = H.shared("Avatar/RaceConfig")
local WorldAnchors = H.server("World/WorldAnchors")
local RegionConfig = H.shared("World/RegionConfig")

-- Même détection d'obstacles que la cinématique (ArrivalController.castObstacle).
local function cast(origin, direction)
	local exclude = {}
	for _, player in ipairs(mock.game:GetService("Players"):GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = mock.RaycastParams.new()
	params.FilterType = mock.Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, 8 do
		params.FilterDescendantsInstances = exclude
		local result = mock.workspace:Raycast(origin, direction, params)
		if result == nil then
			return nil
		end
		local hit = result.Instance
		if hit:IsA("BasePart") and hit.Transparency >= 0.95 and not hit.CanCollide then
			table.insert(exclude, hit)
		else
			return result.Position
		end
	end
	return nil
end

-- Oracle : pièces du décor dans lesquelles la caméra ne doit jamais entrer.
local solids = {}
for _, d in ipairs(mock.workspace:FindFirstChild("World"):GetDescendants()) do
	if d:IsA("BasePart") and (d.CanCollide or d.Transparency < 0.95) then
		table.insert(solids, d)
	end
end
local function insidePart(point)
	for _, part in ipairs(solids) do
		local p = part.CFrame:Inverse() * point
		local h = part.Size / 2
		if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then
			return part
		end
	end
	return nil
end
local function audit(shot, groundMargin)
	local worstGap, offender = math.huge, nil
	for step = 0, 400 do
		local point = ArrivalPath.sample(shot.points, step / 400)
		local gap = point.Y - runtime.terrainHeight(point.X, point.Z)
		if gap < worstGap then
			worstGap = gap
		end
		local part = insidePart(point)
		if part and offender == nil then
			offender = part:GetFullName()
		end
	end
	return worstGap >= groundMargin, worstGap, offender
end

print("== Diagnostic : l'ancien travelling finissait sous la terrasse")
local anchor = WorldAnchors.getCFrame("camera_overlook")
local focus = RegionConfig.toWorld(RegionConfig.LAYOUT.plaza)
do
	local start = anchor.Position
	local toFocus = focus - start
	local forward = toFocus.Unit
	local right = forward:Cross(V3.new(0, 1, 0)).Unit
	local d = toFocus.Magnitude
	local finish = start + forward * math.min(d * 0.12, 18) + right * math.min(d * 0.06, 14) - V3.new(0, math.min(d * 0.03, 8), 0)
	local gap = finish.Y - runtime.terrainHeight(finish.X, finish.Z)
	H.check(string.format("ancienne fin de travelling : %.1f studs au-dessus du sol (défaut reproduit)", gap), gap < 1)
end

for _, raceId in ipairs({ "human", "elf", "dwarf" }) do
	print("== Cinématique, " .. RaceConfig.getById(raceId).name)
	local raceIndex = RaceConfig.indexOf(raceId)
	local player = runtime.addPlayer("Arrivée_" .. raceId, 9500 + raceIndex)
	runtime.spawnCharacter(player)
	H.advance(3)
	H.shared("Avatar/AvatarRemotes").ApplyAvatar.OnServerEvent:Fire(player, H.selection(1, raceIndex, 1))
	H.advance(6)
	local head = player.Character:FindFirstChild("Head")
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	local rootBefore = root.Position
	local context = { cameraAnchor = anchor, focus = focus, subject = head.Position, lookToward = focus }
	local shots = ArrivalPath.buildShots(context, cast)
	local panorama = ArrivalPath.resolve(shots.panorama, cast)
	local approach = ArrivalPath.resolve(shots.approach, cast)
	H.check("panorama jouable (validé par raycasts)", panorama ~= nil)
	H.check("approche du personnage jouable", approach ~= nil)
	if panorama then
		local ok, gap, offender = audit(panorama, 10)
		H.check(string.format("panorama : toujours ≥ 10 studs au-dessus du relief (min %.1f)", gap), ok)
		H.check("panorama : n'entre dans aucune pièce du décor", offender == nil, offender)
		local first, last = panorama.points[1], panorama.points[#panorama.points]
		H.check("panorama : part des hauteurs du belvédère et finit au-dessus du village", first.Y > last.Y - 30 and last.Z - 0 < first.Z)
	end
	if approach then
		local ok, gap, offender = audit(approach, 1)
		H.check(string.format("approche : jamais sous le sol (min %.1f studs)", gap), ok)
		H.check("approche : n'entre dans aucune pièce du décor", offender == nil, offender)
		local final = approach.points[#approach.points]
		local distance = (final - head.Position).Magnitude
		H.check(string.format("approche : finit derrière le personnage (%.1f studs de sa tête)", distance), distance > 2.5 and distance < 13.5)
		H.check("approche : finit en regardant le personnage", (approach.targets[#approach.targets] - head.Position).Magnitude < 1e-3)
	end
	H.check("le personnage n'est pas déplacé par la cinématique", (root.Position - rootBefore).Magnitude < 1e-6)
	H.leave(player)
end

print("== Repli : trajectoire obstruée")
local wall = function()
	return V3.new(0, 0, 0) -- tout est bloqué
end
H.check("plan bloqué partout : abandonné (fondu à la place)", ArrivalPath.resolve(ArrivalPath.buildShots({ cameraAnchor = anchor, focus = focus, subject = anchor.Position, lookToward = focus }, cast).panorama, wall) == nil)
local low = ArrivalPath.buildShots({ cameraAnchor = anchor, focus = focus, subject = anchor.Position, lookToward = focus }, cast).panorama
local lowered = table.clone(low)
lowered.points = {}
for i, p in ipairs(low.points) do
	lowered.points[i] = V3.new(p.X, runtime.terrainHeight(p.X, p.Z) + 2, p.Z)
end
local resolved = ArrivalPath.resolve(lowered, cast)
H.check("plan trop bas : relevé jusqu'à être dégagé", resolved ~= nil and resolved.points[1].Y > lowered.points[1].Y)

print("== Teints clairs (créateur)")
local AvatarConfig = H.shared("Avatar/AvatarConfig")
local Camera = H.env.require("StarterPlayer/StarterPlayerScripts/Client/AvatarCreator/AvatarCreatorCamera")
local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end
local lightest = 0
for _, id in ipairs({ "porcelain", "fair", "rosy" }) do
	for _, tone in ipairs(AvatarConfig.SKIN_TONES) do
		if tone.id == id then
			lightest = math.max(lightest, luminance(tone.color))
			H.check(string.format("%s : luminance %.2f ≤ 0,80", tone.name, luminance(tone.color)), luminance(tone.color) <= 0.80)
			H.check(tone.name .. " : lumière de studio adoucie", Camera.skinLightFactor(tone.color) < 0.9)
		end
	end
end
-- Teints moyens, foncés et surnaturels : rendu inchangé (même couleur, même lumière).
local UNCHANGED = {
	olive = { 198, 160, 118 }, golden = { 204, 150, 104 }, tan = { 176, 124, 86 }, bronze = { 146, 98, 66 },
	umber = { 112, 74, 50 }, deep = { 78, 52, 38 }, ashen = { 158, 156, 162 }, dusk = { 118, 122, 150 },
}
for _, tone in ipairs(AvatarConfig.SKIN_TONES) do
	local rgb = UNCHANGED[tone.id]
	if rgb then
		local same = math.abs(tone.color.R * 255 - rgb[1]) < 0.5 and math.abs(tone.color.G * 255 - rgb[2]) < 0.5 and math.abs(tone.color.B * 255 - rgb[3]) < 0.5
		H.check(tone.name .. " : couleur et lumière inchangées", same and Camera.skinLightFactor(tone.color) == 1)
	end
end
H.check("les teints restent ordonnés du plus clair au plus foncé", lightest > luminance(AvatarConfig.SKIN_TONES[5].color))

H.noNewErrors("cinématique et teints sans erreur")
H.printWarnings()
H.finish()
