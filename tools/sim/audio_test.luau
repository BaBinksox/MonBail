-- Audio (simulation, hors Roblox) : une seule musique à la fois, fondus, priorité du créateur,
-- musique de région, volumes du joueur, chœur du rembobinage sans doublon.
-- Les ID ci-dessous sont des valeurs FACTICES posées en mémoire pour exercer le code : elles ne
-- sont jamais écrites dans AudioConfig (où les champs restent vides tant qu'aucune piste n'est choisie).
local H = require("./helpers")()
local mock, runtime, env = H.mock, H.runtime, H.env

H.boot()
local AudioConfig = H.shared("Audio/AudioConfig")
local AudioCandidates = H.shared("Audio/AudioCandidates")

print("== Candidats trouvés par recherche (données)")
do
	local candidateIds = {}
	local problems = {}
	local function scan(group, list)
		for index, candidate in ipairs(list) do
			local where = group .. " #" .. index
			if not string.match(candidate.id, "^%d+$") then table.insert(problems, where .. " : ID non numérique") end
			if candidate.name == "" or candidate.source == "" or candidate.provider == "" then table.insert(problems, where .. " : nom, fournisseur ou source manquant") end
			if not ({ roblox = true, store = true, range = true, user = true })[candidate.license] then table.insert(problems, where .. " : licence inconnue") end
			candidateIds[candidate.id] = true
		end
	end
	local musicContexts = 0
	for key, list in pairs(AudioCandidates.MUSIC) do
		musicContexts += 1
		if AudioConfig.TRACKS[key] == nil then table.insert(problems, key .. " : pas de piste de ce nom dans AudioConfig") end
		scan(key, list)
	end
	for name, list in pairs(AudioCandidates.SFX) do
		if AudioConfig.SFX[name] == nil then table.insert(problems, name .. " : pas d'effet de ce nom dans AudioConfig") end
		if AudioConfig.SFX[name] and AudioConfig.SFX[name].id ~= "" then table.insert(problems, name .. " : candidats pour un effet déjà rempli") end
		scan("sfx:" .. name, list)
	end
	scan("choir", AudioCandidates.REWIND_CHOIR)
	H.check("candidats bien formés (ID numérique, nom, source, licence)", #problems == 0, table.concat(problems, " ; "))
	H.check("13 contextes musicaux couverts", musicContexts == 13, musicContexts)
	-- Rien d'invérifié n'est écrit dans la configuration : les candidats restent à part.
	local written = {}
	for key, track in pairs(AudioConfig.TRACKS) do
		if candidateIds[(track.id:match("(%d+)$") or "")] then table.insert(written, key) end
	end
	for name, spec in pairs(AudioConfig.SFX) do
		if candidateIds[(spec.id:match("(%d+)$") or "")] then table.insert(written, name) end
	end
	if candidateIds[(AudioConfig.REWIND_CHOIR.id:match("(%d+)$") or "")] then table.insert(written, "choir") end
	H.check("aucun candidat non vérifié recopié dans AudioConfig", #written == 0, table.concat(written, ","))
	H.check("les anciennes pistes écartées ne reviennent pas", not candidateIds["1839911004"] and not candidateIds["9125602726"])
end

-- Essai des candidats coupé pour les tests de mixage ci-dessous (testé à la fin).
AudioConfig.CANDIDATE_TRIAL.enabled = false
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
local choirPeak = choir.Volume
TimeLoopRemotes.RewindStarted:FireClient(player, 4)
H.advance(0.3)
H.check("deux rembobinages rapprochés : un seul chœur", choir.PlayCount == 1, choir.PlayCount)
H.check("chœur : environ +3 dB par rapport à l'ancien réglage (0,32)", math.abs(choirPeak - 0.32 * 10 ^ (3 / 20)) < 0.01, choirPeak)
H.check("chœur : sous le plafond", choirPeak <= AudioConfig.REWIND_CHOIR.maxVolume and AudioConfig.REWIND_CHOIR.maxVolume <= 0.6)
H.check("curseur Effets à 0 : le groupe du chœur est muet", AudioMixer.getVolume("Sfx") == 0 and choir.SoundGroup == AudioMixer.group("Sfx"))
H.advance(AudioConfig.REWIND_CHOIR.maxDuration + AudioConfig.REWIND_CHOIR.fadeOut + 0.5)
H.check("le chœur s'efface de lui-même (court)", choir.IsPlaying == false and choir.Volume < 0.001)
H.check("volume modéré (plafond)", AudioConfig.REWIND_CHOIR.volume <= AudioConfig.REWIND_CHOIR.maxVolume)

print("== Musique dynamique de combat")
local ResourceService = H.server("Combat/ResourceService")
local ResourceConfig = H.shared("Combat/ResourceConfig")
AudioConfig.TRACKS.village.id = "rbxassetid://test-village"
AudioConfig.TRACKS.village_night.id = "rbxassetid://test-village_night"
StateRemotes.UpdateSettings:FireServer({ music = 1, ambience = 1, sfx = 1 })
MusicDirector.set("region", nil) -- les ID viennent d'être posés : la région redemande sa piste
H.advance(8)
local regionKey = MusicDirector.getCurrentKey()
H.check("exploration : musique de région", regionKey == "village" or regionKey == "village_night", regionKey)
local regionSound = SoundService:FindFirstChild("Music_" .. tostring(regionKey))
if regionSound then
	regionSound.TimePosition = 42
end
local CM = AudioConfig.COMBAT_MUSIC
local function fight(seconds)
	local elapsed = 0
	while elapsed < seconds do
		ResourceService.markCombat(player) -- comme un coup donné ou reçu, vu par le serveur
		H.advance(0.5)
		elapsed += 0.5
	end
end
fight(1.5)
H.check("en combat (état du serveur) : musique de combat", MusicDirector.getCurrentKey() == "combat", MusicDirector.getCurrentKey())
fight(5)
count, names = audible()
H.check("une seule musique audible en combat", count == 1, names)
H.advance(ResourceConfig.COMBAT_TIMEOUT + 1)
H.check("hystérésis : la musique de combat tient encore un instant après l'état serveur", MusicDirector.getCurrentKey() == "combat", MusicDirector.getCurrentKey())
H.advance(CM.COMBAT_EXIT_TIME + 1)
H.check("fin du combat : retour à la région", MusicDirector.getCurrentKey() == regionKey, MusicDirector.getCurrentKey())
local resumed = SoundService:FindFirstChild("Music_" .. tostring(regionKey))
H.check("la musique d'exploration reprend où elle en était (pas de redémarrage)", resumed ~= nil and resumed.TimePosition >= 40, resumed and resumed.TimePosition)
H.advance(6)
count, names = audible()
H.check("jamais deux musiques à plein volume", count == 1, names)
TimeLoopRemotes.AnomalyOpened:FireClient(player, 5)
H.advance(0.3)
H.check("anomalie : musique d'anomalie prioritaire", MusicDirector.getCurrentKey() == "anomaly", MusicDirector.getCurrentKey())
H.check("anomalie : bouton tactile « Rembobiner » proposé", C.actions.RewindTouch ~= nil)
fight(1.5)
H.check("l'anomalie passe avant le combat", MusicDirector.getCurrentKey() == "anomaly")
TimeLoopRemotes.AnomalyClosed:FireClient(player)
fight(1)
H.check("anomalie refermée : bouton de rembobinage retiré", C.actions.RewindTouch == nil)
H.check("anomalie refermée : retour au combat en cours", MusicDirector.getCurrentKey() == "combat", MusicDirector.getCurrentKey())
-- Victoire : un ennemi proche (factice, sans IA) vaincu pendant le combat.
local foe = mock.Instance.new("Model")
foe.Name = "EnnemiFactice"
local foeHumanoid = mock.Instance.new("Humanoid")
foeHumanoid.MaxHealth = 100
foeHumanoid.Health = 100
foeHumanoid.Parent = foe
local foeRoot = mock.Instance.new("Part")
foeRoot.Name = "HumanoidRootPart"
foeRoot.Parent = foe
foe.PrimaryPart = foeRoot
foeRoot.CFrame = mock.CFrame.new(H.root(player).Position + mock.Vector3.new(0, 0, 10))
foe.Parent = mock.workspace
mock.game:GetService("CollectionService"):AddTag(foe, "TimeLoopEntity")
fight(1.5)
foe:SetAttribute("Defeated", true)
H.advance(ResourceConfig.COMBAT_TIMEOUT + CM.COMBAT_EXIT_TIME + 1)
H.check("fin d'un combat gagné : phrase de victoire", MusicDirector.getCurrentKey() == "victory", MusicDirector.getCurrentKey())
local victorySound = SoundService:FindFirstChild("Music_victory")
H.check("la victoire est jouée une fois (non bouclée)", victorySound ~= nil and victorySound.Looped == false)
foe:Destroy()
H.advance(CM.VICTORY_DURATION + 1)
local after = MusicDirector.getCurrentKey()
H.check("après la victoire : calme (région) ou présence hostile", after ~= "victory" and after ~= "combat", after)
AudioConfig.TRACKS.combat.id = ""
fight(1.5)
H.advance(6)
count, names = audible()
H.check("piste de combat vide : silence, sans erreur", count == 0, names)

print("== Essai des candidats (Studio)")
local CandidateResolver = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/CandidateResolver")
local SfxPlayer = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/SfxPlayer")
local function printed(pattern)
	for _, line in ipairs(runtime.prints) do
		if string.find(line, pattern) then return line end
	end
	return nil
end
local function preloaded(id)
	return mock.preloadedIds and mock.preloadedIds[id] == true
end
AudioConfig.CANDIDATE_TRIAL.enabled = true
CandidateResolver.reset()
-- Le premier candidat du combat ne se charge pas (privé) : le suivant prend le relais.
mock.failingAssets["1836089842"] = true
CandidateResolver.musicId("combat") -- en jeu : CandidateResolver.prewarm() au démarrage
fight(1.5)
H.advance(2)
local combatSound = SoundService:FindFirstChild("Music_combat")
H.check("ID qui ne se charge pas : candidat suivant essayé", combatSound ~= nil and combatSound.SoundId == "rbxassetid://1837779548", combatSound and combatSound.SoundId)
H.check("l'essai est annoncé comme tel dans la sortie", printed("%[Musique%] combat : ESSAI") ~= nil)
if combatSound then
	combatSound.TimePosition = 3 -- la simulation n'avance pas la lecture d'elle-même
end
H.advance(AudioConfig.CANDIDATE_TRIAL.playCheckDelay + 0.5)
H.check("lecture réelle confirmée dans la sortie", printed("LECTURE CONFIRMÉE : combat") ~= nil)
count, names = audible()
H.check("toujours une seule musique audible avec un candidat", count == 1, names)
H.advance(ResourceConfig.COMBAT_TIMEOUT + CM.COMBAT_EXIT_TIME + CM.VICTORY_DURATION + 2)

-- Durée annoncée par la source ≠ durée réelle : l'ID désigne sans doute une autre piste, écarté.
mock.assetLengths["1843286166"] = 123 -- « Tears Of Sorrow » : 2:03 annoncé
local creatorId = nil
CandidateResolver.musicId("creator")
H.advance(1)
creatorId = CandidateResolver.musicId("creator")
H.check("durée différente de la source : candidat écarté, suivant retenu", creatorId == "rbxassetid://1843286166", creatorId)

-- Téléversements de particuliers (droits inconnus) : jamais essayés par défaut.
mock.failingAssets["1837779548"] = true
CandidateResolver.musicId("boss")
H.advance(1)
H.check("boss : aucun candidat utilisable = silence", CandidateResolver.musicId("boss") == nil)
H.check("les téléversements « user » ne sont pas même chargés", not preloaded("87773547872492") and not preloaded("78744747224727"))
H.check("silence signalé dans la sortie", (function()
	for _, line in ipairs(runtime.warnings) do
		if string.find(line, "boss : aucun candidat utilisable") then return true end
	end
	return false
end)())

-- Effets et chœur.
-- Un effet vide (garde) dont les candidats sont des téléversements : essayés seulement si autorisé.
SfxPlayer.play("swordBlocked")
H.advance(1)
H.check("téléversements « user » non essayés par défaut (effet vide reste muet)", SfxPlayer.play("swordBlocked") == false)
AudioConfig.CANDIDATE_TRIAL.licenses.user = true
CandidateResolver.reset()
SfxPlayer.play("swordBlocked")
H.advance(1)
H.check("effet vide : candidat d'essai joué une fois autorisé", SfxPlayer.play("swordBlocked") == true)
local blockedSound = SoundService:FindFirstChild("Sfx_swordBlocked")
H.check("le son de garde utilise le premier candidat", blockedSound ~= nil and blockedSound.SoundId == "rbxassetid://7058511334", blockedSound and blockedSound.SoundId)
AudioConfig.CANDIDATE_TRIAL.licenses.user = false
H.advance(1)
-- Sons des magies : un son distinct (fichier ou hauteur) pour chaque magie, tous rangés dans Effets.
do
	local signatures, missing = {}, {}
	for _, magicId in ipairs({ "pyromancy", "ice", "lightning", "shadow", "antimatter", "gravity" }) do
		local cast, impact = AudioConfig.SFX["cast_" .. magicId], AudioConfig.SFX["impact_" .. magicId]
		if cast.id == "" or impact.id == "" then table.insert(missing, magicId) end
		signatures[cast.id .. "@" .. cast.pitch] = (signatures[cast.id .. "@" .. cast.pitch] or 0) + 1
		signatures[impact.id .. "@" .. impact.pitch] = (signatures[impact.id .. "@" .. impact.pitch] or 0) + 1
	end
	local duplicates = 0
	for _, n in pairs(signatures) do if n > 1 then duplicates += 1 end end
	H.check("chaque magie a un son de lancement et d'impact", #missing == 0, table.concat(missing, ","))
	H.check("aucun son de magie identique à un autre (fichier + hauteur)", duplicates == 0, duplicates)
	local loud = {}
	for name, spec in pairs(AudioConfig.SFX) do
		if spec.volume > 0.75 or spec.pitch * (1 + spec.pitchVariance) > 1.7 then table.insert(loud, name) end
	end
	H.check("mixage : aucun effet trop fort ni trop aigu", #loud == 0, table.concat(loud, ","))
	SfxPlayer.play("impact_ice")
	local iceSound = SoundService:FindFirstChild("Sfx_impact_ice")
	H.check("son de magie rangé dans le groupe Effets", iceSound ~= nil and iceSound.SoundGroup == AudioMixer.group("Sfx"))
end
AudioConfig.REWIND_CHOIR.id = ""
H.advance(1)
TimeLoopRemotes.RewindStarted:FireClient(player, 4)
H.advance(1)
TimeLoopRemotes.RewindStarted:FireClient(player, 4)
H.advance(0.5)
H.check("chœur vide : candidat d'essai", choir.SoundId == "rbxassetid://1840524246", choir.SoundId)

-- Hors Studio (studioOnly) : aucun essai, le jeu publié reste fidèle à AudioConfig.
local RunService = mock.game:GetService("RunService")
local isStudio = RunService.IsStudio
RunService.IsStudio = function() return false end
CandidateResolver.reset()
H.check("jeu publié : aucun candidat essayé", CandidateResolver.musicId("lake") == nil)
H.advance(1)
H.check("jeu publié : toujours rien après attente", CandidateResolver.musicId("lake") == nil)
RunService.IsStudio = isStudio

print("== Outil de vérification Studio (AudioAudit)")
local AudioAudit = H.shared("Audio/AudioAudit")
mock.assetInfo["1838577168"] = { Name = "Sad Story (Piano & Harp)", Creator = { Name = "Roblox" }, AssetTypeId = 3 }
local finished = nil
AudioAudit.run(function(entries) finished = entries end)
H.advance(30)
local total = #AudioCandidates.REWIND_CHOIR
for _, list in pairs(AudioCandidates.MUSIC) do total += #list end
for _, list in pairs(AudioCandidates.SFX) do total += #list end
for _, list in pairs(AudioCandidates.SFX_ALTERNATIVES) do total += #list end
for _, spec in pairs(AudioConfig.SFX) do
	if string.find(spec.id, "^rbxasset://") then total += 1 end -- sons livrés avec Roblox, vérifiés aussi
end
H.check("AudioAudit.run teste chaque candidat", finished ~= nil and #finished == total, finished and #finished)
local failedEntry, infoLine = nil, nil
for _, entry in ipairs(finished or {}) do
	if entry.candidate.id == "1836089842" then failedEntry = entry end
end
H.check("un ID qui ne se charge pas est signalé en échec", failedEntry ~= nil and failedEntry.probe and failedEntry.probe.loaded == false)
H.check("le rapport montre le nom et le créateur enregistrés chez Roblox", printed("« Sad Story %(Piano & Harp%) » par Roblox") ~= nil)
H.check("le rapport signale une durée qui ne correspond pas à la source", printed("autre piste %?") ~= nil)
AudioAudit.snippet()
H.check("snippet : ligne prête à recopier pour un candidat chargé", printed('TRACKS.creator = "rbxassetid://1843286166"') ~= nil)
H.check("snippet : téléversements de particuliers omis par défaut", printed("téléversement%(s%) de particuliers chargé") ~= nil)
H.check("snippet : rien pour un contexte sans candidat chargé", printed("TRACKS.boss = ") == nil)
AudioAudit.listen("creator", 2)
AudioAudit.stop()
print("== Jeu publié : une piste inscrite dans AudioConfig joue hors Studio")
do
	local RunServiceMock = mock.game:GetService("RunService")
	local wasStudio = RunServiceMock.IsStudio
	RunServiceMock.IsStudio = function() return false end
	CandidateResolver.reset()
	AudioConfig.TRACKS.creator.id = "rbxassetid://123450001" -- valeur factice, en mémoire seulement
	MusicDirector.set("override", nil)
	H.advance(4)
	MusicDirector.set("override", "creator")
	H.advance(6)
	local published = SoundService:FindFirstChild("Music_creator")
	H.check("jeu publié : la piste approuvée (AudioConfig) est jouée", published ~= nil and published.SoundId == "rbxassetid://123450001" and published.IsPlaying, published and published.SoundId)
	AudioConfig.TRACKS.creator.id = ""
	MusicDirector.set("override", nil)
	H.advance(4)
	MusicDirector.set("override", "creator")
	H.advance(4)
	H.check("jeu publié : sans piste approuvée, silence (aucun candidat d'essai)", SoundService:FindFirstChild("Music_creator") == nil or not SoundService:FindFirstChild("Music_creator").IsPlaying)
	MusicDirector.set("override", nil)
	RunServiceMock.IsStudio = wasStudio
	H.advance(4)
end

print("== Ultimes : un seul son d'impact chacun (pas de superposition)")
do
	local CombatRemotes = H.shared("Combat/CombatRemotes")
	local function plays(name)
		local n = 0
		for _, d in ipairs(mock.game:GetDescendants()) do
			if rawget(d, "ClassName") == "Sound" and d.Name == name then n += d.PlayCount or 0 end
		end
		return n
	end
	local doubled = {}
	for _, magicId in ipairs({ "ice", "antimatter", "pyromancy", "lightning", "shadow", "gravity" }) do
		local before = plays("Sfx_impact_" .. magicId)
		CombatRemotes.UltimateFired:FireClient(player, player.Character, H.root(player).Position, {}, magicId)
		H.advance(3)
		local count = plays("Sfx_impact_" .. magicId) - before
		if count ~= 1 then table.insert(doubled, magicId .. "=" .. count) end
	end
	H.check("chaque ultime joue son impact une seule fois", #doubled == 0, table.concat(doubled, ","))
end

print("== Réglages audio conservés après reconnexion")
do
	StateRemotes.UpdateSettings:FireServer({ music = 0.4, ambience = 0.6, sfx = 0.7 })
	H.advance(2)
	local userId = player.UserId
	H.leave(player)
	local again = H.join("Mélodie", userId)
	local settings = H.profile(again).settings
	H.check("musique, ambiance et effets retrouvés à la reconnexion", settings.music == 0.4 and settings.ambience == 0.6 and settings.sfx == 0.7, string.format("%s/%s/%s", tostring(settings.music), tostring(settings.ambience), tostring(settings.sfx)))
end
H.noNewErrors("audio sans erreur")
H.printWarnings()
H.finish()
