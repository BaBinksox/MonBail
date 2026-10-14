--!strict
--[[
	SwingAnimator
	Joue l'animation d'un coup d'épée avec le système officiel de Roblox :
	une instance Animation, chargée sur l'Animator du Humanoid, puis Play().

	À n'appeler que pour le personnage du joueur local : une animation jouée sur son propre
	Animator est répliquée automatiquement au serveur et aux autres clients.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat")
local Config = require(sharedFolder:WaitForChild("CombatConfig") :: ModuleScript)

local SwingAnimator = {}

-- Pistes déjà chargées, par Animator : une animation ne se charge qu'une fois par personnage.
local loadedTracks: { [Animator]: { [string]: AnimationTrack } } = {}

local function getTracks(animator: Animator): { [string]: AnimationTrack }
	local existingTracks = loadedTracks[animator]
	if existingTracks then
		return existingTracks
	end

	local tracks = {}
	loadedTracks[animator] = tracks
	animator.Destroying:Connect(function()
		loadedTracks[animator] = nil
	end)
	return tracks
end

local function getTrack(animator: Animator, animationId: string): AnimationTrack
	local tracks = getTracks(animator)
	local existingTrack = tracks[animationId]
	if existingTrack then
		return existingTrack
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action -- passe au-dessus de l'idle et de la marche
	track.Looped = false
	tracks[animationId] = track
	return track
end

-- Joue l'animation du coup `step` (une entrée de CombatConfig.COMBO) sur `character`.
-- Rejouer une piste déjà en cours la relance du début : deux coups identiques s'enchaînent bien.
function SwingAnimator.play(character: Model, step: any)
	if step.animationId == "" then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end

	-- Play(fondu, poids, vitesse) : la vitesse vient de la config pour rendre chaque coup plus ou moins sec.
	getTrack(animator, step.animationId):Play(Config.ANIMATION_FADE_TIME, 1, step.animationSpeed)
end

return SwingAnimator
