--!strict
--[[
	AudioAudit (ModuleScript partagé)
	Vérifie DANS ROBLOX ce que la recherche web n'a pas pu vérifier : est-ce que chaque ID
	d'AudioCandidates se charge pour cette expérience, quelle est sa durée réelle, et sous quel nom
	et quel créateur Roblox l'a enregistré. Rien n'est écrit dans AudioConfig automatiquement.

	Dans Studio, barre de commande (mode édition ou pendant un Play) :
		local A = require(game.ReplicatedStorage.Shared.Audio.AudioAudit)
		A.run()                    -- teste tout, imprime un rapport (prend quelques secondes)
		A.listen("creator", 2)     -- écoute le 2e candidat du créateur ; A.listen("sfx:dodge")
		A.stop()                   -- coupe l'écoute
		A.snippet()                -- après run() : lignes à recopier dans AudioConfig pour les
		                              pistes qui se chargent ET que vous avez acceptées à l'écoute
		                              (sans les téléversements de particuliers ; A.snippet(true) les inclut)

	Utilisé aussi par CandidateResolver (client) pour l'essai automatique en jeu.
]]

local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")

local AudioCandidates = require(script.Parent:WaitForChild("AudioCandidates") :: ModuleScript)
local AudioConfig = require(script.Parent:WaitForChild("AudioConfig") :: ModuleScript)

