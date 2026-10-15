--!strict
--[[
	EchoRemotes
	Sens des événements :
		PlayEcho  serveur -> client  (echoId: string, points: { Vector3 }, startServerTime: number)
			Le serveur a décidé que CE joueur voit l'écho : le client crée la silhouette et la fait marcher
			le long des points (EchoConfig : vitesse, pauses, runes touchées, sous-titres).
		StopEcho  serveur -> client  (echoId: string)
			Le joueur s'est trop éloigné : l'écho se dissipe (il ne compte pas).
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("EchoRemotes")

return table.freeze({
	PlayEcho = remotes:event("PlayEcho"),
	StopEcho = remotes:event("StopEcho"),
})
