--!strict
--[[
	NpcCostume
	Habille les PNJ de détails médiévaux SIMPLES, sculptés en pièces (aucun asset externe, aucun ID) :
	tablier de forge, robe d'archiviste, armure et cape de garde, besace d'herboriste, écharpe de
	marchand, châle, ceinture... Chaque détail est une liste de pièces soudées à une partie du corps,
	dimensionnées EN PROPORTION de cette partie : elles suivent la taille et la carrure du PNJ.

	Les pièces sont décoratives : sans collision, sans masse, invisibles aux raycasts et aux contacts.
	Elles ne gênent ni les déplacements du PNJ ni ceux des joueurs.

	Ajouter un détail : une entrée dans RECIPES, puis son nom dans NpcConfig (look.details).
]]

type Piece = {
	attach: string, -- partie du corps R15 (UpperTorso, LowerTorso, LeftUpperArm...)
	size: Vector3, -- en fraction de la taille de la partie
	offset: Vector3, -- en fraction de la taille de la partie (-Z = devant)
	rotation: Vector3?, -- degrés (X, Y, Z)
	color: Color3,
	material: Enum.Material,
}

local LEATHER = Color3.fromRGB(92, 62, 40)
local DARK_LEATHER = Color3.fromRGB(58, 42, 32)
local LINEN = Color3.fromRGB(222, 212, 190)
local IRON = Color3.fromRGB(118, 122, 128)
local GUARD_RED = Color3.fromRGB(118, 32, 36)
local SCHOLAR_BLUE = Color3.fromRGB(44, 52, 86)
local ELDER_GREEN = Color3.fromRGB(52, 70, 54)
local GOLD_THREAD = Color3.fromRGB(168, 136, 76)
local WOOL = Color3.fromRGB(128, 112, 96)
local MOURNING = Color3.fromRGB(40, 38, 44)
local HERB_GREEN = Color3.fromRGB(86, 132, 70)

local function piece(attach: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, rotation: Vector3?): Piece
	return { attach = attach, size = size, offset = offset, color = color, material = material, rotation = rotation }
end

local function apron(color: Color3, material: Enum.Material): { Piece }
	return {
		piece("UpperTorso", Vector3.new(0.82, 0.8, 0.06), Vector3.new(0, -0.1, -0.54), color, material),
		piece("LowerTorso", Vector3.new(0.9, 2.6, 0.06), Vector3.new(0, -1.05, -0.56), color, material),
		piece("LowerTorso", Vector3.new(1.04, 0.16, 1.06), Vector3.new(0, 0.3, 0), DARK_LEATHER, Enum.Material.Leather),
	}
end

local function robe(color: Color3): { Piece }
	return {
		piece("LowerTorso", Vector3.new(1.12, 3.4, 1.18), Vector3.new(0, -1.55, 0.02), color, Enum.Material.Fabric),
		piece("UpperTorso", Vector3.new(1.04, 0.22, 1.08), Vector3.new(0, 0.42, 0), GOLD_THREAD, Enum.Material.Fabric),
	}
end

