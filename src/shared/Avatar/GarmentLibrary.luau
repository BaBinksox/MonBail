--!strict
--[[
	GarmentLibrary
	Vêtements et ornements FABRIQUÉS dans le jeu, sans asset externe : partagé serveur (CostumeBuilder
	les pose sur les personnages et les PNJ) + client (fiches et vignettes du créateur).

	Un vêtement se compose de deux couches :
		dye     teinture des membres du corps R15 : la couleur ET la matière (tissu, cuir, métal) des
		        parties du corps, comme une étoffe ajustée. Clés : UpperTorso, LowerTorso, UpperArm,
		        LowerArm, Hand, UpperLeg, LowerLeg, Foot (gauche et droite ensemble). Une partie absente
		        garde la peau (mains, tête) ;
		pieces  pièces sculptées soudées aux membres (pourpoint, cape, plastron, épaulières, ceinture,
		        pans de tunique...). Elles suivent les animations, ne pèsent rien, ne touchent rien.

	Dimensions d'une pièce : en FRACTION de la taille de la partie du corps qui la porte (`attach`) ;
	elles suivent donc la taille et la carrure de chaque peuple. Exceptions :
		yRef     la hauteur et le décalage vertical se mesurent sur une autre partie (ex. les pans de
		         tunique, portés par LowerTorso, se mesurent en longueur de cuisse : « LeftUpperLeg ») ;
		studs    dimensions en studs (ornements de tête : la tête classique a une taille fixe) ;
		children pièces posées sur la pièce elle-même, en fraction de SA taille (liserés, boucles).
	Repère : X vers la droite du personnage, Y vers le haut, Z vers l'ARRIÈRE (-Z = devant).
	Rotation : degrés. Autour de X : négatif = le bas part vers l'arrière (cape).
	Formes : "block", "wedge" (coin), "ellipsoid", "cylinder" (axe vertical).

	Ajouter une tenue : une entrée dans GARMENTS, puis une ligne dans AvatarConfig.OUTFIT_OPTIONS
	(champ `garment`). Aucune pièce ne descend sous la plante des pieds (vérifié par les tests).
]]

export type Shape = "block" | "wedge" | "ellipsoid" | "cylinder"

export type Piece = {
	attach: string,
	shape: Shape,
	size: Vector3,
	offset: Vector3,
	rotation: Vector3?,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	yRef: string?,
	studs: boolean?,
	children: { Piece }?,
}

export type DyeLayer = { color: Color3, material: Enum.Material }

export type Garment = {
	id: string,
	name: string,
	people: string?, -- peuple d'inspiration (RaceConfig id), ou nil ; tous les peuples peuvent le porter
	style: string,
	description: string,
	swatches: { Color3 }, -- couleurs principales (vignette du créateur)
	dye: { [string]: DyeLayer },
	pieces: { Piece },
}

export type Ornament = {
	id: string,
	name: string,
	description: string,
	swatches: { Color3 },
	pieces: { Piece },
}

--------------------------------------------------------------------------------
-- Matières et couleurs
--------------------------------------------------------------------------------

local FABRIC = Enum.Material.Fabric
local LEATHER = Enum.Material.Leather
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood

local C = {
	-- Royaumes des Cendres (humains)
	nightBlue = Color3.fromRGB(54, 66, 108),
	brickRed = Color3.fromRGB(128, 48, 40),
	ivory = Color3.fromRGB(222, 210, 186),
	leather = Color3.fromRGB(132, 90, 56),
	darkLeather = Color3.fromRGB(76, 54, 40),
	trousers = Color3.fromRGB(96, 76, 60),
	bootLeather = Color3.fromRGB(72, 52, 40),
	foldLeather = Color3.fromRGB(150, 108, 70),
	oldGold = Color3.fromRGB(172, 140, 78),
	steel = Color3.fromRGB(140, 144, 152),
	-- Forêts d'Ellendor (elfes)
	forest = Color3.fromRGB(58, 110, 80),
	offWhite = Color3.fromRGB(230, 226, 212),
	mist = Color3.fromRGB(126, 142, 160),
	mistBlue = Color3.fromRGB(118, 144, 168),
	sageSilver = Color3.fromRGB(178, 194, 178),
	paleGold = Color3.fromRGB(214, 192, 128),
	silver = Color3.fromRGB(190, 196, 204),
	softLeather = Color3.fromRGB(146, 114, 80),
	bark = Color3.fromRGB(112, 84, 58),
	-- Monts de Brasegrise (nains)
	rust = Color3.fromRGB(116, 74, 46),
	copper = Color3.fromRGB(176, 106, 62),
	bronze = Color3.fromRGB(150, 110, 60),
	darkSteel = Color3.fromRGB(78, 80, 88),
	fur = Color3.fromRGB(156, 124, 92),
	apron = Color3.fromRGB(98, 68, 46),
	dwarfTrousers = Color3.fromRGB(72, 54, 42),
	-- Marches d'Ombre (Enfants de l'Ombre)
	charcoal = Color3.fromRGB(60, 56, 70),
	plum = Color3.fromRGB(98, 64, 106),
	deepPlum = Color3.fromRGB(78, 54, 88),
	nightCloth = Color3.fromRGB(50, 56, 86),
	blackLeather = Color3.fromRGB(42, 40, 48),
	violet = Color3.fromRGB(96, 78, 122),
	moonSilver = Color3.fromRGB(176, 180, 192),
	-- Village (PNJ)
	soot = Color3.fromRGB(112, 100, 90),
	scholarNavy = Color3.fromRGB(52, 62, 104),
	bookRed = Color3.fromRGB(110, 40, 36),
	parchment = Color3.fromRGB(226, 214, 180),
}

