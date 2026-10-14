--!strict
--[[
	AvatarCreatorCamera
	Caméra scriptable de l'écran de création : placée face au personnage, légèrement décalée
	pour le laisser dans la partie gauche de l'écran (le panneau d'options occupe la droite).

	Recalculée à chaque frame à partir du HumanoidRootPart : elle suit donc toute seule les
	changements de taille et un éventuel nouveau personnage.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RENDER_STEP_NAME = "AvatarCreatorCamera"

local FIELD_OF_VIEW = 40
local START_DISTANCE = 17 -- distance avant le travelling d'ouverture (studs)
local END_DISTANCE = 9.5 -- distance finale
local CAMERA_HEIGHT = 1 -- hauteur de la caméra au-dessus du point visé
local FOCUS_HEIGHT = 0.2 -- point visé, par rapport au centre du RootPart
local SIDE_OFFSET = 2.2 -- décalage latéral : pousse le personnage vers la gauche de l'écran
local SWAY_AMPLITUDE = 0.1 -- "respiration" verticale de la caméra
local SWAY_SPEED = 0.6

local localPlayer = Players.LocalPlayer

local AvatarCreatorCamera = {}

local isRunning = false
local savedFieldOfView = 70
local dollyStartClock: number? = nil
local dollyDuration = 1

local function getDistance(): number
	if dollyStartClock == nil then
		return START_DISTANCE
	end
	local progress = math.clamp((os.clock() - dollyStartClock) / dollyDuration, 0, 1)
	local eased = TweenService:GetValue(progress, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	return START_DISTANCE + (END_DISTANCE - START_DISTANCE) * eased
end

local function update()
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if camera == nil or rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	-- Les scripts caméra par défaut peuvent reprendre la main (au respawn par exemple).
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = FIELD_OF_VIEW

	local rootCFrame = rootPart.CFrame
	local screenRight = -rootCFrame.RightVector -- la droite de l'écran est la gauche du personnage
	local sway = math.sin(os.clock() * SWAY_SPEED) * SWAY_AMPLITUDE

	local focus = rootCFrame.Position + Vector3.new(0, FOCUS_HEIGHT, 0) + screenRight * SIDE_OFFSET
	local position = focus + rootCFrame.LookVector * getDistance() + Vector3.new(0, CAMERA_HEIGHT + sway, 0)

	camera.CFrame = CFrame.lookAt(position, focus)
end

-- Verrouille la caméra face au personnage, à START_DISTANCE.
function AvatarCreatorCamera.start()
	if isRunning then
		return
	end
	isRunning = true
	dollyStartClock = nil

	local camera = workspace.CurrentCamera
	if camera then
		savedFieldOfView = camera.FieldOfView
	end
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

-- Lance le travelling avant jusqu'à END_DISTANCE.
function AvatarCreatorCamera.dollyIn(duration: number)
	dollyStartClock = os.clock()
	dollyDuration = math.max(duration, 0.01)
end

-- Rend la caméra au joueur.
function AvatarCreatorCamera.stop()
	if not isRunning then
		return
	end
	isRunning = false
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = savedFieldOfView
		camera.CameraType = Enum.CameraType.Custom
	end
end

return AvatarCreatorCamera
