--!strict
--[[
	CombatConfig
	Constantes partagées (serveur + client) du combat : épée, Tension et pouvoir ultime.
	(Les caractéristiques propres à chaque ultime sont dans Shared/Magic/MagicConfig.)

	>>> ANIMATIONS : c'est ici qu'on renseigne les ID, dans le champ `animationId` de chaque coup
	>>> du COMBO, au format "rbxassetid://1234567890". Un champ vide ("") = coup sans animation.
	>>> Les ID actuels sont les animations d'épée officielles de Roblox (jouables dans tous les jeux).
	>>> Une animation personnalisée doit appartenir au propriétaire du jeu, sinon elle ne se charge pas.
	>>> En changeant d'animation, ajuster duration / hitStart / hitEnd pour coller à elle.
]]

export type ComboStep = {
	name: string,
	damage: number,
	duration: number, -- durée totale du coup (s) ; le coup suivant ne peut pas partir avant
	hitStart: number, -- début de la fenêtre de frappe, depuis le début du coup (s)
	hitEnd: number, -- fin de la fenêtre de frappe (s)
	reachBonus: number, -- allonge supplémentaire (studs) : la zone de frappe s'étire d'autant vers l'avant
	knockback: number, -- vitesse (studs/s) à laquelle la cible est éjectée en arrière ; 0 = aucune
	animationId: string,
	animationSpeed: number, -- 1 = vitesse d'origine ; plus haut = coup plus sec
}

local SWORD_SLASH_ANIMATION = "rbxassetid://522635514" -- "R15 Sword Slash" (Roblox)
local SWORD_LUNGE_ANIMATION = "rbxassetid://522638767" -- "R15 Sword Lunge" (Roblox)

local COMBO: { ComboStep } = {
	{
		name = "Entaille", -- ouverture très rapide
		damage = 10,
		duration = 0.32,
		hitStart = 0.04,
		hitEnd = 0.24,
		reachBonus = 0,
		knockback = 0,
		animationId = SWORD_SLASH_ANIMATION,
		animationSpeed = 1.6,
	},
	{
		name = "Revers", -- encore plus sec (même animation en attendant un vrai slash inversé)
		damage = 10,
		duration = 0.3,
		hitStart = 0.04,
		hitEnd = 0.22,
		reachBonus = 0,
		knockback = 0,
		animationId = SWORD_SLASH_ANIMATION,
		animationSpeed = 1.8,
	},
	{
		name = "Brise-ciel", -- coup final lourd : de l'allonge, et la cible est éjectée
		damage = 26,
		duration = 0.65,
		hitStart = 0.12,
		hitEnd = 0.45,
		reachBonus = 2.5,
		knockback = 55,
		animationId = SWORD_LUNGE_ANIMATION,
		animationSpeed = 1.2,
	},
}

return table.freeze({
	-- Combo ------------------------------------------------------------------
	COMBO = COMBO,
	COMBO_RESET_DELAY = 0.5, -- après la fin d'un coup, délai (s) pour enchaîner avant de repartir au coup 1
	ATTACK_INPUT = Enum.UserInputType.MouseButton1,
	ANIMATION_FADE_TIME = 0.05, -- fondu d'entrée des animations de coup (s) : court = nerveux
	-- Hit-stop : à chaque coup qui porte, attaquant et cible se figent ce court instant.
	-- C'est ce micro-arrêt qui donne du poids à la lame.
	HIT_STOP_DURATION = 0.05,

	-- Zone de frappe -----------------------------------------------------------
	-- Une boîte posée juste devant le joueur : largeur (X), hauteur (Y), profondeur (Z) en studs.
	-- Tout ennemi qui y a ne serait-ce qu'une pièce pendant la fenêtre de frappe prend le coup,
	-- où que passe le modèle 3D de l'épée.
	HITBOX_SIZE = Vector3.new(6, 6, 6),
	-- Marge du serveur (studs) quand il revérifie la distance : absorbe la latence et les déplacements.
	HITBOX_RANGE_TOLERANCE = 3,

	-- Soft-lock : au départ de chaque coup, le joueur se tourne vers l'ennemi le plus proche
	-- dans ce rayon (studs). 0 = désactivé.
	SOFT_LOCK_RADIUS = 15,

	-- Éjection (coups dont `knockback` > 0) ---------------------------------------
	KNOCKBACK_DURATION = 0.2, -- secondes de poussée
	KNOCKBACK_LIFT = 14, -- vitesse verticale (studs/s) : la cible décolle légèrement du sol

	-- Épée -------------------------------------------------------------------
	-- Modèle optionnel : ServerStorage > Assets > Sword. S'il est absent, une épée provisoire en Parts est générée.
	ASSETS_FOLDER_NAME = "Assets",
	SWORD_NAME = "Sword",
	SWORD_MOTOR_NAME = "SwordGrip", -- Motor6D main -> épée
	HAND_NAME = "RightHand", -- main qui tient l'épée (rig R15)
	GRIP_ATTACHMENT_NAME = "RightGripAttachment", -- point de prise dans cette main
	BLADE_START_NAME = "BladeStart", -- Attachment à la base de la lame
	BLADE_END_NAME = "BladeEnd", -- Attachment à la pointe
	BLADE_TRAIL_NAME = "BladeTrail", -- Trail tendu entre ces deux Attachments
	SWORD_GRIP_OFFSET = CFrame.new(), -- correction de la prise en main (position / rotation)

	-- Validation (serveur) -----------------------------------------------------
	LATENCY_TOLERANCE = 0.25, -- marge (s) sur tous les contrôles de timing
	PVP_ENABLED = true, -- les joueurs peuvent-ils se blesser entre eux ?
	-- Attribut (boolean) qu'un système serveur pose sur un Model pour le rendre intouchable
	-- (ex. : le boss pendant sa charge). Ni l'épée ni l'ultime ne blessent une cible qui le porte.
	INVULNERABLE_ATTRIBUTE = "Invulnerable",

	-- Tension ------------------------------------------------------------------
	-- Stockée par le serveur dans un attribut du Player : elle est répliquée toute seule
	-- au client, qui ne peut que la lire.
	TENSION_ATTRIBUTE = "Tension",
	TENSION_MAX = 100,
	TENSION_PER_HIT = 20, -- gagnée à chaque coup d'épée validé par le serveur

	-- Pouvoir ultime -------------------------------------------------------------
	-- Nom, rayon, dégâts et couleurs dépendent de la Magie Innée du joueur : voir MagicConfig.
	ULTIMATE_INPUT = Enum.KeyCode.E,
	-- Arrêt sur image joué par les clients avant l'explosion ; le serveur attend la même durée
	-- avant d'infliger les dégâts, pour qu'ils tombent au moment où l'onde de choc part.
	ULTIMATE_HIT_STOP = 0.2,

	DEBUG_LOGS = true,
})
