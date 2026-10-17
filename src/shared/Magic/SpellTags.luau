--!strict
--[[
	SpellTags
	Étiquettes courtes qui disent ce que fait VRAIMENT un sort : sa forme (projectile, zone,
	instantané, persistant…) et son effet (ralentit, immobilise, aspire…). Elles sont DÉDUITES des
	données du serveur (SpellConfig : kind, statuses, heal, knockback) et de StatusConfig : elles ne
	peuvent pas promettre un effet que le serveur n'applique pas.
	Affichées dans le HUD de combat (sous le nom du sort) et sur les fiches du créateur.

	API : SpellTags.form(spell) -> string ; SpellTags.effects(spell) -> { string } ;
	      SpellTags.describe(spell) -> "Projectile · Ralentit"
]]

local FORMS: { [string]: string } = {
	projectile = "Projectile",
	zone = "Zone ciblée",
	field = "Zone persistante",
	line = "Instantané",
	chain = "Chaîne",
	self = "Sur soi",
}

-- Effet de chaque altération, du point de vue du joueur.
local STATUS_EFFECTS: { [string]: string } = {
	chill = "Ralentit",
	freeze = "Immobilise",
	burn = "Brûle",
	shock = "Interrompt",
	drain = "Draine la vie",
	veil = "Protège",
	pull = "Aspire",
	pressure = "Ralentit, use la garde",
	paralysis = "Paralyse",
	pinned = "Cloue au sol",
	frostbite = "Ralentit fortement",
}

local SpellTags = {}

function SpellTags.form(spell: any): string
	if spell.kind == "zone" and spell.selfCentered then
		return "Zone autour de soi"
	end
	return FORMS[spell.kind] or "Sort"
end

function SpellTags.effects(spell: any): { string }
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(text: string)
		if not seen[text] then
			seen[text] = true
			table.insert(list, text)
		end
	end
	for _, application in spell.statuses or {} do
		local text = STATUS_EFFECTS[application.id]
		if text then
			add(text)
		end
	end
	if (spell.heal or 0) > 0 then
		add("Draine la vie")
	end
	if (spell.knockback or 0) > 0 then
		add("Repousse")
	end
	if (spell.maxTargets or 1) > 1 and spell.kind == "chain" then
		add(`{spell.maxTargets} cibles`)
	end
	if #list == 0 then
		add(if spell.kind == "projectile" and (spell.radius or 0) >= 3 then "Explose" else "Dégâts")
	end
	return list
end

function SpellTags.describe(spell: any): string
	return SpellTags.form(spell) .. " · " .. table.concat(SpellTags.effects(spell), ", ")
end

return SpellTags
