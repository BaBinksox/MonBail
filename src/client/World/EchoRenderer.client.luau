--!strict
--[[
	EchoRenderer (LocalScript)
	Affiche les échos temporels que le serveur décide de montrer à CE joueur (EchoRemotes.PlayEcho) :
	une silhouette translucide, faite de Parts locales (aucun asset), marche de point en point,
	s'arrête aux actions d'EchoConfig, fait briller la rune qu'elle touche et murmure ses répliques
	en sous-titres. StopEcho la dissipe (le joueur s'est trop éloigné).

	Purement visuel et local : le serveur sait déjà, de son côté, si l'écho a été vu en entier.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local worldFolder = sharedFolder:WaitForChild("World")
local EchoConfig = require(worldFolder:WaitForChild("EchoConfig") :: ModuleScript)
local EchoRemotes = require(worldFolder:WaitForChild("EchoRemotes") :: ModuleScript)
local RegionConfig = require(worldFolder:WaitForChild("RegionConfig") :: ModuleScript)

local GHOST_HEIGHT_OFFSET = 3 -- le centre du torse est 3 studs au-dessus du sol (point du trajet)
local FADE_TIME = 0.8
local TOUCH_FLASH_TIME = 1.2

local localPlayer = Players.LocalPlayer

type Ghost = {
	echoId: string,
	model: Model,
	parts: { BasePart },
	token: number,
}

local current: Ghost? = nil
local token = 0

--------------------------------------------------------------------------------
-- Sous-titres
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "EchoSubtitles"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 45
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.AnchorPoint = Vector2.new(0.5, 1)
subtitle.Position = UDim2.fromScale(0.5, 0.8)
subtitle.Size = UDim2.fromScale(0.7, 0.08)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Garamond
subtitle.TextScaled = true
subtitle.TextWrapped = true
subtitle.TextColor3 = Color3.fromRGB(205, 230, 255)
subtitle.TextStrokeTransparency = 0.4
subtitle.TextTransparency = 1
subtitle.Text = ""
subtitle.Parent = gui

local sizeConstraint = Instance.new("UITextSizeConstraint")
sizeConstraint.MaxTextSize = 30
sizeConstraint.MinTextSize = 14
sizeConstraint.Parent = subtitle

local subtitleToken = 0
local function showSubtitle(speaker: string, text: string)
	subtitleToken += 1
	local myToken = subtitleToken
	subtitle.Text = if speaker ~= "" then `{speaker} : « {text} »` else text
	TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	task.delay(EchoConfig.SUBTITLE_DURATION, function()
		if subtitleToken == myToken then
			TweenService:Create(subtitle, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		end
	end)
end

--------------------------------------------------------------------------------
-- Silhouette
--------------------------------------------------------------------------------

-- Une silhouette humaine simplifiée, translucide, sans collision.
local function buildGhost(color: Color3): (Model, { BasePart })
	local model = Instance.new("Model")
	model.Name = "Echo"
	local parts: { BasePart } = {}
	local function piece(name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Shape = shape or Enum.PartType.Block
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part:SetAttribute("Offset", offset)
		part.Parent = model
		table.insert(parts, part)
		return part
	end
	local root = piece("Torso", Vector3.new(1.8, 2, 0.9), CFrame.new())
	piece("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.65, 0), Enum.PartType.Ball)
	piece("LeftArm", Vector3.new(0.6, 1.9, 0.6), CFrame.new(-1.25, 0.05, 0))
	piece("RightArm", Vector3.new(0.6, 1.9, 0.6), CFrame.new(1.25, 0.05, 0))
	piece("LeftLeg", Vector3.new(0.7, 2, 0.7), CFrame.new(-0.45, -2, 0))
	piece("RightLeg", Vector3.new(0.7, 2, 0.7), CFrame.new(0.45, -2, 0))
	piece("Veil", Vector3.new(2.2, 3.2, 0.2), CFrame.new(0, -0.6, 0.55)) -- un pan de cape
	model.PrimaryPart = root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = root
	return model, parts
end

local function placeGhost(ghost: Ghost, rootCFrame: CFrame, walkPhase: number)
	for _, part in ghost.parts do
		local offset = part:GetAttribute("Offset")
		if typeof(offset) == "CFrame" then
			-- Balancement léger des membres pendant la marche.
			local swing = 0
			if part.Name == "LeftArm" or part.Name == "RightLeg" then
				swing = math.sin(walkPhase) * 0.5
			elseif part.Name == "RightArm" or part.Name == "LeftLeg" then
				swing = -math.sin(walkPhase) * 0.5
			end
			part.CFrame = rootCFrame * offset * CFrame.Angles(swing, 0, 0)
		end
	end
end

local function setGhostTransparency(ghost: Ghost, transparency: number, duration: number)
	for _, part in ghost.parts do
		TweenService:Create(part, TweenInfo.new(duration), { Transparency = transparency }):Play()
	end
end

local function dissolve(ghost: Ghost)
	setGhostTransparency(ghost, 1, FADE_TIME)
	task.delay(FADE_TIME + 0.1, function()
		ghost.model:Destroy()
	end)
end

-- Fait briller l'objet interactif touché par la silhouette (chez ce joueur seulement).
local function flashInteractable(interactableId: string, color: Color3)
	for _, instance in CollectionService:GetTagged(RegionConfig.INTERACTABLE_TAG) do
		if instance:IsA("BasePart") and instance:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE) == interactableId then
			local highlight = Instance.new("Highlight")
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.FillTransparency = 0.3
			highlight.Adornee = instance
			highlight.Parent = instance
			task.delay(TOUCH_FLASH_TIME, function()
				highlight:Destroy()
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Lecture
--------------------------------------------------------------------------------

local function play(echoId: string, points: { Vector3 })
	local echo = EchoConfig.ECHOES[echoId]
	if echo == nil or #points < 2 then
		return
	end
	if current then
		dissolve(current)
	end
	token += 1
	local model, parts = buildGhost(echo.color)
	local ghost: Ghost = { echoId = echoId, model = model, parts = parts, token = token }
	current = ghost
	model.Parent = workspace

	local actionsByPoint: { [number]: any } = {}
	for _, action in echo.actions do
		actionsByPoint[action.point] = action
	end

	local up = Vector3.new(0, GHOST_HEIGHT_OFFSET, 0)
	local function facing(from: Vector3, to: Vector3): CFrame
		local flat = Vector3.new(to.X, from.Y, to.Z)
		if (flat - from).Magnitude < 0.05 then
			return CFrame.new(from)
		end
		return CFrame.lookAt(from, flat)
	end

	placeGhost(ghost, facing(points[1] + up, points[2] + up), 0)
	setGhostTransparency(ghost, EchoConfig.TRANSPARENCY, FADE_TIME)

	local walkPhase = 0
	for index = 1, #points do
		if ghost.token ~= token then
			return
		end
		-- Action au point (pause, rune touchée, réplique).
		local action = actionsByPoint[index]
		if action then
			if action.line then
				showSubtitle(echo.name, action.line)
			end
			if action.touch then
				flashInteractable(action.touch, echo.color)
			end
			task.wait(action.pause)
		end
		-- Marche jusqu'au point suivant.
		local nextPoint = points[index + 1]
		if nextPoint then
			local from, to = points[index] + up, nextPoint + up
			local duration = (to - from).Magnitude / echo.walkSpeed
			local elapsed = 0
			while elapsed < duration do
				if ghost.token ~= token then
					return
				end
				local deltaTime = RunService.RenderStepped:Wait()
				elapsed += deltaTime
				walkPhase += deltaTime * echo.walkSpeed * 0.9
				local alpha = math.clamp(elapsed / duration, 0, 1)
				local position = from:Lerp(to, alpha) + Vector3.new(0, math.abs(math.sin(walkPhase)) * 0.15, 0)
				placeGhost(ghost, facing(position, to), walkPhase)
			end
		end
	end

	if ghost.token == token then
		if echo.finalLine then
			showSubtitle("", echo.finalLine)
		end
		dissolve(ghost)
		current = nil
	end
end

EchoRemotes.PlayEcho.OnClientEvent:Connect(function(echoId: any, points: any, _startServerTime: any)
	if type(echoId) == "string" and type(points) == "table" then
		task.spawn(play, echoId, points)
	end
end)

EchoRemotes.StopEcho.OnClientEvent:Connect(function(echoId: any)
	local ghost = current
	if ghost and ghost.echoId == echoId then
		token += 1
		current = nil
		dissolve(ghost)
		showSubtitle("", "L'écho se dissipe. Vous vous êtes trop éloigné.")
	end
end)
