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

print("== Nature des sorts affichée (SpellTags, déduite des données serveur)")
do
	local SpellTags = H.shared("Magic/SpellTags")
	local expected = {
		frost_shard = "Projectile · Ralentit",
		crystal_prison = "Zone ciblée · Immobilise",
		void_fragment = "Projectile · Explose",
		minor_singularity = "Zone ciblée · Aspire",
		dark_bolt = "Projectile · Draine la vie",
		shadow_veil = "Sur soi · Protège",
		gravity_field = "Zone persistante · Ralentit, use la garde",
		electric_arc = "Instantané · Interrompt",
	}
	local wrong = {}
	for id, text in pairs(expected) do
		local got = SpellTags.describe(SpellConfig.get(id))
		if got ~= text then table.insert(wrong, id .. " = " .. got) end
	end
	H.check("étiquettes justes (forme · effet)", #wrong == 0, table.concat(wrong, " ; "))
	local same = {}
	for _, magic in ipairs(MagicConfig.MAGICS) do
		local base = SpellTags.describe(SpellConfig.forMagic(magic.id, "base"))
		local secondary = SpellTags.describe(SpellConfig.forMagic(magic.id, "secondary"))
		if base == secondary then table.insert(same, magic.id) end
	end
	H.check("les deux sorts de chaque magie se distinguent (forme ou effet)", #same == 0, table.concat(same, ","))
end
print("== Gestes calés sur le serveur")
local PoseLibrary = H.shared("Animation/PoseLibrary")
local AnimationConfig = H.shared("Animation/AnimationConfig")
for _, spell in ipairs(SpellConfig.SPELLS) do
	local pose = PoseLibrary.get(AnimationConfig.ACTIONS[spell.action].pose)
	local gesture = pose.impact * pose.duration
	H.check(string.format("%s : geste à %.2f s, sort lancé à %.2f s", spell.name, gesture, spell.castTime), math.abs(gesture - spell.castTime) <= 0.06)
end
for _, magic in ipairs(MagicConfig.MAGICS) do
	local action = AnimationConfig.ACTIONS["cast_ultimate_" .. magic.id]
	local pose = action and PoseLibrary.get(action.pose)
	local gesture = pose and pose.impact * pose.duration or -1
	H.check(string.format("%s : pose dédiée, frappe à %.2f s pour un impact serveur à %.2f s", magic.ultimateName, gesture, magic.ultimateWindup), pose ~= nil and math.abs(gesture - magic.ultimateWindup) <= 0.03)
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
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
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
print("== Ultimes Glace et Antimatière : impact à la fin de la préparation")
local CombatRemotes = H.shared("Combat/CombatRemotes")
for _, magicId in ipairs({ "ice", "antimatter" }) do
	local mage = mages[magicId]
	local magic = MagicConfig.getById(magicId)
	clearAll()
	H.teleport(mage, root(target).Position + V3.new(0, 0, 6), root(target).Position)
	ResourceService.setTension(mage, 100)
	local hpBefore = health(target)
	CombatRemotes.RequestUltimate.OnServerEvent:Fire(mage)
	H.advance(magic.ultimateWindup * 0.6)
	H.check(string.format("%s : rien avant la fin de la préparation (%.2f s)", magic.ultimateName, magic.ultimateWindup), health(target) == hpBefore)
	H.advance(magic.ultimateWindup * 0.4 + 0.15)
	H.check(magic.ultimateName .. " : dégâts appliqués à l'impact", health(target) < hpBefore, hpBefore - health(target))
	if magicId == "ice" then
		H.check("Hiver Éternel : gel (frostbite) posé au même instant", StatusService.has(target, "frostbite"))
	end
	H.advance(2)
end
clearAll()
H.noNewErrors("sorts serveur sans erreur")

print("== Client : lancer, Mana insuffisant, altérations visibles")
local C = require("./client")(mock, runtime, pyro)
for _, path in ipairs({ "Magic/SpellController", "Combat/StatusEffects", "UI/CombatHud", "Combat/CombatController" }) do
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
local hudGui = C.playerGui:FindFirstChild("CombatHudGui")
local baseSlot = hudGui and hudGui:FindFirstChild("SpellBaseSlot", true)
C.frames(10)
local timer = baseSlot and baseSlot:FindFirstChildWhichIsA("TextLabel", true)
local slotTexts = {}
if baseSlot then
	for _, d in ipairs(baseSlot:GetDescendants()) do
		if d:IsA("TextLabel") then
			table.insert(slotTexts, d.Text)
		end
	end
end
H.check("HUD : emplacement du sort de base nommé (Braise Ardente, 18)", table.find(slotTexts, "Braise Ardente") ~= nil and table.find(slotTexts, "18") ~= nil, table.concat(slotTexts, "|"))
local cooldownShade = baseSlot and baseSlot:FindFirstChild("Cooldown")
H.check("HUD : recharge affichée après le lancer", cooldownShade ~= nil and cooldownShade.Size.Y.Scale > 0, cooldownShade and cooldownShade.Size.Y.Scale)
local _ = timer
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
C.frames(10)
local secondarySlot = hudGui and hudGui:FindFirstChild("SpellSecondarySlot", true)
local costRed = false
if secondarySlot then
	for _, d in ipairs(secondarySlot:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "35" and d.TextColor3.R > 0.8 then
			costRed = true
		end
	end
end
H.check("HUD : coût du sort secondaire en rouge quand le Mana manque", costRed)
StatusService.apply(target, "burn", { source = pyro })
C.frames(5)
H.check("brûlure visible sur l'ennemi (braises)", target:FindFirstChild("StatusFx_burn", true) ~= nil)
StatusService.clear(target)
C.frames(5)
H.check("effet retiré avec l'altération", target:FindFirstChild("StatusFx_burn", true) == nil)
print("== Client : chorégraphies Glace et Antimatière")
local function effects(name)
	local found = 0
	local holder = mock.workspace:FindFirstChild("UltimateEffects")
	if holder then
		for _, child in ipairs(holder:GetChildren()) do
			if child.Name == name then
				found += 1
			end
		end
	end
	return found
end
-- Outils de contrôle des effets « Magies 3.0 ».
local function fxFolders()
	local list = {}
	for _, holderName in ipairs({ "SpellEffects", "UltimateEffects" }) do
		local holder = mock.workspace:FindFirstChild(holderName)
		if holder then table.insert(list, holder) end
	end
	return list
end
local function fxStats()
	local stats = { parts = 0, solid = 0, cylinders = 0, wedges = 0, glass = 0 }
	for _, holder in ipairs(fxFolders()) do
		for _, d in ipairs(holder:GetDescendants()) do
			local cls = rawget(d, "ClassName")
			if cls == "Part" or cls == "WedgePart" then
				stats.parts += 1
				if d.CanCollide or d.CanQuery or d.CanTouch then stats.solid += 1 end
				if cls == "WedgePart" then stats.wedges += 1 end
				if cls == "Part" and d.Shape == Enum.PartType.Cylinder then stats.cylinders += 1 end
				if d.Material == Enum.Material.Glass then stats.glass += 1 end
			end
		end
	end
	return stats
end
local function clearFx()
	for _, holder in ipairs(fxFolders()) do
		for _, child in ipairs(holder:GetChildren()) do child:Destroy() end
	end
end
local function dummy(name, position, boss)
	local model = mock.Instance.new("Model")
	model.Name = name
	local humanoid = mock.Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = model
	local part = mock.Instance.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = V3.new(2, 2, 1)
	part.CFrame = mock.CFrame.new(position)
	part.Parent = model
	humanoid.RootPart = part
	model.PrimaryPart = part
	model.Parent = mock.workspace
	if boss then mock.game:GetService("CollectionService"):AddTag(model, "Boss") end
	return model
end
local iceMagic = MagicConfig.getById("ice")
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(root(target).Position + V3.new(0, 10, 30)) -- joueur proche
clearFx()
CombatRemotes.UltimateFired.OnClientEvent:Fire(mages.ice.Character, root(target).Position + V3.new(0, 0, 6), { target }, "ice")
C.frames(20)
H.check("Hiver Éternel, préparation : cristaux en suspension et givre qui gagne le sol", effects("FloatingCrystal") >= 3 and effects("Frost") >= 6, effects("FloatingCrystal") .. "/" .. effects("Frost"))
H.check("Hiver Éternel, préparation : aucune formation avant l'impact", effects("Spire") == 0)
C.frames(math.ceil(iceMagic.ultimateWindup * 60) + 15)
H.check("Hiver Éternel, impact : grandes formations autour du lanceur et des cibles", effects("Spire") >= 4 + 3, effects("Spire"))
H.check("Hiver Éternel : les cristaux en suspension ont éclaté", effects("FloatingCrystal") == 0)
local iceStats = fxStats()
H.check("Hiver Éternel : vrais cristaux (verre + pointes), aucun disque", iceStats.wedges >= 16 and iceStats.glass >= 20 and iceStats.cylinders == 0, string.format("coins %d, verre %d, cylindres %d", iceStats.wedges, iceStats.glass, iceStats.cylinders))
H.check("Hiver Éternel : aucune pièce d'effet solide (collision, requête, contact)", iceStats.solid == 0, iceStats.solid)
H.check("Hiver Éternel : budget de pièces raisonnable", iceStats.parts <= 220, iceStats.parts)
C.frames(60 * 6)
H.check("Hiver Éternel : tout a disparu ensuite (rien ne reste dans le Workspace)", fxStats().parts == 0, fxStats().parts)
local amMagic = MagicConfig.getById("antimatter")
local AudioMixer = env.require("StarterPlayer/StarterPlayerScripts/Client/Audio/AudioMixer")
local amOrigin = root(target).Position + V3.new(0, 0, 6)
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(amOrigin + V3.new(0, 8, 20)) -- joueur proche
local musicBefore = AudioMixer.getVolume("Music")
clearFx()
CombatRemotes.UltimateFired.OnClientEvent:Fire(mages.antimatter.Character, amOrigin, { target }, "antimatter")
C.frames(15)
H.check("Rupture du Néant, préparation : cœur, espace comprimé (lentille), matière tirée en spirale", effects("VoidCore") == 1 and effects("Distortion") == 1 and effects("VoidMote") >= 5, effects("VoidMote"))
H.check("Rupture du Néant, préparation : lien d'énergie vers la cible", root(target):FindFirstChild("VoidTether") ~= nil)
H.check("Rupture du Néant, préparation : aucun disque", fxStats().cylinders == 0, fxStats().cylinders)
C.frames(math.ceil(amMagic.ultimateWindup * 60) - 18)
H.check("Rupture du Néant : instant de silence juste avant la libération (musique atténuée)", AudioMixer.getVolume("Music") < musicBefore * 0.6, AudioMixer.getVolume("Music"))
C.frames(14)
H.check("Rupture du Néant, libération : effondrement du cœur puis onde géante", effects("VoidCore") == 0 and effects("VoidWave") == 1 and effects("RuptureShell") >= 1)
H.check("Rupture du Néant, libération : fissures sombres au sol", effects("VoidCrack") >= 4, effects("VoidCrack"))
H.check("Rupture du Néant : aucune pièce d'effet solide", fxStats().solid == 0)
C.frames(60 * 3)
H.check("Rupture du Néant : la musique revient", math.abs(AudioMixer.getVolume("Music") - musicBefore) < 1e-3, AudioMixer.getVolume("Music"))
C.frames(60 * 3)
H.check("Rupture du Néant : tout a disparu", fxStats().parts == 0, fxStats().parts)
-- Les quatre autres ultimes (Magies 3.0) : préparation, impact au bon moment, rien de solide, nettoyage.
local function fxCount(className, enabledOnly)
	local n = 0
	for _, holder in ipairs(fxFolders()) do
		for _, d in ipairs(holder:GetDescendants()) do
			if rawget(d, "ClassName") == className and (not enabledOnly or d.Enabled ~= false) then n += 1 end
		end
	end
	return n
end
local ultimateCases = {
	{
		id = "pyromancy",
		before = function() return fxCount("Fire") >= 4 and effects("LavaCrack") >= 4, fxCount("Fire") .. " flammes, " .. effects("LavaCrack") .. " fissures" end,
		after = function() return fxCount("Fire") >= 10 and effects("HotGround") >= 6, fxCount("Fire") .. " flammes, " .. effects("HotGround") .. " sol" end,
		label = "cercle de flammes et fissures de lave, puis colonne et vagues de feu",
	},
	{
		id = "lightning",
		before = function() return effects("StrikeMark") >= 1 and effects("StaticAura") == 1, effects("StrikeMark") end,
		after = function() return effects("Bolt") >= 20, effects("Bolt") .. " segments" end,
		label = "électricité statique et lueur sur la cible, puis éclairs ramifiés tombés du ciel",
	},
	{
		id = "shadow",
		before = function() return effects("Shade") >= 3 and effects("ShadowPool") >= 6 and fxCount("Beam") >= 1, effects("Shade") .. " formes" end,
		after = function() return effects("Shade") == 0 and effects("LifeWisp") >= 1, effects("LifeWisp") .. " lueurs" end,
		label = "flaque, formes sombres et vrilles, puis vague et vie qui revient",
	},
	{
		id = "gravity",
		before = function() return effects("Rock") >= 6 and effects("GravityDome") == 1, effects("Rock") .. " débris" end,
		after = function() return effects("GravityDome") == 0 and effects("GroundCrack") >= 4, effects("GroundCrack") .. " fissures" end,
		label = "débris qui s'élèvent et dôme, puis écrasement et fissures",
		extra = 0.35 + 0.2 + 0.15, -- soulèvement + écrasement du serveur
	},
}
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(root(target).Position + V3.new(0, 10, 30))
for _, case in ipairs(ultimateCases) do
	local magic = MagicConfig.getById(case.id)
	clearFx()
	CombatRemotes.UltimateFired.OnClientEvent:Fire(mages[case.id].Character, root(target).Position + V3.new(0, 0, 6), { target }, case.id)
	C.frames(math.ceil(magic.ultimateWindup * 60 * 0.7))
	local okBefore, infoBefore = case.before()
	H.check(magic.ultimateName .. ", préparation : " .. case.label, okBefore, infoBefore)
	H.check(magic.ultimateName .. ", préparation : aucun disque", fxStats().cylinders == 0, fxStats().cylinders)
	C.frames(math.ceil((magic.ultimateWindup * 0.3 + (case.extra or 0) + 0.15) * 60))
	local okAfter, infoAfter = case.after()
	H.check(magic.ultimateName .. ", impact au moment des dégâts", okAfter, infoAfter)
	H.check(magic.ultimateName .. " : aucune pièce d'effet solide", fxStats().solid == 0, fxStats().solid)
	C.frames(60 * 6)
	H.check(magic.ultimateName .. " : tout a disparu", fxStats().parts == 0, fxStats().parts)
end
local function spellFx(name)
	local found = 0
	for _, holderName in ipairs({ "SpellEffects", "UltimateEffects" }) do
		local holder = mock.workspace:FindFirstChild(holderName)
		if holder then
			for _, child in ipairs(holder:GetChildren()) do
				if child.Name == name then
					found += 1
				end
			end
		end
	end
	return found
end
local origin = root(target).Position + V3.new(0, 1.5, 12)
clearFx()
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.ice.Character, "frost_shard", 9001, origin, root(target).Position)
C.frames(4)
H.check("Éclat de Givre, préparation : un cristal se forme dans la main", spellFx("FormingCrystal") == 1)
C.frames(math.ceil(SpellConfig.get("frost_shard").castTime * 60))
local shard = mock.workspace.SpellEffects:FindFirstChild("FrostShard")
local shardWedges = 0
for _, d in ipairs(shard and shard:GetDescendants() or {}) do
	if rawget(d, "ClassName") == "WedgePart" then shardWedges += 1 end
end
H.check("Éclat de Givre : projectile cristallin en 3D (plusieurs fragments pointus)", shard ~= nil and shardWedges >= 8, shardWedges)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9001, "frost_shard", root(target).Position, { target })
C.frames(15)
H.check("Éclat de Givre, impact : le cristal éclate en fragments et le givre s'étend", spellFx("FrostShard") == 0 and spellFx("Shard") >= 3 and spellFx("Frost") >= 2, spellFx("Shard") .. "/" .. spellFx("Frost"))
H.check("Éclat de Givre : pas de pointes de prison (sorts distincts)", spellFx("Spire") == 0)
C.frames(60 * 3)
H.check("Éclat de Givre : tout a disparu", fxStats().parts == 0, fxStats().parts)

-- Prison Cristalline : cible gelée (attribut du serveur) contre boss qui résiste.
local frozen = dummy("Gelé", root(target).Position + V3.new(30, 0, 0), false)
local boss = dummy("BossRésistant", root(target).Position + V3.new(36, 0, 0), true)
frozen:SetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. "freeze", mock.workspace:GetServerTimeNow() + 2.5)
local prisonPoint = root(frozen).Position
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(prisonPoint + V3.new(0, 10, 25)) -- caméra proche : détail complet
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.ice.Character, "crystal_prison", 9002, origin, prisonPoint)
C.frames(math.ceil(SpellConfig.get("crystal_prison").castTime * 60 * 0.8))
local telegraphStats = fxStats()
H.check("Prison Cristalline, préparation : givre et bourgeons de cristal, aucun disque", spellFx("Frost") >= 4 and spellFx("Spire") >= 3 and telegraphStats.cylinders == 0, string.format("givre %d, pointes %d, cylindres %d", spellFx("Frost"), spellFx("Spire"), telegraphStats.cylinders))
C.frames(20)
clearFx()
SpellRemotes.SpellImpact.OnClientEvent:Fire(9002, "crystal_prison", prisonPoint, { frozen, boss })
C.frames(30)
H.check("Prison Cristalline, impact : pointes successives autour des cibles", spellFx("Spire") >= 6, spellFx("Spire"))
local function spiresNear(model)
	local n = 0
	local position = root(model).Position
	for _, holder in ipairs(fxFolders()) do
		for _, child in ipairs(holder:GetChildren()) do
			if child.Name == "Spire" and (child.Position - position).Magnitude < 4 then n += 1 end
		end
	end
	return n
