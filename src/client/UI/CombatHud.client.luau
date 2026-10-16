--!strict
--[[
	CombatHud (LocalScript)
	Jauges de combat du joueur, discrètes, dans la charte du Grimoire (Theme) :
		- PV (rouge sombre), MANA (bleu), TENSION (dégradé de la Magie Innée) ;
		- invite de la technique ultime quand la Tension est pleine (touche réelle affichée) ;
		- invite « Riposte » pendant la fenêtre ouverte par une parade parfaite ;
		- Mana insuffisant : la barre clignote brièvement (UIBus.ManaDenied, envoyé par les sorts).
	Tout est LU dans des attributs écrits par le serveur (Mana, ManaMax, Tension, CounterUntil...) :
	cette interface ne décide de rien. Placée en bas au centre (en haut au centre sur tactile, pour
	ne pas passer sous le stick ni les boutons). Masquée dans le créateur de personnage.
	La barre de vie de Roblox est masquée (doublon) tant que ce HUD est actif.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("CombatConfig") :: ModuleScript)
local ResourceConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ResourceConfig") :: ModuleScript)
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)

local Theme = require(script.Parent:WaitForChild("Theme") :: ModuleScript)
local UIBus = require(script.Parent:WaitForChild("UIBus") :: ModuleScript)

local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local BAR_WIDTH = 300
local BAR_HEIGHT = 8
local ROW_GAP = 4
local FILL_TIME = 0.2

local COLOR_HEALTH = Color3.fromRGB(176, 52, 52)
local COLOR_HEALTH_LOW = Color3.fromRGB(230, 70, 60)
local COLOR_MANA = Color3.fromRGB(70, 130, 220)
local COLOR_MANA_DENIED = Color3.fromRGB(230, 90, 90)

local localPlayer = Players.LocalPlayer
local colors = Theme.colors

local screen = Theme.screenGui("CombatHudGui", Theme.displayOrder.hud)

local container = Instance.new("Frame")
container.Name = "CombatGauges"
container.BackgroundTransparency = 1
container.Size = UDim2.fromOffset(BAR_WIDTH, 3 * BAR_HEIGHT + 2 * ROW_GAP + 44)
container.Parent = screen.safe

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

type Bar = { frame: Frame, fill: Frame, stroke: UIStroke, gradient: UIGradient?, label: TextLabel }

local function newBar(name: string, order: number, color: Color3): Bar
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colors.sunken
	frame.BackgroundTransparency = 0.2
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -(order * (BAR_HEIGHT + ROW_GAP)))
	frame.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	frame.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = colors.gold
	stroke.Transparency = 0.55
	stroke.Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = frame
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	local label = Theme.caption({
		parent = frame,
		text = "",
		size = UDim2.new(0, 60, 0, 12),
		position = UDim2.new(1, 6, 0.5, -6),
		textSize = Theme.textSize.small,
		alignX = Enum.TextXAlignment.Left,
	})
	return { frame = frame, fill = fill, stroke = stroke, gradient = nil, label = label }
end

local healthBar = newBar("Health", 2, COLOR_HEALTH)
local manaBar = newBar("Mana", 1, COLOR_MANA)
local tensionBar = newBar("Tension", 0, Color3.new(1, 1, 1))
local tensionGradient = Instance.new("UIGradient")
tensionGradient.Parent = tensionBar.fill
tensionBar.gradient = tensionGradient

local prompt = Theme.title({
	parent = container,
	text = "",
	size = UDim2.new(1, 0, 0, 22),
	position = UDim2.fromOffset(0, 0),
	textSize = Theme.textSize.label,
	alignX = Enum.TextXAlignment.Center,
})
prompt.Visible = false

--------------------------------------------------------------------------------
-- Rafraîchissement
--------------------------------------------------------------------------------

local function setRatio(bar: Bar, ratio: number)
	Theme.tween(bar.fill, { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) }, FILL_TIME)
end

local function numberAttribute(name: string, default: number): number
	local value = localPlayer:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Libellé de la touche d'une action, selon le dernier périphérique utilisé.
