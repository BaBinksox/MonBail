--!strict
--[[
	PartyConfig
	Règles des GROUPES : quelques joueurs d'un même serveur qui jouent ensemble (à ne pas confondre
	avec la guilde, persistante et multiserveur). Un groupe n'est pas sauvegardé : il disparaît
	quand ses membres partent.

	Règles (appliquées par PartyService) :
		- un joueur appartient à un seul groupe ; le groupe a un chef ;
		- seul le chef invite (un joueur sans groupe qui invite crée le groupe et en devient le chef),
		  exclut et transmet la direction ;
		- une invitation expire au bout de INVITE_TIMEOUT secondes ;
		- taille maximale MAX_SIZE ;
		- si le chef part (ou se déconnecte), la direction passe automatiquement au membre le plus
		  ancien ;
		- un groupe qui retombe à 1 membre est dissous ; un groupe seul dont la dernière invitation en
		  attente est refusée ou expire aussi ;
		- les membres à moins de SHARE_RANGE studs d'un joueur éligible à une élimination deviennent
		  éligibles eux aussi (récompense complète, voir DamageService).
]]

local ERRORS: { [string]: string } = {
	unknown_action = "Action inconnue.",
	bad_params = "Requête invalide.",
	rate_limited = "Trop de demandes : patientez un instant.",
	internal = "Erreur interne.",
	already_in_party = "Vous faites déjà partie d'un groupe.",
	not_in_party = "Vous ne faites partie d'aucun groupe.",
	not_leader = "Seul le chef du groupe peut faire cela.",
	unknown_player = "Ce joueur n'est pas sur ce serveur.",
	target_is_self = "Vous ne pouvez pas vous viser vous-même.",
	target_in_party = "Ce joueur fait déjà partie d'un groupe.",
	target_not_member = "Ce joueur n'est pas dans votre groupe.",
	party_full = "Le groupe est complet.",
	invites_full = "Trop d'invitations en attente.",
	invite_not_found = "Invitation introuvable ou expirée.",
	party_not_found = "Ce groupe n'existe plus.",
}

local function errorMessage(code: string?): string
	return if code then ERRORS[code] or code else ""
end

return table.freeze({
	MAX_SIZE = 4, -- membres par groupe, chef compris
	INVITE_TIMEOUT = 60, -- secondes avant qu'une invitation expire
	MAX_PENDING_INVITES = 6, -- invitations en attente par groupe
	SHARE_RANGE = 150, -- studs : partage de l'éligibilité aux éliminations entre membres proches
	EXPIRY_CHECK_INTERVAL = 1, -- secondes entre deux nettoyages des invitations expirées

	ERRORS = ERRORS,
	errorMessage = errorMessage,
})
