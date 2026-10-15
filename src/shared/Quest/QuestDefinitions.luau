--!strict
--[[
	QuestDefinitions
	Les quêtes, sous forme de DONNÉES (QuestService les exécute ; aucune logique ici).
	Ajouter une quête = ajouter une entrée : aucun code à écrire tant que ses objectifs utilisent les
	types existants.

	Structure d'une quête :
		id            identifiant STABLE (écrit dans les sauvegardes et dans la clé de récompense "quest:<id>")
		kind          "main" | "side" | "tutorial"
		giver         PNJ qui la propose (AnchorId du marqueur, ex. "npc_bellkeeper")
		prerequisites { minRank?, quests?, unlocks? } : vérifiés par le serveur avant de la proposer
		offer         ce que dit le donneur pour la proposer (+ libellés d'acceptation / refus)
		stages        étapes successives ; une étape est finie quand TOUS ses objectifs sont atteints
		after         ce que disent des PNJ une fois la quête terminée
		rewards       { xp, reputation, items, unlocks, discoveries } versés UNE fois par RewardService

	Types d'objectifs (et événement serveur qui les fait avancer, voir GameEvents) :
		talk      parler au PNJ `target` (AnchorId)                         -> Talked
		examine   utiliser l'objet interactif `target` (InteractableId)     -> InteractableUsed
		interact  idem (objet qui consomme / déclenche quelque chose)       -> InteractableUsed
		collect   ramasser l'objet interactif `target`                     -> InteractableUsed (kind "collect")
		explore   entrer dans la région `target` (RegionConfig.REGIONS.id)  -> RegionEntered
		echo      voir l'écho `target` en entier (EchoConfig)              -> EchoWitnessed
		puzzle    résoudre le mécanisme `target` (MechanismConfig)         -> PuzzleSolved (présents à proximité)
		kill      vaincre `count` ennemis d'id `target` (éligible au butin) -> EnemyDefeated
		item      posséder / obtenir l'objet `target` (ItemConfig)        -> ItemCollected

	Dialogue : chaque étape peut fournir `dialogue[npcId]` (ce que le PNJ dit pendant l'étape) ;
	parler à ce PNJ pendant l'étape fait avancer un objectif "talk" qui le vise.
]]

export type Objective = {
	id: string,
	type: "talk" | "examine" | "interact" | "collect" | "explore" | "echo" | "puzzle" | "kill" | "item",
	target: string,
	count: number,
	text: string, -- affiché dans le journal et le suivi de quête
	marker: string?, -- AnchorId ou InteractableId à signaler à l'écran (facultatif)
}

export type Stage = {
	id: string,
	title: string,
	journal: string, -- texte du journal pour cette étape (récit à la 2e personne)
	objectives: { Objective },
	dialogue: { [string]: { string } }?, -- [npcId] = répliques pendant cette étape
}

export type Quest = {
	id: string,
	name: string,
	kind: "main" | "side" | "tutorial",
	summary: string,
	giver: string,
	prerequisites: { minRank: string?, quests: { string }?, unlocks: { string }? },
	offer: { lines: { string }, accept: string, decline: string },
	stages: { Stage },
	after: { [string]: { string } }?,
	rewards: { xp: number?, reputation: number?, items: { [string]: number }?, unlocks: { string }?, discoveries: { string }? },
	rewardText: string, -- ce que le journal annonce comme récompense (dont l'accès débloqué)
}

local function objective(id: string, kind: any, target: string, count: number, text: string, marker: string?): Objective
	return { id = id, type = kind, target = target, count = count, text = text, marker = marker }
end

local QUESTS: { [string]: Quest } = {
	----------------------------------------------------------------------------
	-- Quête principale : La Cloche Muette
	----------------------------------------------------------------------------
	bell_silent = {
		id = "bell_silent",
		name = "La Cloche Muette",
		kind = "main",
		summary = "La grande cloche de la chapelle sonne certaines nuits, alors que son mécanisme est brisé depuis l'incendie.",
		giver = "npc_bellkeeper",
		prerequisites = {},
		offer = {
			lines = {
				"Vous l'avez entendue, vous aussi ? Cette nuit. Trois coups, puis un.",
				"C'est impossible. La corde est pourrie, le battant a disparu le soir de l'incendie. J'étais le sonneur, je le saurais.",
				"Et pourtant elle sonne. Toujours la même heure : trois heures dix-sept.",
				"Les gens du village font semblant de dormir. Moi, je ne peux plus. Vous accepteriez de monter voir la chapelle ?",
			},
			accept = "Je vais enquêter.",
			decline = "Pas maintenant.",
		},
		stages = {
			{
				id = "testimony",
				title = "Le témoignage",
				journal = "Aldric le Sonneur affirme que la cloche brisée sonne la nuit, toujours à 3 h 17.",
				objectives = {
					objective("talk_aldric", "talk", "npc_bellkeeper", 1, "Écouter Aldric le Sonneur", "npc_bellkeeper"),
				},
			},
			{
				id = "investigate",
				title = "L'enquête",
				journal = "Les ruines de la chapelle gardent peut-être la trace de ce qui s'est passé la nuit de l'incendie. Fouillez-les.",
				objectives = {
					objective("clue_inscription", "examine", "clue_bell_inscription", 1, "Examiner le socle de la cloche", "clue_bell_inscription"),
					objective("clue_hymnbook", "examine", "clue_hymnbook", 1, "Examiner le livre d'hymnes brûlé", "clue_hymnbook"),
					objective("clue_clock", "examine", "clue_frozen_clock", 1, "Examiner l'horloge figée", "clue_frozen_clock"),
				},
				dialogue = {
					npc_bellkeeper = {
						"La chapelle est sur la butte, au nord de la place. Faites attention, le toit de la nef ne tient plus que par habitude.",
					},
					npc_elder = {
						"La chapelle ? Odile y montait chaque soir. La dernière sonneuse avant Aldric.",
						"On ne l'a jamais retrouvée. Certains disent qu'elle a fui. Moi je dis qu'elle a sonné une fois de trop.",
					},
				},
			},
			{
				id = "echo",
				title = "L'écho",
				journal = "Les indices parlent d'un carillon : 3, 1, 4, 2. Sur le parvis de la chapelle, le temps semble trembler. Attendez-y et regardez.",
				objectives = {
					objective("see_echo", "echo", "echo_bell", 1, "Assister à l'écho sur le parvis de la chapelle", "echo_bell"),
				},
				dialogue = {
					npc_bellkeeper = {
						"Trois, un, quatre, deux... Odile chantonnait ça en remontant de la place. Je croyais que c'était une comptine.",
						"Retournez au parvis. Si le temps se souvient de quelque chose, c'est là-haut.",
					},
				},
			},
			{
				id = "discovery",
				title = "La découverte",
				journal = "La silhouette d'Odile a touché les runes du puits dans un ordre précis avant de disparaître dedans. Reproduisez son geste.",
				objectives = {
					objective("open_well", "puzzle", "well_runes", 1, "Toucher les runes du puits dans l'ordre de l'écho", "well_rune_3"),
					objective("enter_crypt", "explore", "crypt", 1, "Descendre dans la crypte sous le puits", "well_rune_3"),
				},
				dialogue = {
					npc_child = {
						"Le puits ? Il chante, la nuit. Maman dit que c'est le vent. Le vent ne chante pas en comptant.",
					},
				},
			},
			{
				id = "trial",
				title = "L'épreuve",
				journal = "La Crypte des Veilleurs. Quelque chose y monte la garde depuis l'incendie. Le battant de la cloche est là, quelque part.",
				objectives = {
					objective("defeat_guardian", "kill", "ash_watcher", 1, "Vaincre le Veilleur de Cendre", "enemy_crypt_guardian"),
					objective("take_clapper", "collect", "crypt_relic", 1, "Récupérer le battant de la cloche", "crypt_relic"),
				},
			},
			{
				id = "reward",
				title = "La récompense",
				journal = "Rendez sa voix à la cloche, puis racontez à Aldric ce que vous avez trouvé.",
				objectives = {
					objective("ring_bell", "interact", "bell_main", 1, "Remettre le battant à la cloche", "bell_main"),
					objective("report", "talk", "npc_bellkeeper", 1, "Retourner voir Aldric le Sonneur", "npc_bellkeeper"),
				},
				dialogue = {
					npc_bellkeeper = {
						"Vous... vous l'avez entendue ? Pas trois coups. Un seul. Juste. Comme avant.",
						"Odile n'a pas fui. Elle a caché le battant pour que la cloche ne puisse plus appeler ce qui vient avec l'heure.",
						"Et nous, pendant des années, nous avons cru que le silence était une malédiction. C'était une protection.",
						"Je ne sais pas si vous avez réparé quelque chose, ou si vous venez de réveiller autre chose. Mais les racines de la forêt ont bougé, cette nuit. Elles s'ouvrent.",
					},
				},
			},
		},
		after = {
			npc_bellkeeper = {
				"Elle sonne juste, maintenant. Une fois par jour. Je ne sais pas qui la fait sonner. Je préfère ne pas savoir.",
			},
			npc_elder = {
				"Vous avez entendu la cloche ? Odile serait contente. Ou terrifiée. Avec elle, c'était souvent la même chose.",
			},
		},
		rewards = {
			xp = 400,
			reputation = 60,
			items = { bell_clapper_shard = 1 },
			unlocks = { "forest_hollow" },
			discoveries = { "lore_bell_truth" },
		},
		rewardText = "400 XP, 60 de Renom, un Éclat de bronze, et la Grille de Racines de la forêt s'ouvre (Grotte des Échos).",
	},

	----------------------------------------------------------------------------
	-- Tutoriel : l'épreuve du Cercle (combat, anomalie, rembobinage)
	----------------------------------------------------------------------------
	circle_trial = {
		id = "circle_trial",
		name = "L'Épreuve du Cercle",
		kind = "tutorial",
		summary = "Bran, le maître d'armes, veut voir si vous savez survivre à ce qui vient avec l'heure.",
		giver = "npc_trainer",
		prerequisites = {},
		offer = {
			lines = {
				"Tu tiens ta lame comme quelqu'un qui est déjà mort une fois. Bien. Ça fait moins peur la deuxième.",
				"Les mannequins t'apprendront le rythme : trois coups, et le dernier avec le poids du corps. Lève ta garde juste avant l'impact, pas avant.",
				"Dans le Cercle, à l'est, dort un Gardien. Quand il est blessé, il arrête le temps autour de lui. Si ça t'arrive : rembobine. Tout de suite.",
				"Reviens vivant et je te dirai que tu es prêt.",
			},
			accept = "J'entre dans le Cercle.",
			decline = "Plus tard.",
		},
		stages = {
			{
				id = "listen",
				title = "Les conseils de Bran",
				journal = "Bran vous a expliqué le rythme de la lame, la parade, et ce qu'il faut faire quand le temps s'arrête.",
				objectives = {
					objective("talk_bran", "talk", "npc_trainer", 1, "Écouter Bran", "npc_trainer"),
				},
			},
			{
				id = "fight",
				title = "Le Gardien du Cercle",
				journal = "Vainquez le Gardien de l'Anomalie dans le Cercle, à l'est de la cour d'entraînement. S'il fige le temps, rembobinez (R).",
				objectives = {
					objective("defeat_boss", "kill", "training_boss", 1, "Vaincre le Gardien de l'Anomalie", "boss_training"),
				},
				dialogue = {
					npc_trainer = {
						"Le Cercle est à l'est. Quand le ciel vire au rouge, tu as quatre battements de cœur. Rembobine.",
					},
				},
			},
			{
				id = "report",
				title = "Retour au maître d'armes",
				journal = "Retournez voir Bran.",
				objectives = {
					objective("report_bran", "talk", "npc_trainer", 1, "Parler à Bran", "npc_trainer"),
				},
				dialogue = {
					npc_trainer = {
						"Tu es revenu. Et tu as rembobiné au bon moment, je le vois dans tes yeux : ils ont l'air plus vieux de cinq secondes.",
						"Ysolde, au tableau des contrats, a du travail pour les gens comme toi. Va la voir.",
					},
				},
			},
		},
		after = {
			npc_trainer = { "Le Gardien revient toujours. Comme nous tous, ici. Entraîne-toi quand tu veux." },
		},
		rewards = { xp = 150, reputation = 15 },
		rewardText = "150 XP et 15 de Renom.",
	},

	----------------------------------------------------------------------------
	-- Quête secondaire : Ce que murmurent les arbres
	----------------------------------------------------------------------------
	forest_whispers = {
		id = "forest_whispers",
		name = "Ce que murmurent les arbres",
		kind = "side",
		summary = "Le Voyageur Répété dit avoir vu une femme s'enfuir de la forêt, encore et encore, sans jamais en sortir.",
		giver = "npc_wanderer",
		prerequisites = {},
		offer = {
			lines = {
				"Vous allez dans la forêt ? Vous allez dans la forêt. Vous allez dans la forêt...",
				"Pardon. Ça me prend parfois. Je répète les choses. Les arbres aussi, vous verrez.",
				"Il y a une femme, là-bas. Elle court vers le nord. Elle court depuis que je suis arrivé ici, et je suis arrivé ici il y a très longtemps.",
				"Si vous la voyez, et si les Murmures vous laissent passer... dites-moi où elle allait.",
			},
			accept = "Je la trouverai.",
			decline = "Une autre fois.",
		},
		stages = {
			{
				id = "listen",
				title = "Le Voyageur Répété",
				journal = "Un étrange voyageur vous a parlé d'une fugitive qui court sans fin dans la Forêt des Murmures.",
				objectives = {
					objective("talk_wanderer", "talk", "npc_wanderer", 1, "Écouter le Voyageur Répété", "npc_wanderer"),
				},
			},
			{
				id = "search",
				title = "La fugitive",
				journal = "Entrez dans la Forêt des Murmures, trouvez la clairière de la statue et observez ce que le temps y rejoue. Les Murmures rôdent autour.",
				objectives = {
					objective("enter_forest", "explore", "forest", 1, "Entrer dans la Forêt des Murmures", "npc_wanderer"),
					objective("see_fugitive", "echo", "echo_forest", 1, "Assister à l'écho de la clairière de la statue", "echo_forest"),
					objective("hunt_whispers", "kill", "whisper", 2, "Disperser des Murmures", "enemy_forest_4"),
				},
			},
			{
				id = "report",
				title = "Ce qu'elle a dit",
				journal = "Racontez au Voyageur Répété ce que la fugitive a dit.",
				objectives = {
					objective("report_wanderer", "talk", "npc_wanderer", 1, "Retourner voir le Voyageur Répété", "npc_wanderer"),
				},
				dialogue = {
					npc_wanderer = {
						"Vers la cathédrale ? Sous l'eau ? ... Oui. Oui, je me souviens maintenant. J'y priais.",
						"Merci. Je ne sais pas si je vais arrêter de répéter. Mais au moins, maintenant, je sais quoi.",
					},
				},
			},
		},
		after = {
			npc_wanderer = { "La cathédrale. La cathédrale. ... Pardon. Ça va mieux, je vous assure." },
		},
		rewards = { xp = 250, reputation = 30, items = { echo_fragment = 1 } },
		rewardText = "250 XP, 30 de Renom, un Fragment d'écho.",
	},
}

-- Ordre d'affichage dans le journal.
local ORDER = { "bell_silent", "circle_trial", "forest_whispers" }

local function getQuest(id: any): Quest?
	return if type(id) == "string" then QUESTS[id] else nil
end

return table.freeze({
	QUESTS = QUESTS,
	ORDER = ORDER,
	getQuest = getQuest,
})
