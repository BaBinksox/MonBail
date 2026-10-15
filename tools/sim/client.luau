-- Extension "client" de la simulation (outil de test, hors Roblox) : fait tourner les LocalScripts
-- du projet dans le même processus que le serveur, pour UN joueur local.
--   - Players.LocalPlayer, PlayerGui, workspace.CurrentCamera ;
--   - remotes : FireClient -> OnClientEvent (différé, comme le réseau), FireServer -> OnServerEvent,
--     InvokeServer -> OnServerInvoke ;
--   - services client : ContextActionService (C.pressKey), UserInputService, GuiService, StarterGui,
--     TextService:GetTextSize, TweenService (propriétés appliquées en fin de tween), RenderStepped.
-- Usage : local C = require("./client")(mock, runtime, player)
-- Limites : aucun rendu, aucune mise en page réelle (AbsoluteSize fixe), un seul client.

return function(mock, R, player)
	local C = {}
	local game = mock.game
	local workspace = mock.workspace
	local Instance = mock.Instance
	local task = mock.task
	local services = mock.services
	local Enum = mock.Enum

	-- Joueur local --------------------------------------------------------------------------
	local Players = game:GetService("Players")
	rawget(Players, "_props").LocalPlayer = player
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	local playerScripts = Instance.new("PlayerScripts")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = player
	C.playerGui = playerGui

	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	camera.CFrame = mock.CFrame.new(0, 20, 20)
	camera.Focus = mock.CFrame.new(0, 0, 0)
	camera.FieldOfView = 70
	camera.ViewportSize = mock.Vector2.new(1920, 1080)
	camera.CameraType = Enum.CameraType.Custom
	camera.Parent = workspace
	rawget(workspace, "_props").CurrentCamera = camera
	C.camera = camera

	-- Remotes -------------------------------------------------------------------------------
	local Imt = getmetatable(Instance.new("Folder"))
	local baseIndex = Imt.__index
	local clientExtra = {}
	Imt.__index = function(self, k)
		local cls = rawget(self, "ClassName")
		local fn = clientExtra[cls .. "." .. k]
		if fn then
			return fn
		end
		return baseIndex(self, k)
	end
	local function record(remote, kind, ...)
		table.insert(R.sent, { remote = remote.Name, kind = kind, args = { ... } })
	end
	C.received = {}
	local function toClient(remote, kind, target, ...)
		if target ~= nil and target ~= player then
			return
		end
		local args = table.pack(...)
		task.defer(function()
			table.insert(C.received, { remote = remote.Name, args = args })
			remote.OnClientEvent:Fire(table.unpack(args, 1, args.n))
		end)
	end
	clientExtra["RemoteEvent.FireClient"] = function(self, target, ...)
		record(self, "FireClient", target, ...)
		toClient(self, "FireClient", target, ...)
	end
	clientExtra["RemoteEvent.FireAllClients"] = function(self, ...)
		record(self, "FireAllClients", ...)
		toClient(self, "FireAllClients", nil, ...)
	end
	clientExtra["RemoteEvent.FireServer"] = function(self, ...)
		record(self, "FireServer", ...)
		local args = table.pack(...)
		task.defer(function()
			self.OnServerEvent:Fire(player, table.unpack(args, 1, args.n))
		end)
	end
	clientExtra["UnreliableRemoteEvent.FireClient"] = clientExtra["RemoteEvent.FireClient"]
	clientExtra["UnreliableRemoteEvent.FireAllClients"] = clientExtra["RemoteEvent.FireAllClients"]
	clientExtra["UnreliableRemoteEvent.FireServer"] = clientExtra["RemoteEvent.FireServer"]
	clientExtra["Sound.Play"] = function(self)
		local props = rawget(self, "_props")
		props.Playing = true
		props.IsPlaying = true
		props.PlayCount = (props.PlayCount or 0) + 1
	end
	clientExtra["Sound.Stop"] = function(self)
		local props = rawget(self, "_props")
		props.Playing = false
		props.IsPlaying = false
	end
	clientExtra["Sound.Pause"] = clientExtra["Sound.Stop"]
	clientExtra["Sound.Resume"] = clientExtra["Sound.Play"]
	clientExtra["ParticleEmitter.Emit"] = function() end
	clientExtra["ParticleEmitter.Clear"] = function() end
	for _, cls in ipairs({ "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ScrollingFrame", "TextBox", "CanvasGroup" }) do
		clientExtra[cls .. ".TweenPosition"] = function() return true end
		clientExtra[cls .. ".TweenSize"] = function() return true end
		clientExtra[cls .. ".TweenSizeAndPosition"] = function() return true end
	end
	clientExtra["TextBox.CaptureFocus"] = function() end
	clientExtra["TextBox.ReleaseFocus"] = function() end
	clientExtra["TextBox.IsFocused"] = function() return false end
	clientExtra["Camera.WorldToViewportPoint"] = function(_, p) return mock.Vector3.new(960, 540, 10), true end
	clientExtra["Camera.WorldToScreenPoint"] = clientExtra["Camera.WorldToViewportPoint"]
	clientExtra["Camera.ViewportPointToRay"] = function(self) return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector } end
	clientExtra["Camera.ScreenPointToRay"] = clientExtra["Camera.ViewportPointToRay"]
	clientExtra["Camera.GetPartsObscuringTarget"] = function() return {} end
	clientExtra["RemoteFunction.InvokeServer"] = function(self, ...)
		task.wait(0.03)
		local handler = rawget(self, "_props").OnServerInvoke
		if handler == nil then
			error("InvokeServer : aucun OnServerInvoke sur " .. tostring(self.Name))
		end
		return handler(player, ...)
	end

	-- RunService ----------------------------------------------------------------------------
	local RunService = game:GetService("RunService")
	RunService.IsClient = function()
		return true
	end
	local function frameSignal()
		local s = mock.newSignal()
		s.Wait = function()
			task.wait(1 / 60)
			return 1 / 60
		end
		return s
	end
	RunService.RenderStepped = frameSignal()
	RunService.Stepped = frameSignal()
	RunService.BindToRenderStep = function() end
	RunService.UnbindFromRenderStep = function() end
	-- Les boucles par image ne tournent pas d'elles-mêmes : C.frames(n) les fait avancer.
	function C.frames(count)
		for _ = 1, count do
			R.advance(1 / 60)
			RunService.RenderStepped:Fire(1 / 60)
			RunService.Heartbeat:Fire(1 / 60)
		end
	end

	-- ContextActionService ------------------------------------------------------------------
	local actions = {}
	C.actions = actions
	local function bind(_, name, fn, _createButton, ...)
		local keys = { ... }
		actions[name] = { fn = fn, keys = keys }
	end
	services.ContextActionService = {
		BindAction = bind,
		BindActionAtPriority = function(self, name, fn, createButton, _priority, ...)
			bind(self, name, fn, createButton, ...)
		end,
		UnbindAction = function(_, name)
			actions[name] = nil
		end,
		SetTitle = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		SetDescription = function() end,
		GetButton = function() return nil end,
	}
	-- Appuie sur une touche : chaque action liée à cette touche reçoit Begin puis End.
	function C.pressKey(keyCode)
		local handled = false
		for name, action in pairs(actions) do
			for _, key in ipairs(action.keys) do
				if key == keyCode then
					handled = true
					local input = { KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard, Position = mock.Vector3.new(0, 0, 0), Delta = mock.Vector3.new(0, 0, 0) }
					task.spawn(action.fn, name, Enum.UserInputState.Begin, input)
					task.spawn(action.fn, name, Enum.UserInputState.End, input)
				end
			end
		end
		return handled
	end

	-- UserInputService / GuiService / StarterGui --------------------------------------------
	services.UserInputService = {
		InputBegan = mock.newSignal(),
		InputChanged = mock.newSignal(),
		InputEnded = mock.newSignal(),
		LastInputTypeChanged = mock.newSignal(),
		GamepadConnected = mock.newSignal(),
		GamepadDisconnected = mock.newSignal(),
		TouchStarted = mock.newSignal(),
		TouchEnded = mock.newSignal(),
		TouchMoved = mock.newSignal(),
		TouchPinch = mock.newSignal(),
		JumpRequest = mock.newSignal(),
		WindowFocused = mock.newSignal(),
		WindowFocusReleased = mock.newSignal(),
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
		MouseBehavior = Enum.MouseBehavior.Default,
		MouseIconEnabled = true,
		IsKeyDown = function() return false end,
		IsMouseButtonPressed = function() return false end,
		IsGamepadButtonDown = function() return false end,
		GetLastInputType = function() return Enum.UserInputType.MouseMovement end,
		GetMouseLocation = function() return mock.Vector2.new(960, 540) end,
		GetMouseDelta = function() return mock.Vector2.new(0, 0) end,
		GetConnectedGamepads = function() return {} end,
		GetNavigationGamepads = function() return {} end,
		GetGamepadConnected = function() return false end,
		GetKeysPressed = function() return {} end,
		GetStringForKeyCode = function(_, keyCode)
			local name = tostring(keyCode)
			return name:match("([^%.]+)$") or name
		end,
		GetFocusedTextBox = function() return nil end,
	}
	services.GuiService = {
		SelectedObject = nil,
		MenuOpened = mock.newSignal(),
		MenuClosed = mock.newSignal(),
		GuiNavigationEnabled = true,
		AutoSelectGuiEnabled = true,
		GetGuiInset = function() return mock.Vector2.new(0, 58), mock.Vector2.new(0, 0) end,
		IsTenFootInterface = function() return false end,
		Select = function() end,
	}
	services.StarterGui = {
		SetCoreGuiEnabled = function() end,
		GetCoreGuiEnabled = function() return true end,
		SetCore = function() end,
		GetCore = function() return nil end,
	}
	services.SoundService = services.SoundService or game:GetService("SoundService")

	-- TextService : taille approximative du texte (aucune police réelle).
	local textService = services.TextService or {}
	textService.GetTextSize = function(_, text, size, _font, _frame)
		return mock.Vector2.new(#tostring(text) * size * 0.5, size)
	end
	textService.GetTextBoundsAsync = function(_, params)
		local size = params and params.Size or 18
		local text = params and params.Text or ""
		return mock.Vector2.new(#tostring(text) * size * 0.5, size)
	end
	services.TextService = textService

	-- TweenService : propriétés appliquées à la fin du tween, Completed déclenché.
	services.TweenService = {
		Create = function(_, instance, info, goal)
			local duration = 0
			if type(info) == "table" and info.args then
				duration = tonumber(info.args[1]) or 0
			end
			local tween = { Completed = mock.newSignal(), PlaybackState = Enum.PlaybackState.Begin }
			local cancelled = false
			function tween:Play()
				cancelled = false
				task.delay(duration, function()
					if cancelled then
						return
					end
					for k, v in pairs(goal) do
						instance[k] = v
					end
					tween.PlaybackState = Enum.PlaybackState.Completed
					tween.Completed:Fire(Enum.PlaybackState.Completed)
				end)
			end
			function tween:Cancel()
				cancelled = true
				tween.PlaybackState = Enum.PlaybackState.Cancelled
			end
			function tween:Pause()
				cancelled = true
			end
			function tween:Destroy() end
			return tween
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
	}

	-- Recherche d'éléments d'interface -------------------------------------------------------
	local function descendants(root, out)
		for _, child in ipairs(root:GetChildren()) do
			table.insert(out, child)
			descendants(child, out)
		end
		return out
	end
	C.descendants = function(root)
		return descendants(root or playerGui, {})
	end
	-- Premier élément dont le texte contient `pattern` (recherche simple, sans motif Lua).
	function C.findText(pattern, root)
		for _, d in ipairs(descendants(root or playerGui, {})) do
			local text = rawget(d, "_props").Text
			if type(text) == "string" and string.find(text, pattern, 1, true) then
				return d
			end
		end
		return nil
	end
	-- Bouton (GuiButton) qui contient ou porte le texte `pattern`.
	function C.findButton(pattern, root)
		local node = C.findText(pattern, root)
		while node do
			local cls = rawget(node, "ClassName")
			if cls == "TextButton" or cls == "ImageButton" then
				return node
			end
			node = rawget(node, "_props").Parent
		end
		return nil
	end
	function C.click(button)
		button.Activated:Fire()
		button.MouseButton1Click:Fire()
	end

	return C
end
