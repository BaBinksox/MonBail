-- Sorts, altérations et réactions élémentaires (simulation, hors Roblox) : les douze sorts des six
-- magies, Mana et recharges tenus par le serveur, altérations communes (durée, cumul, boss,
-- rendement décroissant, nettoyage), deux réactions complètes, plusieurs joueurs sur un même
-- ennemi, rembobinage, ultimes migrés vers les altérations, puis le contrôleur client.
-- Vérifications de LOGIQUE : elles ne remplacent pas les essais visuels et réseau dans Studio.
local H = require("./helpers")()
local runtime, mock, env = H.runtime, H.mock, H.env
local Enum = mock.Enum
local V3 = mock.Vector3

H.boot()
local MagicConfig = H.shared("Magic/MagicConfig")
local SpellConfig = H.shared("Magic/SpellConfig")
local SpellRemotes = H.shared("Magic/SpellRemotes")
local StatusConfig = H.shared("Combat/StatusConfig")
local ResourceConfig = H.shared("Combat/ResourceConfig")
local CombatConfig = H.shared("Combat/CombatConfig")
local SpellService = H.server("Magic/SpellService")
local StatusService = H.server("Combat/StatusService")
local ResourceService = H.server("Combat/ResourceService")
local PostureService = H.server("Combat/PostureService")
local DamageService = H.server("Combat/DamageService")
local CombatStatus = H.server("Combat/CombatStatus")
local TimeLoopService = H.server("TimeLoop/TimeLoopService")
local GameEvents = H.server("Core/GameEvents")
local UltimateBehaviors = H.server("Combat/UltimateBehaviors")

