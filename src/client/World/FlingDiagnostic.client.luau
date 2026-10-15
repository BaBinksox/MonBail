--!strict
--[[
	FlingDiagnostic (STUDIO UNIQUEMENT, désactivé par défaut)
	Aide à trouver la Part qui « projette » le personnage. Ne fait rien en production : le script
	s'arrête immédiatement hors Studio, et en Studio tant que l'attribut n'est pas posé.

	Activation (barre de commande de Studio, pendant un Play) :
		workspace:SetAttribute("DebugFling", true)
	Désactivation : workspace:SetAttribute("DebugFling", false)

	Quand la vitesse du personnage bondit sans cause connue (dash, éjection de combat, ultime :
	ces poussées passent par une LinearVelocity posée dans le personnage), on affiche UNE fois
	(au plus toutes les 2 s) les pièces solides qui touchent le personnage : chemin complet,
	position, taille, ancrage, attributs et DynamicId du modèle parent éventuel.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local ATTRIBUTE = "DebugFling"
local HORIZONTAL_LIMIT = 45 -- studs/s (marche 16, dash 85 mais avec DashVelocity)
local VERTICAL_LIMIT = 65 -- studs/s vers le haut (un saut normal ≈ 50)
local REPORT_COOLDOWN = 2
local SEARCH_MARGIN = Vector3.new(1.5, 1, 1.5)

local player = Players.LocalPlayer
local lastReport = 0

local function describeAttributes(instance: Instance): string
	local parts = {}
	for name, value in instance:GetAttributes() do
		table.insert(parts, string.format("%s=%s", name, tostring(value)))
	end
	table.sort(parts)
	return if #parts > 0 then table.concat(parts, ", ") else "-"
end

local function ownerWithDynamic(part: BasePart): Instance?
	local node: Instance? = part.Parent
	while node and node ~= workspace do
		if node:GetAttribute("DynamicId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Une poussée volontaire (dash, éjection, ultime) est une contrainte de vitesse dans le personnage.
local function hasIntendedForce(character: Model): boolean
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("LinearVelocity") or descendant:IsA("VectorForce") or descendant:IsA("AlignPosition") then
			return true
		end
	end
	return false
end

local function report(character: Model, root: BasePart, velocity: Vector3)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local orientation, size = character:GetBoundingBox()
	local touching = workspace:GetPartBoundsInBox(orientation, size + SEARCH_MARGIN * 2, params)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local state = if humanoid then tostring(humanoid:GetState()) else "?"
	print(string.format("[FlingDiagnostic] vitesse anormale %s (%.0f studs/s) à %s, état %s",
		tostring(velocity), velocity.Magnitude, tostring(root.Position), state))
	if #touching == 0 then
		print("[FlingDiagnostic]   aucune pièce solide au contact (cause probable : script ou personnage voisin)")
		return
	end
	for index, part in touching do
		if index > 8 then
			print(string.format("[FlingDiagnostic]   ... et %d autre(s)", #touching - 8))
			break
		end
		local owner = ownerWithDynamic(part)
		print(string.format("[FlingDiagnostic]   %s | pos %s | taille %s | ancrée %s | attributs %s%s",
			part:GetFullName(), tostring(part.Position), tostring(part.Size), tostring(part.Anchored),
			describeAttributes(part),
			if owner then string.format(" | DynamicId %s (%s)", tostring(owner:GetAttribute("DynamicId")), owner:GetFullName()) else ""))
	end
end

local connection: RBXScriptConnection? = nil

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function start()
	if connection then
		return
	end
	print("[FlingDiagnostic] actif (workspace.DebugFling = true)")
	connection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character == nil or root == nil or not root:IsA("BasePart") or root.Anchored then
			return
		end
		local velocity = root.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if horizontal < HORIZONTAL_LIMIT and velocity.Y < VERTICAL_LIMIT then
			return
		end
		local now = os.clock()
		if now - lastReport < REPORT_COOLDOWN or hasIntendedForce(character) then
			return
		end
		lastReport = now
		report(character, root, velocity)
	end)
end

local function refresh()
	if workspace:GetAttribute(ATTRIBUTE) == true then
		start()
	else
		stop()
	end
end

workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(refresh)
refresh()
