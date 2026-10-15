--!strict
--[[
	EnemyService
	Ennemis de la Région 1 (singleton serveur) : apparition, IA, attaques, récompenses, réapparition.

	APPARITION
		Un ennemi par ancre de EnemyDefinitions.SPAWNS, trouvée par WorldAnchors (aucune coordonnée).
		Carte absente : rien n'apparaît (un seul avertissement), et tout apparaît dès que Workspace.World
		est construit. Chaque apparition est un NOUVEAU Model (EnemyFactory, génération dans un thread à
		part), rangé dans Workspace.Enemies, simulé par le serveur (SetNetworkOwner(nil)), avec :
			- tags EnemyDefinitions.TAG ("Enemy") et TimeLoopConfig.ENTITY_TAG (cible de l'épée, de
			  l'ultime et du soft-lock) ;
			- attributs EnemyId, Elite (élite), Rewindable = false (hors timeline du rembobinage),
			  SpawnAnchor ; Humanoid.DisplayName = nom de la définition.
		Le boss d'entraînement est seulement posé et taggé BossConfig.TAG : BossService le pilote.

	IA
		UNE seule boucle (Heartbeat, toutes les AI.THINK_INTERVAL s) fait penser tous les ennemis :
		étourdissement (CombatStatus) = ni déplacement ni attaque ; laisse dépassée = retour au point
		d'apparition, invulnérable et en régénération ; sinon le comportement (Behaviors/*) décide.
		Aucune décision ne yield : chemins et résolutions d'attaque sont planifiés à part (EnemyBrain).

	MORT
		DamageService émet GameEvents.EnemyDefeated une fois par apparition. Pour ses ennemis (boss
		compris), EnemyService verse à chaque joueur éligible l'XP et un butin tiré pour LUI
		(RewardService.grant, sans clé de ledger : l'unicité vient de DamageService), compte
		l'élimination dans profile.stats.kills, puis le corps disparaît (attribut Despawning : fondu
		côté client) et un nouveau Model réapparaît au même point après le délai.

	API
		EnemyService.start()
		EnemyService.getEnemiesNear(position: Vector3, radius: number): { Model }   (vivants)
		EnemyService.isEnemy(model): boolean
		EnemyService.getEnemyId(model): string?
		EnemyService.Spawned : Signal (model: Model, enemyId: string)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Definitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)
local EnemyRemotes = require(ReplicatedStorage.Shared.Enemy.EnemyRemotes)
local ItemConfig = require(ReplicatedStorage.Shared.Progression.ItemConfig)
local ParryConfig = require(ReplicatedStorage.Shared.Combat.ParryConfig)
local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local TimeLoopConfig = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

local CombatStatus = require(script.Parent.Parent.Combat.CombatStatus)
local DamageService = require(script.Parent.Parent.Combat.DamageService)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local WorldAnchors = require(script.Parent.Parent.World.WorldAnchors)
local EnemyBrain = require(script.Parent.EnemyBrain)
local EnemyFactory = require(script.Parent.EnemyFactory)

type EnemyDef = Definitions.EnemyDef
type Enemy = EnemyBrain.Enemy

-- Un point d'apparition et son occupant actuel.
type Slot = {
	anchorId: string,
	enemyId: string,
	respawn: number,
	current: Model?, -- Model vivant de ce point (nil dès la mort)
	isSpawning: boolean,
	respawnThread: thread?,
	hasWarnedMissing: boolean,
}

-- Un Model d'ennemi en jeu (vivant ou corps en train de disparaître).
type Entry = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	def: EnemyDef,
	slot: Slot?, -- nil pour une invocation (pas de réapparition)
	brain: Enemy?, -- nil pour le boss (piloté par BossService)
	isDefeated: boolean,
	isRemoved: boolean,
	connections: { RBXScriptConnection },
	despawnThread: thread?,
}

local ATTRIBUTES = Definitions.ATTRIBUTES
local AI = Definitions.AI
local RESPAWN_RETRY_DELAY = 30 -- secondes avant de réessayer une apparition impossible
local WORLD_SETTLE_DELAY = 2 -- secondes laissées au générateur pour poser les ancres
local FADE_MARGIN = 0.2 -- secondes après le fondu avant de détruire le corps
local ERROR_REPORT_INTERVAL = 10 -- secondes entre deux avertissements d'erreur d'un même ennemi

local BEHAVIORS: { [string]: EnemyBrain.Behavior } = {
	skirmisher = require(script.Parent.Behaviors.Skirmisher),
	guardian = require(script.Parent.Behaviors.Guardian),
	caster = require(script.Parent.Behaviors.Caster),
	elite = require(script.Parent.Behaviors.Elite),
	dummy = require(script.Parent.Behaviors.Dummy),
}
local EXTERNAL_BEHAVIORS: { [string]: boolean } = { boss = true } -- IA gérée par un autre service

local EnemyService = {}

-- Spawned(model: Model, enemyId: string) : un ennemi vient d'apparaître (déjà dans Workspace).
EnemyService.Spawned = Signal.new()

local slots: { [string]: Slot } = {}
local entries: { [Model]: Entry } = {}
local brains: { Enemy } = {} -- ennemis qui pensent (ordre stable)
local lastErrorClock: { [Enemy]: number } = setmetatable({}, { __mode = "k" }) :: any
local random = Random.new()
local thinkAccumulator = 0
local hasWarnedWorld = false
local isStarted = false

--------------------------------------------------------------------------------
-- Vérification des définitions
--------------------------------------------------------------------------------

local function validateDefinitions()
	for anchorId, spawnDef in Definitions.SPAWNS do
		if RegionConfig.ANCHORS[anchorId] == nil then
			warn(`[Enemy] SPAWNS.{anchorId} : ancre inconnue de RegionConfig.ANCHORS`)
		end
		if Definitions.ENEMIES[spawnDef.enemyId] == nil then
			warn(`[Enemy] SPAWNS.{anchorId} : ennemi inconnu "{spawnDef.enemyId}"`)
		end
	end
	for enemyId, def in Definitions.ENEMIES do
		if BEHAVIORS[def.behavior] == nil and not EXTERNAL_BEHAVIORS[def.behavior] then
			warn(`[Enemy] {enemyId} : comportement inconnu "{def.behavior}"`)
		end
		for _, loot in def.loot do
			if ItemConfig.getItem(loot.itemId) == nil then
				warn(`[Enemy] {enemyId} : objet de butin inconnu "{loot.itemId}"`)
			end
		end
		local practice = def.practice
		if practice then
			local found = false
			for _, attack in def.attacks do
				found = found or attack.id == practice.attackId
			end
			if not found then
				warn(`[Enemy] {enemyId} : attaque d'entraînement inconnue "{practice.attackId}"`)
			end
		end
		local summon = def.summon
		if summon and Definitions.ENEMIES[summon.enemyId] == nil then
			warn(`[Enemy] {enemyId} : invocation inconnue "{summon.enemyId}"`)
		end
	end
end

--------------------------------------------------------------------------------
-- Disparition et réapparition
--------------------------------------------------------------------------------

local function removeBrain(brain: Enemy)
	local index = table.find(brains, brain)
	if index then
		table.remove(brains, index)
	end
end

-- Retire définitivement un Model (corps, invocation, ennemi perdu) et libère tout ce qui s'y rattache.
local function removeEntry(entry: Entry)
	if entry.isRemoved then
		return
	end
	entry.isRemoved = true
	entries[entry.model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	table.clear(entry.connections)
	local despawnThread = entry.despawnThread
	entry.despawnThread = nil
	if despawnThread and despawnThread ~= coroutine.running() then
		pcall(task.cancel, despawnThread)
	end
	local brain = entry.brain
	if brain then
		removeBrain(brain)
		EnemyBrain.shutdown(brain)
	end
	local slot = entry.slot
	if slot and slot.current == entry.model then
		slot.current = nil
	end
	entry.model:Destroy()
end

local spawnSlot: (slot: Slot) -> ()

local function scheduleRespawn(slot: Slot, delay: number)
	local pending = slot.respawnThread
	if pending then
		pcall(task.cancel, pending)
	end
	slot.respawnThread = task.delay(delay, function()
		slot.respawnThread = nil
		spawnSlot(slot)
	end)
end

-- Corps : reste `corpseDuration` s, puis fondu côté client (attribut), puis destruction.
local function scheduleDespawn(entry: Entry)
	local corpseDuration = entry.def.corpseDuration or Definitions.DEFAULT_CORPSE_DURATION
	entry.despawnThread = task.delay(corpseDuration, function()
		if entry.isRemoved then
			return
		end
		entry.model:SetAttribute(ATTRIBUTES.despawning, true)
		entry.despawnThread = task.delay(Definitions.DESPAWN_FADE_DURATION + FADE_MARGIN, function()
			entry.despawnThread = nil
			removeEntry(entry)
		end)
	end)
end

-- Le Model a quitté le jeu sans être éliminé (chute dans le vide, script tiers) : on le remplace.
local function onEntryLost(entry: Entry)
	if entry.isRemoved then
		return
	end
	local slot = entry.slot
	local wasDefeated = entry.isDefeated
	removeEntry(entry)
	if slot and not wasDefeated and slot.current == nil then
		scheduleRespawn(slot, slot.respawn)
	end
end

--------------------------------------------------------------------------------
-- Apparition
--------------------------------------------------------------------------------

local function connectBrain(entry: Entry, brain: Enemy)
	local model = entry.model
	local humanoid = entry.humanoid

	-- Un étourdissement (parade, garde brisée, Foudre...) annule tout de suite l'attaque en préparation.
	table.insert(
		entry.connections,
		model:GetAttributeChangedSignal(ParryConfig.STUNNED_UNTIL_ATTRIBUTE):Connect(function()
			if brain.isAlive and CombatStatus.isStunned(model) then
				EnemyBrain.interrupt(brain)
			end
		end)
	)

	-- Horloge du dernier coup reçu (régénération du mannequin, régénération hors combat).
	local lastHealth = humanoid.Health
	table.insert(
		entry.connections,
		humanoid.HealthChanged:Connect(function(health: number)
			if health < lastHealth then
				brain.lastDamagedClock = os.clock()
			end
			lastHealth = health
		end)
	)
end

--[[
	Met en jeu un Model construit par EnemyFactory : réglages, pose au sol, tags, fiche d'élimination
	(DamageService), cerveau. Retourne l'entrée, ou nil si le Model est inutilisable.
]]
local function activate(model: Model, def: EnemyDef, cframe: CFrame, slot: Slot?, summoner: Enemy?): Entry?
	local humanoid, rootPart = EnemyFactory.getParts(model)
	if humanoid == nil or rootPart == nil then
		warn(`[Enemy] {def.id} : Model sans Humanoid ni RootPart, apparition annulée`)
		model:Destroy()
		return nil
	end
	EnemyFactory.configure(model, def, if slot then slot.anchorId else nil)
	local rootHeight = EnemyFactory.placeAt(model, cframe, EnemyBrain.getWorldParams())
	if def.anchored then
		rootPart.Anchored = true
	end

	-- Attributs posés AVANT l'entrée dans le Workspace et les tags : les autres services les lisent
	-- dès l'inscription (TimeLoopService : Rewindable ; BossService : Model dans le Workspace).
	model.Parent = EnemyBrain.getFolder()
	if rootPart:CanSetNetworkOwnership() then
		rootPart:SetNetworkOwner(nil)
	end
	CollectionService:AddTag(model, Definitions.TAG)
	CollectionService:AddTag(model, TimeLoopConfig.ENTITY_TAG)
	-- Fiche d'élimination créée tout de suite, avec les PV max définitifs : même une mort qui ne
	-- passerait pas par DamageService.dealDamage émet EnemyDefeated (filet Humanoid.Died).
	DamageService.getUid(model)
	if def.behavior == "boss" then
		CollectionService:AddTag(model, BossConfig.TAG)
	end

	local entry: Entry = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		def = def,
		slot = slot,
		brain = nil,
		isDefeated = false,
		isRemoved = false,
		connections = {},
		despawnThread = nil,
	}
	entries[model] = entry

	local behavior = BEHAVIORS[def.behavior]
	if behavior then
		local brain = EnemyBrain.new(model, humanoid, rootPart, def, rootPart.CFrame, behavior, rootHeight)
		brain.summoner = summoner
		entry.brain = brain
		local init = behavior.init
		if init then
			init(brain)
		end
		connectBrain(entry, brain)
		table.insert(brains, brain)
	end

	table.insert(
		entry.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				onEntryLost(entry)
			end
		end)
	)

	EnemyService.Spawned:Fire(model, def.id)
	return entry
