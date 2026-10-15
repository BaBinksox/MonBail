--!strict
--[[
	AudioMixer (ModuleScript, client)
	Trois SoundGroups dans SoundService — Music, Ambience, Sfx — dont le volume suit les réglages du
	joueur (tranche "settings" de PlayerState : music, ambience, sfx, de 0 à 1). Tout son du jeu est
	rangé dans l'un d'eux : baisser « Musique » baisse la musique du créateur ET celle des régions.

	API :
		AudioMixer.assign(sound, category)      range `sound` dans "Music" | "Ambience" | "Sfx"
		AudioMixer.group(category): SoundGroup
		AudioMixer.preview(settings)            applique des volumes sans les enregistrer (curseurs)
		AudioMixer.getVolume(category): number  volume effectif de la catégorie (0 à 1)
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local PlayerState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("PlayerState") :: ModuleScript)

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

function AudioMixer.preview(settings: any)
	for category, key in SETTING_OF_CATEGORY do
		groups[category].Volume = settingValue(settings, key) * (AudioConfig.CATEGORY_MAX_VOLUME[category] or 1)
	end
end

function AudioMixer.getVolume(category: Category): number
	return groups[category].Volume
end

AudioMixer.preview(PlayerState.get("settings"))
PlayerState.Changed:Connect(function(slice: string, data: any)
	if slice == "settings" then
		AudioMixer.preview(data)
	end
end)

return AudioMixer
