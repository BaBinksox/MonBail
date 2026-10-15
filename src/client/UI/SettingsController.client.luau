--!strict
--[[
	SettingsController
	Applique chez ce joueur les réglages qui ne relèvent d'aucun autre système :
		- la taille de l'interface (Theme.setUserScale), sur toutes les toiles ouvertes ;
		- en mode « effets réduits », les voiles d'ombre des Enfants de l'Ombre sont masqués
		  localement (les autres joueurs les voient toujours, selon leurs propres réglages).
	Les volumes sont appliqués par AudioMixer, les effets de lumière, de particules, de secousse et de
	glitch lisent ClientSettings eux-mêmes.
]]

local Players = game:GetService("Players")

local ClientSettings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ClientSettings") :: ModuleScript)
local Theme = require(script.Parent:WaitForChild("Theme") :: ModuleScript)

local VEIL_NAME = "ShadowVeil"

local function refreshVeils()
	local enabled = not ClientSettings.isReducedEffects()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, descendant in character:GetDescendants() do
				if descendant.Name == VEIL_NAME and descendant:IsA("ParticleEmitter") then
					descendant.Enabled = enabled
				end
			end
		end
	end
end

local function apply()
	local settings = ClientSettings.get()
	Theme.setUserScale(settings.uiScale)
	refreshVeils()
end

ClientSettings.Changed:Connect(apply)
-- Un voile d'ombre posé plus tard (apparition, changement d'apparence) suit le réglage.
local function watchCharacter(character: Model)
	character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == VEIL_NAME and descendant:IsA("ParticleEmitter") then
			descendant.Enabled = not ClientSettings.isReducedEffects()
		end
	end)
end
local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
apply()
