--!strict
--[[
	KeyBindings
	Table CENTRALE des commandes du jeu (clavier, manette, tactile). Tous les contrôleurs lisent ici :
	une touche ne peut donc pas être attribuée deux fois sans que cela se voie dans ce fichier.

	Deux façons de désigner une touche clavier :
		- `keyCode` : un EMPLACEMENT physique (Enum.KeyCode). À utiliser près du bloc de déplacement
		  (ZQSD en AZERTY = WASD en QWERTY) : la parade est l'emplacement de Q en QWERTY, c'est-à-dire
		  la touche marquée "A" sur un clavier français. L'interface affiche le vrai libellé avec
		  UserInputService:GetStringForKeyCode.
		- `letter` : une LETTRE imprimée (résolue par Shared/Input/KeyboardLayout), pour les raccourcis
		  "mnémotechniques" éloignés du bloc de déplacement (J = Journal).
	Les chiffres (sorts) sont des emplacements physiques : la touche "1" d'un clavier QWERTY est la
	touche "&" d'un clavier AZERTY, au même endroit.

	CHANGEMENT DE COMMANDES (Combat 2.0) :
		Maj gauche : ancien dash -> SPRINT maintenu. Le dash passe sur C, ou un double appui sur une
		touche de direction. (Décocher StarterPlayer > EnableMouseLockOption dans Studio, sinon Maj
		active aussi le « Shift Lock » de Roblox.)

	Récapitulatif clavier / souris :
		clic gauche        attaque (maintenu : attaque chargée)
		Maj maintenu       sprint                 Espace (en l'air)  double saut
		C / double appui   dash                   A (Q en QWERTY)     parade
		1                  sort de base           2                   sort secondaire
		G maintenu         Concentration          E                   technique ultime
		R                  rembobinage            F                   parler / interagir
		J                  Grimoire               M                   carte
	Manette : R2 attaque (maintenue : chargée), L1 parade, R1 sort de base, L2 sort secondaire,
	Y ultime, B dash, L3 sprint (bascule), A saut / double saut, X interagir, croix haut Grimoire,
	croix bas rembobinage, croix droite Concentration (maintenue).
	Tactile : boutons créés par ContextActionService en arc autour du bouton de saut de Roblox, à
	droite de l'écran (le stick reste libre à gauche, le centre de l'action reste dégagé). Deux
	dispositions : `touch` pour les grands écrans (bouton de saut de 120 px), `touchCompact` pour
	les téléphones (plus petit côté ≤ 500 px, bouton de saut de 70 px). Client/Input/TouchLayout
	choisit la bonne et la réapplique quand l'écran tourne. Le bouton « Rembobiner » n'apparaît que
	pendant une anomalie temporelle. À vérifier dans l'émulateur d'appareils de Studio.
]]

export type Binding = {
	keyCode: Enum.KeyCode?,
	letter: string?,
	fallbackKeyCode: Enum.KeyCode, -- si la disposition du clavier est illisible
	mouse: Enum.UserInputType?, -- bouton de souris (attaque)
	gamepad: Enum.KeyCode?,
	touch: UDim2?, -- position du bouton tactile, grand écran (nil = pas de bouton)
	touchCompact: UDim2?, -- position sur téléphone (plus petit côté ≤ 500 px)
	label: string, -- nom de l'action affiché à l'écran
}

