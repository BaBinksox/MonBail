-- Combat à l'épée 2.0 et ressources (simulation, hors Roblox) : combo de cinq coups et cadence,
-- attaque chargée, riposte, plongée, posture, Tension, ultime, élan d'esquive, Mana, Concentration,
-- plusieurs joueurs sur un même ennemi, rembobinage ; puis le contrôleur client (mise en file, charge).
-- Ces vérifications portent sur la LOGIQUE ; elles ne remplacent pas les essais visuels, physiques et
-- réseau dans Roblox Studio.
local H = require("./helpers")()
local runtime, mock, env = H.runtime, H.mock, H.env
local Enum = mock.Enum
local V3 = mock.Vector3

H.boot()
local CombatConfig = H.shared("Combat/CombatConfig")
local ResourceConfig = H.shared("Combat/ResourceConfig")
local CombatRemotes = H.shared("Combat/CombatRemotes")
local ParryRemotes = H.shared("Combat/ParryRemotes")
local ParryConfig = H.shared("Combat/ParryConfig")
local MovementRemotes = H.shared("Movement/MovementRemotes")
local MovementConfig = H.shared("Movement/MovementConfig")
local CombatService = H.server("Combat/CombatService")
local ResourceService = H.server("Combat/ResourceService")
local PostureService = H.server("Combat/PostureService")
local DamageService = H.server("Combat/DamageService")
local ParryService = H.server("Combat/ParryService")
local MovementService = H.server("Movement/MovementService")
local RaceService = H.server("Avatar/RaceService")
local CombatStatus = H.server("Combat/CombatStatus")
local TimeLoopService = H.server("TimeLoop/TimeLoopService")
local GameEvents = H.server("Core/GameEvents")

local player = H.join("Lame", 9701)
local character = player.Character
local humanoid = character:FindFirstChildOfClass("Humanoid")
humanoid.MaxHealth = 100000
humanoid.Health = 100000
local enemy = H.enemyAt("enemy_forest_1")
H.check("un ennemi de la forêt pour s'entraîner", enemy ~= nil)
local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
enemyHumanoid.MaxHealth = 300 -- posture maximale : 300 x 0,6 = 180
enemyHumanoid.Health = 300
CombatStatus.stun(enemy, 9999) -- l'ennemi reste passif : seule la logique du joueur est testée

local function face()
	local position = enemyRoot.Position
	H.teleport(player, position + V3.new(0, 0, 4), position)
end
local function heal()
	enemyHumanoid.Health = enemyHumanoid.MaxHealth
end
local function attack(kind)
	CombatRemotes.RequestAttack.OnServerEvent:Fire(player, kind)
end
local function hit(target)
	CombatRemotes.ReportHit.OnServerEvent:Fire(player, target or enemy)
end
local function tension()
	return player:GetAttribute(CombatConfig.TENSION_ATTRIBUTE) or 0
end
local function lastResult()
	for i = #runtime.sent, 1, -1 do
		local s = runtime.sent[i]
		if s.remote == "HitConfirmed" and s.args[1] == character then
			return s.args[4], s.args[3]
		end
	end
	return nil
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-3)
end
local tensionMultiplier = RaceService.getTensionGainMultiplier(player)
face()

print("== Combo : cinq coups distincts, cadence et fenêtres")
local names = {}
for index, step in ipairs(CombatConfig.COMBO) do
	names[step.action] = true
	H.check(string.format("coup %d « %s » : fenêtre de frappe dans la durée", index, step.name), step.hitStart < step.hitEnd and step.hitEnd <= step.duration)
end
local distinct = 0
for _ in pairs(names) do
	distinct += 1
