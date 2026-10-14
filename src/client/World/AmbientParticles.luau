--!strict
--[[
	AmbientParticles
	Particules d'ambiance qui flottent autour du joueur : poussière dorée le jour, lucioles la nuit,
	braises pendant l'anomalie. Local à ce client.

	Un grand volume invisible suit la caméra ; chaque ambiance est un ParticleEmitter posé dedans,
	qui fait naître ses particules n'importe où dans ce volume. Les particules, elles, restent dans
	le monde une fois nées (LockedToPart = false) : le joueur les traverse en avançant.

	Ajouter une ambiance = ajouter une entrée à EMITTER_SETUPS.
]]

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- livrée avec le client Roblox

local VOLUME_SIZE = Vector3.new(90, 34, 90) -- studs : la zone autour de la caméra où naissent les particules

-- Chaque fonction règle l'émetteur d'une ambiance.
local EMITTER_SETUPS: { [string]: (ParticleEmitter) -> () } = {
	-- Jour : grains de poussière qui dérivent dans la lumière.
	dust = function(emitter: ParticleEmitter)
		emitter.Rate = 16
		emitter.Lifetime = NumberRange.new(6, 10)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.Size = NumberSequence.new(0.12)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 244, 220))
		emitter.LightEmission = 0.3
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
	end,

	-- Nuit : lucioles, rares, lentes, qui s'allument et s'éteignent.
	fireflies = function(emitter: ParticleEmitter)
		emitter.Rate = 7
		emitter.Lifetime = NumberRange.new(5, 9)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Acceleration = Vector3.new(0, 0.2, 0)
		emitter.Size = NumberSequence.new(0.36)
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 255, 130))
		emitter.LightEmission = 1
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.1),
			NumberSequenceKeypoint.new(0.4, 0.75),
			NumberSequenceKeypoint.new(0.65, 0.1),
			NumberSequenceKeypoint.new(0.85, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
	end,

	-- Anomalie : braises qui montent du sol, de l'orange vers le rouge sombre.
	embers = function(emitter: ParticleEmitter)
		emitter.Rate = 50
		emitter.Lifetime = NumberRange.new(3, 6)
		emitter.Speed = NumberRange.new(2, 6)
		emitter.Acceleration = Vector3.new(0, 3, 0)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Size = NumberSequence.new(0.4, 0)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(120, 10, 10))
		emitter.LightEmission = 1
		emitter.Transparency = NumberSequence.new(0.1, 1)
	end,
}

local AmbientParticles = {}

local volume: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}

-- Crée le volume et ses émetteurs (tous éteints). À appeler une fois.
function AmbientParticles.init()
	if volume then
		return
	end

	local part = Instance.new("Part")
	part.Name = "AmbientParticleVolume"
	part.Size = VOLUME_SIZE
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	for name, setup in EMITTER_SETUPS do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
		emitter.Enabled = false
		emitter.Texture = SPARK_TEXTURE
		emitter.LightInfluence = 0
		emitter.LockedToPart = false
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 1
		emitter.WindAffectsDrag = true -- le vent de la météo emporte les particules
		setup(emitter)
		emitter.Parent = part
		emitters[name] = emitter
	end

	part.Parent = workspace
	volume = part
end

-- Allume l'ambiance `name` et éteint les autres. Les particules déjà nées finissent leur vie.
function AmbientParticles.setActive(name: string)
	for emitterName, emitter in emitters do
		emitter.Enabled = emitterName == name
	end
end

-- Recentre le volume sur `position` (la caméra). À appeler à chaque frame.
function AmbientParticles.follow(position: Vector3)
	if volume then
		volume.CFrame = CFrame.new(position)
	end
end

return AmbientParticles
