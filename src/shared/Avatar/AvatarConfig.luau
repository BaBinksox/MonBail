--!strict
--[[
	AvatarConfig
	Catalogue du Hub de création de personnage, partagé serveur + client.

	Tout est piloté par les listes ci-dessous : ajouter une coiffure, un visage ou une marque,
	c'est ajouter UNE ligne. Le Hub, la validation serveur et la sauvegarde suivent tout seuls.

	Deux règles :
		- le client n'envoie que des INDEX dans ces listes (jamais d'ID d'asset) : le serveur
		  reste seul à décider quels assets peuvent être portés ;
		- chaque option a un `id` : c'est lui qui est écrit dans la sauvegarde du joueur (pas l'index,
		  qui change dès qu'on réordonne une liste). Ne jamais renommer un `id` une fois le jeu en
		  ligne ; un `id` devenu introuvable retombe sur la première option de sa liste.

	Les assets ci-dessous sont des PLACEHOLDERS du catalogue Roblox, à remplacer par ceux du jeu.
]]

local GarmentLibrary = require(script.Parent:WaitForChild("GarmentLibrary") :: ModuleScript)

-- Base du corps : les 5 parties (R15) d'un bundle.
export type BaseOption = {
	id: string,
	name: string,
	torsoId: number,
	rightArmId: number,
	leftArmId: number,
	leftLegId: number,
	rightLegId: number,
}

-- Visage : un Decal plaqué sur l'avant de la tête (il épouse sa courbure).
-- `texture` est une adresse d'image complète (voir image() et decalThumbnail() plus bas).
export type FaceLayerOption = {
	id: string,
	name: string,
	texture: string,
}

-- Marque (cicatrice, tatouage, blessure) : une image posée DEVANT le visage, sur un petit panneau
-- invisible (SurfaceGui). Contrairement à un Decal, on la place et on la dimensionne librement :
--   offset   : décalage depuis le centre du visage, en fraction du panneau. Vu de face :
--              X positif = vers la droite, Y positif = vers le bas. (0.1 = un dixième du visage.)
--   scale    : taille de l'image. 1 = toute la largeur du visage.
--   rotation : degrés, sens horaire.
-- Pour régler une marque au millimètre : lancer le jeu, ouvrir dans l'Explorateur
-- ton personnage > Head > FaceCanvas > MarkSurface > Mark, ajuster Position / Size / Rotation
-- à la main, puis reporter ici (Position = 0.5 + offset, Size = scale).
export type MarkOption = {
	id: string,
	name: string,
	texture: string, -- "" = aucune marque
	offset: Vector2,
	scale: number,
	rotation: number,
}

export type HairOption = {
	id: string,
	name: string,
	assetId: number, -- accessoire de type Hair
}

export type OutfitOption = {
	id: string,
	name: string,
	style: string, -- famille : "vagabond", "chevalier", "mage", "noble"... (classement, récapitulatif)
	-- Tenue FABRIQUÉE (GarmentLibrary) : teinture des membres + pièces sculptées, sans asset externe.
	-- Quand `garment` est renseigné, les trois champs du catalogue Roblox ci-dessous valent 0.
	garment: string?,
	shirtId: number, -- vêtement classique (Shirt) du catalogue Roblox, 0 = aucun
	pantsId: number, -- vêtement classique (Pants), 0 = aucun
	backAccessoryId: number, -- accessoire de type Back (cape), 0 = aucun
}

-- Ornement (barbe, diadème, pendentif) : voir GarmentLibrary.ORNAMENTS.
export type OrnamentOption = {
	id: string,
	name: string,
}

-- Teint : couleur appliquée à la tête ET à tout le corps visible (6 parties de BodyColors).
-- `color = nil` : on garde le teint de l'avatar Roblox du joueur (comportement d'avant).
export type SkinToneOption = {
	id: string,
	name: string,
	color: Color3?,
}

export type ScaleRange = {
	min: number,
	max: number,
	step: number,
	default: number,
}

-- Choix du joueur dans le Hub, tel qu'il transite dans les RemoteEvents (index dans les listes).
export type Selection = {
	baseIndex: number,
	faceIndex: number,
	markIndex: number,
	hairIndex: number,
	outfitIndex: number,
	heightScale: number,
	widthScale: number,
	magicIndex: number, -- index dans MagicConfig.MAGICS
	raceIndex: number, -- index dans RaceConfig.RACES
	skinIndex: number, -- index dans SKIN_TONES
	ornamentIndex: number, -- index dans ORNAMENT_OPTIONS (ajouté en v4 du profil)
}

-- Image que TU as importée (ou une image du catalogue) : on donne l'ID de l'IMAGE.
local function image(imageId: number): string
	return `rbxassetid://{imageId}`
