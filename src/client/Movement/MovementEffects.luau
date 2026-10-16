--!strict
--[[
	MovementEffects (ModuleScript, client)
	Effets visuels de la mobilité, discrets et nettoyés automatiquement :
		- doubleJump(character) : bref cercle magique sous les pieds, aux couleurs de la Magie Innée ;
		- setSpeedStreaks(intensity) : quelques traits de vitesse devant la caméra au sprint maximal.
	En mode « effets réduits », le cercle est plus discret et les traits de vitesse sont coupés.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MagicConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local ClientSettings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)

-- Texture livrée avec Roblox (pas un asset du catalogue).
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local RING_DURATION = 0.45

local MovementEffects = {}

local function paletteOf(character: Model): any
	local player = Players:GetPlayerFromCharacter(character)
	local magic = MagicConfig.getById(player and player:GetAttribute(MagicConfig.ATTRIBUTE))
	return magic.palette
end

local function newEffectPart(name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = workspace
	return part
end

-- Cercle magique très bref sous les pieds, qui s'élargit en s'effaçant.
function MovementEffects.doubleJump(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local reduced = ClientSettings.isReducedEffects()
	local palette = paletteOf(character)
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	local ring = newEffectPart("DoubleJumpRing", CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.08, 2.2, 2.2), palette.glow)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = if reduced then 0.6 else 0.25
	TweenService:Create(ring, TweenInfo.new(RING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.04, 6.5, 6.5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, RING_DURATION + 0.05)
	if reduced then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(palette.glow, palette.main)
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 15)
	emitter.Rate = 0
	emitter.Parent = ring
	emitter:Emit(10)
end

--------------------------------------------------------------------------------
-- Traits de vitesse
--------------------------------------------------------------------------------

local streakPart: Part? = nil
local streakEmitter: ParticleEmitter? = nil

local function getStreaks(): (Part, ParticleEmitter)
	local part = streakPart
	local emitter = streakEmitter
	if part and emitter and part.Parent then
		return part, emitter
	end
	local newPart = Instance.new("Part")
	newPart.Name = "SpeedStreaks"
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.Transparency = 1
	newPart.Size = Vector3.new(14, 9, 1)
	newPart.Parent = workspace
	local newEmitter = Instance.new("ParticleEmitter")
	newEmitter.Texture = SPARK_TEXTURE
	newEmitter.Color = ColorSequence.new(Color3.fromRGB(235, 240, 255))
	newEmitter.LightEmission = 0.4
	newEmitter.Transparency = NumberSequence.new(0.65, 1)
	newEmitter.Size = NumberSequence.new(0.06)
	newEmitter.Lifetime = NumberRange.new(0.18, 0.28)
	newEmitter.Speed = NumberRange.new(40, 55)
	newEmitter.EmissionDirection = Enum.NormalId.Back
	newEmitter.LockedToPart = true
	newEmitter.Shape = Enum.ParticleEmitterShape.Box
	newEmitter.Rate = 0
	newEmitter.Parent = newPart
	streakPart, streakEmitter = newPart, newEmitter
	return newPart, newEmitter
end

-- intensity 0..1 (0 = coupé). À appeler à chaque image pendant le sprint.
function MovementEffects.setSpeedStreaks(intensity: number)
	local camera = workspace.CurrentCamera
	if intensity <= 0.01 or camera == nil or ClientSettings.isReducedEffects() then
		local emitter = streakEmitter
		if emitter then
			emitter.Rate = 0
		end
		return
	end
	local part, emitter = getStreaks()
	part.CFrame = camera.CFrame * CFrame.new(0, 0, -6)
	emitter.Rate = 30 * intensity
end

return MovementEffects
