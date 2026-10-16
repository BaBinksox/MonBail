--!strict
--[[
	TouchLayout (ModuleScript, client)
	Place les boutons tactiles de ContextActionService selon la taille de l'écran, d'après
	KeyBindings : `touchCompact` sur un téléphone (plus petit côté ≤ 500 px, comme le bouton de saut
	de Roblox, qui y est plus petit), `touch` sinon. Réappliqué quand l'écran change (rotation,
	fenêtre redimensionnée). Sans effet sur ordinateur et à la manette (pas de bouton créé).

	API : TouchLayout.place(actionName, bindingName)   à appeler juste après BindAction
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KeyBindings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Input"):WaitForChild("KeyBindings") :: ModuleScript)

local COMPACT_MAX_SIDE = 500 -- même seuil que le bouton de saut de Roblox

local TouchLayout = {}

local placed: { [string]: string } = {} -- action -> nom de la commande dans KeyBindings
local watchedCamera: Camera? = nil

local function isCompact(): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local size = camera.ViewportSize
	return math.min(size.X, size.Y) <= COMPACT_MAX_SIDE
end

local function apply(actionName: string, bindingName: string)
	local binding = KeyBindings.BINDINGS[bindingName]
	if binding == nil then
		return
	end
	local position = if isCompact() then binding.touchCompact or binding.touch else binding.touch
	if position then
		pcall(function()
			ContextActionService:SetPosition(actionName, position)
		end)
	end
end

local function applyAll()
	for actionName, bindingName in placed do
		apply(actionName, bindingName)
	end
end

local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera == nil or camera == watchedCamera then
		return
	end
	watchedCamera = camera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyAll)
end

function TouchLayout.place(actionName: string, bindingName: string)
	placed[actionName] = bindingName
	watchCamera()
	apply(actionName, bindingName)
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera()
	applyAll()
end)

return TouchLayout