local RECIPES: { [string]: { Piece } } = {
	apron_leather = apron(LEATHER, Enum.Material.Leather), -- forgeron
	apron_mourning = apron(MOURNING, Enum.Material.Leather), -- fossoyeuse
	apron_cloth = apron(LINEN, Enum.Material.Fabric), -- aubergiste
	robe_scholar = robe(SCHOLAR_BLUE), -- archiviste
	robe_elder = robe(ELDER_GREEN), -- ancienne
	guard_armor = { -- garde, maître d'armes
		piece("UpperTorso", Vector3.new(1.06, 0.96, 1.1), Vector3.new(0, 0.02, 0), IRON, Enum.Material.Metal),
		piece("LeftUpperArm", Vector3.new(1.35, 0.42, 1.35), Vector3.new(0, 0.36, 0), IRON, Enum.Material.Metal),
		piece("RightUpperArm", Vector3.new(1.35, 0.42, 1.35), Vector3.new(0, 0.36, 0), IRON, Enum.Material.Metal),
		piece("LowerTorso", Vector3.new(0.5, 1.9, 0.06), Vector3.new(0, -0.75, -0.56), GUARD_RED, Enum.Material.Fabric),
	},
	cape = { -- cape de voyage ou de garde (dos)
		piece("UpperTorso", Vector3.new(1.02, 2.9, 0.06), Vector3.new(0, -0.62, 0.58), GUARD_RED, Enum.Material.Fabric),
	},
	travel_cloak = {
		piece("UpperTorso", Vector3.new(1.08, 3.1, 0.07), Vector3.new(0, -0.7, 0.6), WOOL, Enum.Material.Fabric),
		piece("UpperTorso", Vector3.new(1.1, 0.3, 1.12), Vector3.new(0, 0.4, 0), WOOL, Enum.Material.Fabric),
	},
	satchel = { -- besace en bandoulière (marchand, herboriste, voyageur)
		piece("UpperTorso", Vector3.new(0.12, 1.25, 1.08), Vector3.new(0, 0, 0), DARK_LEATHER, Enum.Material.Leather, Vector3.new(0, 0, 38)),
		piece("LowerTorso", Vector3.new(0.3, 0.55, 0.62), Vector3.new(0.62, -0.05, 0), LEATHER, Enum.Material.Leather),
	},
	herbs = { -- brins d'herbes qui dépassent de la besace
		piece("LowerTorso", Vector3.new(0.1, 0.4, 0.14), Vector3.new(0.64, 0.32, 0.08), HERB_GREEN, Enum.Material.Grass),
		piece("LowerTorso", Vector3.new(0.1, 0.32, 0.14), Vector3.new(0.6, 0.28, -0.1), HERB_GREEN, Enum.Material.Grass, Vector3.new(0, 0, 12)),
	},
	sash = { -- écharpe de marchand
		piece("UpperTorso", Vector3.new(1.08, 0.2, 1.08), Vector3.new(0, -0.05, 0), Color3.fromRGB(150, 42, 42), Enum.Material.Fabric, Vector3.new(0, 0, -34)),
	},
	guild_stole = { -- étole du maître de guilde
		piece("UpperTorso", Vector3.new(0.16, 1.02, 0.05), Vector3.new(-0.22, -0.02, -0.54), GOLD_THREAD, Enum.Material.Fabric),
		piece("UpperTorso", Vector3.new(0.16, 1.02, 0.05), Vector3.new(0.22, -0.02, -0.54), GOLD_THREAD, Enum.Material.Fabric),
	},
	shawl = {
		piece("UpperTorso", Vector3.new(1.08, 0.42, 1.1), Vector3.new(0, 0.34, 0), WOOL, Enum.Material.Fabric),
	},
	shawl_mourning = {
		piece("UpperTorso", Vector3.new(1.08, 0.42, 1.1), Vector3.new(0, 0.34, 0), MOURNING, Enum.Material.Fabric),
	},
	belt = {
		piece("LowerTorso", Vector3.new(1.04, 0.16, 1.06), Vector3.new(0, 0.3, 0), DARK_LEATHER, Enum.Material.Leather),
	},
}

local NpcCostume = {}

NpcCostume.RECIPES = RECIPES

-- Ajoute à `model` les détails nommés. Un nom inconnu est signalé puis ignoré.
function NpcCostume.dress(model: Model, details: { string }?)
	if details == nil then
		return
	end
	for _, detail in details do
		local recipe = RECIPES[detail]
		if recipe == nil then
			warn(`[NPC] Détail de costume inconnu : {detail}`)
			continue
		end
		for index, spec in recipe do
			local attach = model:FindFirstChild(spec.attach)
			if attach == nil or not attach:IsA("BasePart") then
				continue
			end
			local base = attach.Size
			local rotation = spec.rotation or Vector3.zero
			local offset = CFrame.new(base * spec.offset)
				* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
			local part = Instance.new("Part")
			part.Name = `Costume_{detail}_{index}`
			part.Size = Vector3.new(
				math.max(base.X * spec.size.X, 0.05),
				math.max(base.Y * spec.size.Y, 0.05),
				math.max(base.Z * spec.size.Z, 0.05)
			)
			part.Color = spec.color
			part.Material = spec.material
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.CFrame = attach.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0 = attach
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part
			part.Parent = model
		end
	end
end

return NpcCostume
