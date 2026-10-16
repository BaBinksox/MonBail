--!strict
--[[
	MovementConfig
	Constantes partagées (serveur + client) de la mobilité : sprint, double saut, dash, contrôles de
	vitesse du serveur. Les touches sont dans Shared/Input/KeyBindings.

	VITESSES (studs/s) : la vitesse de COURSE de base est celle du Humanoid (16 par défaut), multipliée
	par le peuple (RaceConfig) et les altérations (ralentissement, gel...) côté serveur : c'est
	l'attribut MoveSpeedBase du Humanoid. Le sprint la multiplie ensuite par SPRINT_MULTIPLIER, après
	une montée progressive. Un ralentissement s'applique donc AUSSI au sprint (il ne le neutralise pas).

	PORTÉE DES SAUTS — vérifiée contre la carte (voir tests) :
		saut normal (JumpHeight 7,2) + double saut DOUBLE_JUMP_VELOCITY 38 -> ~10,9 studs de haut ;
		au sprint (16 x 1,5 = 24 studs/s), environ 19 studs franchis à plat (Elfe : ~20,7).
	Le ravin du Pont Rompu fait 26 studs et l'îlot de l'Étang Figé est à 20 studs du bord, 6 studs plus
	haut : ni le sprint ni le double saut ne remplacent le pont restauré ou la glace de la Glace.
]]

return table.freeze({
	-- Sprint ------------------------------------------------------------------
	SPRINT_MULTIPLIER = 1.5, -- vitesse maximale = course x 1,5 (24 studs/s pour un humain)
	SPRINT_ACCELERATION_TIME = 0.65, -- s pour passer de la course au sprint maximal
	SPRINT_DECELERATION_TIME = 0.25, -- s pour revenir à la course au relâchement
	SPRINT_MIN_MOVE = 0.1, -- MoveDirection minimale pour compter comme « en mouvement »
	SPRINT_FOV_BONUS = 7, -- degrés ajoutés au champ de vision à pleine vitesse
	SPRINT_FOV_SMOOTHING = 6, -- vitesse de retour du FOV (plus grand = plus vif)
	SPRINT_ATTRIBUTE = "Sprinting", -- attribut (boolean) du Player, posé par le serveur
	MOVE_SPEED_ATTRIBUTE = "MoveSpeedBase", -- attribut (number) du Humanoid, posé par le serveur

	-- Double saut -------------------------------------------------------------
	DOUBLE_JUMP_VELOCITY = 38, -- vitesse verticale imposée au second saut (studs/s)
	DOUBLE_JUMP_MIN_AIR_TIME = 0.12, -- s en l'air avant que le second saut soit possible
	DOUBLE_JUMP_COUNT = 1, -- sauts supplémentaires par passage en l'air
	-- Garde du serveur : montée maximale au-dessus du dernier appui au sol (saut + double saut + marge).
	MAX_RISE_HEIGHT = 15,

	-- Dash --------------------------------------------------------------------
	DASH_INPUT = Enum.KeyCode.C, -- (compatibilité ; la référence est KeyBindings.BINDINGS.Dash)
	DASH_DOUBLE_TAP_WINDOW = 0.25, -- s entre deux appuis sur la même direction
	DASH_SPEED = 85, -- studs/s pendant le dash
	DASH_DURATION = 0.18, -- secondes de propulsion (85 x 0.18 = environ 15 studs)
	DASH_COOLDOWN = 2, -- secondes entre deux dashs
	-- Après un dash accepté par le serveur, le joueur ne peut pas être blessé pendant cette durée
	-- (un peu plus longue que le dash, pour absorber la latence) : c'est ce qui en fait une esquive.
	DASH_INVULNERABILITY = 0.3,

	-- Contrôle de vitesse du serveur --------------------------------------------
	SPEED_CHECK_INTERVAL = 0.5, -- s entre deux mesures
	SPEED_TOLERANCE = 1.3, -- marge sur la vitesse maximale autorisée (latence, pentes)
	SPEED_TOLERANCE_FLAT = 6, -- studs/s ajoutés à la marge
	SPEED_VIOLATIONS_BEFORE_CORRECTION = 3, -- mesures consécutives hors limite avant correction
	TELEPORT_DISTANCE = 60, -- au-delà en une mesure : téléportation par le serveur (non comptée)

	LATENCY_TOLERANCE = 0.25, -- marge (s) du serveur sur les cooldowns
	DEBUG_LOGS = true,
})
