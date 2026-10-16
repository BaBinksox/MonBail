--!strict
--[[
	CombatController (LocalScript)
	Chef d'orchestre du combat à l'épée côté client (Combat 2.0) :
		- ATTAQUE (KeyBindings.Attack : clic gauche, R2, bouton tactile) :
			appui         coup du combo, tout de suite (soft-lock, pose, traînée, zone de frappe) ;
			              cinq coups distincts (CombatConfig.COMBO) ;
			appui pendant un coup : retenu pour le coup suivant SEULEMENT dans la dernière partie
			              du coup (COMBO_BUFFER_FRACTION) : marteler ne sert à rien ;
			maintenu      à la fin du coup, la lame se ramène : ATTAQUE CHARGÉE (ralenti, vulnérable),
			              relâchée = frappe d'autant plus forte ; pleine = brise les gardes ;
			appui juste après une PARADE PARFAITE : RIPOSTE (fenêtre COUNTER_WINDOW) ;
			appui EN L'AIR : ATTAQUE PLONGEANTE (chute rapide, onde d'impact à l'atterrissage) ;
		- soft-lock : au départ de chaque coup, le personnage se tourne vers l'ennemi le plus proche ;
		- zone de frappe : pendant la fenêtre de frappe, et seulement là, tout ennemi présent dans
		  la boîte est signalé au serveur (SpatialHitbox) ;
		- technique ultime (KeyBindings.Ultimate) quand la Tension est pleine ;
		- effets (CombatEffects, SfxPlayer) et poses (CharacterAnimator) en réaction.

	Le client ne retire jamais de points de vie et ne touche jamais à la Tension : il DEMANDE
	(RequestAttack, RequestChargeStart, ReportHit, RequestUltimate), CombatService vérifie et décide.
	Les jauges (Tension, Mana) sont affichées par le HUD de combat.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local combatFolder = sharedFolder:WaitForChild("Combat")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local KeyBindings = require(sharedFolder:WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local Config = require(combatFolder:WaitForChild("CombatConfig") :: ModuleScript)
local Remotes = require(combatFolder:WaitForChild("CombatRemotes") :: ModuleScript)
local SpatialHitbox = require(combatFolder:WaitForChild("SpatialHitbox") :: ModuleScript)

local clientFolder = script.Parent.Parent
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local SfxPlayer = require(clientFolder:WaitForChild("Audio"):WaitForChild("SfxPlayer") :: ModuleScript)
local MovementState = require(clientFolder:WaitForChild("Movement"):WaitForChild("MovementState") :: ModuleScript)
local UIBus = require(clientFolder:WaitForChild("UI"):WaitForChild("UIBus") :: ModuleScript)
local CombatEffects = require(script.Parent:WaitForChild("CombatEffects") :: ModuleScript)
local SoftLock = require(script.Parent:WaitForChild("SoftLock") :: ModuleScript)

local ATTACK_ACTION = "SwordAttack"
local ULTIMATE_ACTION = "Ultimate"
local PLUNGE_MIN_HEIGHT = 3 -- studs de vide sous les pieds (le serveur exige 2,5)
local PLUNGE_IMPACT_WINDOW = 0.15 -- s de zone de frappe à l'atterrissage
local PLUNGE_HORIZONTAL_KEEP = 0.25 -- part de la vitesse horizontale gardée pendant la chute
local TIME_LOOP_ENTITY_TAG = "TimeLoopEntity" -- = TimeLoopConfig.ENTITY_TAG

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local isAttacking = false -- une attaque (ou un enchaînement) est en cours
local currentStep: any = nil -- coup en cours
local currentStartClock = 0
local hasBufferedInput = false -- appui retenu pour le coup suivant
local lastComboIndex = 0 -- dernier coup de combo terminé (0 = aucun)
local lastAttackEndClock = 0

local isPressed = false -- bouton d'attaque maintenu
local pressClock = 0
local isCharging = false
local chargeStartClock = 0
local chargeReadyClock = 0 -- os.clock() local : fin de la recharge de l'attaque chargée
local chargeFullNotified = false
local plungeReadyClock = 0

local isInDialogue = false
local hitbox: any = nil -- SpatialHitbox du personnage actuel
local hitboxRootPart: BasePart? = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Retourne le personnage local, son Humanoid, son RootPart et son épée s'il est en état d'agir.
local function getReadyCharacter(): (Model?, Humanoid?, BasePart?, Instance?)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	local sword = character and character:FindFirstChild(Config.SWORD_NAME)
	if character == nil or humanoid == nil or rootPart == nil or sword == nil then
		return nil, nil, nil, nil
	end
	-- Un RootPart ancré = joueur figé par le serveur (Hub, anomalie, rewind).
	if humanoid.Health <= 0 or rootPart.Anchored or isInDialogue then
		return nil, nil, nil, nil
	end
	if localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) == true or MovementState.concentrating then
		return nil, nil, nil, nil
	end
	return character, humanoid, rootPart, sword
end

local function animatorOf(character: Model): any
	return CharacterAnimator.get(character, true)
end

-- La zone de frappe est liée à un RootPart précis : on la reconstruit quand il change (respawn).
local function getHitbox(character: Model, rootPart: BasePart): any
	if hitboxRootPart ~= rootPart then
		hitbox = SpatialHitbox.new(rootPart, { character })
		hitboxRootPart = rootPart
	end
	return hitbox
end

-- Taille de la zone de frappe d'une attaque (identique côté serveur : CombatService.getHitboxSize).
local function getHitboxSize(step: any): Vector3
	return Config.HITBOX_SIZE + Vector3.new(step.widthBonus, 0, step.reachBonus)
end

local function getTension(): number
	local tension = localPlayer:GetAttribute(Config.TENSION_ATTRIBUTE)
	return if type(tension) == "number" then tension else 0
end

local function isCounterOpen(): boolean
	local untilTime = localPlayer:GetAttribute(Config.COUNTER_ATTRIBUTE)
	return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

-- Hauteur du vide sous les pieds (math.huge si aucun sol à portée).
local function getHeightAboveGround(character: Model, humanoid: Humanoid, rootPart: BasePart): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local feet = rootPart.Size.Y / 2 + humanoid.HipHeight
	local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -60, 0), params)
	return if result then (rootPart.Position.Y - result.Position.Y) - feet else math.huge
