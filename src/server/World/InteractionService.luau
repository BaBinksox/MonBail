--!strict
--[[
	InteractionService
	Les objets interactifs de la Région 1 (Shared/World/MechanismConfig.INTERACTABLES).

	Pour chaque BasePart taggée "Interactable" (attribut InteractableId) posée par le générateur de
	carte, le SERVEUR crée un ProximityPrompt (touche F, X à la manette, appui tactile). Quand un joueur
	le déclenche, le serveur vérifie tout avant d'agir :
		- l'identifiant existe dans la configuration ;
		- le joueur est vivant, hors du Hub, à portée (distance revérifiée) et voit l'objet (raycast :
		  pas de coffre ouvert à travers un mur) ;
		- limite de fréquence ;
		- conditions propres à l'objet : magie requise, étape de quête, objets à consommer.
	Puis il applique l'effet selon le type (examine, board, rune, collect, chest, gate, teleport,
	power, anchor) et émet GameEvents.InteractableUsed (quêtes, missions).

	Retours au joueur : StateSync.notify(player, "text", { title, text }) pour les textes à lire,
	StateSync.notify(player, "openPanel", { panel }) pour les tableaux. Récompenses : RewardService,
	avec une clé unique par joueur ("chest:<id>", "collect:<id>") : un coffre ne paie qu'une fois.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Progression.ItemConfig)