local BINDINGS: { [string]: Binding } = {
	Attack = {
		mouse = Enum.UserInputType.MouseButton1,
		fallbackKeyCode = Enum.KeyCode.ButtonR2, -- pas de touche clavier : clic gauche
		gamepad = Enum.KeyCode.ButtonR2,
		touch = UDim2.new(1, -145, 1, -235),
		touchCompact = UDim2.new(1, -90, 1, -160),
		label = "Attaque",
	},
	Sprint = {
		keyCode = Enum.KeyCode.LeftShift,
		fallbackKeyCode = Enum.KeyCode.LeftShift,
		gamepad = Enum.KeyCode.ButtonL3, -- bascule (on n'appuie pas un stick en continu)
		touch = UDim2.new(1, -255, 1, -50),
		touchCompact = UDim2.new(1, -220, 1, -60),
		label = "Sprint",
	},
	Dash = {
		keyCode = Enum.KeyCode.C,
		fallbackKeyCode = Enum.KeyCode.C,
		gamepad = Enum.KeyCode.ButtonB,
		touch = UDim2.new(1, -255, 1, -125),
		touchCompact = UDim2.new(1, -160, 1, -70),
		label = "Esquive",
	},
	Parry = {
		keyCode = Enum.KeyCode.Q,
		fallbackKeyCode = Enum.KeyCode.Q,
		gamepad = Enum.KeyCode.ButtonL1,
		touch = UDim2.new(1, -240, 1, -205),
		touchCompact = UDim2.new(1, -160, 1, -130),
		label = "Parade",
	},
	SpellBase = {
		keyCode = Enum.KeyCode.One,
		fallbackKeyCode = Enum.KeyCode.One,
		gamepad = Enum.KeyCode.ButtonR1,
		touch = UDim2.new(1, -225, 1, -290),
		touchCompact = UDim2.new(1, -150, 1, -195),
		label = "Sort",
	},
	SpellSecondary = {
		keyCode = Enum.KeyCode.Two,
		fallbackKeyCode = Enum.KeyCode.Two,
		gamepad = Enum.KeyCode.ButtonL2,
		touch = UDim2.new(1, -145, 1, -315),
		touchCompact = UDim2.new(1, -90, 1, -225),
		label = "Sort II",
	},
	Concentrate = {
		keyCode = Enum.KeyCode.G,
		fallbackKeyCode = Enum.KeyCode.G,
		gamepad = Enum.KeyCode.DPadRight,
		touch = UDim2.new(1, -335, 1, -125),
		touchCompact = UDim2.new(1, -222, 1, -122),
		label = "Concentration",
	},
	Ultimate = {
		keyCode = Enum.KeyCode.E,
		fallbackKeyCode = Enum.KeyCode.E,
		gamepad = Enum.KeyCode.ButtonY,
		touch = UDim2.new(1, -305, 1, -275),
		touchCompact = UDim2.new(1, -228, 1, -188),
		label = "Ultime",
	},
	Rewind = {
		keyCode = Enum.KeyCode.R,
		fallbackKeyCode = Enum.KeyCode.R,
		gamepad = Enum.KeyCode.DPadDown,
		touch = UDim2.new(0.5, -45, 1, -230), -- pendant une anomalie seulement (joueur figé)
		touchCompact = UDim2.new(0.5, -35, 1, -170),
		label = "Rembobiner",
	},
	Grimoire = {
		letter = "J",
		fallbackKeyCode = Enum.KeyCode.J,
		-- Pas ButtonSelect : Roblox l'utilise déjà pour la navigation des interfaces à la manette.
		gamepad = Enum.KeyCode.DPadUp,
		touch = UDim2.new(1, -90, 0, 70), -- en haut à droite, loin des boutons de combat
		touchCompact = UDim2.new(1, -70, 0, 56),
		label = "Grimoire",
	},
	Interact = {
		keyCode = Enum.KeyCode.F,
		fallbackKeyCode = Enum.KeyCode.F,
		gamepad = Enum.KeyCode.ButtonX,
		label = "Interagir",
	},
}

-- Touches de direction pour le dash au double appui (emplacements physiques : ZQSD = WASD).
local DIRECTION_KEYS: { [Enum.KeyCode]: Vector3 } = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}

-- Boutons tactiles qui se chevauchent, par disposition (taille de bouton supposée, en px), ou qui
-- empiètent sur le bouton de saut de Roblox.
local JUMP_AREAS = {
	touch = { x0 = -170, x1 = -50, y0 = -140, y1 = -20 }, -- bouton de saut de 120 px
	touchCompact = { x0 = -95, x1 = -25, y0 = -90, y1 = -20 }, -- bouton de saut de 70 px
}
local function findTouchOverlaps(sizeLarge: number, sizeCompact: number): { string }
	local overlaps = {}
	for _, field in { "touch", "touchCompact" } do
		local size = if field == "touch" then sizeLarge else sizeCompact
		local jump = JUMP_AREAS[field]
		local placed: { { name: string, x: number, y: number } } = {}
		for name, binding in BINDINGS do
			local position: UDim2? = (binding :: any)[field]
			if position and position.X.Scale == 1 and position.Y.Scale == 1 then
				for _, other in placed do
					if math.abs(other.x - position.X.Offset) < size and math.abs(other.y - position.Y.Offset) < size then
						table.insert(overlaps, `{field} : {name} / {other.name}`)
					end
				end
				local x0, y0 = position.X.Offset, position.Y.Offset
				if x0 < jump.x1 and x0 + size > jump.x0 and y0 < jump.y1 and y0 + size > jump.y0 then
					table.insert(overlaps, `{field} : {name} / bouton de saut`)
				end
				table.insert(placed, { name = name, x = position.X.Offset, y = position.Y.Offset })
			end
		end
	end
	return overlaps
end

-- Vérifie qu'aucune touche clavier ni bouton de manette n'est attribué à deux actions.
local function findConflicts(): { string }
	local conflicts = {}
	local keyboard: { [any]: string } = {}
	local pad: { [any]: string } = {}
	for name, binding in BINDINGS do
		local key = binding.keyCode or binding.letter
		if key ~= nil then
			if keyboard[key] then
				table.insert(conflicts, `{name} / {keyboard[key]}`)
			end
			keyboard[key] = name
		end
		if binding.gamepad then
			if pad[binding.gamepad] then
				table.insert(conflicts, `{name} / {pad[binding.gamepad]} (manette)`)
			end
			pad[binding.gamepad] = name
		end
	end
	return conflicts
end

return table.freeze({
	BINDINGS = BINDINGS,
	DIRECTION_KEYS = DIRECTION_KEYS,
	findConflicts = findConflicts,
	findTouchOverlaps = findTouchOverlaps,
	-- Touche des ProximityPrompts des objets du monde (identique à celle des villageois).
	PROMPT_KEY = Enum.KeyCode.F,
	PROMPT_GAMEPAD_KEY = Enum.KeyCode.ButtonX,
})
