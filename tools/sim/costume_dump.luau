-- Exporte, pour le rendu de contrôle (costume_render.py), un mannequin R15 habillé de chaque tenue
-- fabriquée : une ligne "FIG {json}" par figure (parties du corps + pièces du costume).
-- Les parties du corps sont des blocs aux dimensions R15 standard (les corps Roblox réels sont
-- arrondis) et la chevelure est une calotte schématique : c'est un contrôle de proportions et de
-- placement, pas un rendu final.
local mock = require("./mock")
local runtime = require("./runtime")(mock)
local env = require("./bundle_out")(mock)
local V3, CF = mock.Vector3, mock.CFrame
local _ = runtime

local GarmentLibrary = env.require("ReplicatedStorage/Shared/Avatar/GarmentLibrary")
local RaceConfig = env.require("ReplicatedStorage/Shared/Avatar/RaceConfig")
local CostumeBuilder = env.require("ServerScriptService/Server/Avatar/CostumeBuilder")

local SKIN = mock.Color3.fromRGB(204, 150, 104)
local HAIR = mock.Color3.fromRGB(70, 48, 34)

local function mannequin(h, w, skin)
	local model = mock.Instance.new("Model")
	local layout = {
		{ "LeftFoot", V3.new(1, 0.3, 1), V3.new(-0.5, 0.15, 0) },
		{ "RightFoot", V3.new(1, 0.3, 1), V3.new(0.5, 0.15, 0) },
		{ "LeftLowerLeg", V3.new(1, 1.2, 1), V3.new(-0.5, 0.9, 0) },
		{ "RightLowerLeg", V3.new(1, 1.2, 1), V3.new(0.5, 0.9, 0) },
		{ "LeftUpperLeg", V3.new(1, 1.2, 1), V3.new(-0.5, 2.1, 0) },
		{ "RightUpperLeg", V3.new(1, 1.2, 1), V3.new(0.5, 2.1, 0) },
		{ "LowerTorso", V3.new(2, 0.4, 1), V3.new(0, 2.9, 0) },
		{ "UpperTorso", V3.new(2, 1.6, 1), V3.new(0, 3.9, 0) },
		{ "LeftUpperArm", V3.new(1, 1.2, 1), V3.new(-1.5, 4.1, 0) },
		{ "RightUpperArm", V3.new(1, 1.2, 1), V3.new(1.5, 4.1, 0) },
		{ "LeftLowerArm", V3.new(1, 1.1, 1), V3.new(-1.5, 2.95, 0) },
		{ "RightLowerArm", V3.new(1, 1.1, 1), V3.new(1.5, 2.95, 0) },
		{ "LeftHand", V3.new(1, 0.3, 1), V3.new(-1.5, 2.25, 0) },
		{ "RightHand", V3.new(1, 0.3, 1), V3.new(1.5, 2.25, 0) },
	}
	for _, entry in ipairs(layout) do
		local part = mock.Instance.new("Part")
		part.Name = entry[1]
		part.Size = V3.new(entry[2].X * w, entry[2].Y * h, entry[2].Z * w)
		part.CFrame = CF.new(entry[3].X * w, entry[3].Y * h, 0)
		part.Color = skin
		part.Parent = model
	end
	local head = mock.Instance.new("Part")
	head.Name = "Head"
	head.Size = V3.new(2, 1, 1)
	head.CFrame = CF.new(0, 4.7 * h + 0.6, 0)
	head.Color = skin
	head.Parent = model
	local bodyColors = mock.Instance.new("BodyColors")
	for _, field in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
		bodyColors[field] = skin
	end
	bodyColors.Parent = model
	model.Parent = mock.workspace
	return model
end

local function encodeColor(c)
	return string.format("[%d,%d,%d]", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function shapeOf(part)
	if part.Name == "Head" then return "head" end
	if part.ClassName == "WedgePart" then return "wedge" end
	if part:FindFirstChildOfClass("SpecialMesh") then return "ellipsoid" end
	if part.Shape == mock.Enum.PartType.Cylinder then return "cylinder" end
	return "block"
end
local function encodePart(part)
	local c = part.CFrame
	local r = c.r
	return string.format(
		'{"n":"%s","s":"%s","size":[%.4f,%.4f,%.4f],"p":[%.4f,%.4f,%.4f],"r":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f],"c":%s,"t":%.2f,"m":"%s"}',
		part.Name, shapeOf(part), part.Size.X, part.Size.Y, part.Size.Z, c.p.X, c.p.Y, c.p.Z,
		r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], encodeColor(part.Color), part.Transparency or 0, part.Material.Name
	)
end

local function dump(label, garmentId, ornamentId, h, w)
	local model = mannequin(h, w, SKIN)
	CostumeBuilder.dress(model, garmentId, ornamentId)
	local parts = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then table.insert(parts, encodePart(child)) end
	end
	for _, child in ipairs((model:FindFirstChild("Costume") or model):GetChildren()) do
		if child:IsA("BasePart") and child.Parent ~= model then table.insert(parts, encodePart(child)) end
	end
	-- Calotte de cheveux schématique (les vraies coiffures sont des accessoires du catalogue).
	local headY = 4.7 * h + 0.6
	table.insert(parts, string.format('{"n":"Hair","s":"ellipsoid","size":[1.32,0.75,1.34],"p":[0,%.4f,0.08],"r":[1,0,0,0,1,0,0,0,1],"c":%s,"t":0,"m":"Fabric"}', headY + 0.3, encodeColor(HAIR)))
	print(string.format('FIG {"label":"%s","parts":[%s]}', label, table.concat(parts, ",")))
	model:Destroy()
end

local scaleOf = {}
for _, race in ipairs(RaceConfig.RACES) do
	scaleOf[race.id] = { race.heightFactor, race.widthFactor }
end
for _, garment in ipairs(GarmentLibrary.GARMENTS) do
	local s = scaleOf[garment.people or "human"] or { 1, 1 }
	local ornament = if garment.people == "dwarf" then "beard_brown" elseif garment.people == "elf" then "ellendor_circlet" elseif garment.people == "shadowborn" then "anomaly_pendant" else nil
	dump(garment.name, garment.id, ornament, s[1], s[2])
end
for _, garment in ipairs(GarmentLibrary.NPC_GARMENTS) do
	dump(garment.name, garment.id, nil, 1.08, 1.02)
end
