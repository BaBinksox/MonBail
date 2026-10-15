-- Scénarios multijoueurs dans la simulation (outil, hors Roblox), sur UN serveur simulé :
--   1. pouvoirs et mécanismes du monde (Gravité, Glace, ancre temporelle), coffres une seule fois ;
--   2. groupe + contrats : deux joueurs terminent le MÊME objectif en même temps ;
--   3. rembobinage pendant un combat de boss à deux (participants, pas de double récompense) ;
--   4. un joueur quitte pendant une sauvegarde ; panne du DataStore au départ ;
--   5. guilde : nom unique, deux officiers qui la modifient en même temps.
local H = require("./helpers")()
local mock = H.mock
local V3 = mock.Vector3

print("== Démarrage, deux joueurs (Gravité, Glace)")
H.boot()
local A = H.join("Aelis", 5001, 6)
local B = H.join("Bram", 5002, 4)
H.check("Aelis : Gravité", A:GetAttribute("InnateMagic") == "gravity")
H.check("Bram : Glace", B:GetAttribute("InnateMagic") == "ice")
H.noNewErrors("arrivée des deux joueurs")
local WorldAnchors = H.server("World/WorldAnchors")
local function xp(player)
	local profile = H.profile(player)
	return profile and profile.progression.xp or -1
end

--------------------------------------------------------------------------------
print("== 1. Pouvoirs et mécanismes")
local function solid(dynamicId)
	local dynamic = WorldAnchors.getDynamic(dynamicId)
	for _, d in ipairs(dynamic:GetDescendants()) do
		if d:IsA("BasePart") then
			return d.CanCollide
		end
	end
	return nil
end
H.interact(A, "mech_frozen_pond")
H.check("Glace refusée à Aelis (Gravité) : l'étang reste liquide", solid("pond_ice") == false)
H.interact(B, "mech_frozen_pond")
H.check("Bram gèle l'étang : les plaques portent", solid("pond_ice") == true)
H.interact(A, "mech_gravity_block")
H.advance(2)
local block = WorldAnchors.getDynamic("gravity_block")
local blockOpen = H.anchorPosition("gravity_block_open")
H.check("Aelis déplace le bloc gravé au pied de la corniche", (block:GetPivot().Position - blockOpen).Magnitude < 0.5)
local ledgeChest = WorldAnchors.getInteractable("chest_gravity")
local before = xp(A)
H.interact(A, "chest_gravity")
local afterFirst = xp(A)
H.advance(1)
H.interact(A, "chest_gravity")
H.check("coffre de la corniche : récompense versée", afterFirst > before, before .. " -> " .. afterFirst)
H.check("coffre de la corniche : pas une seconde fois", xp(A) == afterFirst)
local _ = ledgeChest
-- Ancre temporelle du pont : R près du sablier.
local TimeLoopRemotes = H.shared("TimeLoop/TimeLoopRemotes")
H.check("le pont est rompu", solid("bridge_restorable") == false)
H.teleport(A, WorldAnchors.getInteractable("anchor_bridge").Position + V3.new(3, 0, 0))
TimeLoopRemotes.RequestRewind.OnServerEvent:Fire(A)
H.advance(1)
H.check("R près de l'ancre : le pont se souvient (praticable)", solid("bridge_restorable") == true)
H.advance(16)
H.check("15 s plus tard : le pont redevient un souvenir", solid("bridge_restorable") == false)
H.noNewErrors("mécanismes sans erreur")

--------------------------------------------------------------------------------
print("== 2. Groupe et contrats partagés")
local invite = H.party(A, "invite", { targetName = "Bram" })
H.check("Aelis invite Bram", invite and invite.ok, invite and invite.message)
local PartyService = H.server("Party/PartyService")
local partyInfo = PartyService.getParty(A)
local accepted = partyInfo and H.party(B, "accept", { partyId = partyInfo.id })
H.check("Bram rejoint le groupe", accepted and accepted.ok and PartyService.areInSameParty(A, B), accepted and accepted.message)