end

-- Fait apparaître l'occupant de `slot`. YIELD (génération du rig) : toujours dans un thread à part.
spawnSlot = function(slot: Slot)
	if slot.current or slot.isSpawning then
		return
	end
	local def = Definitions.ENEMIES[slot.enemyId]
	if def == nil then
		return
	end
	if WorldAnchors.getCFrame(slot.anchorId) == nil then
		if not slot.hasWarnedMissing then
			slot.hasWarnedMissing = true
			warn(`[Enemy] Ancre "{slot.anchorId}" introuvable : {def.displayName} n'apparaît pas (carte incomplète ?)`)
		end
		return
	end

	slot.isSpawning = true
	local isBuilt, model = pcall(EnemyFactory.build, def)
	slot.isSpawning = false
	if not isBuilt then
		warn(`[Enemy] Construction de {def.id} impossible : {model}`)
		scheduleRespawn(slot, RESPAWN_RETRY_DELAY)
		return
	end

	-- La carte a pu être reconstruite pendant la génération : on relit l'ancre.
	local anchorCFrame = WorldAnchors.getCFrame(slot.anchorId)
	if anchorCFrame == nil or slot.current then
		model:Destroy()
		return
	end
	if activate(model, def, anchorCFrame, slot, nil) then
		slot.current = model
	end
