--!strict
--[[
	NpcConfig
	Les habitants de la Région 1 : qui apparaît sur quel marqueur de la carte, sous quel nom, avec
	quelle apparence et quelle fonction. NpcSpawner (serveur) les crée au démarrage.

	Chaque clé est l'AnchorId d'un marqueur "npc_*" de RegionConfig.ANCHORS ; c'est aussi l'identifiant
	du PNJ pour les quêtes (objectif "talk" de QuestDefinitions) : NE PAS RENOMMER une fois en ligne.

	Apparence : uniquement des options DÉJÀ présentes dans AvatarConfig (tenues, coiffures, visages),
	plus des couleurs de peau, des échelles et des DÉTAILS médiévaux sculptés en pièces simples
	(NpcCostume : tablier, robe, armure, cape, besace...). Aucun asset nouveau, aucun ID inventé.

	Fonctions (role) :
		"missions"  le dialogue propose d'ouvrir le tableau des contrats ;
		"guild"     le dialogue propose d'ouvrir le menu des guildes ;
		nil         simple habitant (dialogue et quêtes).
]]

export type Look = {
	base: string, -- id de AvatarConfig.BASE_OPTIONS ("man" / "woman")
	outfit: string?, -- id de AvatarConfig.OUTFIT_OPTIONS
	hair: string?, -- id de AvatarConfig.HAIR_OPTIONS
	skin: Color3,
	height: number, -- échelle de hauteur
	width: number,
	face: string?, -- id de AvatarConfig.FACE_OPTIONS (visage dessiné, pas de visage moderne)
	details: { string }?, -- détails de costume (NpcCostume.RECIPES)
	-- Costume fabriqué (GarmentLibrary : teinture des membres + pièces) ; remplace `outfit`.
	garment: string?,
}

export type Npc = {
	name: string,
	dialogueId: string, -- clé de DialogueConfig.DIALOGUES (texte habituel)
	wanders: boolean,
	role: string?,
	look: Look,
}

local SKIN_PALE = Color3.fromRGB(234, 206, 184)
local SKIN_WARM = Color3.fromRGB(205, 160, 125)
local SKIN_DARK = Color3.fromRGB(120, 82, 60)
local SKIN_ASHEN = Color3.fromRGB(196, 190, 186)

local NPCS: { [string]: Npc } = {
	npc_bellkeeper = {
		name = "Aldric le Sonneur",
		dialogueId = "bellkeeper",
		wanders = false,
		look = { base = "man", outfit = "oathbreaker", hair = "pal", skin = SKIN_ASHEN, height = 0.95, width = 0.95, face = "stoic", details = { "belt", "shawl" } },
	},
	npc_elder = {
		name = "L'Ancienne",
		dialogueId = "elder",
		wanders = false,
		look = { base = "woman", outfit = "midnight_traveler", hair = "long_pale", skin = SKIN_PALE, height = 0.9, width = 0.9, face = "serene", details = { "robe_elder", "shawl" } },
	},
	npc_blacksmith = {
		name = "Le Forgeron",
		dialogueId = "blacksmith",
		wanders = false,
		look = { base = "man", hair = "brown", skin = SKIN_DARK, height = 1.1, width = 1.1, face = "defiant", garment = "village_smith" },
	},
	npc_child = {
		name = "L'Enfant",
		dialogueId = "child",
		wanders = true,
		look = { base = "woman", outfit = "midnight_traveler", hair = "bun", skin = SKIN_WARM, height = 0.9, width = 0.8, face = "freckles", details = { "belt" } },
	},
	npc_quartermaster = {
		name = "Ysolde",
		dialogueId = "quartermaster",
		wanders = false,
		role = "missions",
		look = { base = "woman", outfit = "black_iron_knight", hair = "crimson", skin = SKIN_WARM, height = 1.0, width = 0.95, face = "serene", details = { "sash", "satchel" } },
	},
	npc_guildmaster = {
		name = "Corvin l'Archiviste",
		dialogueId = "guildmaster",
		wanders = false,
		role = "guild",
		look = { base = "man", hair = "librarian", skin = SKIN_PALE, height = 1.05, width = 0.9, face = "detached", garment = "village_archivist" },
	},
	npc_trainer = {
		name = "Bran, maître d'armes",
		dialogueId = "trainer",
		wanders = false,
		look = { base = "man", outfit = "black_iron_knight", hair = "spiked", skin = SKIN_WARM, height = 1.1, width = 1.05, face = "defiant", details = { "guard_armor", "cape" } },
	},
	npc_wanderer = {
		name = "Le Voyageur Répété",
		dialogueId = "wanderer",
		wanders = false,
		look = { base = "man", outfit = "oathbreaker", hair = "vagabond", skin = SKIN_ASHEN, height = 1.0, width = 0.9, face = "detached", details = { "travel_cloak", "satchel" } },
	},
	npc_villager_1 = {
		name = "Villageoise",
		dialogueId = "villager_weather",
		wanders = true,
		look = { base = "woman", outfit = "midnight_traveler", hair = "cinnamon", skin = SKIN_PALE, height = 0.95, width = 0.95, face = "serene", details = { "apron_cloth", "shawl" } },
	},
	npc_villager_2 = {
		name = "Villageois",
		dialogueId = "villager_rumor",
		wanders = true,
		look = { base = "man", outfit = "oathbreaker", hair = "bed_head", skin = SKIN_DARK, height = 1.0, width = 1.0, face = "stoic", details = { "belt", "satchel", "herbs" } },
	},
	npc_villager_3 = {
		name = "Fossoyeuse",
		dialogueId = "villager_warning",
		wanders = false,
		look = { base = "woman", outfit = "black_iron_knight", hair = "ninja_updo", skin = SKIN_ASHEN, height = 1.0, width = 0.95, face = "stoic", details = { "apron_mourning", "shawl_mourning" } },
	},
}

return table.freeze({
	NPCS = NPCS,
	NPC_ID_ATTRIBUTE = "NpcId", -- attribut (string) posé sur le Model : identifiant pour les quêtes
	ROLE_ATTRIBUTE = "NpcRole",
})