end

-- Decal publié par quelqu'un d'autre : on ne connaît que l'ID du Decal, pas celui de son image.
-- Roblox sait en fournir l'aperçu 420x420, fond transparent conservé : suffisant pour un visage.
local function decalThumbnail(decalId: number): string
	return `rbxthumb://type=Asset&id={decalId}&w=420&h=420`
end

local BASE_OPTIONS: { BaseOption } = {
	{ -- bundle Roblox "Man"
		id = "man",
		name = "Homme",
		torsoId = 86500008,
		rightArmId = 86500036,
		leftArmId = 86500054,
		leftLegId = 86500064,
		rightLegId = 86500078,
	},
	{ -- bundle Roblox "Woman"
		id = "woman",
		name = "Femme",
		torsoId = 86499666,
		rightArmId = 86499698,
		leftArmId = 86499716,
		leftLegId = 86499753,
		rightLegId = 86499793,
	},
}

local FACE_OPTIONS: { FaceLayerOption } = {
	{ id = "stoic", name = "Impassible", texture = image(83017053) }, -- texture de "Man Face"
	{ id = "serene", name = "Sereine", texture = image(83022608) }, -- texture de "Woman Face"
	{ id = "defiant", name = "Défiant", texture = image(7074780) }, -- texture de "Check It"
	{ id = "detached", name = "Détaché", texture = image(7074749) }, -- texture de "Chill"
	{ id = "freckles", name = "Taches de son", texture = image(12145059) }, -- texture de "Freckles"
}

-- Raccourci pour déclarer une marque : mark(id, nom, image, décalageX, décalageY, taille, rotation).
local function mark(
	id: string,
	name: string,
	texture: string,
	offsetX: number,
	offsetY: number,
	scale: number,
	rotation: number
): MarkOption
	return {
		id = id,
		name = name,
		texture = texture,
		offset = Vector2.new(offsetX, offsetY),
		scale = scale,
		rotation = rotation,
	}
end

