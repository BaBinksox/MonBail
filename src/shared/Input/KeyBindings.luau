--!strict
--[[
	KeyBindings
	Table centrale des touches des NOUVEAUX systèmes (les systèmes existants gardent les leurs :
	CombatConfig, TimeLoopConfig, MovementConfig, DialogueConfig, WorldMapConfig).

	Deux façons de désigner une touche clavier :
		- `keyCode` : un EMPLACEMENT physique (Enum.KeyCode). À utiliser près du bloc de déplacement
		  (ZQSD en AZERTY = WASD en QWERTY) : la parade est l'emplacement de Q en QWERTY, c'est-à-dire
		  la touche marquée "A" sur un clavier français. L'interface affiche le vrai libellé avec
		  UserInputService:GetStringForKeyCode.
		- `letter` : une LETTRE imprimée (résolue par Shared/Input/KeyboardLayout), pour les raccourcis
		  "mnémotechniques" éloignés du bloc de déplacement (J = Journal).

	Rappel des touches déjà prises : clic gauche (attaque), E (ultime), R (rembobinage),
	Maj gauche (dash), lettre M (carte), F (parler / interagir).
]]

export type Binding = {
	keyCode: Enum.KeyCode?,
	letter: string?,
	fallbackKeyCode: Enum.KeyCode, -- si la disposition du clavier est illisible
	gamepad: Enum.KeyCode?,
	label: string, -- nom de l'action affiché à l'écran
}

local BINDINGS: { [string]: Binding } = {
	Parry = {
		keyCode = Enum.KeyCode.Q,
		fallbackKeyCode = Enum.KeyCode.Q,
		gamepad = Enum.KeyCode.ButtonL1,
		label = "Parade",
	},
	Grimoire = {
		letter = "J",
		fallbackKeyCode = Enum.KeyCode.J,
		gamepad = Enum.KeyCode.ButtonSelect,
		label = "Grimoire",
	},
	Interact = {
		keyCode = Enum.KeyCode.F,
		fallbackKeyCode = Enum.KeyCode.F,
		gamepad = Enum.KeyCode.ButtonX,
		label = "Interagir",
	},
}

return table.freeze({
	BINDINGS = BINDINGS,
	-- Touche des ProximityPrompts des objets du monde (identique à celle des villageois).
	PROMPT_KEY = Enum.KeyCode.F,
	PROMPT_GAMEPAD_KEY = Enum.KeyCode.ButtonX,
})
