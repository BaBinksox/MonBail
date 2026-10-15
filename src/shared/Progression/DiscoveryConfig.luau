--!strict
--[[
	DiscoveryConfig
	Noms affichés des découvertes (profil.discoveries = { [discoveryId] = date }).

	Les découvertes viennent de plusieurs sources, rassemblées ici pour que le journal et les
	notifications aient un nom lisible :
		- régions        : RegionConfig.REGIONS[].discoveryId ("region_village"...)
		- secrets        : MechanismConfig.INTERACTABLES[].discovery ("secret_flame_sanctum"...)
		- échos          : EchoConfig.ECHOES[].discovery ("echo_odile"...)
		- récits         : EXTRA ci-dessous (vérités révélées par les quêtes)
	Chaque découverte compte pour les conditions de rang (RankConfig.discoveries).
]]

local World = script.Parent.Parent.World
local EchoConfig = require(World.EchoConfig)
local MechanismConfig = require(World.MechanismConfig)
local RegionConfig = require(World.RegionConfig)

export type Discovery = {
	id: string,
	name: string,
	kind: "region" | "secret" | "echo" | "lore",
}

local EXTRA: { Discovery } = {
	{ id = "lore_bell_truth", name = "La vérité de la Cloche Muette", kind = "lore" },
}

local byId: { [string]: Discovery } = {}

for _, region in RegionConfig.REGIONS do
	if region.discoveryId then
		byId[region.discoveryId] = { id = region.discoveryId, name = region.name, kind = "region" }
	end
end
for _, interactable in MechanismConfig.INTERACTABLES do
	if interactable.discovery then
		byId[interactable.discovery] = { id = interactable.discovery, name = interactable.title, kind = "secret" }
	end
end
for _, echo in EchoConfig.ECHOES do
	if echo.discovery then
		byId[echo.discovery] = { id = echo.discovery, name = `Écho : {echo.name}`, kind = "echo" }
	end
end
for _, discovery in EXTRA do
	byId[discovery.id] = discovery
end

local function getDiscovery(id: any): Discovery?
	return if type(id) == "string" then byId[id] else nil
end

-- Nombre total de découvertes existantes (affiché "12 / 34" dans le journal).
local function countAll(): number
	local count = 0
	for _ in byId do
		count += 1
	end
	return count
end

return table.freeze({
	getDiscovery = getDiscovery,
	countAll = countAll,
	ALL = byId,
})
