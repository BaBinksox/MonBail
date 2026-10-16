--!strict
--[[
	CombatHud (LocalScript)
	Jauges de combat du joueur, discrètes, dans la charte du Grimoire (Theme) :
		- PV (rouge sombre), MANA (bleu), TENSION (dégradé de la Magie Innée) ;
		- invite de la technique ultime quand la Tension est pleine (touche réelle affichée) ;
		- invite « Riposte » pendant la fenêtre ouverte par une parade parfaite ;
		- emplacements des deux sorts et de la Concentration : nom, touche RÉELLE selon l'appareil
		  (clavier AZERTY / QWERTY, manette, tactile), coût en Mana (rouge s'il manque du Mana),
		  recharge qui se vide, état actif ;
		- altérations du joueur (voile...) : petites pastilles avec le temps restant ;
		- Mana insuffisant : la barre clignote brièvement (UIBus.ManaDenied, envoyé par les sorts).
	Tout est LU dans des attributs écrits par le serveur (Mana, ManaMax, Tension, CounterUntil...) :
	cette interface ne décide de rien. Placée en bas au centre (en haut au centre sur tactile, pour
	ne pas passer sous le stick ni les boutons). Masquée dans le créateur de personnage.
	La barre de vie de Roblox est masquée (doublon) tant que ce HUD est actif.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("CombatConfig") :: ModuleScript)
local ResourceConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ResourceConfig") :: ModuleScript)
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local SpellConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("SpellConfig") :: ModuleScript)
local StatusConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("StatusConfig") :: ModuleScript)

local Theme = require(script.Parent:WaitForChild("Theme") :: ModuleScript)
local UIBus = require(script.Parent:WaitForChild("UIBus") :: ModuleScript)
local SfxPlayer = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)

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

local SLOT_SIZE = Vector2.new(64, 44)
local SLOT_GAP = 8
local SLOTS_HEIGHT = SLOT_SIZE.Y + 6
local STATUS_ROW_HEIGHT = 18
local BARS_HEIGHT = 3 * BAR_HEIGHT + 2 * ROW_GAP
local REFRESH_INTERVAL = 0.1

local container = Instance.new("Frame")
container.Name = "CombatGauges"
container.BackgroundTransparency = 1
container.Size = UDim2.fromOffset(BAR_WIDTH, BARS_HEIGHT + SLOTS_HEIGHT + STATUS_ROW_HEIGHT + 30)
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

-- Emplacements : sort de base, sort secondaire, Concentration.
type Slot = { frame: Frame, name: TextLabel, key: TextLabel, cost: TextLabel, shade: Frame, timer: TextLabel, stroke: UIStroke }

local function newSlot(name: string, index: number): Slot
	local width = 3 * SLOT_SIZE.X + 2 * SLOT_GAP
	local frame = Theme.panel({
		name = name,
		parent = container,
		style = "sunken",
		size = UDim2.fromOffset(SLOT_SIZE.X, SLOT_SIZE.Y),
		position = UDim2.new(0.5, -width / 2 + (index - 1) * (SLOT_SIZE.X + SLOT_GAP), 1, -(BARS_HEIGHT + 6 + SLOT_SIZE.Y)),
	})
	frame.ClipsDescendants = true
	local stroke = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Parent = frame
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = colors.ink
	shade.BackgroundTransparency = 0.35
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.ZIndex = 2
	shade.Parent = frame
	local title = Theme.caption({ parent = frame, text = "", size = UDim2.new(1, -6, 0, 14), position = UDim2.fromOffset(3, 2), textSize = Theme.textSize.small, alignX = Enum.TextXAlignment.Center })
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3
	local cost = Theme.caption({ parent = frame, text = "", size = UDim2.new(0.5, -3, 0, 12), position = UDim2.new(0, 3, 1, -14), textSize = Theme.textSize.small, alignX = Enum.TextXAlignment.Left })
	cost.ZIndex = 3
	local key = Theme.caption({ parent = frame, text = "", size = UDim2.new(0.5, -3, 0, 12), position = UDim2.new(0.5, 0, 1, -14), textSize = Theme.textSize.small, alignX = Enum.TextXAlignment.Right })
	key.ZIndex = 3
	local timer = Theme.label({ parent = frame, text = "", size = UDim2.fromScale(1, 1), textSize = Theme.textSize.label, alignX = Enum.TextXAlignment.Center })
	timer.ZIndex = 4
	return { frame = frame, name = title, key = key, cost = cost, shade = shade, timer = timer, stroke = stroke }
