--!strict
--[[
	CombatController (LocalScript)
	Chef d'orchestre du combat côté client :
		- clic gauche : combo à l'épée (enchaînement, mémoire d'un clic, remise à zéro) ;
		  le coup part tout de suite en local (soft-lock, animation, traînée, zone de frappe) ;
		- soft-lock : au départ de chaque coup, le personnage se tourne vers l'ennemi le plus proche ;
		- zone de frappe : pendant la fenêtre de frappe, et seulement là, tout ennemi présent dans
		  la boîte devant le joueur est signalé au serveur (SpatialHitbox) ;
		- jauge de Tension : suit l'attribut du Player écrit par le serveur ;
		- touche E : demande l'ultime de sa Magie Innée quand la jauge est pleine ;
		- déclenche les VFX (CombatEffects) en réaction aux événements du serveur.

	Règle de base : rien ici ne tourne en continu. Tout part d'une entrée du joueur
	(onAttackInput, onUltimateInput) ou d'un événement du serveur.

	Le client ne retire jamais de points de vie et ne touche jamais à la Tension :
	il demande (RequestAttack, ReportHit, RequestUltimate), CombatService vérifie et décide.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local combatFolder = sharedFolder:WaitForChild("Combat")
local AvatarConfig = require(sharedFolder:WaitForChild("Avatar"):WaitForChild("AvatarConfig") :: ModuleScript)
local MagicConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("MagicConfig") :: ModuleScript)
local Config = require(combatFolder:WaitForChild("CombatConfig") :: ModuleScript)
local Remotes = require(combatFolder:WaitForChild("CombatRemotes") :: ModuleScript)
local SpatialHitbox = require(combatFolder:WaitForChild("SpatialHitbox") :: ModuleScript)

local CombatEffects = require(script.Parent:WaitForChild("CombatEffects") :: ModuleScript)
local SoftLock = require(script.Parent:WaitForChild("SoftLock") :: ModuleScript)
local SwingAnimator = require(script.Parent:WaitForChild("SwingAnimator") :: ModuleScript)
local TensionView = require(script.Parent:WaitForChild("TensionView") :: ModuleScript)

local GAUGE_FILL_DURATION = 0.25 -- la barre glisse vers sa nouvelle valeur
local GAUGE_PULSE_DURATION = 0.6 -- demi-période du clignotement quand la jauge est pleine
local GAUGE_STROKE_TRANSPARENCY = 0.4 -- liseré de la barre au repos (même valeur que dans TensionView)

local localPlayer = Players.LocalPlayer
local tensionView = TensionView.create(localPlayer:WaitForChild("PlayerGui"))

--------------------------------------------------------------------------------
-- État
--------------------------------------------------------------------------------

local isAttacking = false -- un coup (ou un enchaînement) est en cours
local hasBufferedInput = false -- un clic est arrivé pendant le coup : il déclenchera le suivant
local lastComboIndex = 0 -- dernier coup terminé (0 = aucun)
local lastAttackEndClock = 0 -- os.clock() de fin du dernier coup

local hitbox: any = nil -- SpatialHitbox du personnage actuel
local hitboxRootPart: BasePart? = nil

local gaugePulseTweens: { Tween } = {} -- clignotement de la jauge pleine (vide = pas de clignotement)

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
	if humanoid.Health <= 0 or rootPart.Anchored then
		return nil, nil, nil, nil
	end
	return character, humanoid, rootPart, sword
end

-- La zone de frappe est liée à un RootPart précis : on la reconstruit quand il change (respawn).
local function getHitbox(character: Model, rootPart: BasePart): any
	if hitboxRootPart ~= rootPart then
		hitbox = SpatialHitbox.new(rootPart, { character })
		hitboxRootPart = rootPart
	end
	return hitbox
end

-- Taille de la zone de frappe du coup `step` : la boîte de base, étirée vers l'avant par son allonge.
local function getHitboxSize(step: any): Vector3
	return Config.HITBOX_SIZE + Vector3.new(0, 0, step.reachBonus)
end

local function getTension(): number
	local tension = localPlayer:GetAttribute(Config.TENSION_ATTRIBUTE)
	return if type(tension) == "number" then tension else 0
end

-- Magie Innée du joueur local (la première de la liste tant qu'il n'a pas choisi).
local function getMagic(): any
	return MagicConfig.getById(localPlayer:GetAttribute(MagicConfig.ATTRIBUTE))
end

