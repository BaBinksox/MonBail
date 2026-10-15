--!strict
--[[
	ParryConfig
	Réglages de la parade parfaite et de l'étourdissement (partagés serveur + client).

	Principe : le joueur appuie sur la touche de parade (KeyBindings.Parry) juste AVANT qu'un coup
	ennemi ne le touche. Le client joue tout de suite la posture (retour immédiat), mais c'est le
	SERVEUR qui décide : il horodate la réception de la demande et, au moment de l'impact, regarde si
	elle tombe dans la fenêtre, corrigée de la latence du joueur (voir ParryService).

	Une parade réussie : aucun dégât, l'attaquant est étourdi (STAGGER_DURATION), le joueur gagne de la
	Tension (PARRY_TENSION). Les attaques de zone télégraphiées au sol ne se parent pas : elles s'esquivent.
]]

return table.freeze({
	-- Fenêtre : la demande peut arriver jusqu'à PERFECT_WINDOW secondes AVANT l'impact (côté serveur)...
	PERFECT_WINDOW = 0.22,
	-- ...ou APRÈS l'impact, de la latence mesurée du joueur (bornée) + une petite marge : le client voit
	-- le coup partir en retard sur le serveur, et sa demande met du temps à arriver.
	MAX_PING_COMPENSATION = 0.25,
	LATE_SLACK = 0.05,
	-- Une demande de parade ne peut pas être renouvelée avant ce délai (pas de parade en rafale).
	COOLDOWN = 0.55,

	PARRY_TENSION = 25, -- Tension gagnée par parade réussie
	STAGGER_DURATION = 1.6, -- secondes d'étourdissement de l'attaquant paré

	-- Attribut (number = workspace:GetServerTimeNow() de fin) posé par le serveur sur un Model étourdi.
	-- Les IA (ennemis, boss) n'attaquent pas tant qu'il n'est pas dépassé ; le client affiche l'étourdissement.
	STUNNED_UNTIL_ATTRIBUTE = "StunnedUntil",
	-- Attribut (number) posé par le serveur sur le Player qui pare : l'instant de sa posture, pour les VFX.
	PARRY_STANCE_ATTRIBUTE = "ParryStanceAt",

	STANCE_DURATION = 0.35, -- durée visuelle de la posture côté client
})
