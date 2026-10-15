--!strict
--[[
	AvatarService
	Façade serveur du Hub de création de personnage (singleton). Il orchestre, sans faire lui-même
	le travail de détail :
		- AvatarSerializer : valide les données du client, convertit vers / depuis la sauvegarde ;
		- AvatarAppearance : applique un choix sur le personnage ;
		- ProfileStore     : lit et écrit la sauvegarde (DataStore).

	Parcours d'un joueur :
		connexion -> chargement de son profil
		   a. profil avec un personnage : son apparence et sa Magie Innée sont appliquées
		      directement, à chaque apparition. Il ne voit jamais le Hub.
		   b. nouveau joueur : son personnage est figé et le Hub s'ouvre. À la validation,
		      le choix est appliqué, sauvegardé, et le joueur est libéré.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage.Shared.Avatar.AvatarConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local Remotes = require(ReplicatedStorage.Shared.Avatar.AvatarRemotes)

local AnchorService = require(script.Parent.Parent.Core.AnchorService)
local CharacterPlacement = require(script.Parent.Parent.Core.CharacterPlacement)
local AvatarAppearance = require(script.Parent.AvatarAppearance)
local AvatarSerializer = require(script.Parent.AvatarSerializer)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)

type Selection = AvatarConfig.Selection

type PlayerState = {
	savedSelection: Selection?, -- choix validé (ou chargé de la sauvegarde), réappliqué au respawn

	-- Hub
	isCustomizing: boolean,
	isConfirmPending: boolean, -- choix final reçu, fermeture dès que l'application est terminée
	frozenRootPart: BasePart?, -- figé par AnchorService (raison HUB_ANCHOR_REASON)
	groundY: number?, -- hauteur du sol sous le personnage figé

	-- File d'application : un seul ApplyDescription à la fois, seule la dernière demande compte
	isApplying: boolean,
	pendingSelection: Selection?,
}

local HUB_ANCHOR_REASON = "hub" -- ancrage compté : ne se mélange pas au rewind ni à l'anomalie

local AvatarService = {}

-- CreatorConfirmed(player) : le joueur vient de valider son personnage et le Hub se ferme
-- (SpawnService l'emmène alors au belvédère pour la cinématique d'arrivée).
AvatarService.CreatorConfirmed = Signal.new()

-- Appelé juste avant de figer un personnage pour ouvrir le Hub : permet de le placer d'abord sur la
-- scène du créateur (SpawnService). Le gel calcule le sol sous la NOUVELLE position.
local stagePlacer: ((player: Player, character: Model) -> ())? = nil

local states: { [Player]: PlayerState } = {}
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Publie la Magie Innée du joueur : CombatService la lit pour son ultime, le client pour son interface.
local function publishMagic(player: Player, selection: Selection)
	player:SetAttribute(MagicConfig.ATTRIBUTE, MagicConfig.MAGICS[selection.magicIndex].id)
end

--------------------------------------------------------------------------------
-- Gel du personnage pendant le Hub
--------------------------------------------------------------------------------

-- Un personnage ancré ne se repose pas tout seul au sol : quand sa taille change, on recale
-- son RootPart pour que ses pieds restent posés (sinon ils s'enfoncent ou flottent).
local function snapToGround(state: PlayerState, humanoid: Humanoid)
	local rootPart, groundY = state.frozenRootPart, state.groundY
	local character = humanoid.Parent
	if rootPart == nil or groundY == nil or character == nil or not character:IsA("Model") then
		return
	end

	-- Hauteur mesurée sur les pieds (HipHeight seulement en secours) : un HipHeight recalculé de
	-- travers après la reconstruction du rig enterrait le personnage dans la plateforme.
	local standingY = groundY + CharacterPlacement.getRootHeight(character) + 0.05
	rootPart.CFrame += Vector3.new(0, standingY - rootPart.Position.Y, 0)
end

local function freeze(state: PlayerState, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil then
		return
	end

	-- Sol praticable sous le personnage (CanCollide respecté : ni marqueur, ni décor, ni autre joueur).
	local ground = CharacterPlacement.findGround(rootPart.Position, { character })

	state.frozenRootPart = rootPart
	state.groundY = if ground then ground.Y else nil

	AnchorService.hold(rootPart, HUB_ANCHOR_REASON)
	snapToGround(state, humanoid)
end

local function unfreeze(state: PlayerState)
	if state.frozenRootPart then
		AnchorService.release(state.frozenRootPart, HUB_ANCHOR_REASON)
	end
	state.frozenRootPart = nil
	state.groundY = nil
end

--------------------------------------------------------------------------------
-- Hub
--------------------------------------------------------------------------------

local function openCreator(player: Player, state: PlayerState, character: Model)
	state.isCustomizing = true
	player:SetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE, true)
	if stagePlacer then
		local placer = stagePlacer
		local isPlaced, message = pcall(function()
			placer(player, character)
		end)
		if not isPlaced then
			warn(`[Avatar] Placement sur la scène du créateur impossible : {message}`)
		end
	end
	freeze(state, character)
	Remotes.OpenCreator:FireClient(player)
end

local function closeCreator(player: Player, state: PlayerState)
	state.isCustomizing = false
	state.isConfirmPending = false
	player:SetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE, false)
	Remotes.CreatorClosed:FireClient(player)
	-- Le personnage est emmené au belvédère ENCORE figé (SpawnService), puis libéré sur place : il ne
	-- passe aucune image en chute libre entre la scène du créateur et son point d'arrivée.
	AvatarService.CreatorConfirmed:Fire(player)
	unfreeze(state)
end

-- Applique les demandes en attente une par une. Si plusieurs aperçus arrivent pendant un
-- chargement, seul le plus récent est appliqué ensuite : le serveur ne peut pas être inondé.
local function processApplyQueue(player: Player, state: PlayerState)
	if state.isApplying then
		return
	end
	state.isApplying = true

	while states[player] == state do
		local selection = state.pendingSelection
		local character = player.Character
		if selection == nil or character == nil then
			break
		end
		state.pendingSelection = nil

		AvatarAppearance.apply(character, selection) -- yield

		local humanoid = getHumanoid(player)
		if humanoid then
			snapToGround(state, humanoid)
		end
	end

	state.isApplying = false

	-- La fermeture a lieu même si l'application a échoué (voir les warn d'AvatarAppearance) :
	-- un ID d'asset invalide ne doit pas enfermer le joueur dans le Hub.
	if state.isConfirmPending and states[player] == state then
		closeCreator(player, state)
	end