end

local function spawnAll()
	if not WorldAnchors.isWorldBuilt() then
		if not hasWarnedWorld then
			hasWarnedWorld = true
			warn(
				`[Enemy] Workspace.{RegionConfig.WORLD_FOLDER_NAME} est absent (carte non construite) : aucun ennemi n'apparaît. `
					.. "Ils apparaîtront dès que WorldBuilder aura construit la carte."
			)
		end
		return
	end
	for _, slot in slots do
		if slot.current == nil and not slot.isSpawning and slot.respawnThread == nil then
			task.spawn(spawnSlot, slot)
		end
	end
end

-- Invocation (élite) : pas de point d'apparition, pas de réapparition.
local function spawnSummon(owner: Enemy, enemyId: string, cframe: CFrame, onSpawned: (Enemy) -> ())
	local def = Definitions.ENEMIES[enemyId]
	if def == nil then
		return
	end
	task.spawn(function()
		local isBuilt, model = pcall(EnemyFactory.build, def)
		if not isBuilt then
			warn(`[Enemy] Invocation de {enemyId} impossible : {model}`)
			return
		end
		if not owner.isAlive then
			model:Destroy() -- l'invocateur est tombé pendant la génération
			return
		end
		local entry = activate(model, def, cframe, nil, owner)
		local brain = entry and entry.brain
		if brain then
			onSpawned(brain)
		end
	end)