end

-- Le serveur décide de tout ; ce filtre évite seulement de jouer un faux impact (et d'envoyer une
-- demande inutile) sur un villageois, un ennemi déjà éliminé ou une cible invulnérable.
local function isPlausibleTarget(target: Model): boolean
	if target:GetAttribute(Config.INVULNERABLE_ATTRIBUTE) == true or target:GetAttribute("Defeated") == true then
		return false
	end
	if Players:GetPlayerFromCharacter(target) then
		return Config.PVP_ENABLED
	end
	return CollectionService:HasTag(target, TIME_LOOP_ENTITY_TAG)
end

local function makeHitHandler(step: any): (Model, Vector3) -> ()
	return function(target: Model, position: Vector3)
		if not isPlausibleTarget(target) then
			return
		end
		-- Retour immédiat pour l'attaquant (impact, arrêt sur image, secousse), sans attendre le
		-- serveur ; un coup bloqué ou une posture brisée sont ajoutés à sa confirmation.
		CombatEffects.playSwordHit(localPlayer.Character, target, position, true, {
			hitStop = step.hitStop,
			heavy = step.heavy or step.knockback > 0,
		})
		Remotes.ReportHit:FireServer(target)
	end
end

--------------------------------------------------------------------------------
-- Soft-lock
--------------------------------------------------------------------------------

