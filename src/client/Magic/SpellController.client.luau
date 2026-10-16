--!strict
--[[
	SpellController (LocalScript)
	Les deux sorts de la Magie Innée du joueur, côté client :
		- commandes (KeyBindings) : sort de base (1 / R1 / bouton tactile), sort secondaire
		  (2 / L2 / bouton tactile). Les chiffres sont des EMPLACEMENTS : « & » et « é » en AZERTY ;
		- visée : à la souris, le point du monde sous le curseur ; à la manette et au tactile, l'ennemi
		  le plus proche devant soi (dans la portée), sinon droit devant ;
		- avant d'envoyer : Mana et recharge vérifiés LOCALEMENT pour un retour immédiat (Mana
		  insuffisant : la jauge clignote, son étouffé) ; le serveur revérifie tout (RequestCast) ;
		- pose d'incantation (CharacterAnimator), son de lancement, effets (SpellEffects) pour tous
		  les sorts lancés par n'importe quel joueur (SpellCast / SpellImpact / ReactionTriggered).
	Le client n'envoie jamais de dégâts, de Mana ni d'état d'ennemi : un identifiant de sort et un point visé.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local SpellConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("SpellConfig") :: ModuleScript)
local SpellRemotes = require(sharedFolder:WaitForChild("Magic"):WaitForChild("SpellRemotes") :: ModuleScript)
local ResourceConfig = require(sharedFolder:WaitForChild("Combat"):WaitForChild("ResourceConfig") :: ModuleScript)

local clientFolder = script.Parent.Parent
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)
local SpellEffects = require(script.Parent:WaitForChild("SpellEffects") :: ModuleScript)

local CUSTOMIZING_ATTRIBUTE = "IsCustomizing"
local TIME_LOOP_ENTITY_TAG = "TimeLoopEntity"
local CHARGING_ATTRIBUTE = "Charging"
local SOFT_AIM_DOT = 0.35 -- cône de visée automatique (manette, tactile)
local MOUSE_RAY_LENGTH = 400

local localPlayer = Players.LocalPlayer
local isInDialogue = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getReadyCharacter(): (Model?, BasePart?)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if character == nil or humanoid == nil or root == nil or humanoid.Health <= 0 or root.Anchored then
		return nil, nil
	end
	if isInDialogue or localPlayer:GetAttribute(CUSTOMIZING_ATTRIBUTE) == true or localPlayer:GetAttribute(CHARGING_ATTRIBUTE) == true then
		return nil, nil
	end
	return character, root
end

