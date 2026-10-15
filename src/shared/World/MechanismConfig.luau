--!strict
--[[
	MechanismConfig
	Tous les objets interactifs de la Région 1 et les mécanismes à états qu'ils pilotent.

	VOCABULAIRE
		- Interactable : un objet VISIBLE sur lequel le serveur pose un ProximityPrompt (touche F).
		  Le générateur de carte le construit et lui donne le tag "Interactable" + l'attribut
		  InteractableId (= clé de INTERACTABLES). Le client ne peut désigner QUE ces identifiants.
		- Dynamic : une pièce (ou un Model) dont l'état change (porte, pont, barrière...). Le générateur
		  le range dans Workspace.World.Dynamic avec l'attribut DynamicId. MechanismService le manipule.
		- Mechanism : la règle qui relie des interactables à des dynamics (état, durée, conditions).

	Chaque interaction qui "ne fait que jouer un effet" est INTERDITE : toute entrée ici change un
	état serveur (porte ouverte, pont praticable, coffre récupéré, objectif de quête...).

	Les identifiants (clés) sont stables : ils servent de clés de récompense dans les profils.
]]

export type InteractableKind =
	"examine" -- affiche un texte ; peut faire avancer une quête (objectif "examine")
	| "board" -- ouvre une interface (tableau des contrats, de guilde)
	| "rune" -- une rune du puzzle du puits
	| "collect" -- ramasse un objet (conditions de quête possibles)
	| "chest" -- récompense unique par joueur (clé de ledger)
	| "gate" -- porte de région à conditions (RegionConfig.GATES) : fait passer le joueur autorisé
	| "teleport" -- passage simple (échelle de sortie de la crypte)
	| "power" -- mécanisme activable par une Magie Innée précise
	| "anchor" -- ancre temporelle : le prompt explique, la touche R agit (voir MECHANISMS.kind = "temporal_anchor")

export type Interactable = {
	kind: InteractableKind,
	prompt: string, -- verbe du ProximityPrompt ("Examiner", "Toucher la rune"...)
	title: string, -- nom de l'objet (ObjectText du prompt, titre du texte)
	text: string?, -- texte affiché au joueur (examine, gate verrouillée...)
	holdDuration: number?, -- secondes d'appui (0 par défaut)
	maxDistance: number?, -- distance d'activation (10 par défaut)
	mechanism: string?, -- clé de MECHANISMS pilotée par cet objet
	runeIndex: number?, -- rune : son numéro (1 à 4)
	item: string?, -- collect : objet donné (ItemConfig)
	consumes: { [string]: number }?, -- objets retirés à l'utilisation (cloche : le battant)
	gate: string?, -- gate : clé de RegionConfig.GATES
	insideAnchor: string?, -- gate / teleport : ancre de destination quand on entre
	outsideAnchor: string?, -- gate : ancre de destination quand on sort
	board: string?, -- board : "missions" | "guild"
	requiresMagic: string?, -- visible et utilisable seulement par cette Magie Innée
	reward: { xp: number?, reputation: number?, items: { [string]: number }?, discoveries: { string }? }?, -- chest
	discovery: string?, -- découverte accordée à la première utilisation (examine, chest, collect)
	builderHint: string, -- pour le générateur : à quoi l'objet ressemble et où il est
}

export type Mechanism = {
	kind: "power" | "group_door" | "temporal_anchor" | "rune_puzzle",
	magic: string?, -- power : id de MagicConfig requis
	effect: string?, -- power : "ignite" | "dissolve" | "power" | "freeze" | "reveal" | "shift"
	dynamic: string?, -- DynamicId manipulé
	duration: number?, -- secondes pendant lesquelles l'état activé dure, avant retour automatique
	group: string?, -- power : mécanisme de groupe auquel il contribue (braziers -> porte)
	requires: { string }?, -- group_door : mécanismes qui doivent être actifs en même temps
	runes: { string }?, -- rune_puzzle : interactables des runes, dans l'ordre de leur numéro
	sequence: { number }?, -- rune_puzzle : ordre à reproduire (numéros de runes)
	resetDelay: number?, -- rune_puzzle : secondes sans nouvelle rune avant remise à zéro
	radius: number?, -- temporal_anchor : distance (studs) à laquelle R agit sur l'ancre
	anchorInteractable: string?, -- temporal_anchor : l'interactable de l'ancre
	cooldown: number?, -- secondes avant de pouvoir réactiver après le retour à l'état initial
	description: string,
}

