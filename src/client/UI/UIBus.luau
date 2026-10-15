--!strict
--[[
	UIBus
	Bus d'événements ENTRE scripts client (aucun réseau). Permet par exemple au dialogue d'un PNJ
	d'ouvrir le tableau des contrats sans connaître le module qui le dessine.

	Événements :
		OpenPanel(panel: string, payload: any?)
			Demande d'ouvrir un panneau : "missions" (tableau des contrats), "guild", "party",
			"journal", "map", "progression", "inventory", "options". Le Grimoire l'écoute.
		ClosePanels()
			Ferme les panneaux ouverts (dialogue qui commence, cinématique...).
		ShowText(title: string, text: string)
			Affiche un texte à lire (inscription examinée, porte verrouillée...).
		DialogueStateChanged(isOpen: boolean)
			Un dialogue s'ouvre ou se ferme (les contrôles de combat se mettent en retrait).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal") :: ModuleScript)

return table.freeze({
	OpenPanel = Signal.new(),
	ClosePanels = Signal.new(),
	ShowText = Signal.new(),
	DialogueStateChanged = Signal.new(),
})
