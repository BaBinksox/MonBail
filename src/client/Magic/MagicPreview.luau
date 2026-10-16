--!strict
--[[
	MagicPreview (ModuleScript, client)
	Aperçu d'une Magie Innée dans le créateur de personnage : le personnage enchaîne le geste du
	sort de base, celui du sort secondaire, puis la pose de l'ultime, avec les MÊMES effets visuels
	qu'en jeu (SpellEffects, chorégraphies d'ultime).

	Purement décoratif et local :
		- aucune demande au serveur, aucun dégât, aucune cible réelle (les effets visent un point
		  vide à côté du personnage ; la Chaîne Foudroyante saute entre des repères invisibles) ;
		- ni Mana, ni Tension, ni recharge, ni progression ;
		- interrompu par stop() (changement de page, fermeture du créateur).

	API :
		MagicPreview.play(character, magic) -> boolean   false si un aperçu tourne déjà
		MagicPreview.stop()
		MagicPreview.isPlaying() -> boolean
		MagicPreview.finished:Connect(function() end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local clientFolder = script.Parent.Parent
local AnimationConfig = require(sharedFolder:WaitForChild("Animation"):WaitForChild("AnimationConfig") :: ModuleScript)
local SpellConfig = require(sharedFolder:WaitForChild("Magic"):WaitForChild("SpellConfig") :: ModuleScript)
local CharacterAnimator = require(clientFolder:WaitForChild("Animation"):WaitForChild("CharacterAnimator") :: ModuleScript)
local CombatEffects = require(clientFolder:WaitForChild("Combat"):WaitForChild("CombatEffects") :: ModuleScript)
local SpellEffects = require(script.Parent:WaitForChild("SpellEffects") :: ModuleScript)
local MagicFx = require(script.Parent:WaitForChild("MagicFx") :: ModuleScript)

local SIDE_DISTANCE = 12 -- studs : les sorts visent un point à droite du personnage (vu de face)
local GAP = 0.9 -- s de pause entre deux démonstrations
local ULTIMATE_HOLD = 1.6 -- s laissées à la chorégraphie d'ultime pour s'éteindre

local MagicPreview = {}

local finishedEvent = Instance.new("BindableEvent")
MagicPreview.finished = finishedEvent.Event

local token = 0
local playing = false
local nextCastId = 0

local function isCurrent(myToken: number): boolean
	return token == myToken
end

-- Identifiants négatifs : jamais confondus avec les sorts annoncés par le serveur.
local function newCastId(): number
	nextCastId -= 1
	return nextCastId
end

local function ultimateAction(magicId: string): string
	local dedicated = `cast_ultimate_{magicId}`
	return if AnimationConfig.ACTIONS[dedicated] then dedicated else "cast_ultimate"
end

-- Repères invisibles (sans Humanoid, ni collision, ni requête) pour les effets qui sautent de
-- cible en cible. Détruits juste après.
local function markers(points: { Vector3 }, lifetime: number): { Model }
	local list: { Model } = {}
	for index, point in points do
		local model = Instance.new("Model")
		model.Name = "PreviewMarker" .. index
		local part = Instance.new("Part")
		part.Name = "Anchor"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.CFrame = CFrame.new(point)
		part.Parent = model
		model.PrimaryPart = part
		model.Parent = MagicFx.getFolder()
		task.delay(lifetime, function()
			model:Destroy()
		end)
		table.insert(list, model)
	end
	return list
end

-- Démonstration d'un sort : geste, annonce, puis résolution visuelle. Rend la durée écoulée.
local function demoSpell(character: Model, root: BasePart, spell: any, myToken: number)
	local animator = CharacterAnimator.get(character, true)
	animator:play(spell.action)
	local side = root.CFrame.RightVector
	local forward = root.CFrame.LookVector
	local origin = root.Position
	local aim = origin + side * math.min(SIDE_DISTANCE, math.max(spell.range, 6)) + forward * 3
	if spell.kind == "zone" or spell.kind == "field" then
		aim = MagicFx.groundBelow(aim + Vector3.new(0, 4, 0), { character })
	end
	if spell.selfCentered or spell.kind == "self" then
		aim = MagicFx.groundBelow(origin, { character })
	end
	local castId = newCastId()
	SpellEffects.castStarted(character, spell, castId, origin, aim)

	local delay = spell.castTime
	if spell.kind == "projectile" and spell.speed > 0 then
		delay += (aim - origin).Magnitude / spell.speed
	end
	task.wait(delay)
	if not isCurrent(myToken) then
		return
	end
	local targets: { Model } = {}
	if spell.kind == "chain" then
		local count = math.min(spell.maxTargets, 3)
		local points: { Vector3 } = {}
		for index = 1, count do
			table.insert(points, origin + side * (6 + index * 4) + forward * (if index % 2 == 0 then 3 else -1))
		end
		targets = markers(points, 2)
	end
	SpellEffects.impact(castId, spell, aim, targets, character)
	local extra = if spell.kind == "field" then math.min(spell.pulses * spell.pulseInterval, 2) else 0
	task.wait(GAP + extra)
end

function MagicPreview.isPlaying(): boolean
	return playing
end

function MagicPreview.stop()
	if not playing then
		return
	end
	token += 1
	playing = false
	finishedEvent:Fire()
end

function MagicPreview.play(character: Model, magic: any): boolean
	if playing then
		return false
	end
	local root = MagicFx.rootOf(character)
	if root == nil then
		return false
	end
	token += 1
	local myToken = token
	playing = true
	task.spawn(function()
		for _, slot in { "base", "secondary" } do
			local spell = SpellConfig.forMagic(magic.id, slot)
			if spell and isCurrent(myToken) then
				demoSpell(character, root, spell, myToken)
			end
		end
		if isCurrent(myToken) then
			CharacterAnimator.get(character, true):play(ultimateAction(magic.id))
			-- Mêmes effets qu'en jeu, sans cible : la chorégraphie attend la préparation puis frappe.
			CombatEffects.playUltimate(character, root.Position, {}, magic)
			task.wait(ULTIMATE_HOLD)
		end
		if isCurrent(myToken) then
			playing = false
			finishedEvent:Fire()
		end
	end)
	return true
end

return MagicPreview