print("== Catalogue")
H.check("douze sorts", #SpellConfig.SPELLS == 12, #SpellConfig.SPELLS)
for _, magic in ipairs(MagicConfig.MAGICS) do
	local base = SpellConfig.forMagic(magic.id, "base")
	local secondary = SpellConfig.forMagic(magic.id, "secondary")
	H.check(string.format("%s : %s (%d Mana) + %s (%d Mana)", magic.name, base and base.name or "?", base and base.manaCost or 0, secondary and secondary.name or "?", secondary and secondary.manaCost or 0),
		base ~= nil and secondary ~= nil and base.manaCost >= 15 and base.manaCost <= 25 and secondary.manaCost >= 30 and secondary.manaCost <= 45)
	for _, spell in ipairs({ base, secondary }) do
		for _, application in ipairs(spell and spell.statuses or {}) do
			H.check(spell.name .. " : altération « " .. application.id .. " » connue", StatusConfig.STATUSES[application.id] ~= nil)
		end
	end
end

local mages = {}
for index, magic in ipairs(MagicConfig.MAGICS) do
	local player = H.join("Mage_" .. magic.id, 9800 + index, index)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = 100000
	humanoid.Health = 100000
	mages[magic.id] = player
end
H.check("six mages", mages.gravity ~= nil and mages.pyromancy ~= nil)

local enemies = {}
for index = 1, 7 do
	local enemy = H.enemyAt("enemy_forest_" .. index)
	if enemy then
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		humanoid.MaxHealth = 3000
		humanoid.Health = 3000
		table.insert(enemies, enemy)
	end
end
H.check("au moins quatre ennemis d'entraînement", #enemies >= 4, #enemies)
local target, second, third, spare = enemies[1], enemies[2], enemies[3], enemies[4]
local center = target:GetPivot().Position
-- Deux voisins à 6 studs (chaîne, explosion), immobiles le temps des essais.
for _, enemy in ipairs({ target, second, third }) do
	CombatStatus.stun(enemy, 9999)
end
second:PivotTo(mock.CFrame.new(center + V3.new(6, 0, 0)))
third:PivotTo(mock.CFrame.new(center + V3.new(-6, 0, 3)))

local function root(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.RootPart
end
local function place(player, distance)
	local position = root(target).Position
	H.teleport(player, position + V3.new(0, 0, distance or 12), position)
end
local function cast(player, spellId, aim)
	SpellRemotes.RequestCast.OnServerEvent:Fire(player, spellId, aim or root(target).Position)
end
local function wait(spell, distance)
	H.advance(spell.castTime + (if spell.speed > 0 then (distance or 12) / spell.speed else 0) + 0.25)
end
local function health(model)
	return model:FindFirstChildOfClass("Humanoid").Health
end
local function heal(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.Health = humanoid.MaxHealth
end
local function denials(player, reason)
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == "CastDenied" and s.args[1] == player and (reason == nil or s.args[3] == reason) then
			n += 1
		end
	end
	return n
end
local function reactions(reactionId)
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == "ReactionTriggered" and s.args[2] == reactionId then
			n += 1
		end
	end
	return n
end
local function lastImpactTargets(spellId)
	for i = #runtime.sent, 1, -1 do
		local s = runtime.sent[i]
		if s.remote == "SpellImpact" and s.args[2] == spellId then
			return s.args[4] or {}
		end
	end
	return {}
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-3)
end
local function clearAll()
	for _, enemy in ipairs(enemies) do
		StatusService.clear(enemy)
		heal(enemy)
	end
end

print("== Pyromancie")
local pyro = mages.pyromancy
local ember = SpellConfig.get("ember")
place(pyro)
local before = health(target)
cast(pyro, "ember")
H.advance(0.05)
H.check("Mana débité par le serveur (100 -> 82)", near(ResourceService.getMana(pyro), 82, 0.5), ResourceService.getMana(pyro))
wait(ember)
H.check(string.format("Braise Ardente touche : %.0f dégâts", before - health(target)), near(before - health(target), ember.damage, 0.01), before - health(target))
H.check("brûlure posée (cran 1)", StatusService.getLevel(target, "burn") == 1)
H.check("attribut Status_burn publié pour les clients", (target:GetAttribute("Status_burn") or 0) > mock.workspace:GetServerTimeNow())
local manaBeforeRecast = ResourceService.getMana(pyro)
cast(pyro, "ember")
H.advance(0.1)
H.check("recharge : relance refusée, Mana non débité", denials(pyro, "cooldown") >= 1 and ResourceService.getMana(pyro) >= manaBeforeRecast)
before = health(target)
H.advance(1.05)
H.check(string.format("brûlure : dégâts périodiques (%.0f)", before - health(target)), before - health(target) >= 4 - 1e-3, before - health(target))
cast(pyro, "frost_shard")
H.advance(0.1)
H.check("un sort d'une autre magie est refusé", denials(pyro, "magic") == 1)
place(pyro, 6)
H.advance(0.5)
cast(pyro, "blazing_circle")
H.advance(SpellConfig.get("blazing_circle").castTime + 0.2)
H.check("Cercle Incandescent : brûlure cumulée jusqu'à 3 crans", StatusService.getLevel(target, "burn") == 3, StatusService.getLevel(target, "burn"))
H.check("Cercle Incandescent : éjection", root(target):FindFirstChild("KnockbackVelocity") ~= nil)
H.check("Cercle Incandescent : voisins brûlés aussi", StatusService.has(second, "burn"))
ResourceService.spendMana(pyro, ResourceService.getMana(pyro) - 5)
H.advance(SpellConfig.get("ember").cooldown)
cast(pyro, "ember")
H.advance(0.1)
H.check("Mana insuffisant : refusé par le serveur (« mana »)", denials(pyro, "mana") == 1)
clearAll()

print("== Glace et réactions")
local ice = mages.ice
place(ice)
cast(ice, "frost_shard")
wait(SpellConfig.get("frost_shard"))
H.check("Éclat de Givre : froid posé", StatusService.has(target, "chill"))
H.check(string.format("froid : vitesse x %.2f publiée pour l'IA", target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) or 1), near(target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) or 1, 0.75))
local lightning = mages.lightning
place(lightning, 10)
local tensionBefore = ResourceService.getTension(lightning)
before = health(target)
cast(lightning, "electric_arc")
wait(SpellConfig.get("electric_arc"))
H.check("Foudre sur cible froide : réaction « Éclatement »", reactions("shatter") == 1)
H.check("la réaction consomme le froid", not StatusService.has(target, "chill"))
H.check(string.format("dégâts bonus de la réaction (%.0f > 11)", before - health(target)), before - health(target) > 11 + 16 - 1e-3, before - health(target))
H.check("Tension de réaction + sort pour le lanceur", ResourceService.getTension(lightning) - tensionBefore >= (10 + 4) * 0.99)
-- Choc thermique : feu sur cible froide.
H.advance(2)
cast(ice, "frost_shard")
wait(SpellConfig.get("frost_shard"))
place(pyro)
ResourceService.restoreMana(pyro, 100)
cast(pyro, "ember")
wait(ember)
H.check("Feu sur cible froide : « Choc thermique »", reactions("thermalShock") == 1)
-- Choc thermique : glace sur cible qui brûle.
H.advance(2)
StatusService.apply(target, "burn", { source = pyro })
H.advance(SpellConfig.get("frost_shard").cooldown)
cast(ice, "frost_shard")
wait(SpellConfig.get("frost_shard"))
H.check("Glace sur cible qui brûle : « Choc thermique », brûlure éteinte", reactions("thermalShock") == 2 and not StatusService.has(target, "burn"))
H.check("pas de réaction en rafale (délai par cible)", reactions("shatter") + reactions("thermalShock") == 3)
clearAll()
H.advance(StatusConfig.REACTION_COOLDOWN)
local prison = SpellConfig.get("crystal_prison")
cast(ice, "crystal_prison")
wait(prison)
H.check("Prison Cristalline : gel (immobile)", StatusService.has(target, "freeze") and target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) == 0)
local frozen = 0
for _, enemy in ipairs({ target, second, third }) do
	if StatusService.has(enemy, "freeze") then
		frozen += 1
	end