end
C.frames(40) -- 1,2 s après l'impact
H.check("Prison Cristalline : la cage tient tant que la cible est gelée", spiresNear(frozen) >= 3, spiresNear(frozen))
H.check("Prison Cristalline : un boss (simple froid) brise aussitôt sa cage", spiresNear(boss) == 0, spiresNear(boss))
C.frames(60 * 2)
H.check("Prison Cristalline : la cage éclate quand le gel prend fin", spiresNear(frozen) == 0, spiresNear(frozen))
H.check("Prison Cristalline : aucune pièce d'effet solide", fxStats().solid == 0)
C.frames(60 * 4)
H.check("Prison Cristalline : tout a disparu", fxStats().parts == 0, fxStats().parts)
frozen:Destroy()
boss:Destroy()
clearFx()
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.antimatter.Character, "void_fragment", 9003, origin, root(target).Position)
C.frames(5)
H.check("Fragment du Vide, préparation : sphère noire condensée dans la main", spellFx("ChargingVoid") == 1)
C.frames(math.ceil(SpellConfig.get("void_fragment").castTime * 60))
local fragment = mock.workspace.SpellEffects:FindFirstChild("VoidFragment")
H.check("Fragment du Vide : sphère à couches (cœur noir, lentille, coque)", fragment ~= nil and fragment:FindFirstChild("Core") ~= nil and fragment:FindFirstChild("Lens") ~= nil and fragment:FindFirstChild("Shell") ~= nil)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9003, "void_fragment", root(target).Position, { target })
C.frames(2)
H.check("Fragment du Vide, impact : la sphère se contracte d'abord", spellFx("VoidFold") == 1 and spellFx("RuptureShell") == 0)
C.frames(15)
H.check("Fragment du Vide, impact : puis l'onde de rupture et les éclats", spellFx("VoidFold") == 0 and spellFx("RuptureShell") == 1 and spellFx("Shard") >= 3)
H.check("Fragment du Vide : ni singularité ni aspiration (sorts distincts)", spellFx("Singularity") == 0 and spellFx("VoidShard") == 0)
C.frames(60 * 3)
H.check("Fragment du Vide : tout a disparu", fxStats().parts == 0, fxStats().parts)

