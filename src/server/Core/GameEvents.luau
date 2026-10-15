--!strict
--[[
	GameEvents
	Bus d'événements de jeu côté serveur : les systèmes qui PRODUISENT un fait l'émettent ici, ceux
	qui en TIRENT une progression (quêtes, missions, contrats de guilde, statistiques) l'écoutent.
	Aucun producteur ne connaît ses consommateurs, ce qui permet d'ajouter un consommateur (un nouveau
	type de contrat) sans toucher au combat ni au monde.

	Un événement est un FAIT validé par le serveur (jamais une affirmation du client). Les consommateurs
	l'appliquent de façon idempotente (clés de récompense, objectifs plafonnés).

	Événements (arguments) :
		EnemyDefeated(info: DefeatInfo)
			Un ennemi (ou un boss) vient d'être éliminé, UNE fois par apparition (DamageService).
		Discovered(player: Player, discoveryId: string)
			Nouvelle découverte (RewardService).
		RegionEntered(player: Player, regionId: string)
			Le joueur entre dans une région (RegionService). Émis à chaque entrée.
		Talked(player: Player, npcId: string)
			Le joueur a parlé à un PNJ (NpcId = AnchorId du marqueur, ex. "npc_bellkeeper").
		InteractableUsed(player: Player, interactableId: string, kind: string)
			Interaction validée par InteractionService (examine, collect, chest, rune...).
		EchoWitnessed(player: Player, echoId: string)
			Le joueur a vu un écho en entier, à proximité (EchoService).
		PuzzleSolved(players: { Player }, mechanismId: string)
			Un puzzle a été résolu ; `players` = joueurs présents à proximité (MechanismService).
		MechanismActivated(player: Player, mechanismId: string)
			Un mécanisme a été activé par ce joueur (pouvoir, ancre temporelle).
		ItemCollected(player: Player, itemId: string, count: number)
			Objet obtenu (butin, collecte, coffre).
		QuestCompleted(player: Player, questId: string)
		MissionCompleted(player: Player, missionId: string, cycleId: string)
		AnomalyResolved(info: AnomalyInfo)
			Une anomalie de boss s'est terminée (rembobinage réussi ou expiration).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type DefeatInfo = {
	enemy: Model, -- le Model (peut être détruit peu après)
	enemyId: string, -- id de définition (EnemyDefinitions) ou "training_boss"
	uid: string, -- identifiant unique de cette apparition
	position: Vector3,
	eligible: { Player }, -- joueurs éligibles aux récompenses (contribution + distance, voir DamageService)
	killer: Player?, -- auteur du coup fatal, s'il s'agit d'un joueur
	isBoss: boolean,
	isElite: boolean,
}

export type AnomalyInfo = {
	encounterId: string,
	target: Player, -- joueur visé par l'attaque fatale
	participants: { Player }, -- joueurs de la rencontre au moment de la résolution
	outcome: "rewound" | "expired" | "cancelled",
	rewoundBy: Player?, -- auteur du rembobinage réussi
}

return table.freeze({
	EnemyDefeated = Signal.new(),
	Discovered = Signal.new(),
	RegionEntered = Signal.new(),
	Talked = Signal.new(),
	InteractableUsed = Signal.new(),
	EchoWitnessed = Signal.new(),
	PuzzleSolved = Signal.new(),
	MechanismActivated = Signal.new(),
	ItemCollected = Signal.new(),
	QuestCompleted = Signal.new(),
	MissionCompleted = Signal.new(),
	AnomalyResolved = Signal.new(),
})