end
H.check("Prison Cristalline : zone (plusieurs ennemis gelés)", frozen >= 2, frozen)
StatusService.clear(spare)
H.check("rendement décroissant : 1er gel pris", StatusService.apply(spare, "freeze", { source = ice }))
StatusService.remove(spare, "freeze")
H.check("rendement décroissant : 2e gel pris (moitié moins long)", StatusService.apply(spare, "freeze", { source = ice }))
H.advance(0.05)
local remaining = (spare:GetAttribute("Status_freeze") or 0) - mock.workspace:GetServerTimeNow()
H.check(string.format("2e gel : %.2f s au lieu de %.1f", remaining, StatusConfig.STATUSES.freeze.maxDuration), remaining <= StatusConfig.STATUSES.freeze.maxDuration * StatusConfig.DR_FACTOR + 0.05)
StatusService.remove(spare, "freeze")
H.check("rendement décroissant : 3e gel refusé (pas de verrouillage)", not StatusService.apply(spare, "freeze", { source = ice }))
local boss = H.enemyAt("boss_training")
H.check("le boss d'entraînement est là", boss ~= nil)
if boss then
	H.check("boss : le gel devient un simple froid", StatusService.apply(boss, "freeze", { source = ice }) and StatusService.has(boss, "chill") and not StatusService.has(boss, "freeze"))
	H.check("boss : pas d'aspiration", not StatusService.apply(boss, "pull", { source = ice, center = center }))
	StatusService.clear(boss)
end
clearAll()

