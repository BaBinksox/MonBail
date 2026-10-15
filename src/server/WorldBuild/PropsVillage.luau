--!strict
--[[
	PropsVillage
	Petits props paramétrés du village brûlé : mobilier, lumières, clôtures, tombes, signalétique,
	détails narratifs (horloges arrêtées, graffitis, traces de griffes, cendres).

	Convention (commune à tous les modules Props) : `base` est un CFrame LOCAL posé AU SOL,
	LookVector = l'avant du prop (la face lisible d'un panneau, l'ouverture d'un coffre...).
	Chaque fonction retourne son Model. Les détails fins sont des décors (CanCollide = false).

	API :
		Mobilier   : barrel, crate, chest, cart, bench, tableSet, woodpile, sack, anvil, trough
		Lumières   : lanternPost, hangingLantern, brazier, candles
		Limites    : fence, palisade
		Cimetière  : tomb, flowers
		Ruines     : brokenPillar, rubble, charredBeams, ashPile
		Signes     : signPost, noticeBoard, hangingSign, banner, clock, graffiti, clawMarks
		Entraînement : weaponRack, trainingDummy
		Linge      : laundryLine
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Config = require(script.Parent.WorldBuildConfig)

type Look = Palette.Look

export type LanternOptions = {
	height: number?, -- hauteur du poteau (défaut 9)
	light: boolean?, -- ajoute une PointLight (budgétée)
	lit: boolean?, -- verre allumé (défaut vrai) ; faux = lanterne morte
	range: number?,
}

export type BrazierOptions = {
	lit: boolean?, -- défaut vrai ; faux = brasero éteint (Fire / PointLight désactivés, braises noires)
	light: boolean?, -- ajoute une PointLight (défaut vrai)
	scale: number?, -- 1 = brasero de rue (hauteur ~3,5)
	stone: boolean?, -- vasque de pierre (brasero antique) au lieu du fer
}

export type FenceOptions = {
	height: number?, -- défaut 3
	broken: number?, -- probabilité (0..1) qu'une travée soit brisée
	solid: boolean?, -- vrai : garde-corps collisionnable (bord de falaise)
	look: Look?,
	spacing: number?, -- distance entre poteaux (défaut 3,5)
}

export type TombVariant = "rounded" | "cross" | "slab" | "broken" | "obelisk"

local PropsVillage = {}

local DECOR: Kit.PartOptions = { decor = true }

local function stoppedClockAngles(): (number, number)
	local minute = Config.STOPPED_CLOCK_MINUTE
	local hour = Config.STOPPED_CLOCK_HOUR + minute / 60
	return math.rad(hour / 12 * 360), math.rad(minute / 60 * 360)
end

--------------------------------------------------------------------------------
-- Mobilier
--------------------------------------------------------------------------------

-- Tonneau cerclé. `tipped` : couché sur le flanc (axe vers l'avant).
function PropsVillage.barrel(parent: Instance, base: CFrame, tipped: boolean?, look: Look?): Model
	local model = Kit.model(parent, "Barrel", base)
	local height, diameter = 3, 2.4
	local frame = if tipped then base * CFrame.new(0, diameter / 2, -height / 2) * CFrame.Angles(math.rad(90), 0, 0) else base
	Kit.column(model, frame, height, diameter, look or Palette.oldWood, { decor = tipped == true })
	for _, y in { 0.55, height - 0.8 } do
		Kit.column(model, frame * CFrame.new(0, y, 0), 0.25, diameter + 0.12, Palette.iron, DECOR)
	end
	Kit.column(model, frame * CFrame.new(0, height, 0), 0.08, diameter - 0.3, Palette.charredWood, DECOR)
	return model
end

-- Caisse de bois ; `broken` : planches éparpillées autour d'une caisse éventrée.
function PropsVillage.crate(parent: Instance, base: CFrame, size: number?, broken: boolean?, random: Random?): Model
	local s = size or 3
	local model = Kit.model(parent, "Crate", base)
	if broken and random then
		Kit.part(model, base * CFrame.new(0, s * 0.25, 0), Vector3.new(s, s * 0.5, s), Palette.burntWood, DECOR)
		for _ = 1, 3 do
			local cf = base * CFrame.new(random:NextNumber(-s, s), 0.15, random:NextNumber(-s, s)) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0)
			Kit.part(model, cf, Vector3.new(s, 0.25, 0.6), Palette.oldWood, DECOR)
		end
		return model
	end
	Kit.part(model, base * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Palette.oldWood, { decor = s < 2.5 })
	Kit.part(model, base * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.08, s * 0.22, s + 0.08), Palette.timber, DECOR)
	return model
end

-- Coffre cerclé de fer. Retourne le Model et sa caisse (la Part à viser pour un interactable).
function PropsVillage.chest(parent: Instance, base: CFrame, look: Look?): (Model, Part)
	local model = Kit.model(parent, "Chest", base)
	local body = Kit.part(model, base * CFrame.new(0, 0.9, 0), Vector3.new(3, 1.8, 2), look or Palette.oldWood, { name = "Body" })
	Kit.cylinder(model, base * CFrame.new(0, 1.8, 0), 3, 2, look or Palette.oldWood, { name = "Lid" })
	for _, x in { -1, 1 } do
		Kit.part(model, base * CFrame.new(x, 1.4, 0), Vector3.new(0.25, 2.4, 2.1), Palette.iron, DECOR)
	end
	Kit.part(model, base * CFrame.new(0, 1.5, -1.05), Vector3.new(0.5, 0.6, 0.15), Palette.rust, DECOR)
	return model, body