local function onHitboxHit(target: Model, position: Vector3)
	-- Retour immédiat pour l'attaquant (impact, hit-stop, secousse), sans attendre le serveur.
	CombatEffects.playSwordHit(localPlayer.Character, target, position, true)
	Remotes.ReportHit:FireServer(target)
end

--------------------------------------------------------------------------------
-- Combo à l'épée
--------------------------------------------------------------------------------

-- Le combo continue si le coup précédent n'était pas le dernier et vient juste de finir.
local function getNextComboIndex(): number
	local isComboAlive = lastComboIndex > 0
		and lastComboIndex < #Config.COMBO
		and os.clock() - lastAttackEndClock <= Config.COMBO_RESET_DELAY
	return if isComboAlive then lastComboIndex + 1 else 1
end

-- Soft-lock : tourne le personnage vers l'ennemi le plus proche et verrouille cette orientation.
-- Retourne la fonction qui rend la rotation automatique au Humanoid (à appeler en fin de frappe).
local function lockOntoNearestEnemy(character: Model, humanoid: Humanoid, rootPart: BasePart): () -> ()
	local target = if Config.SOFT_LOCK_RADIUS > 0
		then SoftLock.findTarget(character, rootPart, Config.SOFT_LOCK_RADIUS)
		else nil
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

-- Exécute UN coup du début à la fin. YIELD pendant toute sa durée.
local function performAttack(character: Model, humanoid: Humanoid, rootPart: BasePart, sword: Instance, comboIndex: number)
	local step = Config.COMBO[comboIndex]
	local hitWindow = step.hitEnd - step.hitStart

	local releaseLock = lockOntoNearestEnemy(character, humanoid, rootPart)
	Remotes.RequestAttack:FireServer(comboIndex)
	SwingAnimator.play(character, step)

	-- Fenêtre de frappe : traînée et zone de frappe ne vivent qu'entre hitStart et hitEnd.
	-- La zone s'éteint d'elle-même au bout de la durée donnée (voir SpatialHitbox.start).
	task.wait(step.hitStart)
	if localPlayer.Character == character then
		CombatEffects.playBladeTrail(sword, hitWindow)
		getHitbox(character, rootPart):start(hitWindow, getHitboxSize(step), onHitboxHit)
	end

	task.wait(hitWindow)
	releaseLock()

	task.wait(step.duration - step.hitEnd)
end

-- Seul point d'entrée d'une attaque à l'épée : appelé une fois par clic gauche.
local function onAttackInput()
	-- Clic pendant un coup : on le retient, il lancera le coup suivant dès la fin de celui-ci.
	if isAttacking then
		hasBufferedInput = true
		return
	end

	isAttacking = true
	repeat
		hasBufferedInput = false -- le clic qui nous amène ici est consommé

		local character, humanoid, rootPart, sword = getReadyCharacter()
		if character == nil or humanoid == nil or rootPart == nil or sword == nil then
			break
		end

		-- pcall : une erreur pendant un coup ne doit pas laisser isAttacking bloqué à true.
		local comboIndex = getNextComboIndex()
		local isCompleted, errorMessage = pcall(performAttack, character, humanoid, rootPart, sword, comboIndex)
		if not isCompleted then
			humanoid.AutoRotate = true -- le soft-lock n'a peut-être pas pu rendre la rotation
			warn(`[Combat] Coup interrompu : {errorMessage}`)
			break
		end
		lastComboIndex = comboIndex
		lastAttackEndClock = os.clock()
	until not hasBufferedInput -- pas de nouveau clic pendant le coup : on s'arrête
	isAttacking = false
end

-- Mort ou respawn : on oublie le combo et on coupe la zone de frappe du coup en cours.
local function resetCombat()
	hasBufferedInput = false
	lastComboIndex = 0
	if hitbox then
		hitbox:stop()
	end
end

--------------------------------------------------------------------------------
-- Pouvoir ultime
--------------------------------------------------------------------------------

-- Seul point d'entrée de l'ultime : appelé une fois par appui sur ULTIMATE_INPUT.
-- Ce test local évite juste d'envoyer une demande inutile ; c'est le serveur qui vérifie la jauge.
local function onUltimateInput()
	if getTension() < Config.TENSION_MAX or getReadyCharacter() == nil then
		return
	end
	Remotes.RequestUltimate:FireServer()
end

--------------------------------------------------------------------------------
-- Jauge de Tension
--------------------------------------------------------------------------------

local function stopGaugePulse()
	for _, pulseTween in gaugePulseTweens do
		pulseTween:Cancel()
	end
	gaugePulseTweens = {}
	tensionView.barStroke.Transparency = GAUGE_STROKE_TRANSPARENCY
	tensionView.prompt.TextTransparency = 0
