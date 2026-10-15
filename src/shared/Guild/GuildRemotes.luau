--!strict
--[[
	GuildRemotes
	Remotes des guildes (GuildService côté serveur). Créés via Shared/Net/RemoteFolder.

	GuildRequest   client -> serveur   RemoteFunction (action: string, params: table?) -> Response
		Response = { ok: boolean, error: string?, message: string?, data: any? }
			error   : code stable (clés de GuildConfig.ERRORS), message : texte français prêt à afficher.
		Le client ne transmet JAMAIS un montant, un rôle ou un résultat : il demande, le serveur vérifie
		tout (permissions sur l'état STOCKÉ de la guilde, limites, filtre de texte Roblox...).

		Action           params                                         data si ok
		---------------  ---------------------------------------------  -----------------------------------
		getInfo          {}                                             tranche "guild" complète (voir GuildService)
		listInvites      {}                                             { IncomingInvite } (invitations reçues)
		create           { name: string, description: string? }        tranche "guild"
		invite           { targetName: string } (joueur de CE serveur)  { targetUserId, targetName }
		                 ou { targetUserId: number } (n'importe où)
		cancelInvite     { targetUserId: number }                       {}
		acceptInvite     { guildId: string }                            tranche "guild"
		declineInvite    { guildId: string }                            {}
		leave            {}                                             {}
		kick             { targetUserId: number }                       {}
		promote          { targetUserId: number }   (membre -> officier) {}
		demote           { targetUserId: number }   (officier -> membre) {}
		transfer         { targetUserId: number }   (nouveau chef)       {}
		setDescription   { description: string }                        {}
		dissolve         { confirmName: string }    (nom exact)          {}
		startContract    { contractId: string }     (contrat manuel)     {}
		claimContractReward { }                                         { granted: number }

	L'état à afficher n'arrive pas par ce Remote mais par StateSync (tranches "guild", StateRemotes) :
	après chaque action, la tranche est repoussée. Les notifications (toasts) arrivent par
	StateRemotes.Notify avec kind = "guild" et payload = { kind: string, text: string, ... }.
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("GuildRemotes")

return table.freeze({
	GuildRequest = remotes:func("GuildRequest"),
})
