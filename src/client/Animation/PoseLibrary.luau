--!strict
--[[
	PoseLibrary (ModuleScript, client)
	Poses PROCÉDURALES des personnages R15 : des images clés de rotations d'articulations, rejouées
	par CharacterAnimator par-dessus les animations de base de Roblox (marche, course, saut).

	Repères (espace de chaque articulation, personnage tourné vers -Z) :
		Waist / Root  X négatif = se penche en avant ; Y positif = pivote vers la gauche
		épaules       X positif = bras levé vers l'avant (90 = tendu devant, 170 = au-dessus de la tête)
		              Z positif = bras droit écarté vers la droite ; Z négatif = bras gauche écarté
		coudes        X positif = avant-bras replié vers l'avant
		hanches       X positif = cuisse levée vers l'avant ; genoux : X négatif = jambe pliée
		pos           décalage du bassin (studs) : Y négatif = s'accroupir, Z négatif = avancer
	Chaque pose déclare `impact` (instant de l'effet, en fraction de sa durée) : les effets visuels et
	la fenêtre de frappe s'y calent. Les durées sont les durées PAR DÉFAUT ; l'action peut les étirer.

	Abréviations : RS / LS épaules droite / gauche, RE / LE coudes, RH / LH hanches, RK / LK genoux.
]]

export type Angles = { number } -- { x, y, z } en degrés

export type Key = {
	t: number, -- 0..1
	j: { [string]: Angles },
	pos: Vector3?,
}

export type Pose = {
	duration: number,
	looped: boolean,
	impact: number, -- fraction de la durée
	keys: { Key },
}

local JOINTS: { [string]: string } = {
	Root = "Root",
	Waist = "Waist",
	Neck = "Neck",
	RS = "RightShoulder",
	RE = "RightElbow",
	LS = "LeftShoulder",
	LE = "LeftElbow",
	RH = "RightHip",
	RK = "RightKnee",
	LH = "LeftHip",
	LK = "LeftKnee",
}

local V = Vector3.new

local function pose(duration: number, impact: number, keys: { Key }, looped: boolean?): Pose
	return { duration = duration, impact = impact, keys = keys, looped = looped == true }
end

local NEUTRAL: { [string]: Angles } = {}

local POSES: { [string]: Pose } = {
	----------------------------------------------------------------------------
	-- Épée : cinq coups distincts
	----------------------------------------------------------------------------
	-- 1. Horizontal rapide : armé à droite, balayage vers la gauche.
	slash_horizontal = pose(0.36, 0.42, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.28, j = { Waist = { 0, -38, 0 }, RS = { 25, 0, 85 }, RE = { 35, 0, 0 }, LS = { 20, 0, -25 } } },
		{ t = 0.5, j = { Waist = { -6, 42, 0 }, RS = { 88, 0, 10 }, RE = { 5, 0, 0 }, LS = { 10, 0, -45 } }, pos = V(0, -0.15, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 2. Diagonale inverse : de haut à gauche vers bas à droite.
	slash_diagonal = pose(0.34, 0.45, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { Waist = { 6, 32, 0 }, RS = { 150, 0, -30 }, RE = { 40, 0, 0 }, LS = { 30, 0, -20 } } },
		{ t = 0.52, j = { Waist = { -12, -36, 0 }, RS = { 45, 0, 55 }, RE = { 5, 0, 0 }, LS = { 15, 0, -40 } }, pos = V(0, -0.2, -0.35) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 3. Verticale à deux mains : grand armé au-dessus de la tête, frappe vers le bas.
	strike_vertical = pose(0.5, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.34, j = { Waist = { 14, 0, 0 }, Neck = { -6, 0, 0 }, RS = { 172, 0, -8 }, RE = { 30, 0, 0 }, LS = { 160, 0, 15 }, LE = { 35, 0, 0 } }, pos = V(0, 0.1, 0.1) },
		{ t = 0.52, j = { Waist = { -28, 0, 0 }, Neck = { 12, 0, 0 }, RS = { 40, 0, -5 }, RE = { 0, 0, 0 }, LS = { 45, 0, 10 }, RH = { 25, 0, 0 }, LK = { -25, 0, 0 } }, pos = V(0, -0.65, -0.5) },
		{ t = 0.75, j = { Waist = { -18, 0, 0 }, RS = { 35, 0, 0 }, LS = { 35, 0, 0 } }, pos = V(0, -0.4, -0.3) },
		{ t = 1, j = NEUTRAL },
	}),
	-- 4. Tournoyant : le corps fait un tour complet, lame tendue.
	spin_slash = pose(0.55, 0.5, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.22, j = { Root = { 0, -60, 0 }, RS = { 20, 0, 80 }, LS = { 20, 0, -60 } }, pos = V(0, -0.3, 0) },
		{ t = 0.48, j = { Root = { 0, 120, 0 }, RS = { 10, 0, 88 }, LS = { 10, 0, -70 } }, pos = V(0, -0.35, 0) },
		{ t = 0.74, j = { Root = { 0, 300, 0 }, RS = { 15, 0, 85 }, LS = { 15, 0, -65 } }, pos = V(0, -0.3, 0) },
		{ t = 1, j = { Root = { 0, 360, 0 } } },
	}),
	-- 5. Final : appel au sol, bond et estoc puissant.
	finisher_thrust = pose(0.7, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.35, j = { Waist = { 10, -20, 0 }, RS = { -25, 0, 25 }, RE = { 70, 0, 0 }, LS = { 70, 0, -20 }, RH = { 35, 0, 0 }, RK = { -40, 0, 0 }, LK = { -35, 0, 0 } }, pos = V(0, -0.85, 0.2) },
		{ t = 0.55, j = { Waist = { -22, 15, 0 }, Neck = { 10, 0, 0 }, RS = { 95, 0, 5 }, RE = { 0, 0, 0 }, LS = { -40, 0, -15 }, LH = { -20, 0, 0 }, RH = { 40, 0, 0 } }, pos = V(0, -0.35, -1.1) },
		{ t = 0.8, j = { Waist = { -12, 8, 0 }, RS = { 80, 0, 10 }, LS = { -20, 0, -10 } }, pos = V(0, -0.2, -0.6) },
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
	plunge_strike = pose(0.45, 0.55, {
		{ t = 0, j = { RS = { 170, 0, 0 }, LS = { 150, 0, 0 }, Waist = { 10, 0, 0 } } },
		{ t = 0.55, j = { RS = { 10, 0, 0 }, LS = { 20, 0, 0 }, Waist = { -35, 0, 0 }, RK = { -50, 0, 0 }, LK = { -50, 0, 0 } }, pos = V(0, -0.9, -0.3) },
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
	cast_ice_shard = pose(0.65, 0.55, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.45, j = { RS = { 82, 8, 6 }, RE = { 12, 0, 0 }, LS = { 60, 0, -32 }, LE = { 70, 0, 0 }, Waist = { 0, 8, 0 } } },
		{ t = 0.58, j = { RS = { 88, 0, 0 }, RE = { 0, 0, 0 }, LS = { 58, 0, -30 }, LE = { 70, 0, 0 }, Waist = { -4, 10, 0 } }, pos = V(0, 0, -0.15) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_ice_seal = pose(0.95, 0.6, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.4, j = { RS = { 80, 0, 6 }, LS = { 80, 0, -6 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 } } },
		{ t = 0.62, j = { RS = { 75, 0, 72 }, LS = { 75, 0, -72 }, Waist = { 6, 0, 0 }, Neck = { -6, 0, 0 } }, pos = V(0, 0.2, 0) },
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
	cast_void_push = pose(0.75, 0.6, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.5, j = { RS = { 88, 0, 4 }, RE = { 25, 0, 0 }, LS = { 55, 0, -25 }, LE = { 80, 0, 0 } }, pos = V(0, 0.25, 0) },
		{ t = 0.62, j = { RS = { 92, 0, 0 }, RE = { 0, 0, 0 }, LS = { 55, 0, -25 }, LE = { 80, 0, 0 }, Waist = { -6, 0, 0 } }, pos = V(0, 0.2, -0.2) },
		{ t = 1, j = NEUTRAL },
	}),
	cast_void_contract = pose(1.05, 0.65, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.45, j = { RS = { 90, 0, 14 }, LS = { 90, 0, -14 }, RE = { 0, 0, 0 }, LE = { 0, 0, 0 } }, pos = V(0, 0.3, 0) },
		{ t = 0.66, j = { RS = { 50, 0, -10 }, LS = { 50, 0, 10 }, RE = { 90, 0, 0 }, LE = { 90, 0, 0 }, Waist = { 8, 0, 0 } }, pos = V(0, 0.35, 0.15) },
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
	cast_ultimate = pose(0.9, 0.3, {
		{ t = 0, j = NEUTRAL },
		{ t = 0.3, j = { RS = { 160, 0, 30 }, LS = { 160, 0, -30 }, Waist = { 14, 0, 0 }, Neck = { -18, 0, 0 } }, pos = V(0, 0.5, 0) },
		{ t = 0.7, j = { RS = { 120, 0, 60 }, LS = { 120, 0, -60 }, Waist = { 10, 0, 0 } }, pos = V(0, 0.4, 0) },
		{ t = 1, j = NEUTRAL },
	}),
}

local PoseLibrary = {}

PoseLibrary.JOINTS = JOINTS
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
	local blend = if span > 1e-6 then smooth((t - previous.t) / span) else 1
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
