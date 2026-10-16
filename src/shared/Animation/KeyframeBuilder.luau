--!strict
--[[
	KeyframeBuilder (ModuleScript, partagé)
	Transforme une pose de PoseLibrary en VRAIE séquence d'animation Roblox (KeyframeSequence) :
	images clés, hiérarchie de Poses R15 (HumanoidRootPart > LowerTorso > UpperTorso > bras...),
	courbes d'interpolation, boucle, priorité. Cette séquence peut :
		- être enregistrée temporairement dans Studio (KeyframeSequenceProvider) et jouée par
		  l'Animator, comme un clip publié : c'est ce que fait le jeu en test dans Studio ;
		- être ouverte dans l'Animation Editor, retouchée, puis publiée (ID à coller dans
		  AnimationConfig) : voir install() ci-dessous et docs/ANIMATIONS.md.

	Seules les articulations réellement animées par la pose ont un poids de 1 : les autres
	(marche, jambes pendant un coup de bras...) restent aux animations de base de Roblox.

	Installation dans Studio (barre de commande, en mode édition) :
		require(game.ReplicatedStorage.Shared.Animation.KeyframeBuilder).install()
	crée (ou complète) un mannequin R15 « EchosAnimRig » armé d'une épée, avec toutes les séquences
	du jeu dans son dossier AnimSaves, prêtes à être chargées dans l'Animation Editor.
]]

local PoseLibrary = require(script.Parent:WaitForChild("PoseLibrary"))

local KeyframeBuilder = {}

export type BuildOptions = {
	priority: Enum.AnimationPriority?,
	name: string?,
}

local ROOT_PART = "HumanoidRootPart"

-- Articulations animées par une pose (union de toutes ses images clés) ; Root si le bassin bouge.
local function animatedJoints(definition: PoseLibrary.Pose): { [string]: boolean }
	local joints: { [string]: boolean } = {}
	for _, key in definition.keys do
		for name in key.j do
			if PoseLibrary.JOINT_INFO[name] then
				joints[name] = true
			end
		end
		if key.pos and key.pos.Magnitude > 1e-4 then
			joints.Root = true
		end
	end
	return joints
end

-- Pièces à placer dans la hiérarchie : les pièces animées et tous leurs parents.
local function partsToBuild(joints: { [string]: boolean }): ({ [string]: string }, { [string]: string })
	local partToJoint: { [string]: string } = {}
	local parentOf: { [string]: string } = {}
	for short in joints do
		local info = PoseLibrary.JOINT_INFO[short]
		partToJoint[info.part] = short
	end
	for _, info in PoseLibrary.JOINT_INFO do
		parentOf[info.part] = info.parent
	end
	return partToJoint, parentOf
end

local function poseCFrame(key: PoseLibrary.Key, short: string): CFrame
	local angles = key.j[short]
	local rotation = if angles
		then CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
		else CFrame.identity
	if short == "Root" and key.pos then
		return CFrame.new(key.pos) * rotation
	end
	return rotation
end

-- Construit la KeyframeSequence de `poseName`, ou nil si la pose est inconnue.
function KeyframeBuilder.build(poseName: string, options: BuildOptions?): KeyframeSequence?
	local definition = PoseLibrary.get(poseName)
	if definition == nil then
		return nil
	end
	local opts: BuildOptions = options or {}
	local joints = animatedJoints(definition)
	local partToJoint, parentOf = partsToBuild(joints)

	-- Pièces nécessaires : animées, plus leurs ancêtres jusqu'au HumanoidRootPart.
	local needed: { [string]: boolean } = { [ROOT_PART] = true }
	for part in partToJoint do
		local current: string? = part
		while current and current ~= ROOT_PART do
			needed[current] = true
			current = parentOf[current]
		end
	end

	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = opts.name or poseName
	sequence.Loop = definition.looped
	sequence.Priority = opts.priority or Enum.AnimationPriority.Action

	for index, key in definition.keys do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = key.t * definition.duration
		keyframe.Name = `Key{index}`
		-- La courbe d'un segment est portée par l'image clé de DÉPART : "linear" sur la suivante
		-- (la frappe) rend vif le segment qui y mène.
		local nextKey = definition.keys[index + 1]
		local isLinear = nextKey ~= nil and nextKey.e == "linear"

		local poses: { [string]: Pose } = {}
		local function getPose(part: string): Pose
			local existing = poses[part]
			if existing then
				return existing
			end
			local newPose = Instance.new("Pose")
			newPose.Name = part
			local short = partToJoint[part]
			if short then
				newPose.CFrame = poseCFrame(key, short)
				newPose.Weight = 1
			else
				newPose.CFrame = CFrame.identity
				newPose.Weight = 0 -- simple maillon de la hiérarchie : n'anime rien
			end
			newPose.EasingStyle = if isLinear then Enum.PoseEasingStyle.Linear else Enum.PoseEasingStyle.Cubic
			newPose.EasingDirection = Enum.PoseEasingDirection.InOut
			poses[part] = newPose
			local parentName = parentOf[part]
			if part ~= ROOT_PART and parentName then
				newPose.Parent = getPose(parentName)
			else
				newPose.Parent = keyframe
			end
			return newPose
		end
		for part in needed do
			getPose(part)
		end
		keyframe.Parent = sequence
	end
	return sequence
