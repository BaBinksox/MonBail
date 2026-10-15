--!strict
--[[
	PartyRemotes
	Remotes des groupes (PartyService côté serveur). Créés via Shared/Net/RemoteFolder.

	PartyRequest   client -> serveur   RemoteFunction (action: string, params: table?) -> Response
		Response = { ok: boolean, error: string?, message: string?, data: any? }
			error : code stable (clés de PartyConfig.ERRORS), message : texte français prêt à afficher.

		Action     params                                               data si ok
		---------  ---------------------------------------------------  ----------------------------
		getInfo    {}                                                   tranche "party" complète
		create     {}                                                   tranche "party"
		invite     { targetName: string } ou { targetUserId: number }   { targetUserId, targetName }
		           (joueur présent sur CE serveur ; crée le groupe si besoin)
		accept     { partyId: string }                                  tranche "party"
		decline    { partyId: string }                                  {}
		leave      {}                                                   {}
		kick       { targetUserId: number }   (chef)                    {}
		promote    { targetUserId: number }   (chef : transmet la direction) {}

	L'état arrive par StateSync (tranche "party") ; les notifications par StateRemotes.Notify avec
	kind = "party" et payload = { kind: string, text: string, ... }.
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("PartyRemotes")

return table.freeze({
	PartyRequest = remotes:func("PartyRequest"),
})
