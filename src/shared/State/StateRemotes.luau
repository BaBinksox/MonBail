--!strict
--[[
	StateRemotes
	Synchronisation de l'état du joueur vers SON client (StateSync côté serveur, PlayerStateClient côté client).

	Sens des événements :
		StateChanged     serveur -> client   (slice: string, data: any)
			Une tranche de l'état a changé : "progression", "quests", "missions", "inventory", "discoveries",
			"unlocks", "settings", "guild", "party", "saveStatus". `data` est la tranche COMPLÈTE (pas un diff).
		Notify           serveur -> client   (kind: string, payload: { [string]: any })
			Notification à afficher : "reward", "promotion", "discovery", "quest", "mission", "guild",
			"party", "info", "error". Purement informatif : l'état fait foi.
		RequestFullState client  -> serveur  () -> { [slice]: data }   (RemoteFunction)
			Au démarrage du client (et après un rechargement), toutes les tranches d'un coup.
		UpdateSettings   client  -> serveur  (settings: { music: number?, ambience: number?, sfx: number?, uiScale: number?, reducedEffects: boolean? })
			Le serveur borne chaque valeur et l'écrit dans le profil.
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("StateRemotes")

return table.freeze({
	StateChanged = remotes:event("StateChanged"),
	Notify = remotes:event("Notify"),
	RequestFullState = remotes:func("RequestFullState"),
	UpdateSettings = remotes:event("UpdateSettings"),
})
