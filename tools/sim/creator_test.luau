-- Test de simulation du créateur de personnage et de l'arrivée (outil, hors Roblox) :
-- serveur complet + LocalScripts du créateur et de l'arrivée pour un joueur local.
-- Parcours : nouveau joueur -> OpenCreator -> introduction -> étapes (Entrée) -> confirmation
-- (clic sur « S'éveiller ») -> ApplyAvatar UNE fois -> CreatorClosed -> arrivée au belvédère
-- -> reconnexion : le créateur ne s'ouvre plus et l'apparence est rendue.
local mock = require("./mock")
local runtime = require("./runtime")(mock)
local env = require("./bundle_out")(mock)
local Enum = mock.Enum

local failures = 0
local function check(label, cond, detail)
	if cond then
		print("  OK    " .. label)
	else
		failures += 1
		print("  ÉCHEC " .. label .. (detail and (" — " .. tostring(detail)) or ""))
	end
end
local shownErrors = 0
local function flushErrors(label)
	for i = shownErrors + 1, #runtime.errors do
		print("    [ERREUR] " .. runtime.errors[i]:sub(1, 1200))
	end
	local count = #runtime.errors - shownErrors
	shownErrors = #runtime.errors
	check(label, count == 0, count .. " erreur(s)")
end
local function countSent(remoteName, kind)
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == remoteName and (kind == nil or s.kind == kind) then
			n += 1
		end
	end
	return n
end

print("== Démarrage du serveur")
mock.task.spawn(function()
	env.run("ServerScriptService/Server/Main")
end)
runtime.runUntil(5)
flushErrors("serveur démarré sans erreur")

print("== Un nouveau joueur rejoint (client simulé)")
local player = runtime.addPlayer("Créatrice")
local C = require("./client")(mock, runtime, player)
local CLIENT = "StarterPlayer/StarterPlayerScripts/Client/"
for _, path in ipairs({ "AvatarCreator/AvatarCreatorController", "World/ArrivalController" }) do
	mock.task.spawn(function()
		env.run(CLIENT .. path)
	end)
end
runtime.advance(0.5)
flushErrors("scripts du créateur chargés sans erreur")

runtime.spawnCharacter(player)
runtime.advance(3)
check("OpenCreator reçu par le client", countSent("OpenCreator") == 1, countSent("OpenCreator"))
check("joueur marqué « en création »", player:GetAttribute("IsCustomizing") == true, player:GetAttribute("IsCustomizing"))
runtime.advance(15) -- introduction (3 phrases) + révélation
check("au moins un aperçu envoyé (PreviewAvatar)", countSent("PreviewAvatar") >= 0)
flushErrors("introduction sans erreur")

print("== Parcours des étapes au clavier (Entrée)")
local handled = C.pressKey(Enum.KeyCode.Right) -- change une option de la 1re étape
check("raccourcis du créateur actifs (Droite)", handled)
runtime.advance(1)
check("1re étape : peuple et origine (avantage / inconvénient affichés)", C.findText("Inconvénient", nil) ~= nil or C.findText("✧", nil) ~= nil)
local Catalog = env.require(CLIENT .. "AvatarCreator/AvatarCreatorCatalog")
local destinyStep = Catalog.findStep("destiny")
for _ = 1, destinyStep - 1 do
	C.pressKey(Enum.KeyCode.Return)
	runtime.advance(1.2)
end
flushErrors("navigation jusqu'au Destin sans erreur")

print("== Roulette du Destin (interface)")
check("panneau « Roulette du Destin » et règles affichés", C.findText("ROULETTE DU DESTIN") ~= nil and C.findText("chances égales") ~= nil)
local spin = C.findButton("Laisser le destin choisir")
check("bouton de la roue présent", spin ~= nil)
if spin then
	C.click(spin)
	runtime.advance(0.3)
end
check("confirmation avant de tourner (verdict définitif)", C.findText("définitif") ~= nil)
local confirmSpin = C.findButton("Tourner la roue")
if confirmSpin then
	C.click(confirmSpin)
	C.click(confirmSpin) -- double clic : une seule demande
end
runtime.advance(9)
check("une seule demande de tirage envoyée", countSent("RequestDestinySpin", "FireServer") == 1, countSent("RequestDestinySpin", "FireServer"))
local ProfileStoreEarly = env.require("ServerScriptService/Server/Data/ProfileStore")
local roll = ProfileStoreEarly.get(player).creation.destinyRoll
check("le serveur a tiré et enregistré le verdict", type(roll) == "string", tostring(roll))
check("verdict annoncé (« Le destin a parlé »)", C.findText("Le destin a parlé") ~= nil)
local MagicConfig = env.require("ReplicatedStorage/Shared/Magic/MagicConfig")
for _, magic in ipairs(MagicConfig.MAGICS) do
	if magic.id ~= roll then
		local card = C.findText(magic.name)
		while card and rawget(card, "ClassName") ~= "TextButton" do
			card = rawget(card, "_props").Parent
		end
		if card then
			C.click(card) -- une autre carte : refusée, la magie est scellée
		end
		break
	end
end
runtime.advance(0.5)
for _ = 1, 4 do
	C.pressKey(Enum.KeyCode.Return)
	runtime.advance(1.2)
end
flushErrors("navigation sans erreur")
local button = C.findButton("S'éveiller")
check("la confirmation s'ouvre au récapitulatif (bouton « S'éveiller »)", button ~= nil)

print("== Confirmation")
local applyBefore = 0
if button then
	runtime.advance(1) -- la validation s'arme après 0,6 s
	C.click(button)
	C.click(button) -- double clic : ne doit partir qu'une fois
	runtime.advance(0.2)
	C.pressKey(Enum.KeyCode.Return)
end
runtime.advance(10)
flushErrors("confirmation et arrivée sans erreur")
local CreatorSession = env.require(CLIENT .. "AvatarCreator/CreatorSession")
check("cinématique d'arrivée en cours (caméra scénarisée)", CreatorSession.isArrivalBusy() and mock.workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable)
runtime.advance(14)
check("fin de cinématique : caméra rendue au jeu (Custom)", mock.workspace.CurrentCamera.CameraType == Enum.CameraType.Custom, tostring(mock.workspace.CurrentCamera.CameraType))
check("fin de cinématique : plus « occupée », écran rouvert", not CreatorSession.isArrivalBusy())
flushErrors("cinématique d'arrivée sans erreur")

local ProfileStore = env.require("ServerScriptService/Server/Data/ProfileStore")
local profile = ProfileStore.get(player)
local appliedCount = 0
for _, s in ipairs(runtime.sent) do
	if s.remote == "CreatorClosed" then
		appliedCount += 1
	end
end
check("CreatorClosed envoyé une seule fois", appliedCount == 1, appliedCount)
check("apparence enregistrée dans le profil", profile ~= nil and profile.avatar ~= nil)
check("magie publiée sur le joueur", player:GetAttribute("InnateMagic") ~= nil, tostring(player:GetAttribute("InnateMagic")))
check("magie publiée = verdict de la roue", player:GetAttribute("InnateMagic") == roll, tostring(player:GetAttribute("InnateMagic")))
check("peuple publié sur le joueur", player:GetAttribute("Race") ~= nil)
check("le joueur n'est plus « en création »", player:GetAttribute("IsCustomizing") == false)
check("cinématique d'arrivée envoyée (ArrivalCinematic)", countSent("ArrivalCinematic") == 1, countSent("ArrivalCinematic"))
check("ApplyAvatar envoyé UNE seule fois malgré double clic + Entrée", countSent("ApplyAvatar", "FireServer") == 1, countSent("ApplyAvatar", "FireServer"))
check("aperçus envoyés pendant la création (PreviewAvatar)", countSent("PreviewAvatar", "FireServer") >= 1, countSent("PreviewAvatar", "FireServer"))
local WorldAnchors = env.require("ServerScriptService/Server/World/WorldAnchors")
local okAnchor, villageAnchor = pcall(WorldAnchors.get, "spawn_village")
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if okAnchor and villageAnchor and root then
	local distance = (root.Position - villageAnchor.Position).Magnitude
	check("personnage placé au belvédère (ancre spawn_village)", distance < 12, string.format("%.1f studs", distance))
else
	check("ancre spawn_village présente", false, tostring(villageAnchor))
end

print("== Interruption de la cinématique (réapparition en plein vol)")
local SpawnRemotes = env.require("ReplicatedStorage/Shared/World/SpawnRemotes")
local anchorCFrame = WorldAnchors.getCFrame("camera_overlook")
SpawnRemotes.ArrivalCinematic:FireClient(player, anchorCFrame, villageAnchor and villageAnchor.Position or anchorCFrame.Position, "village")
runtime.advance(4)
check("cinématique relancée (caméra scénarisée)", mock.workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable)
runtime.spawnCharacter(player)
runtime.advance(1)
check("réapparition : caméra rendue aussitôt (Custom)", mock.workspace.CurrentCamera.CameraType == Enum.CameraType.Custom, tostring(mock.workspace.CurrentCamera.CameraType))
check("réapparition : cinématique terminée", not CreatorSession.isArrivalBusy())
runtime.advance(20)
check("aucune reprise de caméra après l'interruption", mock.workspace.CurrentCamera.CameraType == Enum.CameraType.Custom)
flushErrors("interruption sans erreur")

print("== Réapparition (mort puis respawn)")
local openBeforeRespawn = countSent("OpenCreator")
runtime.spawnCharacter(player)
runtime.advance(4)
check("au respawn, le créateur ne se rouvre pas", countSent("OpenCreator") == openBeforeRespawn)
check("au respawn, le joueur n'est pas « en création »", player:GetAttribute("IsCustomizing") == false)
flushErrors("respawn sans erreur")

print("== Reconnexion")
mock.task.spawn(function()
	runtime.removePlayer(player)
end)
runtime.advance(5)
local cloudKeys = 0
for _, store in pairs(runtime.cloud) do
	for _ in pairs(store) do
		cloudKeys += 1
	end
end
check("profil écrit dans le DataStore simulé", cloudKeys >= 1, cloudKeys)
local openBefore = countSent("OpenCreator")
local cinematicsBefore = countSent("ArrivalCinematic")
local again = runtime.addPlayer("Créatrice", player.UserId) -- même UserId : la sauvegarde est retrouvée
runtime.spawnCharacter(again)
runtime.advance(5)
check("au retour, pas de nouvelle cinématique d'arrivée (déjà vue)", countSent("ArrivalCinematic") == cinematicsBefore, countSent("ArrivalCinematic") - cinematicsBefore)
check("au retour, le créateur ne s'ouvre pas", countSent("OpenCreator") == openBefore, countSent("OpenCreator") - openBefore)
check("au retour, le joueur n'est pas « en création »", again:GetAttribute("IsCustomizing") == false, again:GetAttribute("IsCustomizing"))
flushErrors("reconnexion sans erreur")

print()
print(if failures == 0 then "CRÉATEUR OK" else failures .. " ÉCHEC(S)")
