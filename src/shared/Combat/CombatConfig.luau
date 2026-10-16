--!strict
--[[
	CombatConfig
	Constantes partagées (serveur + client) du combat : épée, posture des ennemis, pouvoir ultime.
	(Mana, Tension et Concentration : Shared/Combat/ResourceConfig. Sorts : Shared/Magic/SpellConfig.)

	ATTAQUES (Combat 2.0). Chaque attaque a un `action` (AnimationConfig : pose ou clip) dont la durée
	et l'instant d'impact sont calés sur `duration` / `hitStart` / `hitEnd` ci-dessous. Le SERVEUR
	vérifie ces fenêtres (marge LATENCY_TOLERANCE) : changer une pose demande d'ajuster ses nombres.
		COMBO      cinq coups distincts enchaînés au clic (fenêtre de mise en file, sans spam) ;
		CHARGED    clic maintenu : préparation (ralenti, vulnérable), frappe d'autant plus forte ;
		COUNTER    riposte après une parade parfaite (fenêtre COUNTER_WINDOW) ;
		PLUNGE     attaque plongeante depuis un saut (extension aérienne contrôlée).
	Toutes les attaques gardent la même logique : zone de frappe côté client, validation complète
	côté serveur (fenêtre, portée, ligne de vue, une touche par cible), dégâts via DamageService.
]]

export type AttackStep = {
	name: string,
	action: string, -- clé d'AnimationConfig.ACTIONS
	damage: number,
	duration: number, -- durée totale du coup (s) ; le coup suivant ne peut pas partir avant
	hitStart: number, -- début de la fenêtre de frappe, depuis le début du coup (s)
	hitEnd: number, -- fin de la fenêtre de frappe (s)
	reachBonus: number, -- allonge supplémentaire (studs) : la zone de frappe s'étire d'autant vers l'avant
	widthBonus: number, -- largeur supplémentaire (studs)
	centered: boolean, -- zone centrée sur le personnage (coup tournoyant, plongée)
	knockback: number, -- vitesse (studs/s) d'éjection de la cible ; 0 = aucune
	posture: number, -- dégâts de posture infligés
	heavy: boolean, -- coup lourd : brise les gardes frontales
	hitStop: number, -- arrêt sur image à l'impact (s)
	tension: string, -- source de Tension (ResourceConfig.TENSION_SOURCES)
}

local function step(fields: { [string]: any }): AttackStep
	return {
		name = fields.name,
		action = fields.action,
		damage = fields.damage,
		duration = fields.duration,
		hitStart = fields.hitStart,
		hitEnd = fields.hitEnd,
		reachBonus = fields.reachBonus or 0,
		widthBonus = fields.widthBonus or 0,
		centered = fields.centered == true,
		knockback = fields.knockback or 0,
		posture = fields.posture or 0,
		heavy = fields.heavy == true,
		hitStop = fields.hitStop or 0.045,
		tension = fields.tension or "comboHit",
	}
end

local COMBO: { AttackStep } = {
	step({ name = "Entaille", action = "sword_1", damage = 10, duration = 0.36, hitStart = 0.11, hitEnd = 0.25, posture = 8 }),
	step({ name = "Revers", action = "sword_2", damage = 10, duration = 0.34, hitStart = 0.11, hitEnd = 0.25, posture = 8 }),
	step({ name = "Fendoir", action = "sword_3", damage = 15, duration = 0.5, hitStart = 0.2, hitEnd = 0.34, reachBonus = 1, posture = 14, hitStop = 0.06 }),
	step({ name = "Tourbillon", action = "sword_4", damage = 12, duration = 0.55, hitStart = 0.12, hitEnd = 0.42, widthBonus = 4, centered = true, posture = 10 }),
	step({ name = "Brise-ciel", action = "sword_5", damage = 26, duration = 0.7, hitStart = 0.33, hitEnd = 0.5, reachBonus = 2.5, knockback = 55, posture = 30, heavy = true, hitStop = 0.09, tension = "finisherHit" }),
}

-- Attaque chargée : dégâts, posture et éjection interpolés selon la charge (0 à 1).
local CHARGED = step({ name = "Frappe chargée", action = "sword_charged", damage = 18, duration = 0.55, hitStart = 0.1, hitEnd = 0.3, reachBonus = 3, widthBonus = 2, knockback = 20, posture = 20, hitStop = 0.08, tension = "chargedHit" })
local COUNTER = step({ name = "Riposte", action = "sword_counter", damage = 22, duration = 0.38, hitStart = 0.1, hitEnd = 0.26, reachBonus = 1.5, knockback = 25, posture = 35, heavy = true, hitStop = 0.08, tension = "counterHit" })
local PLUNGE = step({ name = "Chute de l'astre", action = "sword_plunge", damage = 14, duration = 1.2, hitStart = 0, hitEnd = 1.2, widthBonus = 2, centered = true, posture = 16, hitStop = 0.07 })

