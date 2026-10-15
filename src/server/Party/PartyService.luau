--!strict
--[[
	PartyService
	Groupes de joueurs sur un MÊME serveur (singleton serveur). Règles dans Shared/Party/PartyConfig.

	Architecture : la logique (règles, Remotes, état client) est séparée du STOCKAGE des groupes,
	décrit par le type PartyBackend. L'implémentation actuelle (MemoryBackend) garde tout en mémoire,
	sur ce serveur. Une future version multiserveur (expéditions) pourra fournir un autre PartyBackend
	(MemoryStore + MessagingService) sans changer les règles ni l'API ; elle n'est PAS faite ici.

	Côté client : RemoteFunction PartyRequest (voir PartyRemotes), tranche StateSync "party",
	attribut répliqué "PartyId" sur le Player.

	API serveur pour les autres systèmes (sans yield) :
		PartyService.getParty(player) -> { id, leader, members }?   (copie)
		PartyService.getMembers(player): { Player }                 (membres du groupe, lui compris ;
		                                                             { player } s'il est seul)
		PartyService.areInSameParty(a, b): boolean
		PartyService.Changed(partyId)                               (Signal : composition ou chef modifiés,
		                                                             ou groupe dissous)

	Récompenses partagées : PartyService étend l'éligibilité des éliminations (DamageService.
	setEligibilityExtender) aux membres vivants à moins de SHARE_RANGE studs d'un joueur éligible.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyConfig = require(ReplicatedStorage.Shared.Party.PartyConfig)
local Remotes = require(ReplicatedStorage.Shared.Party.PartyRemotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DamageService = require(script.Parent.Parent.Combat.DamageService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local StateSync = require(script.Parent.Parent.State.StateSync)

export type PartyInfo = {
	id: string,
	leader: Player,
	members: { Player },
}

export type Response = {
	ok: boolean,
	error: string?,
	message: string?,
	data: any?,
}

-- Enregistrement d'un groupe dans le stockage. `members` est dans l'ordre d'arrivée (le premier
-- est le plus ancien : il hérite de la direction).
export type PartyRecord = {
	id: string,
	leader: Player,
	members: { Player },
	createdAt: number,
}

export type PartyInvite = {
	partyId: string,
	from: Player,
	target: Player,
	expiresAt: number, -- os.time()
}

--[[
	Interface du stockage des groupes. Toutes les fonctions sont synchrones dans l'implémentation en
	mémoire ; une implémentation multiserveur devra garder les mêmes garanties vues de PartyService.
]]
export type PartyBackend = {
	create: (leader: Player, now: number) -> PartyRecord,
	get: (partyId: string) -> PartyRecord?,
	getPartyIdOf: (player: Player) -> string?,
	addMember: (partyId: string, player: Player) -> boolean,
	removeMember: (partyId: string, player: Player) -> (),
	setLeader: (partyId: string, player: Player) -> (),
	dissolve: (partyId: string) -> { Player }, -- retourne les membres qu'il avait
	addInvite: (invite: PartyInvite) -> (),
	removeInvite: (partyId: string, target: Player) -> (),
	getInvite: (partyId: string, target: Player) -> PartyInvite?,
	invitesFor: (target: Player) -> { PartyInvite },
	invitesOf: (partyId: string) -> { PartyInvite },
	allInvites: () -> { PartyInvite },
}

type Params = { [string]: any }

local PARTY_ATTRIBUTE = "PartyId"

--------------------------------------------------------------------------------
-- Implémentation en mémoire du stockage (un seul serveur)
--------------------------------------------------------------------------------

local function newMemoryBackend(): PartyBackend
	local parties: { [string]: PartyRecord } = {}
	local partyOf: { [Player]: string } = {}
	local invites: { [string]: { [Player]: PartyInvite } } = {} -- [partyId][cible]

	local backend: PartyBackend
	backend = {
		create = function(leader: Player, now: number): PartyRecord
			local record: PartyRecord = {
				id = "P_" .. string.gsub(HttpService:GenerateGUID(false), "-", ""),
				leader = leader,
				members = { leader },
				createdAt = now,
			}
			parties[record.id] = record
			partyOf[leader] = record.id
			return record
		end,
		get = function(partyId: string): PartyRecord?
			return parties[partyId]
		end,
		getPartyIdOf = function(player: Player): string?
			return partyOf[player]
		end,
		addMember = function(partyId: string, player: Player): boolean
			local record = parties[partyId]
			if record == nil or partyOf[player] ~= nil then
				return false
			end
			table.insert(record.members, player)
			partyOf[player] = partyId
			return true
		end,
		removeMember = function(partyId: string, player: Player)
			local record = parties[partyId]
			if record == nil then
				return
			end
			local index = table.find(record.members, player)
			if index then
				table.remove(record.members, index)
			end
			if partyOf[player] == partyId then
				partyOf[player] = nil
			end
		end,
		setLeader = function(partyId: string, player: Player)
			local record = parties[partyId]
			if record and table.find(record.members, player) then
				record.leader = player
			end
		end,
		dissolve = function(partyId: string): { Player }
			local record = parties[partyId]
			if record == nil then
				return {}
			end
			parties[partyId] = nil
			invites[partyId] = nil
			for _, member in record.members do
				if partyOf[member] == partyId then
					partyOf[member] = nil
				end
			end
			return record.members
		end,
		addInvite = function(invite: PartyInvite)
			local byTarget = invites[invite.partyId]
			if byTarget == nil then
				byTarget = {}
				invites[invite.partyId] = byTarget
			end
			(byTarget :: { [Player]: PartyInvite })[invite.target] = invite
		end,
		removeInvite = function(partyId: string, target: Player)
			local byTarget = invites[partyId]
			if byTarget then
				byTarget[target] = nil
				if next(byTarget) == nil then
					invites[partyId] = nil
				end
			end
		end,
		getInvite = function(partyId: string, target: Player): PartyInvite?
			local byTarget = invites[partyId]
			return byTarget and byTarget[target]
		end,
		invitesFor = function(target: Player): { PartyInvite }
			local result: { PartyInvite } = {}
			for _, byTarget in invites do
				local invite = byTarget[target]
				if invite then
					table.insert(result, invite)
				end
			end
			return result
		end,
		invitesOf = function(partyId: string): { PartyInvite }
			local result: { PartyInvite } = {}
			local byTarget: { [Player]: PartyInvite } = invites[partyId] or {}
			for _, invite in byTarget do
				table.insert(result, invite)
			end
			return result
		end,
		allInvites = function(): { PartyInvite }
			local result: { PartyInvite } = {}
			for _, byTarget in invites do
				for _, invite in byTarget do
					table.insert(result, invite)
				end
			end
			return result
		end,
	}
	return backend
end

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local PartyService = {}

-- Changed(partyId: string) : composition, chef ou existence du groupe modifiés.
PartyService.Changed = Signal.new()

local backend: PartyBackend = newMemoryBackend()
local requestLimiter = RateLimiter.new(2, 6)
local isStarted = false

local function okResponse(data: any?): Response
	return { ok = true, data = data }
end

local function failResponse(code: string): Response
	return { ok = false, error = code, message = PartyConfig.errorMessage(code) }
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
	StateSync.notify(player, "party", payload)
end

local function recordOf(player: Player): PartyRecord?
	local partyId = backend.getPartyIdOf(player)
	return if partyId then backend.get(partyId) else nil
end

local function findTarget(params: Params): Player?
	if type(params.targetName) == "string" and #params.targetName > 0 and #params.targetName <= 32 then
		local wanted = string.lower(params.targetName)
		for _, player in Players:GetPlayers() do
			if string.lower(player.Name) == wanted then
				return player
			end
		end
		local found: Player? = nil
		for _, player in Players:GetPlayers() do
			if string.lower(player.DisplayName) == wanted then
				if found then
					return nil -- nom d'affichage ambigu
				end
				found = player
			end
		end
		return found
	end
	local userId = params.targetUserId
	if type(userId) == "number" and userId == userId and userId >= 1 and userId % 1 == 0 then
		return Players:GetPlayerByUserId(userId)
	end
	return nil
end

-- Repousse la tranche "party" et l'attribut de tous les joueurs concernés.
local function refreshPlayers(players: { Player })
	for _, player in players do
		if isInGame(player) then
			player:SetAttribute(PARTY_ATTRIBUTE, backend.getPartyIdOf(player))
			StateSync.push(player, "party")
		end
	end
end

local function refreshParty(partyId: string, extra: { Player }?)
	local players: { Player } = {}
	local record = backend.get(partyId)
	if record then
		for _, member in record.members do
			table.insert(players, member)
		end
	end
	for _, invite in backend.invitesOf(partyId) do
		table.insert(players, invite.target)
	end
	if extra then
		for _, player in extra do
			table.insert(players, player)
		end
	end
	refreshPlayers(players)
	PartyService.Changed:Fire(partyId)
end

-- Dissout le groupe (prévenant ses membres et ses invités).
local function dissolve(partyId: string, reason: string)
	local pendingTargets: { Player } = {}
	for _, invite in backend.invitesOf(partyId) do
		table.insert(pendingTargets, invite.target)
	end
	local members = backend.dissolve(partyId)
	for _, member in members do
		if isInGame(member) then
			notify(member, "dissolved", reason)
		end
	end
	refreshPlayers(members)
	refreshPlayers(pendingTargets)
	PartyService.Changed:Fire(partyId)
end

-- Règle des groupes seuls : un groupe d'un membre sans invitation en attente est dissous.
local function dissolveIfAlone(partyId: string, reason: string): boolean
	local record = backend.get(partyId)
	if record and #record.members <= 1 and #backend.invitesOf(partyId) == 0 then
		dissolve(partyId, reason)
		return true
	end
	return false
end

-- Retire `player` de son groupe : transmission automatique de la direction, dissolution à 1 membre.
local function removeFromParty(player: Player, notice: string?)
	local record = recordOf(player)
	if record == nil then
		return
	end
	local partyId = record.id
	local wasLeader = record.leader == player
	backend.removeMember(partyId, player)
	refreshPlayers({ player })

	local remaining = backend.get(partyId)
	if remaining == nil then
		return
	end
	if #remaining.members <= 1 then
		dissolve(partyId, "Le groupe est dissous : il ne reste qu'un membre.")
		return
	end
	if wasLeader then
		local heir = remaining.members[1] -- le plus ancien
		backend.setLeader(partyId, heir)
		notify(heir, "leader", "Vous dirigez désormais le groupe.")
	end
	if notice then
		for _, member in remaining.members do
			notify(member, "member_left", notice)
		end
	end
	refreshParty(partyId)
end

--------------------------------------------------------------------------------
-- Tranche d'état "party"
--------------------------------------------------------------------------------

local function buildPartyState(player: Player): any
	local now = os.time()
	local incoming = {}
	for _, invite in backend.invitesFor(player) do
		local inviteRecord = backend.get(invite.partyId)
		if invite.expiresAt > now and inviteRecord then
			table.insert(incoming, {
				partyId = invite.partyId,
				fromUserId = invite.from.UserId,
				fromName = invite.from.Name,
				expiresAt = invite.expiresAt,
				size = #inviteRecord.members,
			})
		end
	end
	table.sort(incoming, function(a, b)
		return a.expiresAt < b.expiresAt
	end)

	local record = recordOf(player)
	local party: any = nil
	if record then
		local members = {}
		for _, member in record.members do
			table.insert(members, {
				userId = member.UserId,
				name = member.Name,
				displayName = member.DisplayName,
				isLeader = member == record.leader,
				isYou = member == player,
			})
		end
		local outgoing = {}
		for _, invite in backend.invitesOf(record.id) do
			if invite.expiresAt > now then
				table.insert(outgoing, { userId = invite.target.UserId, name = invite.target.Name, expiresAt = invite.expiresAt })
			end
		end
		local isLeader = record.leader == player
		party = {
			id = record.id,
			leaderId = record.leader.UserId,
			leaderName = record.leader.Name,
			isLeader = isLeader,
			size = #record.members,
			maxSize = PartyConfig.MAX_SIZE,
			createdAt = record.createdAt,
			members = members,
			outgoingInvites = outgoing,
			canInvite = isLeader and #record.members < PartyConfig.MAX_SIZE,
		}
	end

	return {
		inParty = record ~= nil,
		party = party,
		incomingInvites = incoming,
		limits = {
			maxSize = PartyConfig.MAX_SIZE,
			inviteTimeout = PartyConfig.INVITE_TIMEOUT,
			shareRange = PartyConfig.SHARE_RANGE,
		},
	}
end

--------------------------------------------------------------------------------
-- Actions Remote
--------------------------------------------------------------------------------

local function handleCreate(player: Player, _params: Params): Response
	if recordOf(player) then
		return failResponse("already_in_party")
	end
	local record = backend.create(player, os.time())
	refreshParty(record.id)
	return okResponse(buildPartyState(player))
end

local function handleInvite(player: Player, params: Params): Response
	local target = findTarget(params)
	if target == nil or not isInGame(target) then
		return failResponse("unknown_player")
	end
	if target == player then
		return failResponse("target_is_self")
	end
	if recordOf(target) then
		return failResponse("target_in_party")
	end
	local record = recordOf(player)
	if record and record.leader ~= player then
		return failResponse("not_leader")
	end
	if record and #record.members >= PartyConfig.MAX_SIZE then
		return failResponse("party_full")
	end
	if record and backend.getInvite(record.id, target) == nil and #backend.invitesOf(record.id) >= PartyConfig.MAX_PENDING_INVITES then
		return failResponse("invites_full")
	end
	local party = record or backend.create(player, os.time()) -- inviter sans groupe = le créer
	backend.addInvite({
		partyId = party.id,
		from = player,
		target = target,
		expiresAt = os.time() + PartyConfig.INVITE_TIMEOUT,
	})
	notify(target, "invite_received", `{player.Name} vous invite dans son groupe.`, { partyId = party.id, fromUserId = player.UserId })
	refreshParty(party.id)
	return okResponse({ targetUserId = target.UserId, targetName = target.Name })
end

local function readPartyId(params: Params): string?
	local partyId = params.partyId
	if type(partyId) == "string" and #partyId <= 40 and string.match(partyId, "^P_[%w]+$") then
		return partyId
	end
	return nil
end

local function handleAccept(player: Player, params: Params): Response
	local partyId = readPartyId(params)
	if partyId == nil then
		return failResponse("bad_params")
	end
	if recordOf(player) then
		return failResponse("already_in_party")
	end
	local invite = backend.getInvite(partyId, player)
	local record = backend.get(partyId)
	if invite == nil or invite.expiresAt <= os.time() then
		return failResponse("invite_not_found")
	end
	if record == nil then
		return failResponse("party_not_found")
	end
	if #record.members >= PartyConfig.MAX_SIZE then
		return failResponse("party_full")
	end
	backend.removeInvite(partyId, player)
	if not backend.addMember(partyId, player) then
		return failResponse("already_in_party")
	end
	-- Ses autres invitations n'ont plus d'objet.
	for _, other in backend.invitesFor(player) do
		backend.removeInvite(other.partyId, player)
		task.defer(function()
			if not dissolveIfAlone(other.partyId, `{player.Name} a rejoint un autre groupe : groupe dissous.`) then
				refreshParty(other.partyId)
			end
		end)
	end
	for _, member in record.members do
		if member ~= player then
			notify(member, "member_joined", `{player.Name} a rejoint le groupe.`)
		end
	end
	refreshParty(partyId)
	return okResponse(buildPartyState(player))
end

local function handleDecline(player: Player, params: Params): Response
	local partyId = readPartyId(params)
	if partyId == nil then
		return failResponse("bad_params")
	end
	local invite = backend.getInvite(partyId, player)
	backend.removeInvite(partyId, player)
	refreshPlayers({ player })
	if invite and isInGame(invite.from) then
		notify(invite.from, "invite_declined", `{player.Name} a décliné votre invitation.`)
	end
	if not dissolveIfAlone(partyId, "Personne n'a rejoint le groupe : il est dissous.") then
		refreshParty(partyId)
	end
	return okResponse({})
end

local function handleLeave(player: Player, _params: Params): Response
	if recordOf(player) == nil then
		return failResponse("not_in_party")
	end
	removeFromParty(player, `{player.Name} a quitté le groupe.`)
	return okResponse({})
end

local function handleKick(player: Player, params: Params): Response
	local record = recordOf(player)
	if record == nil then
		return failResponse("not_in_party")
	end
	if record.leader ~= player then
		return failResponse("not_leader")
	end
	local target = findTarget({ targetUserId = params.targetUserId })
	if target == nil or not table.find(record.members, target) then
		return failResponse("target_not_member")
	end
	if target == player then
		return failResponse("target_is_self")
	end
	notify(target, "kicked", "Vous avez été exclu du groupe.")
	removeFromParty(target, `{target.Name} a été exclu du groupe.`)
	return okResponse({})
end

local function handlePromote(player: Player, params: Params): Response
	local record = recordOf(player)
	if record == nil then
		return failResponse("not_in_party")
	end
	if record.leader ~= player then
		return failResponse("not_leader")
	end
	local target = findTarget({ targetUserId = params.targetUserId })
	if target == nil or not table.find(record.members, target) then
		return failResponse("target_not_member")
	end
	if target == player then
		return failResponse("target_is_self")
	end
	backend.setLeader(record.id, target)
	notify(target, "leader", "Vous dirigez désormais le groupe.")
	refreshParty(record.id)
	return okResponse({})
end

local function handleGetInfo(player: Player, _params: Params): Response
	return okResponse(buildPartyState(player))
end

local ACTIONS: { [string]: (Player, Params) -> Response } = {
	getInfo = handleGetInfo,
	create = handleCreate,
	invite = handleInvite,
	accept = handleAccept,
	decline = handleDecline,
	leave = handleLeave,
	kick = handleKick,
	promote = handlePromote,
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
	local isHandled, response = pcall(ACTIONS[action], player, params or {})
	if not isHandled then
		warn(`[Party] Action "{action}" de {player.Name} en erreur : {response}`)
		return failResponse("internal")
	end
	return response
end

--------------------------------------------------------------------------------
-- Éligibilité partagée et expiration des invitations
--------------------------------------------------------------------------------

local function alivePosition(player: Player): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		return nil
	end
	return rootPart.Position
end

-- Ajoute aux éligibles les membres de leur groupe, vivants, à moins de SHARE_RANGE studs d'un éligible.
local function extendEligibility(eligible: { Player }, _position: Vector3): { Player }
	local result = table.clone(eligible)
	local included: { [Player]: boolean } = {}
	for _, player in eligible do
		included[player] = true
	end
	for _, player in eligible do
		local record = recordOf(player)
		local origin = record and alivePosition(player)
		if record == nil or origin == nil then
			continue
		end
		for _, member in record.members do
			if included[member] or not isInGame(member) then
				continue
			end
			local position = alivePosition(member)
			if position and (position - origin).Magnitude <= PartyConfig.SHARE_RANGE then
				included[member] = true
				table.insert(result, member)
			end
		end
	end
	return result
end

local function expireInvites()
	local now = os.time()
	for _, invite in backend.allInvites() do
		if invite.expiresAt <= now then
			backend.removeInvite(invite.partyId, invite.target)
			refreshPlayers({ invite.target })
			if isInGame(invite.from) then
				notify(invite.from, "invite_expired", `L'invitation envoyée à {invite.target.Name} a expiré.`)
			end
			if not dissolveIfAlone(invite.partyId, "Personne n'a rejoint le groupe : il est dissous.") then
				refreshParty(invite.partyId)
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	-- Invitations reçues : elles disparaissent.
	for _, invite in backend.invitesFor(player) do
		backend.removeInvite(invite.partyId, player)
		if not dissolveIfAlone(invite.partyId, "Personne n'a rejoint le groupe : il est dissous.") then
			refreshParty(invite.partyId)
		end
	end
	removeFromParty(player, `{player.Name} s'est déconnecté.`)
	-- Invitations envoyées par un joueur parti sans groupe restant : retirées avec le groupe.
end

--------------------------------------------------------------------------------
-- API serveur
--------------------------------------------------------------------------------

-- Groupe de `player` (copie : modifier la table n'a aucun effet), ou nil s'il n'en a pas.
function PartyService.getParty(player: Player): PartyInfo?
	local record = recordOf(player)
	if record == nil then
		return nil
	end
	return { id = record.id, leader = record.leader, members = table.clone(record.members) }
end

-- Membres du groupe de `player`, lui compris ({ player } s'il est seul).
function PartyService.getMembers(player: Player): { Player }
	local record = recordOf(player)
	return if record then table.clone(record.members) else { player }
end

function PartyService.areInSameParty(a: Player, b: Player): boolean
	if a == b then
		return false
	end
	local partyId = backend.getPartyIdOf(a)
	return partyId ~= nil and partyId == backend.getPartyIdOf(b)
end

-- Remplace le stockage des groupes (tests, future version multiserveur). Avant start() seulement.
function PartyService.setBackend(newBackend: PartyBackend)
	assert(not isStarted, "[Party] setBackend doit être appelé avant start()")
	backend = newBackend
end

-- Fabrique du stockage en mémoire (exposée pour les tests).
PartyService.newMemoryBackend = newMemoryBackend

-- À appeler une seule fois au démarrage du serveur (après StateSync et DamageService).
function PartyService.start()
	if isStarted then
		return
	end
	isStarted = true

	StateSync.register("party", buildPartyState)
	Remotes.PartyRequest.OnServerInvoke = handleRequest
	DamageService.setEligibilityExtender(extendEligibility)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(PartyConfig.EXPIRY_CHECK_INTERVAL)
			expireInvites()
		end
	end)
end

return PartyService
