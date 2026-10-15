--!strict
--[[
	GuildService
	Guildes persistantes et multiserveurs (singleton serveur) : API Remote GuildRequest, cohérence
	profil <-> guilde, progression collective des contrats, tranche d'état "guild".

	Source de vérité : l'enregistrement de guilde (GuildStore). profile.guild n'est qu'un POINTEUR.
		- Toute écriture passe par GuildStore.update (UpdateAsync) + une transformation de GuildRules
		  qui revérifie les permissions sur l'état stocké, avec un opId unique (idempotence).
		- Ordre fixe des opérations profil + guilde : d'abord la guilde, puis le pointeur du profil.
		- RÉCONCILIATION au chargement du profil et à chaque relecture d'une guilde : pointeur effacé si
		  la guilde ne liste plus le joueur (ou est dissoute), rétabli si elle le liste. Un joueur dont le
		  pointeur est vide est recherché via ses indices (GuildStore.readUser : invitations reçues,
		  création en cours) : c'est ce qui répare une opération interrompue entre les deux écritures.
		- Création : réservation du nom -> indice « création en cours » -> enregistrement de la guilde
		  -> pointeur -> confirmation du nom dans l'index -> indice retiré.
		- Les autres serveurs sont prévenus par GuildMessaging (simple signal de relecture) ; les guildes
		  qui ont des membres ici sont de toute façon relues toutes les REFRESH_INTERVAL secondes.

	Progression collective (contrats de guilde, GuildConfig.CONTRACTS) :
		- écoute GameEvents (EnemyDefeated, Discovered, AnomalyResolved, MissionCompleted) ;
		- ACCUMULE en mémoire, par guilde : progression collective (+1 par événement et par guilde) et
		  contributions individuelles ;
		- ÉCRIT par lots toutes les FLUSH_INTERVAL secondes et au départ d'un joueur, via
		  GuildRules.applyContractProgress : les incréments sont ADDITIONNÉS à la valeur stockée, donc
		  deux serveurs qui écrivent en même temps ne perdent rien ; complétion et XP de guilde sont
		  calculées dans la transformation (une seule fois). Un lot non écrit (panne) est gardé avec son
		  opId et renvoyé plus tard ;
		- part individuelle versée par RewardService.grant(player, "cycle:guild:<guildId>:<contractId>:
		  <cycleId>", ...) aux contributeurs (lus dans l'enregistrement), idempotente même après
		  reconnexion ; personne n'a besoin que le chef soit connecté.

	API serveur pour les autres systèmes (lectures en mémoire, sans yield) :
		GuildService.getGuildId(player): string?
		GuildService.getGuildLevel(player): number?
		GuildService.isMemberOf(player, guildId): boolean
		GuildService.hasGuildUnlock(player, unlockId): boolean   (ex. "guild_archive" pour la porte)
		GuildService.MembershipChanged(player, guildId?)         (Signal)

	Attributs posés sur le Player : "GuildName" (nom affiché) et "GuildRole" ("leader" | "officer" |
	"member"), nil hors guilde.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local GuildConfig = require(ReplicatedStorage.Shared.Guild.GuildConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Progression.ItemConfig)
local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)
local Remotes = require(ReplicatedStorage.Shared.Guild.GuildRemotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local StateSync = require(script.Parent.Parent.State.StateSync)
local GuildMessaging = require(script.Parent.GuildMessaging)
local GuildRules = require(script.Parent.GuildRules)
local GuildStore = require(script.Parent.GuildStore)

type GuildRecord = GuildRules.GuildRecord
type Actor = GuildRules.Actor
type Role = GuildConfig.Role
type Contract = GuildConfig.Contract

export type Response = {
	ok: boolean,
	error: string?,
	message: string?,
	data: any?,
}

type Params = { [string]: any }
type ActionSpec = {
	writes: boolean, -- refusée si le profil n'est pas sauvegardable
	handler: (player: Player, params: Params) -> Response,
}

export type IncomingInvite = {
	guildId: string,
	guildName: string,
	inviterName: string,
	expiresAt: number,
}

type QueuedBatch = {
	opId: string,
	batch: GuildRules.ProgressBatch,
}

local NAME_ATTRIBUTE = "GuildName"
local ROLE_ATTRIBUTE = "GuildRole"
local CLOSE_FLUSH_TIMEOUT = 20 -- secondes laissées aux dernières écritures à la fermeture
local LIST_INVITES_MIN_INTERVAL = 10 -- secondes entre deux relectures d'invitations demandées par le client
local REREAD_DEBOUNCE = 1 -- secondes : plusieurs messages pour une même guilde = une seule relecture

local GuildService = {}

-- MembershipChanged(player, guildId: string?) : le joueur vient d'entrer dans une guilde ou d'en sortir.
GuildService.MembershipChanged = Signal.new()

local isStarted = false
local isClosing = false

local memberGuild: { [Player]: string } = {} -- guilde (réconciliée) de chaque joueur de ce serveur
local lastRole: { [Player]: Role } = {}
local incoming: { [Player]: { [string]: IncomingInvite } } = {}
local busy: { [Player]: boolean } = {}
local lastInvitesRefresh: { [Player]: number } = {}

local pendingProgress: { [string]: GuildRules.ProgressBatch } = {} -- lot en cours d'accumulation, par guilde
local queuedBatches: { [string]: { QueuedBatch } } = {} -- lots scellés à écrire, par guilde
local flushing: { [string]: boolean } = {}
local lastLevelSeen: { [string]: number } = {}
local nextRefreshAt: { [string]: number } = {}
local rereadScheduled: { [string]: boolean } = {}

local requestLimiter = RateLimiter.new(1, 6) -- toutes actions confondues
local inviteLimiter = RateLimiter.new(0.2, 3) -- invitations : 1 toutes les 5 s en moyenne

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function newOpId(): string
	return (string.gsub(HttpService:GenerateGUID(false), "-", ""))
end

local function actorOf(player: Player): Actor
	return { userId = player.UserId, name = player.Name }
end

local function userKey(player: Player): string
	return GuildRules.userKey(player.UserId)
end

local function okResponse(data: any?): Response
	return { ok = true, data = data }
end

local function failResponse(code: string?): Response
	local errorCode = code or "internal"
	return { ok = false, error = errorCode, message = GuildConfig.errorMessage(errorCode) }
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function notify(player: Player, kind: string, text: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { kind = kind, text = text }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	StateSync.notify(player, "guild", payload)
end

local function roleName(role: Role?): string
	local def = GuildConfig.getRoleDef(role)
	return if def then def.name else ""
end

local function rewardKey(guildId: string, contractId: string, cycleId: string): string
	return `cycle:guild:{guildId}:{contractId}:{cycleId}`
end

-- Joueurs de CE serveur rattachés à la guilde `guildId`.
local function onlineMembers(guildId: string): { Player }
	local result: { Player } = {}
	for player, id in memberGuild do
		if id == guildId and isInGame(player) then
			table.insert(result, player)
		end
	end
	return result
end

local function findPlayerByName(raw: any): Player?
	if type(raw) ~= "string" or #raw == 0 or #raw > 32 then
		return nil
	end
	local wanted = string.lower(raw)
	for _, player in Players:GetPlayers() do
		if string.lower(player.Name) == wanted then
			return player
		end
	end
	local byDisplayName: Player? = nil
	for _, player in Players:GetPlayers() do
		if string.lower(player.DisplayName) == wanted then
			if byDisplayName ~= nil then
				return nil -- nom d'affichage ambigu : on exige le nom d'utilisateur
			end
			byDisplayName = player
		end
	end
	return byDisplayName
end

-- Filtre Roblox d'un texte visible par tous. YIELD. Refus si le filtre échoue ou modifie le texte :
-- on n'enregistre jamais un texte non filtré.
local function filterText(player: Player, text: string): (string?, string?)
	if text == "" then
		return text, nil
	end
	local isFiltered, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not isFiltered or type(result) ~= "string" then
		return nil, "filter_unavailable"
	end
	if result ~= text then
		return nil, "text_filtered"
	end
	return text, nil
end

--------------------------------------------------------------------------------
-- Pointeur du profil et attributs
--------------------------------------------------------------------------------

local function getPointer(player: Player): string?
	local profile = PlayerData.get(player)
	return profile and profile.guild.guildId
end

local function setPointer(player: Player, guildId: string, joinedAt: number)
	PlayerData.mutate(player, "guild", function(profile)
		profile.guild = { guildId = guildId, joinedAt = joinedAt }
	end)
	PlayerData.saveSoon(player)
end

local function clearPointer(player: Player)
	PlayerData.mutate(player, "guild", function(profile)
		profile.guild = { guildId = nil, joinedAt = nil }
	end)
	PlayerData.saveSoon(player)
end

local function setMemberGuild(player: Player, guildId: string?)
	if memberGuild[player] == guildId then
		return
	end
	if guildId then
		memberGuild[player] = guildId
	else
		memberGuild[player] = nil
	end
	if guildId and nextRefreshAt[guildId] == nil then
		nextRefreshAt[guildId] = os.clock() + GuildConfig.REFRESH_INTERVAL
	end
	GuildService.MembershipChanged:Fire(player, guildId)
end

local function currentRecord(player: Player): GuildRecord?
	local guildId = memberGuild[player]
	if guildId == nil then
		return nil
	end
	local record = GuildStore.getCached(guildId)
	if record == nil or record.status ~= "active" or GuildRules.getRole(record, player.UserId) == nil then
		return nil
	end
	return record
end

local function updateAttributes(player: Player)
	if not isInGame(player) then
		return
	end
	local record = currentRecord(player)
	local role: Role? = GuildRules.getRole(record, player.UserId)
	player:SetAttribute(NAME_ATTRIBUTE, if record then record.name else nil)
	player:SetAttribute(ROLE_ATTRIBUTE, role)
end

--------------------------------------------------------------------------------
-- Récompenses des contrats
--------------------------------------------------------------------------------

-- Verse à `player` ses parts de contrats accomplis (s'il y a contribué). Ne yield pas. Retourne le nombre versé.
local function grantRewards(player: Player, record: GuildRecord): number
	if not ProfileStore.isSaveable(player) or record.status ~= "active" then
		return 0
	end
	local granted = 0
	for _, claim in GuildRules.claimableRewards(record, player.UserId, os.time()) do
		local contract = GuildConfig.getContract(claim.contractId)
		if contract == nil then
			continue
		end
		local key = rewardKey(record.id, contract.id, claim.cycle)
		if RewardService.hasClaimed(player, key) then
			continue
		end
		local reward = contract.reward
		local isGranted = RewardService.grant(player, key, {
			xp = reward.xp,
			reputation = reward.reputation,
			items = reward.items,
		}, { reason = contract.name })
		if isGranted then
			granted += 1
			notify(player, "contract_completed", `Contrat de guilde accompli : « {contract.name} ». Votre part vous est remise.`, {
				guildId = record.id,
				contractId = contract.id,
			})
		end
	end
	return granted
end

--------------------------------------------------------------------------------
-- Réconciliation
--------------------------------------------------------------------------------

-- Explique au joueur pourquoi il n'est plus dans la guilde (d'après le journal stocké).
local function notifyRemoval(player: Player, record: GuildRecord?)
	local guildName = if record then record.name else "votre guilde"
	if record and record.status == "dissolved" then
		notify(player, "dissolved", `La guilde « {guildName} » a été dissoute.`)
		return
	end
	if record then
		for index = #record.log, 1, -1 do
			local entry = record.log[index]
			if entry.kind == "kicked" and entry.target == player.UserId then
				notify(player, "kicked", `Vous avez été exclu de la guilde « {guildName} ».`)
				return
			elseif entry.kind == "left" and entry.by == player.UserId then
				notify(player, "left", `Vous avez quitté la guilde « {guildName} ».`)
				return
			end
		end
	end
	notify(player, "removed", `Vous ne faites plus partie de la guilde « {guildName} ».`)
end

-- Prévient le joueur d'un changement de rôle fait ailleurs (promotion, rétrogradation, direction).
local function notifyRoleChange(player: Player, record: GuildRecord)
	local role: Role? = GuildRules.getRole(record, player.UserId)
	local previous = lastRole[player]
	if role == nil then
		lastRole[player] = nil
		return
	end
	lastRole[player] = role
	if previous == nil or previous == role then
		return
	end
	if role == "leader" then
		notify(player, "role", `Vous dirigez désormais la guilde « {record.name} ».`, { role = role })
	elseif role == "officer" then
		notify(player, "role", `Vous êtes désormais officier de la guilde « {record.name} ».`, { role = role })
	else
		notify(player, "role", `Vous êtes désormais membre de la guilde « {record.name} ».`, { role = role })
	end
end

-- Réconcilie le pointeur de `player` avec l'état relu de `guildId` (record nil = n'existe pas).
local function reconcileWith(player: Player, guildId: string, record: GuildRecord?)
	if PlayerData.get(player) == nil then
		return
	end
	local pointer = getPointer(player)
	local decision = GuildRules.reconcilePointer(record, guildId, player.UserId, pointer)
	local member = if record then record.members[userKey(player)] else nil

	if decision == "keep" then
		setMemberGuild(player, guildId)
	elseif decision == "restore" and member then
		setPointer(player, guildId, member.joinedAt)
		setMemberGuild(player, guildId)
		if not busy[player] then
			notify(player, "joined", `Vous êtes membre de la guilde « {(record :: GuildRecord).name} ».`, { guildId = guildId })
		end
	elseif decision == "clear" then
		clearPointer(player)
		if memberGuild[player] == guildId then
			setMemberGuild(player, nil)
		end
		lastRole[player] = nil
		notifyRemoval(player, record)
	elseif decision == "conflict" then
		warn(`[Guild] {player.Name} est listé dans {guildId} alors que son profil pointe vers {pointer} : le pointeur est gardé.`)
	elseif memberGuild[player] == guildId then
		setMemberGuild(player, nil) -- "none" : cette guilde n'est plus la sienne
	end

	if record and memberGuild[player] == guildId then
		notifyRoleChange(player, record)
	end
	updateAttributes(player)
end

--[[
	Applique l'état relu (ou écrit) de la guilde `guildId` à ce serveur : réconciliation des joueurs
	concernés, montée de niveau, parts de contrats, tranches d'état. Ne yield pas.
]]
local function applyGuildRecord(guildId: string, record: GuildRecord?)
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile == nil then
			continue
		end
		local isListed = record ~= nil and record.members[userKey(player)] ~= nil
		if profile.guild.guildId == guildId or memberGuild[player] == guildId or isListed then
			reconcileWith(player, guildId, record)
		end
	end

	local members = onlineMembers(guildId)
	if record and record.status == "active" then
		local previousLevel = lastLevelSeen[guildId]
		lastLevelSeen[guildId] = record.level
		if previousLevel and record.level > previousLevel then
			local levelDef = GuildConfig.getLevelDef(record.level)
			for _, player in members do
				notify(player, "level_up", `La guilde « {record.name} » atteint le niveau {record.level} : {levelDef.name}.`, {
					level = record.level,
					unlocks = levelDef.unlocks,
					comingSoon = levelDef.comingSoon == true,
				})
			end
		end
		for _, player in members do
			grantRewards(player, record)
		end
	end
	for _, player in members do
		StateSync.push(player, "guild")
	end
end

-- Relit la guilde dans le DataStore puis l'applique. YIELD. Retourne (lecture réussie, record).
local function refreshGuild(guildId: string): (boolean, GuildRecord?)
	local isRead, record = GuildStore.read(guildId)
	if isRead then
		applyGuildRecord(guildId, record)
	end
	return isRead, record
end

-- Invitations reçues de `player`, vérifiées dans les enregistrements de guilde. YIELD.
local function rebuildIncoming(player: Player, hints: GuildRules.UserHints)
	local now = os.time()
	local previous = incoming[player] or {}
	local result: { [string]: IncomingInvite } = {}
	local stale: { string } = {}
	for guildId, hint in hints.invites do
		if hint.expiresAt <= now then
			continue
		end
		local record = GuildStore.getCached(guildId)
		local age = GuildStore.getCacheAge(guildId)
		if record == nil or age == nil or age > GuildConfig.REFRESH_INTERVAL then
			local isRead, fresh = GuildStore.read(guildId)
			if not isRead then
				continue -- illisible pour l'instant : on retentera
			end
			record = fresh
		end
		local invite = if record and record.status == "active" then record.invites[userKey(player)] else nil
		if record and invite and invite.expiresAt > now then
			result[guildId] = {
				guildId = guildId,
				guildName = record.name,
				inviterName = invite.byName,
				expiresAt = invite.expiresAt,
			}
		else
			table.insert(stale, guildId)
		end
	end
	if not isInGame(player) then
		return
	end
	incoming[player] = result
	for guildId, invite in result do
		if previous[guildId] == nil then
			notify(player, "invite_received", `{invite.inviterName} vous invite à rejoindre la guilde « {invite.guildName} ».`, {
				guildId = guildId,
			})
		end
	end
	if #stale > 0 then
		task.spawn(function()
			GuildStore.updateUser(player.UserId, function(current)
				local cleaned = current
				for _, guildId in stale do
					cleaned = GuildRules.applyHintRemove(cleaned, guildId, now)
				end
				return cleaned
			end)
		end)
	end
	StateSync.push(player, "guild")
end

--[[
	Relit les indices de `player` : rétablit son pointeur si une guilde le liste alors que son profil
	l'ignore (opération interrompue), puis reconstruit ses invitations reçues. YIELD.
]]
local function refreshHints(player: Player)
	lastInvitesRefresh[player] = os.clock()
	local isRead, hints = GuildStore.readUser(player.UserId)
	if not isRead or hints == nil or not isInGame(player) then
		return
	end
	if getPointer(player) == nil then
		for _, guildId in GuildRules.hintGuildIds(hints) do
			local isGuildRead, record = GuildStore.read(guildId)
			if isGuildRead and record and GuildRules.reconcilePointer(record, guildId, player.UserId, nil) == "restore" then
				applyGuildRecord(guildId, record)
				break
			end
		end
	end
	rebuildIncoming(player, hints)
end

-- Chargement (ou rechargement) du profil : réconciliation complète. YIELD.
local function refreshPlayer(player: Player)
	if PlayerData.get(player) == nil then
		return
	end
	local pointer = getPointer(player)
	if pointer then
		local isRead = refreshGuild(pointer)
		if not isRead and isInGame(player) then
			setMemberGuild(player, pointer) -- guilde illisible pour l'instant : on garde le pointeur
		end
	end
	if isInGame(player) then
		refreshHints(player)
		updateAttributes(player)
		StateSync.push(player, "guild")
	end
end

-- Relance une relecture de la guilde (plusieurs demandes rapprochées n'en font qu'une).
local function scheduleReread(guildId: string)
	if rereadScheduled[guildId] then
		return
	end
	rereadScheduled[guildId] = true
	task.delay(REREAD_DEBOUNCE, function()
		rereadScheduled[guildId] = nil
		refreshGuild(guildId)
	end)
end

--------------------------------------------------------------------------------
-- Progression collective : accumulation et écriture par lots
--------------------------------------------------------------------------------

-- Range le lot en cours de `guildId` dans la file d'écriture, avec un opId définitif.
local function sealBatch(guildId: string)
	local batch = pendingProgress[guildId]
	pendingProgress[guildId] = nil
	if batch == nil or next(batch.contracts) == nil then
		return
	end
	local queue = queuedBatches[guildId]
	if queue == nil then
		queue = {}
		queuedBatches[guildId] = queue
	end
	table.insert(queue, { opId = newOpId(), batch = batch })
	while #queue > GuildConfig.MAX_QUEUED_BATCHES do
		table.remove(queue, 1)
		warn(`[Guild] Trop de lots de contributions en attente pour {guildId} : le plus ancien est abandonné.`)
	end
end

local function addContribution(guildId: string, contractId: string, contributors: { Player }, cycleId: string)
	local batch: GuildRules.ProgressBatch? = pendingProgress[guildId]
	if batch and batch.cycle ~= cycleId then
		sealBatch(guildId) -- changement de cycle : l'ancien lot part tel quel
		batch = nil
	end
	local current: GuildRules.ProgressBatch
	if batch == nil then
		current = { cycle = cycleId, contracts = {} }
		pendingProgress[guildId] = current
	else
		current = batch
	end
	local increment = current.contracts[contractId]
	if increment == nil then
		increment = { progress = 0, contributors = {} }
		current.contracts[contractId] = increment
	end
	local stored = increment :: GuildRules.ContractIncrement
	stored.progress += 1
	for _, player in contributors do
		local key = userKey(player)
		stored.contributors[key] = (stored.contributors[key] or 0) + 1
	end
end

--[[
	Écrit les contributions accumulées pour `guildId`. YIELD. Un seul envoi à la fois par guilde.
	Les lots non écrits (DataStore en panne) restent en file avec leur opId : si l'écriture avait en fait
	abouti, le renvoi est reconnu (record.ops) et n'ajoute rien.
]]
local function flushGuild(guildId: string)
	if flushing[guildId] then
		return
	end
	sealBatch(guildId)
	local queue = queuedBatches[guildId]
	if queue == nil or #queue == 0 then
		queuedBatches[guildId] = nil
		return
	end
	flushing[guildId] = true
	local toSend = table.clone(queue)
	local isWritten, record, errorCode = GuildStore.update(guildId, function(current)
		local result = current
		local now = os.time()
		for _, queued in toSend do
			local nextRecord, code = GuildRules.applyContractProgress(result, nil, queued.batch, now, queued.opId)
			if nextRecord == nil then
				return nil, code
			end
			result = nextRecord
		end
		return result, nil
	end)

	local isTransient = not isWritten and (errorCode == "datastore" or errorCode == "unavailable")
	if not isTransient then
		-- Écrits, ou refus définitif (guilde dissoute, introuvable, illisible) : ces lots sont terminés.
		local remaining = queuedBatches[guildId]
		if remaining then
			for _ = 1, math.min(#toSend, #remaining) do
				table.remove(remaining, 1)
			end
			if #remaining == 0 then
				queuedBatches[guildId] = nil
			end
		end
	end
	flushing[guildId] = nil
	if isWritten then
		applyGuildRecord(guildId, record)
	end
end

local function flushAll()
	local guildIds: { [string]: boolean } = {}
	for guildId in pendingProgress do
		guildIds[guildId] = true
	end
	for guildId in queuedBatches do
		guildIds[guildId] = true
	end
	for guildId in guildIds do
		task.spawn(flushGuild, guildId)
	end
end

-- Regroupe des joueurs par guilde (membres actuels seulement, d'après la copie en mémoire).
local function groupByGuild(players: { any }): { [string]: { Player } }
	local groups: { [string]: { Player } } = {}
	local seen: { [Player]: boolean } = {}
	for _, value in players do
		if typeof(value) ~= "Instance" or not value:IsA("Player") then
			continue
		end
		local player = value :: Player
		if seen[player] then
			continue
		end
		seen[player] = true
		local record = currentRecord(player)
		if record then
			local group = groups[record.id]
			if group == nil then
				group = {}
				groups[record.id] = group
			end
			table.insert(group, player)
		end
	end
	return groups
end

-- Contrats de `record` que l'événement `event` peut faire avancer (niveau suffisant, pas déjà accompli).
-- Les contrats manuels sont accumulés même si le lancement n'est pas encore connu ici : la
-- transformation stockée décide (un contrat non lancé ignore le lot).
local function candidateContracts(record: GuildRecord, event: GuildConfig.ContractEvent, cycleId: string): { Contract }
	local result: { Contract } = {}
	for _, contract in GuildConfig.CONTRACTS do
		if contract.objective.event ~= event or record.level < contract.guildLevel then
			continue
		end
		local entry = record.contracts[contract.id]
		if entry and entry.cycle == cycleId and entry.completedAt ~= nil then
			continue
		end
		table.insert(result, contract)
	end
	return result
end

local function contains(list: { string }?, value: string?): boolean
	if list == nil then
		return true
	end
	if value == nil then
		return false
	end
	return table.find(list, value) ~= nil
end

local function onEnemyDefeated(info: GameEvents.DefeatInfo)
	if type(info) ~= "table" or type(info.eligible) ~= "table" or type(info.enemyId) ~= "string" then
		return
	end
	local region = if typeof(info.position) == "Vector3" then RegionConfig.regionAt(info.position) else nil
	local regionId = region and region.id
	local cycleId = GuildConfig.getCycle(os.time()).id
	for guildId, members in groupByGuild(info.eligible) do
		local record = GuildStore.getCached(guildId)
		if record == nil then
			continue
		end
		for _, contract in candidateContracts(record, "EnemyDefeated", cycleId) do
			local objective = contract.objective
			local isMatch = contains(objective.enemyIds, info.enemyId)
				and contains(objective.regions, regionId)
				and (not objective.bossOnly or info.isBoss == true)
				and #members >= (objective.minEligibleMembers or 1)
			if isMatch then
				addContribution(guildId, contract.id, members, cycleId)
			end
		end
	end
end

-- Événement d'un seul joueur (découverte, mission) : +1 pour sa guilde.
local function onPlayerEvent(event: GuildConfig.ContractEvent, player: any, detail: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local record = currentRecord(player)
	if record == nil then
		return
	end
	local cycleId = GuildConfig.getCycle(os.time()).id
	for _, contract in candidateContracts(record, event, cycleId) do
		if event ~= "MissionCompleted" or contains(contract.objective.missionIds, if type(detail) == "string" then detail else nil) then
			addContribution(record.id, contract.id, { player }, cycleId)
		end
	end
end

local function onAnomalyResolved(info: GameEvents.AnomalyInfo)
	if type(info) ~= "table" or type(info.participants) ~= "table" then
		return
	end
	local players: { any } = table.clone(info.participants)
	if info.rewoundBy then
		table.insert(players, info.rewoundBy)
	end
	local cycleId = GuildConfig.getCycle(os.time()).id
	for guildId, members in groupByGuild(players) do
		local record = GuildStore.getCached(guildId)
		if record == nil then
			continue
		end
		for _, contract in candidateContracts(record, "AnomalyResolved", cycleId) do
			if contract.objective.outcome == nil or contract.objective.outcome == info.outcome then
				addContribution(guildId, contract.id, members, cycleId)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Tranche d'état "guild"
--------------------------------------------------------------------------------

local function describeReward(reward: GuildConfig.ContractReward): { [string]: any }
	local items = {}
	if reward.items then
		for itemId, count in reward.items do
			local item = ItemConfig.getItem(itemId)
			table.insert(items, { id = itemId, name = if item then item.name else itemId, count = count })
		end
		table.sort(items, function(a, b)
			return a.id < b.id
		end)
	end
	return { xp = reward.xp or 0, reputation = reward.reputation or 0, items = items }
end

local function logText(entry: GuildRules.LogEntry): string
	local by = entry.byName or "?"
	local target = entry.targetName or "?"
	local kind = entry.kind
	if kind == "created" then
		return `{by} a fondé la guilde.`
	elseif kind == "invited" then
		return `{by} a invité {target}.`
	elseif kind == "invite_cancelled" then
		return `{by} a annulé l'invitation de {target}.`
	elseif kind == "joined" then
		return `{by} a rejoint la guilde.`
	elseif kind == "declined" then
		return `{by} a décliné l'invitation.`
	elseif kind == "left" then
		return `{by} a quitté la guilde.`
	elseif kind == "kicked" then
		return `{by} a exclu {target}.`
	elseif kind == "promoted" then
		return `{by} a nommé {target} officier.`
	elseif kind == "demoted" then
		return `{by} a retiré à {target} son titre d'officier.`
	elseif kind == "leader_changed" then
		return `{by} a transmis la direction à {target}.`
	elseif kind == "description" then
		return `{by} a modifié la description.`
	elseif kind == "dissolved" then
		return `{by} a dissous la guilde.`
	elseif kind == "contract_started" or kind == "contract_completed" then
		local contract = GuildConfig.getContract(entry.detail)
		local name = if contract then contract.name else (entry.detail or "?")
		return if kind == "contract_started" then `{by} a lancé le contrat « {name} ».` else `Contrat accompli : « {name} ».`
	elseif kind == "level_up" then
		return `La guilde atteint le niveau {entry.detail or "?"}.`
	end
	return kind
end

local function describeGuild(record: GuildRecord, player: Player, now: number, cycle: GuildConfig.CycleInfo): { [string]: any }
	local myKey = userKey(player)
	local myRole: Role? = GuildRules.getRole(record, player.UserId)
	local permissions = GuildRules.allowedActions(record, player.UserId)

	local members = {}
	for key, member in record.members do
		local userId = tonumber(key) or 0
		local isYou = key == myKey
		table.insert(members, {
			userId = userId,
			name = member.name,
			role = member.role,
			roleName = roleName(member.role),
			joinedAt = member.joinedAt,
			online = Players:GetPlayerByUserId(userId) ~= nil, -- connecté sur CE serveur
			isYou = isYou,
			canKick = not isYou and GuildRules.can(myRole, "kick", member.role),
			canPromote = not isYou and GuildRules.can(myRole, "promote", member.role),
			canDemote = not isYou and GuildRules.can(myRole, "demote", member.role),
			canTransfer = not isYou and GuildRules.can(myRole, "transferLeadership", member.role),
		})
	end
	table.sort(members, function(a, b)
		local orderA = (GuildConfig.getRoleDef(a.role) :: GuildConfig.RoleDef).order
		local orderB = (GuildConfig.getRoleDef(b.role) :: GuildConfig.RoleDef).order
		if orderA ~= orderB then
			return orderA > orderB
		end
		return string.lower(a.name) < string.lower(b.name)
	end)

	local invites = {}
	for key, invite in record.invites do
		if invite.expiresAt > now then
			table.insert(invites, {
				userId = tonumber(key) or 0,
				name = invite.name,
				byName = invite.byName,
				expiresAt = invite.expiresAt,
			})
		end
	end
	table.sort(invites, function(a, b)
		return a.expiresAt < b.expiresAt
	end)

	local contracts = {}
	for _, contract in GuildConfig.CONTRACTS do
		local entry = record.contracts[contract.id]
		local isCurrent = entry ~= nil and entry.cycle == cycle.id
		local contributorCount = 0
		if entry and isCurrent then
			for _ in entry.contributors do
				contributorCount += 1
			end
		end
		local isUnlocked = record.level >= contract.guildLevel
		local isStarted = contract.activation == "manual" and isCurrent and (entry :: GuildRules.ContractEntry).startedAt ~= nil
		table.insert(contracts, {
			id = contract.id,
			name = contract.name,
			description = contract.description,
			guildLevel = contract.guildLevel,
			activation = contract.activation,
			unlocked = isUnlocked,
			active = GuildRules.isContractActive(record, contract, cycle.id),
			started = isStarted,
			canStart = contract.activation == "manual" and isUnlocked and not isStarted and permissions.startContract == true,
			progress = if entry and isCurrent then entry.progress else 0,
			target = contract.target,
			completed = entry ~= nil and isCurrent and entry.completedAt ~= nil,
			completedAt = if entry and isCurrent then entry.completedAt else nil,
			myContribution = if entry and isCurrent then entry.contributors[myKey] or 0 else 0,
			contributorCount = contributorCount,
			guildXp = contract.guildXp,
			reward = describeReward(contract.reward),
			rewardClaimed = RewardService.hasClaimed(player, rewardKey(record.id, contract.id, cycle.id)),
		})
	end

	local unlocks = {}
	for _, levelDef in GuildConfig.LEVELS do
		for _, unlockId in levelDef.unlocks do
			local def = GuildConfig.getUnlock(unlockId)
			if def then
				table.insert(unlocks, {
					id = def.id,
					name = def.name,
					description = def.description,
					level = def.level,
					unlocked = record.level >= def.level,
					comingSoon = def.comingSoon == true,
				})
			end
		end
	end

	local log = {}
	for index = #record.log, 1, -1 do
		local entry = record.log[index]
		table.insert(log, { t = entry.t, kind = entry.kind, text = logText(entry) })
	end

	local levelDef = GuildConfig.getLevelDef(record.level)
	local claimable = 0
	for _, claim in GuildRules.claimableRewards(record, player.UserId, now) do
		if not RewardService.hasClaimed(player, rewardKey(record.id, claim.contractId, claim.cycle)) then
			claimable += 1
		end
	end

	return {
		id = record.id,
		name = record.name,
		description = record.description,
		createdAt = record.createdAt,
		leaderId = record.leaderId,
		level = record.level,
		levelName = levelDef.name,
		levelComingSoon = levelDef.comingSoon == true,
		maxLevel = #GuildConfig.LEVELS,
		xp = record.xp,
		levelXp = levelDef.xp,
		nextLevelXp = GuildConfig.nextLevelXp(record.level),
		memberCount = GuildRules.countMembers(record),
		maxMembers = GuildConfig.MAX_MEMBERS,
		officerCount = GuildRules.countOfficers(record),
		maxOfficers = GuildConfig.MAX_OFFICERS,
		myRole = myRole,
		myRoleName = roleName(myRole),
		permissions = permissions,
		members = members,
		invites = invites,
		contracts = contracts,
		claimableRewards = claimable,
		unlocks = unlocks,
		log = log,
	}
end

local function listIncoming(player: Player): { IncomingInvite }
	local now = os.time()
	local list: { IncomingInvite } = {}
	local invites: { [string]: IncomingInvite } = incoming[player] or {}
	for _, invite in invites do
		if invite.expiresAt > now then
			table.insert(list, invite)
		end
	end
	table.sort(list, function(a, b)
		return a.expiresAt < b.expiresAt
	end)
	return list
end

local function buildGuildState(player: Player): any
	local now = os.time()
	local cycle = GuildConfig.getCycle(now)
	local record = currentRecord(player)
	return {
		loaded = PlayerData.get(player) ~= nil,
		saveable = ProfileStore.isSaveable(player),
		available = GuildStore.isAvailable(),
		inGuild = record ~= nil,
		pending = record == nil and memberGuild[player] ~= nil, -- guilde connue mais pas encore lue
		guild = if record then describeGuild(record, player, now, cycle) else nil,
		incomingInvites = listIncoming(player),
		cycle = { id = cycle.id, startsAt = cycle.startsAt, endsAt = cycle.endsAt },
		limits = {
			nameMin = GuildConfig.NAME_MIN_LENGTH,
			nameMax = GuildConfig.NAME_MAX_LENGTH,
			descriptionMax = GuildConfig.DESCRIPTION_MAX_LENGTH,
			maxMembers = GuildConfig.MAX_MEMBERS,
			maxOfficers = GuildConfig.MAX_OFFICERS,
			inviteDuration = GuildConfig.INVITE_DURATION,
		},
	}
end

--------------------------------------------------------------------------------
-- Opérations (appelées par les actions Remote)
--------------------------------------------------------------------------------

-- Guilde du joueur, relue si la copie en mémoire a plus de `maxAge` secondes. YIELD.
local function requireMembership(player: Player, maxAge: number?): (string?, GuildRecord?, string?)
	local guildId = memberGuild[player] or getPointer(player)
	if guildId == nil then
		return nil, nil, "not_in_guild"
	end
	local age = GuildStore.getCacheAge(guildId)
	if age == nil or (maxAge ~= nil and age > maxAge) then
		local isRead = refreshGuild(guildId)
		if not isRead and GuildStore.getCached(guildId) == nil then
			return nil, nil, "datastore"
		end
	end
	local record = currentRecord(player)
	if record == nil then
		return nil, nil, "not_in_guild"
	end
	return guildId, record, nil
end

-- Le joueur n'appartient-il à aucune guilde (pointeur réconcilié sur une relecture) ? YIELD.
local function ensureNoGuild(player: Player): string?
	local pointer = getPointer(player)
	if pointer == nil then
		return nil
	end
	local isRead = refreshGuild(pointer)
	if not isRead then
		return "datastore"
	end
	return if getPointer(player) ~= nil then "already_in_guild" else nil
end

type GuildTransform = (current: GuildRecord?, actor: Actor, now: number, opId: string) -> (GuildRecord?, string?)

--[[
	Opération d'un membre sur SA guilde : écriture (UpdateAsync + règles), message aux autres serveurs,
	application locale. YIELD. Retourne (record écrit, opId) ou (nil, nil, erreur).
]]
local function runMemberOp(player: Player, kind: string, transform: GuildTransform, targetUserId: number?): (GuildRecord?, string?, string?)
	local guildId, _, membershipError = requireMembership(player, nil)
	if guildId == nil then
		return nil, nil, membershipError
	end
	local opId = newOpId()
	local now = os.time()
	local actor = actorOf(player)
	local isWritten, record, errorCode = GuildStore.update(guildId, function(current)
		return transform(current, actor, now, opId)
	end)
	if not isWritten or record == nil then
		if errorCode == "guild_dissolved" or errorCode == "not_member" or errorCode == "guild_not_found" then
			refreshGuild(guildId) -- notre copie était périmée : on réconcilie
		end
		return nil, nil, errorCode
	end
	GuildMessaging.publish({ guildId = guildId, kind = kind, opId = opId, targetUserId = targetUserId })
	applyGuildRecord(guildId, record)
	return record, opId, nil
end

local function readTargetId(params: Params): number?
	local targetId = params.targetUserId
	return if GuildRules.isUserId(targetId) then targetId else nil
end

--------------------------------------------------------------------------------
-- Actions Remote
--------------------------------------------------------------------------------

local function handleCreate(player: Player, params: Params): Response
	local name, nameError = GuildRules.validateName(params.name)
	if name == nil then
		return failResponse(nameError)
	end
	local description, descriptionError = GuildRules.validateDescription(params.description)
	if description == nil then
		return failResponse(descriptionError)
	end
	if not GuildStore.isAvailable() then
		return failResponse("unavailable")
	end
	local guildError = ensureNoGuild(player)
	if guildError then
		return failResponse(guildError)
	end
	local _, nameFilterError = filterText(player, name)
	if nameFilterError then
		return failResponse(nameFilterError)
	end
	local _, descriptionFilterError = filterText(player, description)
	if descriptionFilterError then
		return failResponse(descriptionFilterError)
	end

	local guildId = "G_" .. newOpId()
	local opId = newOpId()
	local now = os.time()
	local nameKey = GuildRules.normalizeName(name)
	local actor = actorOf(player)

	-- 1. Réservation du nom.
	local isReserved, reserveError = GuildStore.reserveName(nameKey, guildId, now)
	if not isReserved then
		return failResponse(reserveError)
	end
	-- 2. Indice « création en cours » : permet de retrouver la guilde si la suite est interrompue.
	local isHinted = GuildStore.updateUser(player.UserId, function(hints)
		return GuildRules.applyHintPending(hints, guildId, now)
	end)
	if not isHinted then
		GuildStore.releaseName(nameKey, guildId, now)
		return failResponse("datastore")
	end
	-- 3. Enregistrement de la guilde.
	local isCreated, record, createError = GuildStore.update(guildId, function(current)
		return GuildRules.createRecord(current, actor, { guildId = guildId, name = name, description = description }, now, opId)
	end)
	if not isCreated and createError == "datastore" then
		-- Issue inconnue (réponse perdue ?) : on relit avant de conclure.
		local isRead, existing = GuildStore.read(guildId)
		if not isRead then
			return failResponse("datastore") -- nom et indice gardés : la réconciliation tranchera
		end
		if existing and existing.ops[opId] then
			isCreated, record = true, existing
		end
	end
	if not isCreated or record == nil then
		GuildStore.releaseName(nameKey, guildId, now)
		GuildStore.updateUser(player.UserId, function(hints)
			return GuildRules.applyHintRemove(hints, guildId, now)
		end)
		return failResponse(createError)
	end
	-- 4. Pointeur du profil, 5. confirmation du nom, 6. indice retiré.
	setPointer(player, guildId, now)
	GuildStore.confirmName(nameKey, guildId)
	GuildStore.updateUser(player.UserId, function(hints)
		return GuildRules.applyHintRemove(hints, guildId, now)
	end)
	applyGuildRecord(guildId, record)
	notify(player, "created", `La guilde « {record.name} » est fondée. Vous en êtes le chef.`, { guildId = guildId })
	return okResponse(buildGuildState(player))
end

local function handleInvite(player: Player, params: Params): Response
	if not inviteLimiter:allow(player) then
		return failResponse("rate_limited")
	end
	local guildId, record, membershipError = requireMembership(player, GuildConfig.INFO_REFRESH_MIN_AGE)
	if guildId == nil or record == nil then
		return failResponse(membershipError)
	end
	if not GuildRules.can(GuildRules.getRole(record, player.UserId), "invite") then
		return failResponse("no_permission")
	end

	-- Cible : un joueur de ce serveur (par nom) ou n'importe quel UserId.
	local targetId: number? = nil
	local targetName: string? = nil
	if params.targetName ~= nil then
		local target = findPlayerByName(params.targetName)
		if target == nil then
			return failResponse("unknown_player")
		end
		targetId, targetName = target.UserId, target.Name
	else
		targetId = readTargetId(params)
		if targetId == nil then
			return failResponse("bad_params")
		end
		local online = Players:GetPlayerByUserId(targetId)
		if online then
			targetName = online.Name
		else
			local isFound, nameOrError = pcall(function()
				return Players:GetNameFromUserIdAsync(targetId :: number)
			end)
			if not isFound or type(nameOrError) ~= "string" then
				return failResponse("unknown_player")
			end
			targetName = nameOrError
		end
	end
	local finalTargetId = targetId :: number
	if finalTargetId == player.UserId then
		return failResponse("target_is_self")
	end
	local targetPlayer = Players:GetPlayerByUserId(finalTargetId)
	if targetPlayer and getPointer(targetPlayer) ~= nil then
		return failResponse("target_in_guild")
	end

	local written, _, inviteError = runMemberOp(player, "invite", function(current, actor, now, opId)
		return GuildRules.applyInvite(current, actor, { targetId = finalTargetId, targetName = targetName }, now, opId)
	end, finalTargetId)
	if written == nil then
		return failResponse(inviteError)
	end
	local invite = written.invites[GuildRules.userKey(finalTargetId)]
	if invite then
		-- Indice chez l'invité (meilleur effort : la vérité est l'invitation dans la guilde).
		GuildStore.updateUser(finalTargetId, function(hints)
			return GuildRules.applyHintInvite(hints, written.id, {
				expiresAt = invite.expiresAt,
				guildName = written.name,
				byName = player.Name,
			}, os.time())
		end)
	end
	if targetPlayer then
		task.spawn(refreshHints, targetPlayer)
	end
	return okResponse({ targetUserId = finalTargetId, targetName = targetName })
end

local function handleCancelInvite(player: Player, params: Params): Response
	local targetId = readTargetId(params)
	if targetId == nil then
		return failResponse("bad_params")
	end
	local written, _, cancelError = runMemberOp(player, "invite_cancelled", function(current, actor, now, opId)
		return GuildRules.applyCancelInvite(current, actor, { targetId = targetId }, now, opId)
	end, targetId)
	if written == nil then
		return failResponse(cancelError)
	end
	GuildStore.updateUser(targetId, function(hints)
		return GuildRules.applyHintRemove(hints, written.id, os.time())
	end)
	local targetPlayer = Players:GetPlayerByUserId(targetId)
	if targetPlayer then
		task.spawn(refreshHints, targetPlayer)
	end
	return okResponse({})
end

local function forgetInvite(player: Player, guildId: string)
	local invites = incoming[player]
	if invites then
		invites[guildId] = nil
	end
	GuildStore.updateUser(player.UserId, function(hints)
		return GuildRules.applyHintRemove(hints, guildId, os.time())
	end)
	StateSync.push(player, "guild")
end

local function handleAcceptInvite(player: Player, params: Params): Response
	local guildId = params.guildId
	if not GuildRules.isGuildId(guildId) then
		return failResponse("bad_params")
	end
	local guildError = ensureNoGuild(player)
	if guildError then
		return failResponse(guildError)
	end
	local opId = newOpId()
	local now = os.time()
	local actor = actorOf(player)
	local isWritten, record, acceptError = GuildStore.update(guildId, function(current)
		return GuildRules.applyAcceptInvite(current, actor, nil, now, opId)
	end)
	if not isWritten or record == nil then
		if acceptError ~= "datastore" and acceptError ~= "unavailable" then
			forgetInvite(player, guildId) -- invitation périmée, guilde dissoute ou introuvable
		end
		return failResponse(acceptError)
	end
	local member = record.members[userKey(player)]
	setPointer(player, guildId, if member then member.joinedAt else now)
	forgetInvite(player, guildId)
	GuildMessaging.publish({ guildId = guildId, kind = "joined", opId = opId, targetUserId = player.UserId })
	applyGuildRecord(guildId, record)
	notify(player, "joined", `Vous avez rejoint la guilde « {record.name} ».`, { guildId = guildId })
	return okResponse(buildGuildState(player))
end

local function handleDeclineInvite(player: Player, params: Params): Response
	local guildId = params.guildId
	if not GuildRules.isGuildId(guildId) then
		return failResponse("bad_params")
	end
	local opId = newOpId()
	local now = os.time()
	local actor = actorOf(player)
	local isWritten, _, declineError = GuildStore.update(guildId, function(current)
		return GuildRules.applyDeclineInvite(current, actor, nil, now, opId)
	end)
	if not isWritten and (declineError == "datastore" or declineError == "unavailable") then
		return failResponse(declineError)
	end
	forgetInvite(player, guildId)
	if isWritten then
		GuildMessaging.publish({ guildId = guildId, kind = "declined", opId = opId, targetUserId = player.UserId })
	end
	return okResponse({})
end

local function handleLeave(player: Player, _params: Params): Response
	local written, _, leaveError = runMemberOp(player, "left", function(current, actor, now, opId)
		return GuildRules.applyLeave(current, actor, nil, now, opId)
	end, player.UserId)
	return if written then okResponse({}) else failResponse(leaveError)
end

-- Fabrique des actions qui visent un membre (exclure, promouvoir, rétrograder, transférer).
local function targetedAction(kind: string, apply: (GuildRecord?, Actor, GuildRules.TargetParams, number, string) -> (GuildRecord?, string?)): (Player, Params) -> Response
	return function(player: Player, params: Params): Response
		local targetId = readTargetId(params)
		if targetId == nil then
			return failResponse("bad_params")
		end
		local written, _, actionError = runMemberOp(player, kind, function(current, actor, now, opId)
			return apply(current, actor, { targetId = targetId }, now, opId)
		end, targetId)
		return if written then okResponse({}) else failResponse(actionError)
	end
end

local function handleSetDescription(player: Player, params: Params): Response
	local description, descriptionError = GuildRules.validateDescription(params.description)
	if description == nil then
		return failResponse(descriptionError)
	end
	local _, _, membershipError = requireMembership(player, nil)
	if membershipError then
		return failResponse(membershipError)
	end
	local _, filterError = filterText(player, description)
	if filterError then
		return failResponse(filterError)
	end
	local written, _, writeError = runMemberOp(player, "description", function(current, actor, now, opId)
		return GuildRules.applySetDescription(current, actor, { description = description }, now, opId)
	end, nil)
	return if written then okResponse({}) else failResponse(writeError)
end

local function handleDissolve(player: Player, params: Params): Response
	if type(params.confirmName) ~= "string" then
		return failResponse("dissolve_name_mismatch")
	end
	local confirmName: string = params.confirmName
	local written, _, dissolveError = runMemberOp(player, "dissolved", function(current, actor, now, opId)
		return GuildRules.applyDissolve(current, actor, { confirmName = confirmName }, now, opId)
	end, nil)
	if written == nil then
		return failResponse(dissolveError)
	end
	-- Pierre tombale écrite : le nom redevient libre (le pointeur a été effacé par la réconciliation).
	GuildStore.releaseName(written.nameKey, written.id, os.time())
	return okResponse({})
end

local function handleStartContract(player: Player, params: Params): Response
	local contract = GuildConfig.getContract(params.contractId)
	if contract == nil then
		return failResponse("contract_unknown")
	end
	local contractId = contract.id
	local written, _, startError = runMemberOp(player, "contracts", function(current, actor, now, opId)
		return GuildRules.applyStartContract(current, actor, { contractId = contractId }, now, opId)
	end, nil)
	if written == nil then
		return failResponse(startError)
	end
	for _, member in onlineMembers(written.id) do
		notify(member, "contract_started", `Contrat de guilde lancé : « {contract.name} ».`, { contractId = contractId })
	end
	return okResponse({})
end

local function handleGetInfo(player: Player, _params: Params): Response
	local guildId = memberGuild[player]
	if guildId then
		local age = GuildStore.getCacheAge(guildId)
		if age == nil or age > GuildConfig.INFO_REFRESH_MIN_AGE then
			refreshGuild(guildId)
		end
	end
	return okResponse(buildGuildState(player))
end

local function handleListInvites(player: Player, _params: Params): Response
	local last = lastInvitesRefresh[player]
	if last == nil or os.clock() - last >= LIST_INVITES_MIN_INTERVAL then
		refreshHints(player)
	end
	return okResponse(listIncoming(player))
end

local function handleClaimContractReward(player: Player, _params: Params): Response
	local guildId, record, membershipError = requireMembership(player, GuildConfig.INFO_REFRESH_MIN_AGE)
	if guildId == nil or record == nil then
		return failResponse(membershipError)
	end
	local granted = grantRewards(player, record)
	StateSync.push(player, "guild")
	if granted == 0 then
		return failResponse("nothing_to_claim")
	end
	return okResponse({ granted = granted })
end

-- Liste blanche des actions.
local ACTIONS: { [string]: ActionSpec } = {
	getInfo = { writes = false, handler = handleGetInfo },
	listInvites = { writes = false, handler = handleListInvites },
	create = { writes = true, handler = handleCreate },
	invite = { writes = true, handler = handleInvite },
	cancelInvite = { writes = true, handler = handleCancelInvite },
	acceptInvite = { writes = true, handler = handleAcceptInvite },
	declineInvite = { writes = true, handler = handleDeclineInvite },
	leave = { writes = true, handler = handleLeave },
	kick = { writes = true, handler = targetedAction("kicked", GuildRules.applyKick) },
	promote = { writes = true, handler = targetedAction("roles", GuildRules.applyPromote) },
	demote = { writes = true, handler = targetedAction("roles", GuildRules.applyDemote) },
	transfer = { writes = true, handler = targetedAction("roles", GuildRules.applyTransfer) },
	setDescription = { writes = true, handler = handleSetDescription },
	dissolve = { writes = true, handler = handleDissolve },
	startContract = { writes = true, handler = handleStartContract },
	claimContractReward = { writes = true, handler = handleClaimContractReward },
}

local function handleRequest(player: Player, action: any, params: any): Response
	if type(action) ~= "string" or ACTIONS[action] == nil then
		return failResponse("unknown_action")
	end
	if not requestLimiter:allow(player) then
		return failResponse("rate_limited")
	end
	if params ~= nil and type(params) ~= "table" then
		return failResponse("bad_params")
	end
	if PlayerData.get(player) == nil then
		return failResponse("not_loaded")
	end
	local spec = ACTIONS[action]
	if spec.writes and not ProfileStore.isSaveable(player) then
		return failResponse("not_saveable")
	end
	if busy[player] then
		return failResponse("busy")
	end
	busy[player] = true
	local isHandled, response = pcall(spec.handler, player, params or {})
	busy[player] = nil
	if not isHandled then
		warn(`[Guild] Action "{action}" de {player.Name} en erreur : {response}`)
		return failResponse("internal")
	end
	StateSync.push(player, "guild")
	return response
end

--------------------------------------------------------------------------------
-- API serveur
--------------------------------------------------------------------------------

-- Identifiant de la guilde de `player` (nil hors guilde ou guilde pas encore lue).
function GuildService.getGuildId(player: Player): string?
	local record = currentRecord(player)
	return record and record.id
end

-- Niveau de la guilde de `player` (nil hors guilde).
function GuildService.getGuildLevel(player: Player): number?
	local record = currentRecord(player)
	return record and record.level
end

function GuildService.isMemberOf(player: Player, guildId: string): boolean
	local record = currentRecord(player)
	return record ~= nil and record.id == guildId
end

-- true si la guilde de `player` a le déblocage `unlockId` (GuildConfig.UNLOCKS, ex. "guild_archive").
function GuildService.hasGuildUnlock(player: Player, unlockId: string): boolean
	local record = currentRecord(player)
	local def = GuildConfig.getUnlock(unlockId)
	if record == nil or def == nil then
		return false
	end
	return record.level >= def.level or record.unlocks[unlockId] ~= nil
end

-- Rôle de `player` dans sa guilde (nil hors guilde).
function GuildService.getRole(player: Player): Role?
	return GuildRules.getRole(currentRecord(player), player.UserId)
end

--------------------------------------------------------------------------------
-- Démarrage
--------------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	local guildId = memberGuild[player]
	memberGuild[player] = nil
	lastRole[player] = nil
	incoming[player] = nil
	busy[player] = nil
	lastInvitesRefresh[player] = nil
	if guildId == nil then
		return
	end
	task.spawn(function()
		flushGuild(guildId) -- ses contributions partent avec lui
		if #onlineMembers(guildId) == 0 and pendingProgress[guildId] == nil and queuedBatches[guildId] == nil then
			nextRefreshAt[guildId] = nil
			lastLevelSeen[guildId] = nil
		end
	end)
end

local function onMessage(message: GuildMessaging.Message)
	local isConcerned = #onlineMembers(message.guildId) > 0
	local target = if message.targetUserId then Players:GetPlayerByUserId(message.targetUserId) else nil
	if isConcerned or (target and getPointer(target) == message.guildId) then
		scheduleReread(message.guildId)
	end
	if target and (message.kind == "invite" or message.kind == "invite_cancelled") then
		task.spawn(refreshHints, target)
	end
end

-- Boucle d'entretien : relectures périodiques, écritures par lots, invitations.
local function maintenanceLoop()
	local nextFlushAt = os.clock() + GuildConfig.FLUSH_INTERVAL
	while not isClosing do
		task.wait(1)
		local now = os.clock()

		local activeGuilds: { [string]: boolean } = {}
		for _, guildId in memberGuild do
			activeGuilds[guildId] = true
		end
		for guildId in activeGuilds do
			local dueAt = nextRefreshAt[guildId]
			if dueAt == nil or now >= dueAt then
				nextRefreshAt[guildId] = now + GuildConfig.REFRESH_INTERVAL * (0.9 + math.random() * 0.2)
				task.spawn(refreshGuild, guildId)
			end
		end

		if now >= nextFlushAt then
			nextFlushAt = now + GuildConfig.FLUSH_INTERVAL
			flushAll()
		end

		for _, player in Players:GetPlayers() do
			local last = lastInvitesRefresh[player]
			if memberGuild[player] == nil and PlayerData.get(player) ~= nil and last ~= nil
				and now - last >= GuildConfig.INVITES_REFRESH_INTERVAL then
				task.spawn(refreshHints, player)
			end
		end
	end
end

-- À appeler une seule fois au démarrage du serveur (après ProfileStore, StateSync et RewardService).
function GuildService.start()
	if isStarted then
		return
	end
	isStarted = true

	StateSync.register("guild", buildGuildState)
	Remotes.GuildRequest.OnServerInvoke = handleRequest

	GuildMessaging.start()
	GuildMessaging.Received:Connect(onMessage)

	GameEvents.EnemyDefeated:Connect(onEnemyDefeated)
	GameEvents.Discovered:Connect(function(player: any, discoveryId: any)
		onPlayerEvent("Discovered", player, discoveryId)
	end)
	GameEvents.MissionCompleted:Connect(function(player: any, missionId: any)
		onPlayerEvent("MissionCompleted", player, missionId)
	end)
	GameEvents.AnomalyResolved:Connect(onAnomalyResolved)

	ProfileStore.ProfileLoaded:Connect(function(player: Player)
		refreshPlayer(player)
	end)
	ProfileStore.ProfileRefreshed:Connect(function(player: Player)
		refreshPlayer(player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Profils chargés avant le démarrage du service.
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) ~= nil then
			task.spawn(refreshPlayer, player)
		end
	end

	task.spawn(maintenanceLoop)

	-- Fermeture : les contributions accumulées sont écrites avant l'arrêt.
	game:BindToClose(function()
		isClosing = true
		flushAll()
		local deadline = os.clock() + CLOSE_FLUSH_TIMEOUT
		while os.clock() < deadline do
			local isBusy = next(flushing) ~= nil or next(pendingProgress) ~= nil
			if not isBusy then
				break
			end
			task.wait(0.2)
		end
	end)
end

return GuildService