local pulled = dummy("Aspiré", root(target).Position + V3.new(30, 0, 4), false)
local heavy = dummy("BossLourd", root(target).Position + V3.new(30, 0, -4), true)
local singularityPoint = root(target).Position + V3.new(30, 0, 0)
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(singularityPoint + V3.new(0, 10, 25))
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.antimatter.Character, "minor_singularity", 9004, origin, singularityPoint)
C.frames(10)
H.check("Singularité Mineure, préparation : point noir et espace qui se bombe, aucun disque", spellFx("SingularitySeed") == 1 and spellFx("SingularityLens") == 1 and fxStats().cylinders == 0)
C.frames(30)
clearFx()
SpellRemotes.SpellImpact.OnClientEvent:Fire(9004, "minor_singularity", singularityPoint, { pulled, heavy })
C.frames(12)
local function beams()
	local n = 0
	for _, holder in ipairs(fxFolders()) do
		for _, d in ipairs(holder:GetDescendants()) do
			if rawget(d, "ClassName") == "Beam" then n += 1 end
		end
	end
	return n
end
H.check("Singularité Mineure : cœur sombre, coque, fragments en orbite", spellFx("Singularity") == 1 and spellFx("SingularityShell") == 1 and spellFx("VoidShard") >= 4, spellFx("VoidShard"))
H.check("Singularité Mineure : lien tendu vers l'ennemi aspiré seulement (le boss rompt le sien)", beams() == 1, beams())
C.frames(50)
H.check("Singularité Mineure : contraction puis implosion finale", spellFx("Singularity") == 0 and spellFx("RuptureShell") == 1)
H.check("Singularité Mineure : aucune pièce d'effet solide", fxStats().solid == 0)
C.frames(60 * 3)
H.check("Singularité Mineure : tout a disparu", fxStats().parts == 0, fxStats().parts)
pulled:Destroy()
heavy:Destroy()
-- Charge : dix lanceurs au même endroit, en même temps. Le budget doit contenir le nombre de pièces.
do
	clearFx()
	local crowd = {}
	local center = root(target).Position + V3.new(60, 0, 0)
	for index = 1, 3 do
		table.insert(crowd, dummy("Foule" .. index, center + V3.new(index * 3, 0, 0), false))
	end
	mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(center + V3.new(0, 10, 25))
	for index = 1, 10 do
		local spellId = if index % 2 == 0 then "crystal_prison" else "minor_singularity"
		local caster = if index % 2 == 0 then mages.ice.Character else mages.antimatter.Character
		SpellRemotes.SpellCast.OnClientEvent:Fire(caster, spellId, 9500 + index, origin, center)
		SpellRemotes.SpellImpact.OnClientEvent:Fire(9500 + index, spellId, center, crowd)
	end
	-- Les douze sorts des six magies, en même temps, plus trois ultimes.
	for index, spell in ipairs(SpellConfig.SPELLS) do
		SpellRemotes.SpellCast.OnClientEvent:Fire(mages[spell.magic].Character, spell.id, 9600 + index, origin, center)
		SpellRemotes.SpellImpact.OnClientEvent:Fire(9600 + index, spell.id, center, crowd)
	end
	for _, magicId in ipairs({ "pyromancy", "lightning", "gravity" }) do
		mock.task.spawn(function()
			CombatRemotes.UltimateFired.OnClientEvent:Fire(mages[magicId].Character, center, crowd, magicId)
		end)
	end
	local peak = 0
	for _ = 1, 40 do
		C.frames(3)
		peak = math.max(peak, fxStats().parts)
	end
	print("    pic de pièces d'effet : " .. peak)
	H.check("22 sorts et 3 ultimes simultanés : pièces d'effet contenues par le budget", peak <= 900, peak)
	C.frames(60 * 10)
	H.check("sorts et ultimes simultanés : tout a disparu ensuite", fxStats().parts == 0, fxStats().parts)
	for _, model in ipairs(crowd) do model:Destroy() end
