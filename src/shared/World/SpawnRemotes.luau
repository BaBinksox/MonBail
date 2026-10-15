--!strict
--[[
	SpawnRemotes
	Arrivée du joueur dans le monde (SpawnService côté serveur).

	Sens des événements :
		ArrivalCinematic  serveur -> client  (cameraCFrame: CFrame, focus: Vector3, regionName: string)
			Envoyé juste APRÈS que le serveur a placé le personnage au belvédère (ancre spawn_village),
			à la fermeture du créateur de personnage (première création) : le client joue le plan
			d'arrivée (fondu, caméra camera_overlook qui cadre le village, titre de la région), puis
			rend la caméra au joueur. `focus` = point que la caméra regarde (le village).
		CreatorStageReady serveur -> client  (stageCFrame: CFrame, cameraCFrame: CFrame?)
			Envoyé quand le personnage d'un joueur qui va créer son personnage a été placé dans le
			Sanctuaire des Âmes (ancre spawn_creator). cameraCFrame = ancre camera_creator si elle
			existe (le créateur peut s'en servir pour cadrer la scène), sinon nil.
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("SpawnRemotes")

return table.freeze({
	ArrivalCinematic = remotes:event("ArrivalCinematic"),
	CreatorStageReady = remotes:event("CreatorStageReady"),
})