end

-- Chariot ; `overturned` : renversé sur le flanc, une roue arrachée à côté.
function PropsVillage.cart(parent: Instance, base: CFrame, overturned: boolean?, random: Random?): Model
	local model = Kit.model(parent, "Cart", base)
	local frame = if overturned then base * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(100)) else base * CFrame.new(0, 2.2, 0)
	local wood = Palette.burntWood
	Kit.part(model, frame, Vector3.new(4, 0.5, 7), wood, { name = "Bed" })
	for _, x in { -1.9, 1.9 } do
		Kit.part(model, frame * CFrame.new(x, 0.8, 0), Vector3.new(0.3, 1.4, 7), wood, DECOR)
	end
	Kit.part(model, frame * CFrame.new(0, 0.8, 3.4), Vector3.new(4, 1.4, 0.3), wood, DECOR)
	Kit.cylinder(model, frame * CFrame.new(0, -0.7, -0.8), 4.6, 0.3, Palette.iron, DECOR) -- essieu
	local wheelSides: { number } = if overturned then { -2.3 } else { -2.3, 2.3 }
	for _, x in wheelSides do
		Kit.cylinder(model, frame * CFrame.new(x, -0.7, -0.8), 0.4, 3.4, Palette.charredWood, DECOR)
	end
	if overturned then
		local r = random
		local offset = if r then r:NextNumber(-1, 1) else 0
		Kit.cylinder(model, base * CFrame.new(4.5 + offset, 0.25, 2) * CFrame.Angles(0, 0, math.rad(90)), 0.4, 3.4, Palette.charredWood, DECOR)
	else
		for _, x in { -0.9, 0.9 } do
			Kit.beam(model, (frame * CFrame.new(x, -0.2, -3.5)).Position, (base * CFrame.new(x * 0.8, 0.3, -8)).Position, 0.3, 0.3, wood, DECOR)
		end
	end
	return model
end

function PropsVillage.bench(parent: Instance, base: CFrame, length: number?, look: Look?): Model
	local l = length or 5
	local model = Kit.model(parent, "Bench", base)
	local wood = look or Palette.oldWood
	Kit.part(model, base * CFrame.new(0, 1.5, 0), Vector3.new(l, 0.35, 1.3), wood, { name = "Seat" })
	for _, x in { -l / 2 + 0.6, l / 2 - 0.6 } do
		Kit.part(model, base * CFrame.new(x, 0.65, 0), Vector3.new(0.4, 1.4, 1.1), wood, DECOR)
	end
	return model
end

-- Table et deux bancs (terrasse de taverne).
function PropsVillage.tableSet(parent: Instance, base: CFrame, random: Random): Model
	local model = Kit.model(parent, "TableSet", base)
	Kit.part(model, base * CFrame.new(0, 2.9, 0), Vector3.new(5, 0.35, 2.6), Palette.oldWood, { name = "Top" })
	for _, x in { -1.9, 1.9 } do
		Kit.part(model, base * CFrame.new(x, 1.4, 0), Vector3.new(0.4, 2.8, 2), Palette.timber, DECOR)
	end
	PropsVillage.bench(model, base * CFrame.new(0, 0, -2.4), 5)
	if random:NextNumber() < 0.6 then
		PropsVillage.bench(model, base * CFrame.new(0, 0, 2.4), 5)
	else
		Kit.part(model, base * CFrame.new(0.5, 0.3, 2.8) * CFrame.Angles(0, 0.3, math.rad(85)), Vector3.new(5, 0.35, 1.3), Palette.oldWood, DECOR)
	end
	-- Chope et bougie sur la table.
	Kit.column(model, base * CFrame.new(-1, 3.07, 0.3), 0.7, 0.5, Palette.iron, DECOR)
	return model
end

-- Tas de bûches (cylindres couchés).
function PropsVillage.woodpile(parent: Instance, base: CFrame, random: Random): Model
	local model = Kit.model(parent, "Woodpile", base)
	for row = 0, 1 do
		local count = 3 - row
		for i = 1, count do
			local x = (i - (count + 1) / 2) * 1.1
			local cf = base * CFrame.new(x, 0.55 + row * 0.95, random:NextNumber(-0.2, 0.2)) * CFrame.Angles(0, math.rad(90), 0)
			Kit.cylinder(model, cf, 3.5, 1, Palette.oldWood, DECOR)
		end
	end
	return model
end

function PropsVillage.sack(parent: Instance, base: CFrame, random: Random): Model
	local model = Kit.model(parent, "Sack", base)
	local cf = base * CFrame.new(0, 0.8, 0) * CFrame.Angles(math.rad(random:NextNumber(-10, 10)), random:NextNumber(0, 6.28), 0)
	Kit.part(model, cf, Vector3.new(1.6, 1.6, 1.2), Palette.straw, DECOR)
	return model
