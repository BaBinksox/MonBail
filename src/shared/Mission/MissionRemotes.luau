--!strict
--[[
	MissionRemotes
	Sens :
		MissionRequest  client -> serveur  (action: "accept" | "abandon" | "claim", missionId: string)
			-> { ok: boolean, error: string? }
			Le serveur vérifie : identifiant connu, proximité du tableau (ou d'Ysolde), rang et prérequis,
			groupe, nombre de contrats actifs, objectifs atteints (claim), objets à remettre (deliver),
			et la clé de récompense (un seul paiement par cycle).
	L'état des contrats arrive par StateSync (tranche "missions").
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("MissionRemotes")

return table.freeze({
	MissionRequest = remotes:func("MissionRequest"),
})