end
-- Pyromancie
local near = root(target).Position
mock.workspace.CurrentCamera.CFrame = mock.CFrame.new(near + V3.new(0, 10, 30))
clearFx()
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.pyromancy.Character, "ember", 9101, origin, near)
C.frames(5)
H.check("Braise Ardente, préparation : une flamme naît dans la paume", spellFx("EmberCharge") == 1 and fxCount("Fire") >= 1)
C.frames(math.ceil(SpellConfig.get("ember").castTime * 60))
local fireball = mock.workspace.SpellEffects:FindFirstChild("Ember")
H.check("Braise Ardente : boule de feu (noyau incandescent + vraies flammes)", fireball ~= nil and fireball:FindFirstChild("Core") ~= nil and fireball:FindFirstChildOfClass("Fire") ~= nil)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9101, "ember", near, { target })
C.frames(10)
H.check("Braise Ardente, impact : explosion ardente et sol roussi", spellFx("Scorch") >= 2 and spellFx("Flames") >= 1)
C.frames(60 * 4)
H.check("Braise Ardente : tout a disparu", fxStats().parts == 0, fxStats().parts)

SpellRemotes.SpellCast.OnClientEvent:Fire(mages.pyromancy.Character, "blazing_circle", 9102, origin, near)
C.frames(math.ceil(SpellConfig.get("blazing_circle").castTime * 60 * 0.9))
H.check("Cercle Incandescent, préparation : sol qui chauffe, braises, flammes sur le pourtour, aucun disque", spellFx("Flames") >= 3 and spellFx("HotGround") >= 3 and spellFx("Embers") == 1 and fxStats().cylinders == 0)
C.frames(10)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9102, "blazing_circle", near, { target })
C.frames(15)
H.check("Cercle Incandescent, impact : langues de feu de hauteurs variées", fxCount("Fire", true) >= 6, fxCount("Fire", true))
C.frames(math.ceil(1.6 * 60))
H.check("Cercle Incandescent : les flammes retombent (la zone n'agit qu'à l'impact côté serveur)", fxCount("Fire", true) == 0, fxCount("Fire", true))
C.frames(60 * 4)
H.check("Cercle Incandescent : tout a disparu", fxStats().parts == 0, fxStats().parts)

