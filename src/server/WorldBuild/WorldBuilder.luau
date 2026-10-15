--!strict
--[[
	WorldBuilder
	Générateur idempotent de la Région 1 ("Les Terres de la Cloche") : terrain + géométrie + ancres.
	Tout ce qu'il construit va dans Workspace.World (Static, Anchors, Dynamic, EchoPaths) ; il vide et
	resculpte la zone de terrain de la région. Rien d'autre du Workspace n'est créé ni modifié.

	MODE D'EMPLOI (Roblox Studio, en mode édition) :
		1. Affichage > Command Bar, puis exécuter :
		       require(game.ServerScriptService.Server.WorldBuild.WorldBuilder).build()
		2. Vérifier la sortie (Output) : un avertissement liste ce qui manquerait au contrat.
		3. Fichier > Enregistrer : la carte est enregistrée dans la place (plus besoin de la générer
		   au démarrage). Ctrl+Z annule la construction (points d'historique avant / après).
		Autres commandes : .clear() détruit World et vide le terrain de la région ; .verify() liste les
		manques sans rien construire.

	AU DÉMARRAGE DU SERVEUR : Main appelle WorldBuilder.ensureBuilt(), qui ne construit que si
	Workspace.World manque ou porte une BuildVersion inférieure à WorldBuildConfig.BUILD_VERSION
	(et seulement si BUILD_AT_RUNTIME_IF_MISSING est vrai).

	ZONES : modules frères exposant build(context: BuildContext.Context), appelés dans l'ordre de
	WorldBuildConfig.ZONES. Forest et CathedralShore sont facultatifs : ignorés tant qu'ils n'existent
	pas (test script.Parent:FindFirstChild). Voir BuildContext pour le contenu du contexte.

	API :
		WorldBuilder.build(options: { silent: boolean? }?)  -- reconstruit tout (idempotent)
		WorldBuilder.ensureBuilt(): boolean                 -- true si une construction a eu lieu
		WorldBuilder.clear()
		WorldBuilder.verify(): { string }                   -- éléments du contrat manquants
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local MechanismConfig = require(ReplicatedStorage.Shared.World.MechanismConfig)
local EchoConfig = require(ReplicatedStorage.Shared.World.EchoConfig)

local BuildContext = require(script.Parent.BuildContext)
local Config = require(script.Parent.WorldBuildConfig)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local TerrainSculpt = require(script.Parent.TerrainSculpt)
local Overlook = require(script.Parent.Overlook)
local Village = require(script.Parent.Village)
local Chapel = require(script.Parent.Chapel)
local Crypt = require(script.Parent.Crypt)
local Training = require(script.Parent.Training)

type ZoneModule = { build: (context: BuildContext.Context) -> () }

export type BuildOptions = {
	silent: boolean?, -- pas de résumé dans la sortie (les manques sont toujours signalés)
}

-- Interactables réservés : aucune géométrie attendue pour l'instant.
local RESERVED_INTERACTABLES: { [string]: boolean } = { chest_antimatter = true }

-- Zones construites par ce générateur (les autres sont cherchées à côté de ce module).
local BUILT_IN_ZONES: { [string]: ZoneModule } = {
	Overlook = Overlook,
	Village = Village,
	Chapel = Chapel,
	Crypt = Crypt,
	Training = Training,
}

local BOUNDARY_HEIGHT = 300
local BOUNDARY_THICKNESS = 4

local WorldBuilder = {}

--------------------------------------------------------------------------------
-- Historique de Studio (Ctrl+Z)
--------------------------------------------------------------------------------

-- Pose un point d'historique ; sans effet (et sans erreur) hors du mode édition de Studio.
local function setWaypoint(name: string)
	pcall(function()
		ChangeHistoryService:SetWaypoint(name)
	end)
end

--------------------------------------------------------------------------------
-- Dossiers
--------------------------------------------------------------------------------

local function destroyExistingWorlds()
	for _, child in workspace:GetChildren() do
		if child.Name == RegionConfig.WORLD_FOLDER_NAME then
			child:Destroy()
		end
	end
end

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Murs invisibles le long des limites jouables (LAYOUT.playableMin / playableMax).
local function buildBoundaries(static: Folder)
	local folder = Kit.folder(static, "Boundaries")
	local min, max = RegionConfig.LAYOUT.playableMin, RegionConfig.LAYOUT.playableMax
	local center = (min + max) / 2
	local size = max - min
	local y = min.Y + BOUNDARY_HEIGHT / 2
	local walls: { { name: string, cframe: CFrame, size: Vector3 } } = {
		{ name = "BoundaryNorth", cframe = CFrame.new(center.X, y, min.Z), size = Vector3.new(size.X, BOUNDARY_HEIGHT, BOUNDARY_THICKNESS) },
		{ name = "BoundarySouth", cframe = CFrame.new(center.X, y, max.Z), size = Vector3.new(size.X, BOUNDARY_HEIGHT, BOUNDARY_THICKNESS) },
		{ name = "BoundaryWest", cframe = CFrame.new(min.X, y, center.Z), size = Vector3.new(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, size.Z) },
		{ name = "BoundaryEast", cframe = CFrame.new(max.X, y, center.Z), size = Vector3.new(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, size.Z) },
	}
	for _, wall in walls do
		Kit.part(folder, wall.cframe, wall.size, Palette.stoneDark, {
			name = wall.name,
			transparency = 1,
			collide = true,
			query = false,
			shadow = false,
		})
	end
end

--------------------------------------------------------------------------------
-- Vérification du contrat
--------------------------------------------------------------------------------

-- Liste ce qui manque (ou est en double) dans `world` par rapport aux configurations partagées.
local function verifyWorld(world: Instance?): { string }
	local problems: { string } = {}
	if world == nil then
		table.insert(problems, "Workspace." .. RegionConfig.WORLD_FOLDER_NAME)
		return problems
	end

	local anchorsFound: { [string]: number } = {}
	local interactablesFound: { [string]: number } = {}
	local dynamicsFound: { [string]: number } = {}
	for _, descendant in world:GetDescendants() do
		local anchorId = descendant:GetAttribute(RegionConfig.ANCHOR_ATTRIBUTE)
		if typeof(anchorId) == "string" and CollectionService:HasTag(descendant, RegionConfig.ANCHOR_TAG) then
			anchorsFound[anchorId] = (anchorsFound[anchorId] or 0) + 1
		end
		local interactableId = descendant:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE)
		if typeof(interactableId) == "string" and CollectionService:HasTag(descendant, RegionConfig.INTERACTABLE_TAG) then
			interactablesFound[interactableId] = (interactablesFound[interactableId] or 0) + 1
		end
		local dynamicId = descendant:GetAttribute(MechanismConfig.DYNAMIC_ATTRIBUTE)
		if typeof(dynamicId) == "string" then
			dynamicsFound[dynamicId] = (dynamicsFound[dynamicId] or 0) + 1
		end
	end

	local function expect(kind: string, id: string, found: { [string]: number })
		local count = found[id] or 0
		if count == 0 then
			table.insert(problems, kind .. " " .. id)
		elseif count > 1 then
			table.insert(problems, kind .. " " .. id .. " (en double x" .. count .. ")")
		end
	end
	for id in RegionConfig.ANCHORS do
		expect("ancre", id, anchorsFound)
	end
	for id in MechanismConfig.EXTRA_ANCHORS do
		expect("ancre", id, anchorsFound)
	end
	for id in MechanismConfig.INTERACTABLES do
		if not RESERVED_INTERACTABLES[id] then
			expect("interactable", id, interactablesFound)
		end
	end
	for id in MechanismConfig.DYNAMICS do
		expect("dynamic", id, dynamicsFound)
	end

	local echoPaths = world:FindFirstChild(RegionConfig.ECHO_PATHS_FOLDER_NAME)
	for id, echo in EchoConfig.ECHOES do
		local folder = echoPaths and echoPaths:FindFirstChild(echo.pathFolder)
		if folder == nil then
			table.insert(problems, "trajet d'écho " .. id)
		else
			for i = 1, echo.pointCount do
				if folder:FindFirstChild(tostring(i)) == nil then
					table.insert(problems, "point d'écho " .. id .. "/" .. i)
				end
			end
		end
	end
	for _, name in { RegionConfig.STATIC_FOLDER_NAME, RegionConfig.ANCHORS_FOLDER_NAME, RegionConfig.DYNAMIC_FOLDER_NAME, RegionConfig.ECHO_PATHS_FOLDER_NAME } do
		if world:FindFirstChild(name) == nil then
			table.insert(problems, "dossier World." .. name)
		end
	end
	table.sort(problems)
	return problems
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- Module de zone : intégré, ou frère facultatif (Forest, CathedralShore) s'il existe déjà.
local function findZone(name: string): ZoneModule?
	local builtIn = BUILT_IN_ZONES[name]
	if builtIn then
		return builtIn
	end
	local moduleScript = script.Parent:FindFirstChild(name)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local loaded = (require :: any)(moduleScript)
		if type(loaded) == "table" and type(loaded.build) == "function" then
			return loaded :: ZoneModule
		end
		warn(`[WorldBuilder] Le module {name} n'expose pas build(context) : ignoré.`)
	end
	return nil
end

local function buildAll(silent: boolean)
	local startClock = os.clock()
	Kit.reset()
	TerrainSculpt.reset()
	destroyExistingWorlds()

	local world = Instance.new("Folder")
	world.Name = RegionConfig.WORLD_FOLDER_NAME
	world:SetAttribute(Config.BUILD_VERSION_ATTRIBUTE, Config.BUILD_VERSION)
	world:SetAttribute(Config.BUILD_SEED_ATTRIBUTE, Config.SEED)
	local static = newFolder(world, RegionConfig.STATIC_FOLDER_NAME)
	local anchors = newFolder(world, RegionConfig.ANCHORS_FOLDER_NAME)
	local dynamic = newFolder(world, RegionConfig.DYNAMIC_FOLDER_NAME)
	local echoPaths = newFolder(world, RegionConfig.ECHO_PATHS_FOLDER_NAME)
	local context = BuildContext.new(world, static, anchors, dynamic, echoPaths)

	-- Terrain : on vide toute la zone de la région, puis le relief commun à toutes les zones.
	TerrainSculpt.clearZone()
	TerrainSculpt.sculptRegion(context.random)
	buildBoundaries(static)

	local skipped: { string } = {}
	for _, name in Config.ZONES do
		local zone = findZone(name)
		if zone then
			zone.build(context)
		elseif Config.OPTIONAL_ZONES[name] then
			table.insert(skipped, name)
		else
			warn(`[WorldBuilder] Module de zone introuvable : {name}`)
		end
	end

	-- Parenté à la fin : une seule insertion dans le Workspace.
	world.Parent = workspace

	local problems = verifyWorld(world)
	if #problems > 0 then
		local note = if #skipped > 0 then ` (zones pas encore écrites : {table.concat(skipped, ", ")})` else ""
		warn(`[WorldBuilder] Contrat incomplet{note} : {#problems} manque(s) : {table.concat(problems, " ; ")}`)
	end
	if not silent then
		local stats = Kit.stats()
		print(string.format(
			"[WorldBuilder] Région 1 construite (v%d, graine %d) en %.1f s : %d Parts, %d lumières (%d avec ombres), %d opérations de terrain.",
			Config.BUILD_VERSION,
			Config.SEED,
			os.clock() - startClock,
			stats.parts,
			stats.lights,
			stats.shadowLights,
			TerrainSculpt.opCount()
		))
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Reconstruit toute la région (détruit Workspace.World et resculpte le terrain). Idempotent.
function WorldBuilder.build(options: BuildOptions?)
	local silent = options ~= nil and options.silent == true
	setWaypoint("WorldBuilder : avant construction")
	local ok, err = pcall(function()
		buildAll(silent)
	end)
	setWaypoint("WorldBuilder : après construction")
	if not ok then
		error(`[WorldBuilder] Échec de la construction : {err}`, 0)
	end
end

-- Construit seulement si World manque ou est d'une version antérieure. Retourne true si construit.
function WorldBuilder.ensureBuilt(): boolean
	if not Config.BUILD_AT_RUNTIME_IF_MISSING then
		return false
	end
	local world = workspace:FindFirstChild(RegionConfig.WORLD_FOLDER_NAME)
	if world then
		local version = world:GetAttribute(Config.BUILD_VERSION_ATTRIBUTE)
		if typeof(version) == "number" and version >= Config.BUILD_VERSION then
			return false
		end
	end
	WorldBuilder.build({ silent = true })
	return true
end

-- Détruit Workspace.World et vide le terrain de la région.
function WorldBuilder.clear()
	setWaypoint("WorldBuilder : avant effacement")
	destroyExistingWorlds()
	TerrainSculpt.reset()
	TerrainSculpt.clearZone()
	TerrainSculpt.reset()
	setWaypoint("WorldBuilder : après effacement")
end

-- Éléments du contrat absents de la carte actuelle (sans rien construire).
function WorldBuilder.verify(): { string }
	return verifyWorld(workspace:FindFirstChild(RegionConfig.WORLD_FOLDER_NAME))
end

return table.freeze(WorldBuilder)
