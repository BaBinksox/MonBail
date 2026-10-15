--!strict
--[[
	GuildMessaging
	Notifications entre serveurs des changements de guilde (MessagingService, sujet
	DataConfig.GUILD_MESSAGING_TOPIC, préfixé TEST_ dans Studio comme les DataStores). Singleton serveur.

	Une notification n'est QU'UN SIGNAL DE RELECTURE : { guildId, kind, opId, targetUserId? }. Le
	serveur qui la reçoit relit la guilde dans le DataStore avant d'agir ; il ne fait jamais confiance
	au contenu du message (un message peut être perdu, dupliqué, arriver en retard ou dans le désordre).

		GuildMessaging.publish({ guildId = id, kind = "kicked", opId = opId, targetUserId = 123 })
		GuildMessaging.Received:Connect(function(message) ... relire message.guildId ... end)

	Fonctionne aussi SANS MessagingService (Studio, panne, quota dépassé) : publication et abonnement
	sont en pcall et échouent en silence ; la relecture périodique des guildes (GuildConfig.
	REFRESH_INTERVAL) suffit alors, avec un peu plus de délai.

	Limite de débit : au plus GuildConfig.MESSAGING_MAX_PER_MINUTE publications par minute et par
	serveur (au-delà, la notification est abandonnée : la relecture périodique prend le relais).
]]

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local GuildConfig = require(ReplicatedStorage.Shared.Guild.GuildConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GuildRules = require(script.Parent.GuildRules)

export type Message = {
	guildId: string,
	kind: string, -- "invite", "joined", "left", "kicked", "roles", "description", "dissolved", "contracts"...
	opId: string,
	targetUserId: number?, -- joueur directement concerné (invité, exclu...)
}

local MAX_KIND_LENGTH = 32
local MAX_OP_ID_LENGTH = 64
local DEBUG_LOGS = false -- vrai : trace les échecs de MessagingService dans la sortie

-- Identifiant de CE serveur : on ignore ses propres messages (il a déjà relu la guilde).
local SERVER_ID = HttpService:GenerateGUID(false)

local GuildMessaging = {}

-- Received(message: Message) : un AUTRE serveur signale un changement (à relire dans le DataStore).
GuildMessaging.Received = Signal.new()

local isStarted = false
local isSubscribed = false
local tokens = GuildConfig.MESSAGING_MAX_PER_MINUTE
local refilledAt = os.clock()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function debugLog(text: string)
	if DEBUG_LOGS then
		print(`[Guild] {text}`)
	end
end

-- Seau à jetons : MESSAGING_MAX_PER_MINUTE publications par minute au plus.
local function takeToken(): boolean
	local now = os.clock()
	local rate = GuildConfig.MESSAGING_MAX_PER_MINUTE / 60
	tokens = math.min(GuildConfig.MESSAGING_MAX_PER_MINUTE, tokens + (now - refilledAt) * rate)
	refilledAt = now
	if tokens < 1 then
		return false
	end
	tokens -= 1
	return true
end

-- Vérifie la forme d'un message (reçu d'un autre serveur ou prêt à partir). Retourne une copie propre.
local function parse(raw: any): Message?
	if type(raw) ~= "table" or not GuildRules.isGuildId(raw.guildId) then
		return nil
	end
	if type(raw.kind) ~= "string" or #raw.kind == 0 or #raw.kind > MAX_KIND_LENGTH then
		return nil
	end
	if type(raw.opId) ~= "string" or #raw.opId > MAX_OP_ID_LENGTH then
		return nil
	end
	local targetUserId = raw.targetUserId
	if targetUserId ~= nil and not GuildRules.isUserId(targetUserId) then
		return nil
	end
	return { guildId = raw.guildId, kind = raw.kind, opId = raw.opId, targetUserId = targetUserId }
end

local function onPacket(packet: any)
	local data = if type(packet) == "table" then packet.Data else nil
	if type(data) ~= "table" or data.origin == SERVER_ID then
		return
	end
	local message = parse(data)
	if message then
		GuildMessaging.Received:Fire(message)
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

--[[
	Prévient les autres serveurs qu'une guilde a changé. Ne yield pas (l'envoi part en arrière-plan).
	Retourne false si le message est invalide ou abandonné (limite de débit).
]]
function GuildMessaging.publish(message: Message): boolean
	local clean = parse(message)
	if clean == nil or not takeToken() then
		return false
	end
	local payload = {
		guildId = clean.guildId,
		kind = clean.kind,
		opId = clean.opId,
		targetUserId = clean.targetUserId,
		origin = SERVER_ID,
	}
	task.spawn(function()
		local isSent, errorMessage = pcall(function()
			MessagingService:PublishAsync(DataConfig.storeName(DataConfig.GUILD_MESSAGING_TOPIC), payload)
		end)
		if not isSent then
			debugLog(`publication impossible ({errorMessage}) : la relecture périodique prendra le relais.`)
		end
	end)
	return true
end

-- true si l'abonnement au sujet a réussi (sinon : relecture périodique seulement).
function GuildMessaging.isSubscribed(): boolean
	return isSubscribed
end

-- À appeler une seule fois au démarrage (par GuildService.start). L'abonnement part en arrière-plan.
function GuildMessaging.start()
	if isStarted then
		return
	end
	isStarted = true
	task.spawn(function()
		local isDone, errorMessage = pcall(function()
			MessagingService:SubscribeAsync(DataConfig.storeName(DataConfig.GUILD_MESSAGING_TOPIC), onPacket)
		end)
		isSubscribed = isDone
		if not isDone then
			debugLog(`abonnement impossible ({errorMessage}) : relecture périodique seulement.`)
		end
	end)
end

return GuildMessaging
