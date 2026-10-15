--!strict
--[[
	WorldBuildConfig
	Réglages du générateur de la Région 1 (Server/WorldBuild). Données uniquement : aucune logique.

	- BUILD_VERSION : à incrémenter à chaque changement du générateur qui doit se voir dans les places
	  déjà enregistrées. WorldBuilder.ensureBuilt() reconstruit si Workspace.World porte une version
	  inférieure (et si BUILD_AT_RUNTIME_IF_MISSING est vrai).
	- SEED : graine du Random partagé par toutes les zones. Même graine = même carte, au stud près.
	- Les positions des lieux ne sont PAS ici : elles sont dans Shared/World/RegionConfig.LAYOUT.
]]

export type EnemySpawn = {
	enemyId: string, -- id de définition (EnemyDefinitions) ; "training_boss" pour le boss d'entraînement
	group: string, -- groupe de rencontre (les ennemis d'un même groupe réapparaissent ensemble)
}

-- Attributs posés sur les ancres d'ennemis (EnemyId, Group). Les ancres de la forêt sont déjà
-- déclarées ici pour que le module Forest n'ait rien à régler : Kit.anchor() les applique tout seul.
local ENEMY_SPAWNS: { [string]: EnemySpawn } = {
	enemy_training_dummy_1 = { enemyId = "training_dummy", group = "training_yard" },
	enemy_training_dummy_2 = { enemyId = "training_dummy", group = "training_yard" },
	enemy_training_dummy_3 = { enemyId = "training_dummy", group = "training_yard" },
	boss_training = { enemyId = "training_boss", group = "boss_arena" },
	enemy_crypt_guardian = { enemyId = "ash_warden", group = "crypt_hall" },
	enemy_forest_1 = { enemyId = "ash_stalker", group = "forest_gate" },
	enemy_forest_2 = { enemyId = "ash_stalker", group = "forest_fork" },
	enemy_forest_3 = { enemyId = "stone_guardian", group = "forest_north" },
	enemy_forest_4 = { enemyId = "whisper", group = "forest_statue" },
	enemy_forest_5 = { enemyId = "ash_stalker", group = "forest_ravine" },
	enemy_forest_6 = { enemyId = "whisper", group = "forest_pond" },
	enemy_forest_7 = { enemyId = "stone_guardian", group = "forest_west" },
}

return table.freeze({
	BUILD_VERSION = 1,
	SEED = 317, -- 3 h 17 : l'heure où tout s'est arrêté
	BUILD_AT_RUNTIME_IF_MISSING = true,

	----------------------------------------------------------------------------
	-- Terrain
	----------------------------------------------------------------------------
	-- Zone de terrain possédée par le générateur = limites jouables (LAYOUT.playableMin/Max) élargies
	-- de cette marge. Elle est entièrement vidée puis resculptée à chaque construction.
	TERRAIN_MARGIN_MIN = Vector3.new(100, 20, 160),
	TERRAIN_MARGIN_MAX = Vector3.new(100, 20, 160),
	TERRAIN_CHUNK = 512, -- taille max (studs) d'une opération FillBlock par axe
	BASE_BOTTOM = -64, -- fond du sol de base (la crypte et la grotte sont creusées dedans)
	FOREST_EDGE_X = -165, -- à l'ouest de cette abscisse, le sol de base est à FOREST_GROUND_HEIGHT
	FOREST_GROUND_HEIGHT = 8,
	LAKE_SURFACE = 1, -- hauteur de l'eau du lac (LAYOUT.lakeShore est à 2)
	LAKE_BOTTOM = -26,
	LAKE_SOUTH_Z = -245, -- bord sud du lac (la rive est à LAYOUT.lakeShore.Z)

	----------------------------------------------------------------------------
	-- Densités et budgets (multiplicateurs : 1 = valeur de référence)
	----------------------------------------------------------------------------
	DENSITY = table.freeze({
		clutter = 1.0, -- tonneaux, caisses, débris le long des rues
		ash = 1.0, -- tas de cendres et braises éparses
		trees = 1.0, -- arbres morts hors du village
		rocks = 1.0, -- rochers décoratifs
		graves = 1.0, -- tombes du cimetière
	}),
	LIGHT_BUDGET = 58, -- lumières (PointLight/SpotLight/SurfaceLight) pour TOUTE la région
	SHADOW_LIGHT_BUDGET = 5, -- lumières autorisées à projeter des ombres
	SHADOW_MIN_EXTENT = 6, -- une Part plus petite que ça (plus grande dimension) ne projette pas d'ombre

	----------------------------------------------------------------------------
	-- Narration
	----------------------------------------------------------------------------
	STOPPED_CLOCK_HOUR = 3,
	STOPPED_CLOCK_MINUTE = 17,

	ENEMY_SPAWNS = ENEMY_SPAWNS,
	ENEMY_ID_ATTRIBUTE = "EnemyId",
	ENEMY_GROUP_ATTRIBUTE = "Group",
	BUILD_VERSION_ATTRIBUTE = "BuildVersion",
	BUILD_SEED_ATTRIBUTE = "BuildSeed",

	-- Ordre de construction des zones (modules frères de WorldBuilder, chacun expose build(context)).
	-- Les zones facultatives sont ignorées si leur module n'existe pas encore.
	ZONES = { "Overlook", "Village", "Chapel", "Crypt", "Training", "Forest", "CathedralShore" },
	OPTIONAL_ZONES = table.freeze({ Forest = true, CathedralShore = true }),
})