-- Foudre
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.lightning.Character, "electric_arc", 9201, origin, near)
C.frames(3)
H.check("Arc Électrique, préparation : crépitement dans la main", spellFx("ArcCharge") == 1)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9201, "electric_arc", near, { target })
C.frames(2)
H.check("Arc Électrique : éclair ramifié (nombreux segments brisés)", spellFx("Bolt") >= 8, spellFx("Bolt"))
C.frames(60 * 3)
local chainTargets = {
	dummy("Chaîne1", near + V3.new(8, 0, 0), false),
	dummy("Chaîne2", near + V3.new(14, 0, 6), false),
	dummy("Chaîne3", near + V3.new(10, 0, 14), false),
}
clearFx()
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.lightning.Character, "chain_lightning", 9202, origin, near)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9202, "chain_lightning", root(chainTargets[1]).Position, chainTargets)
local reached = {}
for _ = 1, 20 do
	C.frames(1)
	for index, model in ipairs(chainTargets) do
		local position = root(model).Position
		for _, holder in ipairs(fxFolders()) do
			for _, child in ipairs(holder:GetChildren()) do
				if child.Name == "Bolt" and (child.Position - position).Magnitude < 3 then reached[index] = true end
			end
		end
	end
end
H.check("Chaîne Foudroyante : l'éclair atteint chaque cible à sa position réelle", reached[1] and reached[2] and reached[3])
for _, model in ipairs(chainTargets) do model:Destroy() end
C.frames(60 * 3)
H.check("Foudre : tout a disparu", fxStats().parts == 0, fxStats().parts)

