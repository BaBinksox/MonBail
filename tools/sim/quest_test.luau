-- Parcours complet de « La Cloche Muette » dans la simulation (outil, hors Roblox) :
-- lancement -> création -> quête acceptée -> indices -> écho -> runes -> crypte -> Veilleur ->
-- battant -> cloche -> récompense -> reconnexion (rien n'est perdu, rien n'est payé deux fois).
local H = require("./helpers")()
local QUEST = "bell_silent"

print("== Démarrage")
H.boot()
H.noNewErrors("serveur démarré")

print("== Le joueur arrive et crée son personnage")
local player = H.join("Sonneuse", 4242, 6)
local QuestService = H.server("Quest/QuestService")
H.check("personnage créé (plus en création)", player:GetAttribute("IsCustomizing") == false)
H.check("magie Gravité publiée", player:GetAttribute("InnateMagic") == "gravity", player:GetAttribute("InnateMagic"))
local profile = H.profile(player)
local xpStart = profile.progression.xp

local function stage(stageId)
	return QuestService.isAtStage(player, QUEST, stageId)
end

print("== Aldric propose la quête")
local data, result = H.talk(player, "npc_bellkeeper", QUEST)
H.check("Aldric répond (dialogue serveur)", data ~= nil)
H.check("quête acceptée", result ~= nil and result.ok == true, result and result.message)
H.talk(player, "npc_bellkeeper")
H.check("témoignage écouté -> étape « enquête »", stage("investigate"))

print("== Les indices de la chapelle")
for _, id in ipairs({ "clue_bell_inscription", "clue_hymnbook", "clue_frozen_clock" }) do
	local ok, why = H.interact(player, id)
	H.check("examiner " .. id, ok, why)
end
H.check("trois indices -> étape « écho »", stage("echo"))

print("== L'écho du parvis")
local parvis = H.anchorPosition("echo_bell")
H.teleport(player, parvis)
H.advance(2)
local played = #H.runtime.sentTo(player, "PlayEcho")
H.check("l'écho se joue pour ce joueur (PlayEcho)", played >= 1, played)
-- Le joueur suit la scène depuis le haut de la place (à portée de tout le trajet).
H.teleport(player, H.mock.Vector3.new(3000 - 8, 13, -36))
H.advance(70)
H.check("écho vu en entier -> étape « découverte »", stage("discovery"))

print("== Les runes du puits (3, 1, 4, 2)")
H.interact(player, "well_rune_1") -- mauvais ordre : tout s'éteint
local WorldAnchors = H.server("World/WorldAnchors")
H.check("mauvaise rune : aucune rune ne reste allumée", WorldAnchors.getInteractable("well_rune_1"):GetAttribute("RuneLit") ~= true)
for _, index in ipairs({ 3, 1, 4, 2 }) do
	H.interact(player, "well_rune_" .. index)
end
H.advance(2)
local cover = WorldAnchors.getDynamic("well_cover")
local openAt = H.anchorPosition("well_cover_open")
local pivot = cover and cover:GetPivot().Position
H.check("la dalle du puits a glissé", pivot ~= nil and openAt ~= nil and (pivot - openAt).Magnitude < 0.5, pivot and openAt and (pivot - openAt).Magnitude)
H.check("rune allumée visible (glyphe recoloré)", WorldAnchors.getInteractable("well_rune_2").Parent:FindFirstChild("Rune").Color.B > 0.9)

print("== La crypte")
local hall = H.anchorPosition("volume_crypt_hall")
H.teleport(player, hall + H.mock.Vector3.new(0, -5, 12))
H.advance(2)
H.check("crypte atteinte -> étape « épreuve »", stage("trial"))
local relicRefused = H.interact(player, "crypt_relic")
H.check("le battant est refusé tant que le Veilleur veille", relicRefused and not QuestService.isObjectiveDone(player, QUEST, "take_clapper"))
local guardian = H.enemyAt("enemy_crypt_guardian")
H.check("le Veilleur de Cendre est là", guardian ~= nil)
if guardian then
	H.teleport(player, guardian:GetPivot().Position + H.mock.Vector3.new(0, 0, 6))
	local defeated, hits = H.defeat(player, guardian)
	H.check("Veilleur vaincu", defeated, hits .. " coups")
end
H.check("objectif « vaincre le Veilleur » rempli", QuestService.isObjectiveDone(player, QUEST, "defeat_guardian"))
H.interact(player, "crypt_relic")
H.check("battant récupéré -> étape « récompense »", stage("reward"))
H.check("le battant est dans l'inventaire", (H.profile(player).inventory.bell_clapper or 0) == 1)

print("== Retour à la cloche")
H.interact(player, "crypt_exit")
local top = H.anchorPosition("crypt_exit_top")
H.check("l'échelle ramène sur la place", (H.root(player).Position - top).Magnitude < 2)
H.interact(player, "bell_main", 4)
H.check("battant remis (objet consommé)", (H.profile(player).inventory.bell_clapper or 0) == 0)
local world = H.mock.workspace:FindFirstChild("World")
H.check("la cloche sonne (BellRungAt publié)", world and world:GetAttribute("BellRungAt") ~= nil)
H.talk(player, "npc_bellkeeper")
H.check("quête terminée", QuestService.isCompleted(player, QUEST))
profile = H.profile(player)
H.check("clé de récompense dans le registre (quest:bell_silent)", profile.ledger["quest:" .. QUEST] ~= nil)
local xpAfter = profile.progression.xp
H.check("XP gagnée", xpAfter > xpStart, xpStart .. " -> " .. xpAfter)
H.talk(player, "npc_bellkeeper")
H.check("reparler à Aldric ne repaie pas", H.profile(player).progression.xp == xpAfter, H.profile(player).progression.xp)
H.noNewErrors("parcours sans erreur Luau")

print("== Reconnexion")
H.leave(player)
local again = H.join("Sonneuse", 4242)
local reloaded = H.profile(again)
H.check("au retour : pas de nouveau créateur", again:GetAttribute("IsCustomizing") == false)
H.check("au retour : quête toujours terminée", QuestService.isCompleted(again, QUEST))
H.check("au retour : XP conservée, sans double paiement", reloaded and reloaded.progression.xp == xpAfter, reloaded and reloaded.progression.xp)
H.talk(again, "npc_bellkeeper")
H.check("après reconnexion, Aldric ne repaie pas", H.profile(again).progression.xp == xpAfter)
H.noNewErrors("reconnexion sans erreur")
H.printWarnings()
H.finish()