end

local baseSlot = newSlot("SpellBaseSlot", 1)
local secondarySlot = newSlot("SpellSecondarySlot", 2)
local concentrationSlot = newSlot("ConcentrationSlot", 3)

-- Altérations du joueur : pastilles réutilisées.
local statusRow = Instance.new("Frame")
statusRow.Name = "Statuses"
statusRow.BackgroundTransparency = 1
statusRow.AnchorPoint = Vector2.new(0.5, 1)
statusRow.Position = UDim2.new(0.5, 0, 1, -(BARS_HEIGHT + SLOTS_HEIGHT + 6))
statusRow.Size = UDim2.new(1, 0, 0, STATUS_ROW_HEIGHT)
statusRow.Parent = container
local statusLayout = Instance.new("UIListLayout")
statusLayout.FillDirection = Enum.FillDirection.Horizontal
statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statusLayout.Padding = UDim.new(0, 4)
statusLayout.Parent = statusRow
local statusChips: { TextLabel } = {}

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

local wasTensionFull = false

local function refreshTension()
	local tension = numberAttribute(CombatConfig.TENSION_ATTRIBUTE, 0)
	local isFull = tension >= CombatConfig.TENSION_MAX
	if isFull and not wasTensionFull then
		SfxPlayer.play("ultimateReady")
	end
	wasTensionFull = isFull
	setRatio(tensionBar, tension / CombatConfig.TENSION_MAX)
	tensionBar.stroke.Transparency = if tension >= CombatConfig.TENSION_MAX then 0 else 0.55
	tensionBar.label.Text = ""
	refreshPrompt()
end

local refreshKeyLabelsLater: () -> () = function() end

local function refreshMagic()
	local magic = MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE))
	tensionGradient.Color = Theme.magicGradient(magic.palette)
	refreshKeyLabelsLater()
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

-- Emplacements : touches (selon le dernier appareil utilisé), puis recharges et Mana en continu.
local function currentSpells(): (any, any)
	local magicId = MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE)).id
	return SpellConfig.forMagic(magicId, "base"), SpellConfig.forMagic(magicId, "secondary")
end

local function refreshKeyLabels()
	baseSlot.key.Text = keyLabel("SpellBase")
	secondarySlot.key.Text = keyLabel("SpellSecondary")
	concentrationSlot.key.Text = keyLabel("Concentrate")
	local base, secondary = currentSpells()
	baseSlot.name.Text = if base then base.name else ""
	secondarySlot.name.Text = if secondary then secondary.name else ""
	baseSlot.cost.Text = if base then `{base.manaCost}` else ""
	secondarySlot.cost.Text = if secondary then `{secondary.manaCost}` else ""
	concentrationSlot.name.Text = "Concentration"
	concentrationSlot.cost.Text = ""
end

local function setCooldown(slot: Slot, remaining: number, total: number)
	if remaining > 0.05 and total > 0 then
		slot.shade.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
		slot.timer.Text = if remaining >= 1 then `{math.ceil(remaining)}` else string.format("%.1f", remaining)
	else
		slot.shade.Size = UDim2.fromScale(1, 0)
		slot.timer.Text = ""
	end
end

local function refreshSpellSlot(slot: Slot, spell: any, mana: number, now: number)
	if spell == nil then
		return
	end
	local readyAt = numberAttribute(SpellConfig.READY_ATTRIBUTE_PREFIX .. spell.id, 0)
	setCooldown(slot, readyAt - now, spell.cooldown)
	local isAffordable = mana + 1e-6 >= spell.manaCost
	slot.cost.TextColor3 = if isAffordable then COLOR_MANA else COLOR_MANA_DENIED
	local isCasting = localPlayer:GetAttribute(SpellConfig.CASTING_ATTRIBUTE) == spell.id
	slot.stroke.Color = if isCasting then colors.goldBright else colors.gold
	slot.stroke.Transparency = if isCasting then 0 else 0.55
end

