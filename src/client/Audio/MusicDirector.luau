--!strict
--[[
	MusicDirector (ModuleScript, client)
	UNE seule musique à la fois. Plusieurs scripts expriment ce qu'ils voudraient entendre, chacun
	sur sa couche ; la couche la plus prioritaire qui demande une piste l'emporte :
		"override"  écrans plein cadre : créateur de personnage (prioritaire)
		"anomaly"   anomalie temporelle (CombatMusicController)
		"boss"      boss réveillé à proximité
		"combat"    joueur en combat (attribut InCombat posé par le serveur)
		"victory"   courte phrase de victoire, puis retour au calme
		"alert"     présence hostile proche
		"region"    musique de la région où se trouve le joueur (MusicController)
	Changer de piste = fondu de sortie de l'ancienne, fondu d'entrée de la nouvelle (légèrement
	croisés, AudioConfig.CROSSFADE_OVERLAP). Redemander la piste en cours ne la relance pas : changer
	de page dans le créateur ou retraverser une frontière ne la fait pas repartir du début. Une piste
	quittée puis retrouvée dans les RESUME_MEMORY secondes reprend où elle en était (l'exploration
	ne repart pas du début après chaque combat). Au plus deux pistes en fondu de sortie : jamais de
	superposition incontrôlée. Une piste sans ID ("" dans AudioConfig) vaut silence.

	API :
		MusicDirector.set(layer, trackKey?)     nil = la couche ne demande plus rien
		MusicDirector.getCurrentKey(): string?  piste en cours (nil = silence)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local AudioMixer = require(script.Parent:WaitForChild("AudioMixer") :: ModuleScript)

export type Layer = "override" | "anomaly" | "boss" | "combat" | "victory" | "alert" | "region"

type Track = { id: string, volume: number, fadeIn: number, fadeOut: number, looped: boolean }

type Voice = {
	key: string,
	sound: Sound,
	tween: Tween?,
}

local LAYER_ORDER: { Layer } = { "override", "anomaly", "boss", "combat", "victory", "alert", "region" }
local MAX_FADING = 2 -- pistes en fondu de sortie au plus ; au-delà, la plus ancienne se tait

local MusicDirector = {}

local layers: { [string]: string? } = {}
local current: Voice? = nil
local fading: { Voice } = {}
local positions: { [string]: { time: number, clock: number } } = {} -- reprise des pistes quittées

local function trackOf(key: string?): Track?
	if key == nil then
		return nil
	end
	local track = AudioConfig.TRACKS[key]
	return if track and track.id ~= "" then track else nil
end

local function desiredKey(): string?
	for _, layer in LAYER_ORDER do
		local key = layers[layer]
		if key ~= nil then
			return key
		end
	end
	return nil
end

local function fadeTo(voice: Voice, volume: number, duration: number, onCompleted: (() -> ())?)
	local previous = voice.tween
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(voice.sound, TweenInfo.new(math.max(duration, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = volume })
	voice.tween = tween
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and voice.tween == tween and onCompleted then
			onCompleted()
		end
	end)
	tween:Play()
end

local function retire(voice: Voice)
	local track = AudioConfig.TRACKS[voice.key]
	if track == nil or track.looped ~= false then
		positions[voice.key] = { time = voice.sound.TimePosition, clock = os.clock() }
	end
	table.insert(fading, voice)
	while #fading > MAX_FADING do
		local oldest = table.remove(fading, 1) :: Voice
		if oldest.tween then
			oldest.tween:Cancel()
		end
		oldest.sound:Stop()
		oldest.sound:Destroy()
	end
	fadeTo(voice, 0, if track then track.fadeOut else 2, function()
		local index = table.find(fading, voice)
		if index then
			table.remove(fading, index)
		end
		voice.sound:Stop()
		voice.sound:Destroy()
	end)
end

local function refresh()
	local key = desiredKey()
	local track = trackOf(key)
	local playing = current
	if playing and track and playing.key == key then
		fadeTo(playing, track.volume, track.fadeIn) -- déjà là : on s'assure seulement qu'elle est audible
		return
	end

	local previousFadeOut = 0
	if playing then
		current = nil
		local previousTrack = AudioConfig.TRACKS[playing.key]
		previousFadeOut = if previousTrack then previousTrack.fadeOut else 0
		retire(playing)
	end
	if track == nil or key == nil then
		return
	end

	-- La piste demandée est encore en train de s'éteindre : on la rattrape au lieu de la relancer.
	for index, voice in fading do
		if voice.key == key then
			table.remove(fading, index)
			current = voice
			fadeTo(voice, track.volume, track.fadeIn)
			return
		end
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. key
	sound.SoundId = track.id
	sound.Looped = track.looped ~= false
	sound.Volume = 0
	local memory = positions[key]
	if memory and sound.Looped and os.clock() - memory.clock <= AudioConfig.RESUME_MEMORY then
		sound.TimePosition = memory.time -- reprise là où on l'avait quittée
	end
	AudioMixer.assign(sound, "Music")
	sound.Parent = SoundService
	local voice: Voice = { key = key, sound = sound }
	current = voice

	local delay = previousFadeOut * (1 - math.clamp(AudioConfig.CROSSFADE_OVERLAP, 0, 1))
	local function start()
		if current ~= voice then
			return -- une autre demande est arrivée pendant l'attente
		end
		sound:Play()
		fadeTo(voice, track.volume, track.fadeIn)
	end
	if delay > 0 then
		task.delay(delay, start)
	else
		start()
	end
end

function MusicDirector.set(layer: Layer, trackKey: string?)
	if layers[layer] == trackKey then
		return
	end
	layers[layer] = trackKey
	refresh()
end

function MusicDirector.getCurrentKey(): string?
	local voice = current
	return if voice then voice.key else nil
end

return MusicDirector