end
H.check("cinq poses différentes", distinct == 5)
attack(2)
H.advance(0.05)
H.check("le combo ne peut pas commencer par le coup 2", CombatService.getCurrentAttack(player) == nil)
attack(1)
H.advance(0.15)
local before = enemyHumanoid.Health
hit()
H.check("coup 1 : 10 dégâts", near(before - enemyHumanoid.Health, 10), before - enemyHumanoid.Health)
before = enemyHumanoid.Health
hit()
H.check("une seule touche par cible et par coup", enemyHumanoid.Health == before)
attack(2)
H.advance(0.02)
local _, index = CombatService.getCurrentAttack(player)
H.check("marteler : le coup 2 est refusé tant que le coup 1 n'est pas fini", index == 1, index)
H.advance(0.18) -- t = 0,35 (fin du coup 1 à 0,36, marge 0,1)
local expectedTension = 8 * tensionMultiplier
H.check(string.format("Tension gagnée une fois par coup (%.1f)", tension()), near(tension(), expectedTension), tension())
local expectedDamage = { 10, 15, 12, 26 }
for step = 2, 5 do
	attack(step)
	local def = CombatConfig.COMBO[step]
	H.advance(def.hitStart + 0.03)
	before = enemyHumanoid.Health
	face()
	hit()
	local dealt = before - enemyHumanoid.Health
	H.check(string.format("coup %d « %s » accepté : %.0f dégâts", step, def.name, dealt), near(dealt, expectedDamage[step - 1]), dealt)
	if step == 5 then
		H.check("coup final : éjection de la cible", enemyRoot:FindFirstChild("KnockbackVelocity") ~= nil)
	end
	H.advance(def.duration - def.hitStart - 0.03)
	heal()
end
expectedTension += (8 * 3 + 14) * tensionMultiplier
H.check(string.format("Tension après le combo complet : %.1f", tension()), near(tension(), expectedTension), tension())
H.check("posture entamée sans se briser (70 / 180)", near(PostureService.getRatio(enemy), 70 / 180, 0.01), PostureService.getRatio(enemy))
attack(6)
attack(3)
H.advance(0.05)
local kind
kind, index = CombatService.getCurrentAttack(player)
H.check("après le coup final, seul le coup 1 relance le combo", index == 5, index)
H.advance(1.2)
attack(2)
H.advance(0.05)
kind, index = CombatService.getCurrentAttack(player)
H.check("délai d'enchaînement dépassé : le coup 2 est refusé", index == 5, index)
attack(1)
H.advance(0.05)
kind, index = CombatService.getCurrentAttack(player)
H.check("le combo repart du coup 1", kind == "combo" and index == 1)
H.advance(0.6) -- fin de fenêtre 0,25 s + marge de latence 0,25 s
hit()
H.check("impact hors de la fenêtre de frappe : refusé", enemyHumanoid.Health == enemyHumanoid.MaxHealth)
H.advance(1)

