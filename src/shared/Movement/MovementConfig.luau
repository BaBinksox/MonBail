--!strict
--[[
	MovementConfig
	Constantes partagées (serveur + client) de la mobilité : pour l'instant, le dash.
]]

return table.freeze({
	-- Attention : Shift gauche est aussi la touche du "Shift Lock" de Roblox. Pour qu'elle ne
	-- serve qu'au dash, décocher StarterPlayer > EnableMouseLockOption dans Studio.
	DASH_INPUT = Enum.KeyCode.LeftShift,

	DASH_SPEED = 85, -- studs/s pendant le dash
	DASH_DURATION = 0.18, -- secondes de propulsion (85 x 0.18 = environ 15 studs)
	DASH_COOLDOWN = 2, -- secondes entre deux dashs

	-- Après un dash accepté par le serveur, le joueur ne peut pas être blessé pendant cette durée
	-- (un peu plus longue que le dash, pour absorber la latence) : c'est ce qui en fait une esquive.
	DASH_INVULNERABILITY = 0.3,

	LATENCY_TOLERANCE = 0.25, -- marge (s) du serveur sur le contrôle du cooldown
	DEBUG_LOGS = true,
})