local function numberAttribute(name: string, default: number): number
	local value = localPlayer:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function isMouseMode(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseWheel
		or last == Enum.UserInputType.Keyboard
end

-- Ennemi vivant le plus proche dans le cône devant le personnage, à portée.
local function findSoftTarget(root: BasePart, range: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = range
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	for _, model in CollectionService:GetTagged(TIME_LOOP_ENTITY_TAG) do
		if model:IsA("Model") and model:GetAttribute("Defeated") ~= true and model:IsDescendantOf(workspace) then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local enemyRoot = humanoid and humanoid.RootPart
			if humanoid and enemyRoot and humanoid.Health > 0 then
				local offset = (enemyRoot.Position - root.Position) * Vector3.new(1, 0, 1)
				local distance = offset.Magnitude
				if distance <= bestDistance and distance > 0.1 and look.Magnitude > 0.1 and offset.Unit:Dot(look.Unit) >= SOFT_AIM_DOT then
					best, bestDistance = enemyRoot.Position, distance
				end
			end
		end
	end
	return best
end

-- Point visé : sous le curseur (souris), sinon visée automatique douce, sinon droit devant.
local function getAimPoint(character: Model, root: BasePart, spell: any): Vector3
	local camera = workspace.CurrentCamera
	if camera and isMouseMode() then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(ray.Origin, ray.Direction * MOUSE_RAY_LENGTH, params)
		if result then
			return result.Position
		end
		return ray.Origin + ray.Direction * spell.range
	end
	return findSoftTarget(root, spell.range) or (root.Position + root.CFrame.LookVector * math.min(spell.range, 25))
end

-- Le personnage se tourne vers le point visé (à plat) au moment du lancement.
local function faceTowards(root: BasePart, point: Vector3)
	local flat = Vector3.new(point.X, root.Position.Y, point.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

local function denyMana(spellId: string)
	UIBus.ManaDenied:Fire(spellId)
	SfxPlayer.play("manaEmpty")
end

--------------------------------------------------------------------------------
-- Lancement
--------------------------------------------------------------------------------

local function castSlot(slot: string)
	local character, root = getReadyCharacter()
	if character == nil or root == nil then
		return
	end
	local spell = SpellConfig.forMagic(MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE)).id, slot)
	if spell == nil then
		return
	end
	-- Retours immédiats ; le serveur reste seul juge.
	if localPlayer:GetAttribute(SpellConfig.CASTING_ATTRIBUTE) ~= nil then
		return
	end
	if numberAttribute(SpellConfig.READY_ATTRIBUTE_PREFIX .. spell.id, 0) > workspace:GetServerTimeNow() + 0.05 then
		return -- en recharge (le HUD l'affiche)
	end
	if numberAttribute(ResourceConfig.MANA_ATTRIBUTE, 0) + 1e-6 < spell.manaCost then
		denyMana(spell.id)
		return
	end
	local aimPoint = if spell.kind == "self" or spell.selfCentered then root.Position else getAimPoint(character, root, spell)
	if spell.kind ~= "self" and not spell.selfCentered then
		faceTowards(root, aimPoint)
	end
	SpellRemotes.RequestCast:FireServer(spell.id, aimPoint)
	CharacterAnimator.get(character, true):play(spell.action)
	SfxPlayer.play(`cast_{spell.magic}`, root)
end

local function bindSlot(actionName: string, bindingName: string, slot: string)
	local binding = KeyBindings.BINDINGS[bindingName]
	ContextActionService:BindAction(actionName, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			castSlot(slot)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, binding.touch ~= nil, binding.keyCode or binding.fallbackKeyCode, binding.gamepad or Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(actionName, binding.label)
	if binding.touch then
		ContextActionService:SetPosition(actionName, binding.touch)
	end
end

bindSlot("SpellBase", "SpellBase", "base")
bindSlot("SpellSecondary", "SpellSecondary", "secondary")

UIBus.DialogueStateChanged:Connect(function(isOpen: boolean)
	isInDialogue = isOpen
end)

--------------------------------------------------------------------------------
-- Événements du serveur (tous les joueurs)
--------------------------------------------------------------------------------

local casters: { [number]: Model? } = {}

SpellRemotes.SpellCast.OnClientEvent:Connect(function(caster: any, spellId: any, castId: any, origin: any, aimPoint: any)
	local spell = SpellConfig.get(spellId)
	if spell == nil or type(castId) ~= "number" or typeof(origin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return
	end
	local casterModel = if typeof(caster) == "Instance" and caster:IsA("Model") then caster else nil
	casters[castId] = casterModel
	if casterModel and casterModel ~= localPlayer.Character then
		-- Pose d'incantation des autres joueurs (la nôtre est déjà jouée).
		CharacterAnimator.get(casterModel, false):play(spell.action)
		local root = casterModel:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			SfxPlayer.play(`cast_{spell.magic}`, root)
		end
	end
	SpellEffects.castStarted(casterModel, spell, castId, origin, aimPoint)
end)

SpellRemotes.SpellImpact.OnClientEvent:Connect(function(castId: any, spellId: any, position: any, targets: any)
	local spell = SpellConfig.get(spellId)
	if spell == nil or type(castId) ~= "number" or typeof(position) ~= "Vector3" then
		return
	end
	local caster = casters[castId]
	casters[castId] = nil
	SpellEffects.impact(castId, spell, position, if type(targets) == "table" then targets else {}, caster)
	SfxPlayer.play(`impact_{spell.magic}`, position)
end)

SpellRemotes.ReactionTriggered.OnClientEvent:Connect(function(target: any, reactionId: any, position: any)
	if typeof(position) ~= "Vector3" or type(reactionId) ~= "string" then
		return
	end
	SpellEffects.reaction(if typeof(target) == "Instance" and target:IsA("Model") then target else nil, reactionId, position)
	SfxPlayer.play("reaction", position)
end)

SpellRemotes.CastDenied.OnClientEvent:Connect(function(spellId: any, reason: any)
	if reason == "mana" and type(spellId) == "string" then
		denyMana(spellId)
	end
end)
