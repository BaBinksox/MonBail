--!strict
--[[
	MechanismService
	Les mécanismes à états de la Région 1 (règles dans Shared/World/MechanismConfig) :
		- "power"           : un objet que seule une Magie Innée précise réveille (brasero, voile maudit,
		                      conduit, eau dormante, mur sans ombre, bloc gravé) ;
		- "group_door"      : une porte qui s'ouvre quand plusieurs mécanismes sont actifs EN MÊME TEMPS ;
		- "rune_puzzle"     : une séquence à reproduire (runes du puits) ;
		- "temporal_anchor" : la touche R près de l'ancre rend au monde un état passé (le pont entier).

	Chaque activation CHANGE un état serveur, visible et praticable par tous : Parts qui deviennent
	solides ou traversables, Model qui glisse, lumières qui s'allument. Les objets dynamiques portent
	les attributs MechanismConfig.STATE_ATTRIBUTE / STATE_UNTIL_ATTRIBUTE pour les effets client.
	Retour automatique à l'état initial après la durée du mécanisme.

	Le client ne fait que désigner un InteractableId (via InteractionService) ou appuyer sur R : la
	magie du joueur (attribut posé par le serveur), la distance, les délais et l'ordre sont vérifiés ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local MechanismConfig = require(ReplicatedStorage.Shared.World.MechanismConfig)

local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)
local WorldAnchors = require(script.Parent.WorldAnchors)

type Mechanism = MechanismConfig.Mechanism

type PartState = { transparency: number, canCollide: boolean }

type DynamicState = {
	instance: Instance,
	isActive: boolean,
	token: number, -- change à chaque activation : un retour programmé périmé ne fait rien
	closedPivot: CFrame?, -- "slide" : position fermée (pivot initial)
	partStates: { [BasePart]: PartState }, -- état initial de chaque Part (toggle / appear)
}

local PUZZLE_WITNESS_RADIUS = 45 -- studs : joueurs crédités quand un puzzle est résolu près d'eux
local SLIDE_DURATION = 1.2 -- secondes de glissement
local DEFAULT_APPEAR_TRANSPARENCY = 0
local ACTIVE_TRANSPARENCY_ATTRIBUTE = "ActiveTransparency" -- facultatif, posé par le générateur

local MechanismService = {}

local dynamicStates: { [string]: DynamicState } = {}
local activeUntil: { [string]: number } = {} -- mécanisme -> os.clock() de fin d'activation
local cooldownUntil: { [string]: number } = {}
local runeProgress: { [string]: { sequence: { number }, lastTouchClock: number } } = {}
local isStarted = false

--------------------------------------------------------------------------------
-- Objets dynamiques
--------------------------------------------------------------------------------

local function getParts(instance: Instance): { BasePart }
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function getDynamic(dynamicId: string): DynamicState?
	local existing = dynamicStates[dynamicId]
	if existing and existing.instance:IsDescendantOf(workspace) then
		return existing
	end
	local instance = WorldAnchors.getDynamic(dynamicId)
	if instance == nil then
		return nil
	end
	local state: DynamicState = {
		instance = instance,
		isActive = false,
		token = 0,
		closedPivot = if instance:IsA("PVInstance") then instance:GetPivot() else nil,
		partStates = {},
	}
	for _, part in getParts(instance) do
		state.partStates[part] = { transparency = part.Transparency, canCollide = part.CanCollide }
	end
	dynamicStates[dynamicId] = state
	return state
end

local function slideTo(instance: Instance, target: CFrame)
	if not instance:IsA("PVInstance") then
		return
	end
	local start = instance:GetPivot()
	local elapsed = 0
	while elapsed < SLIDE_DURATION and instance.Parent do
		elapsed += RunService.Heartbeat:Wait()
		local alpha = math.clamp(elapsed / SLIDE_DURATION, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		instance:PivotTo(start:Lerp(target, eased))
	end
end

local EMBERS_LIT_COLOR = Color3.fromRGB(255, 128, 44)
local EMBERS_COLD_COLOR = Color3.fromRGB(38, 30, 27)

local function setLights(instance: Instance, isOn: boolean)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Light") or descendant:IsA("Fire") or descendant:IsA("ParticleEmitter") or descendant:IsA("Smoke") then
			(descendant :: any).Enabled = isOn
		elseif descendant:IsA("BasePart") and descendant.Name == "Embers" then
			-- Braises du brasero (voir PropsVillage.brazier) : vives allumé, noires éteint.
			descendant.Color = if isOn then EMBERS_LIT_COLOR else EMBERS_COLD_COLOR
		end
	end
end

-- Rune du puits allumée ou éteinte : attribut RuneLit (lisible par les clients) et glyphes recolorés
-- côté serveur (Parts "Rune" du même Model, voir PropsSacred.runeStone), visible par tous.
local RUNE_LIT_COLOR = Color3.fromRGB(120, 230, 255)
local RUNE_DIM_COLOR = Color3.fromRGB(52, 112, 128)
local function setRuneLit(part: BasePart, isLit: boolean)
	part:SetAttribute("RuneLit", isLit)
	local model = part.Parent
	if model == nil or not model:IsA("Model") then
		return
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Rune" then
			child.Color = if isLit then RUNE_LIT_COLOR else RUNE_DIM_COLOR
		end
	end
end

-- Applique l'état actif / inactif de l'objet dynamique selon sa règle (MechanismConfig.DYNAMICS).
local function applyDynamic(dynamicId: string, state: DynamicState, isActive: boolean)
	local rule = MechanismConfig.DYNAMICS[dynamicId]
	if rule == nil then
		return
	end
	state.isActive = isActive
	local instance = state.instance
	if rule.states == "toggle_collide" then
		for part, original in state.partStates do
			part.CanCollide = if isActive then false else original.canCollide
			part.Transparency = if isActive then 1 else original.transparency
		end
	elseif rule.states == "appear" then
		for part, original in state.partStates do
			local activeTransparency = part:GetAttribute(ACTIVE_TRANSPARENCY_ATTRIBUTE)
			part.CanCollide = if isActive then true else original.canCollide
			part.Transparency = if isActive
				then (if type(activeTransparency) == "number" then activeTransparency else DEFAULT_APPEAR_TRANSPARENCY)
				else original.transparency
		end
	elseif rule.states == "slide" then
		local openCFrame = WorldAnchors.getCFrame(`{dynamicId}_open`)
		local target = if isActive then openCFrame else state.closedPivot
		if target then
			task.spawn(slideTo, instance, target)
		end
	elseif rule.states == "light" then
		setLights(instance, isActive)
	end
end

-- Active l'objet dynamique `dynamicId` pendant `duration` s (prolonge une activation en cours).
local function activateDynamic(dynamicId: string, duration: number)
	local state = getDynamic(dynamicId)
	if state == nil then
		warn(`[Mechanism] Objet dynamique introuvable : {dynamicId} (la carte est-elle construite ?)`)
		return
	end
	state.token += 1
	local token = state.token
	if not state.isActive then
		applyDynamic(dynamicId, state, true)
	end
	state.instance:SetAttribute(MechanismConfig.STATE_ATTRIBUTE, true)
	state.instance:SetAttribute(MechanismConfig.STATE_UNTIL_ATTRIBUTE, workspace:GetServerTimeNow() + duration)
	task.delay(duration, function()
		if state.token == token and state.isActive then
			applyDynamic(dynamicId, state, false)
			state.instance:SetAttribute(MechanismConfig.STATE_ATTRIBUTE, false)
		end
	end)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isActive(mechanismId: string): boolean
	return (activeUntil[mechanismId] or 0) > os.clock()
end

local function getPlayersNear(position: Vector3, radius: number): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") and (rootPart.Position - position).Magnitude <= radius then
			table.insert(list, player)
		end
	end
	return list
end

local function activateMechanism(mechanismId: string, mechanism: Mechanism, player: Player?)
	local duration = mechanism.duration or 20
	activeUntil[mechanismId] = os.clock() + duration
	cooldownUntil[mechanismId] = os.clock() + duration + (mechanism.cooldown or 0)
	if mechanism.dynamic then
		activateDynamic(mechanism.dynamic, duration)
	end
	if player then
		GameEvents.MechanismActivated:Fire(player, mechanismId)
	end
end

-- Porte de groupe : tous les mécanismes requis sont-ils actifs en même temps ?
local function checkGroup(groupId: string, triggeredBy: Player)
	local group = MechanismConfig.MECHANISMS[groupId]
	if group == nil or group.kind ~= "group_door" or group.requires == nil or isActive(groupId) then
		return
	end
	for _, requiredId in group.requires do
		if not isActive(requiredId) then
			return
		end
	end
	activateMechanism(groupId, group, triggeredBy)
	local door = group.dynamic and WorldAnchors.getDynamic(group.dynamic)
	local position = if door and door:IsA("PVInstance") then door:GetPivot().Position else nil
	local witnesses = if position then getPlayersNear(position, PUZZLE_WITNESS_RADIUS * 2) else { triggeredBy }
	GameEvents.PuzzleSolved:Fire(witnesses, groupId)
end

--------------------------------------------------------------------------------
-- Interactions (appelées par InteractionService après ses propres vérifications)
--------------------------------------------------------------------------------

-- Mécanisme de Magie Innée. Retourne (succès, texte à afficher).
local function interactPower(player: Player, mechanismId: string, mechanism: Mechanism, title: string): (boolean, string)
	local magicId = player:GetAttribute(MagicConfig.ATTRIBUTE)
	if magicId ~= mechanism.magic then
		local required = MagicConfig.getById(mechanism.magic)
		return false, `{title} reste sourd à votre magie. Il faudrait la {required.name}.`
	end
	if isActive(mechanismId) then
		return false, "C'est déjà fait : la magie y circule encore."
	end
	if (cooldownUntil[mechanismId] or 0) > os.clock() then
		return false, "La force ancienne se repose. Réessayez dans un instant."
	end
	activateMechanism(mechanismId, mechanism, player)
	if mechanism.group then
		checkGroup(mechanism.group, player)
	end
	return true, mechanism.description
end

-- Rune du puzzle du puits. Retourne (succès, texte).
local function interactRune(player: Player, mechanismId: string, mechanism: Mechanism, runeIndex: number): (boolean, string)
	if isActive(mechanismId) then
		return false, "La dalle est déjà ouverte."
	end
	local sequence = mechanism.sequence or {}
	local progress = runeProgress[mechanismId]
	local now = os.clock()
	if progress == nil or now - progress.lastTouchClock > (mechanism.resetDelay or 10) then
		progress = { sequence = {}, lastTouchClock = now }
		runeProgress[mechanismId] = progress
	end
	local expected = sequence[#progress.sequence + 1]
	progress.lastTouchClock = now

	-- Retour visuel commun : la rune touchée s'illumine (attribut lu par les clients).
	local runeId = mechanism.runes and mechanism.runes[runeIndex]
	local runePart = runeId and WorldAnchors.getInteractable(runeId)
	if runeIndex ~= expected then
		runeProgress[mechanismId] = nil
		if mechanism.runes then
			for _, id in mechanism.runes do
				local part = WorldAnchors.getInteractable(id)
				if part then
					setRuneLit(part, false)
				end
			end
		end
		return false, "Les runes s'éteignent d'un coup. Ce n'était pas le bon ordre."
	end
	if runePart then
		setRuneLit(runePart, true)
	end
	table.insert(progress.sequence, runeIndex)
	if #progress.sequence < #sequence then
		return true, "La rune s'éveille d'une lueur froide."
	end

	-- Séquence complète : la dalle glisse, les témoins proches sont crédités.
	runeProgress[mechanismId] = nil
	activateMechanism(mechanismId, mechanism, player)
	local position = if runePart then runePart.Position else nil
	local witnesses = if position then getPlayersNear(position, PUZZLE_WITNESS_RADIUS) else { player }
	if not table.find(witnesses, player) then
		table.insert(witnesses, player)
	end
	GameEvents.PuzzleSolved:Fire(witnesses, mechanismId)
	task.delay(mechanism.duration or 120, function()
		if mechanism.runes then
			for _, id in mechanism.runes do
				local part = WorldAnchors.getInteractable(id)
				if part then
					setRuneLit(part, false)
				end
			end
		end
	end)
	return true, "Les quatre runes brûlent ensemble. La dalle du puits glisse dans un grondement : un escalier s'enfonce dans le noir."
end

--[[
	Interaction avec l'objet `interactableId` (déjà validé par InteractionService : distance, ligne de
	vue, état du joueur, fréquence). Retourne (succès, texte à afficher au joueur).
]]
function MechanismService.interact(player: Player, interactableId: string): (boolean, string)
	local interactable = MechanismConfig.INTERACTABLES[interactableId]
	local mechanismId = interactable and interactable.mechanism
	local mechanism = mechanismId and MechanismConfig.MECHANISMS[mechanismId]
	if interactable == nil or mechanismId == nil or mechanism == nil then
		return false, "Rien ne se passe."
	end
	if mechanism.kind == "power" then
		return interactPower(player, mechanismId, mechanism, interactable.title)
	elseif mechanism.kind == "rune_puzzle" then
		return interactRune(player, mechanismId, mechanism, interactable.runeIndex or 0)
	elseif mechanism.kind == "temporal_anchor" then
		return true, interactable.text or ""
	end
	return false, "Rien ne se passe."
end

-- R près d'une ancre temporelle (gestionnaire d'exploration de TimeLoopService). true = R consommé.
local function onExplorationRewind(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end
	for mechanismId, mechanism in MechanismConfig.MECHANISMS do
		if mechanism.kind ~= "temporal_anchor" or mechanism.anchorInteractable == nil then
			continue
		end
		local anchorPart = WorldAnchors.getInteractable(mechanism.anchorInteractable)
		if anchorPart and (anchorPart.Position - rootPart.Position).Magnitude <= (mechanism.radius or 16) then
			if (cooldownUntil[mechanismId] or 0) > os.clock() and not isActive(mechanismId) then
				return true -- l'ancre se repose : R est consommé sans rembobiner le joueur
			end
			activateMechanism(mechanismId, mechanism, player)
			return true
		end
	end
	return false
end

-- true si le mécanisme est actif en ce moment (porte ouverte, pont restauré...).
function MechanismService.isActive(mechanismId: string): boolean
	return isActive(mechanismId)
end

-- À appeler une seule fois au démarrage du serveur (après TimeLoopService).
function MechanismService.start()
	if isStarted then
		return
	end
	isStarted = true
	TimeLoopService.setExplorationHandler(onExplorationRewind)
end

return MechanismService