local MAGIC_REQUIRED_TEXT = "Une force ancienne dort ici. Seule une magie précise peut la réveiller."

local INTERACTABLES: { [string]: Interactable } = {
	----------------------------------------------------------------------------
	-- Tableaux
	----------------------------------------------------------------------------
	board_missions = {
		kind = "board",
		prompt = "Consulter",
		title = "Tableau des contrats",
		board = "missions",
		builderHint = "Grand panneau de bois cloué d'affiches, sous un auvent, devant la taverne (LAYOUT.missionBoard).",
	},
	board_guild = {
		kind = "board",
		prompt = "Consulter",
		title = "Tableau des guildes",
		board = "guild",
		builderHint = "Panneau de pierre gravé de blasons, devant la Salle des Serments (LAYOUT.guildBoard).",
	},

	----------------------------------------------------------------------------
	-- Quête "La Cloche Muette"
	----------------------------------------------------------------------------
	clue_bell_inscription = {
		kind = "examine",
		prompt = "Examiner",
		title = "Socle de la cloche",
		text = "Une inscription à demi effacée : « Qu'elle sonne trois fois et une, et la porte des Veilleurs se souviendra. » Quelqu'un a gratté la suite.",
		builderHint = "Socle de pierre gravé au pied du clocher, à l'intérieur de la chapelle (côté nord).",
	},
	clue_hymnbook = {
		kind = "examine",
		prompt = "Examiner",
		title = "Livre d'hymnes brûlé",
		text = "Les pages ont brûlé, sauf une, intacte, comme protégée : la partition d'un carillon. Les notes sont numérotées : 3, 1, 4, 2. Il y a de la cendre fraîche entre les pages.",
		builderHint = "Livre ouvert sur un lutrin renversé, dans la nef de la chapelle.",
	},
	clue_frozen_clock = {
		kind = "examine",
		prompt = "Examiner",
		title = "Horloge figée",
		text = "Les aiguilles sont arrêtées sur trois heures dix-sept. Pourtant, en approchant l'oreille, on entend un tic-tac. Un tic-tac qui recule.",
		builderHint = "Horloge murale fissurée, mur ouest de la nef, à hauteur d'homme.",
	},
	well_rune_1 = {
		kind = "rune",
		prompt = "Toucher la rune",
		title = "Rune du Matin",
		mechanism = "well_runes",
		runeIndex = 1,
		builderHint = "Pierre runique encastrée dans la margelle du puits, côté est. Rune lumineuse (Neon) éteinte.",
	},
	well_rune_2 = {
		kind = "rune",
		prompt = "Toucher la rune",
		title = "Rune du Midi",
		mechanism = "well_runes",
		runeIndex = 2,
		builderHint = "Pierre runique de la margelle, côté sud.",
	},
	well_rune_3 = {
		kind = "rune",
		prompt = "Toucher la rune",
		title = "Rune du Soir",
		mechanism = "well_runes",
		runeIndex = 3,
		builderHint = "Pierre runique de la margelle, côté ouest.",
	},
	well_rune_4 = {
		kind = "rune",
		prompt = "Toucher la rune",
		title = "Rune de Minuit",
		mechanism = "well_runes",
		runeIndex = 4,
		builderHint = "Pierre runique de la margelle, côté nord.",
	},
	crypt_relic = {
		kind = "collect",
		prompt = "Prendre",
		title = "Battant de la Cloche",
		item = "bell_clapper",
		discovery = "secret_crypt_relic",
		builderHint = "Battant de cloche en bronze posé sur un autel, au fond de la salle de la crypte (derrière le Veilleur).",
	},
	crypt_exit = {
		kind = "teleport",
		prompt = "Remonter",
		title = "Échelle du puits",
		insideAnchor = "crypt_exit_top",
		builderHint = "Échelle de fer contre le mur de la salle de la crypte, sous le puits.",
	},
	bell_main = {
		kind = "examine",
		prompt = "Remettre le battant",
		title = "La grande cloche",
		text = "Le bronze est fendu de haut en bas. Le battant manque.",
		consumes = { bell_clapper = 1 },
		maxDistance = 14,
		builderHint = "Cordon de la cloche qui pend au pied du clocher (la cloche elle-même est en haut). Interactable = la corde.",
	},

	----------------------------------------------------------------------------
	-- Portes de région
	----------------------------------------------------------------------------
	hollow_gate = {
		kind = "gate",
		prompt = "Passer",
		title = "Grille de Racines",
		gate = "hollow_gate",
		insideAnchor = "gate_hollow_inside",
		outsideAnchor = "gate_hollow_outside",
		builderHint = "Grille de racines noueuses qui ferme l'entrée de la grotte (LAYOUT.hollowGate). Solide (CanCollide).",
	},
	cathedral_gate = {
		kind = "gate",
		prompt = "Approcher",
		title = "Portail Englouti",
		gate = "cathedral_gate",
		builderHint = "Immense portail gothique fermé au bout de la chaussée (LAYOUT.cathedralGate). Solide.",
	},
	guild_archive_door = {
		kind = "gate",
		prompt = "Entrer",
		title = "Archives des Serments",
		gate = "guild_archive",
		insideAnchor = "gate_archive_inside",
		outsideAnchor = "gate_archive_outside",
		builderHint = "Porte basse cerclée de fer au fond de la Salle des Serments ; derrière, une petite salle d'archives (étagères, coffre).",
	},

	----------------------------------------------------------------------------
	-- Mécanismes des Magies Innées
	----------------------------------------------------------------------------
	mech_brazier_1 = {
		kind = "power",
		prompt = "Embraser",
		title = "Brasero antique",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "brazier_1",
		requiresMagic = "pyromancy",
		builderHint = "Brasero de pierre éteint, clairière de la statue, côté ouest.",
	},
	mech_brazier_2 = {
		kind = "power",
		prompt = "Embraser",
		title = "Brasero antique",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "brazier_2",
		requiresMagic = "pyromancy",
		builderHint = "Brasero de pierre éteint, clairière de la statue, côté nord.",
	},
	mech_brazier_3 = {
		kind = "power",
		prompt = "Embraser",
		title = "Brasero antique",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "brazier_3",
		requiresMagic = "pyromancy",
		builderHint = "Brasero de pierre éteint, clairière de la statue, côté est.",
	},
	mech_barrier_cemetery = {
		kind = "power",
		prompt = "Dissiper",
		title = "Voile maudit",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "barrier_cemetery",
		requiresMagic = "antimatter",
		builderHint = "Socle runique devant le voile violet qui ferme le mausolée du cimetière.",
	},
	mech_conduit_forest = {
		kind = "power",
		prompt = "Électriser",
		title = "Conduit ancien",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "conduit_forest",
		requiresMagic = "lightning",
		builderHint = "Pilier de métal verdi couvert de glyphes, au pied de la Tour du Guetteur.",
	},
	mech_frozen_pond = {
		kind = "power",
		prompt = "Geler",
		title = "Eau dormante",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "frozen_pond",
		requiresMagic = "ice",
		builderHint = "Pierre plate au bord de l'étang ; l'îlot au centre porte un coffre.",
	},
	mech_shadow_wall = {
		kind = "power",
		prompt = "Révéler",
		title = "Mur sans ombre",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "shadow_wall",
		requiresMagic = "shadow",
		builderHint = "Pan de mur de la chapelle (façade ouest, extérieur) qui ne projette pas d'ombre ; derrière, une alcôve.",
	},
	shadow_presence = {
		kind = "examine",
		prompt = "Écouter",
		title = "Présence",
		text = "Une silhouette que vous seul voyez murmure : « Le Sonneur n'a pas fui. Il est descendu. Il attend encore l'heure. »",
		requiresMagic = "shadow",
		discovery = "secret_shadow_presence",
		builderHint = "Point discret dans le cimetière, entre deux tombes (aucune géométrie visible requise : petite pierre noire).",
	},
	mech_gravity_block = {
		kind = "power",
		prompt = "Déplacer",
		title = "Bloc gravé",
		text = MAGIC_REQUIRED_TEXT,
		mechanism = "gravity_block",
		requiresMagic = "gravity",
		builderHint = "Gros bloc de pierre gravé, au pied d'un muret des ruines (LAYOUT.gravityRuins) ; une corniche inaccessible au-dessus.",
	},

	----------------------------------------------------------------------------
	-- Ancre temporelle
	----------------------------------------------------------------------------
	anchor_bridge = {
		kind = "anchor",
		prompt = "Observer",
		title = "Ancre temporelle",
		text = "Un sablier de pierre dont le sable coule vers le haut. Près de lui, le pont semble trembler, comme s'il se souvenait d'avoir été entier. [R] : rembobiner l'instant.",
		mechanism = "bridge_anchor",
		builderHint = "Sablier de pierre lumineux (Neon cyan) sur un socle, au bord sud du ravin, à côté de l'arrivée du pont.",
	},

	----------------------------------------------------------------------------
	-- Coffres et caches (récompense unique par joueur)
	----------------------------------------------------------------------------
	chest_flame_sanctum = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Coffre du Sanctuaire",
		reward = { xp = 120, reputation = 15, items = { ember_relic = 1 } },
		discovery = "secret_flame_sanctum",
		builderHint = "Coffre au fond du Sanctuaire des Flammes (derrière door_flame_sanctum).",
	},
	chest_cemetery = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Reliquaire du mausolée",
		reward = { xp = 120, reputation = 15, items = { void_relic = 1 } },
		discovery = "secret_mausoleum",
		builderHint = "Reliquaire dans le mausolée, derrière le voile maudit.",
	},
	chest_conduit = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Coffre du guetteur",
		reward = { xp = 120, reputation = 15, items = { storm_relic = 1 } },
		discovery = "secret_watchtower",
		builderHint = "Coffre dans la salle de la tour, derrière la grille door_conduit_gate.",
	},
	chest_pond = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Coffre de l'îlot",
		reward = { xp = 120, reputation = 15, items = { frost_relic = 1 } },
		discovery = "secret_pond_isle",
		builderHint = "Coffre sur l'îlot au centre de l'étang.",
	},
	chest_shadow = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Alcôve oubliée",
		reward = { xp = 120, reputation = 15, items = { shadow_relic = 1 } },
		discovery = "secret_shadow_alcove",
		builderHint = "Petite cache dans l'alcôve derrière le mur sans ombre (shadow_passage).",
	},
	chest_gravity = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Cache de la corniche",
		reward = { xp = 120, reputation = 15, items = { gravity_relic = 1 } },
		discovery = "secret_ledge",
		builderHint = "Coffre sur la corniche des ruines, atteignable seulement quand le bloc est en position B.",
	},
	chest_antimatter = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Écrin du vide",
		reward = { xp = 60, items = { echo_fragment = 1 } },
		discovery = nil,
		builderHint = "(Réservé : pas de géométrie requise pour l'instant.)",
	},
	chest_bridge_shrine = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Offrande de l'Autre Rive",
		reward = { xp = 150, reputation = 20, items = { echo_fragment = 2 } },
		discovery = "secret_bridge_shrine",
		builderHint = "Coffre sur l'autel de l'autre rive du ravin (LAYOUT.bridgeShrine).",
	},
	chest_hollow = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Écrin des Échos",
		reward = { xp = 200, reputation = 25, items = { echo_fragment = 3 } },
		discovery = "secret_hollow_heart",
		builderHint = "Coffre au cœur de la Grotte des Échos.",
	},
	chest_guild_archive = {
		kind = "chest",
		prompt = "Ouvrir",
		title = "Coffre des Archives",
		reward = { xp = 150, items = { guild_seal = 1 } },
		discovery = "secret_guild_archive",
		builderHint = "Coffre dans la salle des Archives des Serments (réservée aux guildes de niveau 3).",
	},
}

