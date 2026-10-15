--!strict
--[[
	RewardService
	Versement des récompenses (XP, réputation, objets, déblocages, découvertes). Point UNIQUE : aucun
	autre script n'ajoute d'XP ou d'objet au profil.

	IDEMPOTENCE : une récompense unique porte une CLÉ stable. Si la clé est déjà dans profile.ledger,
	grant() refuse, quelle que soit la raison de la nouvelle demande (requête client répétée,
	reconnexion, double validation, rembobinage...). La clé et la récompense sont écrites dans le MÊME
	profil, donc sauvegardées ensemble : impossible d'avoir l'une sans l'autre.

	Conventions de clés :
		"quest:<questId>"                       quête (une seule fois)
		"mission:<missionId>"                   mission non répétable
		"cycle:mission:<missionId>:<cycleId>"   mission répétable, une fois par cycle (jour / semaine)
		"cycle:guild:<guildId>:<contractId>:<cycleId>"  part personnelle d'un contrat de guilde
		"chest:<interactableId>"                coffre / cache
		"collect:<interactableId>"              objet ramassé
	Les clés "cycle:..." de plus de LEDGER_CYCLE_RETENTION jours sont élaguées au chargement.

	Les éliminations d'ennemis n'utilisent PAS le ledger (il grossirait sans fin) : leur unicité est
	garantie par DamageService (une élimination par apparition, voir EnemyDefeated).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiscoveryConfig = require(ReplicatedStorage.Shared.Progression.DiscoveryConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Progression.ItemConfig)
local RankConfig = require(ReplicatedStorage.Shared.Progression.RankConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local StateSync = require(script.Parent.Parent.State.StateSync)
local ProgressionService = require(script.Parent.ProgressionService)

export type Reward = {
	xp: number?,
	reputation: number?,
	items: { [string]: number }?,
	unlocks: { string }?,
	discoveries: { string }?,
}

export type GrantOptions = {
	reason: string?, -- texte affiché dans la notification ("La Cloche Muette", "Rôdeur des Cendres"...)
	silent: boolean?, -- pas de notification
}

local LEDGER_CYCLE_RETENTION = 14 * 24 * 3600 -- secondes

local RewardService = {}

-- Granted(player, key: string?, reward: Reward, reason: string?)
RewardService.Granted = Signal.new()
-- Discovered(player, discoveryId: string)
RewardService.Discovered = Signal.new()

local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isPositiveCount(value: any): boolean
	return type(value) == "number" and value == value and value >= 1 and value % 1 == 0
end

-- Ajoute des objets à l'inventaire (sans dépasser maxStack). Retourne la liste réellement ajoutée.
local function addItems(profile: PlayerData.Profile, items: { [string]: number }): { { id: string, name: string, count: number } }
	local added = {}
	for itemId, count in items do
		local item = ItemConfig.getItem(itemId)
		if item == nil or not isPositiveCount(count) then
			warn(`[Reward] Objet inconnu ou quantité invalide ignoré : {itemId} x{count}`)
			continue
		end
		local current = profile.inventory[itemId] or 0
		local newCount = math.min(item.maxStack, current + count)
		if newCount > current then
			profile.inventory[itemId] = newCount
			table.insert(added, { id = itemId, name = item.name, count = newCount - current })
		end
	end
	return added
end

local function pruneLedger(player: Player)
	local now = os.time()
	PlayerData.mutate(player, "ledger", function(profile)
		for key, grantedAt in profile.ledger do
			if string.sub(key, 1, 6) == "cycle:" and now - grantedAt > LEDGER_CYCLE_RETENTION then
				profile.ledger[key] = nil
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- true si la récompense de clé `key` a déjà été versée à `player`.
function RewardService.hasClaimed(player: Player, key: string): boolean
	local profile = PlayerData.get(player)
	return profile ~= nil and profile.ledger[key] ~= nil
end

--[[
	Verse `reward` à `player`. Si `key` est fourni, la récompense est UNIQUE : un second appel avec la
	même clé est refusé. Retourne (true) si versée, (false, raison) sinon : "no_profile", "already".
	Ne yield pas.
]]
function RewardService.grant(player: Player, key: string?, reward: Reward, options: GrantOptions?): (boolean, string?)
	local profile = PlayerData.get(player)
	if profile == nil then
		return false, "no_profile"
	end
	if key and profile.ledger[key] then
		return false, "already"
	end

	local addedItems: { { id: string, name: string, count: number } } = {}
	local newUnlocks: { string } = {}
	PlayerData.mutate(player, { "progression", "inventory", "unlocks", "ledger" }, function(p)
		if key then
			p.ledger[key] = os.time()
		end
		if type(reward.reputation) == "number" and reward.reputation > 0 then
			p.progression.reputation += math.floor(reward.reputation)
		end
		if reward.items then
			addedItems = addItems(p, reward.items)
		end
		if reward.unlocks then
			for _, unlockId in reward.unlocks do
				if p.unlocks[unlockId] == nil then
					p.unlocks[unlockId] = os.time()
					table.insert(newUnlocks, unlockId)
				end
			end
		end
	end)

	local xp = if type(reward.xp) == "number" and reward.xp > 0 then math.floor(reward.xp) else 0
	if xp > 0 then
		ProgressionService.addXp(player, xp)
	end

	local opts: GrantOptions = options or {}
	if not opts.silent then
		StateSync.notify(player, "reward", {
			reason = opts.reason,
			xp = xp,
			reputation = reward.reputation or 0,
			items = addedItems,
			unlocks = newUnlocks,
		})
	end
	RewardService.Granted:Fire(player, key, reward, opts.reason)
	for _, added in addedItems do
		GameEvents.ItemCollected:Fire(player, added.id, added.count)
	end

	if reward.discoveries then
		for _, discoveryId in reward.discoveries do
			RewardService.discover(player, discoveryId)
		end
	end

	-- Une quête terminée ou un déblocage peuvent suffire à une promotion, même sans XP.
	ProgressionService.checkPromotion(player)
	if key then
		PlayerData.saveSoon(player) -- une récompense unique mérite d'être écrite tout de suite
	end
	return true
end

-- Découverte (lieu, secret, écho, récit). Unique par nature. Accorde DISCOVERY_XP la première fois.
-- Retourne true si c'est une nouvelle découverte.
function RewardService.discover(player: Player, discoveryId: string): boolean
	local profile = PlayerData.get(player)
	if profile == nil or profile.discoveries[discoveryId] then
		return false
	end
	PlayerData.mutate(player, "discoveries", function(p)
		p.discoveries[discoveryId] = os.time()
	end)
	local discovery = DiscoveryConfig.getDiscovery(discoveryId)
	StateSync.notify(player, "discovery", {
		id = discoveryId,
		name = if discovery then discovery.name else discoveryId,
		kind = if discovery then discovery.kind else "lore",
		xp = RankConfig.DISCOVERY_XP,
	})
	ProgressionService.addXp(player, RankConfig.DISCOVERY_XP)
	RewardService.Discovered:Fire(player, discoveryId)
	GameEvents.Discovered:Fire(player, discoveryId)
	ProgressionService.checkPromotion(player)
	return true
end

function RewardService.hasItems(player: Player, items: { [string]: number }): boolean
	local profile = PlayerData.get(player)
	if profile == nil then
		return false
	end
	for itemId, count in items do
		if (profile.inventory[itemId] or 0) < count then
			return false
		end
	end
	return true
end

-- Retire des objets (consommation, rendu de contrat). Tout ou rien. Retourne false s'il en manque.
function RewardService.takeItems(player: Player, items: { [string]: number }): boolean
	if not RewardService.hasItems(player, items) then
		return false
	end
	PlayerData.mutate(player, "inventory", function(p)
		for itemId, count in items do
			local remaining = (p.inventory[itemId] or 0) - count
			if remaining > 0 then
				p.inventory[itemId] = remaining
			else
				p.inventory[itemId] = nil
			end
		end
	end)
	return true
end

-- À appeler une seule fois au démarrage du serveur.
function RewardService.start()
	if isStarted then
		return
	end
	isStarted = true
	ProfileStore.ProfileLoaded:Connect(pruneLedger)
end

return RewardService