local function refreshStatuses(now: number)
	local character = localPlayer.Character
	local active = {}
	if character then
		for id, def in StatusConfig.STATUSES do
			local untilTime = character:GetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. id)
			if type(untilTime) == "number" and untilTime > now then
				table.insert(active, { def = def, remaining = untilTime - now })
			end
		end
	end
	table.sort(active, function(a, b)
		return a.def.id < b.def.id
	end)
	for index, entry in active do
		if index > #statusChips then
			local newChip = Theme.caption({ parent = statusRow, text = "", size = UDim2.fromOffset(90, STATUS_ROW_HEIGHT), textSize = Theme.textSize.small, alignX = Enum.TextXAlignment.Center })
			newChip.BackgroundColor3 = colors.sunken
			newChip.BackgroundTransparency = 0.3
			newChip.LayoutOrder = index
			table.insert(statusChips, newChip)
		end
		local chip = statusChips[index]
		chip.Visible = true
		chip.Text = `{entry.def.name} {math.ceil(entry.remaining)} s`
		chip.TextColor3 = entry.def.color
	end
	for index = #active + 1, #statusChips do
		statusChips[index].Visible = false
	end
end

local function refreshSlots()
	local now = workspace:GetServerTimeNow()
	local mana = numberAttribute(ResourceConfig.MANA_ATTRIBUTE, ResourceConfig.MANA_MAX)
	local base, secondary = currentSpells()
	refreshSpellSlot(baseSlot, base, mana, now)
	refreshSpellSlot(secondarySlot, secondary, mana, now)
	local isConcentrating = localPlayer:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == true
	setCooldown(concentrationSlot, numberAttribute(ResourceConfig.CONCENTRATION_READY_ATTRIBUTE, 0) - now, ResourceConfig.CONCENTRATION_COOLDOWN)
	concentrationSlot.stroke.Color = if isConcentrating then colors.cyan else colors.gold
	concentrationSlot.stroke.Transparency = if isConcentrating then 0 else 0.55
	refreshStatuses(now)
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

-- Esquive parfaite (élan accordé par le serveur) : un mot bref et un son cristallin.
local function onMomentum()
	local untilTime = numberAttribute(CombatConfig.MOMENTUM_ATTRIBUTE, 0)
	if untilTime <= workspace:GetServerTimeNow() then
		return
	end
	SfxPlayer.play("dodgePerfect")
	if prompt.Visible then
		return -- une invite plus importante (riposte, ultime) garde la place
	end
	prompt.Text = "Esquive parfaite"
	prompt.TextColor3 = colors.cyan
	prompt.Visible = true
	task.delay(0.9, refreshPrompt)
end

--------------------------------------------------------------------------------
-- Branchements
--------------------------------------------------------------------------------

localPlayer:GetAttributeChangedSignal(ResourceConfig.MANA_ATTRIBUTE):Connect(refreshMana)
localPlayer:GetAttributeChangedSignal(ResourceConfig.MANA_MAX_ATTRIBUTE):Connect(refreshMana)
localPlayer:GetAttributeChangedSignal(CombatConfig.TENSION_ATTRIBUTE):Connect(refreshTension)
localPlayer:GetAttributeChangedSignal(CombatConfig.COUNTER_ATTRIBUTE):Connect(refreshPrompt)
localPlayer:GetAttributeChangedSignal(CombatConfig.MOMENTUM_ATTRIBUTE):Connect(onMomentum)
localPlayer:GetAttributeChangedSignal(MagicConfig.ATTRIBUTE):Connect(refreshMagic)
localPlayer:GetAttributeChangedSignal(CUSTOMIZING_ATTRIBUTE):Connect(refreshVisibility)
localPlayer.CharacterAdded:Connect(watchCharacter)
UIBus.ManaDenied:Connect(flashManaDenied)
Theme.onLayoutChanged(screen, refreshLayout)
UserInputService.LastInputTypeChanged:Connect(function()
	refreshKeyLabels()
	refreshPrompt()
end)
refreshKeyLabelsLater = refreshKeyLabels

local sinceRefresh = 0
RunService.Heartbeat:Connect(function(dt: number)
	sinceRefresh += dt
	if sinceRefresh >= REFRESH_INTERVAL and screen.gui.Enabled then
		sinceRefresh = 0
		refreshSlots()
	end
end)

if localPlayer.Character then
	task.spawn(watchCharacter, localPlayer.Character)
end
refreshLayout(Theme.getLayout(screen))
wasTensionFull = numberAttribute(CombatConfig.TENSION_ATTRIBUTE, 0) >= CombatConfig.TENSION_MAX
refreshMana()
refreshKeyLabels()
refreshMagic()
refreshTension()
refreshVisibility()
refreshSlots()