-- Tourne le personnage vers l'ennemi le plus proche et verrouille cette orientation.
-- Retourne la fonction qui rend la rotation automatique au Humanoid (à appeler en fin de frappe).
local function lockOntoNearestEnemy(character: Model, humanoid: Humanoid, rootPart: BasePart): () -> ()
	local target = if Config.SOFT_LOCK_RADIUS > 0 then SoftLock.findTarget(character, rootPart, Config.SOFT_LOCK_RADIUS) else nil
	if target == nil then
		return function() end
	end
	SoftLock.face(rootPart, target)
	-- Sans cela, un joueur qui se déplace serait aussitôt retourné vers sa direction de marche
	-- et la zone de frappe partirait à côté.
	local previousAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	return function()
		humanoid.AutoRotate = previousAutoRotate
	end
end

--------------------------------------------------------------------------------
-- Une attaque
--------------------------------------------------------------------------------

--[[
	Exécute UNE attaque au sol du début à la fin (combo, chargée, riposte). YIELD pendant toute
	sa durée. `power` (0..1) : puissance de la charge, pour l'ampleur des effets.
]]
local function performStrike(character: Model, humanoid: Humanoid, rootPart: BasePart, sword: Instance, step: any, power: number)
	local hitWindow = step.hitEnd - step.hitStart
	currentStep = step
	currentStartClock = os.clock()

	local releaseLock = lockOntoNearestEnemy(character, humanoid, rootPart)
	animatorOf(character):play(step.action, { duration = step.duration })
	local isHeavy = step.heavy or step.knockback > 0 or power >= 1
	SfxPlayer.play(if isHeavy then "swordSwingHeavy" else "swordSwing", rootPart)

	-- Fenêtre de frappe : traînée et zone de frappe ne vivent qu'entre hitStart et hitEnd.
	-- La zone s'éteint d'elle-même au bout de la durée donnée (voir SpatialHitbox.start).
	task.wait(step.hitStart)
	if localPlayer.Character == character then
		CombatEffects.playBladeTrail(sword, hitWindow, isHeavy)
		getHitbox(character, rootPart):start(hitWindow, getHitboxSize(step), makeHitHandler(step), step.centered)
	end

	task.wait(hitWindow)
	releaseLock()
	task.wait(math.max(0, step.duration - step.hitEnd))
end

-- Lance une attaque et ses éventuels enchaînements. `firstKind` : 1..5, "charged" ou "counter".
local function runAttacks(firstKind: any, power: number)
	if isAttacking then
		return
	end
	isAttacking = true
	local kind = firstKind
	repeat
		hasBufferedInput = false
		local character, humanoid, rootPart, sword = getReadyCharacter()
		if character == nil or humanoid == nil or rootPart == nil or sword == nil then
			break
		end
		local step = if kind == "charged" then Config.CHARGED elseif kind == "counter" then Config.COUNTER else Config.COMBO[kind]
		Remotes.RequestAttack:FireServer(kind)

		-- pcall : une erreur pendant un coup ne doit pas laisser isAttacking bloqué à true.
		local isCompleted, errorMessage = pcall(function()
			performStrike(character, humanoid, rootPart, sword, step, power)
		end)
		if not isCompleted then
			humanoid.AutoRotate = true -- le soft-lock n'a peut-être pas pu rendre la rotation
			warn(`[Combat] Coup interrompu : {errorMessage}`)
			break
		end
		lastAttackEndClock = os.clock()
		if type(kind) == "number" then
			lastComboIndex = kind
		else
			lastComboIndex = 0
		end

		-- Suite : riposte prioritaire, puis coup suivant du combo s'il a été demandé à temps.
		if hasBufferedInput then
			if isCounterOpen() then
				kind = "counter"
			elseif lastComboIndex > 0 and lastComboIndex < #Config.COMBO then
				kind = lastComboIndex + 1
			else
				kind = 1
			end
			power = 1
		end
	until not hasBufferedInput
	currentStep = nil
	isAttacking = false
