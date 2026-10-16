--!strict
--[[
	TimeLoopController (LocalScript)
	Côté client du Time-Loop :
		- envoie la demande de rewind au serveur (touche REWIND_KEY, croix bas à la manette) ;
		- met en scène l'anomalie et le rembobinage en réaction aux RemoteEvents du serveur :
		  l'image avec GlitchOverlay, le son avec TimeLoopAudio.

	Le client ne déplace rien et ne décide de rien : c'est le serveur qui fige, rembobine ou tue.

	Deux temps :
		anomalie (AnomalyOpened -> AnomalyClosed) : l'écran vacille, un message presse le joueur ;
		rewind   (RewindStarted -> RewindEnded)   : rupture de la réalité, chœur déformé,
		                                            compteur de magnétoscope qui remonte le temps.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeLoop")
local Config = require(sharedFolder:WaitForChild("TimeLoopConfig") :: ModuleScript)
local Remotes = require(sharedFolder:WaitForChild("TimeLoopRemotes") :: ModuleScript)
local KeyBindings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)

local modulesFolder = script.Parent:WaitForChild("TimeLoop")
local GlitchOverlay = require(modulesFolder:WaitForChild("GlitchOverlay") :: ModuleScript)
local TimeLoopAudio = require(modulesFolder:WaitForChild("TimeLoopAudio") :: ModuleScript)

local ANOMALY_FADE = 0.3 -- retour à la normale si l'anomalie se termine sans rewind
local REWIND_FADE = 0.5 -- retour à la normale après un rewind
local CAPTION_REFRESH = 0.05 -- secondes entre deux mises à jour du compteur

local isRewinding = false

GlitchOverlay.init(Players.LocalPlayer:WaitForChild("PlayerGui"))

--------------------------------------------------------------------------------
-- Compteur de rembobinage
--------------------------------------------------------------------------------

-- Affiche "<< REW  -3.2 s" en haut de l'écran : le temps remonté jusqu'ici, de 0 à REWIND_WINDOW,
-- pendant toute la durée du rewind. YIELD jusqu'à sa fin.
local function runRewindCaption(playbackDuration: number)
	local startClock = os.clock()
	while isRewinding do
		local progress = math.clamp((os.clock() - startClock) / playbackDuration, 0, 1)
		local blink = if math.floor(os.clock() * 4) % 2 == 0 then "<<" else "  "
		GlitchOverlay.setCaption(string.format("%s REW  -%.1f s", blink, progress * Config.REWIND_WINDOW))
		task.wait(CAPTION_REFRESH)
	end
	GlitchOverlay.setCaption("")
end

--------------------------------------------------------------------------------
-- Entrée joueur
--------------------------------------------------------------------------------

-- Clavier (REWIND_KEY) et manette (KeyBindings.Rewind : croix bas).
local rewindGamepad = KeyBindings.BINDINGS.Rewind.gamepad
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.REWIND_KEY or (rewindGamepad ~= nil and input.KeyCode == rewindGamepad) then
		Remotes.RequestRewind:FireServer()
	end
end)

--------------------------------------------------------------------------------
-- Réactions aux événements serveur
--------------------------------------------------------------------------------

-- Attaque fatale : le serveur nous a figés, l'écran vacille jusqu'à AnomalyClosed.
Remotes.AnomalyOpened.OnClientEvent:Connect(function(_windowDuration: number)
	GlitchOverlay.setMessage(Config.ANOMALY_MESSAGE)
	GlitchOverlay.start("anomaly")
end)

-- Fin de l'anomalie, quelle que soit l'issue (rewind accepté, mort, respawn).
Remotes.AnomalyClosed.OnClientEvent:Connect(function()
	GlitchOverlay.setMessage("")
	-- En cas de rewind, RewindStarted a pris le relais : on ne coupe pas son glitch.
	if not isRewinding then
		GlitchOverlay.stop(ANOMALY_FADE)
	end
end)

Remotes.RewindStarted.OnClientEvent:Connect(function(playbackDuration: number)
	isRewinding = true
	GlitchOverlay.setMessage("")
	GlitchOverlay.start("rewind")
	TimeLoopAudio.playRewind(playbackDuration)
	runRewindCaption(playbackDuration) -- yield jusqu'à RewindEnded
end)

Remotes.RewindEnded.OnClientEvent:Connect(function()
	isRewinding = false
	GlitchOverlay.stop(REWIND_FADE)
	TimeLoopAudio.fadeOut()
end)
