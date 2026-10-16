--!strict
--[[
	MovementModel
	Règles PURES de la mobilité (aucune instance, aucun service) : partagées par le client, qui les
	joue, le serveur, qui les vérifie, et les tests, qui les mesurent.

	API :
		MovementModel.stepSprint(ramp, dt, wantsSprint, isMoving): number   montée / descente (0..1)
		MovementModel.sprintFactor(ramp): number                            multiplicateur de vitesse
		MovementModel.canDoubleJump(state): boolean
		MovementModel.jumpReach(horizontalSpeed, landingHeight?, withDoubleJump?): (number, number)
		    distance horizontale franchie et hauteur maximale atteinte (studs)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Movement"):WaitForChild("MovementConfig") :: ModuleScript)

export type AirState = {
	isAirborne: boolean,
	airTime: number, -- s depuis la sortie du sol
	jumpsUsed: number, -- sauts supplémentaires déjà faits pendant ce passage en l'air
}

local GRAVITY = 196.2 -- workspace.Gravity par défaut
local DEFAULT_JUMP_HEIGHT = 7.2 -- Humanoid.JumpHeight par défaut

local MovementModel = {}

MovementModel.GRAVITY = GRAVITY
MovementModel.DEFAULT_JUMP_HEIGHT = DEFAULT_JUMP_HEIGHT

-- Avance la montée en sprint : accélération progressive, décélération plus rapide au relâchement.
function MovementModel.stepSprint(ramp: number, dt: number, wantsSprint: boolean, isMoving: boolean): number
	if wantsSprint and isMoving then
		return math.min(1, ramp + dt / Config.SPRINT_ACCELERATION_TIME)
	end
	return math.max(0, ramp - dt / Config.SPRINT_DECELERATION_TIME)
end

-- Courbe adoucie : le gain de vitesse est fort au début puis se stabilise (sensation d'élan).
function MovementModel.sprintFactor(ramp: number): number
	local t = math.clamp(ramp, 0, 1)
	local eased = 1 - (1 - t) * (1 - t)
	return 1 + (Config.SPRINT_MULTIPLIER - 1) * eased
end

function MovementModel.canDoubleJump(state: AirState): boolean
	return state.isAirborne and state.airTime >= Config.DOUBLE_JUMP_MIN_AIR_TIME and state.jumpsUsed < Config.DOUBLE_JUMP_COUNT
end

--[[
	Portée d'un saut lancé à `horizontalSpeed` studs/s, atterrissant `landingHeight` studs plus haut
	(négatif = plus bas). Le double saut est déclenché au sommet du premier, le cas le plus favorable.
	Retourne (distance horizontale, hauteur maximale).
]]
function MovementModel.jumpReach(horizontalSpeed: number, landingHeight: number?, withDoubleJump: boolean?): (number, number)
	local landing = landingHeight or 0
	local firstVelocity = math.sqrt(2 * GRAVITY * DEFAULT_JUMP_HEIGHT)
	local riseTime = firstVelocity / GRAVITY
	local apex = DEFAULT_JUMP_HEIGHT
	if withDoubleJump ~= false then
		local secondVelocity = Config.DOUBLE_JUMP_VELOCITY
		riseTime += secondVelocity / GRAVITY
		apex += secondVelocity * secondVelocity / (2 * GRAVITY)
	end
	if landing > apex then
		return 0, apex -- inatteignable
	end
	local fallTime = math.sqrt(2 * (apex - landing) / GRAVITY)
	return horizontalSpeed * (riseTime + fallTime), apex
end

return MovementModel
