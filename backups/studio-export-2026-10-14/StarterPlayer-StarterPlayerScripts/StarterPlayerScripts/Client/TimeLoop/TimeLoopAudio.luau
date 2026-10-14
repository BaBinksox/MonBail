--!strict
--[[
	TimeLoopAudio
	Le son du rembobinage : un chœur qui se déforme. Local à ce client.

	Trois traitements, pour que l'effet reste angoissant sans devenir pénible à force d'être entendu :
		- déformation : un PitchShiftSoundEffect fait glisser la hauteur du son vers le grave
		  pendant toute la durée du rewind ;
		- variation   : chaque écoute part d'un autre endroit du morceau, à une hauteur et une
		  vitesse légèrement différentes ;
		- lassitude   : des rewinds rapprochés sont joués de moins en moins fort, et chaque écoute
		  se termine par un fondu de sortie (fadeOut).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeLoop")
local Config = require(sharedFolder:WaitForChild("TimeLoopConfig") :: ModuleScript)

local FADE_IN = 0.15 -- secondes : le chœur surgit presque d'un coup
local START_OCTAVE_MIN = 0.95 -- hauteur de départ, tirée au hasard dans cette plage
local START_OCTAVE_MAX = 1.12
local SPEED_MIN = 0.92 -- vitesse de lecture, tirée au hasard dans cette plage
local SPEED_MAX = 1.06
local MAX_START_RATIO = 0.5 -- le son démarre quelque part dans cette première partie du morceau

local random = Random.new()

local TimeLoopAudio = {}

-- Créés depuis un LocalScript : ce son ne se joue que sur ce client.
local sound = Instance.new("Sound")
sound.Name = "TimeLoopRewindSound"
sound.SoundId = Config.REWIND_SOUND_ID
sound.Volume = 0
sound.Parent = SoundService

local pitchShift = Instance.new("PitchShiftSoundEffect")
pitchShift.Octave = 1
pitchShift.Parent = sound

local volumeTween: Tween? = nil
local pitchTween: Tween? = nil
local lastPlayClock = -math.huge
local fatigueRatio = 1 -- 1 = volume plein ; baisse à chaque rewind rapproché

local function tween(instance: Instance, duration: number, style: Enum.EasingStyle, goal: { [string]: any }): Tween
	local newTween = TweenService:Create(instance, TweenInfo.new(duration, style, Enum.EasingDirection.Out), goal)
	newTween:Play()
	return newTween
end

local function cancelTweens()
	if volumeTween then
		volumeTween:Cancel()
	end
	if pitchTween then
		pitchTween:Cancel()
	end
end

-- Volume de cette écoute : plein après un long silence, réduit si le joueur enchaîne les rewinds.
local function nextVolume(): number
	local now = os.clock()
	if now - lastPlayClock <= Config.REWIND_SOUND_FATIGUE_WINDOW then
		fatigueRatio = math.max(fatigueRatio * Config.REWIND_SOUND_FATIGUE_FACTOR, Config.REWIND_SOUND_MIN_VOLUME_RATIO)
	else
		fatigueRatio = 1
	end
	lastPlayClock = now
	return Config.REWIND_SOUND_VOLUME * fatigueRatio
end

-- Lance le chœur pour un rewind de `duration` secondes.
function TimeLoopAudio.playRewind(duration: number)
	if Config.REWIND_SOUND_ID == "" then
		return
	end
	cancelTweens()

	sound.PlaybackSpeed = random:NextNumber(SPEED_MIN, SPEED_MAX)
	sound.TimePosition = if sound.IsLoaded then random:NextNumber(0, sound.TimeLength * MAX_START_RATIO) else 0
	sound.Volume = 0
	pitchShift.Octave = random:NextNumber(START_OCTAVE_MIN, START_OCTAVE_MAX)
	sound:Play()

	volumeTween = tween(sound, FADE_IN, Enum.EasingStyle.Sine, { Volume = nextVolume() })
	-- La hauteur s'effondre pendant que le temps recule : c'est le son qui "se déforme".
	pitchTween = tween(pitchShift, duration, Enum.EasingStyle.Quad, { Octave = Config.REWIND_SOUND_END_OCTAVE })
end

-- Fondu de sortie, à la fin du rembobinage. Le son s'arrête une fois devenu inaudible.
function TimeLoopAudio.fadeOut()
	if not sound.IsPlaying then
		return
	end
	if volumeTween then
		volumeTween:Cancel()
	end

	local fadeTween = tween(sound, Config.REWIND_SOUND_FADE_OUT, Enum.EasingStyle.Sine, { Volume = 0 })
	volumeTween = fadeTween
	fadeTween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and volumeTween == fadeTween then
			sound:Stop()
		end
	end)
end

return TimeLoopAudio