--------------------------------------------------------------------------------
-- Raccourcis
--------------------------------------------------------------------------------

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function piece(attach: string, shape: Shape, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, rotation: Vector3?, extra: { [string]: any }?): Piece
	local result: Piece = { attach = attach, shape = shape, size = size, offset = offset, color = color, material = material, rotation = rotation }
	if extra then
		for key, value in extra do
			(result :: any)[key] = value
		end
	end
	return result
end

-- Copie en miroir gauche/droite d'une pièce et de ses pièces enfants (X et rotations Y/Z inversés).
local function mirrorPiece(source: Piece, attach: string): Piece
	local rot = source.rotation or Vector3.zero
	local copy = table.clone(source)
	copy.attach = attach
	copy.offset = v(-source.offset.X, source.offset.Y, source.offset.Z)
	copy.rotation = v(rot.X, -rot.Y, -rot.Z)
	local children = source.children
	if children then
		local mirroredChildren: { Piece } = {}
		for index, child in children do
			mirroredChildren[index] = mirrorPiece(child, child.attach)
		end
		copy.children = mirroredChildren
	end
	return copy
end

-- Même pièce sur le membre gauche et le membre droit (X et rotations Y/Z en miroir).
-- `limb` : "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot".
local function pair(limb: string, shape: Shape, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, rotation: Vector3?, extra: { [string]: any }?): { Piece }
	local right = piece("Right" .. limb, shape, size, offset, color, material, rotation, extra)
	return { right, mirrorPiece(right, "Left" .. limb) }
end

-- Même pièce posée symétriquement sur une partie centrale (pans de manteau, clous...).
local function mirrored(attach: string, shape: Shape, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, rotation: Vector3?, extra: { [string]: any }?): { Piece }
	local right = piece(attach, shape, size, offset, color, material, rotation, extra)
	return { right, mirrorPiece(right, attach) }
end

local function concat(...: { Piece }): { Piece }
	local list: { Piece } = {}
	for _, group in { ... } do
		for _, item in group do
			table.insert(list, item)
		end
	end
	return list
end

local THIGH = "LeftUpperLeg" -- longueur de cuisse : mesure des pans qui pendent sous la ceinture

-- Liseré au bas d'une pièce (fraction de la pièce porteuse).
local function hem(color: Color3, material: Enum.Material?): Piece
	return piece("", "block", v(1.02, 0.06, 1.25), v(0, -0.47, 0), color, material or FABRIC)
end

--------------------------------------------------------------------------------
-- Tenues des joueurs
--------------------------------------------------------------------------------

