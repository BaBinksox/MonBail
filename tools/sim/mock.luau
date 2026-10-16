-- Simulation minimale de l'API Roblox pour exécuter des modules hors de Studio (outil de test).
-- Couvre : Vector3, Vector2, CFrame, Color3, Enum, Instance (arbre, propriétés, attributs, tags),
-- Terrain (opérations enregistrées), Random déterministe, task (immédiat), services courants.

local M = {}

--------------------------------------------------------------------------------
-- Vector3
--------------------------------------------------------------------------------
local Vector3 = {}
local V3mt = {}
V3mt.__type = "Vector3"
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then return v3(0, 0, 0) end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" then return v.X elseif k == "y" then return v.Y elseif k == "z" then return v.Z
	end
	return Vector3[k]
end
V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__idiv = function(a, b)
	if type(b) == "number" then return v3(a.X // b, a.Y // b, a.Z // b) end
	return v3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(v) return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z) end
function Vector3.new(x, y, z) return v3(x, y, z) end
function Vector3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function Vector3.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function Vector3.Lerp(a, b, t) return a + (b - a) * t end
function Vector3.Min(a, b) return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function Vector3.Max(a, b) return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
function Vector3.Abs(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
function Vector3.Floor(a) return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z)) end
function Vector3.Ceil(a) return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z)) end
function Vector3.Sign(a) return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z)) end
function Vector3.FuzzyEq(a, b, eps) eps = eps or 1e-5 return (a - b).Magnitude <= eps end
function Vector3.Angle(a, b)
	local d = Vector3.Dot(a.Unit, b.Unit)
	return math.acos(math.clamp(d, -1, 1))
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
M.Vector3 = Vector3

local Vector2 = {}
local V2mt = { __type = "Vector2" }
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end
V2mt.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y) if m == 0 then return v2(0, 0) end return v2(v.X / m, v.Y / m) end
	return Vector2[k]
end
V2mt.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b)
	if type(a) == "number" then return v2(a * b.X, a * b.Y) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__div = function(a, b) if type(b) == "number" then return v2(a.X / b, a.Y / b) end return v2(a.X / b.X, a.Y / b.Y) end
V2mt.__unm = function(a) return v2(-a.X, -a.Y) end
V2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
function Vector2.new(x, y) return v2(x, y) end
function Vector2.Dot(a, b) return a.X * b.X + a.Y * b.Y end
function Vector2.Lerp(a, b, t) return a + (b - a) * t end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
M.Vector2 = Vector2

