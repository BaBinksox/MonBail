--!strict
--[[
	SfxPlayer (ModuleScript, client)
	Joue les effets sonores d'AudioConfig.SFX, rangés dans la catégorie « Effets » (AudioMixer) :
		- un ID vide = silence, sans erreur ;
		- les Sounds sont réutilisés (réserve par son), jamais recréés à chaque coup ;
		- minInterval et maxConcurrent empêchent les rafales (spam de coups, plusieurs joueurs) ;
		- `at` (Vector3 ou BasePart) : son spatialisé à cet endroit ; sinon son d'interface (2D).

	API : SfxPlayer.play(name, at?, options?) -> boolean   options : pitch, volume (multiplicateurs)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"):WaitForChild("AudioConfig") :: ModuleScript)
local AudioMixer = require(script.Parent:WaitForChild("AudioMixer") :: ModuleScript)

export type Options = { pitch: number?, volume: number? }

local MAX_DISTANCE = 140 -- au-delà, un son 3D n'est plus audible
local random = Random.new()

local SfxPlayer = {}

type Pool = { sounds: { Sound }, lastClock: number, holder: Attachment? }
local pools: { [string]: Pool } = {}
local anchorPart: Part? = nil

-- Une pièce invisible et ancrée qui porte les sons 3D (déplacés par Attachment).
local function getAnchorPart(): Part
	local existing = anchorPart
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "SfxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = workspace
	anchorPart = part
	return part
end

local function newSound(name: string, spec: any): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.RollOffMaxDistance = MAX_DISTANCE
	sound.RollOffMinDistance = 8
	AudioMixer.assign(sound, "Sfx")
	return sound
end

function SfxPlayer.play(name: string, at: (Vector3 | BasePart)?, options: Options?): boolean
	local spec = AudioConfig.SFX[name]
	if spec == nil or spec.id == "" then
		return false
	end
	local now = os.clock()
	local pool = pools[name]
	if pool == nil then
		pool = { sounds = {}, lastClock = -math.huge, holder = nil }
		pools[name] = pool
	end
	if now - pool.lastClock < spec.minInterval then
		return false
	end

	-- Une copie libre de la réserve, ou une nouvelle tant que la limite n'est pas atteinte.
	local sound: Sound? = nil
	for _, candidate in pool.sounds do
		if not candidate.IsPlaying then
			sound = candidate
			break
		end
	end
	if sound == nil then
		if #pool.sounds >= spec.maxConcurrent then
			return false
		end
		sound = newSound(name, spec)
		table.insert(pool.sounds, sound :: Sound)
	end
	local chosen = sound :: Sound
	pool.lastClock = now

	local opts: Options = options or {}
	if typeof(at) == "Vector3" or typeof(at) == "Instance" then
		local position = if typeof(at) == "Vector3" then at else (at :: BasePart).Position
		local attachment = chosen.Parent
		if attachment == nil or not attachment:IsA("Attachment") then
			local newAttachment = Instance.new("Attachment")
			newAttachment.Name = "SfxPoint"
			newAttachment.Parent = getAnchorPart()
			chosen.Parent = newAttachment
			attachment = newAttachment
		end
		(attachment :: Attachment).WorldPosition = position
	else
		chosen.Parent = SoundService
	end
	chosen.PlaybackSpeed = spec.pitch * (opts.pitch or 1) * (1 + random:NextNumber(-spec.pitchVariance, spec.pitchVariance))
	chosen.Volume = spec.volume * (opts.volume or 1)
	chosen.TimePosition = 0
	chosen:Play()
	return true
end

return SfxPlayer
