--!strict
--[[
	PlayerState (ModuleScript, client)
	Copie locale de l'état du joueur poussé par le serveur (StateSync / StateRemotes). Les interfaces
	ne parlent jamais au serveur pour LIRE : elles lisent ici et écoutent les changements.

	API :
		PlayerState.get(slice): any                    tranche complète ("progression", "quests",
		                                               "missions", "guild", "party", ...) ou nil
		PlayerState.Changed: Signal(slice, data)       une tranche vient d'être remplacée
		PlayerState.Notified: Signal(kind, payload)    notification du serveur (toast, texte, panneau)
		PlayerState.whenReady(): ()                    YIELD jusqu'au premier état complet
	Le premier état complet est demandé au démarrage (RequestFullState) ; ensuite le serveur pousse
	chaque tranche entière à chaque changement (pas de diff : la dernière reçue fait foi).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(sharedFolder:WaitForChild("Util"):WaitForChild("Signal") :: ModuleScript)
local StateRemotes = require(sharedFolder:WaitForChild("State"):WaitForChild("StateRemotes") :: ModuleScript)

local FULL_STATE_RETRIES = 5
local FULL_STATE_RETRY_DELAY = 2

local PlayerState = {
	Changed = Signal.new(),
	Notified = Signal.new(),
}

local slices: { [string]: any } = {}
local isReady = false
local readyWaiters: { thread } = {}

local function setSlice(slice: string, data: any)
	slices[slice] = data
	PlayerState.Changed:Fire(slice, data)
end

local function markReady()
	if isReady then
		return
	end
	isReady = true
	local waiters = readyWaiters
	readyWaiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

function PlayerState.get(slice: string): any
	return slices[slice]
end

function PlayerState.whenReady()
	if isReady then
		return
	end
	table.insert(readyWaiters, coroutine.running())
	coroutine.yield()
end

StateRemotes.StateChanged.OnClientEvent:Connect(function(slice: any, data: any)
	if type(slice) == "string" then
		setSlice(slice, data)
	end
end)

StateRemotes.Notify.OnClientEvent:Connect(function(kind: any, payload: any)
	if type(kind) == "string" then
		PlayerState.Notified:Fire(kind, if type(payload) == "table" then payload else {})
	end
end)

-- État complet au démarrage : le profil peut ne pas être chargé tout de suite, on réessaie.
task.spawn(function()
	for _ = 1, FULL_STATE_RETRIES do
		local isDone, state = pcall(function()
			return StateRemotes.RequestFullState:InvokeServer()
		end)
		if isDone and type(state) == "table" and next(state) ~= nil then
			for slice, data in state do
				if type(slice) == "string" then
					setSlice(slice, data)
				end
			end
			markReady()
			return
		end
		task.wait(FULL_STATE_RETRY_DELAY)
	end
	markReady() -- les tranches arriveront par StateChanged
end)

return PlayerState
