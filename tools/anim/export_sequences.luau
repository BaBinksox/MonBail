-- Exporte toutes les séquences d'animation du jeu dans un fichier .rbxmx (outil, hors Roblox) :
-- un Model « AnimSaves » contenant une KeyframeSequence par action d'AnimationConfig, construite
-- depuis PoseLibrary avec la même règle que Shared/Animation/KeyframeBuilder.
-- Usage : tools/anim/export.sh   ->   build/AnimationSequences.rbxmx
-- Dans Studio : glisser le fichier sur un rig R15 (il devient son dossier AnimSaves), puis
-- Animation Editor > « ... » > Load (voir docs/ANIMATIONS.md).
local mock = require("../sim/mock")
local runtime = require("../sim/runtime")(mock)
local env = require("../sim/bundle_out")(mock)
local _ = runtime
local PoseLibrary = env.require("ReplicatedStorage/Shared/Animation/PoseLibrary")
local AnimationConfig = env.require("ReplicatedStorage/Shared/Animation/AnimationConfig")

local out = {}
local function emit(s)
	table.insert(out, s)
end
local referent = 0
local function ref()
	referent += 1
	return "RBX" .. referent
end
local function esc(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local function num(x)
	if math.abs(x) < 1e-9 then
		return "0"
	end
	return string.format("%.6g", x)
end

-- Matrice de CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz.
local function angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Ry = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Rz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	local function mul(a, b)
		local r = {}
		for i = 1, 3 do
			r[i] = {}
			for j = 1, 3 do
				r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
			end
		end
		return r
	end
	return mul(mul(Rx, Ry), Rz)
end

local function cframe(name, px, py, pz, m)
	emit(string.format('<CoordinateFrame name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z>', name, num(px), num(py), num(pz)))
	emit(string.format("<R00>%s</R00><R01>%s</R01><R02>%s</R02><R10>%s</R10><R11>%s</R11><R12>%s</R12><R20>%s</R20><R21>%s</R21><R22>%s</R22></CoordinateFrame>",
		num(m[1][1]), num(m[1][2]), num(m[1][3]), num(m[2][1]), num(m[2][2]), num(m[2][3]), num(m[3][1]), num(m[3][2]), num(m[3][3])))
end

local POSE_EASING = { Linear = 0, Cubic = 3 }
local PRIORITY_ACTION = 2

local function writePose(partName, key, partToJoint, children, isLinear)
	local short = partToJoint[partName]
	emit('<Item class="Pose" referent="' .. ref() .. '"><Properties>')
	if short then
		local a = key.j[short]
		local m = a and angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3])) or angles(0, 0, 0)
		local p = (short == "Root" and key.pos) and key.pos or nil
		cframe("CFrame", p and p.X or 0, p and p.Y or 0, p and p.Z or 0, m)
	else
		cframe("CFrame", 0, 0, 0, angles(0, 0, 0))
	end
	emit('<token name="EasingDirection">2</token>')
	emit('<token name="EasingStyle">' .. (isLinear and POSE_EASING.Linear or POSE_EASING.Cubic) .. "</token>")
	emit('<string name="Name">' .. esc(partName) .. "</string>")
	emit('<float name="Weight">' .. (short and "1" or "0") .. "</float>")
	emit("</Properties>")
	for _, child in ipairs(children[partName] or {}) do
		writePose(child, key, partToJoint, children, isLinear)
	end
	emit("</Item>")
end

local function writeSequence(actionName, definition)
	local joints = {}
	for _, key in ipairs(definition.keys) do
		for name in pairs(key.j) do
			if PoseLibrary.JOINT_INFO[name] then
				joints[name] = true
			end
		end
		if key.pos and key.pos.Magnitude > 1e-4 then
			joints.Root = true
		end
	end
	local partToJoint, parentOf, needed = {}, {}, { HumanoidRootPart = true }
	for short in pairs(joints) do
		partToJoint[PoseLibrary.JOINT_INFO[short].part] = short
	end
	for _, info in pairs(PoseLibrary.JOINT_INFO) do
		parentOf[info.part] = info.parent
	end
	for part in pairs(partToJoint) do
		local current = part
		while current and current ~= "HumanoidRootPart" do
			needed[current] = true
			current = parentOf[current]
		end
	end
	local children = {}
	for part in pairs(needed) do
		if part ~= "HumanoidRootPart" then
			local parent = parentOf[part]
			children[parent] = children[parent] or {}
			table.insert(children[parent], part)
		end
	end
	for _, list in pairs(children) do
		table.sort(list)
	end

	emit('<Item class="KeyframeSequence" referent="' .. ref() .. '"><Properties>')
	emit('<bool name="Loop">' .. tostring(definition.looped) .. "</bool>")
	emit('<string name="Name">' .. esc(actionName) .. "</string>")
	emit('<token name="Priority">' .. PRIORITY_ACTION .. "</token>")
	emit("</Properties>")
	for index, key in ipairs(definition.keys) do
		local nextKey = definition.keys[index + 1]
		local isLinear = nextKey ~= nil and nextKey.e == "linear"
		emit('<Item class="Keyframe" referent="' .. ref() .. '"><Properties>')
		emit('<string name="Name">Key' .. index .. "</string>")
		emit('<float name="Time">' .. num(key.t * definition.duration) .. "</float>")
		emit("</Properties>")
		writePose("HumanoidRootPart", key, partToJoint, children, isLinear)
		emit("</Item>")
	end
	emit("</Item>")
end

emit('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
emit('<Item class="Model" referent="' .. ref() .. '"><Properties><string name="Name">AnimSaves</string></Properties>')
local names = {}
for actionName in pairs(AnimationConfig.ACTIONS) do
	table.insert(names, actionName)
end
table.sort(names)
local count = 0
for _, actionName in ipairs(names) do
	local definition = PoseLibrary.get(AnimationConfig.ACTIONS[actionName].pose)
	if definition then
		writeSequence(actionName, definition)
		count += 1
	end
end
emit("</Item></roblox>")
print(table.concat(out, "\n"))