print("== Attaque chargée")
attack("charged")
H.advance(0.05)
kind = CombatService.getCurrentAttack(player)
H.check("frappe chargée sans charge : refusée", kind ~= "charged")
local walkBefore = MovementService.getMaxSpeed(player)
CombatRemotes.RequestChargeStart.OnServerEvent:Fire(player)
H.advance(0.05)
H.check("charge acceptée (attribut Charging)", player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) == true)
H.check("ralenti pendant la charge (x 0,45)", near(MovementService.getMaxSpeed(player), walkBefore * CombatConfig.CHARGE_MOVE_MULTIPLIER), MovementService.getMaxSpeed(player))
MovementRemotes.RequestSprint.OnServerEvent:Fire(player, true)
H.advance(0.05)
H.check("pas de sprint pendant la charge", player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) ~= true)
local stanceBefore = player:GetAttribute(ParryConfig.PARRY_STANCE_ATTRIBUTE)
ParryRemotes.RequestParry.OnServerEvent:Fire(player)
H.advance(0.05)
H.check("pas de parade pendant la charge", player:GetAttribute(ParryConfig.PARRY_STANCE_ATTRIBUTE) == stanceBefore)
local hpBefore = humanoid.Health
H.call(DamageService.damagePlayer, player, 10, { kind = "environment" })
local taken = hpBefore - humanoid.Health
local raceTaken = RaceService.getDamageTakenMultiplier(player)
H.check(string.format("vulnérable pendant la charge : %.2f dégâts reçus au lieu de %.2f", taken, 10 * raceTaken), near(taken, 10 * raceTaken * CombatConfig.CHARGE_DAMAGE_TAKEN), taken)
H.advance(CombatConfig.CHARGE_FULL_TIME)
heal()
local tensionBefore = tension()
attack("charged")
H.advance(0.05)
local power
kind, index, power = CombatService.getCurrentAttack(player)
H.check("charge pleine : puissance 100 %", kind == "charged" and power == 1, power)
H.check("relâchée : la charge cesse, la vitesse revient", player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) == false and near(MovementService.getMaxSpeed(player), walkBefore))
H.advance(0.1)
face()
local postureBefore = PostureService.getRatio(enemy)
before = enemyHumanoid.Health
hit()
H.check(string.format("frappe chargée pleine : %.0f dégâts", before - enemyHumanoid.Health), near(before - enemyHumanoid.Health, CombatConfig.CHARGE_MAX_DAMAGE), before - enemyHumanoid.Health)
H.check("posture : +60 (charge pleine)", near(PostureService.getRatio(enemy) - postureBefore, 60 / 180, 0.02), PostureService.getRatio(enemy))
H.check("Tension d'une charge pleine x 1,5", near(tension() - tensionBefore, 12 * 1.5 * tensionMultiplier), tension() - tensionBefore)
H.advance(0.5)
CombatRemotes.RequestChargeStart.OnServerEvent:Fire(player)
H.advance(0.05)
H.check("recharge : pas de nouvelle charge tout de suite", player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) ~= true)
H.advance(CombatConfig.CHARGE_COOLDOWN)
heal()
CombatRemotes.RequestChargeStart.OnServerEvent:Fire(player)
H.advance(0.55)
attack("charged")
H.advance(0.15)
kind, index, power = CombatService.getCurrentAttack(player)
face()
before = enemyHumanoid.Health
hit()
local partial = before - enemyHumanoid.Health
H.check(string.format("charge partielle (%.0f %%) : %.1f dégâts, entre 18 et 45", power * 100, partial), power > 0.4 and power < 0.6 and partial > 18 and partial < 45, partial)
H.advance(CombatConfig.CHARGE_COOLDOWN + 0.5)
CombatRemotes.RequestChargeStart.OnServerEvent:Fire(player)
H.advance(CombatConfig.CHARGE_MAX_HOLD + 1)
H.check("charge jamais relâchée : elle tombe d'elle-même", player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) == false)
H.advance(CombatConfig.CHARGE_COOLDOWN)

print("== Parade parfaite, riposte et posture brisée")
heal()
attack("counter")
H.advance(0.05)
H.check("riposte sans parade : refusée", CombatService.getCurrentAttack(player) ~= "counter")
-- Posture amenée juste sous le seuil : la parade parfaite (35) doit la briser.
PostureService.damage(enemy, 180 * (1 - PostureService.getRatio(enemy)) - 10, player)
local ratioBefore = PostureService.getRatio(enemy)
H.check(string.format("posture au bord de la rupture (%.2f)", ratioBefore), ratioBefore > 0.9 and not PostureService.isBroken(enemy))
ResourceService.setTension(player, 0)
tensionBefore = tension()
ParryRemotes.RequestParry.OnServerEvent:Fire(player)
H.advance(0.05)
local result = H.call(DamageService.damagePlayer, player, 12, { kind = "enemy", model = enemy })
H.advance(0.05)
H.check("coup ennemi paré dans la fenêtre", result == "parried", result)
H.check("Tension de parade parfaite", near(tension() - tensionBefore, 25 * tensionMultiplier), tension() - tensionBefore)
H.check("fenêtre de riposte ouverte (CounterUntil)", (player:GetAttribute(CombatConfig.COUNTER_ATTRIBUTE) or 0) > mock.workspace:GetServerTimeNow())
H.check("la parade parfaite brise la posture de l'attaquant", PostureService.isBroken(enemy))
attack("counter")
H.advance(0.15)
kind = CombatService.getCurrentAttack(player)
H.check("riposte acceptée dans la fenêtre", kind == "counter")
face()
before = enemyHumanoid.Health
hit()
H.check(string.format("riposte sur posture brisée : %.1f dégâts (22 x 1,3)", before - enemyHumanoid.Health), near(before - enemyHumanoid.Health, 22 * CombatConfig.POSTURE.BREAK_DAMAGE_MULTIPLIER), before - enemyHumanoid.Health)
H.check("posture brisée : attribut PostureBrokenUntil publié", (enemy:GetAttribute(CombatConfig.POSTURE.BROKEN_ATTRIBUTE) or 0) > mock.workspace:GetServerTimeNow())
H.check("posture brisée : l'ennemi est étourdi", CombatStatus.isStunned(enemy))
H.advance(0.5)
attack("counter")
H.advance(0.05)
H.check("une seule riposte par parade", select(1, CombatService.getCurrentAttack(player)) ~= "counter" or select(3, CombatService.getCurrentAttack(player)) == 1)
H.advance(CombatConfig.POSTURE.BREAK_DURATION + CombatConfig.POSTURE.REGEN_DELAY + 8)
H.check("posture reconstituée hors pression", PostureService.getRatio(enemy) == 0, PostureService.getRatio(enemy))

