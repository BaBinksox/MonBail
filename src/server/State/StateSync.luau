--!strict
--[[
	StateSync
	Pousse au client de chaque joueur SON état (progression, quêtes, missions, inventaire, guilde...)
	et ses notifications. C'est le seul canal serveur -> client de la progression : les services ne
	créent pas de RemoteEvent à eux pour ça.

	Fonctionnement :
		- chaque tranche ("slice") a un CONSTRUCTEUR (player) -> data. Par défaut, une tranche du
		  profil est envoyée telle quelle ; un service peut enregistrer un constructeur plus riche
		  (register), par exemple MissionService pour "missions" (avec les contrats disponibles) ;
		- push(player, slice) planifie l'envoi ; plusieurs push dans la même frame n'en font qu'un ;
		- PlayerData.Changed déclenche push automatiquement ;
		- au chargement (ou rechargement) d'un profil, toutes les tranches sont poussées.

	Le client ne peut rien écrire ici, sauf ses réglages (UpdateSettings, bornés par le serveur).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.State.StateRemotes)

local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)

type Builder = (player: Player) -> any

-- Tranches du profil envoyées telles quelles tant qu'aucun service n'a enregistré mieux.
local PROFILE_SLICES = { "progression", "quests", "missions", "inventory", "discoveries", "unlocks", "settings" }

local StateSync = {}

local builders: { [string]: Builder } = {}
local pending: { [Player]: { [string]: boolean } } = {}
local settingsLimiter = RateLimiter.new(2, 5)
local isStarted = false

--------------------------------------------------------------------------------
-- Envoi
--------------------------------------------------------------------------------

local function build(player: Player, slice: string): (boolean, any)
	local builder = builders[slice]
	if builder == nil then
		return false, nil
	end
	local isBuilt, data = pcall(builder, player)
	if not isBuilt then
		warn(`[State] Tranche "{slice}" impossible à construire pour {player.Name} : {data}`)
		return false, nil
	end
	return true, data
end

local function flush(player: Player)
	local slices = pending[player]
	pending[player] = nil
	if slices == nil or player.Parent ~= Players then
		return
	end
	for slice in slices do
		local isBuilt, data = build(player, slice)
		if isBuilt then
			Remotes.StateChanged:FireClient(player, slice, data)
		end
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Enregistre (ou remplace) le constructeur d'une tranche.
function StateSync.register(slice: string, builder: Builder)
	builders[slice] = builder
end

-- Planifie l'envoi de `slice` au client de `player` (regroupé à la frame suivante).
function StateSync.push(player: Player, slice: string)
	local slices = pending[player]
	if slices == nil then
		slices = {}
		pending[player] = slices
		task.defer(flush, player)
	end
	slices[slice] = true
end

function StateSync.pushAll(player: Player)
	for slice in builders do
		StateSync.push(player, slice)
	end
end

-- Notification à afficher chez le joueur (toast). Purement informatif.
function StateSync.notify(player: Player, kind: string, payload: { [string]: any })
	if player.Parent == Players then
		Remotes.Notify:FireClient(player, kind, payload)
	end
end

-- À appeler une seule fois au démarrage du serveur (avant les services qui enregistrent des tranches).
function StateSync.start()
	if isStarted then
		return
	end
	isStarted = true

	for _, slice in PROFILE_SLICES do
		if builders[slice] == nil then
			builders[slice] = function(player: Player): any
				local profile = PlayerData.get(player)
				return profile and (profile :: any)[slice]
			end
		end
	end
	builders.saveStatus = function(player: Player): any
		return { saveable = ProfileStore.isSaveable(player), loaded = PlayerData.get(player) ~= nil }
	end

	PlayerData.Changed:Connect(StateSync.push)
	ProfileStore.ProfileLoaded:Connect(StateSync.pushAll)
	ProfileStore.ProfileRefreshed:Connect(StateSync.pushAll)

	Remotes.RequestFullState.OnServerInvoke = function(player: Player): any
		ProfileStore.waitForProfile(player, 15)
		local state = {}
		for slice in builders do
			local isBuilt, data = build(player, slice)
			if isBuilt then
				state[slice] = data
			end
		end
		return state
	end

	Remotes.UpdateSettings.OnServerEvent:Connect(function(player: Player, raw: any)
		if type(raw) ~= "table" or not settingsLimiter:allow(player) then
			return
		end
		PlayerData.mutate(player, "settings", function(profile)
			local settings = profile.settings
			if type(raw.music) == "number" and raw.music == raw.music then
				settings.music = math.clamp(raw.music, 0, 1)
			end
			if type(raw.sfx) == "number" and raw.sfx == raw.sfx then
				settings.sfx = math.clamp(raw.sfx, 0, 1)
			end
			if type(raw.uiScale) == "number" and raw.uiScale == raw.uiScale then
				settings.uiScale = math.clamp(raw.uiScale, 0.75, 1.5)
			end
			if type(raw.reducedEffects) == "boolean" then
				settings.reducedEffects = raw.reducedEffects
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

return StateSync
