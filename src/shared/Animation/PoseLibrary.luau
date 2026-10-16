--!strict
--[[
	PoseLibrary (ModuleScript, partagé)
	Les mouvements du jeu, décrits UNE fois en images clés de rotations d'articulations R15. La même
	description sert à trois choses :
		1. construire de VRAIES séquences d'animation (KeyframeSequence, voir KeyframeBuilder) :
		   jouées par l'Animator dans Studio, et exportables pour être publiées dans l'Animation Editor ;
		2. un calque procédural de secours (CharacterAnimator) quand aucune piste n'est disponible ;
		3. les tests (durées, instants d'impact calés sur la validation du serveur).

	Repères (espace de chaque articulation, personnage tourné vers -Z) :
		Root          rotation du bassin entier ; Y positif = pivote vers la gauche
		Waist         X négatif = se penche en avant ; Y positif = buste tourné vers la gauche
		épaules       X positif = bras levé vers l'avant (90 = tendu devant, 170 = au-dessus de la tête)
		              Z positif = bras droit écarté vers la droite ; Z négatif = bras gauche écarté
		coudes        X positif = avant-bras replié vers l'avant ; poignets idem
		Sword         la lame dans la main (Motor6D SwordGrip -> pièce Handle) : X = lame qui bascule
		hanches       X positif = cuisse levée vers l'avant ; genoux : X négatif = jambe pliée
		pos           décalage du bassin (studs) : Y négatif = s'accroupir, Z négatif = avancer
	Chaque image clé peut préciser `e` : "linear" (mouvement vif et constant, pour la frappe) ou, par
	défaut, une courbe douce (départ et arrivée ralentis). Chaque pose déclare `impact` (instant de
	l'effet, en fraction de sa durée) : effets et fenêtre de frappe s'y calent.

	Abréviations : RS / LS épaules, RE / LE coudes, RW / LW poignets, RH / LH hanches, RK / LK genoux.
	Règle pour les rotations complètes (tourbillon, salto) : deux images clés successives ne doivent
	jamais différer de plus de 180° sur un axe (une séquence d'animation prend le chemin le plus court).
]]

export type Angles = { number } -- { x, y, z } en degrés

export type Key = {
	t: number, -- 0..1
	j: { [string]: Angles },
	pos: Vector3?,
	e: string?, -- "linear" ou nil (courbe douce)
}

export type Pose = {
	duration: number,
	looped: boolean,
	impact: number, -- fraction de la durée
	keys: { Key },
}

-- Articulation : nom du Motor6D, pièce qu'il anime (Part1) et pièce parente dans la hiérarchie
-- d'une KeyframeSequence (une Pose porte le nom de la pièce animée).
export type Joint = { motor: string, part: string, parent: string }

local JOINT_INFO: { [string]: Joint } = {
	Root = { motor = "Root", part = "LowerTorso", parent = "HumanoidRootPart" },
	Waist = { motor = "Waist", part = "UpperTorso", parent = "LowerTorso" },
	Neck = { motor = "Neck", part = "Head", parent = "UpperTorso" },
	RS = { motor = "RightShoulder", part = "RightUpperArm", parent = "UpperTorso" },
	RE = { motor = "RightElbow", part = "RightLowerArm", parent = "RightUpperArm" },
	RW = { motor = "RightWrist", part = "RightHand", parent = "RightLowerArm" },
	Sword = { motor = "SwordGrip", part = "Handle", parent = "RightHand" },
	LS = { motor = "LeftShoulder", part = "LeftUpperArm", parent = "UpperTorso" },
	LE = { motor = "LeftElbow", part = "LeftLowerArm", parent = "LeftUpperArm" },
	LW = { motor = "LeftWrist", part = "LeftHand", parent = "LeftLowerArm" },
	RH = { motor = "RightHip", part = "RightUpperLeg", parent = "LowerTorso" },
	RK = { motor = "RightKnee", part = "RightLowerLeg", parent = "RightUpperLeg" },
	LH = { motor = "LeftHip", part = "LeftUpperLeg", parent = "LowerTorso" },
	LK = { motor = "LeftKnee", part = "LeftLowerLeg", parent = "LeftUpperLeg" },
}

local JOINTS: { [string]: string } = {}
for short, info in JOINT_INFO do
	JOINTS[short] = info.motor
end

local V = Vector3.new

local function pose(duration: number, impact: number, keys: { Key }, looped: boolean?): Pose
	return { duration = duration, impact = impact, keys = keys, looped = looped == true }
end

local NEUTRAL: { [string]: Angles } = {}

local POSES: { [string]: Pose } = {
	----------------------------------------------------------------------------
	-- Épée : cinq coups distincts. Chacun : anticipation (le corps s'arme), accélération (image
	-- clé « linear »), impact (au milieu de la fenêtre de frappe du serveur), récupération.
	----------------------------------------------------------------------------
	-- 1. Entaille horizontale rapide : bassin et buste armés à droite, balayage vers la gauche.
	slash_horizontal = pose(0.36, 0.42, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.22, j = { Root = { 0, -22, 0 }, Waist = { 4, -38, 0 }, Neck = { 0, 20, 0 }, RS = { 40, 0, 100 }, RE = { 45, 0, 0 }, RW = { 0, 0, 20 }, Sword = { 0, 0, -25 }, LS = { 30, 0, -25 }, LE = { 40, 0, 0 }, RK = { -12, 0, 0 }, LK = { -12, 0, 0 } }, pos = V(0, -0.2, 0.1) },
		{ t = 0.42, e = "linear", j = { Root = { 0, 22, 0 }, Waist = { -10, 45, 0 }, Neck = { 0, -25, 0 }, RS = { 92, 0, 0 }, RE = { 5, 0, 0 }, RW = { 0, 0, -15 }, Sword = { 0, 0, 20 }, LS = { 10, 0, -60 }, RH = { 22, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.3, -0.5) },
		{ t = 0.64, j = { Root = { 0, 30, 0 }, Waist = { -12, 60, 0 }, Neck = { 0, -30, 0 }, RS = { 82, 0, -30 }, RE = { 15, 0, 0 }, Sword = { 0, 0, 30 }, LS = { 0, 0, -50 }, RH = { 18, 0, 0 } }, pos = V(0, -0.28, -0.42) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 2. Revers diagonal : lame armée haut à gauche, s'abat en diagonale vers le bas à droite.
	slash_diagonal = pose(0.34, 0.45, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.24, j = { Root = { 0, 18, 0 }, Waist = { 8, 35, 0 }, Neck = { 0, -15, 0 }, RS = { 155, 0, -40 }, RE = { 55, 0, 0 }, RW = { 20, 0, 0 }, Sword = { 25, 0, 0 }, LS = { 25, 0, -15 }, LE = { 30, 0, 0 } }, pos = V(0, 0.05, 0.12) },
		{ t = 0.45, e = "linear", j = { Root = { 0, -18, 0 }, Waist = { -18, -42, 0 }, Neck = { 0, 20, 0 }, RS = { 40, 0, 65 }, RE = { 0, 0, 0 }, RW = { -15, 0, 0 }, Sword = { -20, 0, 0 }, LS = { 30, 0, -45 }, LH = { 22, 0, 0 }, RK = { -18, 0, 0 } }, pos = V(0, -0.32, -0.45) },
		{ t = 0.66, j = { Root = { 0, -25, 0 }, Waist = { -20, -52, 0 }, RS = { 22, 0, 75 }, RE = { 10, 0, 0 }, Sword = { -25, 0, 0 }, LS = { 20, 0, -40 }, LH = { 18, 0, 0 } }, pos = V(0, -0.3, -0.38) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 3. Attaque verticale puissante : petit appel, grand armé à deux mains, frappe écrasante.
	strike_vertical = pose(0.5, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.14, j = { Waist = { 6, 0, 0 }, RK = { -15, 0, 0 }, LK = { -15, 0, 0 } }, pos = V(0, -0.2, 0) },
		{ t = 0.38, j = { Waist = { 20, 0, 0 }, Neck = { -10, 0, 0 }, RS = { 178, 0, -12 }, RE = { 40, 0, 0 }, RW = { 25, 0, 0 }, Sword = { 35, 0, 0 }, LS = { 168, 0, 22 }, LE = { 45, 0, 0 } }, pos = V(0, 0.2, 0.18) },
		{ t = 0.5, e = "linear", j = { Waist = { -38, 0, 0 }, Neck = { 16, 0, 0 }, RS = { 45, 0, -6 }, RE = { 0, 0, 0 }, RW = { -20, 0, 0 }, Sword = { -30, 0, 0 }, LS = { 50, 0, 18 }, LE = { 10, 0, 0 }, RH = { 38, 0, 0 }, RK = { -38, 0, 0 }, LH = { -12, 0, 0 }, LK = { -32, 0, 0 } }, pos = V(0, -0.85, -0.65) },
		{ t = 0.74, j = { Waist = { -30, 0, 0 }, Neck = { 12, 0, 0 }, RS = { 40, 0, 0 }, RW = { -15, 0, 0 }, Sword = { -25, 0, 0 }, LS = { 42, 0, 12 }, RH = { 32, 0, 0 }, RK = { -32, 0, 0 }, LK = { -28, 0, 0 } }, pos = V(0, -0.72, -0.58) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 4. Attaque tournoyante : armé à droite, un tour complet lame tendue, réception fléchie.
	spin_slash = pose(0.55, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.18, j = { Root = { 0, -50, 0 }, Waist = { 0, -20, 0 }, RS = { 25, 0, 88 }, RE = { 10, 0, 0 }, Sword = { 0, 0, -20 }, LS = { 25, 0, -70 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.35, 0) },
		{ t = 0.36, e = "linear", j = { Root = { 0, 60, 0 }, Waist = { -6, 10, 0 }, RS = { 15, 0, 90 }, Sword = { 0, 0, 10 }, LS = { 15, 0, -75 }, RK = { -22, 0, 0 }, LK = { -22, 0, 0 } }, pos = V(0, -0.4, -0.1) },
		{ t = 0.54, e = "linear", j = { Root = { 0, 170, 0 }, Waist = { -6, 10, 0 }, RS = { 15, 0, 90 }, Sword = { 0, 0, 10 }, LS = { 15, 0, -75 }, RK = { -22, 0, 0 }, LK = { -22, 0, 0 } }, pos = V(0, -0.4, -0.15) },
		{ t = 0.72, e = "linear", j = { Root = { 0, 280, 0 }, Waist = { -8, 12, 0 }, RS = { 18, 0, 86 }, Sword = { 0, 0, 15 }, LS = { 18, 0, -70 }, RK = { -24, 0, 0 }, LK = { -24, 0, 0 } }, pos = V(0, -0.42, -0.15) },
		{ t = 1, j = { Root = { 0, 360, 0 } } },
	}),
	-- 5. Coup final spectaculaire : accroupi, lame armée derrière, bond et grande taille plongeante.
	finisher_thrust = pose(0.7, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.12, j = { Waist = { 6, -10, 0 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.3, 0.1) },
		{ t = 0.38, j = { Root = { 0, -30, 0 }, Waist = { 14, -30, 0 }, Neck = { -6, 20, 0 }, RS = { 165, 0, 45 }, RE = { 65, 0, 0 }, RW = { 25, 0, 0 }, Sword = { 40, 0, 0 }, LS = { 85, 0, -20 }, LE = { 5, 0, 0 }, RH = { 42, 0, 0 }, RK = { -55, 0, 0 }, LH = { -15, 0, 0 }, LK = { -48, 0, 0 } }, pos = V(0, -0.95, 0.25) },
		{ t = 0.55, e = "linear", j = { Root = { 0, 15, 0 }, Waist = { -32, 25, 0 }, Neck = { 12, -10, 0 }, RS = { 28, 0, -22 }, RE = { 0, 0, 0 }, RW = { -20, 0, 0 }, Sword = { -35, 0, 0 }, LS = { -35, 0, -35 }, RH = { 55, 0, 0 }, RK = { -20, 0, 0 }, LH = { -28, 0, 0 }, LK = { -10, 0, 0 } }, pos = V(0, -0.45, -1.35) },
		{ t = 0.8, j = { Root = { 0, 10, 0 }, Waist = { -26, 18, 0 }, RS = { 20, 0, -25 }, RW = { -15, 0, 0 }, Sword = { -30, 0, 0 }, LS = { -20, 0, -25 }, RH = { 45, 0, 0 }, RK = { -25, 0, 0 }, LK = { -15, 0, 0 } }, pos = V(0, -0.58, -1.15) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Attaque chargée : la lame est ramenée haut derrière l'épaule, le corps se ramasse et tremble.
	charge_hold = pose(0.6, 0, {
		{ t = 0, j = { Waist = { 8, -30, 0 }, RS = { 130, 0, 40 }, RE = { 50, 0, 0 }, LS = { 60, 0, -30 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.4, 0.1) },
		{ t = 0.5, j = { Waist = { 9, -33, 1.5 }, RS = { 133, 0, 42 }, RE = { 52, 0, 0 }, LS = { 62, 0, -32 }, RK = { -22, 0, 0 }, LK = { -22, 0, 0 } }, pos = V(0, -0.45, 0.12) },
		{ t = 1, j = { Waist = { 8, -30, 0 }, RS = { 130, 0, 40 }, RE = { 50, 0, 0 }, LS = { 60, 0, -30 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.4, 0.1) },
	}, true),
	charged_release = pose(0.55, 0.3, {
		{ t = 0, j = { Waist = { 8, -30, 0 }, RS = { 130, 0, 40 }, RE = { 50, 0, 0 }, LS = { 60, 0, -30 } }, pos = V(0, -0.4, 0.1) },
		{ t = 0.3, j = { Waist = { -30, 40, 0 }, Neck = { 12, 0, 0 }, RS = { 60, 0, 30 }, RE = { 0, 0, 0 }, LS = { -30, 0, -20 }, RH = { 40, 0, 0 } }, pos = V(0, -0.5, -1.3) },
		{ t = 0.65, j = { Waist = { -18, 30, 0 }, RS = { 45, 0, 25 }, LS = { -10, 0, -15 } }, pos = V(0, -0.3, -0.8) },
		{ t = 1, j = NEUTRAL },
	}),
	counter_thrust = pose(0.38, 0.4, {
		{ t = 0, j = { RS = { 70, 0, -30 }, LS = { 60, 0, -20 }, Waist = { 8, 0, 0 } } },
		{ t = 0.4, j = { Waist = { -20, 20, 0 }, RS = { 92, 0, 5 }, LS = { -25, 0, -10 } }, pos = V(0, -0.3, -0.9) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Plongée : lame levée à deux mains au-dessus de la tête, jambes repliées, pendant la chute...
	plunge_dive = pose(0.4, 0, {
		{ t = 0, j = { RS = { 170, 0, 0 }, LS = { 150, 0, 10 }, RE = { 20, 0, 0 }, Waist = { 10, 0, 0 }, RH = { 30, 0, 0 }, LH = { 30, 0, 0 }, RK = { -50, 0, 0 }, LK = { -50, 0, 0 } } },
		{ t = 0.5, j = { RS = { 172, 0, 0 }, LS = { 152, 0, 10 }, RE = { 22, 0, 0 }, Waist = { 12, 0, 0 }, RH = { 32, 0, 0 }, LH = { 32, 0, 0 }, RK = { -52, 0, 0 }, LK = { -52, 0, 0 } } },
		{ t = 1, j = { RS = { 170, 0, 0 }, LS = { 150, 0, 10 }, RE = { 20, 0, 0 }, Waist = { 10, 0, 0 }, RH = { 30, 0, 0 }, LH = { 30, 0, 0 }, RK = { -50, 0, 0 }, LK = { -50, 0, 0 } } },
	}, true),
	-- ...puis, à l'atterrissage, la lame s'abat d'un coup et le corps s'écrase dans un genou fléchi.
	plunge_strike = pose(0.5, 0.15, {
		{ t = 0, j = { RS = { 170, 0, 0 }, LS = { 150, 0, 10 }, Waist = { 10, 0, 0 } } },
		{ t = 0.15, j = { RS = { 10, 0, 0 }, LS = { 20, 0, 0 }, Waist = { -35, 0, 0 }, RK = { -50, 0, 0 }, LK = { -50, 0, 0 } }, pos = V(0, -0.9, -0.3) },
		{ t = 0.6, j = { RS = { 15, 0, 0 }, LS = { 22, 0, 0 }, Waist = { -30, 0, 0 }, RK = { -45, 0, 0 }, LK = { -45, 0, 0 } }, pos = V(0, -0.8, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),

	----------------------------------------------------------------------------
	-- Défense et réactions
	----------------------------------------------------------------------------
	parry_guard = pose(0.35, 0.15, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.25, j = { Waist = { 8, 15, 0 }, RS = { 75, 0, -35 }, RE = { 40, 0, 0 }, LS = { 65, 0, -20 }, LE = { 50, 0, 0 } }, pos = V(0, -0.2, 0.15) },
		{ t = 0.7, j = { Waist = { 8, 15, 0 }, RS = { 75, 0, -35 }, RE = { 40, 0, 0 }, LS = { 65, 0, -20 }, LE = { 50, 0, 0 } }, pos = V(0, -0.2, 0.15) },
		{ t = 1, j = NEUTRAL },
	}),
	parry_riposte = pose(0.4, 0.25, {
		{ t = 0, j = { RS = { 75, 0, -35 }, LS = { 65, 0, -20 } } },
		{ t = 0.25, j = { Waist = { -10, -35, 0 }, RS = { 60, 0, 70 }, LS = { 20, 0, -30 } }, pos = V(0, -0.15, -0.2) },
		{ t = 1, j = NEUTRAL },
	}),
	hit_flinch = pose(0.32, 0.1, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.18, j = { Waist = { 18, 6, 4 }, Neck = { 16, -8, 0 }, RS = { -10, 0, 20 }, LS = { -10, 0, -20 } }, pos = V(0, -0.1, 0.25) },
		{ t = 1, j = NEUTRAL },
	}),
	stagger = pose(1.2, 0.1, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.15, j = { Waist = { 24, 10, 6 }, Neck = { 22, 0, 0 }, RS = { -20, 0, 35 }, LS = { -15, 0, -35 }, RK = { -25, 0, 0 } }, pos = V(0, -0.35, 0.35) },
		{ t = 0.75, j = { Waist = { 20, -6, -4 }, Neck = { 18, 0, 0 }, RS = { -15, 0, 30 }, LS = { -10, 0, -30 }, RK = { -20, 0, 0 } }, pos = V(0, -0.3, 0.3) },
		{ t = 1, j = NEUTRAL },
	}),

	----------------------------------------------------------------------------
	-- Déplacements
	----------------------------------------------------------------------------
	dash_lean = pose(0.24, 0, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.2, j = { Waist = { -30, 0, 0 }, RS = { -40, 0, 15 }, LS = { -40, 0, -15 }, RH = { 30, 0, 0 }, LK = { -40, 0, 0 } }, pos = V(0, -0.35, 0) },
		{ t = 0.8, j = { Waist = { -26, 0, 0 }, RS = { -35, 0, 12 }, LS = { -35, 0, -12 } }, pos = V(0, -0.3, 0) },
		{ t = 1, j = NEUTRAL },
	}),
	double_jump_flip = pose(0.48, 0.05, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.25, j = { Root = { -120, 0, 0 }, RH = { 80, 0, 0 }, LH = { 80, 0, 0 }, RK = { -100, 0, 0 }, LK = { -100, 0, 0 }, RS = { 60, 0, 20 }, LS = { 60, 0, -20 } } },
		{ t = 0.6, j = { Root = { -260, 0, 0 }, RH = { 85, 0, 0 }, LH = { 85, 0, 0 }, RK = { -110, 0, 0 }, LK = { -110, 0, 0 }, RS = { 70, 0, 20 }, LS = { 70, 0, -20 } } },
		{ t = 1, j = { Root = { -360, 0, 0 } } },
	}),
	land_dip = pose(0.3, 0, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.25, j = { Waist = { -10, 0, 0 }, RH = { 30, 0, 0 }, LH = { 30, 0, 0 }, RK = { -40, 0, 0 }, LK = { -40, 0, 0 }, RS = { 15, 0, 20 }, LS = { 15, 0, -20 } }, pos = V(0, -0.55, 0) },
		{ t = 1, j = NEUTRAL },
	}),

	----------------------------------------------------------------------------
	-- Magie : chaque élément a sa gestuelle
	----------------------------------------------------------------------------
	concentrate = pose(2.4, 0, {
		{ t = 0, j = { RS = { 65, 0, 18 }, RE = { 45, 0, 0 }, LS = { 65, 0, -18 }, LE = { 45, 0, 0 }, Neck = { 10, 0, 0 } }, pos = V(0, 0.15, 0) },
		{ t = 0.5, j = { RS = { 70, 0, 20 }, RE = { 50, 0, 0 }, LS = { 70, 0, -20 }, LE = { 50, 0, 0 }, Neck = { 12, 0, 0 } }, pos = V(0, 0.4, 0) },
		{ t = 1, j = { RS = { 65, 0, 18 }, RE = { 45, 0, 0 }, LS = { 65, 0, -18 }, LE = { 45, 0, 0 }, Neck = { 10, 0, 0 } }, pos = V(0, 0.15, 0) },
	}, true),
	-- Pyromancie : gestes amples, projection énergique.
	cast_fire_throw = pose(0.55, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.4, j = { Waist = { 6, -28, 0 }, RS = { -25, 0, 45 }, RE = { 60, 0, 0 }, LS = { 50, 0, -25 } }, pos = V(0, -0.2, 0.15) },
		{ t = 0.52, j = { Waist = { -14, 22, 0 }, RS = { 92, 0, 5 }, RE = { 0, 0, 0 }, LS = { -20, 0, -20 } }, pos = V(0, -0.25, -0.45) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_fire_slam = pose(0.8, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.4, j = { Waist = { 12, 0, 0 }, RS = { 160, 0, 15 }, LS = { 30, 0, -30 } }, pos = V(0, 0.15, 0) },
		{ t = 0.56, j = { Waist = { -32, 0, 0 }, RS = { 35, 0, 10 }, RE = { 10, 0, 0 }, LS = { 10, 0, -40 }, RK = { -45, 0, 0 }, LK = { -45, 0, 0 } }, pos = V(0, -1, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Glace : lent, précis, fluide.
	cast_ice_shard = pose(0.5, 0.4, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.22, j = { Waist = { 4, -20, 0 }, RS = { 40, 0, 30 }, RE = { 85, 0, 0 }, RW = { 20, 0, 0 }, LS = { 55, 0, -35 }, LE = { 75, 0, 0 } }, pos = V(0, -0.1, 0.1) },
		{ t = 0.4, e = "linear", j = { Waist = { -8, 18, 0 }, RS = { 92, 0, -4 }, RE = { 0, 0, 0 }, RW = { -10, 0, 0 }, LS = { 50, 0, -30 }, LE = { 80, 0, 0 } }, pos = V(0, -0.1, -0.3) },
		{ t = 0.62, j = { Waist = { -6, 14, 0 }, RS = { 85, 0, 0 }, LS = { 45, 0, -28 }, LE = { 70, 0, 0 } }, pos = V(0, -0.08, -0.25) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_ice_seal = pose(0.95, 0.58, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { Waist = { 8, 0, 0 }, RS = { 70, 0, -20 }, LS = { 70, 0, 20 }, RE = { 70, 0, 0 }, LE = { 70, 0, 0 }, RK = { -15, 0, 0 }, LK = { -15, 0, 0 } }, pos = V(0, -0.2, 0) },
		{ t = 0.58, e = "linear", j = { Waist = { -18, 0, 0 }, Neck = { 10, 0, 0 }, RS = { 60, 0, 55 }, LS = { 60, 0, -55 }, RE = { 0, 0, 0 }, LE = { 0, 0, 0 }, RW = { -30, 0, 0 }, LW = { -30, 0, 0 }, RK = { -30, 0, 0 }, LK = { -30, 0, 0 } }, pos = V(0, -0.55, -0.1) },
		{ t = 0.8, j = { Waist = { -12, 0, 0 }, RS = { 55, 0, 50 }, LS = { 55, 0, -50 }, RK = { -22, 0, 0 }, LK = { -22, 0, 0 } }, pos = V(0, -0.4, -0.08) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Foudre : bref, nerveux.
	cast_lightning_snap = pose(0.3, 0.45, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { Waist = { 0, -25, 0 }, RS = { 40, 0, 50 }, RE = { 70, 0, 0 } } },
		{ t = 0.45, j = { Waist = { -10, 25, 0 }, RS = { 96, 0, 0 }, RE = { 0, 0, 0 }, LS = { -30, 0, -25 } }, pos = V(0, -0.1, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_lightning_call = pose(0.55, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.35, j = { RS = { 170, 0, 5 }, RE = { 0, 0, 0 }, Neck = { -15, 0, 0 }, Waist = { 8, 0, 0 } } },
		{ t = 0.55, j = { RS = { 92, 0, 0 }, Waist = { -12, 0, 0 }, LS = { -30, 0, -30 } }, pos = V(0, -0.2, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Ombre : lent, souple, enveloppant.
	cast_shadow_sweep = pose(0.7, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.4, j = { Waist = { -6, 30, 0 }, RS = { 70, 0, -45 }, RE = { 40, 0, 0 }, LS = { 30, 0, -40 } } },
		{ t = 0.58, j = { Waist = { -10, -20, 0 }, RS = { 85, 0, 40 }, RE = { 10, 0, 0 }, LS = { 20, 0, -50 } }, pos = V(0, -0.2, -0.2) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_shadow_veil = pose(0.85, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.45, j = { RS = { 60, 0, -45 }, LS = { 60, 0, 45 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { 12, 0, 0 } }, pos = V(0, -0.35, 0) },
		{ t = 0.6, j = { RS = { 40, 0, 80 }, LS = { 40, 0, -80 }, Waist = { 4, 0, 0 } }, pos = V(0, 0, 0) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Antimatière : maîtrisé, mains en suspension, contraction de l'espace.
	cast_void_push = pose(0.6, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { Waist = { 6, -10, 0 }, RS = { 45, 0, 10 }, RE = { 100, 0, 0 }, RW = { 30, 0, 0 }, LS = { 50, 0, -10 }, LE = { 95, 0, 0 } }, pos = V(0, 0.05, 0.15) },
		{ t = 0.5, e = "linear", j = { Waist = { -10, 8, 0 }, RS = { 90, 0, 2 }, RE = { 0, 0, 0 }, RW = { -20, 0, 0 }, LS = { 40, 0, -30 }, LE = { 60, 0, 0 } }, pos = V(0, 0, -0.35) },
		{ t = 0.72, j = { Waist = { -6, 6, 0 }, RS = { 85, 0, 0 }, LS = { 35, 0, -28 }, LE = { 50, 0, 0 } }, pos = V(0, 0, -0.25) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_void_contract = pose(0.85, 0.6, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.32, j = { Waist = { 4, 0, 0 }, RS = { 90, 0, 40 }, LS = { 90, 0, -40 }, RE = { 0, 0, 0 }, LE = { 0, 0, 0 } }, pos = V(0, 0.2, 0) },
		{ t = 0.6, e = "linear", j = { Waist = { 12, 0, 0 }, Neck = { -6, 0, 0 }, RS = { 80, 0, -12 }, LS = { 80, 0, 12 }, RE = { 70, 0, 0 }, LE = { 70, 0, 0 }, RW = { 30, 0, 0 }, LW = { 30, 0, 0 } }, pos = V(0, 0.3, 0.15) },
		{ t = 0.8, j = { Waist = { 8, 0, 0 }, RS = { 75, 0, -10 }, LS = { 75, 0, 10 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }, pos = V(0, 0.25, 0.1) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Gravité : imposant, vers le sol ou vers la cible.
	cast_gravity_press = pose(0.75, 0.6, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.45, j = { RS = { 125, 0, 10 }, RE = { 10, 0, 0 }, Waist = { 8, 0, 0 } }, pos = V(0, 0.1, 0) },
		{ t = 0.62, j = { RS = { 35, 0, 5 }, RE = { 0, 0, 0 }, Waist = { -14, 0, 0 } }, pos = V(0, -0.4, -0.15) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_gravity_field = pose(1, 0.62, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.45, j = { RS = { 155, 0, 20 }, LS = { 155, 0, -20 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 } }, pos = V(0, 0.2, 0) },
		{ t = 0.64, j = { RS = { 15, 0, 25 }, LS = { 15, 0, -25 }, Waist = { -26, 0, 0 }, RK = { -40, 0, 0 }, LK = { -40, 0, 0 } }, pos = V(0, -0.9, 0) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Ultime Glace « Hiver Éternel » : accroupi, bras croisés qui rassemblent le froid, montée,
	-- puis les deux paumes frappent le sol (impact = fin de la préparation, 0,85 s).
	cast_ultimate_ice = pose(1.3, 0.654, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.2, j = { Waist = { 14, 0, 0 }, Neck = { 12, 0, 0 }, RS = { 70, 0, -35 }, LS = { 70, 0, 35 }, RE = { 95, 0, 0 }, LE = { 95, 0, 0 }, RK = { -30, 0, 0 }, LK = { -30, 0, 0 }, RH = { 15, 0, 0 }, LH = { 15, 0, 0 } }, pos = V(0, -0.5, 0.1) },
		{ t = 0.48, j = { Waist = { 4, 0, 0 }, Neck = { -18, 0, 0 }, RS = { 165, 0, 35 }, LS = { 165, 0, -35 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, RW = { 20, 0, 0 }, LW = { 20, 0, 0 } }, pos = V(0, 0.35, 0) },
		{ t = 0.654, e = "linear", j = { Waist = { -40, 0, 0 }, Neck = { 22, 0, 0 }, RS = { 30, 0, 25 }, LS = { 30, 0, -25 }, RE = { 0, 0, 0 }, LE = { 0, 0, 0 }, RW = { -60, 0, 0 }, LW = { -60, 0, 0 }, RH = { 40, 0, 0 }, RK = { -70, 0, 0 }, LH = { -10, 0, 0 }, LK = { -60, 0, 0 } }, pos = V(0, -1.2, -0.2) },
		{ t = 0.85, j = { Waist = { -32, 0, 0 }, Neck = { 16, 0, 0 }, RS = { 28, 0, 25 }, LS = { 28, 0, -25 }, RW = { -50, 0, 0 }, LW = { -50, 0, 0 }, RH = { 35, 0, 0 }, RK = { -60, 0, 0 }, LK = { -50, 0, 0 } }, pos = V(0, -1.05, -0.18) },
		{ t = 1, j = NEUTRAL },
	}),
	-- Ultime Antimatière : mains rapprochées devant la poitrine qui compriment le vide en tremblant,
	-- puis bras projetés en arrière, torse ouvert (impact = 0,75 s).
	cast_ultimate_antimatter = pose(1.2, 0.625, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.25, j = { Waist = { 8, 0, 0 }, RS = { 85, 0, 20 }, LS = { 85, 0, -20 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 }, RK = { -12, 0, 0 }, LK = { -12, 0, 0 } }, pos = V(0, -0.15, 0.05) },
		{ t = 0.45, j = { Waist = { 12, 2, 0 }, Neck = { 8, 0, 0 }, RS = { 80, 0, -8 }, LS = { 80, 0, 8 }, RE = { 85, 0, 0 }, LE = { 85, 0, 0 }, RW = { 25, 0, 0 }, LW = { 25, 0, 0 }, RK = { -18, 0, 0 }, LK = { -18, 0, 0 } }, pos = V(0, -0.25, 0.1) },
		{ t = 0.56, j = { Waist = { 13, -2, 0 }, Neck = { 9, 0, 0 }, RS = { 82, 0, -10 }, LS = { 82, 0, 10 }, RE = { 88, 0, 0 }, LE = { 88, 0, 0 }, RW = { 28, 0, 0 }, LW = { 28, 0, 0 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } }, pos = V(0, -0.28, 0.1) },
		{ t = 0.625, e = "linear", j = { Waist = { -20, 0, 0 }, Neck = { -14, 0, 0 }, RS = { 100, 0, 95 }, LS = { 100, 0, -95 }, RE = { 0, 0, 0 }, LE = { 0, 0, 0 }, RW = { -20, 0, 0 }, LW = { -20, 0, 0 } }, pos = V(0, 0.15, 0.2) },
		{ t = 0.85, j = { Waist = { -14, 0, 0 }, RS = { 90, 0, 85 }, LS = { 90, 0, -85 } }, pos = V(0, 0.1, 0.15) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_ultimate = pose(0.9, 0.3, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { RS = { 160, 0, 30 }, LS = { 160, 0, -30 }, Waist = { 14, 0, 0 }, Neck = { -18, 0, 0 } }, pos = V(0, 0.5, 0) },
		{ t = 0.7, j = { RS = { 120, 0, 60 }, LS = { 120, 0, -60 }, Waist = { 10, 0, 0 } }, pos = V(0, 0.4, 0) },
		{ t = 1, j = NEUTRAL },
	}),
}

local PoseLibrary = {}

PoseLibrary.JOINTS = JOINTS
PoseLibrary.JOINT_INFO = JOINT_INFO
PoseLibrary.POSES = POSES

-- Adoucissement entre deux images clés (départ et arrivée lents).
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

--[[
	Échantillonne `poseName` à la fraction `alpha` (0..1) : retourne, par nom court d'articulation,
	les angles (radians) et le décalage du bassin. Une articulation absente d'une image clé vaut 0.
]]
function PoseLibrary.sample(poseName: string, alpha: number): ({ [string]: Vector3 }, Vector3)
	local definition = POSES[poseName]
	local result: { [string]: Vector3 } = {}
	if definition == nil then
		return result, Vector3.zero
	end
	local keys = definition.keys
	local t = if definition.looped then alpha % 1 else math.clamp(alpha, 0, 1)
	local previous, following = keys[1], keys[#keys]
	for index = 1, #keys - 1 do
		if t >= keys[index].t and t <= keys[index + 1].t then
			previous, following = keys[index], keys[index + 1]
			break
		end
	end
	local span = following.t - previous.t
	local linear = if span > 1e-6 then (t - previous.t) / span else 1
	local blend = if following.e == "linear" then linear else smooth(linear)
	local seen: { [string]: boolean } = {}
	for name in previous.j do
		seen[name] = true
	end
	for name in following.j do
		seen[name] = true
	end
	for name in seen do
		local a = previous.j[name] or { 0, 0, 0 }
		local b = following.j[name] or { 0, 0, 0 }
		result[name] = Vector3.new(
			math.rad(a[1] + (b[1] - a[1]) * blend),
			math.rad(a[2] + (b[2] - a[2]) * blend),
			math.rad(a[3] + (b[3] - a[3]) * blend)
		)
	end
	local fromPos = previous.pos or Vector3.zero
	local toPos = following.pos or Vector3.zero
	return result, fromPos:Lerp(toPos, blend)
end

function PoseLibrary.get(poseName: string): Pose?
	return POSES[poseName]
end

return PoseLibrary
