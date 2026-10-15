-- Extension "temps réel" de la simulation (outil de test, hors Roblox) :
--   - ordonnanceur virtuel : task.wait / spawn / defer / delay suspendent de vraies coroutines,
--     le temps n'avance que via runUntil() ;
--   - horloge virtuelle injectée aux modules (os.clock, os.time, workspace:GetServerTimeNow) ;
--   - services Roblox simulés : DataStoreService (en mémoire, partagé entre "serveurs"),
--     MessagingService, TextService, PathfindingService, TweenService, Debris, Players
--     (joueurs, personnages R15 simplifiés), RemoteEvent / RemoteFunction enregistrés.
-- Usage : local runtime = require("./runtime")(mock) ; puis runtime.runUntil(t).

return function(mock)
	local R = {}
	local now = 0
	local sleeping = {}
	local errors = {}
	R.errors = errors
	R.warnings = {}

	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(errors, tostring(err) .. "\n" .. debug.traceback(co))
		end
	end

	local task = {}
	function task.wait(t)
		t = t or 1 / 60
		local co = coroutine.running()
		table.insert(sleeping, { co = co, at = now + math.max(t, 1 / 60) })
		coroutine.yield()
		return t
	end
	function task.spawn(f, ...)
		if type(f) == "thread" then
			resume(f, ...)
			return f
		end
		local co = coroutine.create(f)
		resume(co, ...)
		return co
	end
	function task.defer(f, ...)
		local args = { ... }
		local co = coroutine.create(function()
			f(table.unpack(args))
		end)
		table.insert(sleeping, { co = co, at = now })
		return co
	end
	function task.delay(t, f, ...)
		local args = { ... }
		local co = coroutine.create(function()
			f(table.unpack(args))
		end)
		table.insert(sleeping, { co = co, at = now + (t or 0) })
		return co
	end
	function task.cancel(co)
		for i = #sleeping, 1, -1 do
			if sleeping[i].co == co then
				table.remove(sleeping, i)
			end
		end
	end
	mock.task = task

	function R.runUntil(t)
		local guard = 0
		while true do
			local bestI, best = nil, nil
			for i, s in ipairs(sleeping) do
				if best == nil or s.at < best.at then
					bestI, best = i, s
				end
			end
			if best == nil or best.at > t then
				break
			end
			table.remove(sleeping, bestI)
			now = math.max(now, best.at)
			if coroutine.status(best.co) == "suspended" then
				resume(best.co)
			end
			guard += 1
			if guard > 2000000 then
				error("runUntil : trop d'itérations (boucle sans attente ?)")
			end
		end
		now = math.max(now, t)
	end
	function R.now()
		return now
	end
	function R.advance(dt)
		R.runUntil(now + dt)
	end

	local BASE_TIME = 1792000000
	mock.os = {
		clock = function()
			return now
		end,
		time = function(t)
			if t then
				return os.time(t)
			end
			return BASE_TIME + math.floor(now)
		end,
		date = function(fmt, t)
			return os.date(fmt, t or (BASE_TIME + math.floor(now)))
		end,
		difftime = os.difftime,
	}
	mock.warn = function(...)
		local parts = {}
		for _, v in ipairs({ ... }) do
			table.insert(parts, tostring(v))
		end
		local line = table.concat(parts, " ")
		table.insert(R.warnings, line)
		if R.echoWarnings then
			print("[warn] " .. line)
		end
	end
	mock.print = function(...)
		if R.echoPrints then
			print(...)
		end
	end

	local game = mock.game
	local workspace = mock.workspace
	local Instance = mock.Instance

	-- Méthodes génériques ajoutées aux instances (accès via __index des instances mock).
	local Imt = getmetatable(Instance.new("Folder"))
	local baseIndex = Imt.__index
	local extra = {}
	Imt.__index = function(self, k)
		local cls = rawget(self, "ClassName")
		local fn = extra[cls .. "." .. k] or extra["*." .. k]
		if fn then
			return fn
		end
		return baseIndex(self, k)
	end

	-- Remotes : on enregistre les envois pour les vérifications.
	R.sent = {}
	local function record(remote, kind, ...)
		table.insert(R.sent, { remote = remote.Name, kind = kind, args = { ... } })
	end
	extra["RemoteEvent.FireClient"] = function(self, player, ...)
		record(self, "FireClient", player, ...)
	end
	extra["RemoteEvent.FireAllClients"] = function(self, ...)
		record(self, "FireAllClients", ...)
	end
	extra["RemoteEvent.FireServer"] = function() end
	extra["UnreliableRemoteEvent.FireClient"] = extra["RemoteEvent.FireClient"]
	extra["UnreliableRemoteEvent.FireAllClients"] = extra["RemoteEvent.FireAllClients"]
	extra["BindableEvent.Fire"] = function(self, ...)
		self.Event:Fire(...)
	end
	-- Signal attendu : Wait() suspend jusqu'au prochain Fire.
	-- Comme dans Roblox : chaque gestionnaire s'exécute dans son propre thread (il peut céder la main),
	-- Disconnect est respecté et Once se déconnecte après le premier appel.
	mock.newSignal = function()
		local s = { _connections = {} }
		local waiting = {}
		local function connect(self, fn, once)
			local conn = { Connected = true }
			function conn:Disconnect()
				self.Connected = false
			end
			table.insert(self._connections, { fn = fn, conn = conn, once = once })
			return conn
		end
		function s:Connect(fn)
			return connect(self, fn, false)
		end
		function s:Once(fn)
			return connect(self, fn, true)
		end
		function s:Fire(...)
			local list = table.clone(self._connections)
			for _, c in ipairs(list) do
				if c.conn.Connected then
					if c.once then
						c.conn.Connected = false
					end
					task.spawn(c.fn, ...)
				end
			end
			for i = #self._connections, 1, -1 do
				if not self._connections[i].conn.Connected then
					table.remove(self._connections, i)
				end
			end
			local list = waiting
			waiting = {}
			for _, co in ipairs(list) do
				task.spawn(co, ...)
			end
		end
		function s:Wait()
			table.insert(waiting, coroutine.running())
			return coroutine.yield()
		end
		return s
	end

	-- Humanoid
	extra["Humanoid.TakeDamage"] = function(self, amount)
		if self:FindFirstAncestorOfClass("Model") and self.Parent:FindFirstChildOfClass("ForceField") then
			return
		end
		self.Health = math.max(0, (self.Health or 100) - amount)
		if self.Health <= 0 and not rawget(self, "_died") then
			rawset(self, "_died", true)
			self.Died:Fire()
		end
	end
	extra["Humanoid.MoveTo"] = function(self, position)
		rawset(self, "_moveTarget", position)
	end
	extra["Humanoid.GetState"] = function(self)
		return if (self.Health or 100) <= 0 then mock.Enum.HumanoidStateType.Dead else mock.Enum.HumanoidStateType.Running
	end
	extra["Humanoid.ChangeState"] = function() end
	extra["Humanoid.SetStateEnabled"] = function() end
	extra["Humanoid.GetAppliedDescription"] = function()
		return Instance.new("HumanoidDescription")
	end
	extra["HumanoidDescription.SetAccessories"] = function(self, accessories)
		rawget(self, "_props")._accessories = accessories
	end
	extra["HumanoidDescription.GetAccessories"] = function(self)
		return rawget(self, "_props")._accessories or {}
	end
	-- Comme dans Roblox : reconstruit les articulations, dont le cou (Motor6D "Neck" dans la tête).
	extra["Humanoid.BuildRigFromAttachments"] = function(self)
		local character = self.Parent
		local head = character and character:FindFirstChild("Head")
		if head and head:FindFirstChild("Neck") == nil then
			local neck = Instance.new("Motor6D")
			neck.Name = "Neck"
			neck.Parent = head
		end
	end
	extra["Humanoid.ApplyDescription"] = function() end
	extra["Humanoid.ApplyDescriptionAsync"] = function() end
	-- Comme dans Roblox : la nouvelle pièce prend la place (et le nom) de l'ancienne dans le personnage.
	extra["Humanoid.ReplaceBodyPartR15"] = function(self, bodyPart, part)
		local character = self.Parent
		if character == nil or part == nil then
			return false
		end
		local name = tostring(bodyPart):match("([^%.]+)$") or "Head"
		local old = character:FindFirstChild(name)
		if old and old ~= part then
			old.Parent = nil
		end
		part.Name = name
		part.Parent = character
		return true
	end
	extra["Humanoid.LoadAnimation"] = function(self, animation)
		return mock.newTrack()
	end
	extra["Animator.LoadAnimation"] = extra["Humanoid.LoadAnimation"]
	extra["Animator.GetPlayingAnimationTracks"] = function()
		return {}
	end
	extra["Humanoid.GetPlayingAnimationTracks"] = extra["Animator.GetPlayingAnimationTracks"]
	function mock.newTrack()
		return {
			Play = function() end,
			Stop = function() end,
			AdjustSpeed = function() end,
			IsPlaying = false,
			Looped = false,
			Length = 1,
			Stopped = mock.newSignal(),
			GetMarkerReachedSignal = function()
				return mock.newSignal()
			end,
		}
	end
	extra["*.GetNetworkPing"] = function()
		return 0.08
	end
	extra["*.RequestStreamAroundAsync"] = function() end
	extra["*.Kick"] = function() end
	extra["*.HasAppearanceLoaded"] = function()
		return true
	end
	extra["*.LoadCharacter"] = function() end
	extra["*.GetServerTimeNow"] = function()
		return BASE_TIME + now
	end
	-- Raycast : désactivé par défaut (nil), comme avant. Avec R.realRaycast = true, rayon réel contre
	-- les Parts du Workspace (boîtes orientées, méthode des dalles) et, si R.terrainHeight(x, z) est
	-- fourni, contre la surface du terrain. Respecte FilterDescendantsInstances (Exclude / Include),
	-- RespectCanCollide et CanQuery.
	R.realRaycast = false
	R.terrainHeight = nil
	local function isInside(inst, list)
		for _, ancestor in ipairs(list or {}) do
			if inst == ancestor or inst:IsDescendantOf(ancestor) then
				return true
			end
		end
		return false
	end
	local function intersectBox(part, origin, direction)
		local cf = part.CFrame
		local inv = cf:Inverse()
		local o = inv * origin
		local d = inv:VectorToWorldSpace(direction)
		local half = part.Size / 2
		local tMin, tMax = 0, 1
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local oa, da, h = o[axis], d[axis], half[axis]
			if math.abs(da) < 1e-9 then
				if oa < -h or oa > h then
					return nil
				end
			else
				local t1, t2 = (-h - oa) / da, (h - oa) / da
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				tMin = math.max(tMin, t1)
				tMax = math.min(tMax, t2)
				if tMin > tMax then
					return nil
				end
			end
		end
		return tMin
	end
	extra["*.Raycast"] = function(self, origin, direction, raycastParams)
		if not R.realRaycast then
			return nil
		end
		local filter = raycastParams and raycastParams.FilterDescendantsInstances or {}
		local include = raycastParams and raycastParams.FilterType == mock.Enum.RaycastFilterType.Include
		local respect = raycastParams and raycastParams.RespectCanCollide == true
		local bestT, bestPart = math.huge, nil
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.CanQuery ~= false and (not respect or d.CanCollide ~= false) then
				local filtered = isInside(d, filter)
				if (include and filtered) or (not include and not filtered) then
					local t = intersectBox(d, origin, direction)
					if t and t < bestT then
						bestT, bestPart = t, d
					end
				end
			end
		end
		if R.terrainHeight and direction.Y < 0 and not include then
			local h = R.terrainHeight(origin.X, origin.Z)
			if h and origin.Y >= h then
				local t = (origin.Y - h) / -direction.Y
				if t <= 1 and t < bestT then
					bestT, bestPart = t, workspace:FindFirstChildOfClass("Terrain") or workspace
				end
			end
		end
		if bestPart == nil then
			return nil
		end
		return { Instance = bestPart, Position = origin + direction * bestT, Normal = mock.Vector3.new(0, 1, 0), Distance = direction.Magnitude * bestT, Material = mock.Enum.Material.Plastic }
	end
	extra["*.GetPartBoundsInBox"] = function()
		return {}
	end
	extra["*.GetPartBoundsInRadius"] = function()
		return {}
	end
	extra["*.GetPartsInPart"] = function()
		return {}
	end
	extra["*.CanSetNetworkOwnership"] = function()
		return true
	end
	extra["*.GetPlayerFromCharacter"] = function(self, character)
		for _, p in ipairs(self:GetChildren()) do
			if rawget(p, "ClassName") == "Player" and p.Character == character then
				return p
			end
		end
		return nil
	end
	extra["*.GetPlayers"] = function(self)
		local out = {}
		for _, p in ipairs(self:GetChildren()) do
			if rawget(p, "ClassName") == "Player" then
				table.insert(out, p)
			end
		end
		return out
	end
	extra["*.GetPlayerByUserId"] = function(self, userId)
		for _, p in ipairs(extra["*.GetPlayers"](self)) do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end

	-- Personnage R15 simplifié (RootPart, tête, mains, Humanoid, Animator).
	function R.newCharacter(name, cframe)
		local model = Instance.new("Model")
		model.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = mock.Vector3.new(2, 2, 1)
		root.CFrame = cframe or mock.CFrame.new(0, 3, 0)
		root.Parent = model
		-- Silhouette R15 simplifiée : HipHeight 2, pieds 3 studs sous le centre du RootPart.
		local offsets = {
			Head = mock.Vector3.new(0, 2.5, 0),
			UpperTorso = mock.Vector3.new(0, 0.6, 0),
			RightHand = mock.Vector3.new(1.5, -0.6, 0),
			LeftHand = mock.Vector3.new(-1.5, -0.6, 0),
			LeftFoot = mock.Vector3.new(-0.5, -2.5, 0),
			RightFoot = mock.Vector3.new(0.5, -2.5, 0),
		}
		for _, partName in ipairs({ "Head", "UpperTorso", "RightHand", "LeftHand", "LeftFoot", "RightFoot" }) do
			local p = Instance.new("Part")
			p.Name = partName
			p.Size = mock.Vector3.new(1, 1, 1)
			p.CFrame = root.CFrame * mock.CFrame.new(offsets[partName])
			p.Parent = model
			local att = Instance.new("Attachment")
			att.Name = partName == "RightHand" and "RightGripAttachment" or (partName .. "Attachment")
			att.Parent = p
		end
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.MaxHealth = 100
		humanoid.WalkSpeed = 16
		humanoid.HipHeight = 2
		humanoid.RigType = mock.Enum.HumanoidRigType.R15
		humanoid.RootPart = root
		humanoid.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
		model.PrimaryPart = root
		return model
	end

	-- Services
	local services = mock.services
	local Players = game:GetService("Players")
	rawget(Players, "_props").CreateHumanoidModelFromDescription = function(_, _description, _rigType)
		task.wait(0.1)
		return R.newCharacter("Rig")
	end
	rawget(Players, "_props").BanAsync = function() end

	-- DataStore en mémoire, partagé : R.cloud[storeName][key] = { value, userIds, metadata }
	R.cloud = {}
	R.dataStoreFailing = false
	local function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local c = {}
		for k, x in pairs(v) do
			c[deepCopy(k)] = deepCopy(x)
		end
		return setmetatable(c, getmetatable(v))
	end
	local function newStore(name)
		R.cloud[name] = R.cloud[name] or {}
		local data = R.cloud[name]
		local store = {}
		function store:UpdateAsync(key, fn)
			task.wait(0.05)
			if R.dataStoreFailing then
				error("502: panne simulée du DataStore")
			end
			local entry = data[key]
			local keyInfo = entry and {
				GetUserIds = function()
					return deepCopy(entry.userIds or {})
				end,
				GetMetadata = function()
					return deepCopy(entry.metadata or {})
				end,
			}
			local newValue, userIds, metadata = fn(deepCopy(entry and entry.value), keyInfo)
			if newValue == nil then
				return nil
			end
			data[key] = { value = deepCopy(newValue), userIds = userIds or {}, metadata = metadata or {} }
			return newValue
		end
		function store:GetAsync(key)
			task.wait(0.05)
			if R.dataStoreFailing then
				error("502: panne simulée du DataStore")
			end
			local entry = data[key]
			return deepCopy(entry and entry.value), nil
		end
		function store:SetAsync(key, value)
			task.wait(0.05)
			if R.dataStoreFailing then
				error("502: panne simulée du DataStore")
			end
			data[key] = { value = deepCopy(value), userIds = {}, metadata = {} }
		end
		function store:RemoveAsync(key)
			data[key] = nil
		end
		return store
	end
	local stores = {}
	services.DataStoreService = {
		GetDataStore = function(_, name, scope)
			local full = name .. (scope and (":" .. scope) or "")
			stores[full] = stores[full] or newStore(full)
			return stores[full]
		end,
		GetOrderedDataStore = function(_, name)
			return newStore("ordered:" .. name)
		end,
	}
	R.messages = {}
	local subscribers = {}
	services.MessagingService = {
		PublishAsync = function(_, topic, message)
			table.insert(R.messages, { topic = topic, message = message })
			for _, cb in ipairs(subscribers[topic] or {}) do
				task.defer(cb, { Data = message, Sent = now })
			end
		end,
		SubscribeAsync = function(_, topic, cb)
			subscribers[topic] = subscribers[topic] or {}
			table.insert(subscribers[topic], cb)
			return { Disconnect = function() end }
		end,
	}
	services.TextService = {
		FilterStringAsync = function(_, text)
			local filtered = if string.find(string.lower(text), "insulte") then string.rep("#", #text) else text
			return {
				GetNonChatStringForBroadcastAsync = function()
					return filtered
				end,
				GetNonChatStringForUserAsync = function()
					return filtered
				end,
			}
		end,
	}
	services.PathfindingService = {
		CreatePath = function()
			local path = { Status = mock.Enum.PathStatus.Success, _waypoints = {} }
			function path:ComputeAsync(from, to)
				task.wait(0.01)
				self._waypoints = {
					{ Position = from, Action = mock.Enum.PathWaypointAction.Walk },
					{ Position = to, Action = mock.Enum.PathWaypointAction.Walk },
				}
			end
			function path:GetWaypoints()
				return self._waypoints
			end
			path.Blocked = mock.newSignal()
			return path
		end,
	}
	services.TweenService = {
		Create = function()
			return { Play = function() end, Cancel = function() end, Completed = mock.newSignal() }
		end,
	}
	services.Debris = {
		AddItem = function(_, item, t)
			task.delay(t or 10, function()
				if item and item.Destroy then
					item:Destroy()
				end
			end)
		end,
	}
	services.ServerStorage = services.ServerStorage
	rawget(game, "_props").BindToClose = function(_, fn)
		R.closeCallbacks = R.closeCallbacks or {}
		table.insert(R.closeCallbacks, fn)
	end
	local RunService = game:GetService("RunService")
	RunService.IsStudio = function()
		return true
	end
	RunService.IsServer = function()
		return true
	end
	RunService.IsClient = function()
		return false
	end
	RunService.Heartbeat = mock.newSignal()
	RunService.Heartbeat.Wait = function()
		task.wait(1 / 30)
		return 1 / 30
	end
	-- Battement de cœur du moteur : Heartbeat est déclenché 30 fois par seconde de temps simulé
	-- (IA des ennemis, enregistrement des instantanés du Time-Loop, hitbox...).
	R.heartbeatRate = 1 / 30
	task.spawn(function()
		while true do
			local dt = task.wait(R.heartbeatRate)
			RunService.Heartbeat:Fire(dt)
		end
	end)
	-- Les modules attendent les vrais services via game:GetService : on les branche.
	local origGetService = game.GetService
	rawget(game, "_props").GetService = function(self, name)
		if services[name] then
			return services[name]
		end
		if name == "RunService" then
			return RunService
		end
		return origGetService(self, name)
	end

	-- Joueurs
	local nextUserId = 1000
	function R.addPlayer(name, userId)
		nextUserId += 1
		local player = Instance.new("Player")
		player.Name = name
		player.UserId = userId or nextUserId
		player.DisplayName = name
		player.Parent = Players
		Players.PlayerAdded:Fire(player)
		return player
	end
	function R.spawnCharacter(player, cframe)
		local character = R.newCharacter(player.Name, cframe)
		character.Parent = workspace
		player.Character = character
		player.CharacterAdded:Fire(character)
		player.CharacterAppearanceLoaded:Fire(character)
		return character
	end
	function R.removePlayer(player)
		Players.PlayerRemoving:Fire(player)
		if player.Character then
			player.CharacterRemoving:Fire(player.Character)
			player.Character:Destroy()
		end
		player.Parent = nil
	end
	-- Remotes envoyés à un joueur (filtre par nom).
	function R.sentTo(player, remoteName)
		local out = {}
		for _, s in ipairs(R.sent) do
			if s.remote == remoteName and (s.kind == "FireAllClients" or s.args[1] == player) then
				table.insert(out, s)
			end
		end
		return out
	end
	return R
end