-- Ombre
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.shadow.Character, "dark_bolt", 9301, origin, near)
C.frames(5)
H.check("Trait Obscur, préparation : volutes sombres vers la main", spellFx("ShadowCharge") == 1)
C.frames(math.ceil(SpellConfig.get("dark_bolt").castTime * 60))
local darkBolt = mock.workspace.SpellEffects:FindFirstChild("DarkBolt")
local trailCount = 0
for _, d in ipairs(darkBolt and darkBolt:GetChildren() or {}) do
	if rawget(d, "ClassName") == "Trail" then trailCount += 1 end
end
H.check("Trait Obscur : matière sombre avec filaments mouvants", darkBolt ~= nil and trailCount >= 2, trailCount)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9301, "dark_bolt", near, { target })
C.frames(4)
local casterPosition = root(mages.shadow.Character).Position
local function wispDistance()
	local best = math.huge
	for _, holder in ipairs(fxFolders()) do
		for _, child in ipairs(holder:GetChildren()) do
			if child.Name == "LifeWisp" then best = math.min(best, (child.Position - casterPosition).Magnitude) end
		end
	end
	return best
end
local startDistance = wispDistance()
C.frames(18)
H.check("Trait Obscur : l'énergie volée revient vers le lanceur", spellFx("LifeWisp") >= 1 and wispDistance() < startDistance, string.format("%.1f -> %.1f", startDistance, wispDistance()))
C.frames(60 * 3)
local shadowCaster = mages.shadow.Character
shadowCaster:SetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. "veil", mock.workspace:GetServerTimeNow() + 1.5)
SpellRemotes.SpellCast.OnClientEvent:Fire(shadowCaster, "shadow_veil", 9302, origin, near)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9302, "shadow_veil", root(shadowCaster).Position, {})
C.frames(30)
H.check("Voile des Ombres : filaments sombres en orbite autour du lanceur", spellFx("VeilFilament") >= 2, spellFx("VeilFilament"))
C.frames(60 * 1.5)
H.check("Voile des Ombres : se disperse quand le voile du serveur prend fin", spellFx("VeilFilament") == 0, spellFx("VeilFilament"))
shadowCaster:SetAttribute(StatusConfig.ATTRIBUTE_PREFIX .. "veil", nil)
C.frames(60 * 3)
H.check("Ombre : tout a disparu", fxStats().parts == 0, fxStats().parts)

