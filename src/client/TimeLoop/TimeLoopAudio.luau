--!strict
--[[
	TimeLoopAudio
	Le chœur du rembobinage : un souffle de voix féminines, court et discret. Local à ce client.
	Joué quand le SERVEUR confirme le rembobinage (TimeLoopRemotes.RewindStarted, voir
	TimeLoopController), jamais sur la simple pression de la touche R.

	Réglages : AudioConfig.REWIND_CHOIR (ID, volume, durée, fondus). Le son est rangé dans la
	catégorie « Effets » (AudioMixer) : le réglage de volume du joueur s'applique, 0 le coupe.
		- jamais deux chœurs superposés : un seul Sound, et un rembobinage moins de `minInterval`
		  secondes après le précédent ne le relance pas ;
		- court : il s'efface au bout de `maxDuration` secondes, même si le rembobinage dure ;
		- lassitude : des rembobinages rapprochés le jouent de moins en moins fort ;
		- légère retombée de hauteur pendant le rembobinage (`endOctave`).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local AudioMixer = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("AudioMixer") :: ModuleScript)

local CHOIR = AudioConfig.REWIND_CHOIR

local TimeLoopAudio = {}

-- Créé depuis un LocalScript : ce son ne se joue que sur ce client.
local sound = Instance.new("Sound")
sound.Name = "TimeLoopRewindChoir"
sound.SoundId = CHOIR.id
sound.Volume = 0
AudioMixer.assign(sound, "Sfx")
sound.Parent = SoundService

local pitchShift = Instance.new("PitchShiftSoundEffect")
pitchShift.Octave = 1
pitchShift.Parent = sound

local volumeTween: Tween? = nil
local pitchTween: Tween? = nil
local lastPlayClock = -math.huge
local fatigueRatio = 1 -- 1 = volume plein ; baisse à chaque rembobinage rapproché
local playToken = 0

local function tween(instance: Instance, duration: number, goal: { [string]: any }): Tween
	local newTween = TweenService:Create(instance, TweenInfo.new(math.max(duration, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	newTween:Play()
	return newTween
end

local function nextVolume(now: number): number
	if now - lastPlayClock <= CHOIR.fatigueWindow then
		fatigueRatio = math.max(fatigueRatio * CHOIR.fatigueFactor, CHOIR.minVolumeRatio)
	else
		fatigueRatio = 1
	end
	return CHOIR.volume * fatigueRatio
end

-- Lance le chœur pour un rembobinage de `duration` secondes.
function TimeLoopAudio.playRewind(duration: number)
	if CHOIR.id == "" then
		return
	end
	local now = os.clock()
	if sound.IsPlaying and now - lastPlayClock < CHOIR.minInterval then
		return -- le chœur précédent est encore là : pas de doublon
	end
	local volume = nextVolume(now)
	lastPlayClock = now
	playToken += 1
	local token = playToken

	if volumeTween then
		volumeTween:Cancel()
	end
	if pitchTween then
		pitchTween:Cancel()
	end
	sound.Volume = 0
	sound.TimePosition = 0
	pitchShift.Octave = 1
	sound:Play()
	volumeTween = tween(sound, CHOIR.fadeIn, { Volume = volume })
	local audible = math.min(duration, CHOIR.maxDuration)
	pitchTween = tween(pitchShift, audible, { Octave = CHOIR.endOctave })
	task.delay(math.max(audible - CHOIR.fadeOut, CHOIR.fadeIn), function()
		if token == playToken then
			TimeLoopAudio.fadeOut()
		end
	end)
end

-- Fondu de sortie (fin du rembobinage ou durée maximale atteinte). Le son s'arrête une fois muet.
function TimeLoopAudio.fadeOut()
	if not sound.IsPlaying then
		return
	end
	if volumeTween then
		volumeTween:Cancel()
	end
	local token = playToken
	local fadeTween = tween(sound, CHOIR.fadeOut, { Volume = 0 })
	volumeTween = fadeTween
	fadeTween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and token == playToken then
			sound:Stop()
		end
	end)
end

return TimeLoopAudio