local MECHANISMS: { [string]: Mechanism } = {
	brazier_1 = { kind = "power", magic = "pyromancy", effect = "ignite", dynamic = "brazier_1", duration = 90, group = "flame_sanctum", description = "Brasero ouest de la clairière." },
	brazier_2 = { kind = "power", magic = "pyromancy", effect = "ignite", dynamic = "brazier_2", duration = 90, group = "flame_sanctum", description = "Brasero nord de la clairière." },
	brazier_3 = { kind = "power", magic = "pyromancy", effect = "ignite", dynamic = "brazier_3", duration = 90, group = "flame_sanctum", description = "Brasero est de la clairière." },
	flame_sanctum = {
		kind = "group_door",
		requires = { "brazier_1", "brazier_2", "brazier_3" },
		dynamic = "door_flame_sanctum",
		duration = 60,
		description = "La porte du Sanctuaire des Flammes s'ouvre quand les trois braseros brûlent en même temps.",
	},
	barrier_cemetery = { kind = "power", magic = "antimatter", effect = "dissolve", dynamic = "barrier_cemetery", duration = 25, cooldown = 5, description = "Le voile maudit du mausolée se dissout." },
	conduit_forest = { kind = "power", magic = "lightning", effect = "power", dynamic = "door_conduit_gate", duration = 20, cooldown = 5, description = "Le conduit alimente la grille de la tour, qui se lève tant qu'il est chargé." },
	frozen_pond = { kind = "power", magic = "ice", effect = "freeze", dynamic = "pond_ice", duration = 25, cooldown = 5, description = "Des plaques de glace praticables se forment jusqu'à l'îlot." },
	shadow_wall = { kind = "power", magic = "shadow", effect = "reveal", dynamic = "shadow_passage", duration = 25, cooldown = 5, description = "Le mur sans ombre devient traversable et révèle l'alcôve." },
	gravity_block = { kind = "power", magic = "gravity", effect = "shift", dynamic = "gravity_block", duration = 60, cooldown = 5, description = "Le bloc glisse jusqu'au pied de la corniche et sert de marche." },
	bridge_anchor = {
		kind = "temporal_anchor",
		anchorInteractable = "anchor_bridge",
		dynamic = "bridge_restorable",
		radius = 16,
		duration = 15,
		cooldown = 4,
		description = "R près de l'ancre : le pont se souvient d'avoir été entier pendant 15 secondes.",
	},
	well_runes = {
		kind = "rune_puzzle",
		runes = { "well_rune_1", "well_rune_2", "well_rune_3", "well_rune_4" },
		sequence = { 3, 1, 4, 2 },
		resetDelay = 10,
		dynamic = "well_cover",
		duration = 120,
		description = "Toucher les runes dans l'ordre du carillon (3, 1, 4, 2) fait glisser la dalle du puits : l'escalier de la crypte apparaît.",
	},
}

