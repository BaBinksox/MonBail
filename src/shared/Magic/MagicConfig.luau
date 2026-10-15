--!strict
--[[
	MagicConfig
	Catalogue des Magies Innées, partagé serveur + client.

	Chaque joueur en choisit UNE dans le Hub de création ; elle décide de son pouvoir ultime (touche E).
	Le serveur la range dans l'attribut ATTRIBUTE du Player (répliqué, lisible par les clients).

	Ajouter une magie = ajouter une entrée à MAGICS. Rien d'autre à toucher :
		- le Hub l'affiche tout seul dans "Le Choix du Destin" ;
		- CombatService lit `radius` et `damage` au moment de l'ultime ;
		- CombatEffects joue la chorégraphie commune avec sa `palette`, ou une chorégraphie
		  dédiée si on en enregistre une pour son `id` (voir ULTIMATE_PLAYERS dans CombatEffects).

	IMPORTANT : `id` est ce qui est écrit dans la sauvegarde du joueur. Ne jamais le renommer
	une fois le jeu en ligne (le nom affiché, lui, peut changer librement).
]]

export type Palette = {
	void: Color3, -- cœur sombre de l'arrêt sur image
	main: Color3, -- couleur dominante (anneau au sol, lumière, particules)
	glow: Color3, -- couleur claire (onde de choc, colonne, flash d'écran)
}

export type Magic = {
	id: string,
	name: string,
	ultimateName: string,
	description: string,
	radius: number, -- studs autour du lanceur
	damage: number,
	palette: Palette,
}

local MAGICS: { Magic } = {
	{
		id = "antimatter",
		name = "Antimatière",
		ultimateName = "Éruption d'Antimatière",
		description = "Le vide qui dévore. L'explosion aspire les survivants jusqu'à vous, à portée de lame.",
		radius = 30,
		damage = 60,
		palette = {
			void = Color3.fromRGB(6, 3, 12),
			main = Color3.fromRGB(150, 70, 255),
			glow = Color3.fromRGB(228, 200, 255),
		},
	},
	{
		id = "pyromancy",
		name = "Pyromancie",
		ultimateName = "Brasier du Parjure",
		description = "Une colère qui ne s'éteint pas. Zone resserrée ; les survivants continuent de brûler.",
		radius = 26,
		damage = 70,
		palette = {
			void = Color3.fromRGB(24, 5, 0),
			main = Color3.fromRGB(255, 110, 30),
			glow = Color3.fromRGB(255, 226, 170),
		},
	},
	{
		id = "lightning",
		name = "Foudre",
		ultimateName = "Jugement Céleste",
		description = "Le ciel répond à votre appel. Frappe très loin, moins fort, et paralyse un instant.",
		radius = 34,
		damage = 50,
		palette = {
			void = Color3.fromRGB(10, 8, 30),
			main = Color3.fromRGB(255, 220, 70),
			glow = Color3.fromRGB(255, 250, 215),
		},
	},
	{
		id = "ice",
		name = "Glace",
		ultimateName = "Hiver Éternel",
		description = "Un froid venu d'avant le monde. Ceux qu'il touche avancent comme dans un rêve.",
		radius = 30,
		damage = 55,
		palette = {
			void = Color3.fromRGB(2, 10, 22),
			main = Color3.fromRGB(90, 200, 255),
			glow = Color3.fromRGB(222, 246, 255),
		},
	},
	{
		id = "shadow",
		name = "Ombre",
		ultimateName = "Marée d'Ombres",
		description = "Ce qui rampe sous vos pas vous obéit. Courte portée, dégâts dévastateurs, et leur vie devient la vôtre.",
		radius = 24,
		damage = 80,
		palette = {
			void = Color3.fromRGB(4, 0, 2),
			main = Color3.fromRGB(170, 20, 60),
			glow = Color3.fromRGB(255, 170, 190),
		},
	},
	{
		id = "gravity",
		name = "Gravité",
		ultimateName = "Effondrement Stellaire",
		description = "Le poids du monde vous obéit. Les survivants sont arrachés au sol puis écrasés, et restent cloués un instant.",
		radius = 28,
		damage = 52, -- + 12 à l'écrasement (UltimateBehaviors)
		palette = {
			void = Color3.fromRGB(4, 6, 16),
			main = Color3.fromRGB(96, 124, 196),
			glow = Color3.fromRGB(214, 226, 255),
		},
	},
}

-- Retourne la magie d'identifiant `id`. Un identifiant inconnu ou absent (joueur qui n'a pas
-- encore choisi, magie retirée du jeu) donne la première magie de la liste.
local function getById(id: any): Magic
	for _, magic in MAGICS do
		if magic.id == id then
			return magic
		end
	end
	return MAGICS[1]
end

return table.freeze({
	ATTRIBUTE = "InnateMagic", -- attribut (string = id de la magie) posé par le serveur sur le Player
	MAGICS = MAGICS,
	getById = getById,
})