end

local function despawnSilently(enemy: Enemy)
	local entry = entries[enemy.model]
	if entry and not entry.isDefeated then
		removeEntry(entry)
	end
end

--------------------------------------------------------------------------------
-- Mort et récompenses
--------------------------------------------------------------------------------

-- Butin tiré pour UN joueur.
local function rollLoot(def: EnemyDef): { [string]: number }
	local items: { [string]: number } = {}
	for _, loot in def.loot do
		if random:NextNumber() < loot.chance then
			items[loot.itemId] = (items[loot.itemId] or 0) + loot.count
		end
	end
	return items
end

local function rewardPlayers(def: EnemyDef, eligible: { Player })
	for _, player in eligible do
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
			continue
		end
		local items = rollLoot(def)
		if def.xp > 0 or next(items) ~= nil then
			RewardService.grant(player, nil, { xp = def.xp, items = items }, { reason = def.displayName })
		end
		PlayerData.mutate(player, "stats", function(profile)
			local kills = profile.stats.kills
			kills[def.id] = (kills[def.id] or 0) + 1
		end)
	end
end

local function onEnemyDefeated(info: GameEvents.DefeatInfo)
	local entry = entries[info.enemy]
	if entry == nil or entry.isDefeated then
		return -- pas un de nos ennemis, ou déjà traité
	end
	entry.isDefeated = true

	local brain = entry.brain
	if brain then
		removeBrain(brain)
		EnemyBrain.shutdown(brain)
	end
	entry.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, nil)
	entry.model:SetAttribute(ATTRIBUTES.returning, nil)

	rewardPlayers(entry.def, info.eligible)
	scheduleDespawn(entry)

	local slot = entry.slot
	if slot and slot.current == entry.model then
		slot.current = nil
		-- Jamais avant la disparition du corps : deux Models au même point prêteraient à confusion.
		local corpseDuration = entry.def.corpseDuration or Definitions.DEFAULT_CORPSE_DURATION
		local minimum = corpseDuration + Definitions.DESPAWN_FADE_DURATION + FADE_MARGIN
		scheduleRespawn(slot, math.max(slot.respawn, minimum))
	end