local boardPart = WorldAnchors.getInteractable("board_missions")
for _, p in ipairs({ A, B }) do
	H.teleport(p, boardPart.Position + V3.new(4, 0, 0))
end
for _, p in ipairs({ A, B }) do
	local r1 = H.mission(p, "accept", "hunt_prowlers")
	local r2 = H.mission(p, "accept", "group_guardians")
	H.check(p.Name .. " accepte « Cendres errantes »", r1 and r1.ok, r1 and r1.error)
	H.check(p.Name .. " accepte le contrat de groupe", r2 and r2.ok, r2 and r2.error)
end
local DamageService = H.server("Combat/DamageService")
-- Les deux joueurs frappent chaque ennemi (chacun au-delà du seuil de participation).
local function killTogether(anchorId)
	local enemy = H.enemyAt(anchorId)
	if enemy == nil then
		return false
	end
	local position = enemy:GetPivot().Position
	H.teleport(A, position + V3.new(4, 0, 0))
	H.teleport(B, position + V3.new(-4, 0, 0))
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	local share = humanoid.MaxHealth * 0.35
	local guard = 0
	while humanoid.Health > 0 and guard < 40 do
		guard += 1
		DamageService.dealDamage(enemy, share, { player = A, model = A.Character, kind = "melee" })
		H.advance(0.3)
		DamageService.dealDamage(enemy, share, { player = B, model = B.Character, kind = "melee" })
		H.advance(0.3)
	end
	H.advance(1)
	return humanoid.Health <= 0
end
local prowlers = { "enemy_forest_1", "enemy_forest_2", "enemy_forest_5" }
local killed = 0
for _, anchorId in ipairs(prowlers) do
	if killTogether(anchorId) then
		killed += 1
	end
end
H.advance(47) -- réapparition des rôdeurs (45 s)
for i = 1, 2 do
	if killTogether(prowlers[i]) then
		killed += 1
	end
end
H.check("5 Rôdeurs vaincus à deux", killed == 5, killed)
local guardians = 0
for _, anchorId in ipairs({ "enemy_forest_3", "enemy_forest_7" }) do
	if killTogether(anchorId) then
		guardians += 1
	end
end
H.advance(47)
if killTogether("enemy_forest_3") then
	guardians += 1
end
H.check("3 Gardiens de Pierre vaincus en groupe", guardians == 3, guardians)
for _, p in ipairs({ A, B }) do
	H.teleport(p, boardPart.Position + V3.new(4, 0, 0))
end
for _, p in ipairs({ A, B }) do
	local xpBefore = xp(p)
	local claim = H.mission(p, "claim", "hunt_prowlers")
	local xpMid = xp(p)
	local again = H.mission(p, "claim", "hunt_prowlers")
	local group = H.mission(p, "claim", "group_guardians")
	H.check(p.Name .. " : les deux joueurs sont crédités (contrat rendu)", claim and claim.ok, claim and claim.error)
	H.check(p.Name .. " : récompense versée une fois", xpMid > xpBefore and (again == nil or not again.ok), (again and again.error) or "")
	H.check(p.Name .. " : contrat de groupe rendu", group and group.ok, group and group.error)
end
local solo = H.join("Cassian", 5003, 1)
H.teleport(solo, boardPart.Position + V3.new(4, 0, 0))
local refused = H.mission(solo, "accept", "group_guardians")
H.check("contrat de groupe refusé à un joueur seul", refused and not refused.ok, refused and refused.error)
H.noNewErrors("contrats sans erreur")

--------------------------------------------------------------------------------
print("== 3. Rembobinage pendant un combat de boss à deux")
-- Les ennemis ripostent pendant les contrats : on note les dégâts subis, puis chacun réapparaît soigné.
local hurt = 0
for _, p in ipairs({ A, B }) do
	local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health < humanoid.MaxHealth then
		hurt += 1
	end
	H.runtime.spawnCharacter(p)