print("== Esquive parfaite : élan")
heal()
ResourceService.setTension(player, 0)
tensionBefore = tension()
MovementRemotes.RequestDash.OnServerEvent:Fire(player, V3.new(1, 0, 0))
H.advance(0.05)
result = H.call(DamageService.damagePlayer, player, 12, { kind = "enemy", model = enemy })
H.advance(0.05)
H.check("coup ennemi esquivé par le dash", result == "dodged", result)
H.check("Tension d'esquive parfaite", near(tension() - tensionBefore, 12 * tensionMultiplier), tension() - tensionBefore)
H.check("élan publié (MomentumUntil)", (player:GetAttribute(CombatConfig.MOMENTUM_ATTRIBUTE) or 0) > mock.workspace:GetServerTimeNow())
H.advance(0.6)
face()
attack(1)
H.advance(0.15)
before = enemyHumanoid.Health
hit()
H.check(string.format("élan : coup 1 à %.1f dégâts (x 1,15)", before - enemyHumanoid.Health), near(before - enemyHumanoid.Health, 10 * CombatConfig.MOMENTUM_DAMAGE), before - enemyHumanoid.Health)
H.advance(CombatConfig.MOMENTUM_DURATION + 0.5)

print("== Plongée")
local TerrainSculpt = H.server("WorldBuild/TerrainSculpt")
runtime.realRaycast = true
runtime.terrainHeight = function(x, z)
	return TerrainSculpt.heightAt(x - 3000, z)
end
local groundY = enemyRoot.Position.Y
H.teleport(player, V3.new(enemyRoot.Position.X, groundY, enemyRoot.Position.Z + 4))
local rootPart = H.root(player)
local ray = mock.workspace:Raycast(rootPart.Position, V3.new(0, -50, 0))
attack("plunge")
H.advance(0.05)
H.check("le sol est détecté sous le joueur (raycast réel)", ray ~= nil)
H.check("plongée demandée au sol : refusée", CombatService.getCurrentAttack(player) ~= "plunge")
H.teleport(player, rootPart.Position + V3.new(0, 14, 0))
attack("plunge")
H.advance(0.05)
H.check("plongée en l'air : acceptée", CombatService.getCurrentAttack(player) == "plunge")
runtime.realRaycast = false
face()
heal()
before = enemyHumanoid.Health
hit()
H.check("plongée : impact centré, 14 dégâts", near(before - enemyHumanoid.Health, 14), before - enemyHumanoid.Health)
H.advance(0.2)
attack("plunge")
H.advance(0.05)
local _, _, plungePower = CombatService.getCurrentAttack(player)
H.check("recharge de la plongée", plungePower == 1)
H.advance(CombatConfig.PLUNGE_COOLDOWN + 1.5)

