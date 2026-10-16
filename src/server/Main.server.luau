--!strict
--[[
	Main (Script serveur)
	Point d'entrée unique du serveur : démarre les services dans l'ordre (voir docs/ARCHITECTURE.md §8).
	Aucune logique ici, uniquement du câblage.

	Chaque start() est isolé : si un service échoue au démarrage, l'erreur est affichée dans la sortie
	et les services suivants démarrent quand même (le reste du jeu reste jouable).
]]

local Server = script.Parent

local function startService(name: string, module: any)
	local isStarted, message = pcall(function()
		module.start()
	end)
	if not isStarted then
		warn(`[Main] Le service {name} n'a pas pu démarrer : {message}`)
	end
end

-- 1. Données et progression (avant tout service qui lit un profil)
local ProfileStore = require(Server.Data.ProfileStore)
local CollisionGroups = require(Server.Core.CollisionGroups)
local StateSync = require(Server.State.StateSync)
local RewardService = require(Server.Progression.RewardService)
local ProgressionService = require(Server.Progression.ProgressionService)

-- 2. Monde
local WorldBuilder = require(Server.WorldBuild.WorldBuilder)
local WorldService = require(Server.World.WorldService)
local RegionService = require(Server.World.RegionService)
local SpawnService = require(Server.World.SpawnService)

-- 3. Personnage, temps, combat
local AvatarService = require(Server.Avatar.AvatarService)
local TimeLoopService = require(Server.TimeLoop.TimeLoopService)
local EncounterService = require(Server.Encounter.EncounterService)
local MovementService = require(Server.Movement.MovementService)
local ParryService = require(Server.Combat.ParryService)
local ResourceService = require(Server.Combat.ResourceService)
local PostureService = require(Server.Combat.PostureService)
local CombatService = require(Server.Combat.CombatService)
local BossService = require(Server.Boss.BossService)
local EnemyService = require(Server.Enemy.EnemyService)

-- 4. Habitants, objets du monde, quêtes et contrats
local NpcSpawner = require(Server.NPC.NpcSpawner)
local VillagerService = require(Server.NPC.VillagerService)
local QuestService = require(Server.Quest.QuestService)
local DialogueService = require(Server.NPC.DialogueService)
local MechanismService = require(Server.World.MechanismService)
local InteractionService = require(Server.World.InteractionService)
local EchoService = require(Server.World.EchoService)
local MissionService = require(Server.Mission.MissionService)

-- 5. Social
local PartyService = require(Server.Party.PartyService)
local GuildService = require(Server.Guild.GuildService)

startService("CollisionGroups", CollisionGroups) -- avant toute apparition : personnages et PNJ ne se poussent pas
startService("ProfileStore", ProfileStore) -- en premier : AvatarService charge les profils dès l'arrivée des joueurs
startService("StateSync", StateSync)
startService("RewardService", RewardService)
startService("ProgressionService", ProgressionService)

-- La carte n'est construite au démarrage que si elle est absente de la place (voir WorldBuildConfig).
local isWorldBuilt, worldMessage = pcall(WorldBuilder.ensureBuilt)
if not isWorldBuilt then
	warn(`[Main] Construction de la carte impossible : {worldMessage}`)
end

startService("WorldService", WorldService)
startService("RegionService", RegionService)
startService("SpawnService", SpawnService)
startService("AvatarService", AvatarService)
startService("TimeLoopService", TimeLoopService)
startService("EncounterService", EncounterService)
startService("MovementService", MovementService)
startService("ParryService", ParryService)
startService("ResourceService", ResourceService) -- Mana, Tension, Concentration : avant le combat et les sorts
startService("PostureService", PostureService)
startService("CombatService", CombatService)
startService("BossService", BossService)
startService("EnemyService", EnemyService)
startService("NpcSpawner", NpcSpawner)
startService("VillagerService", VillagerService)
startService("QuestService", QuestService)
startService("DialogueService", DialogueService)
startService("MechanismService", MechanismService)
startService("InteractionService", InteractionService)
startService("EchoService", EchoService)
startService("MissionService", MissionService)
startService("PartyService", PartyService)
startService("GuildService", GuildService)

-- Branchements entre services qui ne dépendent pas l'un de l'autre au chargement.
RegionService.setGuildLevelProvider(GuildService.getGuildLevel)
