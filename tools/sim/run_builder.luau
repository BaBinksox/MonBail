-- Exécute WorldBuilder.build() dans la simulation, vérifie le contrat (ancres, interactables,
-- dynamics, trajets d'échos) et exporte la scène en JSON (ligne "JSON ...") pour render.py.
local mock = require("./mock")
local loader = require("./bundle_out")
local env = loader(mock)

local okBuild, buildError = pcall(function()
	local WorldBuilder = env.require("ServerScriptService/Server/WorldBuild/WorldBuilder")
	WorldBuilder.build({ silent = true })
end)
if not okBuild then
	print("REPORT ERREUR DE CONSTRUCTION : " .. tostring(buildError))
end

local RegionConfig = env.require("ReplicatedStorage/Shared/World/RegionConfig")
local MechanismConfig = env.require("ReplicatedStorage/Shared/World/MechanismConfig")
local EchoConfig = env.require("ReplicatedStorage/Shared/World/EchoConfig")
local workspace = mock.workspace
local world = workspace:FindFirstChild("World")

local function report(s) print("REPORT " .. s) end

-- Encodeur JSON minimal
local function encode(v)
	local t = type(v)
	if t == "nil" then return "null"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return string.format("%.4g", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"'
	elseif t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__type == "Vector3" then return string.format("[%.3f,%.3f,%.3f]", v.X, v.Y, v.Z) end
		if mt and mt.__type == "Color3" then return string.format("[%.3f,%.3f,%.3f]", v.R, v.G, v.B) end
		if mt and mt.__type == "EnumItem" then return '"' .. v.Name .. '"' end
		if mt and mt.__type == "CFrame" then
			local r = v.r
			return string.format("{\"p\":[%.3f,%.3f,%.3f],\"r\":[%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f]}", v.p.X, v.p.Y, v.p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		end
		if mt and mt.__type then return '"' .. mt.__type .. '"' end
		if #v > 0 or next(v) == nil then
			local out = {}
			for _, x in ipairs(v) do table.insert(out, encode(x)) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local out = {}
		for k, x in pairs(v) do table.insert(out, encode(tostring(k)) .. ":" .. encode(x)) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

if world == nil then
	report("ÉCHEC : Workspace.World n'existe pas après build()")
	return
end

-- Contrat
local anchorsFound, interactablesFound, dynamicsFound = {}, {}, {}
local partCount, lightCount, shadowLights = 0, 0, 0
local parts = {}
for _, d in ipairs(world:GetDescendants()) do
	if d:IsA("BasePart") then
		partCount += 1
		local a = d:GetAttribute(RegionConfig.ANCHOR_ATTRIBUTE)
		if a and d:HasTag(RegionConfig.ANCHOR_TAG) then anchorsFound[a] = (anchorsFound[a] or 0) + 1 end
		table.insert(parts, {
			n = d.Name, c = d.ClassName, s = d.Size, cf = d.CFrame, col = d.Color, m = d.Material,
			t = d.Transparency, sh = d.Shape, cc = d.CanCollide,
			tag = (#d:GetTags() > 0) and table.concat(d:GetTags(), ",") or nil,
			a = a,
			i = d:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE),
			dy = d:GetAttribute(MechanismConfig.DYNAMIC_ATTRIBUTE),
		})
	end
	if d:IsA("Light") then
		lightCount += 1
		if d.Shadows then shadowLights += 1 end
	end
	local iid = d:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE)
	if iid and d:HasTag(RegionConfig.INTERACTABLE_TAG) then interactablesFound[iid] = (interactablesFound[iid] or 0) + 1 end
	local did = d:GetAttribute(MechanismConfig.DYNAMIC_ATTRIBUTE)
	if did then dynamicsFound[did] = (dynamicsFound[did] or 0) + 1 end
end

local missing = {}
local function need(kind, id, found)
	if not found[id] then table.insert(missing, kind .. ":" .. id)
	elseif found[id] > 1 then table.insert(missing, "DOUBLON " .. kind .. ":" .. id .. " x" .. found[id]) end
end
for id in pairs(RegionConfig.ANCHORS) do need("ancre", id, anchorsFound) end
for id in pairs(MechanismConfig.EXTRA_ANCHORS) do need("ancre", id, anchorsFound) end
for id in pairs(MechanismConfig.INTERACTABLES) do
	if id ~= "chest_antimatter" then need("interactable", id, interactablesFound) end
end
for id in pairs(MechanismConfig.DYNAMICS) do need("dynamic", id, dynamicsFound) end
local echoPaths = world:FindFirstChild(RegionConfig.ECHO_PATHS_FOLDER_NAME)
for id, echo in pairs(EchoConfig.ECHOES) do
	local folder = echoPaths and echoPaths:FindFirstChild(echo.pathFolder)
	if folder == nil then
		table.insert(missing, "trajet d'écho:" .. id)
	else
		for i = 1, echo.pointCount do
			if folder:FindFirstChild(tostring(i)) == nil then table.insert(missing, "point d'écho:" .. id .. "/" .. i) end
		end
	end
end
for _, folderName in ipairs({ RegionConfig.STATIC_FOLDER_NAME, RegionConfig.ANCHORS_FOLDER_NAME, RegionConfig.DYNAMIC_FOLDER_NAME, RegionConfig.ECHO_PATHS_FOLDER_NAME }) do
	if world:FindFirstChild(folderName) == nil then table.insert(missing, "dossier:World." .. folderName) end
end

table.sort(missing)
report(string.format("Parts : %d | lumières : %d (dont %d avec ombres) | opérations de terrain : %d", partCount, lightCount, shadowLights, #mock.terrainOps))
if #missing == 0 then
	report("CONTRAT OK : toutes les ancres, interactables, dynamics et trajets d'échos sont présents (sans doublon).")
else
	report("CONTRAT INCOMPLET (" .. #missing .. ") : " .. table.concat(missing, " ; "))
end

local terrain = {}
for _, op in ipairs(mock.terrainOps) do
	table.insert(terrain, { k = op.kind, a = op.args })
end

-- Idempotence : une deuxième construction ne doit pas dupliquer le monde.
local countBefore = #world:GetDescendants()
local okSecond = pcall(function()
	env.require("ServerScriptService/Server/WorldBuild/WorldBuilder").build({ silent = true })
end)
local worlds = 0
for _, ch in ipairs(workspace:GetChildren()) do if ch.Name == RegionConfig.WORLD_FOLDER_NAME then worlds += 1 end end
local world2 = workspace:FindFirstChild("World")
report(string.format("Idempotence : 2e build %s, %d dossier(s) World, descendants %d -> %d", okSecond and "OK" or "EN ÉCHEC", worlds, countBefore, world2 and #world2:GetDescendants() or -1))

print("JSON " .. encode({ parts = parts, terrain = terrain, origin = RegionConfig.ORIGIN }))
