--!strict
--[[
	WorldAtmosphere (LocalScript)
	Met en image l'état du monde décidé par le serveur. Tout est local à ce client, mais comme tous
	les clients lisent les mêmes données, tout le monde voit le même ciel au même moment.

	Ce que ce script règle, en continu :
		- la lumière : cycle jour / nuit interpolé (LightingPresets), teinté par la météo en cours ;
		- l'anomalie : quand un boss charge son attaque fatale, tout bascule en moins d'une demi-seconde
		  vers un ciel de minuit rouge sang, puis revient lentement une fois le danger passé ;
		- le vent (Workspace.GlobalWind), qui agite herbe, nuages et particules ;
		- les particules d'ambiance autour du joueur (AmbientParticles) ;
		- le son : bourdon de l'anomalie, vent ;
		- les présages : une phrase murmurée à l'écran quand le serveur en envoie une.

	Il crée lui-même tout ce dont il a besoin (Atmosphere, nuages, effets) : rien à préparer dans Studio,
	à une exception près, que seul toi peux faire : Lighting > Technology = Future, pour les ombres
	et lumières les plus fines (cette propriété ne peut pas être changée par un script).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local worldFolder = sharedFolder:WaitForChild("World")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local Config = require(worldFolder:WaitForChild("WorldConfig") :: ModuleScript)
local Remotes = require(worldFolder:WaitForChild("WorldRemotes") :: ModuleScript)

local AmbientParticles = require(script.Parent:WaitForChild("AmbientParticles") :: ModuleScript)
local LightingPresets = require(script.Parent:WaitForChild("LightingPresets") :: ModuleScript)

local APPLY_INTERVAL = 0.5 -- secondes entre deux mises à jour de la lumière en temps normal
local ANOMALY_FADE_IN = 0.35 -- secondes pour basculer dans l'anomalie : brutal
local ANOMALY_FADE_OUT = 4 -- secondes pour en revenir : lent
local WEATHER_SMOOTHING_TIME = 12 -- secondes (ordre de grandeur) pour passer d'une météo à l'autre
local MAX_FOG_DENSITY = 0.9
local FULL_WIND_SPEED = 30 -- studs/s : vent auquel le son du vent est à plein volume

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Instances de rendu
--------------------------------------------------------------------------------

local function getOrCreate(parent: Instance, className: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function newEffect(className: string, name: string): Instance
	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

local function newLoopingSound(name: string, soundId: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

-- Un objet par groupe de LightingPresets : c'est sur eux que les préréglages sont appliqués.
local renderTargets: { [string]: Instance } = {
	Lighting = Lighting,
	Atmosphere = getOrCreate(Lighting, "Atmosphere"),
	ColorCorrection = newEffect("ColorCorrectionEffect", "WorldColorCorrection"),
	Bloom = newEffect("BloomEffect", "WorldBloom"),
	SunRays = newEffect("SunRaysEffect", "WorldSunRays"),
	Clouds = getOrCreate(workspace:FindFirstChildOfClass("Terrain") :: Instance, "Clouds"),
}

-- Réglages fixes : ombres douces, reflets et lumière d'environnement au maximum.
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.25
Lighting.GeographicLatitude = 38
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1

local anomalyDrone = newLoopingSound("WorldAnomalyDrone", Config.ANOMALY_DRONE_ID)
local windSound = newLoopingSound("WorldWind", Config.WIND_SOUND_ID)

AmbientParticles.init()

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local function getTargetWeather(): any
	return Config.WEATHERS[workspace:GetAttribute(Config.WEATHER_ATTRIBUTE)] or Config.WEATHERS[Config.DEFAULT_WEATHER]
end

local function isAnomalyActive(): boolean
	return workspace:GetAttribute(Config.MOOD_ATTRIBUTE) == Config.MOODS.Anomaly
end

-- Météo affichée : elle glisse vers la météo du serveur au lieu de changer d'un coup.
local initialWeather = getTargetWeather()
local weather = {
	fog = initialWeather.fog,
	haze = initialWeather.haze,
	cloudCover = initialWeather.cloudCover,
	windSpeed = initialWeather.windSpeed,
}

local moodAlpha = if isAnomalyActive() then 1 else 0 -- 0 = monde normal, 1 = anomalie
local timeSinceApply = math.huge -- force une première mise à jour immédiate

--------------------------------------------------------------------------------
-- Mise à jour du rendu
--------------------------------------------------------------------------------

local function isNight(clockTime: number): boolean
	return clockTime >= Config.NIGHT_START or clockTime <= Config.NIGHT_END
end

-- Sons d'ambiance : leur volume suit l'état du monde ; ils ne tournent que lorsqu'on les entend.
local function updateSound(sound: Sound, volume: number)
	sound.Volume = volume
	if volume > 0 and not sound.IsPlaying and sound.SoundId ~= "" then
		sound:Play()
	elseif volume <= 0 and sound.IsPlaying then
		sound:Stop()
	end
end

-- Recalcule tout le rendu. `elapsed` : secondes écoulées depuis la mise à jour précédente.
local function apply(elapsed: number)
	-- 1. La météo affichée se rapproche de la météo du serveur.
	local targetWeather = getTargetWeather()
	local rate = 1 - math.exp(-math.min(elapsed, 5) / WEATHER_SMOOTHING_TIME)
	for key, value in weather do
		weather[key] = value + (targetWeather[key] - value) * rate
	end

	-- 2. Lumière de l'heure qu'il est, alourdie par la météo.
	local clockTime = Config.getClockTime()
	local preset = LightingPresets.atClockTime(clockTime)
	preset.Atmosphere.Density = math.min(preset.Atmosphere.Density + weather.fog, MAX_FOG_DENSITY)
	preset.Atmosphere.Haze += weather.haze
	preset.Clouds.Cover = weather.cloudCover

	-- 3. L'anomalie écrase le tout, à proportion de moodAlpha.
	if moodAlpha > 0 then
		preset = LightingPresets.blend(preset, LightingPresets.ANOMALY, moodAlpha)
	end

	for groupName, properties in preset do
		local target = renderTargets[groupName] :: any
		for property, value in properties do
			target[property] = value
		end
	end

	-- Le ciel saute à minuit au milieu de la bascule : le soleil disparaît d'un coup.
	Lighting.ClockTime = if moodAlpha > 0.5 then LightingPresets.ANOMALY_CLOCK_TIME else clockTime
	workspace.GlobalWind = Config.WIND_DIRECTION * weather.windSpeed

	-- 4. Particules et sons.
	if moodAlpha > 0.5 then
		AmbientParticles.setActive("embers")
	elseif isNight(clockTime) then
		AmbientParticles.setActive("fireflies")
	else
		AmbientParticles.setActive("dust")
	end

	updateSound(anomalyDrone, Config.ANOMALY_DRONE_VOLUME * moodAlpha)
	updateSound(windSound, Config.WIND_SOUND_MAX_VOLUME * math.clamp(weather.windSpeed / FULL_WIND_SPEED, 0, 1))
end

-- Une seule boucle : elle suit la caméra avec les particules à chaque frame, mais ne recalcule
-- la lumière que toutes les APPLY_INTERVAL secondes, ou à chaque frame pendant une bascule.
RunService.Heartbeat:Connect(function(deltaTime: number)
	local camera = workspace.CurrentCamera
	if camera then
		AmbientParticles.follow(camera.CFrame.Position)
	end

	local targetAlpha = if isAnomalyActive() then 1 else 0
	local isTransitioning = moodAlpha ~= targetAlpha
	if isTransitioning then
		local fadeDuration = if targetAlpha > moodAlpha then ANOMALY_FADE_IN else ANOMALY_FADE_OUT
		local step = deltaTime / fadeDuration
		moodAlpha = if targetAlpha > moodAlpha
			then math.min(moodAlpha + step, targetAlpha)
			else math.max(moodAlpha - step, targetAlpha)
	end

	timeSinceApply += deltaTime
	if isTransitioning or timeSinceApply >= APPLY_INTERVAL then
		apply(timeSinceApply)
		timeSinceApply = 0
	end
end)

--------------------------------------------------------------------------------
-- Présages
--------------------------------------------------------------------------------

local omenGui = Instance.new("ScreenGui")
omenGui.Name = "OmenGui"
omenGui.ResetOnSpawn = false
omenGui.IgnoreGuiInset = true
omenGui.DisplayOrder = 30

local omenLabel = Instance.new("TextLabel")
omenLabel.Name = "Omen"
omenLabel.AnchorPoint = Vector2.new(0.5, 0.5)
omenLabel.Position = UDim2.fromScale(0.5, 0.24)
omenLabel.Size = UDim2.fromScale(0.8, 0.08)
omenLabel.BackgroundTransparency = 1
omenLabel.Font = Enum.Font.Garamond
omenLabel.Text = ""
omenLabel.TextSize = 32
omenLabel.TextColor3 = Color3.fromRGB(226, 214, 226)
omenLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
omenLabel.TextStrokeTransparency = 1
omenLabel.TextTransparency = 1
omenLabel.Parent = omenGui
omenGui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Voile propre aux présages : le monde pâlit un instant pendant que la phrase est à l'écran.
local omenVeil = newEffect("ColorCorrectionEffect", "WorldOmenVeil") :: ColorCorrectionEffect

local function tween(instance: Instance, duration: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
end

-- Une phrase apparaît, reste, puis s'efface. YIELD pendant toute sa durée.
Remotes.Omen.OnClientEvent:Connect(function(text: string)
	-- Pas de murmure dans le Hub de création, ni si un autre est encore à l'écran.
	if localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true or omenLabel.TextTransparency < 1 then
		return
	end

	local fadeDuration = Config.OMEN_DURATION * 0.3
	omenLabel.Text = text
	tween(omenLabel, fadeDuration, { TextTransparency = 0.1, TextStrokeTransparency = 0.6 })
	tween(omenVeil, fadeDuration, { Saturation = -0.7, Brightness = -0.1, Contrast = 0.15 })

	task.wait(Config.OMEN_DURATION - fadeDuration)

	tween(omenLabel, fadeDuration, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween(omenVeil, fadeDuration, { Saturation = 0, Brightness = 0, Contrast = 0 })
end)
