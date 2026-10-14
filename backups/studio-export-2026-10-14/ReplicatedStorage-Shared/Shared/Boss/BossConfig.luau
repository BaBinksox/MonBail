--!strict
--[[
	BossConfig
	Constantes partagées (serveur + client) du boss.

	Pour créer un boss : poser un rig R15 dans le Workspace et lui donner le tag TAG.
	BossService fait le reste (PV, vitesse, inscription au Time-Loop, IA).
]]

-- États de l'IA, publiés par le serveur dans l'attribut STATE_ATTRIBUTE du Model.
-- Le client les lit pour jouer les effets visuels correspondants.
local STATES = table.freeze({
	Idle = "Idle", -- personne à poursuivre
	Chasing = "Chasing", -- poursuit sa cible (pathfinding)
	Attacking = "Attacking", -- coup de corps-à-corps en cours
	Charging = "Charging", -- charge son attaque fatale : immobile et invulnérable
	Staggered = "Staggered", -- sonné après un rewind : c'est la faille à exploiter
	Dead = "Dead",
})

return table.freeze({
	TAG = "Boss",
	STATE_ATTRIBUTE = "BossState",
	STATES = STATES,

	-- Caractéristiques -----------------------------------------------------------
	DISPLAY_NAME = "Gardien de l'Anomalie",
	MAX_HEALTH = 600,
	WALK_SPEED = 14,

	-- Perception et poursuite ------------------------------------------------------
	AGGRO_RANGE = 150, -- studs : au-delà, le boss ignore le joueur
	THINK_INTERVAL = 0.2, -- secondes entre deux décisions de l'IA (et deux calculs de chemin)

	-- Corps-à-corps --------------------------------------------------------------
	ATTACK_RANGE = 6, -- studs : distance à laquelle le boss s'arrête pour frapper
	ATTACK_RANGE_TOLERANCE = 1.5, -- marge à l'impact : au-delà, le joueur a esquivé en reculant
	ATTACK_WINDUP = 0.35, -- secondes entre le début du geste et l'impact (le temps d'esquiver)
	ATTACK_COOLDOWN = 1.4, -- secondes entre deux coups
	ATTACK_DAMAGE = 8,

	-- Attaque fatale (ouvre l'anomalie temporelle) -----------------------------------
	ULTIMATE_HEALTH_RATIO = 0.2, -- se déclenche quand les PV passent sous 20 %
	CHARGE_DURATION = 1.5, -- secondes de charge avant que l'attaque ne parte
	ULTIMATE_COOLDOWN = 25, -- secondes avant de pouvoir recharger l'attaque fatale
	STAGGER_DURATION = 3, -- secondes où le boss reste sonné après un rewind

	-- Animations (officielles Roblox, jouables dans tous les jeux) ---------------------
	WALK_ANIMATION_ID = "rbxassetid://507777826", -- "R15Walk"
	ATTACK_ANIMATION_ID = "rbxassetid://522635514", -- "R15 Sword Slash"

	DEBUG_LOGS = true,
})