end

function PropsVillage.anvil(parent: Instance, base: CFrame): Model
	local model = Kit.model(parent, "Anvil", base)
	Kit.column(model, base, 2.2, 2.2, Palette.charredWood)
	Kit.part(model, base * CFrame.new(0, 2.6, 0), Vector3.new(1.2, 0.8, 2.6), Palette.iron, { name = "Anvil" })
	Kit.wedge(model, base * CFrame.new(0, 2.75, -1.8) * CFrame.Angles(0, 0, 0), Vector3.new(0.8, 0.5, 1), Palette.iron, DECOR)
	return model
end

-- Abreuvoir de pierre (eau croupie = verre sombre).
function PropsVillage.trough(parent: Instance, base: CFrame, length: number?): Model
	local l = length or 6
	local model = Kit.model(parent, "Trough", base)
	Kit.part(model, base * CFrame.new(0, 1, 0), Vector3.new(l, 2, 2.4), Palette.stone)
	Kit.part(model, base * CFrame.new(0, 1.85, 0), Vector3.new(l - 0.6, 0.2, 1.8), Palette.tint(Palette.stainedBlue, Color3.fromRGB(30, 36, 40)), DECOR)
	return model
end

--------------------------------------------------------------------------------
-- Lumières
--------------------------------------------------------------------------------