end

-- Aperçu : le joueur fait défiler une option, on la lui montre sans rien valider.
local function onPreviewRequested(player: Player, rawSelection: any)
	local state = states[player]
	local selection = AvatarSerializer.sanitizeSelection(rawSelection)
	if state == nil or selection == nil or not state.isCustomizing or state.isConfirmPending then
		return
	end

	state.pendingSelection = selection
	processApplyQueue(player, state)
end

-- Validation finale : on applique, on publie la magie, on sauvegarde, puis le Hub se ferme.
local function onApplyRequested(player: Player, rawSelection: any)
	local state = states[player]
	local selection = AvatarSerializer.sanitizeSelection(rawSelection)
	if state == nil or selection == nil or not state.isCustomizing or state.isConfirmPending then
		return
	end

	state.savedSelection = selection
	publishMagic(player, selection)

	local profile = ProfileStore.get(player)
	if profile then
		profile.avatar = AvatarSerializer.toSaved(selection)
		ProfileStore.markDirty(player)
		task.spawn(ProfileStore.save, player) -- en arrière-plan : le joueur n'attend pas le DataStore
	end

	state.pendingSelection = selection
	state.isConfirmPending = true
	processApplyQueue(player, state)
end

--------------------------------------------------------------------------------
-- Cycle de vie des joueurs
--------------------------------------------------------------------------------

-- Appelé quand un personnage vient d'apparaître avec son apparence Roblox chargée.
local function onCharacterReady(player: Player, character: Model)
	local state = states[player]
	if state == nil then
		return
	end

	if state.savedSelection and not state.isCustomizing then
		-- Joueur déjà créé (cette session ou une précédente) : on lui rend son apparence.
		state.pendingSelection = state.savedSelection
		processApplyQueue(player, state)
	else
		-- Nouveau joueur (ou mort pendant la création) : le Hub s'ouvre sur ce personnage.
		openCreator(player, state, character)
	end
end

-- YIELD : attend le chargement de la sauvegarde avant de décider quoi faire du joueur.
local function onPlayerAdded(player: Player)
	local state: PlayerState = {
		savedSelection = nil,
		isCustomizing = false,
		isConfirmPending = false,
		frozenRootPart = nil,
		groundY = nil,
		isApplying = false,
		pendingSelection = nil,
	}
	states[player] = state
	-- Tant qu'on ne sait pas si le joueur a déjà un personnage, les interfaces de jeu restent masquées.
	player:SetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE, true)

	local profile = ProfileStore.load(player) -- yield
	if states[player] ~= state then
		return -- le joueur est parti pendant le chargement
	end

	local savedSelection = AvatarSerializer.fromSaved(profile.avatar)
	if savedSelection and not AvatarConfig.DEBUG_ALWAYS_OPEN_CREATOR then
		state.savedSelection = savedSelection
		publishMagic(player, savedSelection)
		player:SetAttribute(AvatarConfig.CUSTOMIZING_ATTRIBUTE, false)
	end

	player.CharacterAppearanceLoaded:Connect(function(character: Model)
		onCharacterReady(player, character)
	end)
	if player.Character and player:HasAppearanceLoaded() then
		onCharacterReady(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
	ProfileStore.release(player) -- yield : dernière sauvegarde
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- À appeler une seule fois au démarrage du serveur.
function AvatarService.start()
	if isStarted then
		return
	end
	isStarted = true

	Remotes.PreviewAvatar.OnServerEvent:Connect(onPreviewRequested)
	Remotes.ApplyAvatar.OnServerEvent:Connect(onApplyRequested)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player) -- en parallèle : chaque chargement de profil est un yield
	end
end

-- Enregistre la fonction qui place un personnage sur la scène du créateur (voir stagePlacer).
function AvatarService.setStagePlacer(placer: (player: Player, character: Model) -> ())
	stagePlacer = placer
end

-- true si le joueur a un personnage validé (sauvegardé ou créé pendant cette session).
function AvatarService.hasCharacter(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.savedSelection ~= nil
end

-- true tant que le joueur est dans le Hub (figé, hors combat).
function AvatarService.isCustomizing(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.isCustomizing
end

return AvatarService