local KeyBindings = require(ReplicatedStorage.Shared.Input.KeyBindings)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local MechanismConfig = require(ReplicatedStorage.Shared.World.MechanismConfig)
local RegionConfig = require(ReplicatedStorage.Shared.World.RegionConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local MechanismService = require(script.Parent.MechanismService)
local QuestService = require(script.Parent.Parent.Quest.QuestService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local RegionService = require(script.Parent.RegionService)
local RewardService = require(script.Parent.Parent.Progression.RewardService)
local StateSync = require(script.Parent.Parent.State.StateSync)
local WorldAnchors = require(script.Parent.WorldAnchors)

type Interactable = MechanismConfig.Interactable

local PROMPT_NAME = "InteractPrompt"
local DISTANCE_TOLERANCE = 6 -- studs de marge (latence, déplacement)
-- Attribut posé sur le prompt d'un objet réservé à une magie : le client le masque aux autres.
local REQUIRED_MAGIC_ATTRIBUTE = "RequiredMagic"
local BELL_RUNG_ATTRIBUTE = "BellRungAt" -- posé sur Workspace.World quand la cloche sonne (effet client)

local InteractionService = {}

local prompts: { [BasePart]: ProximityPrompt } = {}
local limiter = RateLimiter.new(2, 4)
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function tell(player: Player, title: string, text: string?)
	if text and text ~= "" then
		StateSync.notify(player, "text", { title = title, text = text })
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil
	end
	return rootPart
end

-- Aucun décor solide entre le joueur et l'objet (les personnages ne bloquent pas).
local function hasLineOfSight(player: Player, rootPart: BasePart, part: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { part }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local parentModel = part:FindFirstAncestorOfClass("Model")
	if parentModel then
		table.insert(ignore, parentModel)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local direction = part.Position - rootPart.Position
	local result = workspace:Raycast(rootPart.Position, direction, params)
	if result == nil then
		return true
	end
	-- Un autre personnage sur la trajectoire ne compte pas.
	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	return hitModel ~= nil and hitModel:FindFirstChildOfClass("Humanoid") ~= nil
end

local function teleport(player: Player, anchorId: string?): boolean
	local target = anchorId and WorldAnchors.getCFrame(anchorId)
	local character = player.Character
	if target == nil or character == nil then
		return false
	end
	pcall(function()
		player:RequestStreamAroundAsync(target.Position)
	end)
	character:PivotTo(target)
	return true
end

local function describeItems(items: { [string]: number }): string
	local names = {}
	for itemId, count in items do
		local item = ItemConfig.getItem(itemId)
		table.insert(names, `{if item then item.name else itemId} x{count}`)
	end
	return table.concat(names, ", ")
end

-- Condition de quête de l'objet : retourne (remplie, texte d'attente).
local function checkQuestRequirement(player: Player, interactable: Interactable): (boolean, string?)
	local requirement = interactable.requiresQuest
	if requirement == nil then
		return true, nil
	end
	if not QuestService.isAtStage(player, requirement.quest, requirement.stage) then
		return false, requirement.waitText
	end
	if requirement.objective and not QuestService.isObjectiveDone(player, requirement.quest, requirement.objective) then
		return false, requirement.waitText
	end
	return true, nil
end

local function used(player: Player, interactableId: string, interactable: Interactable)
	if interactable.discovery then
		RewardService.discover(player, interactable.discovery)
	end
	GameEvents.InteractableUsed:Fire(player, interactableId, interactable.kind)
end

--------------------------------------------------------------------------------
-- Effets par type
--------------------------------------------------------------------------------

local HANDLERS: { [string]: (player: Player, id: string, interactable: Interactable, part: BasePart) -> () } = {}

HANDLERS.examine = function(player, id, interactable, part)
	local isReady, waitText = checkQuestRequirement(player, interactable)
	if not isReady then
		-- L'objet se laisse quand même regarder : on lit son texte de base, sans effet de quête.
		tell(player, interactable.title, waitText or interactable.text)
		return
	end
	if interactable.consumes then
		if not RewardService.takeItems(player, interactable.consumes) then
			tell(player, interactable.title, `Il vous manque : {describeItems(interactable.consumes)}.`)
			return
		end
	end
	if id == "bell_main" then
		-- La cloche sonne : effet partagé par tous les clients proches (attribut lu par MechanismEffects).
		local world = workspace:FindFirstChild(RegionConfig.WORLD_FOLDER_NAME)
		if world then
			world:SetAttribute(BELL_RUNG_ATTRIBUTE, workspace:GetServerTimeNow())
		end
		tell(player, interactable.title, "Le battant reprend sa place. Un seul coup, immense, roule sur le village. Quelque part dans la forêt, des racines se rétractent.")
	else
		tell(player, interactable.title, interactable.text)
	end
	used(player, id, interactable)
end

HANDLERS.board = function(player, id, interactable, _part)
	StateSync.notify(player, "openPanel", { panel = interactable.board or "missions" })
	GameEvents.InteractableUsed:Fire(player, id, interactable.kind)
end

HANDLERS.rune = function(player, id, interactable, _part)
	local isSuccess, text = MechanismService.interact(player, id)
	tell(player, interactable.title, text)
	if isSuccess then
		GameEvents.InteractableUsed:Fire(player, id, interactable.kind)
	end
end

HANDLERS.power = HANDLERS.rune
HANDLERS.anchor = HANDLERS.rune

HANDLERS.collect = function(player, id, interactable, _part)
	local isReady, waitText = checkQuestRequirement(player, interactable)
	if not isReady then
		tell(player, interactable.title, waitText or "Vous ne pouvez pas le prendre.")
		return
	end
	if interactable.item == nil then
		return
	end
	local isGranted = RewardService.grant(player, `collect:{id}`, { items = { [interactable.item] = 1 } }, { reason = interactable.title })
	if not isGranted then
		tell(player, interactable.title, "Vous l'avez déjà pris.")
		return
	end
	used(player, id, interactable)
end

HANDLERS.chest = function(player, id, interactable, _part)
	local reward: any = interactable.reward or {}
	local isGranted = RewardService.grant(player, `chest:{id}`, {
		xp = reward.xp,
		reputation = reward.reputation,
		items = reward.items,
		discoveries = reward.discoveries,
	}, { reason = interactable.title })
	if not isGranted then
		tell(player, interactable.title, "Vide. Vous l'avez déjà ouvert.")
		return
	end
	used(player, id, interactable)
end

HANDLERS.gate = function(player, id, interactable, _part)
	local gateId = interactable.gate
	if gateId == nil then
		return
	end
	local isAllowed, text = RegionService.canPassGate(player, gateId)
	local gate = RegionConfig.GATES[gateId]
	if not isAllowed or (gate and gate.comingSoon) then
		tell(player, interactable.title, text)
		if isAllowed then
			used(player, id, interactable) -- conditions remplies : le joueur a "ouvert" la porte (contenu à venir)
		end
		return
	end
	-- Le joueur passe du côté opposé à celui où il se trouve.
	local rootPart = getRoot(player)
	local inside = interactable.insideAnchor and WorldAnchors.getCFrame(interactable.insideAnchor)
	local outside = interactable.outsideAnchor and WorldAnchors.getCFrame(interactable.outsideAnchor)
	local destination = interactable.insideAnchor
	if rootPart and inside and outside then
		local isInside = (rootPart.Position - inside.Position).Magnitude < (rootPart.Position - outside.Position).Magnitude
		destination = if isInside then interactable.outsideAnchor else interactable.insideAnchor
	end
	if teleport(player, destination) then
		tell(player, interactable.title, text)
		used(player, id, interactable)
	end
end

HANDLERS.teleport = function(player, id, interactable, _part)
	if teleport(player, interactable.insideAnchor) then
		used(player, id, interactable)
	end
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

local function onTriggered(player: Player, part: BasePart)
	if not limiter:allow(player) then
		return
	end
	local interactableId = part:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE)
	local interactable = if type(interactableId) == "string" then MechanismConfig.INTERACTABLES[interactableId] else nil
	local rootPart = getRoot(player)
	if interactable == nil or rootPart == nil or AvatarService.isCustomizing(player) then
		return
	end
	local maxDistance = (interactable.maxDistance or MechanismConfig.DEFAULT_MAX_DISTANCE) + DISTANCE_TOLERANCE
	if (rootPart.Position - part.Position).Magnitude > maxDistance or not hasLineOfSight(player, rootPart, part) then
		return
	end
	-- Objet réservé à une magie (présence que seule l'Ombre perçoit...) : les autres n'en tirent rien.
	if interactable.requiresMagic and interactable.kind ~= "power" then
		if player:GetAttribute(MagicConfig.ATTRIBUTE) ~= interactable.requiresMagic then
			return
		end
	end
	local handler = HANDLERS[interactable.kind]
	if handler then
		local isHandled, message = pcall(function()
			handler(player, interactableId :: string, interactable, part)
		end)
		if not isHandled then
			warn(`[Interaction] {interactableId} : {message}`)
		end
	end
end

local function addPrompt(instance: Instance)
	if not instance:IsA("BasePart") or prompts[instance] or not instance:IsDescendantOf(workspace) then
		return
	end
	local interactableId = instance:GetAttribute(RegionConfig.INTERACTABLE_ATTRIBUTE)
	local interactable = if type(interactableId) == "string" then MechanismConfig.INTERACTABLES[interactableId] else nil
	if interactable == nil then
		warn(`[Interaction] {instance:GetFullName()} porte un InteractableId inconnu : {interactableId}`)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = interactable.prompt
	prompt.ObjectText = if interactable.requiresMagic and interactable.kind == "power"
		then `{interactable.title} ({MagicConfig.getById(interactable.requiresMagic).name})`
		else interactable.title
	prompt.KeyboardKeyCode = KeyBindings.PROMPT_KEY
	prompt.GamepadKeyCode = KeyBindings.PROMPT_GAMEPAD_KEY
	prompt.MaxActivationDistance = interactable.maxDistance or MechanismConfig.DEFAULT_MAX_DISTANCE
	prompt.HoldDuration = interactable.holdDuration or 0
	prompt.RequiresLineOfSight = true
	if interactable.requiresMagic and interactable.kind ~= "power" then
		prompt:SetAttribute(REQUIRED_MAGIC_ATTRIBUTE, interactable.requiresMagic)
	end
	prompt.Parent = instance
	prompts[instance] = prompt

	prompt.Triggered:Connect(function(player: Player)
		onTriggered(player, instance)
	end)
end

local function removePrompt(instance: Instance)
	if instance:IsA("BasePart") then
		local prompt = prompts[instance]
		prompts[instance] = nil
		if prompt then
			prompt:Destroy()
		end
	end
end

-- À appeler une seule fois au démarrage du serveur (après MechanismService et QuestService).
function InteractionService.start()
	if isStarted then
		return
	end
	isStarted = true
	CollectionService:GetInstanceAddedSignal(RegionConfig.INTERACTABLE_TAG):Connect(addPrompt)
	CollectionService:GetInstanceRemovedSignal(RegionConfig.INTERACTABLE_TAG):Connect(removePrompt)
	for _, instance in CollectionService:GetTagged(RegionConfig.INTERACTABLE_TAG) do
		addPrompt(instance)
	end
end

return InteractionService