-- Cage de lanterne (verre Neon chaud) suspendue à `hook` (point d'accroche, LOCAL).
local function lanternCage(model: Model, hook: Vector3, lit: boolean, light: boolean, range: number?)
	local top = hook - Vector3.new(0, 0.7, 0)
	Kit.rod(model, hook, top, 0.12, Palette.iron, DECOR)
	Kit.part(model, CFrame.new(top - Vector3.new(0, 0.15, 0)), Vector3.new(1.1, 0.3, 1.1), Palette.iron, DECOR)
	local glassLook = if lit then Palette.lanternGlow else Palette.soot
	local glass = Kit.part(model, CFrame.new(top - Vector3.new(0, 0.85, 0)), Vector3.new(0.75, 1.1, 0.75), glassLook, { decor = true, name = "Glass", transparency = if lit then 0.1 else 0 })
	Kit.part(model, CFrame.new(top - Vector3.new(0, 1.5, 0)), Vector3.new(0.95, 0.2, 0.95), Palette.iron, DECOR)
	if lit and light then
		Kit.light(glass, { color = Palette.colors.warmLight, brightness = 1.4, range = range or 18 })
	end
end

-- Lanterne sur poteau (rues, place, chemin du belvédère).
function PropsVillage.lanternPost(parent: Instance, base: CFrame, options: LanternOptions?): Model
	local opts: LanternOptions = options or {}
	local height = opts.height or 9
	local model = Kit.model(parent, "LanternPost", base)
	Kit.part(model, base * CFrame.new(0, 0.3, 0), Vector3.new(1.4, 1.2, 1.4), Palette.stoneDark)
	Kit.part(model, base * CFrame.new(0, height / 2, 0), Vector3.new(0.55, height, 0.55), Palette.timber, { name = "Post" })
	local armEnd = (base * CFrame.new(0, height - 0.4, -1.8)).Position
	Kit.beam(model, (base * CFrame.new(0, height - 0.4, 0)).Position, armEnd, 0.35, 0.35, Palette.iron, DECOR)
	Kit.beam(model, (base * CFrame.new(0, height - 1.6, 0)).Position, (base * CFrame.new(0, height - 0.45, -1.2)).Position, 0.2, 0.2, Palette.iron, DECOR)
	lanternCage(model, armEnd, opts.lit ~= false, opts.light == true, opts.range)
	return model
end

-- Lanterne pendue à un point (sous un auvent, à une poutre).
function PropsVillage.hangingLantern(parent: Instance, hook: Vector3, light: boolean?, lit: boolean?): Model
	local model = Kit.model(parent, "HangingLantern", CFrame.new(hook))
	lanternCage(model, hook, lit ~= false, light == true, nil)
	return model
end

--[[
	Brasero. Le Model contient une Part "Embers" (Neon) qui porte le Fire et la PointLight.
	`lit = false` : tout est désactivé et les braises sont noires (état initial des dynamics "light").
]]
function PropsVillage.brazier(parent: Instance, base: CFrame, options: BrazierOptions?): Model
	local opts: BrazierOptions = options or {}
	local s = opts.scale or 1
	local lit = opts.lit ~= false
	local model = Kit.model(parent, "Brazier", base)
	if opts.stone then
		Kit.part(model, base * CFrame.new(0, 0.5 * s, 0), Vector3.new(2.6, 1, 2.6) * s, Palette.stoneDark, { name = "Plinth" })
		Kit.column(model, base * CFrame.new(0, 1 * s, 0), 1.8 * s, 1.4 * s, Palette.stone)
		Kit.column(model, base * CFrame.new(0, 2.8 * s, 0), 1 * s, 3.4 * s, Palette.stone, { name = "Bowl" })
	else
		for i = 0, 2 do
			local angle = i / 3 * math.pi * 2
			local foot = (base * CFrame.new(math.cos(angle) * 1.3 * s, 0, math.sin(angle) * 1.3 * s)).Position
			local top = (base * CFrame.new(math.cos(angle) * 0.7 * s, 2.6 * s, math.sin(angle) * 0.7 * s)).Position
			Kit.rod(model, foot, top, 0.25 * s, Palette.iron, DECOR)
		end
		Kit.column(model, base * CFrame.new(0, 2.6 * s, 0), 0.9 * s, 2.8 * s, Palette.iron, { name = "Bowl" })
	end
	local bowlTop = if opts.stone then 3.8 * s else 3.5 * s
	local embers = Kit.part(
		model,
		base * CFrame.new(0, bowlTop - 0.1 * s, 0),
		Vector3.new(2 * s, 0.35 * s, 2 * s),
		if lit then Palette.ember else Palette.tint(Palette.ember, Color3.fromRGB(38, 30, 27)),
		{ decor = true, name = "Embers" }
	)
	Kit.fire(embers, { size = 4 * s, heat = 7, enabled = lit })
	if opts.light ~= false then
		Kit.light(embers, { color = Palette.colors.emberLight, brightness = 1.8, range = 20 * s, enabled = lit })
	end
	return model
end

-- Bougies groupées (autels, tombes, Sanctuaire). `light` : une seule PointLight pour le groupe.
function PropsVillage.candles(parent: Instance, base: CFrame, count: number, random: Random, light: boolean?): Model
	local model = Kit.model(parent, "Candles", base)
	for i = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = if i == 1 then 0 else random:NextNumber(0.4, 1.3)
		local height = random:NextNumber(0.5, 1.6)
		local foot = base * CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		Kit.column(model, foot, height, random:NextNumber(0.25, 0.4), Palette.wax, DECOR)
		Kit.part(model, foot * CFrame.new(0, height + 0.18, 0), Vector3.new(0.12, 0.3, 0.12), Palette.candleFlame, { decor = true, name = "Flame" })
	end
	if light then
		local holder = Kit.part(model, base * CFrame.new(0, 1.6, 0), Vector3.new(0.2, 0.2, 0.2), Palette.candleFlame, { decor = true, transparency = 1, name = "LightHolder" })
		Kit.light(holder, { color = Palette.colors.candleLight, brightness = 1, range = 12 })
	end
	return model
end

--------------------------------------------------------------------------------
-- Clôtures
--------------------------------------------------------------------------------

-- Clôture de bois de `from` à `to` (points AU SOL). Travées brisées selon `broken`.
function PropsVillage.fence(parent: Instance, from: Vector3, to: Vector3, random: Random, options: FenceOptions?): Model
	local opts: FenceOptions = options or {}
	local height = opts.height or 3
	local look = opts.look or Palette.burntWood
	local spacing = opts.spacing or 3.5
	local solid = opts.solid == true
	local model = Kit.model(parent, "Fence", CFrame.new((from + to) / 2))
	local count = math.max(1, math.floor((to - from).Magnitude / spacing + 0.5))
	local partOptions: Kit.PartOptions = { decor = not solid, collide = solid }
	local previousTop: Vector3? = nil
	for i = 0, count do
		local p = from:Lerp(to, i / count)
		local isBroken = random:NextNumber() < (opts.broken or 0)
		local postHeight = if isBroken then height * random:NextNumber(0.4, 0.8) else height
		local tilt = if isBroken then random:NextNumber(-12, 12) else 0
		local postCf = CFrame.new(p) * CFrame.Angles(math.rad(tilt), 0, math.rad(tilt * 0.5)) * CFrame.new(0, postHeight / 2 - 0.4, 0)
		Kit.part(model, postCf, Vector3.new(0.45, postHeight + 0.8, 0.45), look, partOptions)
		local top = p + Vector3.new(0, height * 0.82, 0)
		if previousTop and not isBroken then
			local lowFrom = previousTop - Vector3.new(0, height * 0.45, 0)
			Kit.beam(model, previousTop, top, 0.25, 0.35, look, partOptions)
			if random:NextNumber() > (opts.broken or 0) * 0.8 then
				Kit.beam(model, lowFrom, top - Vector3.new(0, height * 0.45, 0), 0.25, 0.35, look, partOptions)
			end
		end
		previousTop = if isBroken then nil else top
	end
	return model
end

-- Palissade de pieux pointus (portes du village).
function PropsVillage.palisade(parent: Instance, from: Vector3, to: Vector3, height: number, random: Random, broken: number?): Model
	local model = Kit.model(parent, "Palisade", CFrame.new((from + to) / 2))
	local count = math.max(1, math.floor((to - from).Magnitude / 1.3))
	local direction = Kit.facing(from, to)
	for i = 0, count - 1 do
		local p = from:Lerp(to, (i + 0.5) / count)
		if random:NextNumber() >= (broken or 0) then
			local h = height * random:NextNumber(0.85, 1.05)
			local cf = direction.Rotation + p
			local look = if random:NextNumber() < 0.5 then Palette.charredWood else Palette.burntWood
			Kit.part(model, cf * CFrame.new(0, h / 2 - 1, 0), Vector3.new(1.2, h, 1), look)
			Kit.wedge(model, cf * CFrame.new(0, h - 0.4, 0.25), Vector3.new(1.2, 1.2, 0.5), look, DECOR)
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Cimetière
--------------------------------------------------------------------------------

-- Pierre tombale. La face gravée regarde vers l'avant (-Z de `base`).
function PropsVillage.tomb(parent: Instance, base: CFrame, variant: TombVariant, random: Random): Model
	local model = Kit.model(parent, "Tomb", base)
	local lean = CFrame.Angles(math.rad(random:NextNumber(-8, 8)), 0, math.rad(random:NextNumber(-6, 6)))
	local stone = Palette.darken(Palette.stone, random:NextNumber(0.8, 1.15))
	local foot = base * lean
	if variant == "rounded" then
		Kit.part(model, foot * CFrame.new(0, 1.2, 0), Vector3.new(2.4, 3, 0.6), stone)
		Kit.cylinder(model, foot * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, math.rad(90), 0), 0.6, 2.4, stone, DECOR)
	elseif variant == "cross" then
		Kit.part(model, foot * CFrame.new(0, 2, 0), Vector3.new(0.7, 4.6, 0.6), stone)
		Kit.part(model, foot * CFrame.new(0, 3.1, 0), Vector3.new(2.6, 0.7, 0.6), stone, DECOR)
	elseif variant == "slab" then
		Kit.part(model, base * CFrame.new(0, 0.25, 2), Vector3.new(2.6, 0.6, 4.6), stone)
		Kit.part(model, foot * CFrame.new(0, 0.9, -0.2), Vector3.new(2.4, 2, 0.5), stone, DECOR)
	elseif variant == "broken" then
		Kit.part(model, foot * CFrame.new(0, 0.8, 0), Vector3.new(2.4, 2, 0.6), stone)
		Kit.wedge(model, foot * CFrame.new(-0.3, 2.1, 0) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.6, 0.8, 1.6), stone, DECOR)
		Kit.part(model, base * CFrame.new(1.4, 0.3, -1.2) * CFrame.Angles(math.rad(80), 0.4, 0), Vector3.new(2, 1.2, 0.5), stone, DECOR)
	else -- obélisque
		Kit.part(model, base * CFrame.new(0, 0.5, 0), Vector3.new(2.2, 1, 2.2), stone)
		Kit.part(model, foot * CFrame.new(0, 3.5, 0), Vector3.new(1.2, 5, 1.2), stone)
		Kit.part(model, foot * CFrame.new(0, 6.3, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), Vector3.new(0.9, 0.9, 0.9), stone, DECOR)
	end
	-- Tertre devant la stèle.
	if variant ~= "slab" and variant ~= "obelisk" then
		Kit.part(model, base * CFrame.new(0, 0.1, 2.2) * CFrame.Angles(0, 0, 0), Vector3.new(2.6, 0.5, 4), Palette.dirt, DECOR)
	end
	return model
