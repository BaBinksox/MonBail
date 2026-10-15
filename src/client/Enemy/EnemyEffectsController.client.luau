--!strict
--[[
	EnemyEffectsController (LocalScript)
	La lisibilité des combats contre les ennemis, côté client (le serveur décide de tout) :
		- barre de vie au-dessus de chaque ennemi proche (nom, étiquette « Élite » / « Boss »,
		  PV), masquée au-delà de EnemyDefinitions.EFFECTS_MAX_DISTANCE ;
		- télégraphes au sol (EnemyRemotes.Telegraph) : cercle, cône ou ligne qui se remplit jusqu'à
		  l'impact. Orange = parable (touche de parade au dernier moment), rouge = imparable (s'esquive) ;
		  le remplissage est recalé sur l'heure serveur (startedAt) pour finir à l'instant exact ;
		- actions (EnemyAction) : annulation (efface les télégraphes de l'ennemi), téléportation,
		  invocation, enrage, retour au point d'apparition, garde bloquée / brisée ;
		- corps qui disparaît (attribut Despawning) : fondu.
	Rien n'est un asset : Parts Neon translucides, Highlight, BillboardGui.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local enemyFolder = sharedFolder:WaitForChild("Enemy")
local Definitions = require(enemyFolder:WaitForChild("EnemyDefinitions") :: ModuleScript)
local EnemyRemotes = require(enemyFolder:WaitForChild("EnemyRemotes") :: ModuleScript)

local PARRYABLE_COLOR = Color3.fromRGB(240, 150, 50)
local UNBLOCKABLE_COLOR = Color3.fromRGB(220, 40, 40)
local GUARD_COLOR = Color3.fromRGB(196, 210, 232)
local ENRAGE_COLOR = Color3.fromRGB(255, 70, 40)
local BAR_WIDTH = 4.5 -- studs
local TELEGRAPH_HEIGHT = 0.12
local CONE_SEGMENTS = 9
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local ELITE_ATTRIBUTE = "Elite"

local localPlayer = Players.LocalPlayer
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "EnemyEffects"
effectsFolder.Parent = workspace

--------------------------------------------------------------------------------
-- Barres de vie
--------------------------------------------------------------------------------

type Bar = { gui: BillboardGui, fill: Frame, model: Model, connections: { RBXScriptConnection } }
local bars: { [Model]: Bar } = {}

local function definitionOf(model: Model): any
	local enemyId = model:GetAttribute(ENEMY_ID_ATTRIBUTE)
	return if type(enemyId) == "string" then Definitions.ENEMIES[enemyId] else nil
end

local function removeBar(model: Model)
	local bar = bars[model]
	if bar then
		bars[model] = nil
		for _, connection in bar.connections do
			connection:Disconnect()
		end
		bar.gui:Destroy()
	end
end

local function addBar(model: Instance)
	if not model:IsA("Model") or bars[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
	local adornee = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or not humanoid:IsA("Humanoid") or adornee == nil or not adornee:IsA("BasePart") then
		return
	end
	local def = definitionOf(model)
	local gui = Instance.new("BillboardGui")
	gui.Name = "EnemyBar"
	gui.Adornee = adornee
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = Definitions.EFFECTS_MAX_DISTANCE
	gui.Size = UDim2.new(BAR_WIDTH, 0, 1.1, 0)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.ResetOnSpawn = false
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.55)
	name.Font = Enum.Font.Garamond
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(226, 220, 208)
	name.TextStrokeTransparency = 0.4
	local label = if def then def.displayName else humanoid.DisplayName
	local rankLabel = if def and def.rank then def.rank elseif model:GetAttribute(ELITE_ATTRIBUTE) then "Élite" else nil
	name.Text = if rankLabel then `{label} · {rankLabel}` else label
	name.Parent = gui
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Position = UDim2.fromScale(0, 0.62)
	back.Size = UDim2.fromScale(1, 0.3)
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = if rankLabel then Color3.fromRGB(196, 56, 50) else Color3.fromRGB(176, 146, 96)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local bar: Bar = { gui = gui, fill = fill, model = model, connections = {} }
	bars[model] = bar
	local function refresh()
		local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		gui.Enabled = humanoid.Health > 0
	end
	table.insert(bar.connections, humanoid.HealthChanged:Connect(refresh))
	table.insert(bar.connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
	table.insert(bar.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			removeBar(model)
		end
	end))
	-- Corps qui disparaît : fondu.
	table.insert(bar.connections, model:GetAttributeChangedSignal(Definitions.ATTRIBUTES.despawning):Connect(function()
		if model:GetAttribute(Definitions.ATTRIBUTES.despawning) then
			gui.Enabled = false
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Transparency < 1 then
					TweenService:Create(descendant, TweenInfo.new(Definitions.DESPAWN_FADE_DURATION), { Transparency = 1 }):Play()
				end
			end
		end
	end))
	-- Ennemi enragé : contour rouge permanent.
	table.insert(bar.connections, model:GetAttributeChangedSignal(Definitions.ATTRIBUTES.enraged):Connect(function()
		local existing = model:FindFirstChild("Enraged")
		if model:GetAttribute(Definitions.ATTRIBUTES.enraged) and existing == nil then
			local highlight = Instance.new("Highlight")
			highlight.Name = "Enraged"
			highlight.FillColor = ENRAGE_COLOR
			highlight.FillTransparency = 0.8
			highlight.OutlineColor = ENRAGE_COLOR
			highlight.Parent = model
		elseif not model:GetAttribute(Definitions.ATTRIBUTES.enraged) and existing then
			existing:Destroy()
		end
	end))
	refresh()
end

for _, model in CollectionService:GetTagged(Definitions.TAG) do
	task.spawn(addBar, model)
end
CollectionService:GetInstanceAddedSignal(Definitions.TAG):Connect(function(model: Instance)
	task.spawn(addBar, model)
end)
CollectionService:GetInstanceRemovedSignal(Definitions.TAG):Connect(function(model: Instance)
	if model:IsA("Model") then
		removeBar(model)
	end
end)

--------------------------------------------------------------------------------
-- Télégraphes
--------------------------------------------------------------------------------

type Telegraph = { parts: { BasePart }, enemy: Model?, token: number }
local telegraphs: { Telegraph } = {}
local token = 0

local function flatPart(cframe: CFrame, size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = effectsFolder
	return part
end

local function disc(center: Vector3, radius: number, color: Color3, transparency: number): Part
	local part = flatPart(CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(TELEGRAPH_HEIGHT, radius * 2, radius * 2), color, transparency)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function removeTelegraph(telegraph: Telegraph)
	for _, part in telegraph.parts do
		part:Destroy()
	end
	local index = table.find(telegraphs, telegraph)
	if index then
		table.remove(telegraphs, index)
	end
end

-- Construit la forme : un contour pâle (la zone) et un remplissage qui grandit jusqu'à l'impact.
local function buildShape(data: any, color: Color3): ({ BasePart }, (alpha: number) -> ())
	local origin: Vector3 = data.origin + Vector3.new(0, TELEGRAPH_HEIGHT / 2 + 0.05, 0)
	local parts: { BasePart } = {}
	if data.shape == "circle" then
		local outline = disc(origin, data.radius, color, 0.75)
		local fill = disc(origin + Vector3.new(0, 0.02, 0), 0.1, color, 0.45)
		table.insert(parts, outline)
		table.insert(parts, fill)
		return parts, function(alpha: number)
			local r = math.max(0.1, data.radius * alpha)
			fill.Size = Vector3.new(TELEGRAPH_HEIGHT, r * 2, r * 2)
		end
	end
	local direction: Vector3 = if typeof(data.direction) == "Vector3" and data.direction.Magnitude > 0
		then Vector3.new(data.direction.X, 0, data.direction.Z).Unit
		else Vector3.new(0, 0, -1)
	local frame = CFrame.lookAt(origin, origin + direction)
	if data.shape == "line" then
		local length = data.length or data.radius
		local width = data.width or 4
		local outline = flatPart(frame * CFrame.new(0, 0, -length / 2), Vector3.new(width, TELEGRAPH_HEIGHT, length), color, 0.75)
		local fill = flatPart(frame * CFrame.new(0, 0.02, -0.05), Vector3.new(width, TELEGRAPH_HEIGHT, 0.1), color, 0.45)
		table.insert(parts, outline)
		table.insert(parts, fill)
		return parts, function(alpha: number)
			local l = math.max(0.1, length * alpha)
			fill.Size = Vector3.new(width, TELEGRAPH_HEIGHT, l)
			fill.CFrame = frame * CFrame.new(0, 0.02, -l / 2)
		end
	end
	-- Cône : éventail de lames fines (CONE_SEGMENTS) qui s'allongent.
	local angle = math.rad(data.angle or 60)
	local range = data.radius
	local blades: { BasePart } = {}
	for i = 0, CONE_SEGMENTS - 1 do
		local a = -angle / 2 + angle * (i + 0.5) / CONE_SEGMENTS
		local bladeFrame = frame * CFrame.Angles(0, -a, 0)
		local bladeWidth = 2 * range * math.tan(angle / CONE_SEGMENTS / 2) + 0.2
		local outline = flatPart(bladeFrame * CFrame.new(0, 0, -range / 2), Vector3.new(bladeWidth * 0.5, TELEGRAPH_HEIGHT, range), color, 0.78)
		outline.Size = Vector3.new(math.max(0.3, bladeWidth * 0.5), TELEGRAPH_HEIGHT, range)
		local blade = flatPart(bladeFrame * CFrame.new(0, 0.02, -0.05), Vector3.new(math.max(0.3, bladeWidth * 0.5), TELEGRAPH_HEIGHT, 0.1), color, 0.45)
		table.insert(parts, outline)
		table.insert(parts, blade)
		table.insert(blades, blade)
	end
	return parts, function(alpha: number)
		local l = math.max(0.1, range * alpha)
		for i, blade in blades do
			local a = -angle / 2 + angle * (i - 0.5) / CONE_SEGMENTS
			blade.Size = Vector3.new(blade.Size.X, TELEGRAPH_HEIGHT, l)
			blade.CFrame = frame * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.02, -l / 2)
		end
	end
end

local function playTelegraph(data: any)
	if type(data) ~= "table" or typeof(data.origin) ~= "Vector3" or type(data.duration) ~= "number" then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - data.origin).Magnitude > Definitions.EFFECTS_MAX_DISTANCE then
		return
	end
	token += 1
	local color = if data.unblockable then UNBLOCKABLE_COLOR else PARRYABLE_COLOR
	local parts, setProgress = buildShape(data, color)
	local enemy: Model? = if typeof(data.enemy) == "Instance" and data.enemy:IsA("Model") then data.enemy else nil
	local telegraph: Telegraph = { parts = parts, enemy = enemy, token = token }
	table.insert(telegraphs, telegraph)
	-- Le remplissage finit à l'heure serveur de l'impact (latence rattrapée).
	local startedAt = if type(data.startedAt) == "number" then data.startedAt else workspace:GetServerTimeNow()
	local impactAt = startedAt + data.duration
	task.spawn(function()
		while table.find(telegraphs, telegraph) do
			local remaining = impactAt - workspace:GetServerTimeNow()
			if remaining <= 0 then
				break
			end
			setProgress(1 - remaining / data.duration)
			RunService.RenderStepped:Wait()
		end
		if table.find(telegraphs, telegraph) then
			setProgress(1)
			for _, part in telegraph.parts do
				TweenService:Create(part, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
			task.delay(0.25, function()
				removeTelegraph(telegraph)
			end)
		end
	end)
end

local function clearEnemyTelegraphs(enemy: Model)
	for index = #telegraphs, 1, -1 do
		local telegraph = telegraphs[index]
		if telegraph.enemy == enemy then
			removeTelegraph(telegraph)
		end
	end
end

--------------------------------------------------------------------------------
-- Actions des ennemis
--------------------------------------------------------------------------------

local function burst(position: Vector3, color: Color3, size: number)
	local part = flatPart(CFrame.new(position), Vector3.one * 0.5, color, 0.2)
	part.Shape = Enum.PartType.Ball
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(part, 0.5)
end

local function onAction(data: any)
	if type(data) ~= "table" or typeof(data.enemy) ~= "Instance" then
		return
	end
	local enemy = data.enemy :: Model
	local action = data.action
	if action == "cancel" or action == "reset" then
		clearEnemyTelegraphs(enemy)
	elseif action == "blink" then
		if typeof(data.position) == "Vector3" then
			burst(data.position, Color3.fromRGB(120, 90, 200), 6)
		end
		if typeof(data.toPosition) == "Vector3" then
			burst(data.toPosition, Color3.fromRGB(120, 90, 200), 6)
		end
	elseif action == "summon" then
		if typeof(data.position) == "Vector3" then
			burst(data.position, Color3.fromRGB(90, 70, 140), 10)
		end
	elseif action == "enrage" then
		local position = if enemy:IsA("Model") then enemy:GetPivot().Position else nil
		if position then
			burst(position, ENRAGE_COLOR, 12)
		end
	elseif action == "guard_block" then
		if typeof(data.position) == "Vector3" then
			burst(data.position, GUARD_COLOR, 3)
		end
	elseif action == "guard_break" then
		if typeof(data.position) == "Vector3" then
			burst(data.position, PARRYABLE_COLOR, 9)
		end
	end
end

EnemyRemotes.Telegraph.OnClientEvent:Connect(playTelegraph)
EnemyRemotes.EnemyAction.OnClientEvent:Connect(onAction)
