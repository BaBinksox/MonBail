--!strict
--[[
	ParryRemotes
	Sens des événements :
		RequestParry  client  -> serveur  ()   le joueur lève sa garde (le serveur horodate la réception)
		ParryResult   serveur -> clients  (defender: Model, attacker: Model?, position: Vector3)
			Une parade a RÉUSSI : tous les clients jouent l'étincelle et le son ; le défenseur, le flash.
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("ParryRemotes")

return table.freeze({
	RequestParry = remotes:event("RequestParry"),
	ParryResult = remotes:event("ParryResult"),
})