print("== Technique ultime")
ResourceService.setTension(player, 60)
CombatRemotes.RequestUltimate.OnServerEvent:Fire(player)
H.advance(0.3)
H.check("ultime refusé sans Tension pleine", tension() == 60)
local ultimatesBefore = #runtime.sentTo(player, "UltimateFired")
ResourceService.setTension(player, 100)
CombatRemotes.RequestUltimate.OnServerEvent:Fire(player)
CombatRemotes.RequestUltimate.OnServerEvent:Fire(player)
H.advance(0.5)
H.check("ultime déclenché une seule fois, jauge vidée", tension() == 0)
H.advance(3)

print("== Mana et régénération")
H.check("Mana plein à l'arrivée (100 / 100)", player:GetAttribute(ResourceConfig.MANA_ATTRIBUTE) == 100 and player:GetAttribute(ResourceConfig.MANA_MAX_ATTRIBUTE) == 100)
H.advance(ResourceConfig.COMBAT_TIMEOUT + 1)
H.check("hors combat après quelques secondes sans coup", player:GetAttribute(ResourceConfig.IN_COMBAT_ATTRIBUTE) == false)
H.check("dépense refusée au-delà du Mana disponible", ResourceService.spendMana(player, 1000) == false and ResourceService.getMana(player) == 100)
H.check("dépense de 40", ResourceService.spendMana(player, 40) and near(ResourceService.getMana(player), 60))
H.advance(2)
H.check(string.format("régénération hors combat ~7/s (%.1f)", ResourceService.getMana(player)), near(ResourceService.getMana(player), 74, 1.5), ResourceService.getMana(player))
ResourceService.markCombat(player)
local manaBefore = ResourceService.getMana(player)
H.advance(2)
H.check(string.format("régénération en combat ~3/s (+%.1f)", ResourceService.getMana(player) - manaBefore), near(ResourceService.getMana(player) - manaBefore, 6, 1), ResourceService.getMana(player) - manaBefore)
H.check("attribut InCombat publié", player:GetAttribute(ResourceConfig.IN_COMBAT_ATTRIBUTE) == true)

print("== Concentration")
ResourceService.spendMana(player, ResourceService.getMana(player) - 10)
manaBefore = ResourceService.getMana(player)
walkBefore = MovementService.getMaxSpeed(player)
CombatRemotes.RequestConcentrate.OnServerEvent:Fire(player, true)
H.advance(0.05)
H.check("Concentration accordée", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == true)
H.check("très ralenti (x 0,25)", near(MovementService.getMaxSpeed(player), walkBefore * ResourceConfig.CONCENTRATION_MOVE_MULTIPLIER), MovementService.getMaxSpeed(player))
MovementRemotes.RequestSprint.OnServerEvent:Fire(player, true)
H.advance(0.05)
H.check("pas de sprint en Concentration", player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) ~= true)
CombatRemotes.RequestChargeStart.OnServerEvent:Fire(player)
H.advance(0.05)
H.check("pas de charge en Concentration", player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) ~= true)
H.advance(1)
H.check(string.format("Mana rapide en Concentration (+%.1f en 1,1 s)", ResourceService.getMana(player) - manaBefore), ResourceService.getMana(player) - manaBefore > 20)
H.advance(ResourceConfig.CONCENTRATION_MAX_DURATION)
H.check("durée limitée : la Concentration s'interrompt", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == false)
H.check("vitesse rendue", near(MovementService.getMaxSpeed(player), walkBefore))
ResourceService.spendMana(player, 50)
CombatRemotes.RequestConcentrate.OnServerEvent:Fire(player, true)
H.advance(0.05)
H.check("recharge : pas de nouvelle Concentration tout de suite", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == false)
H.advance(ResourceConfig.CONCENTRATION_COOLDOWN)
ResourceService.spendMana(player, ResourceService.getMana(player) - 5)
CombatRemotes.RequestConcentrate.OnServerEvent:Fire(player, true)
H.advance(0.05)
hpBefore = humanoid.Health
H.call(DamageService.damagePlayer, player, 10, { kind = "environment" })
H.advance(0.05)
taken = hpBefore - humanoid.Health
H.check(string.format("vulnérable en Concentration (%.2f reçus)", taken), near(taken, 10 * raceTaken * ResourceConfig.CONCENTRATION_DAMAGE_TAKEN), taken)
H.check("un coup reçu rompt la Concentration", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == false)
H.advance(ResourceConfig.CONCENTRATION_COOLDOWN + 1)
CombatRemotes.RequestConcentrate.OnServerEvent:Fire(player, "oui")
H.advance(0.05)
H.check("demande invalide ignorée", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == false)