end

-- Le combo continue si le coup précédent n'était pas le dernier et vient juste de finir.
local function getNextComboIndex(): number
	local isComboAlive = lastComboIndex > 0
		and lastComboIndex < #Config.COMBO
		and os.clock() - lastAttackEndClock <= Config.COMBO_RESET_DELAY
	return if isComboAlive then lastComboIndex + 1 else 1
end

--------------------------------------------------------------------------------
-- Attaque chargée
--------------------------------------------------------------------------------

local function canStartCharge(): boolean
	return not isAttacking and not isCharging and os.clock() >= chargeReadyClock and not MovementState.airborne and getReadyCharacter() ~= nil
end

local function startCharge()
	local character = getReadyCharacter()
	if character == nil then
		return
	end
	isCharging = true
	chargeStartClock = os.clock()
	chargeFullNotified = false
	Remotes.RequestChargeStart:FireServer()
	animatorOf(character):play("sword_charge")
	CombatEffects.setChargeGlow(character, 0)
end

local function cancelCharge()
	if not isCharging then
		return
	end
	isCharging = false
	local character = localPlayer.Character
	if character then
		CharacterAnimator.get(character, true):stop("hold")
		CombatEffects.setChargeGlow(character, nil)
	end
end

local function releaseCharge()
	if not isCharging then
		return
	end
	local held = os.clock() - chargeStartClock
	cancelCharge()
	chargeReadyClock = os.clock() + Config.CHARGE_COOLDOWN
	local power = math.clamp(held / Config.CHARGE_FULL_TIME, 0, 1)
	task.spawn(runAttacks, "charged", power)
end

-- Suivi de la charge, image par image (seulement pendant qu'elle existe).
RunService.Heartbeat:Connect(function()
	if isCharging then
		local character = localPlayer.Character
		local held = os.clock() - chargeStartClock
		local ratio = math.clamp(held / Config.CHARGE_FULL_TIME, 0, 1)
		if character then
			CombatEffects.setChargeGlow(character, ratio)
		end
		if ratio >= 1 and not chargeFullNotified then
			chargeFullNotified = true
			SfxPlayer.play("chargeReady", character and character:FindFirstChild("HumanoidRootPart") :: any)
			if character then
				CombatEffects.playChargeReady(character)
			end
		end
		if getReadyCharacter() == nil then
			cancelCharge() -- mort, figé, dialogue : la charge tombe sans frapper
		elseif held >= Config.CHARGE_MAX_HOLD then
			releaseCharge() -- pas de posture éternelle : la frappe part d'elle-même
		end
	elseif isPressed and not isAttacking and os.clock() - pressClock >= Config.CHARGE_HOLD_THRESHOLD and canStartCharge() then
		-- Bouton toujours maintenu après le coup qu'il a lancé : la lame se ramène pour charger.
		startCharge()
	end
end)

--------------------------------------------------------------------------------
-- Attaque plongeante
--------------------------------------------------------------------------------

local function performPlunge(character: Model, humanoid: Humanoid, rootPart: BasePart, sword: Instance)
	isAttacking = true
	plungeReadyClock = os.clock() + Config.PLUNGE_COOLDOWN
	Remotes.RequestAttack:FireServer("plunge")
	local animator = animatorOf(character)
	animator:play("sword_plunge_fall")
	SfxPlayer.play("swordSwingHeavy", rootPart, { pitch = 0.85 })
	CombatEffects.playBladeTrail(sword, Config.PLUNGE.duration, true)

	-- Chute rapide : la vitesse verticale est imposée chaque image jusqu'au sol (ou la fin de la fenêtre).
	local startClock = os.clock()
	local landed = false
	while os.clock() - startClock < Config.PLUNGE.duration - PLUNGE_IMPACT_WINDOW do
		if localPlayer.Character ~= character or humanoid.Health <= 0 or rootPart.Anchored then
			break
		end
		if humanoid.FloorMaterial ~= Enum.Material.Air or getHeightAboveGround(character, humanoid, rootPart) < 0.6 then
			landed = true
			break
		end
		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X * PLUNGE_HORIZONTAL_KEEP, -Config.PLUNGE_SPEED, velocity.Z * PLUNGE_HORIZONTAL_KEEP)
		RunService.Heartbeat:Wait()
	end
	animator:stop("hold")
	if landed and localPlayer.Character == character then
		animator:play("sword_plunge")
		CombatEffects.playPlungeImpact(character, rootPart.Position - Vector3.new(0, rootPart.Size.Y / 2 + humanoid.HipHeight, 0))
		SfxPlayer.play("plungeImpact", rootPart)
		getHitbox(character, rootPart):start(PLUNGE_IMPACT_WINDOW, getHitboxSize(Config.PLUNGE), makeHitHandler(Config.PLUNGE), true)
		task.wait(0.3)
	end
	lastComboIndex = 0
	isAttacking = false