-- Gravité
local pressPoint = near + V3.new(0, 0, -10)
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.gravity.Character, "gravity_press", 9401, origin, pressPoint)
C.frames(math.ceil(SpellConfig.get("gravity_press").castTime * 60))
local liftedRocks = 0
for _, holder in ipairs(fxFolders()) do
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Rock" and child.Position.Y > pressPoint.Y + 0.6 then liftedRocks += 1 end
	end
end
H.check("Pression Gravitationnelle, préparation : cailloux soulevés au point visé", liftedRocks >= 2, liftedRocks)
SpellRemotes.SpellImpact.OnClientEvent:Fire(9401, "gravity_press", pressPoint, { target })
C.frames(3)
H.check("Pression Gravitationnelle, impact : l'espace s'écrase (lentille)", spellFx("PressureLens") == 1)
C.frames(20)
H.check("Pression Gravitationnelle : fissures et onde rasante", spellFx("GroundCrack") >= 3, spellFx("GroundCrack"))
C.frames(60 * 3)
H.check("Pression Gravitationnelle : tout a disparu", fxStats().parts == 0, fxStats().parts)

local fieldSpell = SpellConfig.get("gravity_field")
local fieldPoint = near + V3.new(0, 0, -20)
SpellRemotes.SpellCast.OnClientEvent:Fire(mages.gravity.Character, "gravity_field", 9402, origin, fieldPoint)
C.frames(math.ceil((fieldSpell.castTime + 1) * 60))
local floating = 0
for _, holder in ipairs(fxFolders()) do
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Rock" and child.Position.Y > fieldPoint.Y + 0.6 then floating += 1 end
	end
end
H.check("Champ Gravitationnel : pierres en suspension et limite visible (dôme), aucun disque", floating >= 4 and spellFx("GravityDome") == 1 and fxStats().cylinders == 0, floating)
-- Le serveur termine plus tôt (rembobinage par exemple) : le champ se referme à l'impact.
SpellRemotes.SpellImpact.OnClientEvent:Fire(9402, "gravity_field", fieldPoint, { target })
C.frames(40)
local stillFloating = 0
for _, holder in ipairs(fxFolders()) do
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Rock" and child.Position.Y > fieldPoint.Y + 1.2 then stillFloating += 1 end
	end
end
H.check("Champ Gravitationnel : à la fin réelle, les pierres retombent", stillFloating == 0, stillFloating)
C.frames(60 * 4)
H.check("Gravité : tout a disparu", fxStats().parts == 0, fxStats().parts)
H.check("aucune pièce d'effet solide (quatre magies)", fxStats().solid == 0)
C.frames(120)
C.frames(120)
H.noNewErrors("sorts client sans erreur")
H.printWarnings()
H.finish()
