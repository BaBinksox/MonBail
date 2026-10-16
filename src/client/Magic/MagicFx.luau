--!strict
--[[
	MagicFx (ModuleScript, client)
	Briques visuelles des magies, partagées par les ultimes (UltimateChoreographies) et les sorts
	(SpellEffects) : pièces décoratives, disques au sol, gerbes, flux de particules aspirées, cristaux
	qui jaillissent puis fondent. Tout est local, ancré, intangible et se détruit tout seul.
	Mode « effets réduits » : `scaled` divise les quantités par deux.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local clientFolder = script.Parent.Parent
local ClientSettings = require(clientFolder:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)

local MagicFx = {}
local random = Random.new()
MagicFx.random = random

MagicFx.SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
MagicFx.SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"


--------------------------------------------------------------------------------
-- Briques
--------------------------------------------------------------------------------

local folder: Folder? = nil
function MagicFx.getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "UltimateEffects"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

function MagicFx.reduced(): boolean
	return ClientSettings.isReducedEffects()
end

function MagicFx.scaled(value: number): number
	return if MagicFx.reduced() then math.max(1, math.floor(value / 2)) else value
end

function MagicFx.part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material, lifetime: number): Part
	local newPart = Instance.new("Part")
	newPart.Name = name
	newPart.Shape = shape
	newPart.Size = size
	newPart.Color = color
	newPart.Material = material
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	Debris:AddItem(newPart, lifetime)
	return newPart
end

function MagicFx.tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	TweenService:Create(instance, TweenInfo.new(math.max(duration, 0.01), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
end

-- Disque plat posé au sol (cylindre couché).
function MagicFx.disc(name: string, position: Vector3, diameter: number, color: Color3, material: Enum.Material, lifetime: number): Part
	local newPart = MagicFx.part(name, Enum.PartType.Cylinder, Vector3.new(0.12, diameter, diameter), color, material, lifetime)
	newPart.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	newPart.Parent = MagicFx.getFolder()
	return newPart
end

function MagicFx.groundBelow(position: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -25, 0), params)
	return if result then result.Position else position - Vector3.new(0, 3, 0)
end

function MagicFx.burst(position: Vector3, count: number, configure: (ParticleEmitter) -> ())
	local anchor = MagicFx.part("Burst", Enum.PartType.Block, Vector3.one * 0.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 3)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = MagicFx.getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.SpreadAngle = Vector2.new(180, 180)
	configure(emitter)
	emitter.Parent = anchor
	task.delay(0.03, function()
		emitter:Emit(MagicFx.scaled(count))
	end)
end

-- Émetteur continu de particules ASPIRÉES vers `center`, depuis une sphère de `radius`.
function MagicFx.inwardStream(center: Vector3, radius: number, color: ColorSequence, texture: string, rate: number, lifetime: number): (ParticleEmitter, Part)
	local shell = MagicFx.part("InwardShell", Enum.PartType.Ball, Vector3.one * radius * 2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, lifetime + 2)
	shell.Transparency = 1
	shell.CFrame = CFrame.new(center)
	shell.Parent = MagicFx.getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.Speed = NumberRange.new(radius * 1.1, radius * 1.5)
	emitter.Lifetime = NumberRange.new(0.6, 0.75)
	emitter.Rate = MagicFx.scaled(rate)
	emitter.Color = color
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35, 0.05)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Parent = shell
	return emitter, shell
end

-- Fait jaillir un cristal (prisme pointu) de `base` vers `direction`, puis le laisse fondre.
function MagicFx.crystal(base: Vector3, direction: Vector3, height: number, width: number, color: Color3, hold: number)
	local spike = MagicFx.part("Crystal", Enum.PartType.Block, Vector3.new(width, 0.2, width), color, Enum.Material.Glass, hold + 1.4)
	spike.Transparency = 0.2
	local up = direction.Unit
	local look = if math.abs(up.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis:Cross(up).Unit
	local rotation = CFrame.fromMatrix(Vector3.zero, look, up) * CFrame.Angles(0, math.rad(45), 0)
	spike.CFrame = CFrame.new(base) * rotation
	spike.Parent = MagicFx.getFolder()
	local grown = CFrame.new(base + up * height / 2) * rotation
	MagicFx.tween(spike, 0.12, { Size = Vector3.new(width, height, width), CFrame = grown }, Enum.EasingStyle.Back)
	task.delay(hold, function()
		if spike.Parent then
			MagicFx.tween(spike, 1.2, { Transparency = 1, Size = Vector3.new(width * 0.6, height * 0.85, width * 0.6) }, Enum.EasingStyle.Sine)
		end
	end)
end

function MagicFx.rootOf(model: Model): BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.RootPart
end


return MagicFx
