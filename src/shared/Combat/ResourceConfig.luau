--!strict
--[[
	ResourceConfig
	Les deux ressources de combat, partagées serveur + client (le SERVEUR seul les modifie ; elles
	vivent dans des attributs du Player, répliqués à son client pour l'interface) :
		MANA     énergie magique : sorts ordinaires et secondaires. Se régénère toute seule, plus vite
		         hors combat. Le joueur n'a jamais besoin de frapper à l'épée pour la récupérer ;
		TENSION  énergie de combat : se GAGNE par le jeu (coups, parades, esquives, actions risquées),
		         ne se régénère pas, et paie la technique ultime (100).
	CONCENTRATION : touche maintenue, posture magique : le Mana remonte beaucoup plus vite, mais le
	joueur se traîne, ne peut ni sprinter ni esquiver, prend plus de dégâts, et le premier coup reçu
	la rompt. Durée et recharge limitées : pas de Mana infini au milieu d'un combat.

	Toutes ces valeurs sont des points de départ d'équilibrage, pas un réglage définitif.
]]

return table.freeze({
	-- Mana ---------------------------------------------------------------------
	MANA_ATTRIBUTE = "Mana",
	MANA_MAX_ATTRIBUTE = "ManaMax",
	MANA_MAX = 100,
	MANA_REGEN_OUT_OF_COMBAT = 7, -- par seconde
	MANA_REGEN_IN_COMBAT = 3,
	REGEN_INTERVAL = 0.2, -- s entre deux régénérations côté serveur

	-- Combat (pour la régénération et la musique) ------------------------------------
	COMBAT_TIMEOUT = 6, -- s sans infliger ni subir de dégâts avant d'être « hors combat »
	IN_COMBAT_ATTRIBUTE = "InCombat", -- attribut (boolean) du Player

	-- Concentration --------------------------------------------------------------
	CONCENTRATION_REGEN = 24, -- Mana par seconde pendant la posture (au lieu de 3 ou 7)
	CONCENTRATION_MAX_DURATION = 4, -- s, puis elle s'interrompt d'elle-même
	CONCENTRATION_COOLDOWN = 8, -- s entre la fin d'une Concentration et la suivante
	CONCENTRATION_MOVE_MULTIPLIER = 0.25,
	CONCENTRATION_DAMAGE_TAKEN = 1.35,
	CONCENTRATING_ATTRIBUTE = "Concentrating", -- attribut (boolean) du Player
	CONCENTRATION_READY_ATTRIBUTE = "ConcentrationReadyAt", -- attribut (number, heure serveur)

	-- Tension : ce qui la fait monter (avant le multiplicateur du peuple) ------------------
	TENSION_SOURCES = table.freeze({
		comboHit = 8, -- coups 1 à 4 du combo
		finisherHit = 14, -- coup final du combo
		chargedHit = 12, -- frappe chargée (x 1,5 si pleine)
		counterHit = 16, -- riposte après parade
		perfectParry = 25,
		perfectDodge = 12,
		postureBreak = 15, -- posture d'un ennemi brisée
		spellHit = 4, -- sort qui touche (par cast, pas par cible)
		elementalReaction = 10,
	}),
})
