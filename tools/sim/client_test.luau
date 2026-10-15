-- Test de simulation de TOUS les LocalScripts du projet (outil, hors Roblox) pour un joueur local :
-- création, HUD (rang, suivi de quête, texte examiné), Grimoire (contrats, guilde) piloté par ses
-- boutons, parade, télégraphes des ennemis. Vérifie surtout qu'aucun script client ne plante.
local H = require("./helpers")()
local mock, runtime, env = H.mock, H.runtime, H.env
local Enum = mock.Enum

print("== Serveur et client")
H.boot()
local player = runtime.addPlayer("Lysandre", 7001)
local C = require("./client")(mock, runtime, player)
local scripts = {}
for path, _ in pairs(env.instances) do
	local inst = env.instances[path]
	if string.find(path, "^StarterPlayer/StarterPlayerScripts/Client/") and rawget(inst, "ClassName") == "LocalScript" then
		table.insert(scripts, path)
	end
end
table.sort(scripts)
for _, path in ipairs(scripts) do
	mock.task.spawn(function()
		env.run(path)
	end)
end
H.advance(1)
H.check(#scripts .. " LocalScripts chargés", #scripts >= 14, #scripts)
H.noNewErrors("chargement des scripts client")

runtime.spawnCharacter(player)
H.advance(4)
local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
AvatarRemotes.ApplyAvatar:FireServer(H.selection(2))
H.advance(12)
H.check("personnage créé (pyromancie)", player:GetAttribute("InnateMagic") == "pyromancy")
H.noNewErrors("création et arrivée")

print("== HUD")
local badge = C.findText("Rang E")
H.check("badge de rang affiché (« Rang E »)", badge ~= nil)
local data, result = H.talk(player, "npc_bellkeeper", "bell_silent")
H.advance(1)
H.check("suivi de quête : « La Cloche Muette » affichée", C.findText("La Cloche Muette") ~= nil)
H.interact(player, "clue_frozen_clock")
H.advance(1)
local readingTitle = C.findText("Horloge figée")
H.check("texte examiné affiché (panneau de lecture)", readingTitle ~= nil)
H.check("notification de quête affichée", C.findText("Nouvelle quête") ~= nil or C.findText("Le témoignage") ~= nil or C.findText("L'enquête") ~= nil)
H.noNewErrors("HUD sans erreur")
local _ = data
local _r = result

print("== Grimoire : tableau des contrats")
H.interact(player, "board_missions")
H.advance(1)
local grimoire = player.PlayerGui:FindFirstChild("GrimoireGui")
H.check("le tableau ouvre le Grimoire", grimoire ~= nil and grimoire.Enabled == true)
H.check("onglet Contrats : « Cendres errantes » listé", C.findText("Cendres errantes", grimoire) ~= nil)
local accept = C.findButton("Accepter", grimoire)
H.check("bouton « Accepter » présent", accept ~= nil)
if accept then
	C.click(accept)
	H.advance(2)
end
local profile = H.profile(player)
local activeCount = 0
for _ in pairs(profile.missions.active) do
	activeCount += 1
end
H.check("le clic accepte un contrat côté serveur", activeCount == 1, activeCount)
H.check("le Grimoire se redessine (contrat « En cours »)", C.findText("En cours", grimoire) ~= nil)
H.noNewErrors("contrats sans erreur")

print("== Grimoire : guilde")
local UIBus = env.require("StarterPlayer/StarterPlayerScripts/Client/UI/UIBus")
UIBus.OpenPanel:Fire("guild")
H.advance(1)
local found = nil
for _, d in ipairs(C.descendants(grimoire)) do
	if rawget(d, "ClassName") == "TextBox" and string.find(rawget(d, "_props").PlaceholderText or "", "^Nom %(") then
		found = d
	end
end
H.check("formulaire de fondation de guilde", found ~= nil)
if found then
	found.Text = "La Main Grise"
	local create = C.findButton("Fonder", grimoire)
	if create then
		C.click(create)
	end
	H.advance(4)
end
H.check("guilde fondée depuis l'interface", H.profile(player).guild.guildId ~= nil)
H.check("le Grimoire affiche la guilde", C.findText("La Main Grise", grimoire) ~= nil)

print("== Grimoire : un clic dans le livre ne le ferme pas")
local backdrop = grimoire:FindFirstChild("Backdrop", true)
local book = grimoire:FindFirstChild("Book", true)
H.check("fond et livre présents", backdrop ~= nil and book ~= nil)
H.check("le fond est SOUS le livre (ZIndex)", backdrop.ZIndex < grimoire:FindFirstChild("Safe", true).ZIndex)
H.check("le fond n'est pas sélectionnable à la manette", backdrop.Selectable == false)
book.AbsolutePosition = H.mock.Vector2.new(100, 100)
book.AbsoluteSize = H.mock.Vector2.new(800, 500)
local function clickBackdrop(x, y, inputType)
	local input = { UserInputType = inputType or Enum.UserInputType.MouseButton1, Position = H.mock.Vector3.new(x, y, 0) }
	backdrop.InputBegan:Fire(input)
	backdrop.Activated:Fire(input, 1)
	H.advance(0.2)
end
clickBackdrop(400, 300)
H.check("clic souris au milieu du livre : reste ouvert", grimoire.Enabled == true)
clickBackdrop(890, 590, Enum.UserInputType.Touch)
H.check("toucher dans un coin du livre : reste ouvert", grimoire.Enabled == true)
backdrop.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = H.mock.Vector3.new(400, 300, 0) })
backdrop.Activated:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = H.mock.Vector3.new(20, 20, 0) }, 1)
H.advance(0.2)
H.check("glisser depuis le livre vers le fond : reste ouvert", grimoire.Enabled == true)
backdrop.Activated:Fire()
H.check("Activated sans position (manette) : reste ouvert", grimoire.Enabled == true)
local tabButton = C.findButton("Contrats", grimoire)
if tabButton then
	C.click(tabButton)
	H.advance(0.5)