--------------------------------------------------------------------------------
-- CFrame (rotation stockée en colonnes : right, up, back)
--------------------------------------------------------------------------------
local CFrame = {}
local CFmt = { __type = "CFrame" }
-- r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } (lignes)
local function cf(px, py, pz, r)
	return setmetatable({ p = v3(px, py, pz), r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CFmt)
end
local function mulR(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function rotV(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
CFmt.__index = function(c, k)
	if k == "Position" then return c.p
	elseif k == "X" then return c.p.X elseif k == "Y" then return c.p.Y elseif k == "Z" then return c.p.Z
	elseif k == "RightVector" or k == "XVector" then return v3(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" or k == "YVector" then return v3(c.r[2], c.r[5], c.r[8])
	elseif k == "ZVector" then return v3(c.r[3], c.r[6], c.r[9])
	elseif k == "LookVector" then return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "Rotation" then return cf(0, 0, 0, c.r)
	end
	return CFrame[k]
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == CFmt then
		local p = rotV(a.r, b.p) + a.p
		return cf(p.X, p.Y, p.Z, mulR(a.r, b.r))
	end
	return rotV(a.r, b) + a.p
end
CFmt.__add = function(a, v) local p = a.p + v return cf(p.X, p.Y, p.Z, a.r) end
CFmt.__sub = function(a, v) local p = a.p - v return cf(p.X, p.Y, p.Z, a.r) end
CFmt.__eq = function(a, b)
	if a.p ~= b.p then return false end
	for i = 1, 9 do if a.r[i] ~= b.r[i] then return false end end
	return true
end
CFmt.__tostring = function(c) return "CFrame(" .. tostring(c.p) .. ")" end

local function rx(a) local c, s = math.cos(a), math.sin(a) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function ry(a) local c, s = math.cos(a), math.sin(a) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rz(a) local c, s = math.cos(a), math.sin(a) return { c, -s, 0, s, c, 0, 0, 0, 1 } end

local function lookAtR(pos, target, up)
	up = up or v3(0, 1, 0)
	local back = (pos - target).Unit
	if back.Magnitude == 0 then return { 1, 0, 0, 0, 1, 0, 0, 0, 1 } end
	local right = Vector3.Cross(up, back)
	if right.Magnitude < 1e-6 then right = Vector3.Cross(v3(0, 0, 1), back) end
	right = right.Unit
	local upv = Vector3.Cross(back, right).Unit
	return { right.X, upv.X, back.X, right.Y, upv.Y, back.Y, right.Z, upv.Z, back.Z }
end

function CFrame.new(a, b, c, ...)
	if a == nil then return cf(0, 0, 0) end
	if type(a) == "number" then
		local extra = { ... }
		if #extra == 9 then
			return cf(a, b, c, extra)
		end
		return cf(a, b, c)
	end
	-- CFrame.new(pos) ou CFrame.new(pos, lookAt)
	if b ~= nil then
		return cf(a.X, a.Y, a.Z, lookAtR(a, b))
	end
	return cf(a.X, a.Y, a.Z)
end
function CFrame.fromMatrix(pos, right, up, back)
	back = back or Vector3.Cross(right, up)
	return cf(pos.X, pos.Y, pos.Z, { right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z })
end
function CFrame.lookAt(pos, target, up) return cf(pos.X, pos.Y, pos.Z, lookAtR(pos, target, up)) end
function CFrame.Angles(x, y, z) return cf(0, 0, 0, mulR(mulR(rx(x), ry(y)), rz(z))) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(x, y, z) return cf(0, 0, 0, mulR(mulR(ry(y), rx(x)), rz(z))) end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return cf(0, 0, 0, {
		t * u.X * u.X + c, t * u.X * u.Y - s * u.Z, t * u.X * u.Z + s * u.Y,
		t * u.X * u.Y + s * u.Z, t * u.Y * u.Y + c, t * u.Y * u.Z - s * u.X,
		t * u.X * u.Z - s * u.Y, t * u.Y * u.Z + s * u.X, t * u.Z * u.Z + c,
	})
end
function CFrame.fromMatrix(pos, right, up, back)
	back = back or Vector3.Cross(right, up).Unit
	return cf(pos.X, pos.Y, pos.Z, { right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z })
end
function CFrame.Inverse(c)
	local rt = transpose(c.r)
	local p = rotV(rt, -c.p)
	return cf(p.X, p.Y, p.Z, rt)
end
function CFrame.ToWorldSpace(c, o) return c * o end
function CFrame.ToObjectSpace(c, o) return CFrame.Inverse(c) * o end
function CFrame.PointToWorldSpace(c, v) return c * v end
function CFrame.PointToObjectSpace(c, v) return CFrame.Inverse(c) * v end
function CFrame.VectorToWorldSpace(c, v) return rotV(c.r, v) end
function CFrame.VectorToObjectSpace(c, v) return rotV(transpose(c.r), v) end
function CFrame.Lerp(a, b, t)
	local p = a.p:Lerp(b.p, t)
	return cf(p.X, p.Y, p.Z, if t < 0.5 then a.r else b.r)
end
function CFrame.GetComponents(c)
	local r = c.r
	return c.p.X, c.p.Y, c.p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CFrame.components = CFrame.GetComponents
function CFrame.ToEulerAnglesXYZ(c)
	local r = c.r
	local y = math.asin(math.clamp(r[3], -1, 1))
	local x = math.atan2(-r[6], r[9])
	local z = math.atan2(-r[2], r[1])
	return x, y, z
end
function CFrame.ToEulerAnglesYXZ(c)
	local r = c.r
	local x = math.asin(math.clamp(-r[6], -1, 1))
	local y = math.atan2(r[3], r[9])
	local z = math.atan2(r[4], r[5])
	return x, y, z
end
CFrame.ToOrientation = CFrame.ToEulerAnglesYXZ
CFrame.identity = cf(0, 0, 0)
M.CFrame = CFrame

--------------------------------------------------------------------------------
-- Color3, Enum et types opaques
--------------------------------------------------------------------------------
local Color3 = {}
local C3mt = { __type = "Color3" }
C3mt.__index = function(c, k)
	if k == "r" then return c.R elseif k == "g" then return c.G elseif k == "b" then return c.B end
	return Color3[k]
end
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
local function c3(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end
function Color3.new(r, g, b) return c3(r, g, b) end
function Color3.fromRGB(r, g, b) return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return c3(v, t, p) elseif i == 1 then return c3(q, v, p) elseif i == 2 then return c3(p, v, t)
	elseif i == 3 then return c3(p, q, v) elseif i == 4 then return c3(t, p, v) else return c3(v, p, q) end
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
function Color3.Lerp(a, b, t) return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
function Color3.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, mx
	local d = mx - mn
	if mx > 0 then s = d / mx end
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
		h /= 6
	end
	return h, s, v
end
M.Color3 = Color3

local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumType)
		if enumCache[enumType] == nil then
			local items = {}
			enumCache[enumType] = setmetatable({}, {
				__index = function(_, name)
					if name == "GetEnumItems" then
						return function() return {} end
					end
					if items[name] == nil then
						items[name] = setmetatable({ EnumType = enumType, Name = name, Value = 0 }, {
							__type = "EnumItem",
							__tostring = function() return "Enum." .. enumType .. "." .. name end,
						})
					end
					return items[name]
				end,
			})
		end
		return enumCache[enumType]
	end,
})
M.Enum = Enum

local function opaque(typeName)
	local mt = { __type = typeName }
	mt.__index = mt
	return {
		new = function(...)
			return setmetatable({ args = { ... } }, mt)
		end,
	}
end
M.NumberSequence = opaque("NumberSequence")
M.ColorSequence = opaque("ColorSequence")
M.NumberSequenceKeypoint = opaque("NumberSequenceKeypoint")
M.ColorSequenceKeypoint = opaque("ColorSequenceKeypoint")
M.NumberRange = opaque("NumberRange")
M.PhysicalProperties = opaque("PhysicalProperties")
M.TweenInfo = opaque("TweenInfo")
M.Font = opaque("Font")
M.Font.fromEnum = function(e) return M.Font.new(e) end
M.Font.fromName = function(n) return M.Font.new(n) end
M.Rect = opaque("Rect")
local function params(typeName)
	return {
		new = function()
			return setmetatable({ FilterDescendantsInstances = {}, AddToFilter = function() end }, { __type = typeName })
		end,
	}
end
M.RaycastParams = params("RaycastParams")
M.OverlapParams = params("OverlapParams")
M.Faces = opaque("Faces")
M.Axes = opaque("Axes")
local UDimT = opaque("UDim")
M.UDim = UDimT
local UDim2mt = { __type = "UDim2" }
UDim2mt.__index = UDim2mt
UDim2mt.__add = function(a, b)
	return setmetatable({ X = { Scale = a.X.Scale + b.X.Scale, Offset = a.X.Offset + b.X.Offset }, Y = { Scale = a.Y.Scale + b.Y.Scale, Offset = a.Y.Offset + b.Y.Offset } }, UDim2mt)
end
UDim2mt.__sub = function(a, b)
	return setmetatable({ X = { Scale = a.X.Scale - b.X.Scale, Offset = a.X.Offset - b.X.Offset }, Y = { Scale = a.Y.Scale - b.Y.Scale, Offset = a.Y.Offset - b.Y.Offset } }, UDim2mt)
end
UDim2mt.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
function UDim2mt.Lerp(a, b, t)
	local function l(x, y) return x + (y - x) * t end
	return setmetatable({ X = { Scale = l(a.X.Scale, b.X.Scale), Offset = l(a.X.Offset, b.X.Offset) }, Y = { Scale = l(a.Y.Scale, b.Y.Scale), Offset = l(a.Y.Offset, b.Y.Offset) } }, UDim2mt)
end
M.UDim2 = {
	new = function(xs, xo, ys, yo) return setmetatable({ X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, UDim2mt) end,
	fromScale = function(x, y) return setmetatable({ X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }, UDim2mt) end,
	fromOffset = function(x, y) return setmetatable({ X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }, UDim2mt) end,
}
local BrickColorT = {}
BrickColorT.new = function(name) return setmetatable({ Name = name, Color = c3(0.5, 0.5, 0.5) }, { __type = "BrickColor" }) end
M.BrickColor = BrickColorT

-- Random déterministe (LCG 48 bits simplifié)
local RandomT = {}
local Rmt = { __type = "Random" }
Rmt.__index = Rmt
function RandomT.new(seed)
	return setmetatable({ state = (seed or 12345) % 2147483647 + 1 }, Rmt)
end
function Rmt:_next()
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function Rmt:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function Rmt:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
function Rmt:NextUnitVector()
	local th = self:_next() * math.pi * 2
	local z = self:_next() * 2 - 1
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(th), r * math.sin(th), z)
end
function Rmt:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function Rmt:Clone() return setmetatable({ state = self.state }, Rmt) end
M.Random = RandomT

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------
local Instance = {}
local Imt = { __type = "Instance" }
local allInstances = {}
local tags = {} -- [instance] = { [tag] = true }
local nextId = 0

local DEFAULTS = {
	Part = { Size = v3(4, 1, 2), Anchored = false, CanCollide = true, Transparency = 0, Shape = Enum.PartType.Block },
	WedgePart = { Size = v3(4, 1, 2), Anchored = false, CanCollide = true, Transparency = 0 },
	CornerWedgePart = { Size = v3(2, 2, 2), Anchored = false, CanCollide = true, Transparency = 0 },
	TrussPart = { Size = v3(2, 10, 2), Anchored = false, CanCollide = true, Transparency = 0 },
	SpawnLocation = { Size = v3(12, 1, 12), Anchored = true, CanCollide = true, Transparency = 0 },
	Seat = { Size = v3(2, 1, 2), Anchored = false, CanCollide = true, Transparency = 0 },
	MeshPart = { Size = v3(1, 1, 1), Anchored = false, CanCollide = true, Transparency = 0 },
	Attachment = { CFrame = cf(0, 0, 0), Position = v3() },
	Motor6D = { C0 = cf(0, 0, 0), C1 = cf(0, 0, 0), Transform = cf(0, 0, 0) },
	Weld = { C0 = cf(0, 0, 0), C1 = cf(0, 0, 0) },
	Humanoid = { MoveDirection = v3(), JumpHeight = 7.2, AutoRotate = true },
}
-- Interfaces : aucune mise en page réelle, des tailles absolues fixes suffisent aux calculs.
for _, cls in ipairs({ "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ScrollingFrame", "TextBox", "ViewportFrame", "CanvasGroup", "VideoFrame" }) do
	DEFAULTS[cls] = {
		AbsoluteSize = v2(200, 50), AbsolutePosition = v2(0, 0), AbsoluteRotation = 0, Visible = true,
		BackgroundTransparency = 0, Transparency = 0, TextTransparency = 0, ImageTransparency = 0,
		Text = (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox") and "" or nil,
		TextSize = 14, Rotation = 0, ZIndex = 1, LayoutOrder = 0, Active = false, Selectable = false,
		CanvasPosition = v2(0, 0), AbsoluteCanvasSize = v2(200, 50), AbsoluteWindowSize = v2(200, 50),
		TextBounds = v2(100, 14), GroupTransparency = 0,
	}
end
for _, cls in ipairs({ "ScreenGui", "BillboardGui", "SurfaceGui" }) do
	DEFAULTS[cls] = { AbsoluteSize = v2(1920, 1080), AbsolutePosition = v2(0, 0), Enabled = true, DisplayOrder = 0 }
end
DEFAULTS.UIListLayout = { AbsoluteContentSize = v2(200, 50) }
DEFAULTS.UIGridLayout = { AbsoluteContentSize = v2(200, 50), AbsoluteCellSize = v2(50, 50) }
DEFAULTS.UIScale = { Scale = 1 }
DEFAULTS.Sound = { Volume = 0.5, Playing = false, IsLoaded = true, TimeLength = 10, TimePosition = 0, Looped = false }
local BASEPART = { Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true, MeshPart = true, BasePart = true }
local ISA = {
	BasePart = BASEPART,
	PVInstance = setmetatable({ Model = true }, { __index = BASEPART }),
	Light = { PointLight = true, SpotLight = true, SurfaceLight = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, TextBox = true },
	LayerCollector = { ScreenGui = true, BillboardGui = true, SurfaceGui = true },
	ValueBase = { StringValue = true, NumberValue = true, BoolValue = true, IntValue = true, ObjectValue = true },
}

local function isA(inst, className)
	local c = rawget(inst, "ClassName")
	if c == className or className == "Instance" then return true end
	local group = ISA[className]
	return group ~= nil and group[c] == true
end

local methods = {}
function methods.IsA(self, className) return isA(self, className) end
function methods.GetChildren(self)
	local t = {}
	for _, ch in ipairs(rawget(self, "_children")) do table.insert(t, ch) end
	return t
end
function methods.GetDescendants(self)
	local t = {}
	local function walk(n)
		for _, ch in ipairs(rawget(n, "_children")) do
			table.insert(t, ch)
			walk(ch)
		end
	end
	walk(self)
	return t
end
function methods.FindFirstChild(self, name, recursive)
	for _, ch in ipairs(rawget(self, "_children")) do
		if ch.Name == name then return ch end
	end
	if recursive then
		for _, ch in ipairs(rawget(self, "_children")) do
			local f = methods.FindFirstChild(ch, name, true)
			if f then return f end
		end
	end
	return nil
end
function methods.WaitForChild(self, name) return methods.FindFirstChild(self, name) end
function methods.FindFirstChildOfClass(self, className)
	for _, ch in ipairs(rawget(self, "_children")) do
		if rawget(ch, "ClassName") == className then return ch end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className, recursive)
	for _, ch in ipairs(rawget(self, "_children")) do
		if isA(ch, className) then return ch end
	end
	if recursive then
		for _, ch in ipairs(rawget(self, "_children")) do
			local f = methods.FindFirstChildWhichIsA(ch, className, true)
			if f then return f end
		end
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, className)
	local p = rawget(self, "_props").Parent
	while p do
		if rawget(p, "ClassName") == className then return p end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local p = rawget(self, "_props").Parent
	while p do
		if p.Name == name then return p end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function methods.IsDescendantOf(self, other)
	local p = rawget(self, "_props").Parent
	while p do
		if p == other then return true end
		p = rawget(p, "_props").Parent
	end
	return false
end
function methods.IsAncestorOf(self, other) return methods.IsDescendantOf(other, self) end
function methods.ClearAllChildren(self)
	for _, ch in ipairs(methods.GetChildren(self)) do methods.Destroy(ch) end
end
-- Signaux de tags (CollectionService) : créés à la demande, déclenchés à l'ajout / au retrait d'un
-- tag d'une instance du DataModel, et à la destruction d'une instance taggée.
local tagSignals = { added = {}, removed = {} }
local function tagSignal(kind, t)
	local list = tagSignals[kind]
	if list[t] == nil then
		list[t] = M.newSignal()
	end
	return list[t]
end
M.tagSignal = tagSignal
local function isInGame(inst)
	local node = inst
	while node do
		if rawget(node, "ClassName") == "DataModel" then return true end
		node = rawget(node, "_props").Parent
	end
	return false
end
function methods.Destroy(self)
	rawset(self, "_destroyed", true)
	for _, ch in ipairs(methods.GetChildren(self)) do methods.Destroy(ch) end
	local wasInGame = isInGame(self)
	self.Parent = nil
	local set = tags[self]
	tags[self] = nil
	if set and wasInGame then
		for t in pairs(set) do
			if tagSignals.removed[t] then tagSignals.removed[t]:Fire(self) end
		end
	end
end
function methods.Remove(self) self.Parent = nil end
function methods.Clone(self)
	local copy = Instance.new(rawget(self, "ClassName"))
	for k, v in pairs(rawget(self, "_props")) do
		if k ~= "Parent" then rawget(copy, "_props")[k] = v end
	end
	for k, v in pairs(rawget(self, "_attrs")) do rawget(copy, "_attrs")[k] = v end
	if tags[self] then
		tags[copy] = {}
		for t in pairs(tags[self]) do tags[copy][t] = true end
	end
	for _, ch in ipairs(rawget(self, "_children")) do
		local c = methods.Clone(ch)
		c.Parent = copy
	end
	return copy
end
-- Signaux de changement d'attribut : déclenchés (dans un thread, comme Roblox) quand la valeur change.
local function attributeSignal(self, k)
	local signals = rawget(self, "_attrSignals")
	if signals == nil then
		signals = {}
		rawset(self, "_attrSignals", signals)
	end
	local s = signals[k]
	if s == nil then
		s = { _handlers = {} }
		function s:Connect(fn)
			local conn = { Connected = true }
			function conn:Disconnect()
				conn.Connected = false
			end
			table.insert(self._handlers, { fn = fn, conn = conn })
			return conn
		end
		function s:Once(fn)
			local conn
			conn = self:Connect(function(...)
				conn:Disconnect()
				fn(...)
			end)
			return conn
		end
		function s:Fire(...)
			for _, h in ipairs(table.clone(self._handlers)) do
				if h.conn.Connected then
					M.task.spawn(h.fn, ...)
				end
			end
		end
		function s:Wait()
			return nil
		end
		signals[k] = s
	end
	return s
end
function methods.SetAttribute(self, k, v)
	local attrs = rawget(self, "_attrs")
	local old = attrs[k]
	attrs[k] = v
	if old ~= v then
		local signals = rawget(self, "_attrSignals")
		local s = signals and signals[k]
		if s then
			s:Fire()
		end
	end
end
function methods.GetAttribute(self, k) return rawget(self, "_attrs")[k] end
function methods.GetAttributes(self)
	local t = {}
	for k, v in pairs(rawget(self, "_attrs")) do t[k] = v end
	return t
end
function methods.GetAttributeChangedSignal(self, k) return attributeSignal(self, k) end
function methods.GetPropertyChangedSignal() return M.newSignal() end
function methods.AddTag(self, t)
	tags[self] = tags[self] or {}
	local had = tags[self][t]
	tags[self][t] = true
	if not had and isInGame(self) and tagSignals.added[t] then tagSignals.added[t]:Fire(self) end
end
function methods.RemoveTag(self, t)
	if tags[self] and tags[self][t] then
		tags[self][t] = nil
		if isInGame(self) and tagSignals.removed[t] then tagSignals.removed[t]:Fire(self) end
	end
end
function methods.HasTag(self, t) return tags[self] ~= nil and tags[self][t] == true end
function methods.GetTags(self)
	local out = {}
	if tags[self] then for t in pairs(tags[self]) do table.insert(out, t) end end
	return out
end
function methods.GetFullName(self)
	local parts = {}
	local n = self
	while n do
		table.insert(parts, 1, n.Name)
		n = rawget(n, "_props").Parent
	end
	return table.concat(parts, ".")
end
-- Modèles : pivot = PrimaryPart ou WorldPivot
local function boundingBox(model)
	local mn, mx = nil, nil
	for _, d in ipairs(methods.GetDescendants(model)) do
		if isA(d, "BasePart") then
			local c, s = d.CFrame, d.Size
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = c * v3(s.X / 2 * sx, s.Y / 2 * sy, s.Z / 2 * sz)
						mn = if mn then Vector3.Min(mn, p) else p
						mx = if mx then Vector3.Max(mx, p) else p
					end
				end
			end
		end
	end
	return mn or v3(), mx or v3()
end
function methods.GetBoundingBox(self)
	local mn, mx = boundingBox(self)
	return CFrame.new((mn + mx) / 2), mx - mn
end
function methods.GetExtentsSize(self)
	local mn, mx = boundingBox(self)
	return mx - mn
end
function methods.GetPivot(self)
	if isA(self, "BasePart") then return self.CFrame end
	local pp = rawget(self, "_props").PrimaryPart
	if pp then return pp.CFrame end
	local wp = rawget(self, "_props").WorldPivot
	if wp then return wp end
	local c = methods.GetBoundingBox(self)
	return c
end
function methods.PivotTo(self, target)
	if isA(self, "BasePart") then
		self.CFrame = target
		return
	end
	local pivot = methods.GetPivot(self)
	local delta = target * CFrame.Inverse(pivot)
	for _, d in ipairs(methods.GetDescendants(self)) do
		if isA(d, "BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	if rawget(self, "_props").WorldPivot then rawget(self, "_props").WorldPivot = target end
end
function methods.MoveTo(self, pos)
	local pivot = methods.GetPivot(self)
	methods.PivotTo(self, CFrame.new(pos) * pivot.Rotation)
end
function methods.SetPrimaryPartCFrame(self, c) methods.PivotTo(self, c) end
function methods.ScaleTo() end
function methods.GetScale() return 1 end
function methods.BreakJoints() end
function methods.MakeJoints() end
function methods.SetNetworkOwner() end
function methods.CanSetNetworkOwnership() return true end
function methods.GetMass(self) local s = self.Size return s.X * s.Y * s.Z end
function methods.ApplyImpulse() end

-- Terrain
local terrainOps = {}
M.terrainOps = terrainOps
local function terrainOp(kind)
	return function(self, ...)
		table.insert(terrainOps, { kind = kind, args = { ... } })
	end
end
methods.FillBlock = terrainOp("FillBlock")
methods.FillBall = terrainOp("FillBall")
methods.FillCylinder = terrainOp("FillCylinder")
methods.FillWedge = terrainOp("FillWedge")
methods.FillRegion = terrainOp("FillRegion")
methods.ReplaceMaterial = terrainOp("ReplaceMaterial")
methods.Clear = function(self) table.insert(terrainOps, { kind = "Clear", args = {} }) end
methods.SetMaterialColor = terrainOp("SetMaterialColor")

Imt.__index = function(self, k)
	local props = rawget(self, "_props")
	local v = props[k]
	if v ~= nil then return v end
	if k == "Position" and props.CFrame ~= nil and isA(self, "BasePart") then return props.CFrame.Position end
	if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then return v3() end
	local m = methods[k]
	if m then return m end
	-- enfant par nom (avant les signaux devinés : un module "GameEvents" n'est pas un signal)
	for _, ch in ipairs(rawget(self, "_children")) do
		if ch.Name == k then return ch end
	end
	-- signaux
	if type(k) == "string" and (k:match("^%u") and (k:find("Changed") or k:find("Added") or k:find("Removed") or k:find("Removing") or k:find("Triggered") or k:find("Touched") or k:find("Activated") or k:find("Died") or k:find("Event") or k:find("Clicked") or k:find("Ended") or k:find("Began") or k:find("Destroying") or k:find("Running") or k:find("Invoke") or k:find("Loaded") or k:find("^Mouse") or k:find("^Selection") or k:find("Focus") or k:find("^Input") or k:find("^Touch") or k:find("Gained") or k:find("Lost") or k:find("Fired") or k:find("Reached") or k:find("Completed") or k:find("Unequipped") or k:find("Equipped"))) then
		local s = M.newSignal()
		props[k] = s
		return s
	end
	-- enfant par nom
	for _, ch in ipairs(rawget(self, "_children")) do
		if ch.Name == k then return ch end
	end
	return nil
end
Imt.__newindex = function(self, k, v)
	local props = rawget(self, "_props")
	if k == "Parent" then
		local old = props.Parent
		if old == v then return end
		if old then
			local ch = rawget(old, "_children")
			for i, c in ipairs(ch) do
				if c == self then table.remove(ch, i) break end
			end
		end
		props.Parent = v
		if v then table.insert(rawget(v, "_children"), self) end
		return
	end
	if k == "Position" and isA(self, "BasePart") then
		local c = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(v) * c.Rotation
		return
	end
	if k == "Orientation" and isA(self, "BasePart") then
		local c = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(c.Position) * CFrame.fromEulerAnglesYXZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		props.Orientation = v
		return
	end
	if k == "BrickColor" then props.Color = v.Color end
	props[k] = v
end
Imt.__tostring = function(self) return rawget(self, "_props").Name end

function Instance.new(className, parent)
	nextId += 1
	local inst = setmetatable({ ClassName = className, _props = { Name = className }, _attrs = {}, _children = {}, _id = nextId }, Imt)
	local defaults = DEFAULTS[className]
	if defaults then
		for k, v in pairs(defaults) do rawget(inst, "_props")[k] = v end
	end
	if isA(inst, "BasePart") then
		rawget(inst, "_props").CFrame = CFrame.new()
		rawget(inst, "_props").Color = Color3.fromRGB(163, 162, 165)
		rawget(inst, "_props").Material = Enum.Material.Plastic
	end
	table.insert(allInstances, inst)
	if parent then inst.Parent = parent end
	return inst
end
M.Instance = Instance
M.allInstances = allInstances
M.tags = tags

--------------------------------------------------------------------------------
-- Signaux, task, services
--------------------------------------------------------------------------------
function M.newSignal()
	local s = { _handlers = {} }
	function s:Connect(fn)
		table.insert(self._handlers, fn)
		local conn = { Connected = true }
		function conn:Disconnect() self.Connected = false end
		return conn
	end
	s.Once = s.Connect
	function s:Fire(...)
		for _, h in ipairs(self._handlers) do h(...) end
	end
	function s:Wait() return nil end
	return s
end

M.task = {
	wait = function() return 0 end,
	spawn = function(f, ...) if type(f) == "function" then f(...) end end,
	defer = function(f, ...) if type(f) == "function" then f(...) end end,
	delay = function() end,
	cancel = function() end,
}

local function service(className, name)
	local s = Instance.new(className)
	s.Name = name or className
	return s
end

local game = service("DataModel", "game")
local workspace = service("Workspace")
workspace.Parent = game
local terrain = service("Terrain")
terrain.Parent = workspace
local services = {
	Workspace = workspace,
	ReplicatedStorage = service("ReplicatedStorage"),
	ServerScriptService = service("ServerScriptService"),
	ServerStorage = service("ServerStorage"),
	Lighting = service("Lighting"),
	StarterPlayer = service("StarterPlayer"),
	Players = service("Players"),
	SoundService = service("SoundService"),
}
for _, s in pairs(services) do
	if s ~= workspace then s.Parent = game end
end
local CollectionService = {
	AddTag = function(_, inst, t) methods.AddTag(inst, t) end,
	RemoveTag = function(_, inst, t) methods.RemoveTag(inst, t) end,
	HasTag = function(_, inst, t) return methods.HasTag(inst, t) end,
	GetTagged = function(_, t)
		local out = {}
		for inst, set in pairs(tags) do
			if set[t] and not rawget(inst, "_destroyed") then table.insert(out, inst) end
		end
		return out
	end,
	GetTags = function(_, inst) return methods.GetTags(inst) end,
	GetInstanceAddedSignal = function(_, t) return tagSignal("added", t) end,
	GetInstanceRemovedSignal = function(_, t) return tagSignal("removed", t) end,
}
local RunService = {
	IsServer = function() return true end,
	IsClient = function() return false end,
	IsStudio = function() return true end,
	IsRunning = function() return false end,
	IsEdit = function() return true end,
	Heartbeat = M.newSignal(),
	RenderStepped = M.newSignal(),
	Stepped = M.newSignal(),
}
local ChangeHistoryService = {
	SetWaypoint = function() end,
	TryBeginRecording = function() return "rec" end,
	FinishRecording = function() end,
}
local HttpService = {
	GenerateGUID = function() nextId += 1 return "guid-" .. nextId end,
	JSONEncode = function() return "{}" end,
}
-- Chargement des assets audio (simulation) : M.failingAssets[id] = true fait échouer un ID ;
-- M.assetLengths[id] fixe la durée réelle du son chargé ; M.assetInfo[id] = { Name, Creator }.
M.failingAssets = {}
M.assetLengths = {}
M.assetInfo = {}
M.preloadCount = 0
M.preloadedIds = {}
local function numericId(contentId)
	return tostring(contentId):match("(%d+)$") or tostring(contentId)
end
local ContentProvider = {
	PreloadAsync = function(_, list, callback)
		for _, inst in ipairs(list) do
			M.preloadCount += 1
			local contentId = inst.SoundId
			local id = numericId(contentId)
			M.preloadedIds[id] = true
			local failed = M.failingAssets[id] == true
			inst.IsLoaded = not failed
			inst.TimeLength = if failed then 0 else (M.assetLengths[id] or 10)
			if callback then
				callback(contentId, if failed then Enum.AssetFetchStatus.Failure else Enum.AssetFetchStatus.Success)
			end
		end
	end,
}
local MarketplaceService = {
	GetProductInfo = function(_, id)
		local info = M.assetInfo[tostring(id)]
		if info == nil then error("asset inconnu (simulation)") end
		return info
	end,
}
function game.GetService(_, name)
	if services[name] then return services[name] end
	if name == "ContentProvider" then return ContentProvider end
	if name == "MarketplaceService" then return MarketplaceService end
	if name == "CollectionService" then return CollectionService end
	if name == "RunService" then return RunService end
	if name == "ChangeHistoryService" then return ChangeHistoryService end
	if name == "HttpService" then return HttpService end
	local s = service(name)
	s.Parent = game
	services[name] = s
	return s
end
rawget(game, "_props").GetService = game.GetService
M.game = game
M.workspace = workspace
M.services = services

local typeofOrig = typeof
function M.typeof(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and mt.__type then return mt.__type end
	return typeofOrig(v)
end

return M
