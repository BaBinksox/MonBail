--!strict
--[[
	CandidateResolver (ModuleScript, client)
	Pour un emplacement audio encore vide dans AudioConfig, essaie les candidats d'AudioCandidates
	(dans l'ordre, catégories de licence permises par AudioConfig.CANDIDATE_TRIAL) et retient le
	premier qui se charge vraiment pour cette expérience. Le résultat n'est qu'un ESSAI : il n'est
	jamais écrit dans AudioConfig, et la sortie le dit.

	API :
		CandidateResolver.musicId(key)  -> string?   "rbxassetid://…" si déjà trouvé ; sinon lance
		CandidateResolver.sfxId(name)   -> string?   la recherche (en tâche de fond) et rend nil
		CandidateResolver.choirId()     -> string?
		CandidateResolver.describe(kind, key) -> Candidate?  candidat retenu
		CandidateResolver.resolved:Connect(function(kind, key) end)  kind = "music" | "sfx" | "choir"
		CandidateResolver.isEnabled() -> boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local audioFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio")
local AudioConfig = require(audioFolder:WaitForChild("AudioConfig") :: ModuleScript)
local AudioCandidates = require(audioFolder:WaitForChild("AudioCandidates") :: ModuleScript)
local AudioAudit = require(audioFolder:WaitForChild("AudioAudit") :: ModuleScript)

-- Même forme que AudioCandidates.Candidate (le type exporté n'est pas visible à travers WaitForChild).
type Candidate = { id: string, name: string, provider: string, source: string, duration: number?, license: string, note: string? }
type State = { status: "pending" | "done", candidate: Candidate? }

local CandidateResolver = {}

local resolvedEvent = Instance.new("BindableEvent")
CandidateResolver.resolved = resolvedEvent.Event

local states: { [string]: State } = {}

function CandidateResolver.isEnabled(): boolean
	local trial = AudioConfig.CANDIDATE_TRIAL
	if not trial.enabled then
		return false
	end
	if not trial.studioOnly then
		return true
	end
	local isStudio = false
	pcall(function()
		isStudio = RunService:IsStudio()
	end)
	return isStudio
end

local function listFor(kind: string, key: string): { Candidate }
	if kind == "music" then
		return AudioCandidates.MUSIC[key] or {}
	elseif kind == "sfx" then
		return AudioCandidates.SFX[key] or {}
	end
	return AudioCandidates.REWIND_CHOIR
end

local function label(kind: string): string
	return if kind == "music" then "[Musique]" elseif kind == "choir" then "[Chœur]" else "[Son]"
end

local function resolve(kind: string, key: string, state: State)
	local trial = AudioConfig.CANDIDATE_TRIAL
	local tried: { string } = {}
	for _, candidate in listFor(kind, key) do
		if not (trial.licenses :: any)[candidate.license] then
			continue
		end
		local probe = AudioAudit.probe(candidate.id, trial.loadTimeout, false)
		if probe.loaded and AudioAudit.durationMatches(candidate, probe.timeLength, trial.durationTolerance) then
			state.candidate = candidate
			print(string.format(
				"%s %s : ESSAI de « %s » (%s, %s), chargé, %s. Droits et choix à confirmer (docs/MUSIQUE.md).",
				label(kind), key, candidate.name, candidate.id, candidate.provider, AudioAudit.formatTime(probe.timeLength)
			))
			break
		end
		local why = if probe.loaded then "durée " .. AudioAudit.formatTime(probe.timeLength) .. " ≠ " .. AudioAudit.formatTime(candidate.duration) else probe.reason
		table.insert(tried, candidate.id .. " (" .. why .. ")")
	end
	if state.candidate == nil and #tried > 0 then
		warn(string.format("%s %s : aucun candidat utilisable (%s) : silence.", label(kind), key, table.concat(tried, ", ")))
	end
	state.status = "done"
	if state.candidate then
		resolvedEvent:Fire(kind, key)
	end
end

local function idFor(kind: string, key: string): string?
	if not CandidateResolver.isEnabled() then
		return nil
	end
	local stateKey = kind .. ":" .. key
	local state = states[stateKey]
	if state == nil then
		local newState: State = { status = "pending", candidate = nil }
		states[stateKey] = newState
		task.spawn(resolve, kind, key, newState)
		state = newState
	end
	local candidate = state.candidate
	return if candidate then "rbxassetid://" .. candidate.id else nil
end

function CandidateResolver.musicId(key: string): string?
	return idFor("music", key)
end

function CandidateResolver.sfxId(name: string): string?
	return idFor("sfx", name)
end

function CandidateResolver.choirId(): string?
	return idFor("choir", "rewind")
end

function CandidateResolver.describe(kind: string, key: string): Candidate?
	local state = states[kind .. ":" .. key]
	return if state then state.candidate else nil
end

-- Lance d'avance la recherche des emplacements vides (musiques, chœur, effets) pour qu'ils soient
-- prêts quand le jeu les demande.
function CandidateResolver.prewarm()
	if not CandidateResolver.isEnabled() then
		return
	end
	for key, track in AudioConfig.TRACKS do
		if track.id == "" and AudioCandidates.MUSIC[key] then
			idFor("music", key)
		end
	end
	if AudioConfig.REWIND_CHOIR.id == "" then
		idFor("choir", "rewind")
	end
	for name, spec in AudioConfig.SFX do
		if spec.id == "" and AudioCandidates.SFX[name] then
			idFor("sfx", name)
		end
	end
end

-- Tests : oublie les résultats.
function CandidateResolver.reset()
	states = {}
end

return CandidateResolver