print("== Foudre")
local idle = spare
StatusService.clear(idle)
H.advance(StatusConfig.DR_WINDOW)
local idleRoot = root(idle)
H.teleport(lightning, idleRoot.Position + V3.new(0, 0, 10), idleRoot.Position)
H.advance(SpellConfig.get("electric_arc").cooldown)
cast(lightning, "electric_arc", idleRoot.Position)
wait(SpellConfig.get("electric_arc"))
H.check("Arc Électrique : électrise", StatusService.has(idle, "shock"))
H.check("électrisé : action ennemie interrompue (micro-étourdissement)", CombatStatus.isStunned(idle) or (idle:GetAttribute("StunnedUntil") or 0) > 0)
place(lightning, 10)
H.advance(StatusConfig.REACTION_COOLDOWN)
cast(lightning, "chain_lightning")
wait(SpellConfig.get("chain_lightning"))
local chained = lastImpactTargets("chain_lightning")
H.check(string.format("Chaîne Foudroyante : %d cibles (max 4)", #chained), #chained >= 2 and #chained <= 4, #chained)
clearAll()

print("== Ombre")
local shadow = mages.shadow
place(shadow)
local shadowHumanoid = shadow.Character:FindFirstChildOfClass("Humanoid")
shadowHumanoid.Health = 50000
cast(shadow, "dark_bolt")
wait(SpellConfig.get("dark_bolt"))
H.check("Trait Obscur : drain posé", StatusService.has(target, "drain"))
H.check("Trait Obscur : le lanceur se soigne à l'impact", shadowHumanoid.Health > 50000)
local healthAfterHit = shadowHumanoid.Health
H.advance(1.1)
H.check("drain : soin pendant la durée", shadowHumanoid.Health > healthAfterHit)
cast(shadow, "shadow_veil")
H.advance(SpellConfig.get("shadow_veil").castTime + 0.1)
H.check("Voile des Ombres : posé sur le lanceur", StatusService.has(shadow.Character, "veil"))
local hpBefore = shadowHumanoid.Health
H.call(DamageService.damagePlayer, shadow, 10, { kind = "environment" })
local RaceService = H.server("Avatar/RaceService")
H.check(string.format("voile : dégâts reçus réduits (%.2f)", hpBefore - shadowHumanoid.Health), near(hpBefore - shadowHumanoid.Health, 10 * RaceService.getDamageTakenMultiplier(shadow) * 0.6, 0.01), hpBefore - shadowHumanoid.Health)
clearAll()

print("== Antimatière")
local void = mages.antimatter
place(void)
cast(void, "void_fragment")
wait(SpellConfig.get("void_fragment"))
local exploded = lastImpactTargets("void_fragment")
H.check(string.format("Fragment du Vide : explosion (%d cibles)", #exploded), #exploded >= 1)
H.advance(SpellConfig.get("void_fragment").cooldown)
CombatStatus.stun(second, 0)
second:SetAttribute("StunnedUntil", 0)
cast(void, "minor_singularity", center)
wait(SpellConfig.get("minor_singularity"))
local pulled = lastImpactTargets("minor_singularity")
H.check(string.format("Singularité Mineure : %d cibles (max 6)", #pulled), #pulled >= 2 and #pulled <= 6, #pulled)
H.check("aspiration bornée vers le centre (poussée posée)", root(second):FindFirstChild("StatusPullVelocity") ~= nil or root(third):FindFirstChild("StatusPullVelocity") ~= nil)
CombatStatus.stun(second, 9999)
clearAll()

print("== Gravité")
local gravity = mages.gravity
place(gravity)
local ratioBefore = PostureService.getRatio(target)
cast(gravity, "gravity_press")
wait(SpellConfig.get("gravity_press"))
H.check("Pression Gravitationnelle : pression posée", StatusService.has(target, "pressure"))
H.check("pression : vitesse ralentie", near(target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) or 1, 0.55))
local ratioMid = PostureService.getRatio(target)
PostureService.damage(target, 20, gravity)
local gained = (PostureService.getRatio(target) - ratioMid) * (PostureService.getRatio(target) > 0 and 1 or 0)
H.check("pression : posture plus fragile (+25 %)", gained > 0 and ratioMid > ratioBefore)
clearAll()
before = health(target)
cast(gravity, "gravity_field", center)
local field = SpellConfig.get("gravity_field")
H.advance(field.castTime + field.pulses * field.pulseInterval + 0.3)
H.check(string.format("Champ Gravitationnel : %d impulsions (%.0f dégâts)", field.pulses, before - health(target)), before - health(target) >= field.damage * 4, before - health(target))
clearAll()

print("== Plusieurs joueurs, élimination unique, nettoyage")
local victim = spare
local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")
victimHumanoid.MaxHealth = 40
victimHumanoid.Health = 40
local defeats, eligible = 0, {}
GameEvents.EnemyDefeated:Connect(function(info)
	if info.enemy == victim then
		defeats += 1
		eligible = info.eligible
	end
end)
H.teleport(pyro, root(victim).Position + V3.new(0, 0, 8), root(victim).Position)
H.teleport(ice, root(victim).Position + V3.new(8, 0, 0), root(victim).Position)
StatusService.apply(victim, "burn", { source = pyro })
StatusService.apply(victim, "burn", { source = ice })
H.check("une seule brûlure par cible, cumulée par deux joueurs", StatusService.getLevel(victim, "burn") == 2)
DamageService.dealDamage(victim, 15, { player = pyro, model = pyro.Character, kind = "spell" })
H.advance(6)
H.check("ennemi éliminé par la brûlure", victimHumanoid.Health <= 0)
H.check("une seule élimination (aucune récompense en double)", defeats == 1, defeats)
H.check("les deux joueurs sont éligibles", table.find(eligible, pyro) ~= nil and table.find(eligible, ice) ~= nil, #eligible)
H.check("altérations nettoyées à la mort", victim:GetAttribute("Status_burn") == nil)

print("== Rembobinage")
StatusService.apply(target, "chill", { source = ice })
StatusService.apply(target, "burn", { source = pyro })
TimeLoopService.Rewound:Fire("test", { target }, {})
H.advance(0.1)
H.check("rembobinage : altérations et ralentissement effacés", not StatusService.has(target, "chill") and not StatusService.has(target, "burn") and target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) == nil)

print("== Ultimes : altérations communes")
heal(target)
local humanoidOf = function(p)
	return p.Character:FindFirstChildOfClass("Humanoid")
end
UltimateBehaviors.run({ caster = ice, casterHumanoid = humanoidOf(ice), origin = center, targets = { target }, magic = MagicConfig.getById("ice"), damageDealt = 0 })
H.check("Hiver Éternel : altération « frostbite » (x 0,35)", StatusService.has(target, "frostbite") and near(target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) or 1, 0.35))
UltimateBehaviors.run({ caster = lightning, casterHumanoid = humanoidOf(lightning), origin = center, targets = { target }, magic = MagicConfig.getById("lightning"), damageDealt = 0 })
H.check("Jugement Céleste : paralysie (immobile, sans attaque)", StatusService.has(target, "paralysis") and target:GetAttribute(StatusConfig.SPEED_ATTRIBUTE) == 0)
mock.task.spawn(UltimateBehaviors.run, { caster = pyro, casterHumanoid = humanoidOf(pyro), origin = center, targets = { third }, magic = MagicConfig.getById("pyromancy"), damageDealt = 0 })
H.check("Brasier du Parjure : brûlure à 2 crans", StatusService.getLevel(third, "burn") == 2)
clearAll()
H.noNewErrors("sorts serveur sans erreur")

print("== Client : lancer, Mana insuffisant, altérations visibles")
local C = require("./client")(mock, runtime, pyro)
for _, path in ipairs({ "Magic/SpellController", "Combat/StatusEffects", "UI/CombatHud" }) do
	mock.task.spawn(function()
		env.run("StarterPlayer/StarterPlayerScripts/Client/" .. path)
	end)
end
H.advance(1)
local function sentCasts()
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == "RequestCast" and s.kind == "FireServer" then
			n += 1
		end
	end
	return n
end
H.check("actions de sort liées (1 / 2, R1 / L2, tactile)", C.actions.SpellBase ~= nil and C.actions.SpellSecondary ~= nil)
ResourceService.restoreMana(pyro, 100)
place(pyro)
H.advance(2)
local castsBefore = sentCasts()
mock.task.spawn(C.actions.SpellBase.fn, "SpellBase", Enum.UserInputState.Begin, {})
C.frames(30)
H.check("touche 1 : Braise Ardente demandée au serveur", sentCasts() == castsBefore + 1)
local UIBus = env.require("StarterPlayer/StarterPlayerScripts/Client/UI/UIBus")
local denied = 0
UIBus.ManaDenied:Connect(function()
	denied += 1
end)
ResourceService.spendMana(pyro, ResourceService.getMana(pyro) - 3)
C.frames(5)
castsBefore = sentCasts()
mock.task.spawn(C.actions.SpellSecondary.fn, "SpellSecondary", Enum.UserInputState.Begin, {})
C.frames(5)
H.check("Mana insuffisant : rien n'est envoyé, la jauge le signale", sentCasts() == castsBefore and denied == 1, denied)
StatusService.apply(target, "burn", { source = pyro })
C.frames(5)
H.check("brûlure visible sur l'ennemi (braises)", target:FindFirstChild("StatusFx_burn", true) ~= nil)
StatusService.clear(target)
C.frames(5)
H.check("effet retiré avec l'altération", target:FindFirstChild("StatusFx_burn", true) == nil)
H.noNewErrors("sorts client sans erreur")
H.printWarnings()
H.finish()