end

-- Toutes les séquences du jeu, par action (AnimationConfig.ACTIONS : nom d'action -> pose).
function KeyframeBuilder.buildAll(actions: { [string]: any }): { KeyframeSequence }
	local list = {}
	for actionName, action in actions do
		local sequence = KeyframeBuilder.build(action.pose, { name = actionName })
		if sequence then
			table.insert(list, sequence)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

--[[
	STUDIO SEULEMENT (barre de commande, mode édition). Prépare tout pour l'Animation Editor :
		1. un mannequin R15 « EchosAnimRig » dans le Workspace (créé s'il manque) ;
		2. une épée simple dans sa main droite (Motor6D SwordGrip -> Handle), comme en jeu ;
		3. toutes les séquences dans EchosAnimRig > AnimSaves.
	Ensuite : sélectionner le mannequin, Avatar > Animation Editor, « ... » > Load, choisir une
	séquence, la retoucher si besoin, puis « ... » > Publish to Roblox, et coller l'ID dans
	AnimationConfig.ACTIONS.<action>.animationId.
]]
function KeyframeBuilder.install(): Model?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local AnimationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"):WaitForChild("AnimationConfig")) :: any

	local rig = workspace:FindFirstChild("EchosAnimRig")
	if rig == nil then
		local isCreated, created = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if not isCreated or created == nil then
			warn("[KeyframeBuilder] Impossible de créer le mannequin : insérez un rig R15 (Avatar > Rig Builder), nommez-le EchosAnimRig, puis relancez install().")
			return nil
		end
		rig = created
		rig.Name = "EchosAnimRig"
		rig:PivotTo(CFrame.new(0, 6, 0))
		rig.Parent = workspace
	end
	if not rig:IsA("Model") then
		return nil
	end

	-- Épée de travail : même articulation que l'épée du jeu (SwordFactory).
	local hand = rig:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") and rig:FindFirstChild("Handle", true) == nil then
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.3, 1, 0.3)
		handle.CanCollide = false
		handle.Massless = true
		handle.CFrame = hand.CFrame
		handle.Parent = rig
		local blade = Instance.new("Part")
		blade.Name = "Blade"
		blade.Size = Vector3.new(0.2, 3.6, 0.5)
		blade.Material = Enum.Material.Metal
		blade.CanCollide = false
		blade.Massless = true
		blade.CFrame = handle.CFrame * CFrame.new(0, 2.3, 0)
		blade.Parent = rig
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = blade
		weld.Parent = blade
		local grip = Instance.new("Motor6D")
		grip.Name = "SwordGrip"
		grip.Part0 = hand
		grip.Part1 = handle
		grip.C0 = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		grip.Parent = hand
	end

	local saves = rig:FindFirstChild("AnimSaves")
	if saves == nil then
		saves = Instance.new("Model")
		saves.Name = "AnimSaves"
		saves.Parent = rig
	end
	local count = 0
	for _, sequence in KeyframeBuilder.buildAll(AnimationConfig.ACTIONS) do
		local old = (saves :: Instance):FindFirstChild(sequence.Name)
		if old then
			old:Destroy()
		end
		sequence.Parent = saves
		count += 1
	end
	print(`[KeyframeBuilder] {count} séquences installées dans {rig:GetFullName()}.AnimSaves`)
	return rig
end

return KeyframeBuilder
