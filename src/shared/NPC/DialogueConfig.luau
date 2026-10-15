--!strict
--[[
	DialogueConfig
	Tout ce qui règle les villageois : comment on leur parle, ce qu'ils disent, comment ils vivent.

	CRÉER UN VILLAGEOIS dans Studio :
		1. poser un rig (Avatar > Rig Builder, de préférence R15) dans le Workspace ;
		2. lui donner le tag "Villager" (Propriétés > Tags) ;
		3. facultatif, dans Propriétés > Attributes :
		     NpcName    (string)  le nom affiché. Par défaut : celui du dialogue, sinon le nom du Model.
		     DialogueId (string)  une clé de DIALOGUES ci-dessous. Par défaut : un dialogue générique,
		                          toujours le même pour un villageois donné.
		     Wanders    (boolean) false pour qu'il reste sur place. Par défaut : il se promène.

	ÉCRIRE UN DIALOGUE : ajouter une entrée à DIALOGUES. Chaque élément de `lines` est une réplique,
	affichée lettre par lettre ; le joueur passe à la suivante d'un clic ou d'une touche.
]]

export type Dialogue = {
	name: string?, -- nom du personnage qui parle (facultatif)
	lines: { string },
}

local DIALOGUES: { [string]: Dialogue } = {
	elder = {
		name = "Ancienne du village",
		lines = {
			"Tiens, un visage que je ne connais pas. Ou que je connais trop bien... c'est étrange.",
			"Ne restez pas dehors quand le ciel vire au rouge. Ceux qui restent ne reviennent pas les mêmes.",
			"Et si vous sentez une odeur de fleurs fanées, courez. Ne demandez pas pourquoi.",
		},
	},
	blacksmith = {
		name = "Forgeron",
		lines = {
			"Jolie lame. Mal entretenue, mais jolie.",
			"Le troisième coup, mettez-y le poids du corps. Une épée ne tue pas avec le poignet.",
			"Revenez me voir quand vous aurez de quoi payer. Les nains ne font pas crédit, et moi non plus.",
		},
	},
	child = {
		name = "Enfant",
		lines = {
			"Vous êtes un chevalier ? Un vrai ?",
			"Ma sœur dit qu'un monstre dort dans la plaine et qu'il se réveille quand on lui fait trop mal.",
			"Moi je crois que vous allez le battre. Vous l'avez déjà fait, non ?",
		},
	},

	-- PNJ de la Région 1 (placés par NpcSpawner, voir Shared/NPC/NpcConfig). Ces répliques sont leur texte
	-- HABITUEL : quand une quête les concerne, le serveur fournit d'autres répliques (DialogueService).
	bellkeeper = {
		name = "Aldric le Sonneur",
		lines = {
			"Elle ne sonne plus. Elle ne devrait plus jamais sonner.",
			"Allez, laissez un vieil homme regarder sa chapelle en paix.",
		},
	},
	quartermaster = {
		name = "Ysolde",
		lines = {
			"Des contrats, du travail honnête, et des pièces qui ne disparaissent pas quand le temps recule.",
			"Le tableau est derrière moi. Choisissez selon votre rang : je n'enterre pas les imprudents.",
		},
	},
	guildmaster = {
		name = "Corvin l'Archiviste",
		lines = {
			"Une guilde, c'est un serment écrit à plusieurs mains. Je garde les serments.",
			"Fondez la vôtre, ou rejoignez celle d'un ami. Les Archives n'ouvrent qu'aux serments qui ont tenu.",
		},
	},
	trainer = {
		name = "Bran, maître d'armes",
		lines = {
			"Trois coups. Le dernier avec le poids du corps.",
			"Et la garde : juste avant l'impact. Pas avant. Jamais avant.",
		},
	},
	wanderer = {
		name = "Le Voyageur Répété",
		lines = {
			"Bonjour. Bonjour. Bonjour... Pardon. Ça me prend parfois.",
			"Les arbres répètent ce qu'ils entendent. Moi aussi. Nous nous entendons bien.",
		},
	},

	-- Dialogues génériques : attribués aux villageois sans DialogueId.
	villager_weather = {
		lines = {
			"Le vent tourne. Ça sent la brume pour ce soir.",
			"Rentrez avant la nuit, voyageur. Les lucioles sont jolies, mais elles ne protègent de rien.",
		},
	},
	villager_rumor = {
		lines = {
			"Vous avez entendu ? Un marchand jure avoir vécu deux fois la même journée.",
			"On l'a pris pour un fou. Pourtant il savait à l'avance ce que j'allais lui répondre...",
		},
	},
	villager_tired = {
		lines = {
			"J'ai l'impression de vous avoir déjà dit bonjour ce matin.",
			"... Non ? Alors c'est que je dors mal. Tout le monde dort mal, ces temps-ci.",
		},
	},
	villager_warning = {
		lines = {
			"N'allez pas vers la plaine. Le Gardien n'aime pas qu'on le dérange.",
			"Et s'il se met à briller de rouge, c'est déjà trop tard pour fuir.",
		},
	},
}

return table.freeze({
	TAG = "Villager",
	NAME_ATTRIBUTE = "NpcName",
	DIALOGUE_ATTRIBUTE = "DialogueId",
	WANDER_ATTRIBUTE = "Wanders",

	-- Interaction ----------------------------------------------------------------
	-- F et non E : E est déjà la touche de l'ultime.
	INTERACT_KEY = Enum.KeyCode.F,
	INTERACT_DISTANCE = 10, -- studs
	ACTION_TEXT = "Parler",

	-- Machine à écrire -------------------------------------------------------------
	LETTERS_PER_SECOND = 38,
	SENTENCE_PAUSE = 0.28, -- secondes d'arrêt après . ! ?
	COMMA_PAUSE = 0.12, -- après , ; :
	-- Petit son joué toutes les BLIP_INTERVAL lettres, à une hauteur légèrement aléatoire.
	-- Par défaut : un son livré avec le client Roblox (rien à importer, il se charge toujours).
	-- >>> Pour le tien : "rbxassetid://123456".
	BLIP_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav",
	BLIP_VOLUME = 0.2,
	BLIP_INTERVAL = 2,
	BLIP_SPEED_MIN = 0.85,
	BLIP_SPEED_MAX = 1.15,

	-- Dialogues ------------------------------------------------------------------
	DIALOGUES = DIALOGUES,
	GENERIC_DIALOGUE_IDS = { "villager_weather", "villager_rumor", "villager_tired", "villager_warning" },

	-- Vie du village (serveur) -------------------------------------------------------
	WANDER_RADIUS = 14, -- studs autour de l'endroit où le villageois a été posé
	WANDER_SPEED = 6,
	WANDER_PAUSE_MIN = 4, -- secondes entre deux déplacements
	WANDER_PAUSE_MAX = 10,
	TALK_TIMEOUT = 45, -- secondes après lesquelles un villageois reprend sa promenade quoi qu'il arrive
	WALK_ANIMATION_ID = "rbxassetid://507777826", -- "R15Walk" (Roblox)
})