end

--------------------------------------------------------------------------------
-- Boucle d'IA
--------------------------------------------------------------------------------

local function startReturn(brain: Enemy, now: number)
	EnemyBrain.interrupt(brain)
	brain.state = "returning"
	brain.target = nil
	brain.targetRoot = nil
	brain.lastAttacker = nil
	brain.returnStartedClock = now
	brain.model:SetAttribute(ATTRIBUTES.returning, true)
	-- Invulnérable pendant le retour : attirer un ennemi au bout de sa laisse ne donne pas de coups gratuits.
	brain.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, true)
	local onReset = brain.behavior.onReset
	if onReset then
		onReset(brain)
	end
	EnemyBrain.action(brain, "reset")
end

local function finishReturn(brain: Enemy)
	brain.state = "idle"
	brain.humanoid.Health = brain.humanoid.MaxHealth
	brain.model:SetAttribute(ATTRIBUTES.returning, nil)
	brain.model:SetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE, nil)
	EnemyBrain.stop(brain)
	EnemyBrain.face(brain, brain.home.Position + brain.home.LookVector * 10)
end

local function updateReturn(brain: Enemy, now: number, dt: number)
	local humanoid = brain.humanoid
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * AI.RETURN_REGEN_RATE * dt)
	if EnemyBrain.distanceFromHome(brain) <= AI.HOME_TOLERANCE then
		finishReturn(brain)
	elseif now - brain.returnStartedClock > AI.RETURN_TIMEOUT then
		EnemyBrain.teleport(brain, brain.home.Position, brain.home.Position + brain.home.LookVector)
		finishReturn(brain)
	else
		EnemyBrain.moveTo(brain, brain.home.Position)
	end
end

-- Hors combat depuis un moment : l'ennemi panse ses plaies.
local function regenerateOutOfCombat(brain: Enemy, now: number, dt: number)
	local humanoid = brain.humanoid
	if brain.target ~= nil or humanoid.Health >= humanoid.MaxHealth then
		return
	end
	if now - brain.lastDamagedClock < AI.OUT_OF_COMBAT_DELAY then
		return
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * AI.OUT_OF_COMBAT_REGEN_RATE * dt)
end

local function thinkEnemy(brain: Enemy, now: number, dt: number)
	if not brain.isAlive then
		return
	end
	local entry = entries[brain.model]
	if entry == nil or entry.isDefeated then
		return
	end
	if brain.rootPart.Parent == nil or not brain.model:IsDescendantOf(workspace) then
		onEntryLost(entry)
		return
	end
	if brain.humanoid.Health <= 0 then
		return -- la mort est traitée par EnemyDefeated
	end

	EnemyBrain.refreshSpeed(brain)
	if CombatStatus.isStunned(brain.model) or EnemyBrain.isImmobilized(brain) then
		if brain.pendingAction then
			EnemyBrain.interrupt(brain)
		end
		EnemyBrain.stop(brain)
		EnemyBrain.releaseFacing(brain)
		brain.state = "stunned"
		return
	end
	if now < brain.busyUntil then
		return -- télégraphe, récupération ou incantation en cours
	end

	if brain.state == "returning" then
		updateReturn(brain, now, dt)
		return
	end
	if not brain.rootPart.Anchored and EnemyBrain.distanceFromHome(brain) > brain.def.aggro.leashRadius then
		startReturn(brain, now)
		return
	end

	-- Personne aux alentours : il dort (et rentre chez lui s'il s'en était éloigné).
	local isAwake = brain.target ~= nil or EnemyBrain.isPlayerNear(brain, brain.def.aggro.detectRadius + AI.WAKE_MARGIN)
	if not isAwake then
		regenerateOutOfCombat(brain, now, dt)
		if EnemyBrain.distanceFromHome(brain) > AI.HOME_TOLERANCE then
			EnemyBrain.idle(brain)
		elseif brain.state ~= "asleep" then
			EnemyBrain.idle(brain)
			brain.state = "asleep"
		end
		return
	end

	EnemyBrain.updateTarget(brain, now)
	regenerateOutOfCombat(brain, now, dt)
	brain.behavior.think(brain, now, dt)