end

-- Bouquet fané (tiges brunes, têtes violettes passées).
function PropsVillage.flowers(parent: Instance, base: CFrame, random: Random): Model
	local model = Kit.model(parent, "WiltedFlowers", base)
	local headLook = Palette.tint(Palette.cloth, Color3.fromRGB(96, 66, 92))
	for _ = 1, 5 do
		local foot = base * CFrame.new(random:NextNumber(-0.4, 0.4), 0, random:NextNumber(-0.3, 0.3))
		local tip = foot * CFrame.new(random:NextNumber(-0.5, 0.5), random:NextNumber(0.6, 1.1), random:NextNumber(-0.5, 0.5))
		Kit.rod(model, foot.Position, tip.Position, 0.08, Palette.deadGrass, DECOR)
		Kit.ball(model, tip.Position - Vector3.new(0, 0.1, 0), 0.32, headLook, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Ruines
--------------------------------------------------------------------------------

-- Pilier brisé : socle, fût cylindrique tronqué en biseau, tambours tombés au pied.
function PropsVillage.brokenPillar(parent: Instance, base: CFrame, height: number, diameter: number, random: Random, look: Look?): Model
	local stone = look or Palette.stone
	local model = Kit.model(parent, "BrokenPillar", base)
	Kit.part(model, base * CFrame.new(0, 0.5, 0), Vector3.new(diameter + 1.2, 1.6, diameter + 1.2), Palette.darken(stone, 0.85))
	local shaft = math.max(1, height - 1.3)
	Kit.column(model, base * CFrame.new(0, 1.2, 0), shaft, diameter, stone)
	local capCf = base * CFrame.new(0, 1.2 + shaft + diameter * 0.2, 0) * CFrame.Angles(math.rad(random:NextNumber(-15, 15)), random:NextNumber(0, 6.28), 0)
	Kit.wedge(model, capCf, Vector3.new(diameter * 0.9, diameter * 0.45, diameter * 0.9), stone, DECOR)
	if random:NextNumber() < 0.7 then
		local angle = random:NextNumber(0, 6.28)
		local drum = base * CFrame.new(math.cos(angle) * (diameter + 1.5), diameter * 0.4, math.sin(angle) * (diameter + 1.5)) * CFrame.Angles(0, angle, 0)
		Kit.cylinder(model, drum, diameter * 0.9, diameter * 0.85, stone, DECOR)
	end
	return model
end

-- Gravats épars dans un disque (décor : pas d'accroche).
function PropsVillage.rubble(parent: Instance, center: CFrame, radius: number, count: number, random: Random, look: Look?): Model
	local model = Kit.model(parent, "Rubble", center)
	for _ = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(0, radius)
		local s = random:NextNumber(0.5, 1.6)
		local cf = center * CFrame.new(math.cos(angle) * distance, s * 0.25, math.sin(angle) * distance)
			* CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 6.28), random:NextNumber(-0.5, 0.5))
		Kit.part(model, cf, Vector3.new(s, s * 0.6, s * random:NextNumber(0.6, 1.2)), Palette.darken(look or Palette.stone, random:NextNumber(0.75, 1.1)), DECOR)
	end
	return model
