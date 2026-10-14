--!strict
--[[
	NPCInteraction (LocalScript)
	Parler aux villageois :
		- pose un ProximityPrompt ("Parler") sur chaque Model taggé "Villager" ;
		- au déclenchement, ouvre la boîte de dialogue et écrit les répliques lettre par lettre,
		  avec un petit son rétro, des pauses sur la ponctuation et un passage à la suite au clic ;
		- pendant le dialogue, le joueur ne bouge plus et ses touches de combat sont neutralisées.

	Tout est local : les prompts, le texte et le son n'existent que chez ce joueur. Le serveur est
	seulement prévenu (TalkStarted / TalkEnded) pour que le villageois s'arrête et le regarde.

	Entrées pendant un dialogue : clic n'importe où, F, Espace ou Entrée.
		- réplique en cours d'écriture -> elle s'affiche entièrement ;
		- réplique terminée            -> réplique suivante, ou fin du dialogue.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local npcFolder = sharedFolder:WaitForChild("NPC")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local Config = require(npcFolder:WaitForChild("DialogueConfig") :: ModuleScript)
local Remotes = require(npcFolder:WaitForChild("NPCRemotes") :: ModuleScript)

local DialogueView = require(script.Parent:WaitForChild("DialogueView") :: ModuleScript)

local ADVANCE_ACTION = "DialogueAdvance"
local SINK_ACTION = "DialogueSink"
local ACTION_PRIORITY = 3000 -- au-dessus des contrôles par défaut de Roblox
local PROMPT_NAME = "TalkPrompt"
local PROMPT_RETRY_DELAY = 1 -- secondes : un Model reçu en streaming peut arriver avant ses pièces
local PROMPT_MAX_RETRIES = 10

local localPlayer = Players.LocalPlayer
local view = DialogueView.create(localPlayer:WaitForChild("PlayerGui"))
local random = Random.new()

-- Créé depuis un LocalScript : ce son ne se joue que sur ce client.
local blip = Instance.new("Sound")
blip.Name = "DialogueBlip"
blip.SoundId = Config.BLIP_SOUND_ID
blip.Volume = Config.BLIP_VOLUME
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
	view.hint.Text = if lineIndex < #lines then "[F] ou clic : continuer" else "[F] ou clic : terminer"
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

	view.gui.Enabled = false
	ContextActionService:UnbindAction(ADVANCE_ACTION)
	ContextActionService:UnbindAction(SINK_ACTION)
	if controls then
		controls:Enable()
	end
	setPromptsEnabled(true)
	Remotes.TalkEnded:FireServer()
end

-- Clic ou touche pendant un dialogue.
local function advanceDialogue()
	if activeVillager == nil then
		return
	end

	if isTyping then
		typingToken += 1 -- l'écriture en cours s'arrête...
		finishLine() -- ...et la réplique s'affiche en entier
	elseif lineIndex < #lines then
		lineIndex += 1
		task.spawn(typeLine, lines[lineIndex])
	else
		closeDialogue()
	end
end

local function openDialogue(villager: Model)
	if activeVillager or localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true then
		return
	end
	activeVillager = villager
	lines = getDialogue(villager).lines
	lineIndex = 1

	view.namePlate.Text = getDisplayName(villager)
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

	-- Touches de jeu neutralisées pendant qu'on parle : ultime, dash, carte. Une entrée "absorbée"
	-- arrive aux autres scripts marquée gameProcessed, et ils l'ignorent. (R n'y est pas : une
	-- anomalie doit toujours pouvoir être rembobinée.)
	ContextActionService:BindActionAtPriority(SINK_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, Enum.KeyCode.E, Enum.KeyCode.LeftShift, Enum.KeyCode.M)

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
