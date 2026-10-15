--!strict
--[[
	CharacterPlacement
	Poser un personnage DEBOUT sur le sol réel, quelles que soient ses proportions.

	Pourquoi ce module : une ancre de personnage (Kit.standing) est posée « sol + 3 studs », la hauteur
	du HumanoidRootPart d'un R15 standard. Un personnage plus grand, plus petit, ou dont le rig vient
	d'être reconstruit (tête classique, BuildRigFromAttachments, qui peut recalculer HipHeight de
	travers) ne tient pas sur cette valeur fixe : ses pieds s'enfoncent dans le sol et le Humanoid
	tombe ou se couche. Ici, la hauteur vient :
		- du SOL réellement praticable sous l'ancre (raycast qui respecte CanCollide et ignore les
		  personnages, les ennemis et les marqueurs invisibles) ;
		- de la GÉOMÉTRIE du personnage (distance entre la plante des pieds et le centre du RootPart),
		  avec HipHeight seulement en secours.
	Un placement remet aussi à zéro la vitesse du personnage et sort le Humanoid d'un état couché.

	API :
		CharacterPlacement.findGround(position, ignore?): Vector3?    point du sol sous `position`
		CharacterPlacement.measureHipHeight(character): number?      HipHeight mesurée sur les pieds
		CharacterPlacement.getRootHeight(character): number           pieds -> centre du RootPart
		CharacterPlacement.place(character, target): boolean          pose debout à `target`
		CharacterPlacement.repairHipHeight(character, expected?)      corrige un HipHeight aberrant
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PROBE_UP = 1.5 -- studs au-dessus de l'ancre (« sol + 3 ») : sous un éventuel plafond
local PROBE_DOWN = 60
local FEET_CLEARANCE = 0.05 -- les pieds sont posés juste au-dessus de la surface
local DEFAULT_ROOT_HEIGHT = 3 -- R15 standard : HipHeight 2 + demi-RootPart 1
local HIP_TOLERANCE = 0.75 -- écart (studs) au-delà duquel HipHeight est jugé faux
local MIN_HIP_HEIGHT = 0.3
local MAX_HIP_HEIGHT = 12

local FOOT_NAMES = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }
local LYING_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Seated] = true,
}
local IGNORED_TAGS = { "Enemy", "Villager", "Boss" }

local CharacterPlacement = {}

local function getParts(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if root == nil then
		local candidate = character:FindFirstChild("HumanoidRootPart")
		root = if candidate and candidate:IsA("BasePart") then candidate else nil
	end
	return humanoid, root
end

-- Point le plus bas d'une pièce (ses 8 coins, rotation comprise).
local function bottomOf(part: BasePart): number
	local half = part.Size / 2
	local lowest = math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
				lowest = math.min(lowest, corner.Y)
			end
		end
	end
	return lowest
end

function CharacterPlacement.findGround(position: Vector3, ignore: { Instance }?): Vector3?
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	for _, tag in IGNORED_TAGS do
		for _, instance in CollectionService:GetTagged(tag) do
			table.insert(exclude, instance)
		end
	end
	if ignore then
		for _, instance in ignore do
			table.insert(exclude, instance)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true -- ignore les ancres, les décors et les vitres non solides
	params.IgnoreWater = true
	local origin = position + Vector3.new(0, PROBE_UP, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(PROBE_UP + PROBE_DOWN), 0), params)
	return if result then result.Position else nil
end

-- HipHeight déduite de la géométrie : bas du RootPart -> plante des pieds. nil si pas de pieds.
function CharacterPlacement.measureHipHeight(character: Model): number?
	local _, root = getParts(character)
	if root == nil then
		return nil
	end
	local feet = math.huge
	for _, name in FOOT_NAMES do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			feet = math.min(feet, bottomOf(part))
		end
	end
	if feet == math.huge then
		return nil
	end
	return (root.Position.Y - root.Size.Y / 2) - feet
end

-- Distance entre la plante des pieds et le centre du RootPart, debout.
function CharacterPlacement.getRootHeight(character: Model): number
	local humanoid, root = getParts(character)
	if root == nil then
		return DEFAULT_ROOT_HEIGHT
	end
	local measured = CharacterPlacement.measureHipHeight(character)
	local hip = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight else nil
	local chosen = measured or hip
	if chosen == nil or chosen < MIN_HIP_HEIGHT or chosen > MAX_HIP_HEIGHT then
		return DEFAULT_ROOT_HEIGHT
	end
	return chosen + root.Size.Y / 2
end

--[[
	Après une reconstruction du rig (tête classique), HipHeight peut être recalculé de travers : le
	Humanoid se maintient alors trop bas et ses jambes passent dans le sol. On rétablit `expected`
	(la valeur calculée par Roblox juste après ApplyDescription) ou, à défaut, la valeur mesurée.
]]
function CharacterPlacement.repairHipHeight(character: Model, expected: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local measured = CharacterPlacement.measureHipHeight(character)
	local reference = expected
	if reference == nil or reference < MIN_HIP_HEIGHT or reference > MAX_HIP_HEIGHT then
		reference = measured
	elseif measured and measured >= MIN_HIP_HEIGHT and math.abs(measured - reference) > HIP_TOLERANCE then
		reference = measured -- la géométrie fait foi quand les deux divergent nettement
	end
	if reference and reference >= MIN_HIP_HEIGHT and reference <= MAX_HIP_HEIGHT and math.abs(humanoid.HipHeight - reference) > 0.05 then
		humanoid.HipHeight = reference
	end
end

-- Remet le personnage debout et immobile (vitesse nulle, pas d'état couché ni assis).
local function settle(character: Model, humanoid: Humanoid?)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		if LYING_STATES[humanoid:GetState()] then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

--[[
	Pose `character` debout à `target` (position ET orientation : seul le cap horizontal est gardé).
	Le sol est cherché sous la position de l'ancre ; sans sol (carte non construite, vide), la cible
	est utilisée telle quelle. Retourne false si le personnage n'a pas de RootPart.
]]
function CharacterPlacement.place(character: Model, target: CFrame): boolean
	local humanoid, root = getParts(character)
	if root == nil or character.Parent == nil then
		return false
	end
	local look = target.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local ground = CharacterPlacement.findGround(target.Position, { character })
	local y = if ground then ground.Y + CharacterPlacement.getRootHeight(character) + FEET_CLEARANCE else target.Position.Y
	local position = Vector3.new(target.Position.X, y, target.Position.Z)
	settle(character, humanoid)
	-- On déplace le Model entier de sorte que le RootPart arrive à la cible (indépendant du pivot).
	local rootTarget = CFrame.lookAt(position, position + heading)
	character:PivotTo(rootTarget * root.CFrame:Inverse() * character:GetPivot())
	settle(character, humanoid)
	return true
end

return CharacterPlacement