-- Cicatrices, tatouages, blessures. Les images doivent être à fond transparent.
-- Les quatre derniers nombres de chaque ligne placent la marque : voir le type MarkOption.
-- Placeholders : decals gratuits de la bibliothèque Roblox (série "[FACE] Extras" de morscore).
local MARK_OPTIONS: { MarkOption } = {
	mark("none", "Aucune", "", 0, 0, 1, 0),
	mark("scar_eye", "Cicatrice à l'œil", decalThumbnail(3524093836), 0, 0, 1, 0),
	mark("scar_slash", "Balafre", decalThumbnail(3524095179), 0, 0, 1, 0),
	mark("scar_cheek", "Entaille à la joue", decalThumbnail(3524096392), 0, 0, 1, 0),
	mark("scar_cross", "Croix du parjure", decalThumbnail(3524097066), 0, 0, 1, 0),
	mark("scar_claw", "Griffure", decalThumbnail(3524097803), 0, 0, 1, 0),
	-- Tatouage facial dessiné par un fan (motif inspiré d'un manga) : à remplacer avant de publier.
	mark("curse_seal", "Sceau maudit", decalThumbnail(16324571137), 0, 0, 1, 0),
}

-- La liste peut grandir sans limite : le Hub affiche "3 / 15" et boucle en fin de liste.
local HAIR_OPTIONS: { HairOption } = {
	{ id = "pal", name = "Mèches du pèlerin", assetId = 63690008 }, -- "Pal Hair"
	{ id = "spiked", name = "Crinière de cendre", assetId = 376524487 }, -- "Blonde Spiked Hair"
	{ id = "brown", name = "Coupe de l'écuyer", assetId = 62234425 }, -- "Brown Hair"
	{ id = "bun", name = "Chignon de la servante", assetId = 62724852 }, -- "Chestnut Bun"
	{ id = "ninja_updo", name = "Chignon de l'ombre", assetId = 2907260402 }, -- "Dark Age Ninja Updo Hair"
	{ id = "princess", name = "Chevelure de la princesse", assetId = 13477162 }, -- "Star Princess Hair"
	{ id = "azure", name = "Azur de l'héroïne", assetId = 164482409 }, -- "Blue Anime Girl Hair"
	{ id = "long_pale", name = "Longue chevelure pâle", assetId = 727320877 }, -- "Long Pastel Hair"
	{ id = "vagabond", name = "Mèche du vagabond", assetId = 65941324 }, -- "Black Indie Hair"
	{ id = "duelist", name = "Pointes du duelliste", assetId = 30332157 }, -- "Pointy Boy Hair"
	{ id = "bed_head", name = "Réveil difficile", assetId = 20372960 }, -- "Bed Hair"
	{ id = "dragon_heir", name = "Héritier du dragon", assetId = 2804642677 }, -- "Half-Dragon Heir Hair"
	{ id = "abyss", name = "Sirène des abysses", assetId = 4041570918 }, -- "Dark Mermaid Hair"
	{ id = "specter", name = "Spectre au ruban noir", assetId = 1425141074 }, -- "Ghostly White Hair with Black Bow"
	{ id = "crimson", name = "Tignasse écarlate", assetId = 259423003 }, -- "Crimson Bed Head Hair"
	{ id = "cinnamon", name = "Mèches cannelle", assetId = 13745548 }, -- "Cinnamon Hair"
	{ id = "ember", name = "Chevelure de braise", assetId = 77359955 }, -- "Lava Hair"
	{ id = "eccentric", name = "Rose de l'excentrique", assetId = 61885694 }, -- "Extreme Pink Hair"
	{ id = "azure_fringe", name = "Frange d'azur", assetId = 293316132 }, -- "Blue Scene Hair"
	{ id = "hazel_fringe", name = "Frange noisette", assetId = 323476364 }, -- "Brown Scene Hair"
	{ id = "librarian", name = "Bibliothécaire bicolore", assetId = 319642720 }, -- "Monochrome Library Hair"
	{ id = "bat_queen", name = "Reine des chauves-souris", assetId = 1074737868 }, -- "Queen of Bats Hair"
}

--[[
	Tenues.
	Les quatre premières sont FABRIQUÉES dans le jeu (GarmentLibrary) : aucune dépendance au
	catalogue, elles s'affichent pour tout le monde. Une par peuple d'inspiration ; tous les peuples
	peuvent les porter.
	Les trois suivantes sont les tenues historiques du projet (Shirt/Pants du catalogue Roblox,
	placeholders) : conservées pour les personnages déjà créés (leur `id` est dans les sauvegardes).
	>>> AJOUTER UNE TENUE : une ligne de plus, avec des ID VÉRIFIÉS en jeu (Toolbox > Marketplace >
	    Shirts / Pants / Back accessories, puis Play : la vignette du créateur et le personnage doivent
	    s'afficher). Familles souhaitées et encore à pourvoir : voir OUTFIT_WISHLIST plus bas.
	Aucun ID n'est inventé : une famille sans ID vérifié reste dans la liste de souhaits.
]]
local OUTFIT_OPTIONS: { OutfitOption } = {
	{ id = "ash_adventurer", name = "Aventurier des Cendres", style = "aventurier", garment = "ash_adventurer", shirtId = 0, pantsId = 0, backAccessoryId = 0 },
	{ id = "ellendor_warden", name = "Veilleur d'Ellendor", style = "voyageur des forêts", garment = "ellendor_warden", shirtId = 0, pantsId = 0, backAccessoryId = 0 },
	{ id = "brasegrise_smith", name = "Forgeron de Brasegrise", style = "artisan des montagnes", garment = "brasegrise_smith", shirtId = 0, pantsId = 0, backAccessoryId = 0 },
	{ id = "umbral_watcher", name = "Veilleur des Marches d'Ombre", style = "veilleur des ombres", garment = "umbral_watcher", shirtId = 0, pantsId = 0, backAccessoryId = 0 },
	{
		id = "midnight_traveler",
		name = "Voyageur de minuit",
		style = "voyageur",
		shirtId = 3267725621,
		pantsId = 3267727546,
		backAccessoryId = 878915975, -- "Cape of Midnight's Wisdom"
	},
	{
		id = "black_iron_knight",
		name = "Chevalier de fer noir",
		style = "chevalier",
		shirtId = 8991866831,
		pantsId = 8991863926,
		backAccessoryId = 2163546691, -- "Black Iron Cape"
	},
	{
		id = "oathbreaker",
		name = "Parjure",
		style = "noble déchu",
		shirtId = 560184638,
		pantsId = 560182503,
		backAccessoryId = 1772350677, -- "Sinister Cape"
	},
}

-- Familles de tenues médiévales voulues, à remplir avec des ID vérifiés (voir OUTFIT_OPTIONS).
local OUTFIT_WISHLIST: { { style: string, look: string } } = {
	{ style = "vagabond", look = "Haillons, ceinture de corde, capuchon élimé." },
	{ style = "aventurier", look = "Tunique de cuir, brassards, sacoche, cape courte." },
	{ style = "mage", look = "Robe longue brodée, ceinture à grimoire, capuche." },
	{ style = "noble", look = "Pourpoint, chemise à jabot, manteau doublé." },
	{ style = "chevalier", look = "Cotte de mailles, tabard, épaulières (complète le Chevalier de fer noir)." },
	{ style = "garde", look = "Gambison, tabard aux couleurs du village, cape." },
	{ style = "guérisseur / érudit", look = "Robe sobre, tablier à fioles ou étole." },
	{ style = "manteau de voyage", look = "Grand manteau à capuche, bottes hautes." },
	{ style = "elfique", look = "Tunique ajustée vert sombre, motifs de feuilles." },
	{ style = "naine", look = "Tablier de forge, cuir épais, fourrure." },
	{ style = "ombre", look = "Habits sombres déchirés, voile ou écharpe." },
}

-- Teints : du plus clair au plus foncé, puis deux teints surnaturels (Enfants de l'Ombre, mais
-- accessibles à tous). Le premier garde le teint de l'avatar Roblox : c'est celui des personnages
-- créés avant cette option (leur apparence ne change pas).
local SKIN_TONES: { SkinToneOption } = {
	{ id = "native", name = "Teint de votre avatar", color = nil },
	-- Les trois teints les plus clairs restent sous ~0,8 de luminance : plus haut, la lumière du
	-- créateur et le soleil les saturaient en blanc (visage et marques illisibles).
	{ id = "porcelain", name = "Porcelaine", color = Color3.fromRGB(224, 198, 180) },
	{ id = "fair", name = "Clair", color = Color3.fromRGB(220, 184, 158) },
	{ id = "rosy", name = "Rosé", color = Color3.fromRGB(216, 172, 150) },
	{ id = "olive", name = "Olivâtre", color = Color3.fromRGB(198, 160, 118) },
	{ id = "golden", name = "Doré", color = Color3.fromRGB(204, 150, 104) },
	{ id = "tan", name = "Hâlé", color = Color3.fromRGB(176, 124, 86) },
	{ id = "bronze", name = "Bronze", color = Color3.fromRGB(146, 98, 66) },
	{ id = "umber", name = "Brun", color = Color3.fromRGB(112, 74, 50) },
	{ id = "deep", name = "Ébène", color = Color3.fromRGB(78, 52, 38) },
	{ id = "ashen", name = "Cendre", color = Color3.fromRGB(158, 156, 162) },
	{ id = "dusk", name = "Crépuscule", color = Color3.fromRGB(118, 122, 150) },
}

-- Ornements : la liste suit GarmentLibrary.ORNAMENTS (le premier, « Aucun », est le défaut).
local ORNAMENT_OPTIONS: { OrnamentOption } = {}
for index, ornament in GarmentLibrary.ORNAMENTS do
	ORNAMENT_OPTIONS[index] = { id = ornament.id, name = ornament.name }
end

local HEIGHT_SCALE: ScaleRange = { min = 0.9, max = 1.15, step = 0.05, default = 1 }
local WIDTH_SCALE: ScaleRange = { min = 0.75, max = 1.1, step = 0.05, default = 1 }

return table.freeze({
	-- Attribut (boolean) posé par le serveur sur le Player tant qu'il est dans le Hub.
	-- Les interfaces de jeu (jauge de Tension...) le lisent pour se masquer.
	CUSTOMIZING_ATTRIBUTE = "IsCustomizing",

	-- Musique du créateur : voir AudioConfig.TRACKS.creator (Shared/Audio/AudioConfig).

	-- true = ignore la sauvegarde et rouvre le Hub à chaque connexion (pour le tester).
	-- Rien n'est effacé : repasser à false retrouve le personnage sauvegardé, ou le remplace
	-- par le nouveau si on a validé le Hub entre-temps.
	DEBUG_ALWAYS_OPEN_CREATOR = false,

	-- Panneau des marques : un carré invisible tenu devant le visage, sur lequel l'image est posée.
	FACE_CANVAS_SIZE = 1.25, -- côté du carré (studs) : la largeur visible de la tête classique
	-- Distance (studs) entre le centre de la tête et le panneau. Trop petit : la marque disparaît
	-- dans la tête. Trop grand : elle flotte devant le visage.
	FACE_CANVAS_DEPTH = 0.64,

	BASE_OPTIONS = BASE_OPTIONS,
	FACE_OPTIONS = FACE_OPTIONS,
	MARK_OPTIONS = MARK_OPTIONS,
	HAIR_OPTIONS = HAIR_OPTIONS,
	OUTFIT_OPTIONS = OUTFIT_OPTIONS,
	OUTFIT_WISHLIST = OUTFIT_WISHLIST,
	ORNAMENT_OPTIONS = ORNAMENT_OPTIONS,
	SKIN_TONES = SKIN_TONES,
	HEIGHT_SCALE = HEIGHT_SCALE, -- HumanoidDescription.HeightScale (BodyHeightScale)
	WIDTH_SCALE = WIDTH_SCALE, -- HumanoidDescription.WidthScale (BodyWidthScale)
})