end

--------------------------------------------------------------------------------
-- Entrée d'attaque
--------------------------------------------------------------------------------

local function onAttackPressed()
	isPressed = true
	pressClock = os.clock()

	if isCharging then
		return
	end
	-- Pendant un coup : retenu pour le suivant, seulement dans la dernière partie du coup.
	if isAttacking then
		local step = currentStep
		if step then
			local elapsed = os.clock() - currentStartClock
			if elapsed >= step.duration * (1 - Config.COMBO_BUFFER_FRACTION) then
				hasBufferedInput = true
			end
		end
		return
	end

	local character, humanoid, rootPart, sword = getReadyCharacter()
	if character == nil or humanoid == nil or rootPart == nil or sword == nil then
		return
	end
	if isCounterOpen() then
		task.spawn(runAttacks, "counter", 1)
		return
	end
	if MovementState.airborne and os.clock() >= plungeReadyClock and getHeightAboveGround(character, humanoid, rootPart) >= PLUNGE_MIN_HEIGHT then
		task.spawn(function()
			local isCompleted, errorMessage = pcall(function()
				performPlunge(character, humanoid, rootPart, sword)
			end)
			if not isCompleted then
				isAttacking = false
				warn(`[Combat] Plongée interrompue : {errorMessage}`)
			end
		end)
		return
	end
	task.spawn(runAttacks, getNextComboIndex(), 1)
end

local function onAttackReleased()
	isPressed = false
	if isCharging then
		releaseCharge()
	end
end

-- Technique ultime. Ce test local évite juste d'envoyer une demande inutile : le serveur vérifie la jauge.
local function onUltimateInput()
	if getTension() < Config.TENSION_MAX or getReadyCharacter() == nil then
		return
	end
	cancelCharge()
	local character = localPlayer.Character
	if character then
		animatorOf(character):play("cast_ultimate")
	end
	Remotes.RequestUltimate:FireServer()
end

-- Mort ou respawn : on oublie le combo, la charge, et on coupe la zone de frappe du coup en cours.
local function resetCombat()
	hasBufferedInput = false
	lastComboIndex = 0
	isPressed = false
	isCharging = false
	if hitbox then
		hitbox:stop()
	end
end

--------------------------------------------------------------------------------
-- Liaisons des commandes
--------------------------------------------------------------------------------

local attackBinding = KeyBindings.BINDINGS.Attack
local ultimateBinding = KeyBindings.BINDINGS.Ultimate

-- Souris : UserInputService (un clic sur l'interface est « gameProcessed » et ne frappe pas).
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.UserInputType == attackBinding.mouse then
		onAttackPressed()
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == attackBinding.mouse then
		onAttackReleased()
	end
end)