end

-- Poutres calcinées effondrées, en travers les unes des autres.
function PropsVillage.charredBeams(parent: Instance, base: CFrame, length: number, random: Random): Model
	local model = Kit.model(parent, "CharredBeams", base)
	for i = 1, random:NextInteger(3, 4) do
		local yaw = random:NextNumber(0, math.pi)
		local raise = if i == 1 then 0 else random:NextNumber(0.3, 2.2)
		local a = base * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0.5, -length / 2)
		local b = base * CFrame.Angles(0, yaw, 0) * CFrame.new(random:NextNumber(-1, 1), 0.5 + raise, length / 2)
		Kit.beam(model, a.Position, b.Position, 0.9, 0.9, Palette.charredWood, DECOR)
	end
	return model
end

-- Tas de cendres, parfois une braise qui couve.
function PropsVillage.ashPile(parent: Instance, base: CFrame, size: number, random: Random): Model
	local model = Kit.model(parent, "AshPile", base)
	local yaw = CFrame.Angles(0, random:NextNumber(0, 6.28), 0)
	Kit.wedge(model, base * yaw * CFrame.new(0, size * 0.18, size * 0.2), Vector3.new(size, size * 0.4, size * 0.7), Palette.ash, DECOR)
	Kit.wedge(model, base * yaw * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, size * 0.18, size * 0.2), Vector3.new(size, size * 0.4, size * 0.7), Palette.ashDark, DECOR)
	if random:NextNumber() < 0.35 then
		Kit.part(model, base * CFrame.new(random:NextNumber(-0.3, 0.3) * size, size * 0.3, 0), Vector3.new(0.4, 0.2, 0.3), Palette.emberDim, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Signalétique et narration
--------------------------------------------------------------------------------

-- Poteau indicateur : planche avec un texte (SurfaceGui) lisible depuis l'avant.
function PropsVillage.signPost(parent: Instance, base: CFrame, text: string, random: Random): Model
	local model = Kit.model(parent, "SignPost", base)
	Kit.part(model, base * CFrame.new(0, 2.6, 0), Vector3.new(0.45, 5.2, 0.45), Palette.timber)
	local board = Kit.part(model, base * CFrame.new(0.9, 4.2, -0.3) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-6, 6))), Vector3.new(3.6, 1, 0.2), Palette.oldWood, { decor = true, name = "Board" })
	Kit.surfaceText(board, Enum.NormalId.Front, text, { color = Palette.colors.chalk, pixelsPerStud = 50 })
	return model
end

--[[
	Tableau d'affichage sous auvent (contrats). Retourne le Model et le panneau (la Part à viser).
	Les affiches sont de petites Parts de papier clouées de travers.
]]
function PropsVillage.noticeBoard(parent: Instance, base: CFrame, random: Random, title: string?): (Model, Part)
	local model = Kit.model(parent, "NoticeBoard", base)
	for _, x in { -3.4, 3.4 } do
		Kit.part(model, base * CFrame.new(x, 4, 0), Vector3.new(0.7, 8, 0.7), Palette.timber)
	end
	local board = Kit.part(model, base * CFrame.new(0, 4.2, 0), Vector3.new(6.4, 4.2, 0.4), Palette.oldWood, { name = "Board" })
	for _ = 1, 7 do
		local cf = base * CFrame.new(random:NextNumber(-2.6, 2.6), 4.2 + random:NextNumber(-1.4, 1.4), -0.24) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-12, 12)))
		Kit.part(model, cf, Vector3.new(random:NextNumber(0.9, 1.4), random:NextNumber(1.1, 1.6), 0.05), Palette.paper, DECOR)
	end
	-- Auvent à deux pans.
	for _, side in { -1, 1 } do
		local cf = base * CFrame.new(0, 8.2, side * 0.9) * CFrame.Angles(math.rad(side * 28), 0, 0)
		Kit.part(model, cf, Vector3.new(8.4, 0.3, 2.4), Palette.roofShingle, DECOR)
	end
	if title then
		local plank = Kit.part(model, base * CFrame.new(0, 6.8, -0.25), Vector3.new(5, 0.9, 0.15), Palette.charredWood, { decor = true, name = "Title" })
		Kit.surfaceText(plank, Enum.NormalId.Front, title, { color = Palette.colors.chalk, pixelsPerStud = 50 })
	end
	return model, board
