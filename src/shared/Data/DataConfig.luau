--!strict
--[[
	DataConfig
	Réglages communs aux sauvegardes des NOUVEAUX systèmes (guildes, index de noms...).

	Bac à sable de test : quand USE_TEST_STORES est vrai, les DataStores des nouveaux systèmes sont
	préfixés par TEST_PREFIX. Les tests dans Studio n'écrivent donc jamais dans les guildes de
	production. Par défaut : actif dans Studio, inactif en jeu publié.

	Le profil joueur (ProfileStore, "PlayerProfiles_v4") n'est PAS concerné : son nom ne change pas,
	pour ne pas perdre les personnages existants. Un test n'y touche que le profil du testeur.
]]

local RunService = game:GetService("RunService")

local TEST_PREFIX = "TEST_"
local USE_TEST_STORES = RunService:IsStudio()

-- Nom réel d'un DataStore d'un nouveau système (avec le préfixe de test si besoin).
local function storeName(baseName: string): string
	return if USE_TEST_STORES then TEST_PREFIX .. baseName else baseName
end

return table.freeze({
	USE_TEST_STORES = USE_TEST_STORES,
	TEST_PREFIX = TEST_PREFIX,
	storeName = storeName,

	GUILD_STORE = "Guilds_v1",
	GUILD_NAME_STORE = "GuildNames_v1",
	GUILD_MESSAGING_TOPIC = "GuildEvents_v1",
})
