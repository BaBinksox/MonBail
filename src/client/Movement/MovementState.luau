--!strict
--[[
	MovementState (ModuleScript, client)
	État de mobilité du personnage LOCAL, écrit par MovementController et lu par les autres scripts
	client (poses de l'AnimationDirector, effets, interface). Aucune logique ici.
]]

export type State = {
	sprintRamp: number, -- 0 = course, 1 = sprint maximal
	wantsSprint: boolean,
	airborne: boolean,
	verticalSpeed: number,
	speed: number, -- vitesse horizontale (studs/s)
	jumpsUsed: number,
	concentrating: boolean,
}

local state: State = {
	sprintRamp = 0,
	wantsSprint = false,
	airborne = false,
	verticalSpeed = 0,
	speed = 0,
	jumpsUsed = 0,
	concentrating = false,
}

return state