local GARMENTS: { Garment } = {
	{
		id = "ash_adventurer",
		name = "Aventurier des Cendres",
		people = "human",
		style = "aventurier",
		description = "Pourpoint de cuir sur tunique de laine bleu nuit, capuche rabattue et cape courte rouge brique, besace, brassards. La tenue de ceux qui partent quand le village s'arrête.",
		swatches = { C.nightBlue, C.leather, C.brickRed, C.ivory },
		dye = {
			UpperTorso = { color = C.nightBlue, material = FABRIC },
			LowerTorso = { color = C.leather, material = LEATHER },
			UpperArm = { color = C.nightBlue, material = FABRIC },
			LowerArm = { color = C.ivory, material = FABRIC },
			UpperLeg = { color = C.trousers, material = FABRIC },
			LowerLeg = { color = C.bootLeather, material = LEATHER },
			Foot = { color = C.bootLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Chemise de lin lacée, visible dans l'ouverture du pourpoint ; dos du pourpoint ; col.
				piece("UpperTorso", "block", v(0.2, 0.62, 0.05), v(0, 0.16, -0.52), C.ivory, FABRIC, nil, {
					children = {
						piece("", "block", v(0.7, 0.04, 1.3), v(0, 0.25, 0), C.darkLeather, LEATHER),
						piece("", "block", v(0.7, 0.04, 1.3), v(0, 0, 0), C.darkLeather, LEATHER),
						piece("", "block", v(0.7, 0.04, 1.3), v(0, -0.25, 0), C.darkLeather, LEATHER),
					},
				}),
				piece("UpperTorso", "block", v(0.94, 0.9, 0.07), v(0, -0.04, 0.535), C.leather, LEATHER),
				piece("UpperTorso", "ellipsoid", v(0.6, 0.16, 0.7), v(0, 0.5, -0.06), C.ivory, FABRIC),
				-- Capuche rabattue sur les épaules.
				piece("UpperTorso", "ellipsoid", v(0.84, 0.34, 0.5), v(0, 0.46, 0.42), C.brickRed, FABRIC),
				-- Cape courte en deux pans (épaules -> taille, taille -> genou) : elle suit le buste sans
				-- traverser les jambes.
				piece("UpperTorso", "block", v(1.08, 0.95, 0.05), v(0, -0.05, 0.6), C.brickRed, FABRIC, v(-4, 0, 0)),
				piece("LowerTorso", "block", v(1.06, 1.05, 0.05), v(0, -0.42, 0.68), C.brickRed, FABRIC, v(-8, 0, 0), { yRef = THIGH, children = { hem(C.oldGold) } }),
				-- Ceinture, boucle, bandoulière, besace et bourse.
				piece("LowerTorso", "block", v(1.06, 0.55, 1.08), v(0, 0.15, 0), C.darkLeather, LEATHER),
				piece("LowerTorso", "block", v(0.16, 0.42, 0.05), v(0, 0.15, -0.56), C.oldGold, METAL),
				piece("UpperTorso", "block", v(0.1, 1.28, 1.2), v(0, -0.04, 0), C.darkLeather, LEATHER, v(0, 0, 36)),
				piece("LowerTorso", "block", v(0.18, 0.42, 0.52), v(0.6, -0.22, 0.04), C.leather, LEATHER, nil, {
					yRef = THIGH,
					children = { piece("", "block", v(1.08, 0.4, 1.06), v(0, 0.32, 0), C.foldLeather, LEATHER) },
				}),
				piece("LowerTorso", "block", v(0.14, 0.22, 0.28), v(-0.42, -0.12, -0.5), C.foldLeather, LEATHER, nil, { yRef = THIGH }),
				-- Épaulière de cuir à gauche (allure de voyageur, asymétrique).
				piece("LeftUpperArm", "ellipsoid", v(1.34, 0.48, 1.34), v(0, 0.4, 0), C.leather, LEATHER),
			},
			-- Pourpoint ouvert : deux pans de cuir de part et d'autre de la chemise, avec leurs flancs.
			mirrored("UpperTorso", "block", v(0.4, 0.9, 0.07), v(0.3, -0.04, -0.535), C.leather, LEATHER, nil, {
				children = { piece("", "block", v(0.1, 1, 1.1), v(-0.45, 0, 0), C.foldLeather, LEATHER) },
			}),
			mirrored("UpperTorso", "block", v(0.07, 0.9, 1.06), v(0.535, -0.04, 0), C.leather, LEATHER),
			pair("LowerArm", "block", v(1.12, 0.55, 1.12), v(0, -0.1, 0), C.leather, LEATHER),
			pair("LowerLeg", "block", v(1.14, 0.16, 1.16), v(0, 0.36, 0), C.foldLeather, LEATHER)
		),
	},
	{
		id = "ellendor_warden",
		name = "Veilleur d'Ellendor",
		people = "elf",
		style = "voyageur des forêts",
		description = "Tunique longue vert profond aux pans fendus, mantelet argenté liseré d'or pâle, cape de brume légère, broche en feuille et brassards de bois clair.",
		swatches = { C.forest, C.sageSilver, C.mistBlue, C.paleGold },
		dye = {
			UpperTorso = { color = C.forest, material = FABRIC },
			LowerTorso = { color = C.forest, material = FABRIC },
			UpperArm = { color = C.offWhite, material = FABRIC },
			LowerArm = { color = C.offWhite, material = FABRIC },
			UpperLeg = { color = C.mist, material = FABRIC },
			LowerLeg = { color = C.softLeather, material = LEATHER },
			Foot = { color = C.softLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Mantelet sur les épaules et son liseré.
				piece("UpperTorso", "ellipsoid", v(1.34, 0.42, 1.22), v(0, 0.4, 0), C.sageSilver, FABRIC),
				piece("UpperTorso", "ellipsoid", v(1.38, 0.07, 1.26), v(0, 0.26, 0), C.paleGold, FABRIC),
				-- Écharpe d'argent en diagonale sur la poitrine.
				piece("UpperTorso", "block", v(0.12, 1.2, 1.12), v(0, -0.08, 0), C.silver, FABRIC, v(0, 0, -34)),
				-- Broche en feuille (deux coins tête-bêche).
				piece("UpperTorso", "wedge", v(0.1, 0.12, 0.05), v(-0.24, 0.16, -0.555), C.paleGold, METAL),
				piece("UpperTorso", "wedge", v(0.1, 0.12, 0.05), v(-0.24, 0.04, -0.555), C.paleGold, METAL, v(0, 0, 180)),
				-- Ceinture d'argent.
				piece("LowerTorso", "block", v(1.04, 0.36, 1.06), v(0, 0.28, 0), C.silver, FABRIC),
				-- Pans de la tunique : devant, dos, côtés, légèrement évasés, jusqu'au genou.
				piece("LowerTorso", "block", v(0.58, 1.62, 0.05), v(0, -0.66, -0.56), C.forest, FABRIC, v(4, 0, 0), { yRef = THIGH, children = { hem(C.paleGold) } }),
				piece("LowerTorso", "block", v(0.66, 1.68, 0.05), v(0, -0.68, 0.56), C.forest, FABRIC, v(-4, 0, 0), { yRef = THIGH, children = { hem(C.paleGold) } }),
				-- Cape de brume, légère et un peu translucide.
				piece("UpperTorso", "block", v(0.9, 0.95, 0.04), v(0, -0.05, 0.6), C.mistBlue, FABRIC, v(-3, 0, 0), { transparency = 0.1 }),
				piece("LowerTorso", "block", v(0.88, 1.45, 0.04), v(0, -0.6, 0.68), C.mistBlue, FABRIC, v(-6, 0, 0), { yRef = THIGH, transparency = 0.1, children = { hem(C.sageSilver) } }),
			},
			mirrored("LowerTorso", "block", v(0.05, 1.4, 0.46), v(0.53, -0.55, 0), C.forest, FABRIC, v(0, 0, 5), { yRef = THIGH, children = { hem(C.paleGold) } }),
			pair("LowerArm", "block", v(1.1, 0.48, 1.1), v(0, -0.12, 0), C.bark, WOOD, nil, {
				children = { piece("", "block", v(1.04, 0.14, 1.04), v(0, 0.5, 0), C.silver, METAL) },
			}),
			pair("LowerLeg", "block", v(1.12, 0.13, 1.14), v(0, 0.4, 0), C.bark, LEATHER)
		),
	},
	{
		id = "brasegrise_smith",
		name = "Forgeron de Brasegrise",
		people = "dwarf",
		style = "artisan des montagnes",
		description = "Plastron de cuivre gravé, larges épaulières, col de fourrure, grosse ceinture à boucle d'or, tablier de forge, gantelets et bottes cloutées. Compact, solide, fait pour durer.",
		swatches = { C.copper, C.rust, C.darkSteel, C.fur },
		dye = {
			UpperTorso = { color = C.rust, material = FABRIC },
			LowerTorso = { color = C.darkLeather, material = LEATHER },
			UpperArm = { color = C.rust, material = FABRIC },
			LowerArm = { color = C.rust, material = FABRIC },
			UpperLeg = { color = C.dwarfTrousers, material = FABRIC },
			LowerLeg = { color = C.bootLeather, material = LEATHER },
			Foot = { color = C.bootLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Plastron, arête centrale, bandes gravées, dossière.
				piece("UpperTorso", "block", v(0.94, 0.72, 0.1), v(0, 0.06, -0.55), C.copper, METAL, nil, {
					children = {
						piece("", "block", v(0.1, 0.96, 1.4), v(0, 0, -0.2), C.darkSteel, METAL),
						piece("", "block", v(1.01, 0.07, 1.1), v(0, 0.33, 0), C.bronze, METAL),
						piece("", "block", v(1.01, 0.07, 1.1), v(0, -0.33, 0), C.bronze, METAL),
					},
				}),
				piece("UpperTorso", "block", v(0.94, 0.72, 0.08), v(0, 0.06, 0.54), C.copper, METAL),
				-- Col de fourrure.
				piece("UpperTorso", "ellipsoid", v(1.12, 0.34, 1.16), v(0, 0.47, 0), C.fur, FABRIC),
				-- Grosse ceinture et sa boucle.
				piece("LowerTorso", "block", v(1.1, 0.9, 1.12), v(0, 0.1, 0), Color3.fromRGB(70, 50, 36), LEATHER),
				piece("LowerTorso", "block", v(0.34, 0.76, 0.06), v(0, 0.1, -0.6), C.oldGold, METAL, nil, {
					children = { piece("", "block", v(0.55, 0.55, 1.2), v(0, 0, -0.1), C.darkSteel, METAL) },
				}),
				-- Tablier de forge (au-dessus du genou) et marteau à la ceinture.
				piece("LowerTorso", "block", v(0.78, 0.92, 0.06), v(0, -0.44, -0.6), C.apron, LEATHER, v(3, 0, 0), { yRef = THIGH }),
				piece("LowerTorso", "cylinder", v(0.05, 0.42, 0.06), v(0.6, -0.2, 0.18), C.bark, WOOD, nil, {
					yRef = THIGH,
					children = { piece("", "block", v(3.2, 0.24, 2.2), v(0, 0.5, 0), C.darkSteel, METAL) },
				}),
			},
			-- Épaulières et leur bordure.
			pair("UpperArm", "ellipsoid", v(1.5, 0.5, 1.5), v(0, 0.3, 0), C.copper, METAL),
			pair("UpperArm", "ellipsoid", v(1.56, 0.1, 1.56), v(0, 0.16, 0), C.darkSteel, METAL),
			-- Gantelets.
			pair("LowerArm", "block", v(1.22, 0.62, 1.22), v(0, -0.18, 0), C.darkSteel, METAL, nil, {
				children = { piece("", "ellipsoid", v(1.08, 0.3, 1.08), v(0, 0.52, 0), C.steel, METAL) },
			}),
			-- Bottes lourdes : tige, revers de fourrure, coque d'acier sur l'orteil (au-dessus de la semelle).
			pair("LowerLeg", "block", v(1.2, 0.62, 1.22), v(0, -0.2, 0), C.bootLeather, LEATHER, nil, {
				children = { piece("", "block", v(1.05, 0.22, 1.05), v(0, 0.55, 0), C.fur, FABRIC) },
			}),
			pair("Foot", "block", v(0.9, 0.55, 0.3), v(0, 0.05, -0.4), C.darkSteel, METAL)
		),
	},
	{
		id = "umbral_watcher",
		name = "Veilleur des Marches d'Ombre",
		people = "shadowborn",
		style = "veilleur des ombres",
		description = "Long manteau charbon ouvert sur un gilet prune, col haut, capuche rabattue, liserés et fermoirs d'argent, ceinture violette et pans fendus. Élégant, sobre, le visage toujours découvert.",
		swatches = { C.charcoal, C.plum, C.moonSilver, C.violet },
		dye = {
			UpperTorso = { color = C.plum, material = FABRIC },
			LowerTorso = { color = C.charcoal, material = FABRIC },
			UpperArm = { color = C.charcoal, material = FABRIC },
			LowerArm = { color = C.charcoal, material = FABRIC },
			UpperLeg = { color = C.nightCloth, material = FABRIC },
			LowerLeg = { color = C.blackLeather, material = LEATHER },
			Foot = { color = C.blackLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Dos et flancs du manteau.
				piece("UpperTorso", "block", v(0.98, 0.96, 0.07), v(0, -0.02, 0.535), C.charcoal, FABRIC),
				-- Capuche rabattue.
				piece("UpperTorso", "ellipsoid", v(0.88, 0.36, 0.52), v(0, 0.47, 0.42), C.deepPlum, FABRIC),
				-- Chaînette d'argent entre les deux fermoirs.
				piece("UpperTorso", "block", v(0.32, 0.025, 0.03), v(0, 0.3, -0.59), C.moonSilver, METAL),
				-- Ceinture violette et son pan qui retombe.
				piece("LowerTorso", "block", v(1.06, 0.6, 1.08), v(0, 0.15, 0), C.violet, FABRIC),
				piece("LowerTorso", "block", v(0.13, 0.55, 0.05), v(-0.3, -0.24, -0.58), C.violet, FABRIC, v(0, 0, -6), { yRef = THIGH }),
			},
			-- Devant du manteau ouvert (gilet prune visible au centre), liserés d'argent.
			mirrored("UpperTorso", "block", v(0.36, 0.96, 0.07), v(0.3, -0.02, -0.535), C.charcoal, FABRIC, nil, {
				children = { piece("", "block", v(0.16, 1, 1.1), v(-0.42, 0, 0), C.moonSilver, METAL) },
			}),
			mirrored("UpperTorso", "block", v(0.07, 0.96, 1.04), v(0.535, -0.02, 0), C.charcoal, FABRIC),
			-- Col haut.
			mirrored("UpperTorso", "block", v(0.1, 0.32, 0.55), v(0.3, 0.6, 0.08), C.charcoal, FABRIC, v(0, 0, -8)),
			-- Fermoirs d'argent.
			mirrored("UpperTorso", "ellipsoid", v(0.1, 0.1, 0.06), v(0.16, 0.3, -0.58), C.moonSilver, METAL),
			-- Pans du manteau : deux derrière (sous le genou), deux devant, liserés d'argent.
			mirrored("LowerTorso", "block", v(0.47, 1.6, 0.05), v(0.25, -0.66, 0.62), C.charcoal, FABRIC, v(-6, 0, 3), { yRef = THIGH, children = { hem(C.moonSilver, METAL) } }),
			mirrored("LowerTorso", "block", v(0.36, 1.32, 0.05), v(0.32, -0.54, -0.6), C.charcoal, FABRIC, v(5, 0, 4), { yRef = THIGH, children = { hem(C.moonSilver, METAL) } }),
			-- Revers d'argent aux poignets.
			pair("LowerArm", "block", v(1.1, 0.1, 1.1), v(0, -0.38, 0), C.moonSilver, METAL)
		),
	},
}