return table.freeze({
	-- Combo ------------------------------------------------------------------
	COMBO = COMBO,
	COMBO_RESET_DELAY = 0.6, -- après la fin d'un coup, délai (s) pour enchaîner avant de repartir au coup 1
	-- Mise en file : un clic n'est retenu pour le coup suivant que pendant la dernière partie du coup
	-- en cours (part de sa durée). Plus tôt, il est ignoré : marteler la souris ne sert à rien.
	COMBO_BUFFER_FRACTION = 0.55,
	ATTACK_INPUT = Enum.UserInputType.MouseButton1,
	ANIMATION_FADE_TIME = 0.05, -- fondu d'entrée des animations de coup (s) : court = nerveux
	HIT_STOP_DURATION = 0.05, -- arrêt sur image par défaut (chaque attaque a le sien : hitStop)

	-- Attaque chargée -----------------------------------------------------------
	CHARGED = CHARGED,
	CHARGE_HOLD_THRESHOLD = 0.25, -- s de clic maintenu avant que la charge commence
	CHARGE_FULL_TIME = 1.1, -- s de charge pour atteindre la puissance maximale
	CHARGE_MAX_HOLD = 2.6, -- au-delà, la charge se relâche toute seule (pas de posture éternelle)
	CHARGE_MAX_DAMAGE = 45,
	CHARGE_MAX_POSTURE = 60,
	CHARGE_MAX_KNOCKBACK = 70,
	CHARGE_COOLDOWN = 2.5, -- s entre deux frappes chargées
	-- Contrepartie : pendant la charge, le joueur avance lentement, ne peut ni sprinter ni parer,
	-- et prend plus de dégâts. Seule une charge PLEINE brise les gardes frontales.
	CHARGE_MOVE_MULTIPLIER = 0.45,
	CHARGE_DAMAGE_TAKEN = 1.25,
	CHARGING_ATTRIBUTE = "Charging", -- attribut (boolean) du Player, posé par le serveur

	-- Riposte (après une parade parfaite) -----------------------------------------
	COUNTER = COUNTER,
	COUNTER_WINDOW = 1.1, -- s pendant lesquelles la riposte est possible
	COUNTER_ATTRIBUTE = "CounterUntil", -- attribut (number, heure serveur) du Player

	-- Attaque plongeante (depuis un saut) ------------------------------------------
	PLUNGE = PLUNGE,
	PLUNGE_SPEED = 70, -- studs/s vers le bas, imposés par le client à son personnage
	PLUNGE_COOLDOWN = 3,

	-- Esquive parfaite --------------------------------------------------------------
	-- Un dash lancé au plus tard PERFECT_DODGE_WINDOW s avant un coup ennemi : Tension, et un court
	-- élan (MOMENTUM) : les coups d'épée font un peu plus mal pendant MOMENTUM_DURATION s.
	PERFECT_DODGE_WINDOW = 0.2,
	MOMENTUM_DURATION = 2,
	MOMENTUM_DAMAGE = 1.15,
	MOMENTUM_ATTRIBUTE = "MomentumUntil", -- attribut (number, heure serveur) du Player

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

	-- Posture des ennemis ----------------------------------------------------------
	-- Jauge discrète : les coups lourds, la parade et certaines magies l'entament. Pleine : l'ennemi
	-- est brièvement sans défense (étourdi, plus vulnérable). Elle se reconstitue hors pression.
	POSTURE = table.freeze({
		HEALTH_RATIO = 0.6, -- posture maximale = PV max x ce ratio...
		MIN = 40, -- ...bornée
		MAX = 400,
		ELITE_MULTIPLIER = 1.3,
		BOSS_MULTIPLIER = 2.5,
		BREAK_DURATION = 2, -- s sans défense
		BOSS_BREAK_DURATION = 1.2,
		BOSS_BREAK_COOLDOWN = 12, -- un boss ne peut pas être brisé de nouveau avant ce délai
		BREAK_DAMAGE_MULTIPLIER = 1.3, -- dégâts reçus pendant la rupture
		REGEN_DELAY = 3, -- s sans dégâts de posture avant qu'elle ne se reconstitue
		REGEN_RATE = 0.15, -- part de la posture maximale reconstituée par seconde
		PARRY_DAMAGE = 35, -- posture retirée à l'attaquant par une parade parfaite
		ATTRIBUTE = "Posture", -- attribut (number 0..1) du Model : jauge pour l'interface
		BROKEN_ATTRIBUTE = "PostureBrokenUntil", -- attribut (number, heure serveur)
	}),

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
	-- Préparation des armes futures : chaque arme aura sa table de combo (épée longue, dague, bâton,
	-- lance, marteau nain). Seule l'épée existe pour l'instant ; WEAPON identifie le jeu de coups.
	WEAPON = "sword",

	-- Validation (serveur) -----------------------------------------------------
	LATENCY_TOLERANCE = 0.25, -- marge (s) sur les fenêtres de frappe, de riposte, de charge
	-- Marge (s) sur l'enchaînement de deux attaques : la latence touche les deux demandes de la même
	-- façon et s'annule ; seule sa variation compte. Plus petite : pas de coups en rafale.
	CADENCE_TOLERANCE = 0.1,
	PVP_ENABLED = true, -- les joueurs peuvent-ils se blesser entre eux (à l'épée) ?
	-- Attribut (boolean) qu'un système serveur pose sur un Model pour le rendre intouchable
	-- (ex. : le boss pendant sa charge). Ni l'épée ni l'ultime ne blessent une cible qui le porte.
	INVULNERABLE_ATTRIBUTE = "Invulnerable",

	-- Tension (détails des gains : ResourceConfig.TENSION_SOURCES) --------------------------
	-- Stockée par le serveur dans un attribut du Player : elle est répliquée toute seule
	-- au client, qui ne peut que la lire.
	TENSION_ATTRIBUTE = "Tension",
	TENSION_MAX = 100,

	-- Pouvoir ultime -------------------------------------------------------------
	-- Nom, rayon, dégâts et couleurs dépendent de la Magie Innée du joueur : voir MagicConfig.
	ULTIMATE_INPUT = Enum.KeyCode.E,
	-- Arrêt sur image joué par les clients avant l'explosion ; le serveur attend la même durée
	-- avant d'infliger les dégâts, pour qu'ils tombent au moment où l'onde de choc part.
	ULTIMATE_HIT_STOP = 0.2,

	DEBUG_LOGS = true,
})
