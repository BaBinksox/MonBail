--!strict
--[[
	HudController (LocalScript)
	L'affichage permanent du jeu, alimenté par PlayerState (état poussé par le serveur) :
		- badge de rang (haut gauche) : rang d'aventurier, XP ;
		- suivi de quête (haut droite) : quête principale en cours, étape, objectifs et compteurs ;
		- notifications (bas, au centre) : récompenses, découvertes, promotions, quêtes, contrats,
		  guilde, groupe, erreurs ;
		- panneau de lecture (centre) : textes examinés (inscriptions, livres, portes verrouillées) ;
		- invites réservées à une autre Magie Innée : masquées (le serveur les refuse de toute façon) ;
		- la cloche qui sonne (attribut BellRungAt de Workspace.World) : une phrase pour tous.
	Masqué tant que le joueur est dans le créateur de personnage (attribut IsCustomizing).
	Les panneaux (contrats, guilde...) sont ouverts via UIBus.OpenPanel : voir Grimoire.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(sharedFolder:WaitForChild("Progression"):WaitForChild("ItemConfig") :: ModuleScript)
local RankConfig = require(sharedFolder:WaitForChild("Progression"):WaitForChild("RankConfig") :: ModuleScript)
local QuestDefinitions = require(sharedFolder:WaitForChild("Quest"):WaitForChild("QuestDefinitions") :: ModuleScript)
local MissionDefinitions = require(sharedFolder:WaitForChild("Mission"):WaitForChild("MissionDefinitions") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local RegionConfig = require(sharedFolder:WaitForChild("World"):WaitForChild("RegionConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local Theme = require(clientFolder:WaitForChild("UI"):WaitForChild("Theme") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)
local PlayerState = require(clientFolder:WaitForChild("State"):WaitForChild("PlayerState") :: ModuleScript)

local TOAST_DURATION = 4.5
local TOAST_LIMIT = 4
local READING_CLOSE_DISTANCE = 18 -- studs : le texte se referme si l'on s'éloigne
local REQUIRED_MAGIC_ATTRIBUTE = "RequiredMagic"
local BELL_RUNG_ATTRIBUTE = "BellRungAt"
local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"

local localPlayer = Players.LocalPlayer
local colors = Theme.colors

local screen = Theme.screenGui("HudGui", Theme.displayOrder.hud)
local readingScreen = Theme.screenGui("ReadingGui", Theme.displayOrder.world)

--------------------------------------------------------------------------------
-- Badge de rang
--------------------------------------------------------------------------------

local badge = Theme.panel({
	name = "RankBadge",
	parent = screen.safe,
	style = "glass",
	size = UDim2.fromOffset(230, 58),
	position = UDim2.fromOffset(Theme.spacing.md, Theme.spacing.md),
	padding = Theme.spacing.sm,
})
local rankLetter = Theme.title({
	parent = badge,
	text = "E",
	size = UDim2.new(0, 40, 1, 0),
	textSize = 34,
	color = colors.goldBright,
	alignX = Enum.TextXAlignment.Center,
})
local rankName = Theme.label({
	parent = badge,
	text = "",
	size = UDim2.new(1, -48, 0.5, 0),
	position = UDim2.fromOffset(48, 0),
	textSize = Theme.textSize.label,
	alignX = Enum.TextXAlignment.Left,
})
local rankXp = Theme.caption({
	parent = badge,
	text = "",
	size = UDim2.new(1, -48, 0.5, 0),
	position = UDim2.new(0, 48, 0.5, 0),
	alignX = Enum.TextXAlignment.Left,
})

local function refreshBadge()
	local progression = PlayerState.get("progression")
	if type(progression) ~= "table" then
		return
	end
	local rank = RankConfig.getRank(progression.rank)
	rankLetter.Text = rank.id
	rankName.Text = `Rang {rank.id} · {rank.name}`
	local nextRank = progression.nextRank
	local xpRequirement = nil
	if type(nextRank) == "table" and type(nextRank.requirements) == "table" then
		for _, requirement in nextRank.requirements do
			if requirement.kind == "xp" then
				xpRequirement = requirement
			end
		end
	end
	rankXp.Text = if xpRequirement
		then `{progression.xp} / {xpRequirement.target} XP · rang {nextRank.id}`
		else `{progression.xp} XP`
end

--------------------------------------------------------------------------------
-- Suivi de quête
--------------------------------------------------------------------------------

local tracker = Theme.panel({
	name = "QuestTracker",
	parent = screen.safe,
	style = "glass",
	size = UDim2.fromOffset(320, 0),
	position = UDim2.new(1, -Theme.spacing.md, 0, Theme.spacing.md),
	anchor = Vector2.new(1, 0),
	padding = Theme.spacing.md,
	visible = false,
})
tracker.AutomaticSize = Enum.AutomaticSize.Y
local trackerList = Instance.new("UIListLayout")
trackerList.SortOrder = Enum.SortOrder.LayoutOrder
trackerList.Padding = UDim.new(0, Theme.spacing.xs)
trackerList.Parent = tracker

local function clearTracker()
	for _, child in tracker:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function trackerLine(order: number, text: string, kind: "title" | "stage" | "objective", done: boolean?)
	local props = {
		parent = tracker,
		text = text,
		size = UDim2.new(1, 0, 0, 0),
		autoSize = "Y" :: "Y",
		wrap = true,
		layoutOrder = order,
		alignX = Enum.TextXAlignment.Left,
	}
	if kind == "title" then
		local label = Theme.title(props)
		label.TextSize = Theme.textSize.heading
		label.TextColor3 = colors.goldBright
	elseif kind == "stage" then
		Theme.caption(props)
	else
		local label = Theme.label(props)
		label.TextColor3 = if done then colors.textMuted else colors.text
	end
end

-- Quête suivie : la première quête active dans l'ordre du récit.
local function trackedQuest(quests: any): (any, any)
	if type(quests) ~= "table" or type(quests.active) ~= "table" then
		return nil, nil
	end
	for _, questId in QuestDefinitions.ORDER do
		local progress = quests.active[questId]
		if progress then
			return QuestDefinitions.getQuest(questId), progress
		end
	end
	for questId, progress in quests.active do
		local quest = QuestDefinitions.getQuest(questId)
		if quest then
			return quest, progress
		end
	end
	return nil, nil
end

local function refreshTracker()
	clearTracker()
	local quest, progress = trackedQuest(PlayerState.get("quests"))
	if quest == nil or progress == nil then
		tracker.Visible = false
		return
	end
	local stage = quest.stages[progress.stage]
	if stage == nil then
		tracker.Visible = false
		return
	end
	trackerLine(1, quest.name, "title")
	trackerLine(2, string.upper(stage.title), "stage")
	for index, objective in stage.objectives do
		local count = if type(progress.progress) == "table" then progress.progress[objective.id] or 0 else 0
		local done = count >= objective.count
		local counter = if objective.count > 1 then ` ({math.min(count, objective.count)}/{objective.count})` else ""
		trackerLine(2 + index, `{if done then "✓" else "•"} {objective.text}{counter}`, "objective", done)
	end
	-- Contrats prêts à rendre : un rappel discret.
	local missions = PlayerState.get("missions")
	if type(missions) == "table" and type(missions.active) == "table" then
		local ready = 0
		for _, entry in missions.active do
			if entry.ready then
				ready += 1
			end
		end
		if ready > 0 then
			trackerLine(50, `{ready} contrat(s) à rendre au tableau`, "stage")
		end
	end
	tracker.Visible = true
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

local toastArea = Instance.new("Frame")
toastArea.Name = "Toasts"
toastArea.BackgroundTransparency = 1
toastArea.AnchorPoint = Vector2.new(0.5, 1)
toastArea.Position = UDim2.new(0.5, 0, 1, -110)
toastArea.Size = UDim2.fromOffset(460, 300)
toastArea.Parent = screen.safe
local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, Theme.spacing.xs)
toastLayout.Parent = toastArea

local toastOrder = 0
local function toast(title: string, body: string?, accent: Color3?)
	toastOrder += 1
	local group, content = Theme.group({
		parent = toastArea,
		style = "panel",
		size = UDim2.new(1, 0, 0, 0),
		layoutOrder = toastOrder,
		padding = Theme.spacing.sm,
		borderColor = accent,
	})
	group.AutomaticSize = Enum.AutomaticSize.Y
	content.AutomaticSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = content
	local heading = Theme.title({ parent = content, text = title, size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = 1 })
	heading.TextSize = Theme.textSize.button
	if accent then
		heading.TextColor3 = accent
	end
	if body and body ~= "" then
		Theme.label({ parent = content, text = body, size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = 2 })
	end
	-- Pas plus de TOAST_LIMIT à la fois : les plus anciennes partent.
	local toasts = {}
	for _, child in toastArea:GetChildren() do
		if child:IsA("CanvasGroup") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - TOAST_LIMIT do
		toasts[i]:Destroy()
	end
	Theme.fade(group, true, Theme.durations.normal)
	task.delay(TOAST_DURATION, function()
		if group.Parent then
			Theme.fade(group, false, Theme.durations.slow)
			task.delay(Theme.durations.slow + 0.1, function()
				group:Destroy()
			end)
		end
	end)
end

local function describeReward(payload: any): string
	local parts: { string } = {}
	if type(payload.xp) == "number" and payload.xp > 0 then
		table.insert(parts, `+{payload.xp} XP`)
	end
	if type(payload.reputation) == "number" and payload.reputation > 0 then
		table.insert(parts, `+{payload.reputation} réputation`)
	end
	if type(payload.items) == "table" then
		for _, added in payload.items do
			local item = ItemConfig.getItem(added.id)
			table.insert(parts, `{if item then item.name else tostring(added.id)} ×{added.count}`)
		end
	end
	return table.concat(parts, "  ·  ")
end

local function onNotified(kind: string, payload: any)
	if kind == "text" then
		UIBus.ShowText:Fire(tostring(payload.title or ""), tostring(payload.text or ""))
	elseif kind == "openPanel" then
		UIBus.OpenPanel:Fire(tostring(payload.panel or "missions"))
	elseif kind == "reward" then
		local text = describeReward(payload)
		if text ~= "" then
			toast("Récompense", text, colors.goldBright)
		end
	elseif kind == "discovery" then
		toast(`Découverte : {payload.name or ""}`, if payload.xp then `+{payload.xp} XP` else nil, colors.cyan)
	elseif kind == "promotion" then
		toast(`Rang {payload.rank} — {payload.name or ""}`, payload.perk, colors.amber)
	elseif kind == "quest" then
		if payload.event == "started" then
			toast(`Nouvelle quête : {payload.name}`, payload.journal, colors.goldBright)
		elseif payload.event == "stage" then
			toast(`{payload.name} — {payload.stage}`, payload.journal)
		elseif payload.event == "completed" then
			toast(`Quête terminée : {payload.name}`, payload.rewardText, colors.success)
		end
	elseif kind == "mission" then
		local mission = MissionDefinitions.getMission(payload.missionId)
		local name = payload.name or (mission and mission.name) or ""
		if payload.event == "ready" then
			toast(`Contrat rempli : {name}`, "Rendez-le au tableau des contrats.", colors.success)
		elseif payload.event == "accepted" then
			toast(`Contrat accepté : {name}`)
		end
	elseif kind == "guild" or kind == "party" or kind == "info" then
		if payload.text then
			toast(if kind == "guild" then "Guilde" elseif kind == "party" then "Groupe" else "Information", payload.text)
		end
	elseif kind == "error" then
		toast("Impossible", payload.text or payload.message, colors.danger)
	end
end

--------------------------------------------------------------------------------
-- Panneau de lecture
--------------------------------------------------------------------------------

local reading = Theme.panel({
	name = "Reading",
	parent = readingScreen.safe,
	size = UDim2.fromOffset(520, 0),
	position = UDim2.fromScale(0.5, 0.42),
	anchor = Vector2.new(0.5, 0.5),
	padding = Theme.spacing.lg,
	visible = false,
	active = true,
})
reading.AutomaticSize = Enum.AutomaticSize.Y
local readingList = Instance.new("UIListLayout")
readingList.SortOrder = Enum.SortOrder.LayoutOrder
readingList.Padding = UDim.new(0, Theme.spacing.sm)
readingList.HorizontalAlignment = Enum.HorizontalAlignment.Center
readingList.Parent = reading
local readingTitle = Theme.title({ parent = reading, text = "", size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = 1, alignX = Enum.TextXAlignment.Center })
Theme.divider({ parent = reading, size = UDim2.new(0.8, 0, 0, 1), layoutOrder = 2 })
local readingText = Theme.label({ parent = reading, text = "", size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = 3, font = Theme.fonts.hand })
readingText.TextSize = Theme.textSize.body + 2
local readingClose = Theme.button({ parent = reading, text = "Fermer", variant = "secondary", size = UDim2.fromOffset(160, 40), layoutOrder = 4 })
local readingOrigin: Vector3? = nil

local function closeReading()
	if reading.Visible then
		Theme.fade(reading, false, Theme.durations.fast)
	end
	readingOrigin = nil
end
readingClose:onActivated(closeReading)

UIBus.ShowText:Connect(function(title: string, text: string)
	readingTitle.Text = title
	readingText.Text = text
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	readingOrigin = if root and root:IsA("BasePart") then root.Position else nil
	Theme.fade(reading, true, Theme.durations.normal)
end)
UIBus.ClosePanels:Connect(closeReading)

task.spawn(function()
	while true do
		task.wait(0.5)
		local origin = readingOrigin
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if origin and root and root:IsA("BasePart") and (root.Position - origin).Magnitude > READING_CLOSE_DISTANCE then
			closeReading()
		end
	end
end)

--------------------------------------------------------------------------------
-- Invites réservées à une Magie Innée
--------------------------------------------------------------------------------

local function refreshPrompt(prompt: ProximityPrompt)
	local required = prompt:GetAttribute(REQUIRED_MAGIC_ATTRIBUTE)
	if type(required) == "string" then
		prompt.Enabled = localPlayer:GetAttribute(MagicConfig.ATTRIBUTE) == required
	end
end

local function watchInteractable(instance: Instance)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			refreshPrompt(descendant)
		end
	end
	instance.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
			refreshPrompt(descendant)
		end
	end)
end

local function refreshAllPrompts()
	for _, instance in CollectionService:GetTagged(RegionConfig.INTERACTABLE_TAG) do
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				refreshPrompt(descendant)
			end
		end
	end
end

for _, instance in CollectionService:GetTagged(RegionConfig.INTERACTABLE_TAG) do
	watchInteractable(instance)
end
CollectionService:GetInstanceAddedSignal(RegionConfig.INTERACTABLE_TAG):Connect(watchInteractable)
localPlayer:GetAttributeChangedSignal(MagicConfig.ATTRIBUTE):Connect(refreshAllPrompts)

--------------------------------------------------------------------------------
-- La cloche
--------------------------------------------------------------------------------

local function watchBell(world: Instance)
	world:GetAttributeChangedSignal(BELL_RUNG_ATTRIBUTE):Connect(function()
		toast("La Cloche Muette a retrouvé sa voix", "Trois coups, puis un. Quelque part sous le village, quelque chose s'éveille.", colors.cyan)
	end)
end
local existingWorld = workspace:FindFirstChild(RegionConfig.WORLD_FOLDER_NAME)
if existingWorld then
	watchBell(existingWorld)
end
workspace.ChildAdded:Connect(function(child: Instance)
	if child.Name == RegionConfig.WORLD_FOLDER_NAME then
		watchBell(child)
	end
end)

--------------------------------------------------------------------------------
-- Branchements
--------------------------------------------------------------------------------

local function refreshVisibility()
	local isCustomizing = localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true
	screen.gui.Enabled = not isCustomizing
	readingScreen.gui.Enabled = not isCustomizing
end
localPlayer:GetAttributeChangedSignal(CUSTOMIZING_ATTRIBUTE):Connect(refreshVisibility)
refreshVisibility()

PlayerState.Changed:Connect(function(slice: string)
	if slice == "progression" then
		refreshBadge()
	elseif slice == "quests" or slice == "missions" then
		refreshTracker()
	end
end)
PlayerState.Notified:Connect(onNotified)
refreshBadge()
refreshTracker()
