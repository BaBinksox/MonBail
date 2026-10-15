--!strict
--[[
	EnemyRemotes
	Événements du système d'ennemis (EnemyService côté serveur, EnemyEffectsController côté client).
	Ils vont TOUS du serveur vers les clients : le serveur n'accepte aucune requête ici (il ignore ce
	qu'un client y enverrait). Seuls les joueurs proches (TELEGRAPH_BROADCAST_RADIUS) les reçoivent.

	Sens des événements :
		Telegraph    serveur -> clients  (data: TelegraphData)
			Une attaque ennemie est annoncée : zone au sol à afficher pendant `duration` secondes.
			À la fin, le SERVEUR résout l'attaque sur les positions serveur des joueurs ; le client ne
			fait que la mettre en image (elle se remplit jusqu'à l'impact).
			`startedAt` = workspace:GetServerTimeNow() au départ : le client rattrape sa latence pour que
			le remplissage finisse au moment exact de l'impact (utile pour parer).
		EnemyAction  serveur -> clients  (data: ActionData)
			Événement visuel d'un ennemi : "cancel" (attaque interrompue : effacer ses télégraphes),
			"blink" (téléportation de `position` vers `toPosition`), "summon", "enrage", "reset"
			(retour au point d'apparition), "guard_block" / "guard_break" (garde du Gardien, à `position`).
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

export type TelegraphShape = "circle" | "cone" | "line"

export type TelegraphData = {
	shape: TelegraphShape,
	origin: Vector3, -- point AU SOL : centre du cercle, sommet du cône, départ de la ligne
	direction: Vector3?, -- unitaire, à plat (cône, ligne)
	radius: number, -- cercle : rayon ; cône : portée ; ligne : longueur
	angle: number?, -- cône : ouverture totale (degrés)
	length: number?, -- ligne : longueur
	width: number?, -- ligne : largeur
	duration: number, -- secondes jusqu'à l'impact
	enemy: Model?, -- auteur (pour l'effacer s'il est interrompu, et pour sa posture)
	unblockable: boolean, -- true = ne se pare pas (rouge vif) ; false = parable (orange)
	startedAt: number?, -- heure serveur du départ
}

export type ActionData = {
	enemy: Model,
	action: string,
	position: Vector3?,
	toPosition: Vector3?,
}

local remotes = RemoteFolder.new("EnemyRemotes")

return table.freeze({
	Telegraph = remotes:event("Telegraph"),
	EnemyAction = remotes:event("EnemyAction"),
})