local function keyLabel(actionName: string): string
	local binding = KeyBindings.BINDINGS[actionName]
	if binding == nil then
		return "?"
	end
	local mode = Theme.getInputMode()
	if mode == "gamepad" and binding.gamepad then
		return (string.gsub(binding.gamepad.Name, "^Button", ""))
	elseif mode == "touch" then
		return binding.label
	end
	if binding.mouse == Enum.UserInputType.MouseButton1 then
		return "Clic"
	end
	local keyCode = binding.keyCode or binding.fallbackKeyCode
	local isOk, text = pcall(function()
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	return if isOk and type(text) == "string" and text ~= "" then string.upper(text) else keyCode.Name
end

local healthConnection: RBXScriptConnection? = nil

local function refreshHealth(humanoid: Humanoid)
	local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0
	setRatio(healthBar, ratio)
	healthBar.fill.BackgroundColor3 = if ratio <= 0.3 then COLOR_HEALTH_LOW else COLOR_HEALTH
	healthBar.label.Text = `{math.ceil(humanoid.Health)}`
end

local function watchCharacter(character: Model)
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	healthConnection = humanoid.HealthChanged:Connect(function()
		refreshHealth(humanoid)
	end)
	refreshHealth(humanoid)
end

local function refreshMana()
	local max = numberAttribute(ResourceConfig.MANA_MAX_ATTRIBUTE, ResourceConfig.MANA_MAX)
	local mana = numberAttribute(ResourceConfig.MANA_ATTRIBUTE, max)
	setRatio(manaBar, if max > 0 then mana / max else 0)
	manaBar.label.Text = `{math.floor(mana)}`
end

local function refreshPrompt()
	local now = workspace:GetServerTimeNow()
	local counterUntil = numberAttribute(CombatConfig.COUNTER_ATTRIBUTE, 0)
	if counterUntil > now then
		prompt.Text = `[{keyLabel("Attack")}]  Riposte`
		prompt.TextColor3 = colors.goldBright
		prompt.Visible = true
		task.delay(counterUntil - now + 0.05, refreshPrompt)
		return
	end
	local tension = numberAttribute(CombatConfig.TENSION_ATTRIBUTE, 0)
	if tension >= CombatConfig.TENSION_MAX then
		local magic = MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE))
		prompt.Text = `[{keyLabel("Ultimate")}]  {magic.ultimateName}`
		prompt.TextColor3 = magic.palette.glow
		prompt.Visible = true
		return
	end
	prompt.Visible = false
end

local function refreshTension()
	local tension = numberAttribute(CombatConfig.TENSION_ATTRIBUTE, 0)
	setRatio(tensionBar, tension / CombatConfig.TENSION_MAX)
	tensionBar.stroke.Transparency = if tension >= CombatConfig.TENSION_MAX then 0 else 0.55
	tensionBar.label.Text = ""
	refreshPrompt()
end

local function refreshMagic()
	local magic = MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE))
	tensionGradient.Color = Theme.magicGradient(magic.palette)
	refreshPrompt()
end

local function refreshVisibility()
	local isCustomizing = localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true
	screen.gui.Enabled = not isCustomizing
	if not isCustomizing then
		-- Le créateur réactive toute l'interface de Roblox en sortant : on remasque la barre de vie.
		task.delay(0.5, function()
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
		end)
	end
end

local function refreshLayout(layout: any)
	if layout.isTouch then
		container.AnchorPoint = Vector2.new(0.5, 0)
		container.Position = UDim2.new(0.5, 0, 0, Theme.spacing.sm)
	else
		container.AnchorPoint = Vector2.new(0.5, 1)
		container.Position = UDim2.new(0.5, 0, 1, -Theme.spacing.xl)
	end
end

-- Sort refusé faute de Mana : la barre clignote en rouge un instant.
local function flashManaDenied()
	manaBar.stroke.Color = COLOR_MANA_DENIED
	manaBar.stroke.Transparency = 0
	Theme.tween(manaBar.stroke, { Transparency = 0.55 }, 0.6)
	task.delay(0.6, function()
		manaBar.stroke.Color = colors.gold
	end)
end

--------------------------------------------------------------------------------
-- Branchements
--------------------------------------------------------------------------------

localPlayer:GetAttributeChangedSignal(ResourceConfig.MANA_ATTRIBUTE):Connect(refreshMana)
localPlayer:GetAttributeChangedSignal(ResourceConfig.MANA_MAX_ATTRIBUTE):Connect(refreshMana)
localPlayer:GetAttributeChangedSignal(CombatConfig.TENSION_ATTRIBUTE):Connect(refreshTension)
localPlayer:GetAttributeChangedSignal(CombatConfig.COUNTER_ATTRIBUTE):Connect(refreshPrompt)
localPlayer:GetAttributeChangedSignal(MagicConfig.ATTRIBUTE):Connect(refreshMagic)
localPlayer:GetAttributeChangedSignal(CUSTOMIZING_ATTRIBUTE):Connect(refreshVisibility)
localPlayer.CharacterAdded:Connect(watchCharacter)
UIBus.ManaDenied:Connect(flashManaDenied)
Theme.onLayoutChanged(screen, refreshLayout)

if localPlayer.Character then
	task.spawn(watchCharacter, localPlayer.Character)
end
refreshLayout(Theme.getLayout(screen))
refreshMana()
refreshMagic()
refreshTension()
refreshVisibility()
