--!strict
--[[
	Main (Script serveur)
	Point d'entrée unique du serveur : démarre les services dans l'ordre.
	Aucune logique ici, uniquement du câblage.
]]

local AvatarService = require(script.Parent.Avatar.AvatarService)
local BossService = require(script.Parent.Boss.BossService)
local CombatService = require(script.Parent.Combat.CombatService)
local MovementService = require(script.Parent.Movement.MovementService)
local ProfileStore = require(script.Parent.Data.ProfileStore)
local TimeLoopService = require(script.Parent.TimeLoop.TimeLoopService)
local VillagerService = require(script.Parent.NPC.VillagerService)
local WorldService = require(script.Parent.World.WorldService)

ProfileStore.start() -- en premier : AvatarService charge les profils dès l'arrivée des joueurs
WorldService.start() -- avant le boss, qui fait basculer le monde dans l'anomalie
AvatarService.start()
TimeLoopService.start()
MovementService.start()
CombatService.start()
BossService.start()
VillagerService.start()
