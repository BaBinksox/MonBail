-- Audio (simulation, hors Roblox) : une seule musique à la fois, fondus, priorité du créateur,
-- musique de région, volumes du joueur, chœur du rembobinage sans doublon.
-- Les ID ci-dessous sont des valeurs FACTICES posées en mémoire pour exercer le code : elles ne
-- sont jamais écrites dans AudioConfig (où les champs restent vides tant qu'aucune piste n'est choisie).
local H = require("./helpers")()
local mock, runtime, env = H.mock, H.runtime, H.env

H.boot()
local AudioConfig = H.shared("Audio/AudioConfig")
for key, track in pairs(AudioConfig.TRACKS) do
	track.id = "rbxassetid://test-" .. key
end
AudioConfig.REWIND_CHOIR.id = "rbxassetid://test-choir"

local player = runtime.addPlayer("Mélodie", 7301)
local C = require("./client")(mock, runtime, player)
local scripts = {}
for path, _ in pairs(env.instances) do
	local inst = env.instances[path]
	if string.find(path, "^StarterPlayer/StarterPlayerScripts/Client/") and rawget(inst, "ClassName") == "LocalScript" then
		table.insert(scripts, path)
	end
end
table.sort(scripts)
for _, path in ipairs(scripts) do
	mock.task.spawn(function()
		env.run(path)
	end)
end
H.advance(1)
local _ = C
local SoundService = mock.game:GetService("SoundService")
local MusicDirector = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/MusicDirector")
local AudioMixer = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/AudioMixer")

local function musicSounds()
	local list = {}
	for _, child in ipairs(SoundService:GetChildren()) do
		if string.find(child.Name, "^Music_") then
			table.insert(list, child)
		end
	end
	return list
end
local function audible()
	local count, names = 0, {}
	for _, sound in ipairs(musicSounds()) do
		if sound.Volume > 0.001 and sound.IsPlaying then
			count += 1
			table.insert(names, sound.Name)
		end
	end
	return count, table.concat(names, ",")
end

print("== Créateur")
runtime.spawnCharacter(player)
H.advance(12) -- le simulateur applique la fin d'un fondu à son terme (fondu d'entrée : 4 s)
H.check("musique du créateur demandée", MusicDirector.getCurrentKey() == "creator", MusicDirector.getCurrentKey())
local count, names = audible()
H.check("une seule musique audible", count == 1, names)
local creatorSound = SoundService:FindFirstChild("Music_creator")
local plays = creatorSound and creatorSound.PlayCount or 0
H.check("musique du créateur dans le groupe Music", creatorSound ~= nil and creatorSound.SoundGroup == AudioMixer.group("Music"))
MusicDirector.set("override", "creator") -- changer de page = redemander la même piste
H.advance(1)
H.check("redemander la piste ne la relance pas", creatorSound.PlayCount == plays, creatorSound.PlayCount)

print("== Validation : musique de région")
local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
AvatarRemotes.ApplyAvatar:FireServer(H.selection(1))
H.advance(16)
H.check("le créateur rend la main à la région", MusicDirector.getCurrentKey() == "overlook", MusicDirector.getCurrentKey())
count, names = audible()
H.check("une seule musique audible après le fondu", count == 1, names)
H.check("l'ancienne piste est détruite", SoundService:FindFirstChild("Music_creator") == nil)

H.teleport(player, H.anchorPosition("spawn_plaza"))
H.advance(12)
local key = MusicDirector.getCurrentKey()
H.check("place du village : musique du village (jour ou nuit)", key == "village" or key == "village_night", key)
count, names = audible()
H.check("toujours une seule musique audible", count == 1, names)

print("== Pistes vides = silence, sans erreur")
AudioConfig.TRACKS.village.id = ""
AudioConfig.TRACKS.village_night.id = ""
MusicDirector.set("region", nil)
H.advance(6)
MusicDirector.set("region", "village")
H.advance(6)
count, names = audible()
H.check("piste sans ID : silence", count == 0, names)

print("== Volumes du joueur")
local StateRemotes = H.shared("State/StateRemotes")
StateRemotes.UpdateSettings:FireServer({ music = 0.25, ambience = 0.5, sfx = 0 })
H.advance(3)
H.check("réglage Musique appliqué au groupe", math.abs(AudioMixer.getVolume("Music") - 0.25) < 1e-6, AudioMixer.getVolume("Music"))
H.check("réglage Ambiance appliqué", math.abs(AudioMixer.getVolume("Ambience") - 0.5) < 1e-6)
H.check("réglage Effets à 0", AudioMixer.getVolume("Sfx") == 0)
H.check("réglages enregistrés dans le profil", H.profile(player).settings.music == 0.25 and H.profile(player).settings.ambience == 0.5)

print("== Chœur du rembobinage")
local TimeLoopRemotes = H.shared("TimeLoop/TimeLoopRemotes")
local choir = SoundService:FindFirstChild("TimeLoopRewindChoir")
H.check("chœur créé, rangé dans Effets", choir ~= nil and choir.SoundGroup == AudioMixer.group("Sfx"))
TimeLoopRemotes.RewindStarted:FireClient(player, 4)
H.advance(0.3)
TimeLoopRemotes.RewindStarted:FireClient(player, 4)
H.advance(0.3)
H.check("deux rembobinages rapprochés : un seul chœur", choir.PlayCount == 1, choir.PlayCount)
H.advance(AudioConfig.REWIND_CHOIR.maxDuration + AudioConfig.REWIND_CHOIR.fadeOut + 0.5)
H.check("le chœur s'efface de lui-même (court)", choir.IsPlaying == false and choir.Volume < 0.001)
H.check("volume modéré", AudioConfig.REWIND_CHOIR.volume <= 0.4)
H.noNewErrors("audio sans erreur")
H.printWarnings()
H.finish()