end

-- Enseigne pendue à une potence fixée au mur (`base` = point d'attache sur la façade, regard = rue).
function PropsVillage.hangingSign(parent: Instance, base: CFrame, text: string): (Model, Part)
	local model = Kit.model(parent, "HangingSign", base)
	Kit.part(model, base * CFrame.new(0, 0, -1.8), Vector3.new(0.3, 0.3, 3.6), Palette.iron, DECOR)
	for _, x in { -1.2, 1.2 } do
		Kit.rod(model, (base * CFrame.new(0, 0, -2.3 + x * 0.5)).Position, (base * CFrame.new(0, -0.9, -2.3 + x * 0.5)).Position, 0.08, Palette.iron, DECOR)
	end
	local board = Kit.part(model, base * CFrame.new(0, -1.9, -2.3) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(3.4, 1.9, 0.25), Palette.oldWood, { decor = true, name = "Board" })
	Kit.surfaceText(board, Enum.NormalId.Front, text, { color = Palette.colors.chalk, pixelsPerStud = 50 })
	Kit.surfaceText(board, Enum.NormalId.Back, text, { color = Palette.colors.chalk, pixelsPerStud = 50 })
	return model, board
end

-- Bannière de tissu pendue sous une hampe (`base` = haut de la hampe, regard = face visible).
function PropsVillage.banner(parent: Instance, base: CFrame, width: number, height: number, look: Look?, emblem: Look?): Model
	local model = Kit.model(parent, "Banner", base)
	Kit.cylinder(model, base, width + 0.8, 0.25, Palette.iron, DECOR)
	Kit.part(model, base * CFrame.new(0, -height / 2, 0), Vector3.new(width, height, 0.12), look or Palette.banner, DECOR)
	Kit.wedge(model, base * CFrame.new(0, -height - 0.5, 0) * CFrame.Angles(math.rad(180), 0, 0), Vector3.new(width, 1, 0.12), look or Palette.banner, DECOR)
	if emblem then
		Kit.part(model, base * CFrame.new(0, -height * 0.45, -0.08) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(width * 0.35, width * 0.35, 0.05), emblem, DECOR)
	end
	return model
end

--[[
	Horloge arrêtée sur 3 h 17 (WorldBuildConfig.STOPPED_CLOCK_*). Le cadran regarde vers -Z de `base`
	(centre du cadran). `temporal` : cadran Neon cyan pâle (objet lié au temps).
	Retourne le Model et le cadran (la Part à viser).
]]
function PropsVillage.clock(parent: Instance, base: CFrame, radius: number, temporal: boolean?): (Model, Part)
	local model = Kit.model(parent, "StoppedClock", base)
	local faceLook = if temporal then Palette.temporalCyanDim else Palette.bone
	Kit.cylinder(model, base * CFrame.new(0, 0, 0.15) * CFrame.Angles(0, math.rad(90), 0), 0.4, radius * 2 + 0.5, Palette.bronzeDark, { decor = true, name = "Rim" })
	local face = Kit.cylinder(model, base * CFrame.Angles(0, math.rad(90), 0), 0.3, radius * 2, faceLook, { decor = true, name = "Face", transparency = if temporal then 0.15 else 0 })
	local hourAngle, minuteAngle = stoppedClockAngles()
	local hands: { { angle: number, length: number, width: number } } = {
		{ angle = hourAngle, length = radius * 0.55, width = 0.22 * radius / 2 + 0.08 },
		{ angle = minuteAngle, length = radius * 0.85, width = 0.14 * radius / 2 + 0.06 },
	}
	for _, hand in hands do
		local cf = base * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, 0, hand.angle) * CFrame.new(0, hand.length / 2, 0)
		Kit.part(model, cf, Vector3.new(hand.width, hand.length, 0.08), Palette.iron, DECOR)
	end
	-- Fissure en travers du cadran.
	Kit.part(model, base * CFrame.new(radius * 0.2, -radius * 0.2, -0.17) * CFrame.Angles(0, 0, math.rad(35)), Vector3.new(0.06, radius * 1.4, 0.04), Palette.soot, DECOR)
	return model, face
end

-- Graffiti peint (Part porteuse invisible + texte), `base` = centre, regard = vers le lecteur.
function PropsVillage.graffiti(parent: Instance, base: CFrame, size: Vector2, text: string, color: Color3?): Model
	local model = Kit.model(parent, "Graffiti", base)
	local carrier = Kit.part(model, base, Vector3.new(size.X, size.Y, 0.05), Palette.soot, { decor = true, transparency = 1, name = "Paint" })
	Kit.surfaceText(carrier, Enum.NormalId.Front, text, {
		color = color or Palette.colors.blood,
		font = Enum.Font.Fantasy,
		pixelsPerStud = 30,
		rotation = -4,
	})
	return model
