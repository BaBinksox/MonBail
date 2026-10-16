--!strict
--[[
	GeneratedAnimations (ModuleScript, client)
	Dans Roblox Studio, transforme une pose de PoseLibrary en vraie piste d'animation jouable :
	KeyframeBuilder construit la KeyframeSequence, KeyframeSequenceProvider l'enregistre et rend un
	identifiant TEMPORAIRE, que l'Animator charge comme un clip publié.

	Ces identifiants ne valent que pour la session Studio en cours : sur un serveur publié, la
	fonction échoue (ou n'est pas autorisée) et getId rend nil. Le jeu passe alors au clip de repli
	ou à la pose procédurale (voir AnimationConfig). Pour un jeu publié : publier les séquences
	(docs/ANIMATIONS.md) et coller les ID dans AnimationConfig.

	API : GeneratedAnimations.getId(poseName) -> string?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local animationFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation")
local AnimationConfig = require(animationFolder:WaitForChild("AnimationConfig") :: ModuleScript)
local KeyframeBuilder = require(animationFolder:WaitForChild("KeyframeBuilder") :: ModuleScript)

local GeneratedAnimations = {}

local cache: { [string]: string } = {}
local failed: { [string]: boolean } = {}
local isAvailable: boolean? = nil -- nil = pas encore essayé

local function canGenerate(): boolean
	if isAvailable == false or not AnimationConfig.USE_GENERATED_IN_STUDIO then
		return false
	end
	local isStudio = false
	pcall(function()
		isStudio = RunService:IsStudio()
	end)
	return isStudio
end

function GeneratedAnimations.getId(poseName: string): string?
	if failed[poseName] then
		return nil
	end
	local cached = cache[poseName]
	if cached then
		return cached
	end
	if not canGenerate() then
		return nil
	end
	local isRegistered, result = pcall(function()
		local sequence = KeyframeBuilder.build(poseName)
		if sequence == nil then
			return nil
		end
		local provider = game:GetService("KeyframeSequenceProvider")
		return provider:RegisterKeyframeSequence(sequence)
	end)
	if isRegistered and type(result) == "string" and result ~= "" then
		cache[poseName] = result
		isAvailable = true
		return result
	end
	failed[poseName] = true
	if not isRegistered and isAvailable == nil then
		isAvailable = false -- service indisponible ici : inutile de réessayer pour chaque pose
		warn(`[Animation] Séquences générées indisponibles ({result}) : repli sur les clips ou les poses.`)
	end
	return nil
end

-- Oublie les séquences enregistrées et les échecs (tests, changement de réglage en cours de jeu).
function GeneratedAnimations.reset()
	cache = {}
	failed = {}
	isAvailable = nil
end

return GeneratedAnimations
