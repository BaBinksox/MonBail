--!strict
--[[
	DialogueRemotes
	Dialogues fournis par le serveur (DialogueService) : répliques liées aux quêtes et choix.

	Sens :
		GetDialogue   client -> serveur  (npc: Model) -> { npcId: string, name: string, lines: { string }?, options: { { id, label } } }?
			Le serveur vérifie le PNJ (tag, distance) et répond selon les quêtes du joueur. `lines` absent :
			le client garde le texte habituel du PNJ (DialogueConfig). nil : PNJ inconnu du serveur.
		ChooseOption  client -> serveur  (npc: Model, optionId: string) -> { ok: boolean, action: string?, message: string? }
			Le serveur n'accepte qu'un choix qu'il vient lui-même de proposer pour ce PNJ.
			action : "close" | "open_missions" | "open_guild".
]]

local RemoteFolder = require(script.Parent.Parent.Net.RemoteFolder)

local remotes = RemoteFolder.new("DialogueRemotes")

return table.freeze({
	GetDialogue = remotes:func("GetDialogue"),
	ChooseOption = remotes:func("ChooseOption"),
})
