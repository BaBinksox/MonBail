--!strict
--[[
	NPCInteraction (LocalScript)
	Parler aux villageois :
		- pose un ProximityPrompt ("Parler") sur chaque Model taggé "Villager" ;
		- au déclenchement, ouvre la boîte de dialogue et écrit les répliques lettre par lettre,
		  avec un petit son rétro, des pauses sur la ponctuation et un passage à la suite au clic ;
		- pendant le dialogue, le joueur ne bouge plus et ses touches de combat sont neutralisées.

	Les prompts, le texte et le son n'existent que chez ce joueur. Le serveur est prévenu
	(TalkStarted / TalkEnded) pour que le villageois s'arrête et le regarde, et il FOURNIT les répliques
	liées aux quêtes et les choix (DialogueRemotes.GetDialogue) ; sans réponse du serveur (PNJ posé à la
	main, délai dépassé), le PNJ dit son texte habituel (DialogueConfig).

	Entrées pendant un dialogue : clic n'importe où, F, Espace ou Entrée.
		- réplique en cours d'écriture -> elle s'affiche entièrement ;
		- réplique terminée            -> réplique suivante, ou fin du dialogue.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local npcFolder = sharedFolder:WaitForChild("NPC")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local Config = require(npcFolder:WaitForChild("DialogueConfig") :: ModuleScript)
local KeyboardLayout = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyboardLayout") :: ModuleScript)
local Remotes = require(npcFolder:WaitForChild("NPCRemotes") :: ModuleScript)
local WorldMapConfig = require(sharedFolder:WaitForChild("World"):WaitForChild("WorldMapConfig") :: ModuleScript)

local DialogueRemotes = require(npcFolder:WaitForChild("DialogueRemotes") :: ModuleScript)

local DialogueView = require(script.Parent:WaitForChild("DialogueView") :: ModuleScript)
local AudioMixer = require(script.Parent.Parent:WaitForChild("Audio"):WaitForChild("AudioMixer") :: ModuleScript)
local UIBus = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)

local ADVANCE_ACTION = "DialogueAdvance"
local SINK_ACTION = "DialogueSink"
local ACTION_PRIORITY = 3000 -- au-dessus des contrôles par défaut de Roblox
local PROMPT_NAME = "TalkPrompt"
local PROMPT_RETRY_DELAY = 1 -- secondes : un Model reçu en streaming peut arriver avant ses pièces
local PROMPT_MAX_RETRIES = 10
local SERVER_DIALOGUE_TIMEOUT = 3 -- secondes : au-delà, le PNJ dit son texte habituel
local OPTION_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
local OPTION_ACTION = "DialogueOption"

local localPlayer = Players.LocalPlayer
local view = DialogueView.create(localPlayer:WaitForChild("PlayerGui"))
local random = Random.new()

-- Créé depuis un LocalScript : ce son ne se joue que sur ce client.
local blip = Instance.new("Sound")
blip.Name = "DialogueBlip"
blip.SoundId = Config.BLIP_SOUND_ID
blip.Volume = Config.BLIP_VOLUME
AudioMixer.assign(blip, "Sfx")
blip.Parent = SoundService

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local prompts: { [Model]: ProximityPrompt } = {}

local activeVillager: Model? = nil -- villageois avec qui on parle (nil = pas de dialogue)
local lines: { string } = {}
local lineIndex = 0
local isTyping = false
local typingToken = 0 -- change à chaque réplique : arrête l'écriture de la précédente
local dialogueOptions: { { id: string, label: string } } = {} -- choix proposés par le serveur à la fin
local isChoosing = false -- les choix sont affichés : le clic ne ferme plus le dialogue

-- Contrôles de déplacement de Roblox, pour immobiliser le joueur pendant un dialogue.
local controls: any = nil
task.spawn(function()
	local isLoaded, playerModule = pcall(function()
		local playerScripts = localPlayer:WaitForChild("PlayerScripts")
		return require(playerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if isLoaded then
		controls = playerModule:GetControls()
	end
end)

--------------------------------------------------------------------------------
-- Contenu d'un dialogue
--------------------------------------------------------------------------------

-- Dialogue générique d'un villageois sans DialogueId : choisi d'après son nom,
-- donc toujours le même pour lui, mais différent d'un villageois à l'autre.
local function getGenericDialogue(villager: Model): any
	local hash = 0
	for index = 1, #villager.Name do
		hash += string.byte(villager.Name, index)
	end
	local genericIds = Config.GENERIC_DIALOGUE_IDS
	return Config.DIALOGUES[genericIds[hash % #genericIds + 1]]
end

local function getDialogue(villager: Model): any
	local dialogueId = villager:GetAttribute(Config.DIALOGUE_ATTRIBUTE)
	local dialogue = if type(dialogueId) == "string" then Config.DIALOGUES[dialogueId] else nil
	return dialogue or getGenericDialogue(villager)
end

local function getDisplayName(villager: Model): string
	local customName = villager:GetAttribute(Config.NAME_ATTRIBUTE)
	if type(customName) == "string" and customName ~= "" then
		return customName
	end
	return getDialogue(villager).name or villager.Name
end

--------------------------------------------------------------------------------
-- Machine à écrire
--------------------------------------------------------------------------------

local function playBlip()
	if Config.BLIP_SOUND_ID == "" then
		return
	end
	blip.PlaybackSpeed = random:NextNumber(Config.BLIP_SPEED_MIN, Config.BLIP_SPEED_MAX)
	-- PlayLocalSound joue une copie : deux bips rapprochés se superposent au lieu de se couper.
	SoundService:PlayLocalSound(blip)
end

-- Temps d'attente après avoir affiché `character` : plus long sur la ponctuation, comme une respiration.
local function getLetterDelay(character: string): number
	if character == "." or character == "!" or character == "?" then
		return Config.SENTENCE_PAUSE
	elseif character == "," or character == ";" or character == ":" then
		return Config.COMMA_PAUSE
	end
	return 1 / Config.LETTERS_PER_SECOND
end

-- La réplique est entièrement affichée : on montre comment continuer.
local function finishLine()
	isTyping = false
	view.line.MaxVisibleGraphemes = -1 -- -1 = tout le texte
	view.hint.Text = if lineIndex < #lines then "[F] ou clic : continuer"
		elseif #dialogueOptions > 0 then "[F] ou clic : répondre"
		else "[F] ou clic : terminer"
	view.hint.Visible = true
end

-- Écrit `text` lettre par lettre. YIELD. S'arrête d'elle-même si une autre réplique a pris sa place.
local function typeLine(text: string)
	typingToken += 1
	local token = typingToken

	isTyping = true
	view.hint.Visible = false
	-- Le texte complet est posé d'un coup (la mise en page ne bouge pas), puis dévoilé caractère
	-- par caractère avec MaxVisibleGraphemes, qui compte correctement les lettres accentuées.
	view.line.Text = text
	view.line.MaxVisibleGraphemes = 0

	local shownCount = 0
	for _, codepoint in utf8.codes(text) do
		if token ~= typingToken then
			return
		end

		shownCount += 1
		view.line.MaxVisibleGraphemes = shownCount

		local character = utf8.char(codepoint)
		if character ~= " " and shownCount % Config.BLIP_INTERVAL == 0 then
			playBlip()
		end
		task.wait(getLetterDelay(character))
	end

	if token == typingToken then
		finishLine()
	end
end

--------------------------------------------------------------------------------
-- Déroulement d'un dialogue
--------------------------------------------------------------------------------

local function setPromptsEnabled(isEnabled: boolean)
	for _, prompt in prompts do
		prompt.Enabled = isEnabled
	end
end

local function closeDialogue()
	if activeVillager == nil then
		return
	end
	activeVillager = nil
	typingToken += 1 -- arrête l'écriture en cours
	isTyping = false
	isChoosing = false
	dialogueOptions = {}
	DialogueView.clearOptions(view)

	view.gui.Enabled = false
	ContextActionService:UnbindAction(ADVANCE_ACTION)
	ContextActionService:UnbindAction(SINK_ACTION)
	ContextActionService:UnbindAction(OPTION_ACTION)
	UIBus.DialogueStateChanged:Fire(false)
	if controls then
		controls:Enable()
	end
	setPromptsEnabled(true)
	Remotes.TalkEnded:FireServer()
end

-- Le joueur choisit une réponse : le serveur valide et dit quoi faire (fermer, ouvrir un panneau).
local function chooseOption(optionId: string)
	local villager = activeVillager
	if villager == nil or not isChoosing then
		return
	end
	isChoosing = false
	DialogueView.clearOptions(view)
	local isAnswered, result = pcall(function()
		return DialogueRemotes.ChooseOption:InvokeServer(villager, optionId)
	end)
	closeDialogue()
	if not isAnswered or type(result) ~= "table" then
		return
	end
	if result.action == "open_missions" then
		UIBus.OpenPanel:Fire("missions")
	elseif result.action == "open_guild" then
		UIBus.OpenPanel:Fire("guild")
	end
	if type(result.message) == "string" then
		UIBus.ShowText:Fire("", result.message)
	end
end

local function showOptions()
	isChoosing = true
	view.hint.Text = "1-" .. #dialogueOptions .. " ou clic sur un choix"
	local buttons = DialogueView.setOptions(view, dialogueOptions, chooseOption)
	GuiService.SelectedObject = buttons[1] -- manette : le premier choix est sélectionné
	local keys = {}
	for index = 1, math.min(#dialogueOptions, #OPTION_KEYS) do
		table.insert(keys, OPTION_KEYS[index])
	end
	ContextActionService:BindActionAtPriority(OPTION_ACTION, function(_actionName: string, state: Enum.UserInputState, input: InputObject)
		if state == Enum.UserInputState.Begin then
			local index = table.find(OPTION_KEYS, input.KeyCode)
			local option = index and dialogueOptions[index]
			if option then
				chooseOption(option.id)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(keys))
end

-- Clic ou touche pendant un dialogue.
local function advanceDialogue()
	if activeVillager == nil or isChoosing then
		return
	end

	if isTyping then
		typingToken += 1 -- l'écriture en cours s'arrête...
		finishLine() -- ...et la réplique s'affiche en entier
	elseif lineIndex < #lines then
		lineIndex += 1
		task.spawn(typeLine, lines[lineIndex])
	elseif #dialogueOptions > 0 then
		showOptions()
	else
		closeDialogue()
	end
end

-- Demande au serveur les répliques liées aux quêtes (YIELD, borné par SERVER_DIALOGUE_TIMEOUT).
local function fetchServerDialogue(villager: Model): any
	local result: any = nil
	local isDone = false
	task.spawn(function()
		local isAnswered, response = pcall(function()
			return DialogueRemotes.GetDialogue:InvokeServer(villager)
		end)
		result = if isAnswered then response else nil
		isDone = true
	end)
	local deadline = os.clock() + SERVER_DIALOGUE_TIMEOUT
	while not isDone and os.clock() < deadline do
		task.wait()
	end
	return result
end

local function openDialogue(villager: Model)
	if activeVillager or localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true then
		return
	end
	activeVillager = villager
	lines = getDialogue(villager).lines
	dialogueOptions = {}
	isChoosing = false
	lineIndex = 1

	-- Répliques et choix du serveur (quêtes, contrats...). Le texte habituel sert de repli.
	local server = fetchServerDialogue(villager)
	if activeVillager ~= villager then
		return -- fermé pendant l'attente (mort, PNJ disparu)
	end
	if type(server) == "table" then
		if type(server.lines) == "table" and #server.lines > 0 then
			lines = server.lines
		end
		if type(server.options) == "table" then
			dialogueOptions = server.options
		end
	end

	UIBus.DialogueStateChanged:Fire(true)
	UIBus.ClosePanels:Fire()
	view.namePlate.Text = if type(server) == "table" and type(server.name) == "string" then server.name else getDisplayName(villager)
	view.gui.Enabled = true
	setPromptsEnabled(false)
	if controls then
		controls:Disable()
	end
	Remotes.TalkStarted:FireServer(villager)

	-- Touches qui font avancer le dialogue.
	ContextActionService:BindActionAtPriority(ADVANCE_ACTION, function(_actionName: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			advanceDialogue()
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, Config.INTERACT_KEY, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)

	-- Touches de jeu neutralisées pendant qu'on parle : ultime, sprint (Maj), dash (C), carte. Une entrée "absorbée"
	-- arrive aux autres scripts marquée gameProcessed, et ils l'ignorent. (R n'y est pas : une
	-- anomalie doit toujours pouvoir être rembobinée.)
	-- La touche de la carte est cherchée par sa lettre : ce n'est pas KeyCode.M sur un clavier AZERTY.
	local mapKey = KeyboardLayout.findKeyCode(WorldMapConfig.TOGGLE_LETTER, WorldMapConfig.TOGGLE_KEY)
	ContextActionService:BindActionAtPriority(SINK_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, Enum.KeyCode.E, Enum.KeyCode.LeftShift, Enum.KeyCode.C, mapKey)

	task.spawn(typeLine, lines[lineIndex])
end

--------------------------------------------------------------------------------
-- Prompts des villageois
--------------------------------------------------------------------------------

local function findPromptPart(villager: Model): BasePart?
	local rootPart = villager:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	return villager.PrimaryPart or villager:FindFirstChildWhichIsA("BasePart", true)
end

local function addPrompt(instance: Instance)
	if not instance:IsA("Model") or prompts[instance] then
		return
	end
	local villager = instance

	-- En streaming, le Model peut arriver avant ses pièces : on réessaie un moment.
	local part = findPromptPart(villager)
	local retries = 0
	while part == nil and retries < PROMPT_MAX_RETRIES and villager.Parent ~= nil do
		retries += 1
		task.wait(PROMPT_RETRY_DELAY)
		part = findPromptPart(villager)
	end
	if part == nil or prompts[villager] then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = Config.ACTION_TEXT
	prompt.ObjectText = getDisplayName(villager)
	prompt.KeyboardKeyCode = Config.INTERACT_KEY
	prompt.MaxActivationDistance = Config.INTERACT_DISTANCE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = activeVillager == nil
	prompt.Parent = part
	prompts[villager] = prompt

	prompt.Triggered:Connect(function()
		openDialogue(villager)
	end)
end

local function removePrompt(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local prompt = prompts[instance]
	if prompt then
		prompts[instance] = nil
		prompt:Destroy()
	end
	if activeVillager == instance then
		closeDialogue() -- le villageois a disparu en pleine conversation
	end
end

CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(addPrompt)
CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(removePrompt)
for _, instance in CollectionService:GetTagged(Config.TAG) do
	task.spawn(addPrompt, instance)
end

--------------------------------------------------------------------------------
-- Entrées et cycle de vie
--------------------------------------------------------------------------------

view.clickCatcher.Activated:Connect(advanceDialogue)

-- Mort ou respawn en pleine conversation : on referme tout proprement.
localPlayer.CharacterAdded:Connect(closeDialogue)
