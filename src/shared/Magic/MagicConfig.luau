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
	advantage: string, -- point fort, en une phrase (carte du Destin)
	drawback: string, -- point faible, en une phrase
	radius: number, -- studs autour du lanceur
	damage: number,
	palette: Palette,
	-- Préparation de l'ultime (s) : posture et accumulation visibles ; les dégâts et l'effet propre
	-- à la magie tombent exactement à la fin (CombatService), quand la chorégraphie frappe.
	ultimateWindup: number,
}

local MAGICS: { Magic } = {
	{
		id = "antimatter",
		ultimateWindup = 0.75,
		name = "Antimatière",
		ultimateName = "Éruption d'Antimatière",
		description = "Le vide qui dévore. L'explosion aspire les survivants jusqu'à vous, à portée de lame.",
		advantage = "Regroupe les survivants à portée de lame : idéal pour enchaîner.",
		drawback = "Dégâts moyens ; les ennemis attirés vous entourent.",
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
		ultimateWindup = 0.2,
		name = "Pyromancie",
		ultimateName = "Brasier du Parjure",
		description = "Une colère qui ne s'éteint pas. Zone resserrée ; les survivants continuent de brûler.",
		advantage = "Les survivants continuent de brûler après l'explosion.",
		drawback = "Zone resserrée : il faut être au cœur de la mêlée.",
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
		ultimateWindup = 0.2,
		name = "Foudre",
		ultimateName = "Jugement Céleste",
		description = "Le ciel répond à votre appel. Frappe très loin, moins fort, et paralyse un instant.",
		advantage = "La plus grande portée ; paralyse un instant.",
		drawback = "Les dégâts directs les plus faibles.",
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
		ultimateWindup = 0.85,
		name = "Glace",
		ultimateName = "Hiver Éternel",
		description = "Un froid venu d'avant le monde. Ceux qu'il touche avancent comme dans un rêve.",
		advantage = "Ralentit tout ce qu'elle touche : le temps de souffler ou de fuir.",
		drawback = "Peu de dégâts sur la durée ; le froid ne tue pas seul.",
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
		ultimateWindup = 0.2,
		name = "Ombre",
		ultimateName = "Marée d'Ombres",
		description = "Ce qui rampe sous vos pas vous obéit. Courte portée, dégâts dévastateurs, et leur vie devient la vôtre.",
		advantage = "Les dégâts les plus lourds, et vous soigne de ce que vous prenez.",
		drawback = "La plus courte portée : il faut aller au contact.",
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
		ultimateWindup = 0.2,
		name = "Gravité",
		ultimateName = "Effondrement Stellaire",
		description = "Le poids du monde vous obéit. Les survivants sont arrachés au sol puis écrasés, et restent cloués un instant.",
		advantage = "Soulève puis écrase : dégâts en deux temps et ennemis cloués au sol.",
		drawback = "Effet lent à se déclencher ; les ennemis isolés en profitent peu.",
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

--[[
	Roulette du Destin (créateur de personnage) — règles affichées au joueur :
		- jamais payante, jamais de nouvelle chance contre de l'argent ou un objet ;
		- c'est le SERVEUR qui tire, chaque magie a exactement la même chance (1 sur #MAGICS) ;
		- une seule roue par personnage : le résultat est enregistré tout de suite et reste le même
		  si l'on ferme le jeu, se reconnecte ou insiste ; il SCELLE la magie de ce personnage ;
		- ne pas tourner la roue = choisir soi-même sa magie, librement.
]]
local DESTINY_RULES = "Le destin tire au sort parmi les magies, à chances égales. Une seule roue par personnage : son verdict est définitif et remplace votre choix. Gratuit, toujours."

return table.freeze({
	ATTRIBUTE = "InnateMagic", -- attribut (string = id de la magie) posé par le serveur sur le Player
	DESTINY_RULES = DESTINY_RULES,
	MAGICS = MAGICS,
	getById = getById,
})