end

-- Trois traces de griffes parallèles (`base` = centre, sur une surface qui regarde vers -Z).
function PropsVillage.clawMarks(parent: Instance, base: CFrame, length: number): Model
	local model = Kit.model(parent, "ClawMarks", base)
	for i = -1, 1 do
		local cf = base * CFrame.new(i * 0.45, i * 0.15, -0.05) * CFrame.Angles(0, 0, math.rad(-28))
		Kit.part(model, cf, Vector3.new(0.14, length * (1 - math.abs(i) * 0.15), 0.06), Palette.soot, DECOR)
	end
	return model
end

-- Corde à linge tendue entre deux points, quelques vêtements pendus.
function PropsVillage.laundryLine(parent: Instance, from: Vector3, to: Vector3, random: Random): Model
	local model = Kit.model(parent, "LaundryLine", CFrame.new((from + to) / 2))
	local sag = Vector3.new(0, -0.8, 0)
	local middle = (from + to) / 2 + sag
	Kit.rod(model, from, middle, 0.08, Palette.straw, DECOR)
	Kit.rod(model, middle, to, 0.08, Palette.straw, DECOR)
	local count = random:NextInteger(3, 5)
	local facing = Kit.facing(from, to)
	for i = 1, count do
		local t = i / (count + 1)
		local p = from:Lerp(to, t) + sag * (1 - (2 * t - 1) ^ 2)
		local w, h = random:NextNumber(1.2, 2.4), random:NextNumber(1.2, 2.6)
		local look = if random:NextNumber() < 0.5 then Palette.cloth else Palette.clothDark
		local cf = facing.Rotation * CFrame.Angles(0, math.rad(90), math.rad(random:NextNumber(-6, 6))) + (p - Vector3.new(0, h / 2, 0))
		Kit.part(model, cf, Vector3.new(0.06, h, w), look, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Entraînement
--------------------------------------------------------------------------------

-- Râtelier d'armes : épées et lances appuyées.
function PropsVillage.weaponRack(parent: Instance, base: CFrame, random: Random): Model
	local model = Kit.model(parent, "WeaponRack", base)
	for _, x in { -2.4, 2.4 } do
		Kit.part(model, base * CFrame.new(x, 2.2, 0), Vector3.new(0.5, 4.4, 0.5), Palette.timber)
	end
	Kit.part(model, base * CFrame.new(0, 3.9, 0), Vector3.new(5.4, 0.35, 0.5), Palette.timber, DECOR)
	Kit.part(model, base * CFrame.new(0, 1.2, 0.35), Vector3.new(5.4, 0.35, 0.5), Palette.timber, DECOR)
	for i = 1, 4 do
		local x = -2.4 + i * 0.96
		local tilt = CFrame.Angles(math.rad(-12), 0, math.rad(random:NextNumber(-4, 4)))
		if i % 2 == 0 then
			Kit.part(model, base * CFrame.new(x, 2.6, 0.25) * tilt, Vector3.new(0.25, 4.2, 0.08), Palette.iron, DECOR)
			Kit.part(model, base * CFrame.new(x, 1.2, 0.55) * tilt, Vector3.new(0.9, 0.18, 0.18), Palette.rust, DECOR)
		else
			Kit.part(model, base * CFrame.new(x, 3, 0.25) * tilt, Vector3.new(0.18, 6, 0.18), Palette.oldWood, DECOR)
			Kit.part(model, base * CFrame.new(x, 6.1, -0.4) * tilt, Vector3.new(0.3, 0.9, 0.12), Palette.iron, DECOR)
		end
	end
	return model
end

-- Mannequin d'entraînement décoratif (les mannequins COMBATTANTS sont créés par EnemyService).
function PropsVillage.trainingDummy(parent: Instance, base: CFrame, random: Random, broken: boolean?): Model
	local model = Kit.model(parent, "TrainingDummy", base)
	local lean = if broken then CFrame.Angles(math.rad(random:NextNumber(15, 30)), 0, 0) else CFrame.identity
	local frame = base * lean
	Kit.part(model, base * CFrame.new(0, 0.2, 0), Vector3.new(2.6, 0.4, 0.5), Palette.timber, DECOR)
	Kit.part(model, base * CFrame.new(0, 0.2, 0), Vector3.new(0.5, 0.4, 2.6), Palette.timber, DECOR)
	Kit.part(model, frame * CFrame.new(0, 2.6, 0), Vector3.new(0.4, 5.2, 0.4), Palette.timber, DECOR)
	Kit.part(model, frame * CFrame.new(0, 3.2, 0), Vector3.new(1.8, 2.4, 1.1), Palette.straw, DECOR)
	Kit.part(model, frame * CFrame.new(0, 4, 0), Vector3.new(3.6, 0.35, 0.35), Palette.timber, DECOR)
	if not broken then
		Kit.ball(model, (frame * CFrame.new(0, 5.1, 0)).Position, 1.3, Palette.cloth, DECOR)
	end
	return model
end

return table.freeze(PropsVillage)
