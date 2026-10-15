--!strict
--[[
	Grimoire (LocalScript)
	Le livre du joueur, en quatre onglets, entièrement alimenté par l'état serveur (PlayerState) :
		Journal      quêtes en cours (étape, récit, objectifs), quêtes disponibles et terminées ;
		Contrats     tableau des contrats : accepter, abandonner, rendre (MissionRequest) ;
		Compagnons   groupe (PartyRequest) et guilde (GuildRequest) : création, invitations, rôles,
		             description, contrats collectifs, journal de la guilde ;
		Progression  rang d'aventurier, conditions du rang suivant, réputation, découvertes, inventaire.
	Ouverture : touche J (lettre imprimée, toutes dispositions), croix directionnelle haut à la manette,
	ou UIBus.OpenPanel("missions" | "guild" | "party" | "journal" | "progression" | "inventory")
	(tableaux du village, Ysolde, Corvin). Le serveur vérifie tout : ce panneau ne fait que demander,
	puis se redessine quand la tranche d'état correspondante revient.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local KeyboardLayout = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyboardLayout") :: ModuleScript)
local QuestDefinitions = require(sharedFolder:WaitForChild("Quest"):WaitForChild("QuestDefinitions") :: ModuleScript)
local MissionDefinitions = require(sharedFolder:WaitForChild("Mission"):WaitForChild("MissionDefinitions") :: ModuleScript)
local MissionRemotes = require(sharedFolder:WaitForChild("Mission"):WaitForChild("MissionRemotes") :: ModuleScript)
local GuildRemotes = require(sharedFolder:WaitForChild("Guild"):WaitForChild("GuildRemotes") :: ModuleScript)
local PartyRemotes = require(sharedFolder:WaitForChild("Party"):WaitForChild("PartyRemotes") :: ModuleScript)
local NpcConfig = require(sharedFolder:WaitForChild("NPC"):WaitForChild("NpcConfig") :: ModuleScript)
local ItemConfig = require(sharedFolder:WaitForChild("Progression"):WaitForChild("ItemConfig") :: ModuleScript)
local RankConfig = require(sharedFolder:WaitForChild("Progression"):WaitForChild("RankConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local Theme = require(clientFolder:WaitForChild("UI"):WaitForChild("Theme") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)
local PlayerState = require(clientFolder:WaitForChild("State"):WaitForChild("PlayerState") :: ModuleScript)

local ACTION_NAME = "ToggleGrimoire"
local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local TABS = {
	{ id = "journal", label = "Journal" },
	{ id = "missions", label = "Contrats" },
	{ id = "companions", label = "Compagnons" },
	{ id = "progression", label = "Progression" },
}
local PANEL_TO_TAB: { [string]: string } = {
	journal = "journal",
	missions = "missions",
	guild = "companions",
	party = "companions",
	progression = "progression",
	inventory = "progression",
}
local TAB_SLICES: { [string]: { string } } = {
	journal = { "quests" },
	missions = { "missions", "progression", "party" },
	companions = { "party", "guild" },
	progression = { "progression", "inventory", "discoveries" },
}

local localPlayer = Players.LocalPlayer
local colors = Theme.colors
local spacing = Theme.spacing

local screen = Theme.screenGui("GrimoireGui", Theme.displayOrder.menu)
screen.gui.Enabled = false

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = colors.ink
backdrop.BackgroundTransparency = 0.45
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Modal = true -- libère la souris (caméra verrouillée) tant que le Grimoire est ouvert
backdrop.Parent = screen.root

local book = Theme.panel({
	name = "Book",
	parent = screen.safe,
	size = UDim2.fromScale(0.9, 0.86),
	position = UDim2.fromScale(0.5, 0.5),
	anchor = Vector2.new(0.5, 0.5),
	maxSize = Vector2.new(1080, 680),
	padding = spacing.lg,
	active = true,
})
Theme.title({ parent = book, text = "Grimoire", size = UDim2.new(1, -60, 0, 40), alignX = Enum.TextXAlignment.Left })
local closeButton = Theme.iconButton({ parent = book, glyph = "✕", size = UDim2.fromOffset(40, 40), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
local tabs = Theme.tabs({
	parent = book,
	items = TABS,
	orientation = "horizontal",
	position = UDim2.fromOffset(0, 48),
	size = UDim2.new(1, 0, 0, 44),
})
local status = Theme.caption({ parent = book, text = "", size = UDim2.new(1, 0, 0, 18), position = UDim2.new(0, 0, 1, 0), anchor = Vector2.new(0, 1), alignX = Enum.TextXAlignment.Left })
local content = Theme.scroller({ parent = book, position = UDim2.fromOffset(0, 100), size = UDim2.new(1, 0, 1, -124) })
local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, spacing.sm)
contentLayout.Parent = content

local currentTab = "journal"
local isOpen = false
local order = 0

--------------------------------------------------------------------------------
-- Construction de contenu
--------------------------------------------------------------------------------

local function nextOrder(): number
	order += 1
	return order
end

local function clear()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	order = 0
end

local function heading(text: string, parent: Instance?)
	local label = Theme.title({ parent = parent or content, text = text, size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = nextOrder(), alignX = Enum.TextXAlignment.Left })
	label.TextSize = Theme.textSize.heading
end

local function caption(text: string, parent: Instance?)
	Theme.caption({ parent = parent or content, text = text, size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = nextOrder(), alignX = Enum.TextXAlignment.Left })
end

local function paragraph(text: string, parent: Instance?, color: Color3?, font: Enum.Font?): TextLabel
	local label = Theme.label({ parent = parent or content, text = text, size = UDim2.new(1, 0, 0, 0), autoSize = "Y", wrap = true, layoutOrder = nextOrder(), alignX = Enum.TextXAlignment.Left, font = font })
	if color then
		label.TextColor3 = color
	end
	return label
end

-- Carte : panneau en relief dont le contenu s'empile verticalement.
local function card(parent: Instance?): Frame
	local frame = Theme.panel({ parent = parent or content, style = "raised", size = UDim2.new(1, -8, 0, 0), layoutOrder = nextOrder(), padding = spacing.md })
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, spacing.xs)
	list.Parent = frame
	return frame
end

-- Rangée de boutons.
local function buttonRow(parent: Instance): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 40)
	row.LayoutOrder = nextOrder()
	row.Parent = parent
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, spacing.sm)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	return row
end

local function addButton(row: Instance, text: string, variant: any, enabled: boolean?, onActivated: () -> ())
	local button = Theme.button({ parent = row, text = text, variant = variant or "secondary", size = UDim2.fromOffset(math.max(120, #text * 9 + 30), 38), enabled = enabled ~= false })
	button:onActivated(onActivated)
end

local function textBox(parent: Instance, placeholder: string, width: number?): TextBox
	local box = Instance.new("TextBox")
	box.PlaceholderText = placeholder
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = Theme.fonts.body
	box.TextSize = Theme.textSize.body
	box.TextColor3 = colors.text
	box.PlaceholderColor3 = colors.textMuted
	box.BackgroundColor3 = colors.sunken
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(width or 260, 38)
	box.TextXAlignment = Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, spacing.sm)
	padding.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = box
	box.Parent = parent
	return box
end

local function setStatus(text: string?, isError: boolean?)
	status.Text = text or ""
	status.TextColor3 = if isError then colors.danger else colors.textMuted
end

-- Envoie une requête au serveur hors du fil de l'interface, puis affiche son résultat.
local function request(remote: RemoteFunction, ...: any)
	local args = table.pack(...)
	setStatus("…")
	task.spawn(function()
		local isDone, response = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not isDone or type(response) ~= "table" then
			setStatus("Le serveur ne répond pas. Réessayez.", true)
		elseif response.ok then
			setStatus(response.message or "C'est fait.")
		else
			setStatus(response.message or response.error or "Refusé.", true)
		end
	end)
end

local function formatDuration(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	return if hours > 0 then `{hours} h {minutes} min` else `{minutes} min`
end

local function describeRewards(rewards: any): string
	if type(rewards) ~= "table" then
		return ""
	end
	local parts: { string } = {}
	if rewards.xp then
		table.insert(parts, `{rewards.xp} XP`)
	end
	if rewards.reputation then
		table.insert(parts, `{rewards.reputation} réputation`)
	end
	if type(rewards.items) == "table" then
		for itemId, count in rewards.items do
			local item = ItemConfig.getItem(itemId)
			table.insert(parts, `{if item then item.name else itemId} ×{count}`)
		end
	end
	return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- Journal
--------------------------------------------------------------------------------

local function renderJournal()
	local quests = PlayerState.get("quests")
	if type(quests) ~= "table" then
		paragraph("Le journal se remplit…", nil, colors.textMuted)
		return
	end
	heading("Quêtes en cours")
	local anyActive = false
	for _, questId in QuestDefinitions.ORDER do
		local progress = quests.active and quests.active[questId]
		local quest = QuestDefinitions.getQuest(questId)
		if progress and quest then
			anyActive = true
			local stage = quest.stages[progress.stage]
			local box = card()
			heading(quest.name, box)
			if stage then
				caption(string.upper(stage.title), box)
				paragraph(stage.journal, box, colors.text, Theme.fonts.hand)
				for _, objective in stage.objectives do
					local count = if type(progress.progress) == "table" then progress.progress[objective.id] or 0 else 0
					local done = count >= objective.count
					local counter = if objective.count > 1 then ` ({math.min(count, objective.count)}/{objective.count})` else ""
					paragraph(`{if done then "✓" else "•"} {objective.text}{counter}`, box, if done then colors.textMuted else colors.text)
				end
			end
		end
	end
	if not anyActive then
		paragraph("Aucune quête en cours.", nil, colors.textMuted)
	end
	if type(quests.available) == "table" and #quests.available > 0 then
		heading("À découvrir")
		for _, questId in quests.available do
			local quest = QuestDefinitions.getQuest(questId)
			if quest then
				local giver = NpcConfig.NPCS[quest.giver]
				paragraph(`• {quest.name} — {if giver then giver.name else "un habitant"} a quelque chose à vous demander.`)
			end
		end
	end
	if type(quests.completed) == "table" and next(quests.completed) ~= nil then
		heading("Accomplies")
		for _, questId in QuestDefinitions.ORDER do
			if quests.completed[questId] then
				local quest = QuestDefinitions.getQuest(questId)
				paragraph(`✓ {if quest then quest.name else questId}`, nil, colors.textMuted)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Contrats
--------------------------------------------------------------------------------

local function missionCard(mission: any, entry: any?, lockReason: string?)
	local box = card()
	heading(mission.name, box)
	local category = MissionDefinitions.CATEGORY_NAMES[mission.category] or mission.category
	local rotation = if mission.rotation == "daily" then "quotidien" elseif mission.rotation == "weekly" then "hebdomadaire" else "unique"
	caption(`{string.upper(category)}  ·  RANG {mission.minRank}  ·  {string.upper(rotation)}`, box)
	paragraph(mission.description, box, colors.textMuted)
	for _, objective in mission.objectives do
		local count = if entry and type(entry.progress) == "table" then entry.progress[objective.id] or 0 else 0
		local done = entry ~= nil and count >= objective.count
		local counter = if entry and objective.count > 1 then ` ({math.min(count, objective.count)}/{objective.count})` else ""
		paragraph(`{if done then "✓" else "•"} {objective.text}{counter}`, box)
	end
	paragraph(`Récompense : {describeRewards(mission.rewards)}`, box, colors.goldBright)
	if lockReason then
		paragraph(`Verrouillé : {lockReason}`, box, colors.danger)
		return
	end
	local row = buttonRow(box)
	if entry then
		addButton(row, "Rendre le contrat", "primary", entry.ready == true, function()
			request(MissionRemotes.MissionRequest, "claim", mission.id)
		end)
		addButton(row, "Abandonner", "ghost", true, function()
			request(MissionRemotes.MissionRequest, "abandon", mission.id)
		end)
	else
		addButton(row, "Accepter", "primary", true, function()
			request(MissionRemotes.MissionRequest, "accept", mission.id)
		end)
	end
end

local function renderMissions()
	local missions = PlayerState.get("missions")
	if type(missions) ~= "table" then
		paragraph("Le tableau est vide pour l'instant…", nil, colors.textMuted)
		return
	end
	caption(`Contrats acceptés et rendus au tableau du village (ou auprès d'Ysolde). Renouvellement quotidien dans {formatDuration(missions.secondsToDailyReset or 0)}.`)
	if type(missions.active) == "table" and #missions.active > 0 then
		heading(`En cours ({#missions.active}/{MissionDefinitions.MAX_ACTIVE})`)
		for _, entry in missions.active do
			local mission = MissionDefinitions.getMission(entry.id)
			if mission then
				missionCard(mission, entry, nil)
			end
		end
	end
	if type(missions.available) == "table" and #missions.available > 0 then
		heading("Disponibles")
		for _, missionId in missions.available do
			local mission = MissionDefinitions.getMission(missionId)
			if mission then
				missionCard(mission, nil, nil)
			end
		end
	end
	if type(missions.locked) == "table" and #missions.locked > 0 then
		heading("Hors de portée")
		for _, locked in missions.locked do
			local mission = MissionDefinitions.getMission(locked.id)
			if mission then
				missionCard(mission, nil, tostring(locked.reason))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Compagnons : groupe et guilde
--------------------------------------------------------------------------------

local function renderParty()
	heading("Groupe")
	local state = PlayerState.get("party")
	local party = type(state) == "table" and state.party or nil
	if type(state) == "table" and type(state.incomingInvites) == "table" then
		for _, invite in state.incomingInvites do
			local box = card()
			paragraph(`{invite.fromName} vous invite dans son groupe ({invite.size} membre(s)).`, box)
			local row = buttonRow(box)
			addButton(row, "Rejoindre", "primary", true, function()
				request(PartyRemotes.PartyRequest, "accept", { partyId = invite.partyId })
			end)
			addButton(row, "Refuser", "ghost", true, function()
				request(PartyRemotes.PartyRequest, "decline", { partyId = invite.partyId })
			end)
		end
	end
	local box = card()
	if party then
		caption(`{party.size}/{party.maxSize or (state.limits and state.limits.maxSize) or "?"} MEMBRES`, box)
		for _, member in party.members or {} do
			local line = `{if member.isLeader then "♛ " else "• "}{member.displayName or member.name}{if member.isYou then " (vous)" else ""}`
			if party.isLeader and not member.isYou then
				local row = buttonRow(box)
				local label = Theme.label({ parent = row, text = line, size = UDim2.fromOffset(240, 38), alignX = Enum.TextXAlignment.Left })
				label.LayoutOrder = 0
				addButton(row, "Exclure", "ghost", true, function()
					request(PartyRemotes.PartyRequest, "kick", { targetUserId = member.userId })
				end)
				addButton(row, "Nommer chef", "ghost", true, function()
					request(PartyRemotes.PartyRequest, "promote", { targetUserId = member.userId })
				end)
			else
				paragraph(line, box)
			end
		end
	else
		paragraph("Vous voyagez seul. Les contrats de groupe exigent au moins deux compagnons.", box, colors.textMuted)
	end
	local row = buttonRow(box)
	local nameBox = textBox(row, "Nom du joueur à inviter")
	addButton(row, "Inviter", "primary", true, function()
		if nameBox.Text ~= "" then
			request(PartyRemotes.PartyRequest, "invite", { targetName = nameBox.Text })
		end
	end)
	if party then
		addButton(row, "Quitter le groupe", "danger", true, function()
			request(PartyRemotes.PartyRequest, "leave", {})
		end)
	end
end

local function renderGuild()
	heading("Guilde")
	local state = PlayerState.get("guild")
	if type(state) ~= "table" then
		paragraph("Les registres des guildes s'ouvrent…", nil, colors.textMuted)
		return
	end
	if state.available == false then
		paragraph("Les registres des guildes sont momentanément inaccessibles. Réessayez dans un instant.", nil, colors.danger)
	end
	for _, invite in state.incomingInvites or {} do
		local box = card()
		paragraph(`{invite.inviterName} vous invite à rejoindre « {invite.guildName} ».`, box)
		local row = buttonRow(box)
		addButton(row, "Prêter serment", "primary", true, function()
			request(GuildRemotes.GuildRequest, "acceptInvite", { guildId = invite.guildId })
		end)
		addButton(row, "Refuser", "ghost", true, function()
			request(GuildRemotes.GuildRequest, "declineInvite", { guildId = invite.guildId })
		end)
	end
	local guild = state.guild
	if guild == nil then
		local box = card()
		paragraph(if state.pending then "Votre guilde se rappelle à vous…" else "Vous n'avez prêté serment à aucune guilde. Fondez la vôtre :", box, colors.textMuted)
		local limits = state.limits or {}
		local row = buttonRow(box)
		local nameBox = textBox(row, `Nom ({limits.nameMin or 3} à {limits.nameMax or 24} caractères)`)
		local descriptionBox = textBox(row, "Devise (facultatif)", 300)
		addButton(row, "Fonder", "primary", true, function()
			request(GuildRemotes.GuildRequest, "create", { name = nameBox.Text, description = descriptionBox.Text })
		end)
		return
	end
	local permissions = guild.permissions or {}
	local box = card()
	heading(`{guild.name}  —  niveau {guild.level} · {guild.levelName}`, box)
	caption(`{guild.memberCount}/{guild.maxMembers} MEMBRES  ·  {guild.xp} XP DE GUILDE{if guild.nextLevelXp then ` / {guild.nextLevelXp}` else ""}  ·  VOUS : {string.upper(guild.myRoleName or "")}`, box)
	paragraph(if guild.description ~= "" then guild.description else "(Aucune devise.)", box, colors.textMuted, Theme.fonts.hand)
	if permissions.setDescription then
		local row = buttonRow(box)
		local descriptionBox = textBox(row, "Nouvelle devise", 360)
		addButton(row, "Graver", "secondary", true, function()
			request(GuildRemotes.GuildRequest, "setDescription", { description = descriptionBox.Text })
		end)
	end
	-- Membres.
	heading("Membres")
	local members = card()
	for _, member in guild.members or {} do
		local row = buttonRow(members)
		local label = Theme.label({ parent = row, text = `{member.roleName} · {member.name}{if member.isYou then " (vous)" elseif member.online then " · en ligne" else ""}`, size = UDim2.fromOffset(300, 38), alignX = Enum.TextXAlignment.Left })
		label.LayoutOrder = 0
		if member.canPromote then
			addButton(row, "Promouvoir", "ghost", true, function()
				request(GuildRemotes.GuildRequest, "promote", { targetUserId = member.userId })
			end)
		end
		if member.canDemote then
			addButton(row, "Rétrograder", "ghost", true, function()
				request(GuildRemotes.GuildRequest, "demote", { targetUserId = member.userId })
			end)
		end
		if member.canKick then
			addButton(row, "Exclure", "danger", true, function()
				request(GuildRemotes.GuildRequest, "kick", { targetUserId = member.userId })
			end)
		end
		if member.canTransfer then
			addButton(row, "Transmettre", "ghost", true, function()
				request(GuildRemotes.GuildRequest, "transfer", { targetUserId = member.userId })
			end)
		end
	end
	if permissions.invite then
		local row = buttonRow(members)
		local nameBox = textBox(row, "Nom du joueur à inviter")
		addButton(row, "Inviter", "primary", true, function()
			if nameBox.Text ~= "" then
				request(GuildRemotes.GuildRequest, "invite", { targetName = nameBox.Text })
			end
		end)
	end
	-- Contrats collectifs.
	heading("Contrats de guilde")
	if (guild.claimableRewards or 0) > 0 then
		local row = buttonRow(content)
		addButton(row, `Réclamer {guild.claimableRewards} récompense(s)`, "primary", true, function()
			request(GuildRemotes.GuildRequest, "claimContractReward", {})
		end)
	end
	for _, contract in guild.contracts or {} do
		local contractBox = card()
		heading(contract.name, contractBox)
		paragraph(contract.description, contractBox, colors.textMuted)
		if not contract.unlocked then
			paragraph(`Niveau de guilde {contract.guildLevel} requis.`, contractBox, colors.textDim)
		else
			paragraph(`Progression : {contract.progress}/{contract.target}  ·  votre part : {contract.myContribution}{if contract.completed then "  ·  ACCOMPLI" else ""}`, contractBox)
			if contract.canStart then
				local row = buttonRow(contractBox)
				addButton(row, "Lancer", "secondary", true, function()
					request(GuildRemotes.GuildRequest, "startContract", { contractId = contract.id })
				end)
			end
		end
	end
	-- Chronique et départ.
	if type(guild.log) == "table" and #guild.log > 0 then
		heading("Chronique")
		for index = 1, math.min(6, #guild.log) do
			paragraph(`• {guild.log[index].text}`, nil, colors.textMuted)
		end
	end
	local row = buttonRow(content)
	addButton(row, "Quitter la guilde", "danger", true, function()
		request(GuildRemotes.GuildRequest, "leave", {})
	end)
end

local function renderCompanions()
	renderParty()
	renderGuild()
end

--------------------------------------------------------------------------------
-- Progression
--------------------------------------------------------------------------------

local function renderProgression()
	local progression = PlayerState.get("progression")
	if type(progression) == "table" then
		local rank = RankConfig.getRank(progression.rank)
		local box = card()
		heading(`Rang {rank.id} — {rank.name}`, box)
		if rank.perk then
			paragraph(rank.perk, box, colors.textMuted)
		end
		caption(`{progression.xp} XP  ·  {progression.reputation} RÉPUTATION  ·  {progression.discoveries or 0} DÉCOUVERTE(S)`, box)
		local nextRank = progression.nextRank
		if type(nextRank) == "table" then
			heading(`Vers le rang {nextRank.id}{if nextRank.comingSoon then " (bientôt)" else ""}`)
			local requirements = card()
			for _, requirement in nextRank.requirements or {} do
				local label = requirement.label
				if requirement.kind == "quest" then
					local quest = QuestDefinitions.getQuest(requirement.id)
					label = `Quête : {if quest then quest.name else requirement.id}`
				elseif requirement.kind == "mission" then
					local mission = MissionDefinitions.getMission(requirement.id)
					label = `Contrat : {if mission then mission.name else requirement.id}`
				end
				local counter = if requirement.target > 1 then ` ({math.min(requirement.current, requirement.target)}/{requirement.target})` else ""
				paragraph(`{if requirement.done then "✓" else "•"} {label}{counter}`, requirements, if requirement.done then colors.textMuted else colors.text)
			end
		end
	end
	heading("Inventaire")
	local inventory = PlayerState.get("inventory")
	local anyItem = false
	if type(inventory) == "table" then
		for itemId, count in inventory do
			if type(count) == "number" and count > 0 then
				anyItem = true
				local item = ItemConfig.getItem(itemId)
				paragraph(`• {if item then item.name else itemId} ×{count}`)
			end
		end
	end
	if not anyItem then
		paragraph("Vos poches sont vides.", nil, colors.textMuted)
	end
end

--------------------------------------------------------------------------------
-- Ouverture, onglets, rafraîchissement
--------------------------------------------------------------------------------

local RENDERERS: { [string]: () -> () } = {
	journal = renderJournal,
	missions = renderMissions,
	companions = renderCompanions,
	progression = renderProgression,
}

local function render()
	if not isOpen then
		return
	end
	clear()
	local renderer = RENDERERS[currentTab]
	if renderer then
		local isDone, problem = pcall(function()
			renderer()
		end)
		if not isDone then
			warn(`[Grimoire] Affichage de l'onglet {currentTab} impossible : {problem}`)
		end
	end
end

local function selectTab(tabId: string)
	currentTab = tabId
	for index, tab in TABS do
		if tab.id == tabId then
			tabs:select(index, true)
		end
	end
	setStatus(nil)
	render()
end

local function setOpen(open: boolean)
	if open and localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true then
		return
	end
	isOpen = open
	screen.gui.Enabled = open
	if open then
		render()
	end
end

tabs:onChanged(function(index: number)
	local tab = TABS[index]
	if tab then
		selectTab(tab.id)
	end
end)
closeButton:onActivated(function()
	setOpen(false)
end)
backdrop.Activated:Connect(function()
	setOpen(false)
end)

UIBus.OpenPanel:Connect(function(panel: string)
	local tabId = PANEL_TO_TAB[panel]
	if tabId then
		setOpen(true)
		selectTab(tabId)
	end
end)
UIBus.ClosePanels:Connect(function()
	setOpen(false)
end)

PlayerState.Changed:Connect(function(slice: string)
	if not isOpen then
		return
	end
	local watched = TAB_SLICES[currentTab]
	if watched and table.find(watched, slice) then
		render()
	end
end)

localPlayer:GetAttributeChangedSignal(CUSTOMIZING_ATTRIBUTE):Connect(function()
	if localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true then
		setOpen(false)
	end
end)

-- Touche J (lettre imprimée) et croix haut à la manette.
local binding = KeyBindings.BINDINGS.Grimoire
local grimoireKey = KeyboardLayout.findKeyCode(binding.letter or "J", binding.fallbackKeyCode)
ContextActionService:BindAction(ACTION_NAME, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		setOpen(not isOpen)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, grimoireKey, binding.gamepad or Enum.KeyCode.DPadUp)
