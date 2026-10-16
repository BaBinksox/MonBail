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
	Tactile : boutons créés par ContextActionService autour du bouton de saut (positions ci-dessous).
]]

export type Binding = {
	keyCode: Enum.KeyCode?,
	letter: string?,
	fallbackKeyCode: Enum.KeyCode, -- si la disposition du clavier est illisible
	mouse: Enum.UserInputType?, -- bouton de souris (attaque)
	gamepad: Enum.KeyCode?,
	touch: UDim2?, -- position du bouton tactile (nil = pas de bouton)
	label: string, -- nom de l'action affiché à l'écran
}

local BINDINGS: { [string]: Binding } = {
	Attack = {
		mouse = Enum.UserInputType.MouseButton1,
		fallbackKeyCode = Enum.KeyCode.ButtonR2, -- pas de touche clavier : clic gauche
		gamepad = Enum.KeyCode.ButtonR2,
		touch = UDim2.new(1, -95, 1, -205),
		label = "Attaque",
	},
	Sprint = {
		keyCode = Enum.KeyCode.LeftShift,
		fallbackKeyCode = Enum.KeyCode.LeftShift,
		gamepad = Enum.KeyCode.ButtonL3, -- bascule (on n'appuie pas un stick en continu)
		touch = UDim2.new(1, -245, 1, -95),
		label = "Sprint",
	},
	Dash = {
		keyCode = Enum.KeyCode.C,
		fallbackKeyCode = Enum.KeyCode.C,
		gamepad = Enum.KeyCode.ButtonB,
		touch = UDim2.new(1, -245, 1, -165),
		label = "Esquive",
	},
	Parry = {
		keyCode = Enum.KeyCode.Q,
		fallbackKeyCode = Enum.KeyCode.Q,
		gamepad = Enum.KeyCode.ButtonL1,
		label = "Parade",
	},
	SpellBase = {
		keyCode = Enum.KeyCode.One,
		fallbackKeyCode = Enum.KeyCode.One,
		gamepad = Enum.KeyCode.ButtonR1,
		touch = UDim2.new(1, -170, 1, -285),
		label = "Sort",
	},
	SpellSecondary = {
		keyCode = Enum.KeyCode.Two,
		fallbackKeyCode = Enum.KeyCode.Two,
		gamepad = Enum.KeyCode.ButtonL2,
		touch = UDim2.new(1, -95, 1, -285),
		label = "Sort II",
	},
	Concentrate = {
		keyCode = Enum.KeyCode.G,
		fallbackKeyCode = Enum.KeyCode.G,
		gamepad = Enum.KeyCode.DPadRight,
		touch = UDim2.new(1, -320, 1, -95),
		label = "Concentration",
	},
	Ultimate = {
		keyCode = Enum.KeyCode.E,
		fallbackKeyCode = Enum.KeyCode.E,
		gamepad = Enum.KeyCode.ButtonY,
		touch = UDim2.new(1, -320, 1, -165),
		label = "Ultime",
	},
	Rewind = {
		keyCode = Enum.KeyCode.R,
		fallbackKeyCode = Enum.KeyCode.R,
		gamepad = Enum.KeyCode.DPadDown,
		label = "Rembobiner",
	},
	Grimoire = {
		letter = "J",
		fallbackKeyCode = Enum.KeyCode.J,
		-- Pas ButtonSelect : Roblox l'utilise déjà pour la navigation des interfaces à la manette.
		gamepad = Enum.KeyCode.DPadUp,
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
	-- Touche des ProximityPrompts des objets du monde (identique à celle des villageois).
	PROMPT_KEY = Enum.KeyCode.F,
	PROMPT_GAMEPAD_KEY = Enum.KeyCode.ButtonX,
})
