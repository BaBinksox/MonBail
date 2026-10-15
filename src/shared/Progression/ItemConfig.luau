--!strict
--[[
	ItemConfig
	Catalogue des objets que le joueur peut posséder (profil.inventory = { [itemId] = quantité }).

	Il n'y a pas encore d'équipement : les objets servent de reliques de quête, de matériaux pour les
	contrats de récupération, de trophées et de monnaie pour des améliorations futures. L'inventaire
	l'affiche honnêtement ("utilité à venir" quand c'est le cas).

	IMPORTANT : `id` est écrit dans les sauvegardes. Ne jamais renommer un id une fois en ligne.
]]

export type Item = {
	id: string,
	name: string,
	description: string,
	category: "relic" | "material" | "quest" | "trophy" | "currency",
	maxStack: number,
	color: Color3, -- pastille de couleur de la vignette (pas d'image : aucun asset inventé)
	use: string?, -- à quoi sert l'objet (nil = "Utilité à venir")
}

local ITEMS: { Item } = {
	-- Objets de quête
	{ id = "bell_clapper", name = "Battant de la Cloche", description = "Un battant de bronze, tiède comme s'il venait de sonner. Il a été caché sous le village.", category = "quest", maxStack = 1, color = Color3.fromRGB(196, 150, 80), use = "Rend sa voix à la grande cloche (quête « La Cloche Muette »)." },
	{ id = "bell_clapper_shard", name = "Éclat de bronze", description = "Un éclat tombé du battant quand la cloche a sonné. Il vibre encore.", category = "trophy", maxStack = 1, color = Color3.fromRGB(170, 120, 60), use = "Trophée : la preuve que vous avez rendu sa voix à la cloche." },

	-- Matériaux (butin des ennemis, contrats de récupération)
	{ id = "ash_shard", name = "Éclat de cendre", description = "Un fragment durci qui se détache des Rôdeurs. Il garde la chaleur d'un incendie qui n'a jamais fini.", category = "material", maxStack = 99, color = Color3.fromRGB(120, 110, 105), use = "Demandé par les contrats de récupération." },
	{ id = "stone_core", name = "Cœur de pierre", description = "Le noyau qui animait un Gardien de Pierre. Il bat encore, lentement.", category = "material", maxStack = 99, color = Color3.fromRGB(110, 120, 135), use = "Demandé par les contrats de récupération." },
	{ id = "whisper_essence", name = "Essence de murmure", description = "Une brume captive qui répète la dernière phrase entendue.", category = "material", maxStack = 99, color = Color3.fromRGB(150, 120, 190), use = "Demandée par les contrats de récupération." },

	-- Reliques des secrets (une par Magie Innée)
	{ id = "ember_relic", name = "Braise du Sanctuaire", description = "Une flamme qui brûle sans rien consumer.", category = "relic", maxStack = 1, color = Color3.fromRGB(255, 120, 40) },
	{ id = "void_relic", name = "Fragment de vide", description = "Une absence que l'on peut tenir dans la main.", category = "relic", maxStack = 1, color = Color3.fromRGB(140, 70, 230) },
	{ id = "storm_relic", name = "Glyphe d'orage", description = "Un disque de métal qui crépite au moindre contact.", category = "relic", maxStack = 1, color = Color3.fromRGB(255, 220, 80) },
	{ id = "frost_relic", name = "Larme de givre", description = "Une goutte gelée qui ne fond jamais.", category = "relic", maxStack = 1, color = Color3.fromRGB(120, 210, 255) },
	{ id = "shadow_relic", name = "Ombre captive", description = "Une ombre sans propriétaire, roulée dans un linge noir.", category = "relic", maxStack = 1, color = Color3.fromRGB(150, 20, 60) },
	{ id = "gravity_relic", name = "Pierre lourde", description = "Un caillou de la taille d'une noix qui pèse comme un rocher.", category = "relic", maxStack = 1, color = Color3.fromRGB(90, 110, 150) },

	-- Monnaies et distinctions
	{ id = "echo_fragment", name = "Fragment d'écho", description = "Un éclat de temps cristallisé. Les Veilleurs en faisaient des clés.", category = "currency", maxStack = 999, color = Color3.fromRGB(140, 220, 255) },
	{ id = "guild_seal", name = "Sceau de guilde", description = "Remis pour un contrat de guilde accompli. Il porte le nom de tous ceux qui y ont participé.", category = "currency", maxStack = 999, color = Color3.fromRGB(210, 180, 110) },
}

local byId: { [string]: Item } = {}
for _, item in ITEMS do
	byId[item.id] = item
end

local function getItem(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

return table.freeze({
	ITEMS = ITEMS,
	getItem = getItem,
})
