--!strict
--[[
	AudioMixer (ModuleScript, client)
	Trois SoundGroups dans SoundService — Music, Ambience, Sfx — dont le volume suit les réglages du
	joueur (tranche "settings" de PlayerState : music, ambience, sfx, de 0 à 1). Tout son du jeu est
	rangé dans l'un d'eux : baisser « Musique » baisse la musique du créateur ET celle des régions.
	Les volumes suivent ClientSettings : les réglages enregistrés, et l'aperçu pendant qu'on bouge
	un curseur des options.

	API :
		AudioMixer.assign(sound, category)      range `sound` dans "Music" | "Ambience" | "Sfx"
		AudioMixer.group(category): SoundGroup
		AudioMixer.preview(settings)            applique des volumes sans les enregistrer (curseurs)
		AudioMixer.getVolume(category): number  volume effectif de la catégorie (0 à 1)
		AudioMixer.duck(level, down, hold, up)  atténuation brève de la musique et de l'ambiance
		                                        (instant de silence d'un ultime), puis retour
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local ClientSettings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)

export type Category = "Music" | "Ambience" | "Sfx"

local SETTING_OF_CATEGORY: { [Category]: string } = { Music = "music", Ambience = "ambience", Sfx = "sfx" }

local AudioMixer = {}

local groups: { [string]: SoundGroup } = {}
for _, name in { "Music", "Ambience", "Sfx" } do
	local existing = SoundService:FindFirstChild(name)
	local group: SoundGroup
	if existing and existing:IsA("SoundGroup") then
		group = existing
	else
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = 1
		group.Parent = SoundService
	end
	groups[name] = group
end

function AudioMixer.group(category: Category): SoundGroup
	return groups[category]
end

function AudioMixer.assign(sound: Sound, category: Category)
	sound.SoundGroup = groups[category]
end

local function settingValue(settings: any, key: string): number
	local value = if type(settings) == "table" then settings[key] else nil
	return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
end

-- Atténuation momentanée (multiplie Musique et Ambiance ; les effets restent audibles).
local duckValue = Instance.new("NumberValue")
duckValue.Value = 1
local duckToken = 0
local lastSettings: any = nil
local DUCKED: { [string]: boolean } = { Music = true, Ambience = true }

local function apply(settings: any)
	lastSettings = settings
	for category, key in SETTING_OF_CATEGORY do
		local duck = if DUCKED[category] then duckValue.Value else 1
		groups[category].Volume = settingValue(settings, key) * (AudioConfig.CATEGORY_MAX_VOLUME[category] or 1) * duck
	end
end

function AudioMixer.preview(settings: any)
	apply(settings)
end

duckValue.Changed:Connect(function()
	apply(lastSettings)
end)

function AudioMixer.duck(level: number, down: number, hold: number, up: number)
	duckToken += 1
	local token = duckToken
	TweenService:Create(duckValue, TweenInfo.new(math.max(down, 0.01)), { Value = math.clamp(level, 0, 1) }):Play()
	task.delay(down + hold, function()
		if token == duckToken then
			TweenService:Create(duckValue, TweenInfo.new(math.max(up, 0.01)), { Value = 1 }):Play()
		end
	end)
end

function AudioMixer.getVolume(category: Category): number
	return groups[category].Volume
end

AudioMixer.preview(ClientSettings.get())
ClientSettings.Changed:Connect(function(settings: any)
	AudioMixer.preview(settings)
end)

return AudioMixer
