--!strict
--[[
	PropsBuildings
	Architecture paramétrée : maison à colombages (intacte / délabrée / effondrée, deux styles de
	toit), toit à deux pans, pignon, mur à baies, mur écroulé, arche (plein cintre ou gothique),
	escalier, rampe, colonne, cheminée isolée.

	Convention : `base` est un CFrame LOCAL au sol ; pour un bâtiment, c'est le centre de l'emprise
	et son LookVector regarde la RUE (la façade avec la porte est du côté -Z local).
	Les murs ont leur face extérieure du côté -Z de leur propre repère.

	API :
		PropsBuildings.house(parent, base, random, options?): HouseResult
		PropsBuildings.gableRoof(parent, frame, span, length, height, look, options?)
		PropsBuildings.gable(parent, frame, width, height, thickness, look)
		PropsBuildings.panelWall(parent, frame, length, height, openings, look, timber?, options?)
		PropsBuildings.ruinedWall(parent, from, to, height, thickness, random, look?)
		PropsBuildings.archway(parent, base, width, height, thickness, look, pointed?)
		PropsBuildings.stairs(parent, from, to, width, look, options?)
		PropsBuildings.ramp(parent, from, to, width, look)
		PropsBuildings.pillar(parent, base, height, diameter, look)
		PropsBuildings.chimney(parent, base, height, look?)
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local PropsVillage = require(script.Parent.PropsVillage)

type Look = Palette.Look

export type HouseState = "intact" | "damaged" | "collapsed"
export type RoofStyle = "front" | "side" -- front : pignon sur rue ; side : faîtage parallèle à la rue

export type HouseOptions = {
	width: number?, -- le long de la façade (défaut 14)
	depth: number?, -- défaut 12
	floors: number?, -- 1 ou 2 (défaut 2)
	state: HouseState?, -- défaut "damaged"
	roof: RoofStyle?, -- défaut "front"
	pitch: number?, -- hauteur du toit / demi-portée (défaut 1,25 : toits pointus)
	plinth: number?, -- hauteur du sol intérieur au-dessus de `base` (défaut 0,9)
	doorOffset: number?, -- décalage de la porte le long de la façade
	chimney: boolean?, -- défaut vrai
	lit: boolean?, -- fenêtres encore éclairées (Neon chaud)
	name: string?,
	wallLook: Look?,
	roofLook: Look?,
}

export type HouseResult = {
	model: Model,
	floorY: number, -- hauteur LOCALE du sol intérieur (relative à base)
	door: CFrame, -- au sol, devant la porte, regard vers la rue
	width: number,
	depth: number,
	height: number, -- hauteur totale jusqu'au faîtage
}

export type Opening = {
	x0: number, -- bord gauche (le long du mur, centre du mur = 0)
	x1: number,
	y0: number, -- bas (0 = pied du mur)
	y1: number,
	kind: ("door" | "window")?,
}

export type WallOptions = {
	random: Random?,
	jagged: number?, -- 0..1 : arase irrégulière (mur effondré)
	missing: number?, -- 0..1 : probabilité qu'un panneau plein ait brûlé (ossature visible)
	thickness: number?, -- défaut 0,8
	braces: boolean?, -- croix de Saint-André dans les panneaux larges (défaut vrai)
}

export type RoofOptions = {
	thickness: number?,
	overhang: number?, -- débord latéral (défaut 1,2)
	gableOverhang: number?, -- débord en pignon (défaut 0,8)
	damage: number?, -- 0 = intact ; > 0 : un pan percé, chevrons visibles
	random: Random?,
	ridgeLook: Look?,
}

export type StairOptions = {
	maxRise: number?, -- hauteur max d'une marche (défaut 1)
	sides: Look?, -- murets latéraux
}

local PropsBuildings = {}

local DECOR: Kit.PartOptions = { decor = true }
local WALL_THICKNESS = 0.8
local FIRST_FLOOR_HEIGHT = 9
local UPPER_FLOOR_HEIGHT = 8
local JETTY = 1

--------------------------------------------------------------------------------
-- Murs
--------------------------------------------------------------------------------

type BayKind = "solid" | "door" | "window"
type Bay = { x0: number, x1: number, solid: boolean, y0: number, y1: number, kind: BayKind }

-- Découpe un mur en travées pleines et travées percées.
local function splitBays(length: number, height: number, openings: { Opening }): { Bay }
	table.sort(openings, function(a, b)
		return a.x0 < b.x0
	end)
	local bays: { Bay } = {}
	local cursor = -length / 2
	for _, o in openings do
		if o.x0 > cursor + 0.05 then
			table.insert(bays, { x0 = cursor, x1 = o.x0, solid = true, y0 = 0, y1 = height, kind = "solid" })
		end
		local kind: BayKind = if o.kind == "door" then "door" else "window"
		table.insert(bays, { x0 = o.x0, x1 = o.x1, solid = false, y0 = o.y0, y1 = o.y1, kind = kind })
		cursor = o.x1
	end
	if cursor < length / 2 - 0.05 then
		table.insert(bays, { x0 = cursor, x1 = length / 2, solid = true, y0 = 0, y1 = height, kind = "solid" })
	end
	return bays
end

--[[
	Mur à baies (torchis + ossature de bois). `frame` = centre du PIED du mur, le mur court le long
	du X local, face extérieure vers -Z local. `timber` = nil : mur sans ossature (pierre).
	Retourne la liste des hauteurs d'arase de chaque travée (utile pour un mur effondré).
]]
function PropsBuildings.panelWall(
	parent: Instance,
	frame: CFrame,
	length: number,
	height: number,
	openings: { Opening },
	look: Look,
	timber: Look?,
	options: WallOptions?
)
	local opts: WallOptions = options or {}
	local random = opts.random
	local jagged = opts.jagged or 0
	local missing = opts.missing or 0
	local t = opts.thickness or WALL_THICKNESS
	local bays = splitBays(length, height, openings)
	local outer = -(t / 2 + 0.12)

	for _, bay in bays do
		local w = bay.x1 - bay.x0
		local cx = (bay.x0 + bay.x1) / 2
		local top = height
		if jagged > 0 and random then
			top = height * random:NextNumber(1 - jagged, 1 - jagged * 0.25)
		end
		if bay.solid then
			local burnt = random ~= nil and missing > 0 and random:NextNumber() < missing
			if not burnt then
				Kit.part(parent, frame * CFrame.new(cx, top / 2, 0), Vector3.new(w, top, t), look)
				if jagged > 0 and random and w > 1.5 then
					-- Arase cassée en biais.
					local wedgeHeight = math.min(2.5, top * 0.3)
					local flip = if random:NextNumber() < 0.5 then 90 else -90
					Kit.wedge(parent, frame * CFrame.new(cx, top + wedgeHeight / 2, 0) * CFrame.Angles(0, math.rad(flip), 0), Vector3.new(t, wedgeHeight, w), look, DECOR)
				end
			end
			if timber and opts.braces ~= false and jagged == 0 and w >= 3.2 then
				Kit.beam(parent, (frame * CFrame.new(bay.x0 + 0.35, 0.7, outer)).Position, (frame * CFrame.new(bay.x1 - 0.35, top - 0.7, outer)).Position, 0.45, 0.3, timber, DECOR)
			end
		else
			if bay.y0 > 0.05 then
				Kit.part(parent, frame * CFrame.new(cx, bay.y0 / 2, 0), Vector3.new(w, bay.y0, t), look)
			end
			local keepLintel = jagged == 0 or (random ~= nil and random:NextNumber() > jagged)
			if bay.y1 < top - 0.05 and keepLintel then
				Kit.part(parent, frame * CFrame.new(cx, (bay.y1 + top) / 2, 0), Vector3.new(w, top - bay.y1, t), look)
			end
			if timber then
				Kit.part(parent, frame * CFrame.new(cx, bay.y1 + 0.2, outer), Vector3.new(w + 0.6, 0.4, 0.3), timber, DECOR)
				if bay.y0 > 0.05 then
					Kit.part(parent, frame * CFrame.new(cx, bay.y0 - 0.15, outer - 0.1), Vector3.new(w + 0.6, 0.3, 0.5), timber, DECOR)
				end
			end
		end
	end

	if timber then
		-- Poteaux aux extrémités et aux bords des portes, sablière basse et haute.
		local postXs = { -length / 2 + 0.4, length / 2 - 0.4 }
		for _, o in openings do
			if o.kind == "door" then
				table.insert(postXs, o.x0 - 0.3)
				table.insert(postXs, o.x1 + 0.3)
			end
		end
		for _, x in postXs do
			local postTop = height
			if jagged > 0 and random then
				postTop = height * random:NextNumber(1 - jagged, 1)
			end
			Kit.part(parent, frame * CFrame.new(x, postTop / 2, outer), Vector3.new(0.7, postTop, 0.3), timber, { decor = true, name = "Post" })
		end
		Kit.part(parent, frame * CFrame.new(0, 0.3, outer), Vector3.new(length, 0.6, 0.3), timber, DECOR)
		if jagged == 0 then
			Kit.part(parent, frame * CFrame.new(0, height - 0.3, outer), Vector3.new(length + 0.2, 0.6, 0.35), timber, DECOR)
		end
	end
end

-- Pignon triangulaire (deux coins dos à dos). `frame` = centre de la base, face extérieure -Z.
function PropsBuildings.gable(parent: Instance, frame: CFrame, width: number, height: number, thickness: number, look: Look)
	local size = Vector3.new(thickness, height, width / 2)
	Kit.wedge(parent, frame * CFrame.new(-width / 4, height / 2, 0) * CFrame.Angles(0, math.rad(90), 0), size, look)
	Kit.wedge(parent, frame * CFrame.new(width / 4, height / 2, 0) * CFrame.Angles(0, math.rad(-90), 0), size, look)
end

--[[
	Toit à deux pans. `frame` = centre du haut des murs ; le faîtage suit le Z local.
	`span` = largeur couverte (X), `length` = longueur du faîtage (Z), `height` = hauteur du faîtage.
	`damage` > 0 : le pan droit est percé (tronçons manquants, chevrons calcinés apparents).
]]
function PropsBuildings.gableRoof(parent: Instance, frame: CFrame, span: number, length: number, height: number, look: Look, options: RoofOptions?)
	local opts: RoofOptions = options or {}
	local t = opts.thickness or 0.6
	local overhang = opts.overhang or 1.2
	local lz = length + 2 * (opts.gableOverhang or 0.8)
	local half = span / 2
	local theta = math.atan2(height, half)
	local run = half + overhang
	local slabLength = run / math.cos(theta) + t
	local eaveY = -overhang * math.tan(theta)
	local damage = opts.damage or 0
	local random = opts.random

	for _, side in { -1, 1 } do
		local mx = side * run / 2
		local my = (eaveY + height) / 2
		local normal = Vector3.new(side * math.sin(theta), math.cos(theta), 0)
		local slabFrame = frame * CFrame.new(mx + normal.X * t / 2, my + normal.Y * t / 2, 0) * CFrame.Angles(0, 0, -side * theta)
		if side == 1 and damage > 0 and random then
			-- Pan percé : on garde des tronçons, les chevrons restent visibles.
			local pieces = 4
			local pieceLength = lz / pieces
			for i = 1, pieces do
				local z = -lz / 2 + (i - 0.5) * pieceLength
				if random:NextNumber() > damage then
					Kit.part(parent, slabFrame * CFrame.new(0, 0, z), Vector3.new(slabLength, t, pieceLength + 0.05), look)
				else
					for k = -1, 1, 2 do
						local rafter = slabFrame * CFrame.new(0, -t, z + k * pieceLength * 0.25)
						Kit.part(parent, rafter, Vector3.new(slabLength, 0.5, 0.45), Palette.charredWood, DECOR)
					end
				end
			end
		else
			Kit.part(parent, slabFrame, Vector3.new(slabLength, t, lz), look)
		end
	end
	Kit.part(parent, frame * CFrame.new(0, height + t * 0.6, 0), Vector3.new(0.7, 0.7, lz + 0.2), opts.ridgeLook or Palette.timber, DECOR)
end

--------------------------------------------------------------------------------
-- Maison à colombages
--------------------------------------------------------------------------------

local function frontOpenings(width: number, doorX: number, doorHeight: number): { Opening }
	local openings: { Opening } = { { x0 = doorX - 2, x1 = doorX + 2, y0 = 0, y1 = doorHeight, kind = "door" } }
	local leftSpace = (doorX - 2) - (-width / 2)
	if leftSpace >= 4.5 then
		local cx = -width / 2 + leftSpace / 2
		table.insert(openings, { x0 = cx - 1.2, x1 = cx + 1.2, y0 = 3.2, y1 = 6.2, kind = "window" })
	end
	local rightSpace = width / 2 - (doorX + 2)
	if rightSpace >= 4.5 then
		local cx = width / 2 - rightSpace / 2
		table.insert(openings, { x0 = cx - 1.2, x1 = cx + 1.2, y0 = 3.2, y1 = 6.2, kind = "window" })
	end
	return openings
end

local function centeredWindow(y0: number, y1: number, offset: number?): { Opening }
	local x = offset or 0
	return { { x0 = x - 1.2, x1 = x + 1.2, y0 = y0, y1 = y1, kind = "window" } }
end

-- Remplit les fenêtres d'une façade : vitre chaude (lit), volets, ou rien.
local function dressWindows(parent: Instance, frame: CFrame, openings: { Opening }, state: HouseState, lit: boolean, random: Random)
	for _, o in openings do
		if o.kind == "window" then
			local cx, cy = (o.x0 + o.x1) / 2, (o.y0 + o.y1) / 2
			local w, h = o.x1 - o.x0, o.y1 - o.y0
			if lit and state == "intact" then
				Kit.part(parent, frame * CFrame.new(cx, cy, 0.1), Vector3.new(w, h, 0.2), Palette.lanternGlow, { decor = true, transparency = 0.2, name = "WarmWindow" })
			elseif state ~= "collapsed" and random:NextNumber() < 0.45 then
				-- Volet arraché, pendu par un gond.
				local hinge = frame * CFrame.new(o.x0 - 0.1, cy, -0.6) * CFrame.Angles(0, 0, math.rad(random:NextNumber(10, 35)))
				Kit.part(parent, hinge * CFrame.new(-w / 4, -h * 0.15, 0), Vector3.new(w / 2, h, 0.2), Palette.burntWood, DECOR)
			end
		end
	end
end

--[[
	Maison à colombages paramétrée. ~40 à 90 Parts selon l'état.
	intact    : toit complet, porte fermée, fenêtres (éventuellement éclairées) ;
	damaged   : toit percé, panneaux de l'étage brûlés, porte arrachée, suie ;
	collapsed : murs du rez-de-chaussée arasés, plus d'étage ni de toit, cheminée debout,
	            poutres calcinées et gravats à l'intérieur.
]]
function PropsBuildings.house(parent: Instance, base: CFrame, random: Random, options: HouseOptions?): HouseResult
	local opts: HouseOptions = options or {}
	local width = opts.width or 14
	local depth = opts.depth or 12
	local state: HouseState = opts.state or "damaged"
	local floors = if state == "collapsed" then 1 else math.clamp(opts.floors or 2, 1, 2)
	local roofStyle: RoofStyle = opts.roof or "front"
	local plinth = opts.plinth or 0.9
	local lit = opts.lit == true
	local doorX = math.clamp(opts.doorOffset or 0, -width / 2 + 2.6, width / 2 - 2.6)
	local t = WALL_THICKNESS
	local model = Kit.model(parent, opts.name or "House", base)

	local wallLook = opts.wallLook
		or (if state == "intact" then Palette.plaster elseif state == "damaged" then Palette.plasterSooty else Palette.plasterBurnt)
	local upperLook = if state == "intact" then Palette.mix(wallLook, Palette.plasterSooty, 0.3) else Palette.darken(wallLook, 0.8)
	local timber = if state == "intact" then Palette.timber else Palette.charredWood
	local roofLook = opts.roofLook or (if state == "intact" then Palette.roofSlate else Palette.roofBurnt)

	-- Soubassement de pierre (enfoncé dans le sol) et plancher.
	Kit.part(model, base * CFrame.new(0, (plinth - 1.5) / 2, 0), Vector3.new(width + 0.6, plinth + 1.5, depth + 0.6), Palette.cobble, { name = "Plinth" })
	if state ~= "collapsed" then
		Kit.part(model, base * CFrame.new(0, plinth + 0.08, 0), Vector3.new(width - 1.4, 0.16, depth - 1.4), Palette.burntWood, DECOR)
	end
	if plinth > 1.05 then
		-- Marches devant la porte (1 stud max chacune).
		local steps = math.ceil(plinth)
		for i = 1, steps - 1 do
			local h = plinth - i * (plinth / steps)
			Kit.part(model, base * CFrame.new(doorX, h / 2 - 0.25, -depth / 2 - 0.3 - i * 1.1), Vector3.new(4.4, h + 0.5, 1.2), Palette.stoneLight)
		end
	end

	-- Rez-de-chaussée.
	local h1 = FIRST_FLOOR_HEIGHT
	local floorFrame = base * CFrame.new(0, plinth, 0)
	local jagged = if state == "collapsed" then 0.7 else 0
	local frontFrame = floorFrame * CFrame.new(0, 0, -depth / 2 + t / 2)
	local backFrame = floorFrame * CFrame.new(0, 0, depth / 2 - t / 2) * CFrame.Angles(0, math.pi, 0)
	local leftFrame = floorFrame * CFrame.new(-width / 2 + t / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	local rightFrame = floorFrame * CFrame.new(width / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	local front = frontOpenings(width, doorX, 7.2)
	local sideWindows = if depth >= 10 then centeredWindow(3.2, 6.2) else {}
	local backWindows = centeredWindow(3.2, 6.2, random:NextNumber(-width / 4, width / 4))
	local wallOptions: WallOptions = { random = random, jagged = jagged }
	PropsBuildings.panelWall(model, frontFrame, width, h1, front, wallLook, timber, wallOptions)
	PropsBuildings.panelWall(model, backFrame, width, h1, backWindows, wallLook, timber, wallOptions)
	PropsBuildings.panelWall(model, leftFrame, depth - 2 * t, h1, table.clone(sideWindows), wallLook, timber, wallOptions)
	PropsBuildings.panelWall(model, rightFrame, depth - 2 * t, h1, table.clone(sideWindows), wallLook, timber, wallOptions)
	dressWindows(model, frontFrame, front, state, lit, random)

	-- Porte.
	local doorFrame = frontFrame * CFrame.new(doorX, 0, 0)
	if state == "intact" then
		Kit.part(model, doorFrame * CFrame.new(0, 3.6, 0.1), Vector3.new(3.8, 7.2, 0.35), Palette.oldWood, { name = "Door" })
		for _, y in { 1.6, 5.6 } do
			Kit.part(model, doorFrame * CFrame.new(0, y, -0.12), Vector3.new(3.6, 0.3, 0.1), Palette.iron, DECOR)
		end
	elseif state == "damaged" and random:NextNumber() < 0.6 then
		local hinge = doorFrame * CFrame.new(-1.9, 0, -0.2) * CFrame.Angles(0, math.rad(random:NextNumber(55, 100)), 0)
		Kit.part(model, hinge * CFrame.new(1.9, 3.5, 0) * CFrame.Angles(0, 0, math.rad(4)), Vector3.new(3.8, 6.8, 0.35), Palette.burntWood, DECOR)
	end

	local wallTop = plinth + h1
	local roofDepth = depth
	if floors == 2 then
		-- Étage en encorbellement (débord de JETTY studs devant et derrière).
		local h2 = UPPER_FLOOR_HEIGHT
		roofDepth = depth + 2 * JETTY
		Kit.part(model, base * CFrame.new(0, wallTop + 0.3, 0), Vector3.new(width + 0.2, 0.6, roofDepth), timber, { name = "Joists" })
		local upperFrame = base * CFrame.new(0, wallTop + 0.6, 0)
		local missing = if state == "damaged" then 0.35 else 0
		local upperOptions: WallOptions = { random = random, missing = missing }
		local upperFront = upperFrame * CFrame.new(0, 0, -roofDepth / 2 + t / 2)
		local frontUpper: { Opening } = {
			{ x0 = -width / 4 - 1.2, x1 = -width / 4 + 1.2, y0 = 2.4, y1 = 5.4, kind = "window" },
			{ x0 = width / 4 - 1.2, x1 = width / 4 + 1.2, y0 = 2.4, y1 = 5.4, kind = "window" },
		}
		PropsBuildings.panelWall(model, upperFront, width, h2, frontUpper, upperLook, timber, upperOptions)
		PropsBuildings.panelWall(model, upperFrame * CFrame.new(0, 0, roofDepth / 2 - t / 2) * CFrame.Angles(0, math.pi, 0), width, h2, {}, upperLook, timber, upperOptions)
		PropsBuildings.panelWall(model, upperFrame * CFrame.new(-width / 2 + t / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), roofDepth - 2 * t, h2, {}, upperLook, timber, upperOptions)
		PropsBuildings.panelWall(model, upperFrame * CFrame.new(width / 2 - t / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), roofDepth - 2 * t, h2, {}, upperLook, timber, upperOptions)
		dressWindows(model, upperFront, frontUpper, state, lit, random)
		-- Consoles sous l'encorbellement.
		for _, x in { -width / 2 + 1, width / 2 - 1 } do
			Kit.wedge(model, base * CFrame.new(x, wallTop - 0.4, -depth / 2 - 0.5) * CFrame.Angles(math.pi, 0, 0), Vector3.new(0.6, 1.2, 1), timber, DECOR)
		end
		wallTop += 0.6 + h2
	end

	-- Toit (ou ce qu'il en reste).
	local pitch = opts.pitch or 1.25
	local roofHeight = 0
	if state ~= "collapsed" then
		local topFrame = base * CFrame.new(0, wallTop, 0)
		local span, length, gableFrames
		if roofStyle == "front" then
			span, length = width, roofDepth
			gableFrames = {
				topFrame * CFrame.new(0, 0, -roofDepth / 2 + t / 2),
				topFrame * CFrame.new(0, 0, roofDepth / 2 - t / 2) * CFrame.Angles(0, math.pi, 0),
			}
		else
			span, length = roofDepth, width
			topFrame *= CFrame.Angles(0, math.rad(90), 0)
			gableFrames = {
				base * CFrame.new(-width / 2 + t / 2, wallTop, 0) * CFrame.Angles(0, math.rad(90), 0),
				base * CFrame.new(width / 2 - t / 2, wallTop, 0) * CFrame.Angles(0, math.rad(-90), 0),
			}
		end
		roofHeight = span / 2 * pitch
		for _, gableFrame in gableFrames do
			PropsBuildings.gable(model, gableFrame, span - 0.2, roofHeight, t, upperLook)
			Kit.part(model, gableFrame * CFrame.new(0, roofHeight * 0.45, -(t / 2 + 0.12)), Vector3.new(0.6, roofHeight * 0.9, 0.3), timber, DECOR)
		end
		PropsBuildings.gableRoof(model, topFrame, span, length, roofHeight, roofLook, {
			damage = if state == "damaged" then 0.55 else 0,
			random = random,
		})
	else
		-- Effondrée : chevrons calcinés tombés en travers, gravats et cendres.
		for _ = 1, 2 do
			local a = base * CFrame.new(random:NextNumber(-width / 3, width / 3), plinth + h1 * 0.5, random:NextNumber(-depth / 3, depth / 3))
			local b = base * CFrame.new(random:NextNumber(-width / 2, width / 2), plinth + 0.3, random:NextNumber(-depth / 2, depth / 2))
			Kit.beam(model, a.Position, b.Position, 0.8, 0.8, Palette.charredWood, DECOR)
		end
		PropsVillage.rubble(model, base * CFrame.new(0, plinth, 0), math.min(width, depth) * 0.4, 7, random, wallLook)
		PropsVillage.charredBeams(model, base * CFrame.new(random:NextNumber(-2, 2), plinth, random:NextNumber(-2, 2)), math.min(width, depth) * 0.7, random)
	end

	-- Cheminée de pierre (reste debout même quand tout s'est effondré).
	if opts.chimney ~= false then
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local chimneyHeight = if state == "collapsed" then plinth + h1 + 5 else wallTop + roofHeight * 0.75 + 2
		PropsBuildings.chimney(model, base * CFrame.new(side * (width / 2 + 0.9), 0, random:NextNumber(-depth / 4, depth / 4)), chimneyHeight)
	end

	return {
		model = model,
		floorY = plinth,
		door = base * CFrame.new(doorX, 0, -depth / 2 - 2.5),
		width = width,
		depth = depth,
		height = wallTop + roofHeight,
	}
end

--------------------------------------------------------------------------------
-- Ruines, arches, accès
--------------------------------------------------------------------------------

-- Cheminée de pierre isolée (`base` au sol).
function PropsBuildings.chimney(parent: Instance, base: CFrame, height: number, look: Look?)
	local stone = look or Palette.stone
	Kit.part(parent, base * CFrame.new(0, height / 2 - 1, 0), Vector3.new(2.2, height + 2, 2.6), stone, { name = "Chimney" })
	Kit.part(parent, base * CFrame.new(0, height + 0.25, 0), Vector3.new(2.6, 0.5, 3), Palette.soot, DECOR)
end

-- Mur de pierre écroulé de `from` à `to` (au sol) : arase en dents de scie, pierres tombées.
function PropsBuildings.ruinedWall(parent: Instance, from: Vector3, to: Vector3, height: number, thickness: number, random: Random, look: Look?): Model
	local stone = look or Palette.stone
	local model = Kit.model(parent, "RuinedWall", CFrame.new((from + to) / 2))
	local frame = Kit.facing(from, to)
	local length = (to - from).Magnitude
	local count = math.max(1, math.floor(length / 3))
	local segment = length / count
	for i = 0, count - 1 do
		local h = height * random:NextNumber(0.25, 1)
		local cf = frame.Rotation + from:Lerp(to, (i + 0.5) / count)
		-- Le mur court le long du Z de `frame` (orienté de from vers to).
		Kit.part(model, cf * CFrame.new(0, h / 2 - 0.5, 0), Vector3.new(thickness, h + 1, segment + 0.05), Palette.darken(stone, random:NextNumber(0.85, 1.1)))
		if random:NextNumber() < 0.35 then
			local side = if random:NextNumber() < 0.5 then -1 else 1
			local s = random:NextNumber(0.8, 1.6)
			local stoneCf = cf * CFrame.new(side * (thickness + random:NextNumber(0.5, 2)), s * 0.3, 0) * CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 6), 0)
			Kit.part(model, stoneCf, Vector3.new(s, s * 0.7, s), stone, DECOR)
		end
	end
	return model
end

--[[
	Arche entre deux piliers. `base` = centre au sol, l'arche regarde vers -Z (on passe en Z).
	`width` = largeur libre, `height` = hauteur libre au sommet. `pointed` : arc brisé gothique.
]]
function PropsBuildings.archway(parent: Instance, base: CFrame, width: number, height: number, thickness: number, look: Look, pointed: boolean?): Model
	local model = Kit.model(parent, "Archway", base)
	local ring = 1.6 -- épaisseur des claveaux (et largeur des piliers)
	local segments = 5 -- claveaux par demi-arc
	local e = if pointed then width * 0.25 else 0 -- décalage des centres (arc brisé)
	local innerRadius = width / 2 + e
	local spring = math.max(1, height - math.sqrt(innerRadius * innerRadius - e * e))
	local radius = innerRadius + ring / 2
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + ring / 2)
		Kit.part(model, base * CFrame.new(x, spring / 2, 0), Vector3.new(ring, spring, thickness), look, { name = "Pillar" })
		Kit.part(model, base * CFrame.new(x, 0.4, 0), Vector3.new(ring + 0.5, 0.8, thickness + 0.5), Palette.darken(look, 0.85))
		-- Demi-arc : centre en (-side * e), de l'horizontale jusqu'au sommet (x = 0).
		local cx = -side * e
		local topAngle = math.acos(math.clamp(e / radius, -1, 1))
		local previous: Vector3? = nil
		for i = 0, segments do
			local a = topAngle * i / segments -- 0 = naissance, topAngle = sommet
			local px = cx + side * math.cos(a) * radius
			local py = spring + math.sin(a) * radius
			local point = (base * CFrame.new(px, py, 0)).Position
			if previous then
				Kit.beam(model, previous, point, thickness, ring, look)
			end
			previous = point
		end
	end
	return model
end

--[[
	Escalier plein de `from` (pied, AU SOL, bord de la première marche) à `to` (palier haut).
	Marches de `maxRise` stud au plus (1 par défaut) : toujours praticable.
]]
function PropsBuildings.stairs(parent: Instance, from: Vector3, to: Vector3, width: number, look: Look, options: StairOptions?): Model
	local opts: StairOptions = options or {}
	local model = Kit.model(parent, "Stairs", CFrame.new((from + to) / 2))
	local rise = to.Y - from.Y
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local run = flat.Magnitude
	local count = math.max(1, math.ceil(math.abs(rise) / (opts.maxRise or 1)))
	local frame = Kit.flatLook(from, flat)
	local depthStep = run / count
	for i = 1, count do
		local top = from.Y + rise * i / count
		local bottom = math.min(from.Y, to.Y) - 1
		local h = top - bottom
		local z = -(i - 0.5) * depthStep
		Kit.part(model, frame * CFrame.new(0, top - h / 2 - from.Y, z), Vector3.new(width, h, depthStep + 0.05), look)
	end
	if opts.sides then
		for _, side in { -1, 1 } do
			local a = (frame * CFrame.new(side * (width / 2 + 0.5), 0.6, 0)).Position
			local b = (frame * CFrame.new(side * (width / 2 + 0.5), rise + 0.6, -run)).Position
			Kit.beam(model, a, b, 1, 1.6, opts.sides)
		end
	end
	return model
end

-- Rampe en coin (WedgePart) de `from` (bas) à `to` (haut), points au sol.
function PropsBuildings.ramp(parent: Instance, from: Vector3, to: Vector3, width: number, look: Look): WedgePart
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local rise = to.Y - from.Y
	local middle = Vector3.new((from.X + to.X) / 2, from.Y + rise / 2, (from.Z + to.Z) / 2)
	local frame = CFrame.lookAt(middle, middle - flat)
	return Kit.wedge(parent, frame, Vector3.new(width, math.max(rise, 0.2), flat.Magnitude), look, { name = "Ramp" })
end

-- Colonne entière : base, fût, chapiteau.
function PropsBuildings.pillar(parent: Instance, base: CFrame, height: number, diameter: number, look: Look): Model
	local model = Kit.model(parent, "Pillar", base)
	Kit.part(model, base * CFrame.new(0, 0.6, 0), Vector3.new(diameter + 1, 1.2, diameter + 1), Palette.darken(look, 0.85))
	Kit.column(model, base * CFrame.new(0, 1.2, 0), height - 2.4, diameter, look)
	Kit.part(model, base * CFrame.new(0, height - 0.6, 0), Vector3.new(diameter + 1, 1.2, diameter + 1), Palette.darken(look, 0.85))
	return model
end

return table.freeze(PropsBuildings)
