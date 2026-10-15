--!strict
--[[
	ClientSettings (ModuleScript, client)
	Réglages du joueur tels que le client doit les APPLIQUER : copie de la tranche "settings" de
	PlayerState (enregistrée côté serveur, restaurée à la connexion), plus un aperçu local pendant
	qu'on bouge un curseur. Les effets lisent ici (pull) : aucun couplage entre l'écran des options
	et les systèmes d'effets.

	API :
		ClientSettings.get(): Settings              réglages effectifs (valeurs par défaut si inconnus)
		ClientSettings.isReducedEffects(): boolean  mode « effets réduits »
		ClientSettings.preview(partial)             aperçu local (curseur), sans enregistrer
		ClientSettings.Changed: Signal(settings)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal") :: ModuleScript)
local PlayerState = require(script.Parent:WaitForChild("PlayerState") :: ModuleScript)

export type Settings = {
	music: number,
	ambience: number,
	sfx: number,
	uiScale: number,
	reducedEffects: boolean,
}

local DEFAULTS: Settings = { music = 1, ambience = 1, sfx = 1, uiScale = 1, reducedEffects = false }

local ClientSettings = {
	Changed = Signal.new(),
}

local current: Settings = table.clone(DEFAULTS)

local function merge(source: any)
	if type(source) ~= "table" then
		return
	end
	for key, default in DEFAULTS do
		local value = source[key]
		if type(value) == type(default) then
			(current :: any)[key] = value
		end
	end
end

function ClientSettings.get(): Settings
	return table.clone(current)
end

function ClientSettings.isReducedEffects(): boolean
	return current.reducedEffects == true
end

function ClientSettings.preview(partial: { [string]: any })
	merge(partial)
	ClientSettings.Changed:Fire(ClientSettings.get())
end

merge(PlayerState.get("settings"))
PlayerState.Changed:Connect(function(slice: string, data: any)
	if slice == "settings" then
		merge(data)
		ClientSettings.Changed:Fire(ClientSettings.get())
	end
end)

return ClientSettings
