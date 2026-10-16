--!strict
--[[
	SpellConfig
	Les DOUZE sorts : deux par Magie Innée (un sort de base, un sort secondaire), en plus de
	l'ultime (MagicConfig / CombatService). Partagé serveur + client : le serveur valide et résout
	tout (SpellService), le client ne lit ces valeurs que pour l'interface, la visée et les effets.

	Champs :
		magic / slot     magie propriétaire, "base" (touche 1) ou "secondary" (touche 2)
		manaCost         Mana débité par le serveur (base 15 à 25, secondaire 30 à 45)
		cooldown         recharge (s), tenue par le serveur
		castTime         temps d'incantation (s) entre la demande et l'effet : le lanceur est exposé
		kind             "projectile"  trajectoire simulée par le serveur (vitesse, portée, rayon d'explosion)
		                 "zone"        effet à un point visé (ou autour du lanceur si `selfCentered`)
		                 "field"       zone persistante qui agit par impulsions (`pulses`)
		                 "line"        rayon instantané (première cible sur la ligne)
		                 "chain"       arc qui rebondit de cible en cible (`maxTargets`, `chainRange`)
		                 "self"        effet sur le lanceur
		range            portée maximale (studs) ; le point visé est ramené dans cette portée
		radius           rayon de l'effet ; damage ; posture ; knockback
		statuses         altérations posées sur chaque cible touchée (StatusConfig) : { id, stacks?, duration? }
		heal             part des dégâts infligés rendue au lanceur
		action           pose d'incantation (AnimationConfig.ACTIONS)
		advantage / drawback   forces et faiblesses, affichées dans le Grimoire
	Les sorts ne blessent que les ENNEMIS (pas de PvP magique).
]]

export type StatusApplication = { id: string, stacks: number?, duration: number? }

export type Spell = {
	id: string,
	magic: string,
	slot: "base" | "secondary",
	name: string,
	description: string,
	advantage: string,
	drawback: string,
	manaCost: number,
	cooldown: number,
	castTime: number,
	kind: string,
	range: number,
	radius: number,
	speed: number, -- projectiles (studs/s)
	damage: number,
	posture: number,
	knockback: number,
	statuses: { StatusApplication },
	heal: number,
	maxTargets: number,
	chainRange: number,
	chainFalloff: number, -- part des dégâts perdue à chaque rebond
	pulses: number, -- champs persistants : nombre d'impulsions
	pulseInterval: number,
	selfCentered: boolean,
	action: string,
}

local function spell(fields: { [string]: any }): Spell
	return {
		id = fields.id,
		magic = fields.magic,
		slot = fields.slot,
		name = fields.name,
		description = fields.description,
		advantage = fields.advantage,
		drawback = fields.drawback,
		manaCost = fields.manaCost,
		cooldown = fields.cooldown,
		castTime = fields.castTime or 0.2,
		kind = fields.kind,
		range = fields.range or 40,
		radius = fields.radius or 0,
		speed = fields.speed or 0,
		damage = fields.damage or 0,
		posture = fields.posture or 0,
		knockback = fields.knockback or 0,
		statuses = fields.statuses or {},
		heal = fields.heal or 0,
		maxTargets = fields.maxTargets or 8,
		chainRange = fields.chainRange or 0,
		chainFalloff = fields.chainFalloff or 0,
		pulses = fields.pulses or 0,
		pulseInterval = fields.pulseInterval or 0,
		selfCentered = fields.selfCentered == true,
		action = fields.action,
	}
end

local SPELLS: { Spell } = {
	-- Pyromancie : dégâts dans le temps, zones de feu. Fragile si on la laisse au contact.
	spell({
		id = "ember", magic = "pyromancy", slot = "base", name = "Braise Ardente",
		description = "Une braise lancée à main nue qui s'accroche et consume.",
		advantage = "Brûlure cumulable : les dégâts continuent après l'impact.",
		drawback = "Projectile lent à esquiver pour un ennemi mobile.",
		manaCost = 18, cooldown = 1.2, castTime = 0.25, kind = "projectile", range = 60, speed = 70, radius = 1.5,
		damage = 12, posture = 4, statuses = { { id = "burn" } }, action = "cast_pyromancy_base",
	}),
	spell({
		id = "blazing_circle", magic = "pyromancy", slot = "secondary", name = "Cercle Incandescent",
		description = "Le sol s'embrase autour de vous et repousse ceux qui vous serrent de trop près.",
		advantage = "Dégage la mêlée et brûle fort (2 crans).",
		drawback = "Courte portée : il faut être entouré pour qu'il rende.",
		manaCost = 35, cooldown = 8, castTime = 0.45, kind = "zone", selfCentered = true, range = 0, radius = 10,
		damage = 22, posture = 18, knockback = 22, statuses = { { id = "burn", stacks = 2 } }, action = "cast_pyromancy_secondary",
	}),
	-- Glace : contrôle. Peu de dégâts, mais elle ralentit, gèle et prépare les réactions.
	spell({
		id = "frost_shard", magic = "ice", slot = "base", name = "Éclat de Givre",
		description = "Un éclat de glace très rapide qui engourdit.",
		advantage = "Rapide et précis ; le froid se cumule et ralentit.",
		drawback = "Dégâts faibles.",
		manaCost = 16, cooldown = 1.0, castTime = 0.2, kind = "projectile", range = 65, speed = 110, radius = 1.2,
		damage = 10, posture = 5, statuses = { { id = "chill" } }, action = "cast_ice_base",
	}),
	spell({
		id = "crystal_prison", magic = "ice", slot = "secondary", name = "Prison Cristalline",
		description = "La glace jaillit du sol et emprisonne tout ce qui se trouve au point visé.",
		advantage = "Gèle sur place : ni déplacement ni attaque.",
		drawback = "Les boss y résistent (simple froid) ; gels répétés de moins en moins longs.",
		manaCost = 40, cooldown = 12, castTime = 0.55, kind = "zone", range = 40, radius = 7,
		damage = 10, posture = 10, statuses = { { id = "freeze" } }, action = "cast_ice_secondary",
	}),
	-- Foudre : vitesse, interruption, plusieurs cibles. Dégâts dispersés.
	spell({
		id = "electric_arc", magic = "lightning", slot = "base", name = "Arc Électrique",
		description = "Un arc instantané qui foudroie la première cible sur sa ligne.",
		advantage = "Instantané ; interrompt l'attaque ennemie en préparation.",
		drawback = "Portée moyenne, une seule cible.",
		manaCost = 15, cooldown = 1.4, castTime = 0.12, kind = "line", range = 35, radius = 1.5,
		damage = 11, posture = 6, statuses = { { id = "shock" } }, action = "cast_lightning_base",
	}),
	spell({
		id = "chain_lightning", magic = "lightning", slot = "secondary", name = "Chaîne Foudroyante",
		description = "La foudre saute d'ennemi en ennemi.",
		advantage = "Jusqu'à 4 cibles, toutes électrisées.",
		drawback = "Perd 20 % de sa force à chaque rebond ; il faut une première cible devant soi.",
		manaCost = 38, cooldown = 9, castTime = 0.35, kind = "chain", range = 32, radius = 2,
		damage = 22, posture = 8, maxTargets = 4, chainRange = 14, chainFalloff = 0.2, statuses = { { id = "shock" } },
		action = "cast_lightning_secondary",
	}),
	-- Ombre : drain, survie. Peu de contrôle.
	spell({
		id = "dark_bolt", magic = "shadow", slot = "base", name = "Trait Obscur",
		description = "Un trait d'ombre qui vole un peu de vie, puis encore un peu.",
		advantage = "Soigne à l'impact et pendant le drain.",
		drawback = "Aucun contrôle sur l'ennemi.",
		manaCost = 18, cooldown = 1.3, castTime = 0.25, kind = "projectile", range = 55, speed = 80, radius = 1.4,
		damage = 12, posture = 4, heal = 0.25, statuses = { { id = "drain" } }, action = "cast_shadow_base",
	}),
	spell({
		id = "shadow_veil", magic = "shadow", slot = "secondary", name = "Voile des Ombres",
		description = "Les ombres vous enveloppent : les coups glissent, le pas s'allège.",
		advantage = "Dégâts reçus -40 % et vitesse +15 % pendant 4 s.",
		drawback = "Aucun dégât ; long à se recharger.",
		manaCost = 30, cooldown = 14, castTime = 0.3, kind = "self", range = 0,
		statuses = { { id = "veil" } }, action = "cast_shadow_secondary",
	}),
	-- Antimatière : zones, regroupement. Lente à se déployer.
	spell({
		id = "void_fragment", magic = "antimatter", slot = "base", name = "Fragment du Vide",
		description = "Un éclat de vide qui implose à l'impact.",
		advantage = "Explosion : touche aussi les ennemis proches de la cible.",
		drawback = "Le projectile le plus lent.",
		manaCost = 20, cooldown = 1.5, castTime = 0.3, kind = "projectile", range = 50, speed = 55, radius = 4,
		damage = 15, posture = 6, action = "cast_antimatter_base",
	}),
	spell({
		id = "minor_singularity", magic = "antimatter", slot = "secondary", name = "Singularité Mineure",
		description = "Un point de vide aspire les ennemis proches, puis se referme sur eux.",
		advantage = "Regroupe jusqu'à 6 ennemis puis les blesse ensemble.",
		drawback = "Aspiration courte et bornée ; les boss n'y cèdent pas.",
		manaCost = 42, cooldown = 12, castTime = 0.5, kind = "zone", range = 35, radius = 12,
		damage = 18, posture = 12, maxTargets = 6, statuses = { { id = "pull", duration = 0.8 } }, action = "cast_antimatter_secondary",
	}),
	-- Gravité : pression, posture. Dégâts modestes.
	spell({
		id = "gravity_press", magic = "gravity", slot = "base", name = "Pression Gravitationnelle",
		description = "Le poids du monde s'abat sur un point : tout y ralentit et ploie.",
		advantage = "Ralentit et fragilise la posture (+25 %).",
		drawback = "Petite zone, dégâts modestes.",
		manaCost = 17, cooldown = 1.4, castTime = 0.3, kind = "zone", range = 30, radius = 5,
		damage = 10, posture = 12, statuses = { { id = "pressure" } }, action = "cast_gravity_base",
	}),
	spell({
		id = "gravity_field", magic = "gravity", slot = "secondary", name = "Champ Gravitationnel",
		description = "Un champ de gravité persistant où chaque pas coûte.",
		advantage = "Zone large qui maintient la pression et use la posture.",
		drawback = "Dégâts par impulsion faibles ; il faut y maintenir les ennemis.",
		manaCost = 36, cooldown = 13, castTime = 0.5, kind = "field", range = 30, radius = 10,
		damage = 4, posture = 5, pulses = 8, pulseInterval = 0.5, statuses = { { id = "pressure", duration = 1 } },
		action = "cast_gravity_secondary",
	}),
}

local byId: { [string]: Spell } = {}
local byMagic: { [string]: { base: Spell?, secondary: Spell? } } = {}
for _, entry in SPELLS do
	byId[entry.id] = entry
	local slots = byMagic[entry.magic] or {}
	slots[entry.slot] = entry
	byMagic[entry.magic] = slots
end

local function get(id: any): Spell?
	return if type(id) == "string" then byId[id] else nil
end

-- Sort d'une magie pour un emplacement ("base" / "secondary").
local function forMagic(magicId: any, slot: string): Spell?
	local slots = byMagic[magicId]
	if slots == nil then
		return nil
	end
	return if slot == "base" then slots.base elseif slot == "secondary" then slots.secondary else nil
end

return table.freeze({
	SPELLS = SPELLS,
	get = get,
	forMagic = forMagic,
	READY_ATTRIBUTE_PREFIX = "SpellReady_", -- attribut Player : heure serveur de fin de recharge
	CASTING_ATTRIBUTE = "Casting", -- attribut Player (string = id du sort) pendant l'incantation
	GLOBAL_COOLDOWN = 0.35, -- s minimum entre deux sorts, quels qu'ils soient
	AIM_TOLERANCE = 6, -- studs de marge sur la portée (latence, déplacement)
	MAX_PROJECTILES_PER_PLAYER = 4,
})