end
H.advance(4)
H.check("les ennemis ont riposté pendant les contrats (IA active)", hurt > 0, hurt .. " joueur(s) blessé(s)")
local boss = H.enemyAt("boss_training")
H.check("le Gardien de l'Anomalie est dans son cercle", boss ~= nil)
if boss then
	local bossHumanoid = boss:FindFirstChildOfClass("Humanoid")
	local center = boss:GetPivot().Position
	H.teleport(A, center + V3.new(5, 0, 0))
	H.teleport(B, center + V3.new(-5, 0, 0))
	H.advance(2)
	local EncounterService = H.server("Encounter/EncounterService")
	local participants = EncounterService.getParticipants(boss)
	H.check("les deux joueurs sont participants de la rencontre", #participants == 2, #participants)
	-- On l'amène sous 20 % : il charge son attaque fatale et ouvre une anomalie sur un participant.
	-- (le test réagit dans la fenêtre de l'anomalie, comme un joueur : sinon la cible meurt)
	local function anomalyTarget()
		if #H.runtime.sentTo(A, "AnomalyOpened") > 0 then
			return A
		elseif #H.runtime.sentTo(B, "AnomalyOpened") > 0 then
			return B
		end
		return nil
	end
	local target = bossHumanoid.MaxHealth * 0.18
	local guard = 0
	while bossHumanoid.Health > target and guard < 60 and anomalyTarget() == nil do
		guard += 1
		DamageService.dealDamage(boss, 30, { player = if guard % 2 == 0 then A else B, model = (if guard % 2 == 0 then A else B).Character, kind = "melee" })
		H.advance(0.25)
	end
	local opened = anomalyTarget()
	for _ = 1, 80 do
		if opened then
			break
		end
		H.advance(0.25)
		opened = anomalyTarget()
	end
	H.advance(0.5)
	H.check("anomalie ouverte sur un participant", opened ~= nil)
	local healthBeforeRewind = bossHumanoid.Health
	if opened then
		TimeLoopRemotes.RequestRewind.OnServerEvent:Fire(opened)
		H.advance(8)
	end
	local rewound = #H.runtime.sentTo(A, "RewindStarted") > 0 and #H.runtime.sentTo(B, "RewindStarted") > 0
	H.check("le rembobinage concerne les deux participants", rewound)
	H.check("le boss revient en arrière (PV restaurés), toujours vivant", bossHumanoid.Health > healthBeforeRewind and bossHumanoid.Health > 0, healthBeforeRewind .. " -> " .. bossHumanoid.Health)
	local xpA, xpB = xp(A), xp(B)
	guard = 0
	while bossHumanoid.Health > 0 and guard < 120 do
		guard += 1
		DamageService.dealDamage(boss, 40, { player = if guard % 2 == 0 then A else B, model = (if guard % 2 == 0 then A else B).Character, kind = "melee" })
		H.advance(0.25)
	end
	H.advance(2)
	H.check("boss vaincu", bossHumanoid.Health <= 0)
	H.check("les deux participants sont récompensés", xp(A) > xpA and xp(B) > xpB, (xp(A) - xpA) .. " / " .. (xp(B) - xpB))
	local xpA2, xpB2 = xp(A), xp(B)
	TimeLoopRemotes.RequestRewind.OnServerEvent:Fire(A)
	H.advance(8)
	H.check("un rembobinage après la mort ne ranime pas le boss", boss.Parent == nil or bossHumanoid.Health <= 0)
	H.check("et ne repaie pas la victoire", xp(A) == xpA2 and xp(B) == xpB2)
end
H.noNewErrors("combat de boss sans erreur")

--------------------------------------------------------------------------------
print("== 4. Départ pendant une sauvegarde, panne du DataStore")
local ProfileStore = H.server("Data/ProfileStore")
local RewardService = H.server("Progression/RewardService")
RewardService.grant(solo, "test:avant_depart", { xp = 25 })
mock.task.spawn(function()
	ProfileStore.save(solo)
end)
H.advance(0.02) -- la sauvegarde est en vol...
H.leave(solo) -- ...quand le joueur quitte
local back = H.join("Cassian", 5003)
H.check("au retour : rien de perdu (clé de récompense présente)", H.profile(back) and H.profile(back).ledger["test:avant_depart"] ~= nil)
H.check("au retour : profil sauvegardable (verrou repris)", ProfileStore.isSaveable(back))
RewardService.grant(back, "test:pendant_panne", { xp = 10 })
H.runtime.dataStoreFailing = true
H.leave(back)
H.advance(20)
H.runtime.dataStoreFailing = false
local again = H.join("Cassian", 5003)
H.advance(5)
H.check("après une panne au départ : le joueur peut revenir jouer", H.profile(again) ~= nil and ProfileStore.isSaveable(again))
H.check("la dernière sauvegarde réussie est intacte", H.profile(again) and H.profile(again).ledger["test:avant_depart"] ~= nil)
H.noNewErrors("sauvegardes sans erreur Luau")

--------------------------------------------------------------------------------
print("== 5. Guilde : nom unique, officiers concurrents")
local created = H.guild(A, "create", { name = "Les Veilleurs", description = "Ceux qui gardent l'heure." })
H.check("Aelis fonde « Les Veilleurs »", created and created.ok, created and (created.error or created.message))
local clash = H.guild(again, "create", { name = "les veilleurs" })
H.check("le même nom (casse différente) est refusé", clash and not clash.ok, clash and clash.error)
local GuildService = H.server("Guild/GuildService")
local function guildIdOf(player)
	local profile = H.profile(player)
	return profile and profile.guild and profile.guild.guildId
end
local guildId = guildIdOf(A)
for _, p in ipairs({ B, again }) do
	local inv = H.guild(A, "invite", { targetName = p.Name })
	local acc = H.guild(p, "acceptInvite", { guildId = guildId })
	H.check(p.Name .. " rejoint la guilde", inv and inv.ok and acc and acc.ok, (inv and inv.error) or (acc and acc.error))
end
local p1 = H.guild(A, "promote", { targetUserId = B.UserId })
local p2 = H.guild(A, "promote", { targetUserId = again.UserId })
H.check("deux officiers nommés", p1 and p1.ok and p2 and p2.ok, (p1 and p1.error) or (p2 and p2.error))
-- Les deux officiers agissent au même instant.
local results = {}
mock.task.spawn(function()
	results.b = H.shared("Guild/GuildRemotes").GuildRequest.OnServerInvoke(B, "setDescription", { description = "Bram a écrit ceci." })
end)
mock.task.spawn(function()
	results.c = H.shared("Guild/GuildRemotes").GuildRequest.OnServerInvoke(again, "setDescription", { description = "Cassian a écrit cela." })
end)
H.advance(6)
H.check("les deux modifications simultanées aboutissent sans erreur", results.b and results.b.ok and results.c and results.c.ok, (results.b and results.b.error) or (results.c and results.c.error))
local info = H.guild(A, "getInfo")
local description = info and info.data and (info.data.description or (info.data.guild and info.data.guild.description))
H.check("la description finale est l'une des deux (pas de mélange)", description == "Bram a écrit ceci." or description == "Cassian a écrit cela.", description)
local kickResult, demoteResult = nil, nil
mock.task.spawn(function()
	kickResult = H.shared("Guild/GuildRemotes").GuildRequest.OnServerInvoke(A, "kick", { targetUserId = again.UserId })
end)
mock.task.spawn(function()
	demoteResult = H.shared("Guild/GuildRemotes").GuildRequest.OnServerInvoke(B, "demote", { targetUserId = again.UserId })
end)
H.advance(6)
H.check("exclusion et rétrogradation concurrentes : au moins l'exclusion aboutit", kickResult and kickResult.ok, kickResult and kickResult.error)
H.check("profil de l'exclu réconcilié (plus de guilde)", guildIdOf(again) == nil, guildIdOf(again))
local _ = GuildService
local _d = demoteResult
H.noNewErrors("guilde sans erreur")
H.printWarnings()
H.finish()
