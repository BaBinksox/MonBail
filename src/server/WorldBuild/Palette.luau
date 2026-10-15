--!strict
--[[
	Palette
	Couleurs et matériaux nommés de la Région 1 (dark fantasy mélancolique).

	Règles de la direction artistique :
		- base : pierre charbon et ardoise, bois brûlé et noirci, cendre gris clair, mousses éteintes, rouille ;
		- accents CHAUDS (orange ambré) : lanternes, braises, fenêtres encore éclairées ;
		- accents FROIDS (cyan pâle, Neon translucide) : RÉSERVÉS à ce qui touche au temps
		  (runes, ancre temporelle, horloges, échos). Ne pas en mettre ailleurs.

	Un "Look" = { color, material } : c'est ce que prennent toutes les fonctions du Kit et des Props.
	Les couleurs seules sont dans Palette.colors (lumières, textes, particules), les matériaux de
	terrain dans Palette.terrain.
]]

export type Look = {
	color: Color3,
	material: Enum.Material,
}

local function look(r: number, g: number, b: number, material: Enum.Material): Look
	return table.freeze({ color = Color3.fromRGB(r, g, b), material = material })
end

local M = Enum.Material

local Palette = {
	----------------------------------------------------------------------------
	-- Pierre
	----------------------------------------------------------------------------
	stoneDark = look(52, 53, 58, M.Slate), -- charbon : soubassements, ombres
	stone = look(84, 86, 92, M.Slate), -- ardoise : murs de pierre
	stoneLight = look(118, 116, 112, M.Cobblestone), -- pierre claire usée : marches, margelles
	cobble = look(92, 89, 86, M.Cobblestone),
	granite = look(76, 76, 82, M.Granite), -- statues, monuments
	basalt = look(40, 40, 45, M.Basalt), -- pierre noire : crypte, cercle du gardien
	rock = look(70, 68, 66, M.Rock), -- rochers
	rockMossy = look(66, 72, 60, M.Rock),
	brick = look(92, 62, 52, M.Brick), -- brique brûlée
	brickDark = look(62, 46, 42, M.Brick),
	plaster = look(150, 142, 128, M.Concrete), -- torchis encore clair
	plasterSooty = look(104, 98, 90, M.Concrete), -- torchis noirci par la fumée
	plasterBurnt = look(70, 64, 60, M.Concrete),
	marble = look(150, 150, 154, M.Granite), -- dalles de chapelle, effigies

	----------------------------------------------------------------------------
	-- Bois
	----------------------------------------------------------------------------
	charredWood = look(36, 31, 28, M.Wood), -- calciné
	burntWood = look(58, 46, 38, M.WoodPlanks), -- planches noircies
	oldWood = look(88, 70, 54, M.WoodPlanks), -- bois épargné, grisé
	timber = look(46, 37, 31, M.Wood), -- poutres des colombages
	paleWood = look(112, 98, 82, M.WoodPlanks), -- bois neuf (rare : tableaux, mannequins)
	deadTree = look(84, 78, 72, M.Wood), -- arbres morts (écorce grise)
	deadTreeDark = look(54, 48, 44, M.Wood),

	----------------------------------------------------------------------------
	-- Toits
	----------------------------------------------------------------------------
	roofSlate = look(46, 48, 54, M.Slate),
	roofShingle = look(66, 52, 44, M.WoodPlanks),
	roofBurnt = look(40, 34, 32, M.WoodPlanks),

	----------------------------------------------------------------------------
	-- Métal
	----------------------------------------------------------------------------
	iron = look(50, 50, 54, M.Metal),
	rust = look(110, 62, 40, M.CorrodedMetal),
	bronze = look(112, 92, 60, M.CorrodedMetal), -- cloche, battant, statue de l'Horloger
	bronzeDark = look(78, 70, 52, M.CorrodedMetal),

	----------------------------------------------------------------------------
	-- Sols, cendres, végétation éteinte
	----------------------------------------------------------------------------
	ash = look(168, 166, 160, M.Concrete), -- cendre gris clair
	ashDark = look(110, 108, 104, M.Concrete),
	soot = look(30, 29, 30, M.Concrete),
	dirt = look(72, 60, 48, M.Concrete),
	moss = look(68, 78, 58, M.Fabric), -- mousse éteinte
	deadGrass = look(104, 96, 70, M.Fabric),
	straw = look(150, 130, 84, M.Fabric),
	bone = look(196, 188, 168, M.Concrete),

	----------------------------------------------------------------------------
	-- Tissus et papier
	----------------------------------------------------------------------------
	cloth = look(170, 160, 140, M.Fabric), -- linge
	clothDark = look(52, 48, 54, M.Fabric),
	banner = look(104, 30, 36, M.Fabric), -- bannières (rouge sombre)
	bannerBlue = look(38, 50, 84, M.Fabric),
	paper = look(196, 184, 152, M.Fabric), -- affiches, pages
	wax = look(222, 212, 186, M.Concrete), -- bougies

	----------------------------------------------------------------------------
	-- Accents lumineux
	----------------------------------------------------------------------------
	ember = look(255, 128, 44, M.Neon), -- braises vives
	emberDim = look(150, 60, 28, M.Neon), -- braises mourantes
	lanternGlow = look(255, 176, 96, M.Neon), -- verre de lanterne, fenêtres éclairées
	candleFlame = look(255, 196, 120, M.Neon),
	coldFlame = look(196, 210, 232, M.Neon), -- flammes froides de la crypte (blanc acier, PAS le cyan du temps)
	temporalCyan = look(120, 230, 255, M.Neon), -- LE TEMPS : runes actives, horloges, ancres
	temporalCyanDim = look(52, 112, 128, M.Neon), -- runes éteintes
	temporalInlay = look(64, 96, 104, M.Slate), -- incrustation de pierre teintée (sols, cercles) : pas de lueur
	curseViolet = look(140, 70, 210, M.ForceField), -- voile maudit
	curseGlyph = look(150, 84, 220, M.Neon), -- glyphes de la malédiction (socle du voile)
	stainedBlue = look(54, 74, 130, M.Glass), -- vitraux
	stainedRed = look(120, 40, 44, M.Glass),
	stainedAmber = look(150, 104, 44, M.Glass),
	ice = look(170, 210, 230, M.Ice),
	darkWater = look(26, 34, 40, M.Glass), -- eau croupie (abreuvoirs, bassins)
	void = look(12, 12, 14, M.Concrete), -- noir profond (fond de puits, intérieur de sarcophage)

	----------------------------------------------------------------------------
	-- Couleurs seules (lumières, textes, particules)
	----------------------------------------------------------------------------
	colors = table.freeze({
		warmLight = Color3.fromRGB(255, 168, 96),
		emberLight = Color3.fromRGB(255, 118, 48),
		candleLight = Color3.fromRGB(255, 190, 120),
		coldLight = Color3.fromRGB(165, 196, 235), -- crypte
		temporalLight = Color3.fromRGB(120, 220, 255),
		curseLight = Color3.fromRGB(160, 90, 225),
		ink = Color3.fromRGB(28, 22, 20),
		chalk = Color3.fromRGB(214, 206, 190),
		blood = Color3.fromRGB(120, 24, 24),
		smoke = Color3.fromRGB(60, 58, 58),
	}),

	----------------------------------------------------------------------------
	-- Matériaux de terrain
	----------------------------------------------------------------------------
	terrain = table.freeze({
		air = M.Air,
		ground = M.Ground,
		mud = M.Mud,
		grass = M.Grass,
		leafyGrass = M.LeafyGrass,
		rock = M.Rock,
		slate = M.Slate,
		basalt = M.Basalt,
		cobble = M.Cobblestone,
		water = M.Water,
	}),
}

-- Variante d'un look avec une autre couleur (même matériau).
function Palette.tint(base: Look, color: Color3): Look
	return table.freeze({ color = color, material = base.material })
end

-- Variante d'un look assombrie (factor 0..1 : 0 = noir, 1 = inchangé).
function Palette.darken(base: Look, factor: number): Look
	local c = base.color
	return table.freeze({ color = Color3.new(c.R * factor, c.G * factor, c.B * factor), material = base.material })
end

-- Mélange de deux looks (couleur interpolée, matériau du premier).
function Palette.mix(a: Look, b: Look, t: number): Look
	return table.freeze({ color = a.color:Lerp(b.color, t), material = a.material })
end

return table.freeze(Palette)