--[[
	Objets dynamiques que le générateur DOIT créer dans Workspace.World.Dynamic, avec l'attribut DynamicId.
	`states` décrit ce que MechanismService fait de leurs Parts (aucune autre convention n'est supposée) :
		- "toggle_collide" : état actif = Parts traversables et transparentes (barrière, mur, porte qui
		  "s'efface"), inactif = solides et visibles ;
		- "appear" : état actif = Parts solides et visibles (pont, glace), inactif = transparentes et traversables ;
		- "slide" : le Model se déplace de son pivot initial vers l'ancre `<DynamicId>_open` (porte, dalle, bloc) ;
		- "light" : état actif = PointLight / Fire / ParticleEmitter descendants activés (brasero).
]]
local DYNAMICS: { [string]: { states: string, builderHint: string } } = {
	brazier_1 = { states = "light", builderHint = "Le brasero lui-même (Model) : contient un Fire désactivé, un PointLight désactivé, une Part 'Embers' Neon éteinte." },
	brazier_2 = { states = "light", builderHint = "Idem brazier_1." },
	brazier_3 = { states = "light", builderHint = "Idem brazier_1." },
	door_flame_sanctum = { states = "slide", builderHint = "Dalle de pierre qui ferme l'entrée du sanctuaire ; ancre door_flame_sanctum_open = position ouverte (descendue dans le sol)." },
	barrier_cemetery = { states = "toggle_collide", builderHint = "Voile violet (Part ForceField/Neon translucide, CanCollide) qui ferme l'entrée du mausolée." },
	door_conduit_gate = { states = "slide", builderHint = "Herse de fer de la tour ; ancre door_conduit_gate_open = position levée." },
	pond_ice = { states = "appear", builderHint = "Model de plaques de glace (Material Ice) en chemin jusqu'à l'îlot, au ras de l'eau." },
	shadow_passage = { states = "toggle_collide", builderHint = "Le pan de mur (Parts) qui ferme l'alcôve ouest de la chapelle." },
	gravity_block = { states = "slide", builderHint = "Le bloc gravé (Model) ; ancre gravity_block_open = position B, au pied de la corniche." },
	bridge_restorable = { states = "appear", builderHint = "Planches et rambardes manquantes du pont (Model) ; les culées restent dans Static." },
	well_cover = { states = "slide", builderHint = "Dalle de pierre qui couvre le puits ; ancre well_cover_open = glissée sur le côté. Dessous : escalier en colimaçon vers la crypte." },
}

-- Ancres supplémentaires nécessaires aux mécanismes et portes (en plus de RegionConfig.ANCHORS).
local EXTRA_ANCHORS: { [string]: string } = {
	door_flame_sanctum_open = "Position ouverte de la dalle du sanctuaire.",
	door_conduit_gate_open = "Position levée de la herse de la tour.",
	gravity_block_open = "Position B du bloc gravé.",
	well_cover_open = "Position glissée de la dalle du puits.",
	crypt_exit_top = "Sortie de la crypte : à côté du puits, sur la place (LookVector vers la place).",
	gate_hollow_inside = "Juste derrière la grille de racines (intérieur de la grotte).",
	gate_hollow_outside = "Juste devant la grille de racines (côté forêt).",
	gate_archive_inside = "Intérieur de la salle des Archives.",
	gate_archive_outside = "Devant la porte des Archives, dans la Salle des Serments.",
}

return table.freeze({
	INTERACTABLES = INTERACTABLES,
	MECHANISMS = MECHANISMS,
	DYNAMICS = DYNAMICS,
	EXTRA_ANCHORS = EXTRA_ANCHORS,
	DYNAMIC_ATTRIBUTE = "DynamicId",
	DEFAULT_MAX_DISTANCE = 10,
	-- Attributs publiés par le serveur sur chaque Dynamic (lus par les clients pour leurs effets).
	STATE_ATTRIBUTE = "MechanismActive", -- boolean
	STATE_UNTIL_ATTRIBUTE = "MechanismActiveUntil", -- workspace:GetServerTimeNow() de fin (number)
})
