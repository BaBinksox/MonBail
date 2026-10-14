--!strict
--[[
	WorldMapConfig
	Contenu de la carte du monde (touche M) : les continents, leur place et leur histoire.

	>>> EMPLACEMENTS D'IMAGES. Tout est dessiné par code en attendant tes illustrations :
	>>>   - PARCHMENT_IMAGE : texture de fond du parchemin ;
	>>>   - `image` de chaque continent : sa silhouette sur la carte (remplace les taches de couleur) ;
	>>>   - `illustration` de chaque continent : la vignette affichée dans le panneau de droite.
	>>> Format : "rbxassetid://123456". Une chaîne vide = dessin par défaut.

	Positions et tailles sont des fractions de la zone de carte : (0, 0) = coin haut gauche,
	(1, 1) = coin bas droit.
]]

-- Une tache arrondie de la silhouette par défaut d'un continent, en fractions du cadre du continent.
export type Blob = {
	x: number, -- centre
	y: number,
	width: number,
	height: number,
	rotation: number, -- degrés
}

export type Continent = {
	id: string,
	name: string,
	epithet: string,
	lore: string,
	color: Color3,
	image: string,
	illustration: string,
	position: Vector2, -- centre du continent sur la carte
	size: Vector2,
	blobs: { Blob },
}

local function blob(x: number, y: number, width: number, height: number, rotation: number): Blob
	return { x = x, y = y, width = width, height = height, rotation = rotation }
end

local CONTINENTS: { Continent } = {
	{
		id = "demon",
		name = "Continent Démoniaque",
		epithet = "Les Terres Brûlées du Nord",
		lore = "Un désert de cendre sous un ciel sans étoiles. Les clans démons s'y disputent les ruines d'un empire que plus personne n'ose nommer. On dit que le temps lui-même y a été blessé.",
		color = Color3.fromRGB(122, 38, 42),
		image = "",
		illustration = "",
		position = Vector2.new(0.5, 0.19),
		size = Vector2.new(0.4, 0.26),
		blobs = {
			blob(0.35, 0.55, 0.6, 0.7, -8),
			blob(0.68, 0.45, 0.55, 0.6, 12),
			blob(0.5, 0.3, 0.45, 0.45, 0),
			blob(0.15, 0.4, 0.22, 0.3, 25),
		},
	},
	{
		id = "elf",
		name = "Continent Elfique",
		epithet = "La Forêt des Mille Murmures",
		lore = "Des arbres plus vieux que les royaumes, et un peuple qui n'oublie rien. Les elfes ferment leurs frontières depuis trois siècles : ceux qui entrent sans y être invités ressortent rarement.",
		color = Color3.fromRGB(58, 104, 72),
		image = "",
		illustration = "",
		position = Vector2.new(0.2, 0.55),
		size = Vector2.new(0.28, 0.4),
		blobs = {
			blob(0.5, 0.35, 0.7, 0.5, 10),
			blob(0.45, 0.68, 0.6, 0.5, -14),
			blob(0.72, 0.52, 0.4, 0.35, 0),
		},
	},
	{
		id = "dwarf",
		name = "Continent des Nains",
		epithet = "Les Monts de Fer-Profond",
		lore = "Une chaîne de montagnes creusée de part en part. Les forges des nains ne s'éteignent jamais ; leurs dettes non plus. Tout ce qui tranche, sur ce monde, est passé un jour entre leurs mains.",
		color = Color3.fromRGB(98, 102, 114),
		image = "",
		illustration = "",
		position = Vector2.new(0.82, 0.4),
		size = Vector2.new(0.26, 0.32),
		blobs = {
			blob(0.5, 0.4, 0.65, 0.6, -18),
			blob(0.55, 0.7, 0.5, 0.42, 8),
			blob(0.28, 0.6, 0.32, 0.3, 30),
		},
	},
	{
		id = "human",
		name = "Continent des Humains",
		epithet = "Les Royaumes du Centre",
		lore = "Des plaines fertiles, des villages serrés autour de leurs clochers, et des rois qui se croient éternels. C'est ici que vous avez ouvert les yeux. C'est ici, aussi, que vous êtes mort la première fois.",
		color = Color3.fromRGB(152, 114, 64),
		image = "",
		illustration = "",
		position = Vector2.new(0.52, 0.6),
		size = Vector2.new(0.3, 0.3),
		blobs = {
			blob(0.45, 0.5, 0.7, 0.62, 6),
			blob(0.7, 0.38, 0.42, 0.42, -20),
			blob(0.3, 0.72, 0.4, 0.34, 15),
		},
	},
	{
		id = "beast",
		name = "Continent des Semi-humains",
		epithet = "L'Archipel des Crocs",
		lore = "Mille îles et autant de tribus : hommes-loups, enfants du renard, peuples-chats. Vendus comme esclaves pendant des siècles, ils n'accordent plus leur confiance à personne, et ils ont de bonnes raisons.",
		color = Color3.fromRGB(160, 96, 50),
		image = "",
		illustration = "",
		position = Vector2.new(0.74, 0.83),
		size = Vector2.new(0.34, 0.22),
		blobs = {
			blob(0.25, 0.5, 0.36, 0.6, -10),
			blob(0.56, 0.42, 0.3, 0.5, 20),
			blob(0.82, 0.6, 0.26, 0.44, -6),
			blob(0.42, 0.82, 0.16, 0.24, 0),
		},
	},
}

return table.freeze({
	TOGGLE_KEY = Enum.KeyCode.M,
	TITLE = "CARTE DU MONDE CONNU",
	PARCHMENT_IMAGE = "",
	-- Continent où se trouve le joueur : marqué "Vous êtes ici" et sélectionné à l'ouverture.
	CURRENT_CONTINENT_ID = "human",
	CONTINENTS = CONTINENTS,
	-- Noms des mers, écrits en travers de la carte (position en fractions, rotation en degrés).
	SEAS = {
		{ name = "Mer des Soupirs", position = Vector2.new(0.33, 0.33), rotation = -12 },
		{ name = "Détroit du Parjure", position = Vector2.new(0.68, 0.6), rotation = 62 },
		{ name = "Océan Sans Rivage", position = Vector2.new(0.3, 0.9), rotation = 4 },
	},
})
