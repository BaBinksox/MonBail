--!strict
--[[
	BuildContext
	Le "context" passé à chaque module de zone : build(context).

	Contenu :
		world, static, anchors, dynamic, echoPaths : les dossiers de Workspace.World ;
		random : Random(WorldBuildConfig.SEED), partagé (l'ordre des zones est fixe : déterministe) ;
		Kit, Palette, Props, TerrainSculpt, Config : les modules du générateur ;
		zone(name) : le sous-dossier World.Static.<name> (créé à la demande) ;
		addEchoPoint(pathName, index, cframe) : raccourci de Kit.echoPoint dans World.EchoPaths.

	Exemple de zone (Forest.luau, CathedralShore.luau) :
		local BuildContext = require(script.Parent.BuildContext)
		local Zone = {}
		function Zone.build(context: BuildContext.Context)
			local folder = context.zone("Forest")
			local Kit, Props = context.Kit, context.Props
			Props.deadTree(folder, CFrame.new(-300, context.TerrainSculpt.heightAt(-300, -20), -20), 18, context.random)
			Kit.anchor(context.anchors, "enemy_forest_2", Kit.standing(Vector3.new(-300, 8, -20), Vector3.new(-200, 8, -10)))
		end
		return Zone
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local TerrainSculpt = require(script.Parent.TerrainSculpt)
local Config = require(script.Parent.WorldBuildConfig)

export type Context = {
	world: Folder,
	static: Folder,
	anchors: Folder,
	dynamic: Folder,
	echoPaths: Folder,
	random: Random,
	Kit: typeof(Kit),
	Palette: typeof(Palette),
	Props: typeof(Props),
	TerrainSculpt: typeof(TerrainSculpt),
	Config: typeof(Config),
	zone: (name: string) -> Folder,
	addEchoPoint: (pathName: string, index: number, cframe: CFrame) -> Part,
}

local BuildContext = {}

-- Crée le contexte d'une construction à partir des dossiers de Workspace.World.
function BuildContext.new(world: Folder, static: Folder, anchors: Folder, dynamic: Folder, echoPaths: Folder): Context
	local context: Context = {
		world = world,
		static = static,
		anchors = anchors,
		dynamic = dynamic,
		echoPaths = echoPaths,
		random = Random.new(Config.SEED),
		Kit = Kit,
		Palette = Palette,
		Props = Props,
		TerrainSculpt = TerrainSculpt,
		Config = Config,
		zone = function(name: string): Folder
			return Kit.folder(static, name)
		end,
		addEchoPoint = function(pathName: string, index: number, cframe: CFrame): Part
			return Kit.echoPoint(echoPaths, pathName, index, cframe)
		end,
	}
	return context
end

return table.freeze(BuildContext)