-- Manette et tactile : ContextActionService (bouton tactile créé à la position de KeyBindings).
ContextActionService:BindAction(ATTACK_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		onAttackPressed()
		return Enum.ContextActionResult.Sink
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		onAttackReleased()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, attackBinding.touch ~= nil, attackBinding.gamepad or Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle(ATTACK_ACTION, attackBinding.label)
if attackBinding.touch then
	ContextActionService:SetPosition(ATTACK_ACTION, attackBinding.touch)
end

ContextActionService:BindAction(ULTIMATE_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		onUltimateInput()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, ultimateBinding.touch ~= nil, ultimateBinding.keyCode or ultimateBinding.fallbackKeyCode, ultimateBinding.gamepad or Enum.KeyCode.ButtonY)
ContextActionService:SetTitle(ULTIMATE_ACTION, ultimateBinding.label)
if ultimateBinding.touch then
	ContextActionService:SetPosition(ULTIMATE_ACTION, ultimateBinding.touch)
end

UIBus.DialogueStateChanged:Connect(function(isOpen: boolean)
	isInDialogue = isOpen
	if isOpen then
		cancelCharge()
	end
end)

localPlayer.CharacterAdded:Connect(resetCombat)

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

-- Un AUTRE joueur attaque : sa pose est jouée par l'AnimationDirector ; ici, la traînée de sa lame
-- et le souffle de son coup, pendant sa fenêtre de frappe.
Remotes.AttackStarted.OnClientEvent:Connect(function(attacker: Model?, comboIndex: any, action: any, power: any)
	local step: any = nil
	if action == "sword_charged" then
		step = Config.CHARGED
	elseif action == "sword_counter" then
		step = Config.COUNTER
	elseif action == "sword_plunge" then
		step = Config.PLUNGE
	elseif type(comboIndex) == "number" then
		step = Config.COMBO[comboIndex]
	end
	local sword = attacker and attacker:FindFirstChild(Config.SWORD_NAME)
	local root = attacker and attacker:FindFirstChild("HumanoidRootPart")
	if step == nil or sword == nil then
		return
	end
	local isHeavy = step.heavy or step.knockback > 0 or (type(power) == "number" and power >= 1)
	if root and root:IsA("BasePart") then
		SfxPlayer.play(if isHeavy then "swordSwingHeavy" else "swordSwing", root)
	end
	task.wait(step.hitStart)
	CombatEffects.playBladeTrail(sword, step.hitEnd - step.hitStart, isHeavy)
end)

-- Impact validé par le serveur. Pour nos propres coups, l'impact a déjà été joué à la détection :
-- on n'ajoute que ce que seul le serveur sait (garde qui bloque, posture brisée).
-- La caméra ne tremble que si c'est nous qui encaissons.
Remotes.HitConfirmed.OnClientEvent:Connect(function(attacker: Model?, target: Model?, _damage: any, result: any, hitStop: any)
	if target == nil then
		return
	end
	local localCharacter = localPlayer.Character
	local resultName = if type(result) == "string" then result else "hit"
	if attacker == localCharacter then
		if resultName ~= "hit" then
			CombatEffects.playHitResult(target, resultName, true)
		end
		return
	end
	CombatEffects.playSwordHit(attacker, target, nil, target == localCharacter, {
		hitStop = if type(hitStop) == "number" then hitStop else nil,
	})
	if resultName ~= "hit" then
		CombatEffects.playHitResult(target, resultName, false)
	end
end)

-- Ultime validé par le serveur (le nôtre ou celui d'un autre joueur) : place au spectacle,
-- aux couleurs de la magie du lanceur.
Remotes.UltimateFired.OnClientEvent:Connect(function(caster: Model?, origin: Vector3, targets: { Model }, magicId: string)
	if typeof(origin) == "Vector3" and type(targets) == "table" then
		SfxPlayer.play("ultimateActivate", origin)
		CombatEffects.playUltimate(caster, origin, targets, MagicConfig.getById(magicId))
	end
end)
