--!strict
--[[
	EchoConfig
	Les échos temporels : des silhouettes translucides qui rejouent une scène effacée de l'histoire.

	Un écho n'est PAS décoratif : il montre quelque chose dont le joueur a besoin (l'ordre des runes
	du puits, la direction de la cathédrale), et le serveur sait qui l'a vu (objectif de quête "echo").

	Trajet : le générateur crée Workspace.World.EchoPaths.<echoId> contenant des Parts invisibles
	nommées "1", "2", ... (dans l'ordre du trajet). La silhouette marche de point en point.
	Actions : à certains points, la silhouette s'arrête (pause), peut toucher une cible (une rune,
	qui s'illumine chez le spectateur) et murmurer une phrase (sous-titre).

	Rendu : 100 % client (EchoRenderer). Le serveur (EchoService) décide QUAND un joueur voit l'écho :
	il est à moins de triggerRadius de l'ancre de l'écho, et, si `requiresQuest` est renseigné, sa
	quête est à la bonne étape. Il crédite l'objectif après la durée de l'écho si le joueur est resté
	à proximité (le client ne déclare jamais "j'ai vu l'écho").
]]

export type EchoAction = {
	point: number, -- index du point du trajet où l'action a lieu
	pause: number, -- secondes d'arrêt à ce point
	touch: string?, -- InteractableId touché (il s'illumine brièvement chez le spectateur)
	line: string?, -- sous-titre murmuré
}

export type Echo = {
	id: string,
	name: string, -- nom de la silhouette (affiché en sous-titre)
	anchor: string, -- AnchorId du début de l'écho (RegionConfig.ANCHORS)
	pathFolder: string, -- nom du dossier dans Workspace.World.EchoPaths
	pointCount: number, -- nombre de points que le générateur doit poser
	walkSpeed: number, -- studs/s
	triggerRadius: number, -- studs autour de l'ancre pour déclencher
	watchRadius: number, -- studs : le joueur doit rester dans ce rayon de la silhouette pour que l'écho compte
	color: Color3,
	actions: { EchoAction },
	finalLine: string?,
	requiresQuest: { quest: string, stage: string }?, -- nil = visible par tous (avec cooldown)
	replayCooldown: number, -- secondes avant qu'un même joueur puisse le revoir
	discovery: string?, -- découverte accordée après l'avoir vu en entier
	builderHint: string,
}

local ECHOES: { [string]: Echo } = {
	echo_bell = {
		id = "echo_bell",
		name = "Odile, la dernière sonneuse",
		anchor = "echo_bell",
		pathFolder = "echo_bell",
		pointCount = 10,
		walkSpeed = 7,
		triggerRadius = 28,
		watchRadius = 70,
		color = Color3.fromRGB(150, 210, 255),
		actions = {
			{ point = 1, pause = 2.5, line = "Ils arrivent... Il faut que la cloche se taise. Il faut qu'elle oublie." },
			{ point = 4, pause = 1.5, line = "Trois, puis un. Ne te trompe pas, Odile. Pas cette fois." },
			{ point = 7, pause = 1.4, touch = "well_rune_3", line = "Le Soir..." },
			{ point = 8, pause = 1.4, touch = "well_rune_1", line = "...le Matin..." },
			{ point = 9, pause = 1.4, touch = "well_rune_4", line = "...Minuit..." },
			{ point = 10, pause = 2.0, touch = "well_rune_2", line = "...et le Midi. Veilleurs, gardez-la pour moi." },
		},
		finalLine = "La silhouette descend dans le puits... et n'y est jamais entrée.",
		requiresQuest = { quest = "bell_silent", stage = "echo" },
		replayCooldown = 20,
		discovery = "echo_odile",
		builderHint = "Points 1-3 : parvis de la chapelle puis descente du chemin de la butte ; 4-6 : traversée de la place ; 7 : face à la rune ouest (3), 8 : rune est (1), 9 : rune nord (4), 10 : rune sud (2). Points à hauteur du sol (le centre de la silhouette sera 3 studs au-dessus).",
	},
	echo_forest = {
		id = "echo_forest",
		name = "Une fugitive sans visage",
		anchor = "echo_forest",
		pathFolder = "echo_forest",
		pointCount = 8,
		walkSpeed = 14,
		triggerRadius = 30,
		watchRadius = 80,
		color = Color3.fromRGB(255, 190, 140),
		actions = {
			{ point = 1, pause = 1.5, line = "Les flammes... j'ai allumé les trois flammes, et il ne s'est rien passé !" },
			{ point = 5, pause = 2.0, line = "Elle est sous l'eau, maintenant. La cathédrale. Avec tous ceux qui priaient." },
			{ point = 8, pause = 1.5, line = "Si quelqu'un entend ceci... ne sonnez pas la cloche. Ou sonnez-la. Je ne sais plus." },
		},
		finalLine = "Elle s'efface vers le nord, là où l'eau a avalé les flèches de la cathédrale.",
		requiresQuest = nil,
		replayCooldown = 300,
		discovery = "echo_fugitive",
		builderHint = "Points 1-2 : au centre de la clairière de la statue ; 3-8 : course vers le nord-est, en direction de la cathédrale (vers LAYOUT.cathedralSpires), s'arrêtant au bord de la forêt.",
	},
}

return table.freeze({
	ECHOES = ECHOES,
	TRANSPARENCY = 0.55, -- transparence des Parts de la silhouette
	SUBTITLE_DURATION = 3.5,
})
