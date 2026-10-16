--!strict
--[[
	MagicShowcase
	Présentation des Magies Innées sur les fiches du créateur (page Destin) : identité, style
	tactique et difficulté. Texte et repères seulement : aucune valeur de combat n'est lue ici,
	et rien ici ne change le jeu (dégâts, coûts, sorts et ultimes restent dans MagicConfig et
	SpellConfig, d'où la fiche tire aussi les noms et coûts des sorts).

	roles      : 0 à 3 pour chaque axe tactique (dégâts, contrôle, mobilité, soutien), d'après ce
	             que font réellement les deux sorts et l'ultime de la magie.
	difficulty : 1 Accessible, 2 Intermédiaire, 3 Exigeante.
	Une magie ajoutée à MagicConfig sans profil ici s'affiche quand même (fiche sans ces lignes).
]]

export type Roles = { damage: number, control: number, mobility: number, support: number }

export type Profile = {
	identity: string, -- l'identité de la magie, en une phrase
	playstyle: string, -- comment on la joue
	roles: Roles,
	difficulty: number,
}

local ROLE_ORDER = table.freeze({
	{ key = "damage", label = "Dégâts" },
	{ key = "control", label = "Contrôle" },
	{ key = "mobility", label = "Mobilité" },
	{ key = "support", label = "Soutien" },
})

local DIFFICULTY_LABELS = table.freeze({ "Accessible", "Intermédiaire", "Exigeante" })

local PROFILES: { [string]: Profile } = {
	antimatter = {
		identity = "Le vide qui dévore : on rassemble, puis tout implose.",
		playstyle = "Contrôle de foule : regrouper les ennemis pour les frapper ensemble.",
		roles = { damage = 2, control = 3, mobility = 0, support = 0 },
		difficulty = 2,
	},
	pyromancy = {
		identity = "Une colère qui ne s'éteint pas : brûlures qui s'accumulent, mêlée en flammes.",
		playstyle = "Dégâts dans la durée : marquer, laisser brûler, dégager la mêlée.",
		roles = { damage = 3, control = 1, mobility = 0, support = 0 },
		difficulty = 1,
	},
	lightning = {
		identity = "Le ciel répond à l'appel : vitesse, portée, interruption.",
		playstyle = "Réactivité : couper les attaques ennemies et toucher plusieurs cibles.",
		roles = { damage = 2, control = 2, mobility = 1, support = 0 },
		difficulty = 2,
	},
	ice = {
		identity = "Un froid venu d'avant le monde : tout ralentit autour de vous.",
		playstyle = "Contrôle : ralentir, geler, garder le combat à son rythme.",
		roles = { damage = 1, control = 3, mobility = 0, support = 1 },
		difficulty = 1,
	},
	shadow = {
		identity = "Ce qui rampe sous vos pas : voler la vie, glisser entre les coups.",
		playstyle = "Duel rapproché : drainer, encaisser sous le voile, achever.",
		roles = { damage = 3, control = 0, mobility = 2, support = 2 },
		difficulty = 3,
	},
	gravity = {
		identity = "Le poids du monde : pression, postures brisées, ennemis cloués au sol.",
		playstyle = "Pression : user la posture et maintenir les ennemis dans le champ.",
		roles = { damage = 2, control = 3, mobility = 0, support = 1 },
		difficulty = 3,
	},
}

local function get(magicId: string): Profile?
	return PROFILES[magicId]
end

return table.freeze({
	PROFILES = PROFILES,
	ROLE_ORDER = ROLE_ORDER,
	DIFFICULTY_LABELS = DIFFICULTY_LABELS,
	MAX_ROLE = 3,
	get = get,
})
