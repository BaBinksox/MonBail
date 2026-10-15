-- Audit physique de la carte générée (simulation, hors Roblox).
-- Cherche ce qui peut projeter ou accrocher un Humanoid qui marche :
--   - pièces NON ancrées dans World (elles tomberaient, rouleraient, pousseraient) ;
--   - petites pièces SOLIDES INCLINÉES au ras du sol (le Humanoid tente de monter dessus et peut être
--     éjecté par la dépénétration) ;
--   - pièces solides très fines posées au sol (marche invisible qui accroche les pieds).
-- Usage : tools/sim/run.sh geometry_audit   (affiche un résumé par Model parent ; "AUDIT OK" sinon)
local mock = require("./mock")
local env = require("./bundle_out")(mock)
local WorldBuilder = env.require("ServerScriptService/Server/WorldBuild/WorldBuilder")
WorldBuilder.build({ silent = true })
local TerrainSculpt = env.require("ServerScriptService/Server/WorldBuild/TerrainSculpt")
local ORIGIN_X = 3000

local TILT_LIMIT = 12 -- degrés
local LOW_TOP = 5 -- studs au-dessus du sol : franchissable / atteignable en marchant
local SMALL = 14 -- studs : au-delà, c'est un mur, pas un caillou
local THIN = 0.45

local function tiltOf(cf)
	-- Angle entre la verticale et l'axe du part le plus proche de la verticale.
	local best = 0
	for _, v in ipairs({ cf.RightVector, cf.UpVector, cf.LookVector }) do
		best = math.max(best, math.abs(v.Y))
	end
	return math.deg(math.acos(math.clamp(best, -1, 1)))
end

local function topOf(part)
	local half = part.Size / 2
	local top = -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				top = math.max(top, (part.CFrame * mock.Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y)
			end
		end
	end
	return top
end

local function ownerName(part)
	local node = part.Parent
	while node and node.ClassName ~= "Model" and node.Name ~= "Static" do
		node = node.Parent
	end
	return if node and node.ClassName == "Model" then node.Name else "(dossier)"
end

local world = mock.workspace:FindFirstChild("World")
local static = world:FindFirstChild("Static")
local unanchored, tilted, thin = {}, {}, {}
local totalCollide = 0
for _, d in ipairs(world:GetDescendants()) do
	if d:IsA("BasePart") then
		if d.Anchored ~= true then
			table.insert(unanchored, d)
		end
		if d.CanCollide and d.Transparency < 1 and d:IsDescendantOf(static) then
			totalCollide += 1
			local p = d.Position
			local ground = TerrainSculpt.heightAt(p.X - ORIGIN_X, p.Z)
			local top = topOf(d) - ground
			local size = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			local tilt = tiltOf(d.CFrame)
			if tilt > TILT_LIMIT and top < LOW_TOP and top > 0.2 and size < SMALL then
				local name = ownerName(d)
				tilted[name] = (tilted[name] or 0) + 1
			end
			if math.min(d.Size.X, d.Size.Y, d.Size.Z) < THIN and top > 0.1 and top < 1.6 and size < SMALL then
				local name = ownerName(d)
				thin[name] = (thin[name] or 0) + 1
			end
		end
	end
end

local function report(title, map)
	local names, count = {}, 0
	for name, n in pairs(map) do
		table.insert(names, name .. " x" .. n)
		count += n
	end
	table.sort(names)
	print(string.format("%s : %d", title, count))
	if count > 0 then
		print("    " .. table.concat(names, ", "))
	end
	return count
end

print(string.format("Pièces solides visibles de la carte : %d", totalCollide))
print(string.format("Pièces non ancrées : %d", #unanchored))
for i = 1, math.min(5, #unanchored) do
	print("    " .. unanchored[i]:GetFullName())
end
local a = report("Petites pièces solides inclinées au ras du sol", tilted)
local b = report("Pièces solides très fines au sol", thin)
print(if #unanchored + a + b == 0 then "AUDIT OK" else "AUDIT : " .. (#unanchored + a + b) .. " risque(s)")
