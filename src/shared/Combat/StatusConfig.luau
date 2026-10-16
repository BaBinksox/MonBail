--!strict
--[[
	StatusConfig
	Les ALTÉRATIONS d'état communes à toutes les magies (sorts, ultimes), tenues par le serveur
	(Server/Combat/StatusService) et affichées par les clients (Client/Combat/StatusEffects).

	Règles communes :
		- chaque altération a une durée MAXIMALE (maxDuration) : rien ne dure indéfiniment ;
		- empilement (`stacking`) :
			"refresh"  une nouvelle application remet la durée au plus long des deux ;
			"stack"    l'intensité monte d'un cran (jusqu'à maxStacks) et la durée est rafraîchie ;
		- plusieurs joueurs peuvent alimenter la même altération : elle reste UNE altération par cible,
		  attribuée au dernier joueur qui l'a appliquée (dégâts, élimination : DamageService, une seule
		  élimination et une seule récompense quoi qu'il arrive) ;
		- contrôles durs (gel, immobilisation) : rendement décroissant par cible (DR_WINDOW) : la
		  deuxième application dure moitié moins, la troisième ne prend pas. Pas de verrouillage ;
		- boss : durée multipliée par `bossDuration`, ou immunité (`bossImmune`), ou conversion
		  (`bossConvertTo`, ex. gel -> froid) ; élites : ELITE_DURATION ;
		- tout disparaît à la mort, à la disparition de la cible et au rembobinage.

	Côté client, chaque altération active se lit dans un attribut du Model :
		Status_<id> = heure serveur de fin (number) ; Status_<id>Level = intensité (number).
	La vitesse résultante est publiée dans SPEED_ATTRIBUTE (multiplicateur, 1 = normal), que les IA
	(EnemyBrain, boss) appliquent à leur vitesse de base.
]]

export type Status = {
	id: string,
	name: string, -- nom affiché
	element: string, -- magie d'origine (id de MagicConfig) : réactions, dégâts attribués
	maxDuration: number,
	stacking: "refresh" | "stack",
	maxStacks: number,
	speedMultiplier: number?, -- vitesse restante (1 = aucun effet ; 0 = immobile)
	speedPerStack: number?, -- ralentissement supplémentaire par cran (stack)
	stun: boolean?, -- empêche d'attaquer (CombatStatus.stun)
	tickInterval: number?, -- dégâts périodiques
	tickDamage: number?, -- par tick et par cran
	healSourceRatio: number?, -- part des dégâts périodiques rendue au joueur source (drain)
	postureTakenMultiplier: number?, -- dégâts de posture reçus (pression)
	damageTakenMultiplier: number?, -- dégâts reçus (voile : sur un JOUEUR)
	hardControl: boolean?, -- soumis au rendement décroissant
	bossDuration: number, -- multiplicateur de durée sur un boss (0 = immunité)
	bossConvertTo: string?, -- sur un boss, cette altération est remplacée par une autre
	color: Color3, -- teinte des effets visuels
}

local function status(fields: { [string]: any }): Status
	return {
		id = fields.id,
		name = fields.name,
		element = fields.element,
		maxDuration = fields.maxDuration,
		stacking = fields.stacking or "refresh",
		maxStacks = fields.maxStacks or 1,
		speedMultiplier = fields.speedMultiplier,
		speedPerStack = fields.speedPerStack,
		stun = fields.stun,
		tickInterval = fields.tickInterval,
		tickDamage = fields.tickDamage,
		healSourceRatio = fields.healSourceRatio,
		postureTakenMultiplier = fields.postureTakenMultiplier,
		damageTakenMultiplier = fields.damageTakenMultiplier,
		hardControl = fields.hardControl,
		bossDuration = if fields.bossDuration == nil then 1 else fields.bossDuration,
		bossConvertTo = fields.bossConvertTo,
		color = fields.color,
	}
end

local STATUSES: { [string]: Status } = {
	-- Pyromancie : brûlure, dégâts dans le temps, cumulable (3 crans).
	burn = status({ id = "burn", element = "pyromancy", name = "Brûlure", maxDuration = 6, stacking = "stack", maxStacks = 3, tickInterval = 1, tickDamage = 4, bossDuration = 1, color = Color3.fromRGB(255, 120, 40) }),
	-- Glace : froid (ralenti), puis gel (immobilisé, sans attaque). Le boss ne gèle pas : il a froid.
	chill = status({ id = "chill", element = "ice", name = "Froid", maxDuration = 4, stacking = "stack", maxStacks = 3, speedMultiplier = 0.75, speedPerStack = 0.1, bossDuration = 0.6, color = Color3.fromRGB(150, 220, 255) }),
	freeze = status({ id = "freeze", element = "ice", name = "Gel", maxDuration = 2.5, speedMultiplier = 0, stun = true, hardControl = true, bossDuration = 0.6, bossConvertTo = "chill", color = Color3.fromRGB(200, 240, 255) }),
	-- Foudre : électrisé. À l'application, l'action en préparation est interrompue (micro-étourdissement).
	shock = status({ id = "shock", element = "lightning", name = "Électrisé", maxDuration = 3, bossDuration = 1, color = Color3.fromRGB(255, 230, 90) }),
	-- Ombre : drain de vie (le lanceur récupère ce que la cible perd) ; voile (sur le lanceur).
	drain = status({ id = "drain", element = "shadow", name = "Drain", maxDuration = 3, tickInterval = 1, tickDamage = 3, healSourceRatio = 1, bossDuration = 1, color = Color3.fromRGB(190, 40, 80) }),
	veil = status({ id = "veil", element = "shadow", name = "Voile des Ombres", maxDuration = 4, damageTakenMultiplier = 0.6, speedMultiplier = 1.15, bossDuration = 1, color = Color3.fromRGB(120, 30, 70) }),
	-- Antimatière : aspiration (déplacement bref vers un point). Le boss n'est pas aspiré.
	pull = status({ id = "pull", element = "antimatter", name = "Aspiré", maxDuration = 1, bossDuration = 0, color = Color3.fromRGB(170, 90, 255) }),
	-- Gravité : pression (ralenti, posture plus fragile).
	pressure = status({ id = "pressure", element = "gravity", name = "Pression", maxDuration = 3.5, stacking = "refresh", speedMultiplier = 0.55, postureTakenMultiplier = 1.25, bossDuration = 0.7, color = Color3.fromRGB(120, 140, 210) }),
	-- Ultimes (UltimateBehaviors) : paralysie de la Foudre, écrasement de la Gravité.
	paralysis = status({ id = "paralysis", element = "lightning", name = "Paralysie", maxDuration = 1.5, speedMultiplier = 0, stun = true, hardControl = true, bossDuration = 0.5, color = Color3.fromRGB(255, 240, 150) }),
	pinned = status({ id = "pinned", element = "gravity", name = "Cloué", maxDuration = 1.2, speedMultiplier = 0, stun = true, hardControl = true, bossDuration = 0.5, color = Color3.fromRGB(150, 170, 230) }),
	frostbite = status({ id = "frostbite", element = "ice", name = "Hiver Éternel", maxDuration = 5, speedMultiplier = 0.35, bossDuration = 0.6, color = Color3.fromRGB(120, 210, 255) }),
}

--[[
	RÉACTIONS ÉLÉMENTAIRES (deux complètes pour l'instant). Elles se déclenchent quand un coup d'un
	élément touche une cible qui porte déjà une altération d'un autre élément ; elles CONSOMMENT
	l'altération et récompensent le bon enchaînement (dégâts, posture, Tension « elementalReaction »).
	Elles marchent entre joueurs : l'un gèle, l'autre foudroie.
		shatter      Foudre sur une cible froide ou gelée : la glace vole en éclats.
		thermalShock Feu sur une cible froide ou gelée, ou Glace sur une cible qui brûle : choc
		             thermique, la vapeur explose.
]]
export type Reaction = {
	id: string,
	name: string,
	trigger: string, -- élément du coup qui déclenche
	consumes: { string }, -- altérations qui doivent être présentes (l'une d'elles) et sont consommées
	bonusDamage: number,
	bonusDamageRatio: number, -- part des dégâts du coup déclencheur ajoutée
	posture: number,
	stun: number, -- étourdissement bref (s), 0 = aucun
	color: Color3,
}

local REACTIONS: { Reaction } = {
	{ id = "shatter", name = "Éclatement", trigger = "lightning", consumes = { "freeze", "chill" }, bonusDamage = 16, bonusDamageRatio = 0.5, posture = 40, stun = 0.4, color = Color3.fromRGB(190, 235, 255) },
	{ id = "thermalShock", name = "Choc thermique", trigger = "pyromancy", consumes = { "freeze", "chill" }, bonusDamage = 12, bonusDamageRatio = 0.6, posture = 20, stun = 0, color = Color3.fromRGB(255, 200, 160) },
	{ id = "thermalShock", name = "Choc thermique", trigger = "ice", consumes = { "burn" }, bonusDamage = 12, bonusDamageRatio = 0.6, posture = 20, stun = 0, color = Color3.fromRGB(255, 200, 160) },
}

return table.freeze({
	STATUSES = STATUSES,
	REACTIONS = REACTIONS,
	ATTRIBUTE_PREFIX = "Status_", -- Status_<id> = heure serveur de fin ; Status_<id>Level = intensité
	SPEED_ATTRIBUTE = "StatusSpeedMultiplier", -- sur le Model : multiplicateur de vitesse (absent = 1)
	TICK_INTERVAL = 0.1, -- s entre deux passages de la boucle serveur
	ELITE_DURATION = 0.75, -- durée des altérations sur un élite
	DR_WINDOW = 12, -- s : fenêtre du rendement décroissant des contrôles durs
	DR_FACTOR = 0.5, -- durée de la 2e application dans la fenêtre ; la 3e ne prend pas
	REACTION_COOLDOWN = 1.5, -- s entre deux réactions sur une même cible
	SHOCK_INTERRUPT_STUN = 0.3, -- s : micro-étourdissement qui interrompt l'action en préparation
	BOSS_INTERRUPT_COOLDOWN = 8, -- s : un boss ne peut être interrompu qu'une fois par période
	PULL_SPEED = 32, -- studs/s maximum vers le centre d'une aspiration
	PULL_STOP_DISTANCE = 3,
})