--------------------------------------------------------------------------------
-- Costumes des PNJ (utilisés par NpcConfig : look.garment)
--------------------------------------------------------------------------------

local NPC_GARMENTS: { Garment } = {
	{
		id = "village_smith",
		name = "Forgeron du village",
		style = "forgeron",
		description = "Chemise noircie aux manches retroussées, grand tablier de cuir, gants de forge, ceinture à outils.",
		swatches = { C.soot, C.leather, C.darkLeather },
		dye = {
			UpperTorso = { color = C.soot, material = FABRIC },
			LowerTorso = { color = C.darkLeather, material = LEATHER },
			UpperArm = { color = C.soot, material = FABRIC },
			-- Avant-bras nus (manches retroussées) : peau.
			UpperLeg = { color = C.trousers, material = FABRIC },
			LowerLeg = { color = C.bootLeather, material = LEATHER },
			Foot = { color = C.bootLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Bavette et jupe du tablier, sangles croisées dans le dos.
				piece("UpperTorso", "block", v(0.78, 0.82, 0.07), v(0, -0.06, -0.54), C.leather, LEATHER),
				piece("LowerTorso", "block", v(0.86, 1.02, 0.07), v(0, -0.42, -0.58), C.leather, LEATHER, v(3, 0, 0), { yRef = THIGH }),
				piece("UpperTorso", "block", v(0.1, 1.1, 0.05), v(0, 0, 0.54), C.darkLeather, LEATHER, v(0, 0, 30)),
				piece("UpperTorso", "block", v(0.1, 1.1, 0.05), v(0, 0, 0.54), C.darkLeather, LEATHER, v(0, 0, -30)),
				-- Ceinture à outils, marteau, pinces.
				piece("LowerTorso", "block", v(1.06, 0.6, 1.08), v(0, 0.15, 0), C.darkLeather, LEATHER),
				piece("LowerTorso", "cylinder", v(0.05, 0.42, 0.06), v(0.6, -0.2, 0.15), C.bark, WOOD, nil, {
					yRef = THIGH,
					children = { piece("", "block", v(3.2, 0.24, 2.2), v(0, 0.5, 0), C.darkSteel, METAL) },
				}),
				piece("LowerTorso", "block", v(0.04, 0.45, 0.05), v(-0.58, -0.2, 0.05), C.darkSteel, METAL, v(0, 0, 8), { yRef = THIGH }),
			},
			-- Manches retroussées.
			pair("UpperArm", "ellipsoid", v(1.18, 0.24, 1.18), v(0, -0.42, 0), C.soot, FABRIC),
			-- Gants de forge et leurs manchettes.
			pair("Hand", "block", v(1.12, 1.08, 1.12), v(0, 0, 0), C.darkLeather, LEATHER),
			pair("LowerArm", "block", v(1.16, 0.32, 1.16), v(0, -0.36, 0), C.darkLeather, LEATHER)
		),
	},
	{
		id = "village_archivist",
		name = "Archiviste",
		style = "érudit",
		description = "Longue robe bleu de nuit, étole d'or, larges manches, cordelière, livre et étui à parchemins.",
		swatches = { C.scholarNavy, C.oldGold, C.parchment },
		dye = {
			UpperTorso = { color = C.scholarNavy, material = FABRIC },
			LowerTorso = { color = C.scholarNavy, material = FABRIC },
			UpperArm = { color = C.scholarNavy, material = FABRIC },
			LowerArm = { color = C.scholarNavy, material = FABRIC },
			UpperLeg = { color = C.scholarNavy, material = FABRIC },
			LowerLeg = { color = Color3.fromRGB(52, 50, 56), material = FABRIC },
			Foot = { color = C.darkLeather, material = LEATHER },
		},
		pieces = concat(
			{
				-- Col de lin.
				piece("UpperTorso", "ellipsoid", v(0.7, 0.16, 0.76), v(0, 0.5, 0), C.parchment, FABRIC),
				-- Étole d'or sur la poitrine.
				piece("UpperTorso", "block", v(0.12, 0.98, 0.05), v(-0.2, -0.02, -0.545), C.oldGold, FABRIC),
				piece("UpperTorso", "block", v(0.12, 0.98, 0.05), v(0.2, -0.02, -0.545), C.oldGold, FABRIC),
				-- Robe longue : devant (avec l'étole qui continue), dos, côtés évasés.
				piece("LowerTorso", "block", v(0.98, 1.9, 0.05), v(0, -0.8, -0.57), C.scholarNavy, FABRIC, v(3, 0, 0), {
					yRef = THIGH,
					children = {
						piece("", "block", v(0.12, 1, 1.2), v(-0.2, 0, 0), C.oldGold, FABRIC),
						piece("", "block", v(0.12, 1, 1.2), v(0.2, 0, 0), C.oldGold, FABRIC),
						hem(C.oldGold),
					},
				}),
				piece("LowerTorso", "block", v(1.02, 1.95, 0.05), v(0, -0.82, 0.57), C.scholarNavy, FABRIC, v(-3, 0, 0), { yRef = THIGH, children = { hem(C.oldGold) } }),
				-- Cordelière, livre à la ceinture, étui à parchemins dans le dos.
				piece("LowerTorso", "block", v(1.04, 0.3, 1.06), v(0, 0.3, 0), C.oldGold, FABRIC),
				piece("LowerTorso", "block", v(0.16, 0.3, 0.32), v(-0.56, -0.2, 0), C.bookRed, LEATHER, nil, {
					yRef = THIGH,
					children = { piece("", "block", v(0.9, 0.9, 1.04), v(0.08, 0, 0), C.parchment, FABRIC) },
				}),
				piece("UpperTorso", "cylinder", v(0.16, 1.05, 0.16), v(0.25, 0.05, 0.6), C.leather, LEATHER, v(0, 0, 18)),
			},
			mirrored("LowerTorso", "block", v(0.05, 1.85, 0.98), v(0.52, -0.78, 0), C.scholarNavy, FABRIC, v(0, 0, 4), { yRef = THIGH }),
			-- Larges manches à revers d'or.
			pair("LowerArm", "block", v(1.36, 0.46, 1.36), v(0, -0.3, 0), C.scholarNavy, FABRIC, nil, {
				children = { piece("", "block", v(1.03, 0.2, 1.03), v(0, -0.42, 0), C.oldGold, FABRIC) },
			})
		),
	},
}

--------------------------------------------------------------------------------
-- Ornements (tête et poitrine), en studs sur la tête classique (taille fixe)
--------------------------------------------------------------------------------

local BEARD_BROWN = Color3.fromRGB(86, 58, 38)
local BEARD_AUBURN = Color3.fromRGB(136, 70, 40)
local BEARD_GREY = Color3.fromRGB(150, 146, 140)

-- Barbe tressée : sous le menton (la bouche reste visible), une tresse et deux anneaux de bronze.
local function beard(color: Color3): { Piece }
	return {
		piece("Head", "ellipsoid", v(0.95, 0.62, 0.5), v(0, -0.6, -0.36), color, FABRIC, v(-12, 0, 0), { studs = true }),
		piece("Head", "ellipsoid", v(0.5, 0.3, 0.32), v(0, -0.34, -0.55), color, FABRIC, nil, { studs = true }),
		piece("Head", "cylinder", v(0.22, 0.5, 0.22), v(0, -1.02, -0.5), color, FABRIC, v(-12, 0, 0), {
			studs = true,
			children = {
				piece("", "cylinder", v(1.25, 0.16, 1.25), v(0, 0.15, 0), C.bronze, METAL),
				piece("", "cylinder", v(1.25, 0.16, 1.25), v(0, -0.3, 0), C.bronze, METAL),
			},
		}),
	}
end

local ORNAMENTS: { Ornament } = {
	{ id = "none", name = "Aucun", description = "Pas d'ornement.", swatches = {}, pieces = {} },
	{ id = "beard_brown", name = "Barbe tressée (brune)", description = "Barbe fournie sous le menton, une tresse à anneaux de bronze. Facultative pour tous les peuples, nains compris.", swatches = { BEARD_BROWN, C.bronze }, pieces = beard(BEARD_BROWN) },
	{ id = "beard_auburn", name = "Barbe tressée (rousse)", description = "La même, couleur de cuivre.", swatches = { BEARD_AUBURN, C.bronze }, pieces = beard(BEARD_AUBURN) },
	{ id = "beard_grey", name = "Barbe tressée (grise)", description = "La même, grisonnante : un vétéran.", swatches = { BEARD_GREY, C.bronze }, pieces = beard(BEARD_GREY) },
	{
		id = "ellendor_circlet",
		name = "Diadème d'Ellendor",
		description = "Fin bandeau d'argent sur le front, feuille d'or pâle au centre.",
		swatches = { C.silver, C.paleGold },
		pieces = {
			piece("Head", "block", v(0.62, 0.06, 0.05), v(0, 0.22, -0.6), C.silver, METAL, nil, { studs = true }),
			piece("Head", "block", v(0.42, 0.06, 0.05), v(0.42, 0.22, -0.42), C.silver, METAL, v(0, -45, 0), { studs = true }),
			piece("Head", "block", v(0.42, 0.06, 0.05), v(-0.42, 0.22, -0.42), C.silver, METAL, v(0, 45, 0), { studs = true }),
			piece("Head", "wedge", v(0.07, 0.11, 0.04), v(0, 0.31, -0.63), C.paleGold, METAL, nil, { studs = true }),
			piece("Head", "wedge", v(0.07, 0.11, 0.04), v(0, 0.2, -0.63), C.paleGold, METAL, v(0, 0, 180), { studs = true }),
		},
	},
	{
		id = "anomaly_pendant",
		name = "Sablier de l'anomalie",
		description = "Petit sablier d'argent au bout d'une chaîne, une lueur violette prisonnière du verre.",
		swatches = { C.moonSilver, C.violet },
		pieces = {
			piece("UpperTorso", "block", v(0.025, 0.36, 0.025), v(-0.09, 0.3, -0.56), C.moonSilver, METAL, v(0, 0, -16)),
			piece("UpperTorso", "block", v(0.025, 0.36, 0.025), v(0.09, 0.3, -0.56), C.moonSilver, METAL, v(0, 0, 16)),
			piece("UpperTorso", "ellipsoid", v(0.09, 0.08, 0.06), v(0, 0.12, -0.57), Color3.fromRGB(150, 110, 220), Enum.Material.Neon, nil, {
				children = {
					piece("", "block", v(1.4, 0.15, 1.2), v(0, 0.75, 0), C.moonSilver, METAL),
					piece("", "block", v(1.4, 0.15, 1.2), v(0, -0.75, 0), C.moonSilver, METAL),
				},
			}),
		},
	},
}

--------------------------------------------------------------------------------
-- Accès
--------------------------------------------------------------------------------

local byId: { [string]: Garment } = {}
for _, garment in GARMENTS do
	byId[garment.id] = garment
end
for _, garment in NPC_GARMENTS do
	byId[garment.id] = garment
end
local ornamentById: { [string]: Ornament } = {}
for _, ornament in ORNAMENTS do
	ornamentById[ornament.id] = ornament
end

-- Membres du corps visés par une clé de teinture.
local DYE_TARGETS: { [string]: { string } } = {
	UpperTorso = { "UpperTorso" },
	LowerTorso = { "LowerTorso" },
	UpperArm = { "LeftUpperArm", "RightUpperArm" },
	LowerArm = { "LeftLowerArm", "RightLowerArm" },
	Hand = { "LeftHand", "RightHand" },
	UpperLeg = { "LeftUpperLeg", "RightUpperLeg" },
	LowerLeg = { "LeftLowerLeg", "RightLowerLeg" },
	Foot = { "LeftFoot", "RightFoot" },
}

return table.freeze({
	GARMENTS = GARMENTS,
	NPC_GARMENTS = NPC_GARMENTS,
	ORNAMENTS = ORNAMENTS,
	DYE_TARGETS = DYE_TARGETS,
	COLORS = C,
	get = function(id: string?): Garment?
		return if id then byId[id] else nil
	end,
	getOrnament = function(id: string?): Ornament?
		return if id then ornamentById[id] else nil
	end,
})
