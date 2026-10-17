-- Tenues fabriquées et ornements (simulation, hors Roblox) : ajustement sur un mannequin R15 réaliste
-- à toutes les tailles des peuples, sécurité physique, teinture, sauvegarde, migration v3 -> v4, PNJ.
-- Ce test mesure la GÉOMÉTRIE (rien sous les pieds, rien qui flotte, rien de solide) ; il ne juge
-- pas l'esthétique, qui se vérifie dans Studio.
local H = require("./helpers")()
local runtime, mock = H.runtime, H.mock
local V3, CF = mock.Vector3, mock.CFrame

H.boot()
local GarmentLibrary = H.shared("Avatar/GarmentLibrary")
local AvatarConfig = H.shared("Avatar/AvatarConfig")
local RaceConfig = H.shared("Avatar/RaceConfig")
local CostumeBuilder = H.server("Avatar/CostumeBuilder")
local CharacterPlacement = H.server("Core/CharacterPlacement")
local AvatarSerializer = H.server("Avatar/AvatarSerializer")
local ProfileSchema = H.server("Data/ProfileSchema")

local SKIN = mock.Color3.fromRGB(204, 150, 104)

-- Mannequin R15 aux dimensions standard (blocs), pieds au sol (y = 0), mis à l'échelle.
local function mannequin(heightScale, widthScale)
	local h, w = heightScale, widthScale
	local model = mock.Instance.new("Model")
	model.Name = "Mannequin"
	local layout = {
		-- nom, taille, centre (avant échelle)
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
		part.CFrame = CF.new(entry[3].X * w, entry[3].Y * h, entry[3].Z)
		part.Color = SKIN
		part.Material = mock.Enum.Material.Plastic
		part.Parent = model
	end
	-- Tête classique : taille fixe (la tête n'est pas mise à l'échelle par AvatarAppearance).
	local head = mock.Instance.new("Part")
	head.Name = "Head"
	head.Size = V3.new(2, 1, 1)
	head.CFrame = CF.new(0, 4.7 * h + 0.6, 0)
	head.Parent = model
	local root = mock.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3.new(2 * w, 2 * h, 1 * w)
	root.CFrame = CF.new(0, 3.3 * h, 0)
	root.Parent = model
	local humanoid = mock.Instance.new("Humanoid")
	humanoid.RootPart = root
	humanoid.HipHeight = 2.3 * h
	humanoid.Parent = model
	local bodyColors = mock.Instance.new("BodyColors")
	for _, field in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
		bodyColors[field] = SKIN
	end
	bodyColors.Parent = model
	model.PrimaryPart = root
	model.Parent = mock.workspace
	return model
end

local function corners(part)
	local half = part.Size / 2
	local list = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(list, part.CFrame:PointToWorldSpace(V3.new(half.X * sx, half.Y * sy, half.Z * sz)))
			end
		end
	end
	return list
end
local function aabb(part)
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, p in ipairs(corners(part)) do
		lo = { math.min(lo[1], p.X), math.min(lo[2], p.Y), math.min(lo[3], p.Z) }
		hi = { math.max(hi[1], p.X), math.max(hi[2], p.Y), math.max(hi[3], p.Z) }
	end
	return { lo = lo, hi = hi }
end
local function gap(a, b)
	local sum = 0
	for axis = 1, 3 do
		local d = math.max(0, a.lo[axis] - b.hi[axis], b.lo[axis] - a.hi[axis])
		sum += d * d
	end
	return math.sqrt(sum)
end

local function costumeParts(model)
	local folder = model:FindFirstChild("Costume")
	local list = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then table.insert(list, child) end
		end
	end
	return list
end

local function bodyParts(model)
	local list = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then table.insert(list, child) end
	end
	return list
end

-- Analyse d'une tenue posée : sécurité, plancher, pièces flottantes.
local function inspect(model)
	local pieces = costumeParts(model)
	local report = { pieces = #pieces, unsafe = 0, unwelded = 0, belowFeet = 0, floating = {}, maxGap = 0 }
	local boxes = {}
	for _, part in ipairs(bodyParts(model)) do table.insert(boxes, aabb(part)) end
	local pieceBoxes = {}
	for index, part in ipairs(pieces) do
		pieceBoxes[index] = aabb(part)
		if part.CanCollide or part.CanQuery or part.CanTouch or not part.Massless or part.Anchored then
			report.unsafe += 1
		end
		local weld = part:FindFirstChild("CostumeWeld")
		if weld == nil or weld.Part1 ~= part or weld.Part0 == nil or weld.Part0.Parent ~= model then
			report.unwelded += 1
		end
		if pieceBoxes[index].lo[2] < -0.02 then
			report.belowFeet += 1
		end
	end
	-- Chaque pièce touche (à 0,35 stud près) le corps ou une autre pièce : rien ne flotte.
	for index, box in ipairs(pieceBoxes) do
		local best = math.huge
		for _, other in ipairs(boxes) do best = math.min(best, gap(box, other)) end
		for otherIndex, other in ipairs(pieceBoxes) do
			if otherIndex ~= index then best = math.min(best, gap(box, other)) end
		end
		report.maxGap = math.max(report.maxGap, best)
		if best > 0.35 then table.insert(report.floating, pieces[index].Name) end
	end
	return report
end

print("== Bibliothèque")
local playerGarments = 0
for _, option in ipairs(AvatarConfig.OUTFIT_OPTIONS) do
	if option.garment then
		playerGarments += 1
		H.check("tenue " .. option.id .. " : vêtement fabriqué présent", GarmentLibrary.get(option.garment) ~= nil)
		H.check("tenue " .. option.id .. " : aucun vêtement du catalogue", option.shirtId == 0 and option.pantsId == 0 and option.backAccessoryId == 0)
	end
end
H.check("quatre tenues fabriquées (une par peuple d'inspiration)", playerGarments == 4, playerGarments)
local peoples = {}
for _, garment in ipairs(GarmentLibrary.GARMENTS) do
	if garment.people then peoples[garment.people] = true end
end
H.check("chaque peuple a sa tenue d'inspiration", peoples.human and peoples.elf and peoples.dwarf and peoples.shadowborn)
H.check("tenues historiques conservées (sauvegardes existantes)", (function()
	local ids = {}
	for _, option in ipairs(AvatarConfig.OUTFIT_OPTIONS) do ids[option.id] = true end
	return ids.midnight_traveler and ids.black_iron_knight and ids.oathbreaker
end)())
-- Silhouettes distinctes : pas une seule tenue recolorée (nombre et forme des pièces différents).
local signatures = {}
for _, garment in ipairs(GarmentLibrary.GARMENTS) do
	local shapes = {}
	for _, spec in ipairs(garment.pieces) do shapes[spec.shape .. "@" .. spec.attach] = (shapes[spec.shape .. "@" .. spec.attach] or 0) + 1 end
	local keys = {}
	for key, n in pairs(shapes) do table.insert(keys, key .. "x" .. n) end
	table.sort(keys)
	signatures[table.concat(keys, ",")] = (signatures[table.concat(keys, ",")] or 0) + 1
end
local distinct = 0
for _ in pairs(signatures) do distinct += 1 end
H.check("silhouettes distinctes (pas une tenue recolorée)", distinct == #GarmentLibrary.GARMENTS, distinct)

print("== Ajustement sur toutes les tailles de peuples et proportions extrêmes")
local sizes = {}
for _, race in ipairs(RaceConfig.RACES) do
	table.insert(sizes, { label = race.name, h = race.heightFactor, w = race.widthFactor })
end
table.insert(sizes, { label = "petit et fin", h = AvatarConfig.HEIGHT_SCALE.min * 0.86, w = AvatarConfig.WIDTH_SCALE.min * 0.92 })
table.insert(sizes, { label = "grand et large", h = AvatarConfig.HEIGHT_SCALE.max * 1.05, w = AvatarConfig.WIDTH_SCALE.max * 1.12 })
local allGarments = {}
for _, garment in ipairs(GarmentLibrary.GARMENTS) do table.insert(allGarments, garment) end
for _, garment in ipairs(GarmentLibrary.NPC_GARMENTS) do table.insert(allGarments, garment) end
local problems = {}
local worstGap = 0
for _, garment in ipairs(allGarments) do
	for _, size in ipairs(sizes) do
		local model = mannequin(size.h, size.w)
		local hipBefore = CharacterPlacement.measureHipHeight(model)
		local count = CostumeBuilder.dress(model, garment.id, nil)
		local report = inspect(model)
		local tag = garment.id .. " / " .. size.label
		worstGap = math.max(worstGap, report.maxGap)
		if count < 8 then table.insert(problems, tag .. " : " .. count .. " pièces") end
		if report.unsafe > 0 then table.insert(problems, tag .. " : " .. report.unsafe .. " pièce(s) solide(s)") end
		if report.unwelded > 0 then table.insert(problems, tag .. " : " .. report.unwelded .. " non soudée(s)") end
		if report.belowFeet > 0 then table.insert(problems, tag .. " : " .. report.belowFeet .. " sous les pieds") end
		if #report.floating > 0 then table.insert(problems, tag .. " : flotte " .. table.concat(report.floating, ",")) end
		if math.abs((CharacterPlacement.measureHipHeight(model) or 0) - (hipBefore or 0)) > 1e-6 then table.insert(problems, tag .. " : HipHeight mesurée modifiée") end
		model:Destroy()
	end
end
print(string.format("    écart maximal pièce/corps : %.2f stud", worstGap))
H.check("toutes tenues x toutes tailles : sûres, soudées, au-dessus des pieds, rien ne flotte, HipHeight intacte", #problems == 0, table.concat(problems, " ; "))

print("== Teinture, changement de tenue, retour à une tenue du catalogue")
do
	local model = mannequin(1, 1)
	local adventurer = GarmentLibrary.get("ash_adventurer")
	CostumeBuilder.dress(model, "ash_adventurer", nil)
	H.check("teinture : le buste prend la couleur et la matière de la tunique", model.UpperTorso.Color == adventurer.dye.UpperTorso.color and model.UpperTorso.Material == mock.Enum.Material.Fabric)
	H.check("teinture : les mains gardent la peau", model.RightHand.Color == SKIN)
	local first = #costumeParts(model)
	CostumeBuilder.dress(model, "brasegrise_smith", nil)
	local folders = 0
	for _, child in ipairs(model:GetChildren()) do if child.Name == "Costume" then folders += 1 end end
	H.check("changer de tenue remplace l'ancienne (un seul dossier, pièces de la nouvelle)", folders == 1 and #costumeParts(model) ~= first and string.find(costumeParts(model)[1].Name, "brasegrise") ~= nil)
	CostumeBuilder.dress(model, nil, nil)
	H.check("tenue du catalogue : plus aucune pièce, peau et matière d'origine rétablies", model:FindFirstChild("Costume") == nil and model.UpperTorso.Color == SKIN and model.UpperTorso.Material == mock.Enum.Material.Plastic and model.RightLowerLeg.Color == SKIN)
	model:Destroy()
end

print("== Ornements")
do
	local model = mannequin(0.86, 1.12) -- nain
	CostumeBuilder.dress(model, "brasegrise_smith", "beard_brown")
	local beardPieces, onHead = 0, true
	for _, part in ipairs(costumeParts(model)) do
		if string.find(part.Name, "^Ornament_beard_brown") then
			beardPieces += 1
			if part.CostumeWeld.Part0 ~= model.Head then onHead = false end
		end
	end
	H.check("barbe tressée posée et soudée à la tête", beardPieces >= 3 and onHead, beardPieces)
	local report = inspect(model)
	H.check("barbe : rien ne flotte, rien de solide", #report.floating == 0 and report.unsafe == 0, table.concat(report.floating, ","))
	CostumeBuilder.dress(model, nil, "none")
	H.check("ornement « Aucun » : rien n'est posé", model:FindFirstChild("Costume") == nil)
	for _, ornament in ipairs(GarmentLibrary.ORNAMENTS) do
		if #ornament.pieces > 0 then
			CostumeBuilder.dress(model, nil, ornament.id)
			local r = inspect(model)
			H.check("ornement " .. ornament.id .. " : sûr et bien placé", r.pieces > 0 and r.unsafe == 0 and #r.floating == 0 and r.belowFeet == 0, table.concat(r.floating, ","))
		end
	end
	model:Destroy()
end

print("== Sauvegarde et migration")
do
	local selection = AvatarSerializer.sanitizeSelection(H.selection(1))
	H.check("un client d'avant les ornements reste accepté (ornement : aucun)", selection ~= nil and selection.ornamentIndex == 1)
	local raw = H.selection(1)
	raw.ornamentIndex = 2
	raw.outfitIndex = 3
	local saved = AvatarSerializer.toSaved(AvatarSerializer.sanitizeSelection(raw))
	H.check("l'ornement et la tenue fabriquée sont sauvegardés par identifiant", saved.ornament == AvatarConfig.ORNAMENT_OPTIONS[2].id and saved.outfit == AvatarConfig.OUTFIT_OPTIONS[3].id)
	local restored = AvatarSerializer.fromSaved(saved)
	H.check("et restaurés à l'identique", restored.ornamentIndex == 2 and restored.outfitIndex == 3)
	raw.ornamentIndex = 99
	H.check("index d'ornement invalide refusé", AvatarSerializer.sanitizeSelection(raw) == nil)
	-- Profil v3 existant : tenue historique, pas d'ornement.
	local v3 = { version = 3, avatar = { base = "man", face = "stoic", mark = "none", hair = "pal", outfit = "black_iron_knight", magic = "ice", height = 1, width = 1, race = "dwarf", skin = "tan" } }
	ProfileSchema.migrateV3toV4(v3)
	H.check("migration v3 -> v4 : ornement « none », rien d'autre ne change", v3.avatar.ornament == "none" and v3.avatar.outfit == "black_iron_knight" and v3.avatar.race == "dwarf" and v3.avatar.skin == "tan")
	local old = AvatarSerializer.fromSaved(v3.avatar)
	H.check("ancien personnage : sa tenue historique est retrouvée", AvatarConfig.OUTFIT_OPTIONS[old.outfitIndex].id == "black_iron_knight" and old.ornamentIndex == 1)
	H.check("version du profil : 4", ProfileSchema.VERSION == 4)
end

print("== Joueur en jeu : la tenue est posée par le serveur et refaite au respawn")
do
	local raw = H.selection(1)
	raw.outfitIndex = 4 -- Veilleur des Marches d'Ombre
	raw.ornamentIndex = 6 -- sablier
	local player = runtime.addPlayer("Tailleur", 8801)
	runtime.spawnCharacter(player)
	runtime.advance(3)
	local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
	AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(player, raw)
	runtime.advance(5)
	local folder = player.Character and player.Character:FindFirstChild("Costume")
	H.check("tenue fabriquée posée sur le personnage du joueur", folder ~= nil and #folder:GetChildren() > 0)
	local hasPendant = false
	for _, child in ipairs(folder and folder:GetChildren() or {}) do
		if string.find(child.Name, "anomaly_pendant") then hasPendant = true end
	end
	H.check("ornement posé avec", hasPendant)
	H.check("profil : tenue et ornement enregistrés", H.profile(player).avatar.outfit == "umbral_watcher" and H.profile(player).avatar.ornament == "anomaly_pendant")
	-- Respawn : nouvelle silhouette, la tenue revient.
	player.Character:Destroy()
	runtime.spawnCharacter(player)
	runtime.advance(5)
	local again = player.Character and player.Character:FindFirstChild("Costume")
	H.check("respawn : la tenue est refaite", again ~= nil and #again:GetChildren() > 0)
end

print("== PNJ rhabillés")
do
	local NpcSpawner = H.server("NPC/NpcSpawner")
	for _, npcId in ipairs({ "npc_blacksmith", "npc_guildmaster" }) do
		local model = NpcSpawner.getNpc(npcId)
		local folder = model and model:FindFirstChild("Costume")
		H.check(npcId .. " : costume fabriqué posé, nom et dialogue intacts", folder ~= nil and #folder:GetChildren() >= 8 and model:GetAttribute("DialogueId") ~= nil, model and model.Name)
	end
end

H.noNewErrors("tenues sans erreur")
H.printWarnings()
H.finish()
