--!strict
--[[
	MusicController
	Musique de la région où se trouve le joueur (attribut Player "Region", publié par RegionService
	côté serveur), avec sa variante de nuit si AudioConfig.REGION_MUSIC en prévoit une.
	Le changement n'est demandé qu'après AudioConfig.REGION_SETTLE_TIME secondes dans la nouvelle
	région : longer une frontière ne fait pas alterner deux musiques. Le fondu, la priorité sur le
	créateur et l'absence de chevauchement sont l'affaire de MusicDirector.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(sharedFolder:WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local WorldConfig = require(sharedFolder:WaitForChild("World"):WaitForChild("WorldConfig") :: ModuleScript)
local MusicDirector = require(script.Parent:WaitForChild("MusicDirector") :: ModuleScript)

local REGION_ATTRIBUTE = "Region"
local NIGHT_CHECK_INTERVAL = 5 -- secondes : la bascule jour / nuit n'a pas besoin d'être plus fine

local localPlayer = Players.LocalPlayer
local settleToken = 0
local isSettling = false -- un changement de région attend la fin de REGION_SETTLE_TIME

local function isNight(): boolean
	local clock = WorldConfig.getClockTime()
	return clock >= WorldConfig.NIGHT_START or clock < WorldConfig.NIGHT_END
end

-- Piste voulue pour la région courante, ou nil (région sans musique propre : on garde l'actuelle).
local function regionTrack(): (boolean, string?)
	local regionId = localPlayer:GetAttribute(REGION_ATTRIBUTE)
	if type(regionId) ~= "string" then
		return false, nil
	end
	local music = AudioConfig.REGION_MUSIC[regionId]
	if music == nil then
		return false, nil
	end
	return true, if isNight() and music.night then music.night else music.day
end

local function apply()
	local known, key = regionTrack()
	if known then
		MusicDirector.set("region", key)
	end
end

localPlayer:GetAttributeChangedSignal(REGION_ATTRIBUTE):Connect(function()
	settleToken += 1
	local token = settleToken
	isSettling = true
	task.delay(AudioConfig.REGION_SETTLE_TIME, function()
		if token == settleToken then
			isSettling = false
			apply()
		end
	end)
end)

apply()
task.spawn(function()
	while true do
		task.wait(NIGHT_CHECK_INTERVAL)
		if not isSettling then
			apply()
		end -- même piste : MusicDirector ne fait rien ; variante jour / nuit : fondu
	end
end)
