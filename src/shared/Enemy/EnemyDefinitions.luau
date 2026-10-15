--!strict
--[[
	EnemyDefinitions
	Données des ennemis de la Région 1 (partagées serveur + client). AUCUNE logique ici.

		ENEMIES[enemyId]  : caractéristiques, comportement, aggro, attaques, butin, APPARENCE ;
		SPAWNS[anchorId]  : quel ennemi apparaît sur quelle ancre de RegionConfig.ANCHORS, et son délai
		                    de réapparition (DEFAULT_RESPAWN si absent) ;
		AI                : réglages communs de l'IA (rythme de décision, laisse, régénération...) ;
		ATTRIBUTES        : noms des attributs posés par le serveur sur les Models d'ennemis.

	Qui lit quoi :
		- Server/Enemy/EnemyService + EnemyFactory + Behaviors/* (apparition, IA, attaques, récompenses) ;
		- Client/Enemy/EnemyEffectsController (nom, rang, couleurs des télégraphes).

	>>> APPARENCE : chaque ennemi est un rig R15 généré (HumanoidDescription) et habillé par `appearance`.
	>>> Pour utiliser votre propre modèle, posez un Model nommé comme l'enemyId dans
	>>> ServerStorage > Assets > Enemies (Humanoid + HumanoidRootPart) : il est cloné à la place.
	>>> ANIMATIONS : uniquement des ID déjà présents dans le projet (animations officielles Roblox) ;
	>>> "" = pas d'animation. Aucune animation de sort n'existe encore pour le Murmure.

	Coordonnées des décorations : `position` est RELATIVE à la taille de la pièce porteuse
	(x = 0.5 -> bord droit, z = -0.5 -> face avant), `size` en studs AVANT la mise à l'échelle du modèle
	(`modelScale`, appliquée à tout le rig décorations comprises).
]]

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type AttackShape = "circle" | "cone" | "line"

export type AttackDef = {
	id: string,
	name: string, -- nom lisible (débogage, effets)
	shape: AttackShape,
	center: "self" | "target", -- zone posée sous l'ennemi (orientée vers la cible) ou sous la cible
	range: number, -- l'ennemi ne lance l'attaque que si sa cible est à cette distance (studs) ou moins
	radius: number, -- cercle : rayon ; cône : portée ; ligne : longueur (sert aussi au tri par distance)
	angle: number?, -- cône : ouverture totale (degrés)
	length: number?, -- ligne : longueur (studs)
	width: number?, -- ligne : largeur (studs)
	telegraph: number, -- secondes d'annonce au sol avant l'impact (le temps de réagir)
	damage: number,
	parryable: boolean, -- false = attaque de zone : ne se pare pas, elle s'esquive (dash)
	cooldown: number, -- secondes avant de pouvoir relancer CETTE attaque
	recovery: number, -- secondes d'immobilité après l'impact (fenêtre pour punir)
	weight: number?, -- poids du tirage quand plusieurs attaques sont possibles (1 par défaut)
	lunge: number?, -- bond : distance parcourue le long de la ligne au moment de l'impact
	guardDown: boolean?, -- Gardien : sa garde frontale tombe pendant cette attaque
	animationId: string, -- "" = aucune
	animationSpeed: number?,
}

export type BodyColors = {
	head: Color3,
	torso: Color3,
	leftArm: Color3,
	rightArm: Color3,
	leftLeg: Color3,
	rightLeg: Color3,
}

export type DecorationDef = {
	name: string,
	attachTo: string, -- pièce du corps R15 porteuse ("Head", "UpperTorso", "RightHand"...)
	shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	size: Vector3,
	position: Vector3, -- relative à la taille de la pièce porteuse
	offset: Vector3?, -- décalage supplémentaire en studs (objets tenus en main, robe...)
	rotation: Vector3?, -- degrés (X, Y, Z)
	color: Color3,
	material: Enum.Material,
	transparency: number?,
}

-- Émetteur de particules à texture PAR DÉFAUT (aucun asset).
export type EmitterDef = {
	name: string,
	attachTo: string,
	position: Vector3?, -- relative (comme les décorations)
	offset: Vector3?, -- studs
	color: ColorSequence,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence?,
	lightEmission: number?,
	spread: number?, -- angle de dispersion (degrés)
	acceleration: Vector3?,
}

export type LightDef = {
	attachTo: string,
	color: Color3,
	range: number,
	brightness: number,
}

export type AppearanceDef = {
	bodyColors: BodyColors,
	bodyMaterial: Enum.Material?, -- matière des pièces du corps (nil = inchangée)
	bodyTransparency: number?,
	heightScale: number, -- HumanoidDescription.HeightScale (0.9 à 1.15, comme les joueurs)
	widthScale: number, -- HumanoidDescription.WidthScale (0.75 à 1.1)
	depthScale: number?,
	headScale: number?,
	modelScale: number, -- Model:ScaleTo : taille globale (1 = taille d'un joueur)
	hideFace: boolean?, -- retire le visage souriant par défaut
	decorations: { DecorationDef },
	emitters: { EmitterDef },
	lights: { LightDef }?,
}

export type AggroDef = {
	detectRadius: number, -- un joueur plus proche (et visible) est pris pour cible
	loseRadius: number, -- la cible est abandonnée au-delà de cette distance
	leashRadius: number, -- laisse autour du point d'apparition : au-delà, retour au point + régénération
	verticalTolerance: number, -- écart de hauteur maximal (évite de repérer à travers un plancher)
}

export type LootDef = {
	itemId: string, -- id de Shared/Progression/ItemConfig
	chance: number, -- 0..1, tirée UNE fois par joueur éligible
	count: number,
}

-- Paramètres propres à un comportement (voir Server/Enemy/Behaviors).
export type SkirmishDef = {
	zigzagAmplitude: number, -- studs d'écart latéral pendant l'approche
	zigzagPeriod: number, -- secondes pour un aller-retour du zigzag
	retreatDistance: number, -- distance à reprendre après un bond
	retreatDuration: number, -- secondes de repli
	orbitDistance: number, -- distance de harcèlement quand le bond recharge
}

export type GuardDef = {
	angle: number, -- ouverture totale du cône de garde (degrés)
	reduction: number, -- part des dégâts absorbée par la garde (0.8 = -80 %)
	breakStun: number, -- secondes d'étourdissement quand le coup lourd brise la garde
	affectedKinds: { [string]: boolean }, -- DamageSource.kind que la garde réduit
}

export type KiteDef = {
	minDistance: number, -- plus près : l'ennemi recule
	maxDistance: number, -- plus loin : l'ennemi s'approche
	preferredDistance: number,
}

export type BlinkDef = {
	triggerDistance: number, -- un joueur plus proche déclenche la téléportation
	cooldown: number,
	minDistance: number, -- distance d'arrivée par rapport au joueur
	maxDistance: number,
}

export type SummonDef = {
	enemyId: string,
	count: number,
	healthRatio: number, -- invocation UNIQUE quand les PV passent sous ce seuil
	channel: number, -- secondes d'incantation (interrompue par un étourdissement)
	radius: number, -- distance d'apparition autour de l'invocateur
}

export type EnrageDef = {
	healthRatio: number,
	speedMultiplier: number,
	telegraphMultiplier: number, -- < 1 : télégraphes plus courts
	cooldownMultiplier: number,
}

export type RegenDef = {
	delay: number, -- secondes après le dernier coup avant de récupérer TOUS ses PV
}

export type PracticeDef = {
	interval: number, -- secondes entre deux attaques à vide
	radius: number, -- un joueur à cette distance déclenche l'attaque
	attackId: string, -- attaque de la liste `attacks` à utiliser
}

export type EnemyDef = {
	id: string,
	displayName: string,
	behavior: string, -- "skirmisher" | "guardian" | "caster" | "elite" | "dummy" | "boss"
	elite: boolean,
	rank: string?, -- étiquette affichée sur la barre de vie ("Élite", "Boss")
	maxHealth: number,
	walkSpeed: number,
	turnSpeed: number, -- degrés / seconde quand il pivote vers sa cible sans marcher
	xp: number,
	loot: { LootDef },
	respawn: number?, -- secondes (un SPAWN peut le remplacer ; nil = DEFAULT_RESPAWN)
	corpseDuration: number?, -- secondes avant le fondu du corps (nil = DEFAULT_CORPSE_DURATION)
	rewindable: boolean?, -- true = entre dans la timeline du rembobinage (boss uniquement)
	anchored: boolean?, -- planté au sol (mannequin)
	aggro: AggroDef,
	attacks: { AttackDef },
	appearance: AppearanceDef,
	skirmish: SkirmishDef?,
	guard: GuardDef?,
	kite: KiteDef?,
	blink: BlinkDef?,
	summon: SummonDef?,
	enrage: EnrageDef?,
	regen: RegenDef?,
	practice: PracticeDef?,
}

export type SpawnDef = {
	enemyId: string,
	respawn: number?, -- secondes ; remplace celui de la définition
}

--------------------------------------------------------------------------------
-- Valeurs communes
--------------------------------------------------------------------------------

-- Animations officielles Roblox déjà utilisées par le projet (CombatConfig, BossConfig).
local SLASH_ANIMATION = "rbxassetid://522635514" -- "R15 Sword Slash"
local LUNGE_ANIMATION = "rbxassetid://522638767" -- "R15 Sword Lunge"

local function sameColors(head: Color3, torso: Color3, arms: Color3, legs: Color3): BodyColors
	return { head = head, torso = torso, leftArm = arms, rightArm = arms, leftLeg = legs, rightLeg = legs }
end

--------------------------------------------------------------------------------
-- Ennemis
--------------------------------------------------------------------------------

local ENEMIES: { [string]: EnemyDef } = {
	----------------------------------------------------------------------------
	-- Rôdeur des Cendres : rapide, harcèle, bondit puis se replie.
	----------------------------------------------------------------------------
	ash_prowler = {
		id = "ash_prowler",
		displayName = "Rôdeur des Cendres",
		behavior = "skirmisher",
		elite = false,
		maxHealth = 60,
		walkSpeed = 22,
		turnSpeed = 540,
		xp = 25,
		loot = { { itemId = "ash_shard", chance = 0.5, count = 1 } },
		aggro = { detectRadius = 45, loseRadius = 70, leashRadius = 75, verticalTolerance = 14 },
		skirmish = {
			zigzagAmplitude = 7,
			zigzagPeriod = 1.6,
			retreatDistance = 16,
			retreatDuration = 1.3,
			orbitDistance = 11,
		},
		attacks = {
			{
				id = "pounce",
				name = "Bond",
				shape = "line",
				center = "self",
				range = 13,
				radius = 15,
				length = 15,
				width = 4.5,
				telegraph = 0.45,
				damage = 7,
				parryable = true,
				cooldown = 2.6,
				recovery = 0.35,
				lunge = 13,
				animationId = LUNGE_ANIMATION,
				animationSpeed = 1.3,
			},
		},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(46, 40, 37),
				Color3.fromRGB(58, 48, 42),
				Color3.fromRGB(36, 31, 29),
				Color3.fromRGB(36, 31, 29)
			),
			bodyMaterial = Enum.Material.CrackedLava, -- fissures incandescentes : il couve encore
			heightScale = 0.95,
			widthScale = 0.8,
			depthScale = 0.9,
			modelScale = 0.95,
			hideFace = true,
			decorations = {
				{ name = "EyeLeft", attachTo = "Head", shape = "Ball", size = Vector3.new(0.22, 0.14, 0.14), position = Vector3.new(-0.18, 0.08, -0.5), color = Color3.fromRGB(255, 120, 30), material = Enum.Material.Neon },
				{ name = "EyeRight", attachTo = "Head", shape = "Ball", size = Vector3.new(0.22, 0.14, 0.14), position = Vector3.new(0.18, 0.08, -0.5), color = Color3.fromRGB(255, 120, 30), material = Enum.Material.Neon },
				{ name = "SpineUpper", attachTo = "UpperTorso", shape = "Wedge", size = Vector3.new(0.25, 0.7, 0.6), position = Vector3.new(0, 0.35, 0.55), rotation = Vector3.new(0, 180, 0), color = Color3.fromRGB(28, 24, 22), material = Enum.Material.Slate },
				{ name = "SpineLower", attachTo = "UpperTorso", shape = "Wedge", size = Vector3.new(0.22, 0.55, 0.5), position = Vector3.new(0, -0.15, 0.55), rotation = Vector3.new(0, 180, 0), color = Color3.fromRGB(28, 24, 22), material = Enum.Material.Slate },
				{ name = "ClawLeft", attachTo = "LeftHand", shape = "Wedge", size = Vector3.new(0.2, 0.5, 0.35), position = Vector3.new(0, -0.6, -0.2), rotation = Vector3.new(180, 0, 0), color = Color3.fromRGB(220, 200, 170), material = Enum.Material.Marble },
				{ name = "ClawRight", attachTo = "RightHand", shape = "Wedge", size = Vector3.new(0.2, 0.5, 0.35), position = Vector3.new(0, -0.6, -0.2), rotation = Vector3.new(180, 0, 0), color = Color3.fromRGB(220, 200, 170), material = Enum.Material.Marble },
			},
			emitters = {
				{
					name = "Embers",
					attachTo = "UpperTorso",
					color = ColorSequence.new(Color3.fromRGB(255, 150, 50), Color3.fromRGB(120, 20, 10)),
					rate = 6,
					lifetime = NumberRange.new(0.8, 1.4),
					speed = NumberRange.new(1, 3),
					size = NumberSequence.new(0.25, 0),
					lightEmission = 1,
					spread = 60,
					acceleration = Vector3.new(0, 3, 0),
				},
			},
			lights = { { attachTo = "UpperTorso", color = Color3.fromRGB(255, 120, 40), range = 8, brightness = 0.8 } },
		},
	},

	----------------------------------------------------------------------------
	-- Gardien de Pierre : lent, garde frontale, coup de masse au sol.
	----------------------------------------------------------------------------
	stone_guardian = {
		id = "stone_guardian",
		displayName = "Gardien de Pierre",
		behavior = "guardian",
		elite = false,
		maxHealth = 160,
		walkSpeed = 10,
		turnSpeed = 100, -- pivote lentement : on peut le contourner pour frapper de côté ou de dos
		xp = 45,
		loot = { { itemId = "stone_core", chance = 0.35, count = 1 } },
		aggro = { detectRadius = 30, loseRadius = 50, leashRadius = 55, verticalTolerance = 14 },
		guard = {
			angle = 120,
			reduction = 0.8,
			breakStun = 1.2,
			-- La garde arrête l'épée et les ultimes venus de face ; pas la brûlure (sans direction).
			affectedKinds = { melee = true, ultimate = true },
		},
		attacks = {
			{
				id = "slam",
				name = "Coup de masse",
				shape = "circle",
				center = "self",
				range = 7,
				radius = 9,
				telegraph = 1.0,
				damage = 16,
				parryable = false,
				cooldown = 5.5,
				recovery = 0.9,
				weight = 1,
				guardDown = true, -- il lève la masse à deux mains : la garde tombe
				animationId = SLASH_ANIMATION,
				animationSpeed = 0.7,
			},
			{
				id = "strike",
				name = "Revers de pierre",
				shape = "cone",
				center = "self",
				range = 6.5,
				radius = 8,
				angle = 80,
				telegraph = 0.6,
				damage = 11,
				parryable = true,
				cooldown = 2.4,
				recovery = 0.5,
				weight = 2,
				animationId = SLASH_ANIMATION,
				animationSpeed = 1,
			},
		},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(122, 120, 112),
				Color3.fromRGB(108, 106, 100),
				Color3.fromRGB(96, 94, 90),
				Color3.fromRGB(88, 86, 82)
			),
			bodyMaterial = Enum.Material.Slate,
			heightScale = 1.1,
			widthScale = 1.1,
			depthScale = 1.1,
			modelScale = 1.3,
			hideFace = true,
			decorations = {
				{ name = "EyeLeft", attachTo = "Head", shape = "Block", size = Vector3.new(0.28, 0.1, 0.1), position = Vector3.new(-0.2, 0.05, -0.5), color = Color3.fromRGB(140, 230, 255), material = Enum.Material.Neon },
				{ name = "EyeRight", attachTo = "Head", shape = "Block", size = Vector3.new(0.28, 0.1, 0.1), position = Vector3.new(0.2, 0.05, -0.5), color = Color3.fromRGB(140, 230, 255), material = Enum.Material.Neon },
				{ name = "Brow", attachTo = "Head", shape = "Block", size = Vector3.new(1.3, 0.3, 0.4), position = Vector3.new(0, 0.38, -0.35), color = Color3.fromRGB(84, 82, 78), material = Enum.Material.Basalt },
				{ name = "ChestPlate", attachTo = "UpperTorso", shape = "Block", size = Vector3.new(1.7, 1.1, 0.35), position = Vector3.new(0, 0.05, -0.55), color = Color3.fromRGB(90, 88, 84), material = Enum.Material.Basalt },
				{ name = "ShoulderLeft", attachTo = "LeftUpperArm", shape = "Block", size = Vector3.new(1.1, 0.5, 1.2), position = Vector3.new(-0.1, 0.5, 0), color = Color3.fromRGB(84, 82, 78), material = Enum.Material.Basalt },
				{ name = "ShoulderRight", attachTo = "RightUpperArm", shape = "Block", size = Vector3.new(1.1, 0.5, 1.2), position = Vector3.new(0.1, 0.5, 0), color = Color3.fromRGB(84, 82, 78), material = Enum.Material.Basalt },
				-- Bouclier de pierre porté sur l'avant-bras gauche : la garde frontale, visible.
				{ name = "Shield", attachTo = "LeftLowerArm", shape = "Block", size = Vector3.new(1.8, 2.2, 0.35), position = Vector3.new(0.2, 0, -0.5), offset = Vector3.new(0, 0, -0.25), color = Color3.fromRGB(100, 98, 92), material = Enum.Material.Slate },
				{ name = "MaceHandle", attachTo = "RightHand", shape = "Cylinder", size = Vector3.new(2.6, 0.3, 0.3), position = Vector3.new(0, -0.5, 0), offset = Vector3.new(0, 0, -1.3), rotation = Vector3.new(0, 90, 0), color = Color3.fromRGB(70, 52, 38), material = Enum.Material.Wood },
				{ name = "MaceHead", attachTo = "RightHand", shape = "Block", size = Vector3.new(1, 1, 1), position = Vector3.new(0, -0.5, 0), offset = Vector3.new(0, 0, -3), color = Color3.fromRGB(110, 108, 102), material = Enum.Material.Basalt },
			},
			emitters = {
				{
					name = "Dust",
					attachTo = "LowerTorso",
					color = ColorSequence.new(Color3.fromRGB(150, 145, 135)),
					rate = 2,
					lifetime = NumberRange.new(1.2, 2),
					speed = NumberRange.new(0.3, 0.8),
					size = NumberSequence.new(0.4, 0.9),
					transparency = NumberSequence.new(0.6, 1),
					lightEmission = 0,
					spread = 180,
				},
			},
		},
	},

	----------------------------------------------------------------------------
	-- Murmure : lanceur de sorts, garde ses distances et pose des zones de danger.
	----------------------------------------------------------------------------
	whisper = {
		id = "whisper",
		displayName = "Murmure",
		behavior = "caster",
		elite = false,
		maxHealth = 50,
		walkSpeed = 14,
		turnSpeed = 360,
		xp = 35,
		loot = { { itemId = "whisper_essence", chance = 0.4, count = 1 } },
		aggro = { detectRadius = 50, loseRadius = 70, leashRadius = 65, verticalTolerance = 16 },
		kite = { minDistance = 25, maxDistance = 40, preferredDistance = 32 },
		blink = { triggerDistance = 12, cooldown = 6, minDistance = 20, maxDistance = 28 },
		attacks = {
			{
				id = "dread_zone",
				name = "Zone de murmure",
				shape = "circle",
				center = "target",
				range = 45,
				radius = 7,
				telegraph = 1.2,
				damage = 14,
				parryable = false,
				cooldown = 3.4,
				recovery = 0.4,
				animationId = "", -- >>> ANIMATION : aucune animation de sort dans le projet pour l'instant
			},
		},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(190, 180, 210),
				Color3.fromRGB(70, 56, 92),
				Color3.fromRGB(150, 140, 175),
				Color3.fromRGB(60, 48, 80)
			),
			bodyMaterial = Enum.Material.SmoothPlastic,
			bodyTransparency = 0.35, -- silhouette à demi effacée
			heightScale = 1.1,
			widthScale = 0.75,
			depthScale = 0.8,
			modelScale = 1.05,
			hideFace = true,
			decorations = {
				{ name = "Hood", attachTo = "Head", shape = "Block", size = Vector3.new(1.45, 1.5, 1.45), position = Vector3.new(0, 0.12, 0.08), color = Color3.fromRGB(42, 32, 58), material = Enum.Material.Fabric },
				{ name = "Veil", attachTo = "Head", shape = "Block", size = Vector3.new(1.2, 0.6, 0.1), position = Vector3.new(0, -0.32, -0.6), color = Color3.fromRGB(30, 24, 42), material = Enum.Material.Fabric, transparency = 0.15 },
				{ name = "EyeLeft", attachTo = "Head", shape = "Ball", size = Vector3.new(0.18, 0.18, 0.1), position = Vector3.new(-0.17, 0.1, -0.62), color = Color3.fromRGB(200, 140, 255), material = Enum.Material.Neon },
				{ name = "EyeRight", attachTo = "Head", shape = "Ball", size = Vector3.new(0.18, 0.18, 0.1), position = Vector3.new(0.17, 0.1, -0.62), color = Color3.fromRGB(200, 140, 255), material = Enum.Material.Neon },
				{ name = "Mantle", attachTo = "UpperTorso", shape = "Block", size = Vector3.new(2.3, 0.4, 1.3), position = Vector3.new(0, 0.45, 0), color = Color3.fromRGB(42, 32, 58), material = Enum.Material.Fabric },
				{ name = "Robe", attachTo = "LowerTorso", shape = "Block", size = Vector3.new(1.9, 2.4, 1.3), position = Vector3.new(0, -0.5, 0), offset = Vector3.new(0, -1.1, 0), color = Color3.fromRGB(38, 28, 52), material = Enum.Material.Fabric, transparency = 0.1 },
			},
			emitters = {
				{
					name = "Mist",
					attachTo = "LowerTorso",
					offset = Vector3.new(0, -2, 0),
					color = ColorSequence.new(Color3.fromRGB(170, 120, 230), Color3.fromRGB(40, 20, 60)),
					rate = 8,
					lifetime = NumberRange.new(1, 1.6),
					speed = NumberRange.new(0.5, 1.5),
					size = NumberSequence.new(0.6, 1.4),
					transparency = NumberSequence.new(0.6, 1),
					lightEmission = 0.6,
					spread = 180,
				},
			},
			lights = { { attachTo = "Head", color = Color3.fromRGB(180, 120, 255), range = 10, brightness = 1 } },
		},
	},

	----------------------------------------------------------------------------
	-- Veilleur de Cendre : élite de la crypte, plusieurs attaques, invocation, rage.
	----------------------------------------------------------------------------
	ash_watcher = {
		id = "ash_watcher",
		displayName = "Veilleur de Cendre",
		behavior = "elite",
		elite = true,
		rank = "Élite",
		maxHealth = 900,
		walkSpeed = 13,
		turnSpeed = 160,
		xp = 300,
		loot = { { itemId = "ash_shard", chance = 1, count = 3 } },
		respawn = 120,
		corpseDuration = 5,
		-- La salle du gardien fait environ 40 x 40 : la laisse le garde chez lui, la tolérance verticale
		-- l'empêche de repérer les joueurs du village, 30 studs plus haut.
		aggro = { detectRadius = 34, loseRadius = 46, leashRadius = 30, verticalTolerance = 10 },
		summon = { enemyId = "ash_prowler", count = 2, healthRatio = 0.5, channel = 1.2, radius = 9 },
		enrage = { healthRatio = 0.25, speedMultiplier = 1.3, telegraphMultiplier = 0.75, cooldownMultiplier = 0.75 },
		attacks = {
			{
				id = "sweep",
				name = "Balayage",
				shape = "cone",
				center = "self",
				range = 10,
				radius = 12,
				angle = 140,
				telegraph = 0.8,
				damage = 18,
				parryable = true,
				cooldown = 2.8,
				recovery = 0.6,
				weight = 2,
				animationId = SLASH_ANIMATION,
				animationSpeed = 0.9,
			},
			{
				id = "crush",
				name = "Écrasement",
				shape = "circle",
				center = "self",
				range = 11,
				radius = 12,
				telegraph = 1.1,
				damage = 24,
				parryable = false,
				cooldown = 6.5,
				recovery = 1.0,
				weight = 1,
				animationId = LUNGE_ANIMATION,
				animationSpeed = 0.8,
			},
		},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(38, 34, 32),
				Color3.fromRGB(30, 27, 26),
				Color3.fromRGB(44, 40, 37),
				Color3.fromRGB(26, 24, 23)
			),
			bodyMaterial = Enum.Material.Basalt,
			heightScale = 1.1,
			widthScale = 1.05,
			depthScale = 1,
			modelScale = 1.6,
			hideFace = true,
			decorations = {
				{ name = "EyeLeft", attachTo = "Head", shape = "Block", size = Vector3.new(0.3, 0.12, 0.1), position = Vector3.new(-0.2, 0.06, -0.5), color = Color3.fromRGB(255, 140, 40), material = Enum.Material.Neon },
				{ name = "EyeRight", attachTo = "Head", shape = "Block", size = Vector3.new(0.3, 0.12, 0.1), position = Vector3.new(0.2, 0.06, -0.5), color = Color3.fromRGB(255, 140, 40), material = Enum.Material.Neon },
				{ name = "HornLeft", attachTo = "Head", shape = "Wedge", size = Vector3.new(0.25, 0.9, 0.5), position = Vector3.new(-0.4, 0.75, 0), color = Color3.fromRGB(215, 200, 175), material = Enum.Material.Marble },
				{ name = "HornRight", attachTo = "Head", shape = "Wedge", size = Vector3.new(0.25, 0.9, 0.5), position = Vector3.new(0.4, 0.75, 0), color = Color3.fromRGB(215, 200, 175), material = Enum.Material.Marble },
				{ name = "Crown", attachTo = "Head", shape = "Cylinder", size = Vector3.new(0.25, 1.35, 1.35), position = Vector3.new(0, 0.5, 0), rotation = Vector3.new(0, 0, 90), color = Color3.fromRGB(70, 60, 50), material = Enum.Material.CorrodedMetal },
				{ name = "HeartCore", attachTo = "UpperTorso", shape = "Ball", size = Vector3.new(0.6, 0.6, 0.6), position = Vector3.new(0, 0.05, -0.48), color = Color3.fromRGB(255, 120, 30), material = Enum.Material.Neon },
				{ name = "PauldronLeft", attachTo = "LeftUpperArm", shape = "Block", size = Vector3.new(1.2, 0.5, 1.3), position = Vector3.new(-0.15, 0.55, 0), color = Color3.fromRGB(60, 52, 46), material = Enum.Material.CorrodedMetal },
				{ name = "PauldronRight", attachTo = "RightUpperArm", shape = "Block", size = Vector3.new(1.2, 0.5, 1.3), position = Vector3.new(0.15, 0.55, 0), color = Color3.fromRGB(60, 52, 46), material = Enum.Material.CorrodedMetal },
				{ name = "Blade", attachTo = "RightHand", shape = "Block", size = Vector3.new(0.2, 0.6, 4.2), position = Vector3.new(0, -0.5, 0), offset = Vector3.new(0, 0, -2.3), color = Color3.fromRGB(80, 70, 64), material = Enum.Material.CorrodedMetal },
			},
			emitters = {
				{
					name = "Embers",
					attachTo = "UpperTorso",
					color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(110, 20, 10)),
					rate = 14,
					lifetime = NumberRange.new(1, 1.8),
					speed = NumberRange.new(1.5, 4),
					size = NumberSequence.new(0.35, 0),
					lightEmission = 1,
					spread = 70,
					acceleration = Vector3.new(0, 4, 0),
				},
			},
			lights = { { attachTo = "UpperTorso", color = Color3.fromRGB(255, 130, 50), range = 14, brightness = 1.4 } },
		},
	},

	----------------------------------------------------------------------------
	-- Mannequin d'entraînement : n'attaque jamais pour de vrai, se régénère.
	----------------------------------------------------------------------------
	training_dummy = {
		id = "training_dummy",
		displayName = "Mannequin",
		behavior = "dummy",
		elite = false,
		maxHealth = 300,
		walkSpeed = 0,
		turnSpeed = 200,
		xp = 0,
		loot = {},
		respawn = 3,
		corpseDuration = 1.2,
		anchored = true,
		aggro = { detectRadius = 10, loseRadius = 14, leashRadius = 1000, verticalTolerance = 8 },
		regen = { delay = 5 },
		-- Attaque à vide pour s'entraîner à la parade (attribut ATTRIBUTES.practice, activé par défaut) :
		-- très lente, parable, aucun dégât.
		practice = { interval = 4, radius = 9, attackId = "practice_swing" },
		attacks = {
			{
				id = "practice_swing",
				name = "Moulinet d'entraînement",
				shape = "cone",
				center = "self",
				range = 9,
				radius = 8,
				angle = 90,
				telegraph = 1.4,
				damage = 0,
				parryable = true,
				cooldown = 4,
				recovery = 0.3,
				animationId = SLASH_ANIMATION,
				animationSpeed = 0.6,
			},
		},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(196, 168, 118),
				Color3.fromRGB(172, 140, 96),
				Color3.fromRGB(186, 156, 108),
				Color3.fromRGB(112, 82, 52)
			),
			bodyMaterial = Enum.Material.Fabric,
			heightScale = 1,
			widthScale = 1,
			modelScale = 1,
			hideFace = true,
			decorations = {
				{ name = "Target", attachTo = "UpperTorso", shape = "Cylinder", size = Vector3.new(0.12, 1.4, 1.4), position = Vector3.new(0, 0, -0.52), rotation = Vector3.new(0, 90, 0), color = Color3.fromRGB(180, 40, 36), material = Enum.Material.SmoothPlastic },
				{ name = "Bullseye", attachTo = "UpperTorso", shape = "Cylinder", size = Vector3.new(0.14, 0.6, 0.6), position = Vector3.new(0, 0, -0.56), rotation = Vector3.new(0, 90, 0), color = Color3.fromRGB(235, 225, 205), material = Enum.Material.SmoothPlastic },
				{ name = "Rope", attachTo = "LowerTorso", shape = "Block", size = Vector3.new(2.1, 0.2, 1.1), position = Vector3.new(0, 0.3, 0), color = Color3.fromRGB(120, 96, 60), material = Enum.Material.Fabric },
				{ name = "StitchMark", attachTo = "Head", shape = "Block", size = Vector3.new(0.7, 0.08, 0.06), position = Vector3.new(0, 0.05, -0.5), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Fabric },
			},
			emitters = {},
		},
	},

	----------------------------------------------------------------------------
	-- Boss d'entraînement : apparition par EnemyService, IA par BossService (existant).
	----------------------------------------------------------------------------
	training_boss = {
		id = "training_boss",
		displayName = "Gardien de l'Anomalie", -- BossService impose BossConfig.DISPLAY_NAME
		behavior = "boss",
		elite = false,
		rank = "Boss",
		maxHealth = 600, -- remplacé par BossConfig.MAX_HEALTH à l'apparition
		walkSpeed = 14,
		turnSpeed = 360,
		xp = 200,
		loot = {},
		respawn = 60,
		corpseDuration = 4,
		rewindable = true, -- son attaque fatale repose sur le rembobinage
		aggro = { detectRadius = 150, loseRadius = 150, leashRadius = 1000, verticalTolerance = 30 },
		attacks = {},
		appearance = {
			bodyColors = sameColors(
				Color3.fromRGB(30, 26, 30),
				Color3.fromRGB(24, 20, 24),
				Color3.fromRGB(36, 30, 36),
				Color3.fromRGB(20, 18, 20)
			),
			bodyMaterial = Enum.Material.Metal,
			heightScale = 1.15,
			widthScale = 1.1,
			depthScale = 1.05,
			modelScale = 1.5,
			hideFace = true,
			decorations = {
				{ name = "EyeLeft", attachTo = "Head", shape = "Block", size = Vector3.new(0.3, 0.1, 0.1), position = Vector3.new(-0.2, 0.06, -0.5), color = Color3.fromRGB(255, 40, 45), material = Enum.Material.Neon },
				{ name = "EyeRight", attachTo = "Head", shape = "Block", size = Vector3.new(0.3, 0.1, 0.1), position = Vector3.new(0.2, 0.06, -0.5), color = Color3.fromRGB(255, 40, 45), material = Enum.Material.Neon },
				{ name = "Crown", attachTo = "Head", shape = "Cylinder", size = Vector3.new(0.35, 1.4, 1.4), position = Vector3.new(0, 0.55, 0), rotation = Vector3.new(0, 0, 90), color = Color3.fromRGB(60, 10, 14), material = Enum.Material.Neon, transparency = 0.2 },
				{ name = "PauldronLeft", attachTo = "LeftUpperArm", shape = "Block", size = Vector3.new(1.2, 0.5, 1.3), position = Vector3.new(-0.15, 0.55, 0), color = Color3.fromRGB(40, 34, 40), material = Enum.Material.Metal },
				{ name = "PauldronRight", attachTo = "RightUpperArm", shape = "Block", size = Vector3.new(1.2, 0.5, 1.3), position = Vector3.new(0.15, 0.55, 0), color = Color3.fromRGB(40, 34, 40), material = Enum.Material.Metal },
			},
			emitters = {
				{
					name = "VoidSparks",
					attachTo = "UpperTorso",
					color = ColorSequence.new(Color3.fromRGB(255, 40, 45), Color3.fromRGB(20, 0, 4)),
					rate = 5,
					lifetime = NumberRange.new(0.6, 1),
					speed = NumberRange.new(1, 2.5),
					size = NumberSequence.new(0.3, 0),
					lightEmission = 1,
					spread = 180,
				},
			},
		},
	},
}

--------------------------------------------------------------------------------
-- Points d'apparition (AnchorId de RegionConfig.ANCHORS -> ennemi)
--------------------------------------------------------------------------------

local SPAWNS: { [string]: SpawnDef } = {
	enemy_forest_1 = { enemyId = "ash_prowler" },
	enemy_forest_2 = { enemyId = "ash_prowler" },
	enemy_forest_5 = { enemyId = "ash_prowler" },
	enemy_forest_3 = { enemyId = "stone_guardian" },
	enemy_forest_7 = { enemyId = "stone_guardian" },
	enemy_forest_4 = { enemyId = "whisper" },
	enemy_forest_6 = { enemyId = "whisper" },
	enemy_crypt_guardian = { enemyId = "ash_watcher", respawn = 120 },
	enemy_training_dummy_1 = { enemyId = "training_dummy", respawn = 3 },
	enemy_training_dummy_2 = { enemyId = "training_dummy", respawn = 3 },
	enemy_training_dummy_3 = { enemyId = "training_dummy", respawn = 3 },
	boss_training = { enemyId = "training_boss", respawn = 60 },
}

--------------------------------------------------------------------------------
-- Réglages communs de l'IA (serveur) et des effets (client)
--------------------------------------------------------------------------------

local AI = table.freeze({
	THINK_INTERVAL = 0.2, -- secondes entre deux décisions (une seule boucle pour tous les ennemis)
	WAKE_MARGIN = 60, -- studs au-delà du rayon de détection : plus loin, l'ennemi au repos "dort"
	HOME_TOLERANCE = 3, -- studs : distance à laquelle il considère être rentré
	RETURN_REGEN_RATE = 0.25, -- part des PV max regagnée par seconde pendant le retour au point
	RETURN_TIMEOUT = 10, -- secondes : coincé en rentrant, il est replacé à son point d'apparition
	OUT_OF_COMBAT_DELAY = 6, -- secondes sans coup ni cible avant la régénération hors combat
	OUT_OF_COMBAT_REGEN_RATE = 0.1, -- part des PV max par seconde
	PROVOKE_WINDOW = 8, -- secondes : un joueur qui le frappe devient sa cible (même hors détection)
	HIT_MARGIN = 1, -- studs : rayon du corps d'un joueur, ajouté aux zones d'attaque
	HIT_VERTICAL_REACH = 8, -- studs : un joueur plus haut que ça au-dessus de la zone l'évite (saut)
	REPATH_INTERVAL = 1, -- secondes entre deux calculs de chemin vers une même destination
	REPATH_DISTANCE = 6, -- studs : une destination qui bouge plus que ça force un nouveau chemin
	WAYPOINT_REACHED = 2.5, -- studs : point de passage atteint
	LUNGE_DURATION = 0.22, -- secondes de déplacement d'un bond
	GUARD_FX_INTERVAL = 0.25, -- secondes minimum entre deux effets "garde" envoyés aux clients
	BLINK_RECOVERY = 0.5, -- secondes d'immobilité après une téléportation
})

local ATTRIBUTES = table.freeze({
	spawnAnchor = "SpawnAnchor", -- string : AnchorId du point d'apparition
	despawning = "Despawning", -- boolean : le corps disparaît (fondu côté client)
	rewindable = "Rewindable", -- boolean : false = hors de la timeline du rembobinage
	enraged = "Enraged", -- boolean : élite enragé
	guardBrokenUntil = "GuardBrokenUntil", -- number (heure serveur) : garde brisée jusqu'à
	practice = "PracticeParry", -- boolean : le mannequin attaque à vide (entraînement à la parade)
	returning = "Returning", -- boolean : rentre à son point d'apparition (invulnérable)
})

return table.freeze({
	ENEMIES = table.freeze(ENEMIES),
	SPAWNS = table.freeze(SPAWNS),
	AI = AI,
	ATTRIBUTES = ATTRIBUTES,

	-- Marche des rigs générés : animation officielle "R15Walk", déjà utilisée par BossConfig et DialogueConfig.
	WALK_ANIMATION_ID = "rbxassetid://507777826",
	WALK_ANIMATION_BASE_SPEED = 16, -- WalkSpeed pour laquelle l'animation est jouée à vitesse 1

	TAG = "Enemy", -- tag CollectionService de tout Model créé par EnemyService (boss compris)
	FOLDER_NAME = "Enemies", -- Workspace.Enemies
	ASSETS_FOLDER_NAME = "Enemies", -- ServerStorage.Assets.Enemies (modèles du créateur, facultatif)

	DEFAULT_RESPAWN = 45, -- secondes entre la mort et la réapparition
	DEFAULT_CORPSE_DURATION = 3, -- secondes avant le fondu du corps
	DESPAWN_FADE_DURATION = 1, -- secondes de fondu (client) avant la destruction

	EFFECTS_MAX_DISTANCE = 150, -- studs : au-delà, le client n'affiche rien (barre de vie, effets)
	TELEGRAPH_BROADCAST_RADIUS = 220, -- studs : seuls les joueurs proches reçoivent un télégraphe
})