print("== Deux joueurs sur le même ennemi, élimination unique")
local second = H.join("Second", 9702)
second.Character:FindFirstChildOfClass("Humanoid").MaxHealth = 100000
second.Character:FindFirstChildOfClass("Humanoid").Health = 100000
local defeats = 0
local eligible = {}
GameEvents.EnemyDefeated:Connect(function(info)
	if info.enemy == enemy then
		defeats += 1
		eligible = info.eligible
	end
end)
enemyHumanoid.Health = 30
face()
H.teleport(second, enemyRoot.Position + V3.new(0, 0, -4), enemyRoot.Position)
CombatRemotes.RequestAttack.OnServerEvent:Fire(second, 1)
attack(1)
H.advance(0.15)
CombatRemotes.ReportHit.OnServerEvent:Fire(second, enemy)
hit()
H.advance(0.3)
attack(2)
CombatRemotes.RequestAttack.OnServerEvent:Fire(second, 2)
H.advance(0.15)
hit()
CombatRemotes.ReportHit.OnServerEvent:Fire(second, enemy)
H.advance(0.4)
attack(3)
H.advance(0.25)
hit()
H.advance(2)
H.check("ennemi vaincu", enemyHumanoid.Health <= 0)
H.check("une seule élimination (pas de récompense en double)", defeats == 1, defeats)
H.check("les deux joueurs sont éligibles à la récompense", table.find(eligible, player) ~= nil and table.find(eligible, second) ~= nil, #eligible)

print("== Rembobinage : la posture repart d'intacte")
local enemy2 = H.enemyAt("enemy_forest_2") or H.enemyAt("enemy_forest_3")
if enemy2 then
	PostureService.damage(enemy2, 20, player)
	H.check("posture entamée", PostureService.getRatio(enemy2) > 0)
	TimeLoopService.Rewound:Fire("test", { enemy2 }, { player })
	H.advance(0.1)
	H.check("après rembobinage : posture intacte", PostureService.getRatio(enemy2) == 0 and enemy2:GetAttribute(CombatConfig.POSTURE.ATTRIBUTE) == nil)
else
	H.check("un second ennemi pour le rembobinage", false)
end
print("== Sauvegarde et reconnexion")
local profileBefore = H.profile(player)
local xpBefore = profileBefore and profileBefore.progression.xp
local serialized = profileBefore and mock.game:GetService("HttpService"):JSONEncode(profileBefore) or ""
H.check("ni Mana, ni Tension, ni recharge dans la sauvegarde (rien à migrer)", not string.find(serialized, "Mana") and not string.find(serialized, "Tension") and not string.find(serialized, "SpellReady"))
ResourceService.setTension(player, 70)
ResourceService.spendMana(player, 50)
H.leave(player)
player = H.join("Lame", 9701)
character = player.Character
humanoid = character:FindFirstChildOfClass("Humanoid")
H.check("au retour : pas de nouveau créateur, progression conservée", player:GetAttribute("IsCustomizing") == false and H.profile(player) and H.profile(player).progression.xp == xpBefore)
H.check("au retour : Mana plein, Tension à zéro, aucune charge ni riposte en cours", player:GetAttribute(ResourceConfig.MANA_ATTRIBUTE) == 100 and tension() == 0 and player:GetAttribute(CombatConfig.CHARGING_ATTRIBUTE) == false)
humanoid.MaxHealth = 100000
humanoid.Health = 100000
H.noNewErrors("combat serveur sans erreur")

print("== Client : combo, mise en file, charge")
H.leave(second)
local C = require("./client")(mock, runtime, player)
for _, path in ipairs({ "Combat/CombatController", "Combat/ConcentrationController", "Animation/AnimationDirector", "UI/CombatHud" }) do
	mock.task.spawn(function()
		env.run("StarterPlayer/StarterPlayerScripts/Client/" .. path)
	end)
end
H.advance(1)
local action = C.actions.SwordAttack
H.check("action d'attaque liée (R2 / tactile)", action ~= nil)
local function sentCount(remoteName, filter)
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == remoteName and s.kind == "FireServer" and (filter == nil or filter(s.args)) then
			n += 1
		end
	end
	return n
end
local function press()
	mock.task.spawn(action.fn, "SwordAttack", Enum.UserInputState.Begin, {})
end
local function release()
	mock.task.spawn(action.fn, "SwordAttack", Enum.UserInputState.End, {})
end
face()
local attacksBefore = sentCount("RequestAttack")
press()
C.frames(2)
release()
C.frames(3)
press() -- trop tôt : ignoré
C.frames(1)
release()
C.frames(10) -- t ~ 0,25 s : dans la dernière partie du coup 1
press()
C.frames(1)
release()
C.frames(40)
local sentKinds = {}
for _, s in ipairs(runtime.sent) do
	if s.remote == "RequestAttack" and s.kind == "FireServer" then
		table.insert(sentKinds, tostring(s.args[1]))
	end
end
H.check("clic + clic mis en file : coups 1 puis 2, le clic trop précoce est ignoré", sentCount("RequestAttack") - attacksBefore == 2, table.concat(sentKinds, ","))
C.frames(60)
local chargesBefore = sentCount("RequestChargeStart")
press()
C.frames(60) -- coup 1, puis la lame se ramène
H.check("bouton maintenu : la charge commence", sentCount("RequestChargeStart") == chargesBefore + 1)
C.frames(80)
release()
C.frames(5)
H.check("relâché : frappe chargée demandée", sentCount("RequestAttack", function(args)
	return args[1] == "charged"
end) >= 1)
C.frames(60)
print("== Client : Concentration")
local MovementState = env.require("StarterPlayer/StarterPlayerScripts/Client/Movement/MovementState")
local concentrate = C.actions.Concentrate
H.check("action Concentration liée (G / croix droite / tactile)", concentrate ~= nil)
H.advance(ResourceConfig.CONCENTRATION_COOLDOWN)
ResourceService.spendMana(player, ResourceService.getMana(player) - 10)
mock.task.spawn(concentrate.fn, "Concentrate", Enum.UserInputState.Begin, {})
C.frames(10)
H.check("maintenue : demande envoyée et accordée", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == true, string.format("envois=%d mana=%.1f", sentCount("RequestConcentrate"), ResourceService.getMana(player)))
H.check("posture locale : dash et épée en retrait", MovementState.concentrating == true)
local aura = H.root(player):FindFirstChild("ConcentrationAura")
H.check("aura de la Magie Innée autour du personnage", aura ~= nil and aura:FindFirstChildOfClass("ParticleEmitter") ~= nil)
mock.task.spawn(concentrate.fn, "Concentrate", Enum.UserInputState.End, {})
C.frames(10)
H.check("relâchée : fin de la Concentration, aura retirée", player:GetAttribute(ResourceConfig.CONCENTRATING_ATTRIBUTE) == false and MovementState.concentrating == false and H.root(player):FindFirstChild("ConcentrationAura") == nil)
local hud = C.playerGui:FindFirstChild("CombatHudGui")
H.check("HUD de combat créé (PV, Mana, Tension)", hud ~= nil and hud:FindFirstChild("Mana", true) ~= nil and hud:FindFirstChild("Tension", true) ~= nil)
H.noNewErrors("combat client sans erreur")
H.printWarnings()
H.finish()
