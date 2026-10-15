--!strict
--[[
	Signal
	Événement en mémoire, pour que deux modules d'un même côté (serveur ↔ serveur, client ↔ client)
	se préviennent sans dépendre l'un de l'autre. Exemple : DamageService émet EnemyDefeated, que
	QuestService et MissionService écoutent sans que DamageService les connaisse.

	Chaque écouteur est appelé dans son propre thread (task.spawn) : un écouteur qui yield ou qui
	plante ne bloque ni l'émetteur ni les autres écouteurs.

		local onDefeated = Signal.new()
		local connection = onDefeated:Connect(function(enemy, enemyId) ... end)
		onDefeated:Fire(enemy, "ash_prowler")
		connection:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Listener = {
	callback: (...any) -> (),
	connection: Connection,
}

local Signal = {}
Signal.__index = Signal

type SignalData = {
	_listeners: { Listener },
}

export type Signal = typeof(setmetatable({} :: SignalData, Signal))

function Signal.new(): Signal
	local data: SignalData = { _listeners = {} }
	return setmetatable(data, Signal)
end

-- Abonne `callback`. Retourne une connexion à déconnecter quand on n'écoute plus.
function Signal.Connect(self: Signal, callback: (...any) -> ()): Connection
	local listeners = self._listeners
	local connection: Connection
	connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			for index, listener in listeners do
				if listener.connection == connection then
					table.remove(listeners, index)
					break
				end
			end
		end,
	}
	table.insert(listeners, { callback = callback, connection = connection })
	return connection
end

-- Comme Connect, mais l'écouteur se déconnecte de lui-même après le premier appel.
function Signal.Once(self: Signal, callback: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...: any)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

-- Prévient tous les écouteurs actuels. Ne yield jamais.
function Signal.Fire(self: Signal, ...: any)
	-- Copie : un écouteur peut se déconnecter (ou en connecter un autre) pendant la boucle.
	local snapshot = table.clone(self._listeners)
	for _, listener in snapshot do
		if listener.connection.Connected then
			task.spawn(listener.callback, ...)
		end
	end
end

-- Attend le prochain Fire et retourne ses arguments. YIELD.
function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...: any)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, listener in table.clone(self._listeners) do
		listener.connection:Disconnect()
	end
end

return Signal