-- Même forme que AudioCandidates.Candidate (le type exporté n'est pas visible à travers WaitForChild).
type Candidate = { id: string, name: string, provider: string, source: string, duration: number?, license: string, note: string? }

export type Probe = {
	id: string,
	loaded: boolean,
	reason: string, -- "ok", "échec du chargement", "délai dépassé"…
	timeLength: number, -- durée réelle (s), 0 si non chargé
	assetName: string?, -- nom enregistré chez Roblox (si disponible)
	creator: string?, -- créateur enregistré chez Roblox
	isAudio: boolean?, -- type d'asset Audio
}

export type Entry = {
	group: string, -- "creator", "choir", "sfx:dodge"…
	index: number,
	candidate: Candidate,
	probe: Probe?,
}

local AudioAudit = {}

AudioAudit.results = {} :: { Entry }

local ASSET_TYPE_AUDIO = 3

local function probeFolder(): Folder
	local folder = SoundService:FindFirstChild("AudioProbe")
	if folder == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "AudioProbe"
		newFolder.Archivable = false -- jamais enregistré dans la place
		newFolder.Parent = SoundService
		folder = newFolder
	end
	return folder :: Folder
end

local function contentId(id: string): string
	return if string.find(id, "^rbxasset") then id else "rbxassetid://" .. id
end

-- Nom et créateur enregistrés chez Roblox (facultatif : un échec n'empêche pas le test).
function AudioAudit.info(id: string): (string?, string?, boolean?)
	local numeric = tonumber(id)
	if numeric == nil then
		return nil, nil, nil
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(numeric, Enum.InfoType.Asset)
	end)
	if not ok or type(info) ~= "table" then
		return nil, nil, nil
	end
	local creator = if type(info.Creator) == "table" then info.Creator.Name else nil
	return info.Name, creator, info.AssetTypeId == ASSET_TYPE_AUDIO
end

-- Charge un son et attend son chargement (au plus `timeout` secondes). Ne le joue pas.
function AudioAudit.probe(id: string, timeout: number?, withInfo: boolean?): Probe
	local limit = timeout or 8
	local sound = Instance.new("Sound")
	sound.Name = "Probe_" .. id
	sound.SoundId = contentId(id)
	sound.Volume = 0
	sound.Parent = probeFolder()

	local fetchFailed = false
	pcall(function()
		ContentProvider:PreloadAsync({ sound }, function(_assetId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				fetchFailed = true
			end
		end)
	end)
	local waited = 0
	while not fetchFailed and not sound.IsLoaded and waited < limit do
		task.wait(0.1)
		waited += 0.1
	end
	local loaded = not fetchFailed and sound.IsLoaded and sound.TimeLength > 0
	local result: Probe = {
		id = id,
		loaded = loaded,
		reason = if loaded then "ok" elseif fetchFailed then "échec du chargement (privé, supprimé ou ID inconnu)" else "délai dépassé",
		timeLength = if loaded then sound.TimeLength else 0,
	}
	sound:Destroy()
	if withInfo then
		result.assetName, result.creator, result.isAudio = AudioAudit.info(id)
	end
	return result
end

-- La durée réelle correspond-elle à celle annoncée par la source ? (nil = pas de durée annoncée)
function AudioAudit.durationMatches(candidate: Candidate, timeLength: number, tolerance: number?): boolean
	local expected = candidate.duration
	if expected == nil then
		return true
	end
	local margin = math.max(expected * (tolerance or 0.2), 5)
	return math.abs(timeLength - expected) <= margin
end

local function formatTime(seconds: number?): string
	if seconds == nil or seconds <= 0 then
		return "?"
	end
	local total = math.floor(seconds + 0.5)
	return string.format("%d:%02d", total // 60, total % 60)
end
AudioAudit.formatTime = formatTime

-- Tous les candidats, dans un ordre stable : musiques, chœur, effets.
function AudioAudit.entries(): { Entry }
	local list: { Entry } = {}
	local groups: { string } = {}
	for key in AudioCandidates.MUSIC do
		table.insert(groups, key)
	end
	table.sort(groups)
	for _, key in groups do
		for index, candidate in AudioCandidates.MUSIC[key] do
			table.insert(list, { group = key, index = index, candidate = candidate })
		end
	end
	for index, candidate in AudioCandidates.REWIND_CHOIR do
		table.insert(list, { group = "choir", index = index, candidate = candidate })
	end
	local sfxNames: { string } = {}
	for name in AudioCandidates.SFX do
		table.insert(sfxNames, name)
	end
	table.sort(sfxNames)
	for _, name in sfxNames do
		for index, candidate in AudioCandidates.SFX[name] do
			table.insert(list, { group = "sfx:" .. name, index = index, candidate = candidate })
		end
	end
	local altNames: { string } = {}
	for name in AudioCandidates.SFX_ALTERNATIVES do
		table.insert(altNames, name)
	end
	table.sort(altNames)
	for _, name in altNames do
		for index, candidate in AudioCandidates.SFX_ALTERNATIVES[name] do
			table.insert(list, { group = "alt:" .. name, index = index, candidate = candidate })
		end
	end
	-- Sons livrés avec Roblox utilisés par AudioConfig : on vérifie qu'ils existent bien.
	local builtinNames: { string } = {}
	for name, spec in AudioConfig.SFX do
		if string.find(spec.id, "^rbxasset://") then
			table.insert(builtinNames, name)
		end
	end
	table.sort(builtinNames)
	for _, name in builtinNames do
		local spec = AudioConfig.SFX[name]
		table.insert(list, {
			group = "builtin:" .. name,
			index = 1,
			candidate = { id = spec.id, name = name, provider = "Roblox (son livré avec le client)", source = "installation Roblox", duration = nil, license = "builtin" },
		})
	end
	return list
end

local function find(group: string, index: number?): Candidate?
	local list: { Candidate }? = nil
	if group == "choir" then
		list = AudioCandidates.REWIND_CHOIR
	elseif string.sub(group, 1, 4) == "sfx:" then
		list = AudioCandidates.SFX[string.sub(group, 5)]
	elseif string.sub(group, 1, 4) == "alt:" then
		list = AudioCandidates.SFX_ALTERNATIVES[string.sub(group, 5)]
	else
		list = AudioCandidates.MUSIC[group]
	end
	if list == nil then
		return nil
	end
	return list[index or 1]
end

local function report(entries: { Entry })
	print("==== AudioAudit : " .. #entries .. " candidats (" .. AudioCandidates.STATUS .. " avant ce test) ====")
	for _, entry in entries do
		local candidate = entry.candidate
		local probe = entry.probe
		local line
		if probe == nil then
			line = "non testé"
		elseif probe.loaded then
			local durationNote = if candidate.duration == nil
				then ""
				elseif AudioAudit.durationMatches(candidate, probe.timeLength) then " (= source)"
				else " (SOURCE : " .. formatTime(candidate.duration) .. " → autre piste ?)"
			line = "CHARGÉ " .. formatTime(probe.timeLength) .. durationNote
		else
			line = "ÉCHEC : " .. probe.reason
		end
		local registered = if probe and (probe.assetName or probe.creator)
			then string.format(" | Roblox : « %s » par %s%s", probe.assetName or "?", probe.creator or "?", if probe.isAudio == false then " (PAS un audio)" else "")
			else ""
		print(string.format("[%s #%d] %s — « %s » (%s, licence %s) : %s%s", entry.group, entry.index, candidate.id, candidate.name, candidate.provider, candidate.license, line, registered))
	end
	print("==== Fin. Écoutez les pistes chargées : AudioAudit.listen(\"<contexte>\", n). ====")
end

-- Teste tous les candidats (4 à la fois) puis imprime le rapport. Rend la main tout de suite ;
-- `onDone` reçoit la liste quand tout est fini.
function AudioAudit.run(onDone: ((entries: { Entry }) -> ())?)
	local entries = AudioAudit.entries()
	AudioAudit.results = entries
	print("[AudioAudit] Test de " .. #entries .. " identifiants en cours…")
	task.spawn(function()
		local nextIndex = 0
		local running = 0
		local function worker()
			running += 1
			while true do
				nextIndex += 1
				local entry = entries[nextIndex]
				if entry == nil then
					break
				end
				entry.probe = AudioAudit.probe(entry.candidate.id, 10, true)
			end
			running -= 1
		end
		for _ = 1, 4 do
			task.spawn(worker)
		end
		while running > 0 do
			task.wait(0.2)
		end
		report(entries)
		if onDone then
			onDone(entries)
		end
	end)
end

local listening: Sound? = nil

function AudioAudit.stop()
	local sound = listening
	if sound then
		sound:Stop()
		sound:Destroy()
		listening = nil
	end
end

-- Écoute un candidat (dans Studio, même en mode édition).
function AudioAudit.listen(group: string, index: number?)
	AudioAudit.stop()
	local candidate = find(group, index)
	if candidate == nil then
		warn("[AudioAudit] Aucun candidat « " .. group .. " » n°" .. tostring(index or 1))
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Listen_" .. candidate.id
	sound.SoundId = contentId(candidate.id)
	sound.Volume = 0.5
	sound.Parent = probeFolder()
	listening = sound
	print(string.format("[AudioAudit] Écoute : « %s » (%s), %s — AudioAudit.stop() pour couper.", candidate.name, candidate.id, candidate.provider))
	local played = pcall(function()
		SoundService:PlayLocalSound(sound) -- fonctionne aussi en mode édition
	end)
	if not played then
		sound:Play()
	end
end

-- Lignes à recopier dans AudioConfig : premier candidat CHARGÉ de chaque contexte (après run()).
-- À n'utiliser que pour les pistes écoutées et acceptées.
-- Les téléversements de particuliers (licence "user") sont exclus sauf `includeUser` : leur
-- disponibilité ne dit rien des droits ; il faut l'accord de leur auteur.
function AudioAudit.snippet(includeUser: boolean?)
	if #AudioAudit.results == 0 or AudioAudit.results[1].probe == nil then
		warn("[AudioAudit] Lancez d'abord AudioAudit.run() et attendez le rapport.")
		return
	end
	local seen: { [string]: boolean } = {}
	local skippedUser = 0
	print("---- À recopier dans src/shared/Audio/AudioConfig.luau (remplacer le \"\" de la ligne indiquée) ----")
	for _, entry in AudioAudit.results do
		local probe = entry.probe
		local allowed = includeUser == true or entry.candidate.license ~= "user"
		local prefix = string.sub(entry.group, 1, 4)
		if entry.candidate.license == "builtin" or prefix == "alt:" then
			continue -- déjà en place (son livré) ou simple alternative à écouter
		elseif probe and probe.loaded and not allowed then
			skippedUser += 1
		elseif probe and probe.loaded and not seen[entry.group] and AudioAudit.durationMatches(entry.candidate, probe.timeLength) then
			seen[entry.group] = true
			local where = if entry.group == "choir"
				then "REWIND_CHOIR.id"
				elseif string.sub(entry.group, 1, 4) == "sfx:" then "SFX." .. string.sub(entry.group, 5)
				else "TRACKS." .. entry.group
			print(string.format("%s = \"rbxassetid://%s\" -- « %s », %s, %s", where, entry.candidate.id, entry.candidate.name, entry.candidate.provider, formatTime(probe.timeLength)))
		end
	end
	if skippedUser > 0 then
		print(string.format("(%d téléversement(s) de particuliers chargé(s) mais omis : droits inconnus. AudioAudit.snippet(true) pour les voir.)", skippedUser))
	end
	print("---- Fin ----")
end

return AudioAudit
