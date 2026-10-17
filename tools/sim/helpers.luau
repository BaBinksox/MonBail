-- Aides communes aux tests de parcours (outil, hors Roblox) : démarrage du serveur, joueurs prêts à
-- jouer (personnage créé), déplacements, interactions, dialogues, combat.
-- Usage : local H = require("./helpers")() ; puis H.boot(), H.join("Nom"), H.interact(p, "id")...
return function()
	local mock = require("./mock")
	local runtime = require("./runtime")(mock)
	local env = require("./bundle_out")(mock)
	local H = { mock = mock, runtime = runtime, env = env, failures = 0 }

	local S = "ServerScriptService/Server/"
	local R = "ReplicatedStorage/Shared/"
	function H.server(name)
		return env.require(S .. name)
	end
	function H.shared(name)
		return env.require(R .. name)
	end

	function H.check(label, cond, detail)
		if cond then
			print("  OK    " .. label)
		else
			H.failures += 1
			print("  ÉCHEC " .. label .. (if detail ~= nil then " — " .. tostring(detail) else ""))
		end
		return cond
	end

	local shownErrors = 0
	function H.noNewErrors(label)
		for i = shownErrors + 1, #runtime.errors do
			print("    [ERREUR] " .. runtime.errors[i]:sub(1, 1200))
		end
		local count = #runtime.errors - shownErrors
		shownErrors = #runtime.errors
		return H.check(label, count == 0, count .. " erreur(s)")
	end
	local shownWarnings = 0
	function H.printWarnings()
		for i = shownWarnings + 1, #runtime.warnings do
			print("    [warn] " .. runtime.warnings[i]:sub(1, 300))
		end
		shownWarnings = #runtime.warnings
	end

	function H.advance(seconds)
		runtime.advance(seconds)
	end

	-- Appelle `fn(...)` dans une coroutine (elle peut attendre le DataStore) et fait avancer le temps
	-- jusqu'à sa fin (30 s simulées au plus). Retourne ses résultats, ou nil si elle n'a pas fini.
	function H.call(fn, ...)
		local args = table.pack(...)
		local done, results = false, nil
		mock.task.spawn(function()
			results = table.pack(fn(table.unpack(args, 1, args.n)))
			done = true
		end)
		local waited = 0
		while not done and waited < 30 do
			runtime.advance(0.1)
			waited += 0.1
		end
		if not done or results == nil then
			return nil
		end
		return table.unpack(results, 1, results.n)
	end

	function H.party(player, action, params)
		return H.call(H.shared("Party/PartyRemotes").PartyRequest.OnServerInvoke, player, action, params or {})
	end
	function H.guild(player, action, params)
		return H.call(H.shared("Guild/GuildRemotes").GuildRequest.OnServerInvoke, player, action, params or {})
	end
	function H.mission(player, action, missionId)
		return H.call(H.shared("Mission/MissionRemotes").MissionRequest.OnServerInvoke, player, action, missionId)
	end

	function H.boot()
		mock.task.spawn(function()
			env.run(S .. "Main")
		end)
		runtime.runUntil(5)
	end

	-- Choix de création valide (index 1 partout, magie `magicIndex`, peuple et teint facultatifs).
	function H.selection(magicIndex, raceIndex, skinIndex)
		return {
			baseIndex = 1, faceIndex = 1, markIndex = 1, hairIndex = 1, outfitIndex = 1,
			heightScale = 1, widthScale = 1, magicIndex = magicIndex or 1,
			raceIndex = raceIndex or 1, skinIndex = skinIndex or 1, ornamentIndex = 1,
		}
	end

	-- Joueur qui rejoint, avec un personnage ; s'il est nouveau, il valide la création (ApplyAvatar).
	function H.join(name, userId, magicIndex)
		local player = runtime.addPlayer(name, userId)
		runtime.spawnCharacter(player)
		runtime.advance(3)
		if player:GetAttribute("IsCustomizing") == true then
			local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
			AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(player, H.selection(magicIndex))
			runtime.advance(4)
		end
		return player
	end

	function H.leave(player)
		mock.task.spawn(function()
			runtime.removePlayer(player)
		end)
		runtime.advance(4)
	end

	function H.root(player)
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end

	-- Place le personnage (position MONDE) ; regarde vers `lookAt` si donné.
	function H.teleport(player, position, lookAt)
		local root = H.root(player)
		if root then
			root.CFrame = if lookAt then mock.CFrame.lookAt(position, lookAt) else mock.CFrame.new(position)
		end
	end

	function H.anchorPosition(anchorId)
		local WorldAnchors = H.server("World/WorldAnchors")
		local cframe = WorldAnchors.getCFrame(anchorId)
		return cframe and cframe.Position
	end

	-- Déclenche le ProximityPrompt de l'interactable `id` après s'être approché à `distance` studs.
	function H.interact(player, id, distance)
		local WorldAnchors = H.server("World/WorldAnchors")
		local part = WorldAnchors.getInteractable(id)
		if part == nil then
			return false, "interactable introuvable : " .. id
		end
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return false, "aucun ProximityPrompt sur " .. id
		end
		local offset = mock.Vector3.new(distance or 3, 0, 0)
		H.teleport(player, part.Position + offset, part.Position)
		prompt.Triggered:Fire(player)
		runtime.advance(0.8)
		return true
	end

	function H.npc(npcId)
		local CollectionService = mock.game:GetService("CollectionService")
		for _, model in ipairs(CollectionService:GetTagged("Villager")) do
			if model:GetAttribute("NpcId") == npcId then
				return model
			end
		end
		return nil
	end

	-- Parle à un PNJ (GetDialogue) ; accepte la quête proposée si `acceptQuest` est donné.
	function H.talk(player, npcId, acceptQuest)
		local model = H.npc(npcId)
		if model == nil then
			return nil, "PNJ introuvable : " .. npcId
		end
		local npcRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		H.teleport(player, npcRoot.Position + mock.Vector3.new(3, 0, 0), npcRoot.Position)
		local DialogueRemotes = H.shared("NPC/DialogueRemotes")
		local data = H.call(DialogueRemotes.GetDialogue.OnServerInvoke, player, model)
		runtime.advance(0.8)
		if acceptQuest and data then
			local result = H.call(DialogueRemotes.ChooseOption.OnServerInvoke, player, model, "quest_accept:" .. acceptQuest)
			runtime.advance(0.8)
			return data, result
		end
		return data
	end

	function H.enemyAt(anchorId)
		local CollectionService = mock.game:GetService("CollectionService")
		for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
			if model:GetAttribute("SpawnAnchor") == anchorId and model.Parent ~= nil then
				return model
			end
		end
		return nil
	end

	-- Frappe un ennemi jusqu'à sa défaite (au plus `maxHits` coups), au nom de `player`.
	function H.defeat(player, model, maxHits)
		local DamageService = H.server("Combat/DamageService")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local hits = 0
		while humanoid and humanoid.Health > 0 and hits < (maxHits or 60) do
			hits += 1
			DamageService.dealDamage(model, 60, { player = player, model = player.Character, kind = "melee" })
			runtime.advance(0.4)
		end
		runtime.advance(1)
		return humanoid ~= nil and humanoid.Health <= 0, hits
	end

	function H.profile(player)
		return H.server("Data/ProfileStore").get(player)
	end

	function H.finish()
		print()
		print(if H.failures == 0 then "TOUT OK" else H.failures .. " ÉCHEC(S)")
	end

	return H
end