end

-- Jauge pleine : le liseré et l'invite clignotent jusqu'à ce que la Tension soit dépensée.
-- (Deux tweens en boucle, arrêtés par stopGaugePulse : aucun script ne tourne pendant ce temps.)
local function startGaugePulse()
	if #gaugePulseTweens > 0 then
		return
	end
	local pulseInfo = TweenInfo.new(GAUGE_PULSE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	tensionView.barStroke.Transparency = 0
	gaugePulseTweens = {
		TweenService:Create(tensionView.barStroke, pulseInfo, { Transparency = 0.7 }),
		TweenService:Create(tensionView.prompt, pulseInfo, { TextTransparency = 0.6 }),
	}
	for _, pulseTween in gaugePulseTweens do
		pulseTween:Play()
	end
end

-- Recopie la Tension du serveur dans l'interface. Appelé à chaque changement de l'attribut.
local function refreshGauge()
	local ratio = math.clamp(getTension() / Config.TENSION_MAX, 0, 1)
	local isFull = ratio >= 1

	local fillInfo = TweenInfo.new(GAUGE_FILL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(tensionView.fill, fillInfo, { Size = UDim2.fromScale(ratio, 1) }):Play()

	tensionView.prompt.Visible = isFull
	if isFull then
		startGaugePulse()
	else
		stopGaugePulse()
	end
end

-- L'invite porte le nom de l'ultime du joueur, à la couleur de sa magie.
local function refreshUltimatePrompt()
	local magic = getMagic()
	tensionView.prompt.Text = `[{Config.ULTIMATE_INPUT.Name}]  {magic.ultimateName}`
	tensionView.prompt.TextColor3 = magic.palette.glow
end

-- La jauge est masquée tant que le joueur est dans le Hub de création.
local function refreshGaugeVisibility()
	tensionView.gui.Enabled = localPlayer:GetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE) ~= true
end

localPlayer:GetAttributeChangedSignal(Config.TENSION_ATTRIBUTE):Connect(refreshGauge)
localPlayer:GetAttributeChangedSignal(MagicConfig.ATTRIBUTE):Connect(refreshUltimatePrompt)
localPlayer:GetAttributeChangedSignal(AvatarConfig.CUSTOMIZING_ATTRIBUTE):Connect(refreshGaugeVisibility)
refreshGauge()
refreshUltimatePrompt()
refreshGaugeVisibility()

--------------------------------------------------------------------------------
-- Entrée joueur
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return -- clic sur l'interface, saisie dans le chat...
	end

	if input.UserInputType == Config.ATTACK_INPUT then
		onAttackInput()
	elseif input.KeyCode == Config.ULTIMATE_INPUT then
		onUltimateInput()
	end
end)

localPlayer.CharacterAdded:Connect(resetCombat)

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

-- Un AUTRE joueur attaque : son animation est déjà répliquée par Roblox, il ne manque que
-- la traînée de sa lame, à allumer chez nous pendant sa fenêtre de frappe.
Remotes.AttackStarted.OnClientEvent:Connect(function(attacker: Model?, comboIndex: number)
	local step = Config.COMBO[comboIndex]
	local sword = attacker and attacker:FindFirstChild(Config.SWORD_NAME)
	if step == nil or sword == nil then
		return
	end

	task.wait(step.hitStart)
	CombatEffects.playBladeTrail(sword, step.hitEnd - step.hitStart)
end)

-- Impact validé par le serveur (coup d'un autre joueur ou du boss). Pour nos propres coups,
-- l'effet a déjà été joué à la détection. La caméra ne tremble que si c'est nous qui encaissons.
Remotes.HitConfirmed.OnClientEvent:Connect(function(attacker: Model?, target: Model?, _damage: number)
	local localCharacter = localPlayer.Character
	if target and attacker ~= localCharacter then
		CombatEffects.playSwordHit(attacker, target, nil, target == localCharacter)
	end
end)

-- Ultime validé par le serveur (le nôtre ou celui d'un autre joueur) : place au spectacle,
-- aux couleurs de la magie du lanceur.
Remotes.UltimateFired.OnClientEvent:Connect(function(caster: Model?, origin: Vector3, targets: { Model }, magicId: string)
	if typeof(origin) == "Vector3" and type(targets) == "table" then
		CombatEffects.playUltimate(caster, origin, targets, MagicConfig.getById(magicId))
	end
end)