end
H.check("changer d'onglet : reste ouvert", grimoire.Enabled == true)
H.check("onglet Contrats : bouton « Abandonner » du contrat en cours", C.findButton("Abandonner", grimoire) ~= nil)
clickBackdrop(20, 20)
H.check("clic sur le fond, hors du livre : se ferme", grimoire.Enabled == false)
UIBus.OpenPanel:Fire("guild")
H.advance(0.5)
H.check("réouverture", grimoire.Enabled == true)
C.pressKey(Enum.KeyCode.J)
H.advance(0.5)
H.check("touche J : le Grimoire se ferme", grimoire.Enabled == false)
H.noNewErrors("guilde sans erreur")

print("== Options (Grimoire)")
UIBus.OpenPanel:Fire("options")
H.advance(0.5)
H.check("onglet Options ouvert", grimoire.Enabled == true and C.findText("MUSIQUE", grimoire) ~= nil)
local musicSlider = C.findText("MUSIQUE", grimoire)
while musicSlider and rawget(musicSlider, "_props").Name ~= "Slider" do
	musicSlider = rawget(musicSlider, "_props").Parent
end
local minus = musicSlider and musicSlider:FindFirstChild("Minus", true)
H.check("curseur Musique avec bouton −", minus ~= nil)
if minus then
	C.click(minus)
	C.click(minus)
end
H.advance(2)
H.check("volume Musique enregistré côté serveur (90 %)", math.abs(H.profile(player).settings.music - 0.9) < 1e-6, H.profile(player).settings.music)
local AudioMixer = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/AudioMixer")
H.check("volume appliqué au groupe Music", math.abs(AudioMixer.getVolume("Music") - 0.9) < 1e-6, AudioMixer.getVolume("Music"))
local reducedButton = C.findButton("Effets réduits", grimoire)
if reducedButton then
	C.click(reducedButton)
end
H.advance(2)
local ClientSettings = env.require("StarterPlayer/StarterPlayerScripts/Client/State/ClientSettings")
H.check("effets réduits : appliqués chez le client", ClientSettings.isReducedEffects() == true)
H.check("effets réduits : enregistrés dans le profil", H.profile(player).settings.reducedEffects == true)
C.pressKey(Enum.KeyCode.J)
H.advance(0.5)
H.noNewErrors("options sans erreur")

print("== Parade et ennemis")
local enemy = H.enemyAt("enemy_forest_1")
if enemy then
	H.teleport(player, enemy:GetPivot().Position + mock.Vector3.new(5, 0, 0))
end
for _ = 1, 40 do
	C.frames(15)
end
local telegraphs = 0
for _, s in ipairs(runtime.sent) do
	if s.remote == "Telegraph" then
		telegraphs += 1
	end
end
H.check("l'ennemi attaque : télégraphes reçus", telegraphs > 0, telegraphs)
local effects = mock.workspace:FindFirstChild("EnemyEffects")
H.check("télégraphes et barres de vie dessinés sans erreur", effects ~= nil)
local handled = C.pressKey(Enum.KeyCode.Q)
H.advance(0.2)
local parries = 0
for _, s in ipairs(runtime.sent) do
	if s.remote == "RequestParry" then
		parries += 1
	end
end
H.check("touche de parade (emplacement Q / « A » AZERTY) envoie RequestParry", handled and parries == 1, parries)
H.noNewErrors("combat client sans erreur")
H.printWarnings()
H.finish()