end

local function thinkAll(now: number, dt: number)
	-- À rebours : un ennemi retiré pendant le tour (perdu, invocation renvoyée) ne décale rien.
	for index = #brains, 1, -1 do
		local brain = brains[index]
		if brain == nil then
			continue
		end
		local isDone, message = pcall(thinkEnemy, brain, now, dt)
		if not isDone and now - (lastErrorClock[brain] or -math.huge) >= ERROR_REPORT_INTERVAL then
			lastErrorClock[brain] = now
			warn(`[Enemy] Erreur d'IA ({brain.enemyId}) : {message}`)
		end
	end
end

local function onHeartbeat(dt: number)
	thinkAccumulator += dt
	if thinkAccumulator < AI.THINK_INTERVAL then
		return
	end
	local elapsed = math.min(thinkAccumulator, AI.THINK_INTERVAL * 5) -- borne après un gel du serveur
	thinkAccumulator = 0
	thinkAll(os.clock(), elapsed)
end

--------------------------------------------------------------------------------
-- Garde, provocation (modificateur de DamageService)
--------------------------------------------------------------------------------

-- Appelé par DamageService.dealDamage avant chaque dégât infligé à un ennemi. Ne yield pas.
local function modifyDamage(target: Model, amount: number, source: DamageService.DamageSource): number
	local entry = entries[target]
	local brain = entry and entry.brain
	if brain == nil or not brain.isAlive then
		return amount
	end
	if source.player then
		brain.lastAttacker = source.player
		brain.lastAttackedClock = os.clock()
	end
	local modify = brain.behavior.modifyDamage
	return if modify then modify(brain, amount, source) else amount
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Ennemis vivants (non éliminés) dont le RootPart est à moins de `radius` studs de `position`.
function EnemyService.getEnemiesNear(position: Vector3, radius: number): { Model }
	local found = {}
	for model, entry in entries do
		if not entry.isDefeated and entry.humanoid.Health > 0 and entry.rootPart.Parent ~= nil then
			if (entry.rootPart.Position - position).Magnitude <= radius then
				table.insert(found, model)
			end
		end
	end
	return found
end

-- true si `model` a été créé par EnemyService et est encore en jeu (vivant ou corps).
function EnemyService.isEnemy(model: any): boolean
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	return entries[model :: Model] ~= nil
end

function EnemyService.getEnemyId(model: any): string?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local entry = entries[model :: Model]
	return if entry then entry.def.id else nil
end

-- À appeler une seule fois au démarrage du serveur (après DamageService, CombatService et BossService).
function EnemyService.start()
	if isStarted then
		return
	end
	isStarted = true

	validateDefinitions()
	for anchorId, spawnDef in Definitions.SPAWNS do
		local def = Definitions.ENEMIES[spawnDef.enemyId]
		if def then
			slots[anchorId] = {
				anchorId = anchorId,
				enemyId = spawnDef.enemyId,
				respawn = spawnDef.respawn or def.respawn or Definitions.DEFAULT_RESPAWN,
				current = nil,
				isSpawning = false,
				respawnThread = nil,
				hasWarnedMissing = false,
			}
		end
	end

	EnemyBrain.hooks.spawnSummon = spawnSummon
	EnemyBrain.hooks.despawn = despawnSilently
	DamageService.addModifier(modifyDamage)
	GameEvents.EnemyDefeated:Connect(onEnemyDefeated)

	-- Ces Remotes ne servent qu'à parler aux clients : ce qu'un client y envoie est ignoré.
	EnemyRemotes.Telegraph.OnServerEvent:Connect(function() end)
	EnemyRemotes.EnemyAction.OnServerEvent:Connect(function() end)

	RunService.Heartbeat:Connect(onHeartbeat)

	-- Carte construite (ou reconstruite) après le démarrage : les points vides se remplissent.
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == RegionConfig.WORLD_FOLDER_NAME then
			task.delay(WORLD_SETTLE_DELAY, spawnAll)
		end
	end)
	spawnAll()
end

return EnemyService
