--!strict
--[[
	PropsSacred
	Props paramétrés du sacré, du funéraire et du temps : statue, sablier, pierre runique, sarcophage,
	autel, lutrin, livre, banc d'église, cloche, échelle, bibliothèque, candélabre, applique murale,
	vitrail gothique, mausolée, tas d'ossements.

	Convention (commune à tous les modules Props) : `base` est un CFrame LOCAL posé AU SOL,
	LookVector = l'avant du prop (le visage d'une statue, la face gravée d'une pierre, la porte d'un
	mausolée). `random` = context.random. Les détails fins sont des décors (CanCollide = false).
	Accents : le cyan (Palette.temporalCyan*) est RÉSERVÉ aux objets liés au temps (sablier, runes,
	horloge de la statue) ; la crypte est éclairée en blanc acier (Palette.coldFlame / colors.coldLight).

	API :
		PropsSacred.statue(parent, base, height, random, options?): StatueResult
		PropsSacred.hourglass(parent, base, height, options?): (Model, Part)      -- Part = bulbe inférieur
		PropsSacred.runeStone(parent, base, size, options?): (Model, Part)        -- Part = la pierre (à viser)
		PropsSacred.sarcophagus(parent, base, random, options?): Model
		PropsSacred.altar(parent, base, width, depth, look?): (Model, Part)       -- dessus à base.Y + ALTAR_HEIGHT
		PropsSacred.lectern(parent, base, overturned?): (Model, CFrame)          -- CFrame où poser le livre
		PropsSacred.book(parent, cframe, open?): Part
		PropsSacred.pew(parent, base, length, random, broken?): Model
		PropsSacred.bell(parent, hang, height, options?): (Model, Part)          -- `hang` = point d'accroche
		PropsSacred.ladder(parent, foot, height, width?): (Model, Part)          -- Part = montant gauche
		PropsSacred.bookshelf(parent, base, width, height, random): Model
		PropsSacred.candelabrum(parent, base, height, options?): Model
		PropsSacred.wallSconce(parent, mount, options?): Model                   -- `mount` = sur le mur, regard vers la pièce
		PropsSacred.gothicWindow(parent, frame, width, height, glass, options?): Model
		PropsSacred.mausoleum(parent, base, random, options?): MausoleumResult
		PropsSacred.boneHeap(parent, base, size, random): Model
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local PropsBuildings = require(script.Parent.PropsBuildings)
local PropsVillage = require(script.Parent.PropsVillage)

type Look = Palette.Look

export type StatueOptions = {
	look: Look?,
	holds: ("clock" | "hourglass" | "sword" | "lantern")?, -- objet tenu dans la main droite levée
	plinth: number?, -- hauteur du socle (0 = aucun ; défaut 0,3 x height)
	broken: boolean?, -- statue mutilée : tête et bras gauche brisés
	inscription: string?, -- texte gravé sur la face avant du socle
}

export type StatueResult = {
	model: Model,
	held: BasePart?, -- l'objet tenu (cadran de l'horloge, bulbe du sablier...)
	plinthTop: number, -- hauteur LOCALE du dessus du socle (relative à base)
	top: number, -- hauteur LOCALE du sommet de la statue
}

export type HourglassOptions = {
	temporal: boolean?, -- verre Neon cyan pâle (objet lié au temps)
	inverted: boolean?, -- le sable est en haut (il "coule vers le haut")
	look: Look?, -- pierre du cadre
}

export type RuneStoneOptions = {
	lit: boolean?, -- rune allumée (cyan vif) ; défaut : éteinte (cyan sombre)
	look: Look?,
	glyph: Look?, -- remplace la couleur de la rune
}

export type SarcophagusOptions = {
	length: number?, -- défaut 7
	effigy: boolean?, -- gisant sculpté sur le couvercle (défaut vrai si fermé)
	open: boolean?, -- couvercle repoussé de travers
	look: Look?,
}

export type BellOptions = {
	cracked: boolean?, -- fissure de haut en bas
	look: Look?,
}

export type CandelabrumOptions = {
	light: boolean?, -- ajoute une PointLight (budgétée)
	cold: boolean?, -- flammes et lumière froides (crypte)
}

export type SconceOptions = {
	light: boolean?,
	cold: boolean?,
	lit: boolean?, -- défaut vrai
	range: number?,
}

export type WindowOptions = {
	random: Random?,
	broken: boolean?, -- vitrail à demi brisé (éclats)
}

export type MausoleumOptions = {
	width: number?, -- défaut 12
	depth: number?, -- défaut 14 (sans le porche)
	height: number?, -- hauteur des murs (défaut 9)
	look: Look?,
	inscription: string?, -- gravé au-dessus de la porte
}

export type MausoleumResult = {
	model: Model,
	floorY: number, -- hauteur LOCALE du sol intérieur (relative à base)
	doorway: CFrame, -- bas du milieu de l'ouverture, face extérieure du mur ; regard vers l'extérieur
	doorSize: Vector3, -- taille de l'ouverture (largeur, hauteur, épaisseur du mur)
	interior: CFrame, -- centre du sol intérieur
	approach: CFrame, -- au sol devant les marches, regard vers la porte
}

local PropsSacred = {}

local DECOR = Kit.DECOR
PropsSacred.ALTAR_HEIGHT = 3.5

--------------------------------------------------------------------------------
-- Statues et objets du temps
--------------------------------------------------------------------------------

-- Bras : épaule -> coude -> main (tiges), dans le repère du personnage `f`.
local function arm(model: Model, f: CFrame, points: { Vector3 }, diameter: number, look: Look)
	for i = 1, #points - 1 do
		Kit.rod(model, (f * CFrame.new(points[i])).Position, (f * CFrame.new(points[i + 1])).Position, diameter, look)
	end
end

--[[
	Statue en robe à capuche sur un socle. `height` = hauteur du personnage (pieds -> tête).
	La main droite levée tient `holds` ; le cadran de l'horloge est Neon cyan (objet du temps)
	et arrêté sur 3 h 17. ~20 Parts.
]]
function PropsSacred.statue(parent: Instance, base: CFrame, height: number, random: Random, options: StatueOptions?): StatueResult
	local opts: StatueOptions = options or {}
	local H = height
	local look = opts.look or Palette.granite
	local model = Kit.model(parent, "Statue", base)
	local P = opts.plinth or H * 0.3
	if P > 0 then
		local W = H * 0.42
		Kit.part(model, base * CFrame.new(0, 0.3, 0), Vector3.new(W + 1, 0.6, W + 1), Palette.darken(look, 0.8), { name = "PlinthBase" })
		local plinth = Kit.part(model, base * CFrame.new(0, P / 2, 0), Vector3.new(W, P, W), Palette.darken(look, 0.9), { name = "Plinth" })
		Kit.part(model, base * CFrame.new(0, P - 0.25, 0), Vector3.new(W + 0.6, 0.5, W + 0.6), Palette.darken(look, 0.8), DECOR)
		if opts.inscription then
			local plate = Kit.part(model, base * CFrame.new(0, P * 0.5, -W / 2 - 0.06), Vector3.new(W * 0.8, P * 0.4, 0.1), Palette.bronzeDark, { decor = true, name = "Plaque" })
			Kit.surfaceText(plate, Enum.NormalId.Front, opts.inscription, { color = Palette.colors.chalk, pixelsPerStud = 30 })
		end
		local _ = plinth
	end
	local f = base * CFrame.new(0, P, 0)
	local shade = Palette.darken(look, 0.75)

	-- Robe évasée, buste, épaules.
	Kit.part(model, f * CFrame.new(0, H * 0.25, 0), Vector3.new(H * 0.34, H * 0.5, H * 0.26), look, { name = "Robe" })
	Kit.wedge(model, f * CFrame.new(0, H * 0.09, -H * 0.17), Vector3.new(H * 0.34, H * 0.18, H * 0.08), look, DECOR)
	Kit.wedge(model, f * CFrame.new(0, H * 0.09, H * 0.17) * CFrame.Angles(0, math.pi, 0), Vector3.new(H * 0.34, H * 0.18, H * 0.08), look, DECOR)
	Kit.part(model, f * CFrame.new(0, H * 0.63, 0), Vector3.new(H * 0.3, H * 0.26, H * 0.18), look, { name = "Torso" })
	Kit.part(model, f * CFrame.new(0, H * 0.755, 0.01 * H), Vector3.new(H * 0.38, H * 0.07, H * 0.22), look, DECOR)

	-- Tête encapuchonnée (visage en retrait plus sombre) ou moignon brisé.
	if opts.broken then
		Kit.wedge(model, f * CFrame.new(0, H * 0.82, 0) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), Vector3.new(H * 0.12, H * 0.08, H * 0.12), shade, DECOR)
	else
		Kit.ball(model, (f * CFrame.new(0, H * 0.865, H * 0.025)).Position, H * 0.17, look, { name = "Hood" })
		Kit.ball(model, (f * CFrame.new(0, H * 0.85, -H * 0.03)).Position, H * 0.12, shade, DECOR)
	end

	-- Bras droit levé vers l'avant ; bras gauche replié (ou brisé).
	local hand = Vector3.new(H * 0.13, H * 0.93, -H * 0.2)
	arm(model, f, { Vector3.new(H * 0.17, H * 0.74, 0), Vector3.new(H * 0.2, H * 0.82, -H * 0.1), hand }, H * 0.07, look)
	if opts.broken then
		arm(model, f, { Vector3.new(-H * 0.17, H * 0.74, 0), Vector3.new(-H * 0.2, H * 0.62, -H * 0.03) }, H * 0.07, look)
	else
		arm(model, f, { Vector3.new(-H * 0.17, H * 0.74, 0), Vector3.new(-H * 0.21, H * 0.56, -H * 0.04), Vector3.new(-H * 0.08, H * 0.52, -H * 0.15) }, H * 0.07, look)
	end

	-- Objet tenu.
	local held: BasePart? = nil
	local top = P + H
	local holdFrame = f * CFrame.new(hand) * CFrame.new(0, H * 0.02, -H * 0.02)
	if opts.holds == "clock" then
		local radius = H * 0.13
		local _, face = PropsVillage.clock(model, holdFrame * CFrame.new(0, radius * 0.9, 0), radius, true)
		held = face
		top = math.max(top, P + hand.Y + radius * 2)
	elseif opts.holds == "hourglass" then
		local _, bulb = PropsSacred.hourglass(model, holdFrame, H * 0.22, { temporal = true, inverted = true })
		held = bulb
	elseif opts.holds == "sword" then
		local tip = (f * CFrame.new(H * 0.12, 0.2, -H * 0.24)).Position
		held = Kit.beam(model, (holdFrame * CFrame.new(0, H * 0.06, 0)).Position, tip, H * 0.05, H * 0.015, Palette.iron, DECOR)
		Kit.part(model, holdFrame * CFrame.new(0, -H * 0.03, 0), Vector3.new(H * 0.16, H * 0.02, H * 0.03), Palette.iron, DECOR)
	elseif opts.holds == "lantern" then
		local lantern = PropsVillage.hangingLantern(model, (holdFrame * CFrame.new(0, -H * 0.02, 0)).Position, false, true)
		held = lantern:FindFirstChild("Glass") :: BasePart?
	end
	return { model = model, held = held, plinthTop = P, top = top }
end

--[[
	Sablier sur socle. `temporal` : bulbes Neon cyan pâle translucides (ancre temporelle) ;
	`inverted` : le sable est dans le bulbe du HAUT. Retourne le Model et le bulbe inférieur.
]]
function PropsSacred.hourglass(parent: Instance, base: CFrame, height: number, options: HourglassOptions?): (Model, Part)
	local opts: HourglassOptions = options or {}
	local h = height
	local stone = opts.look or Palette.stone
	local model = Kit.model(parent, "Hourglass", base)
	Kit.column(model, base, h * 0.08, h * 0.6, stone, { decor = true, name = "Foot" })
	Kit.column(model, base * CFrame.new(0, h * 0.92, 0), h * 0.08, h * 0.6, stone, DECOR)
	for i = 0, 2 do
		local degrees = 90 + i * 120
		local foot = Kit.ringPoint((base * CFrame.new(0, h * 0.08, 0)).Position, h * 0.24, degrees)
		Kit.rod(model, foot, foot + base.UpVector * (h * 0.84), h * 0.05, stone, DECOR)
	end
	local glassLook = if opts.temporal then Palette.temporalCyanDim else Palette.tint(Palette.stainedAmber, Color3.fromRGB(150, 140, 120))
	local glassOptions: Kit.PartOptions = { decor = true, transparency = if opts.temporal then 0.45 else 0.55 }
	local lower = Kit.ball(model, (base * CFrame.new(0, h * 0.3, 0)).Position, h * 0.36, glassLook, glassOptions)
	lower.Name = "LowerBulb"
	Kit.ball(model, (base * CFrame.new(0, h * 0.7, 0)).Position, h * 0.36, glassLook, glassOptions).Name = "UpperBulb"
	Kit.column(model, base * CFrame.new(0, h * 0.45, 0), h * 0.1, h * 0.08, glassLook, glassOptions)
	local sandLook = if opts.temporal then Palette.temporalCyan else Palette.straw
	local sandY = if opts.inverted then h * 0.74 else h * 0.26
	Kit.ball(model, (base * CFrame.new(0, sandY, 0)).Position, h * 0.2, sandLook, { decor = true, name = "Sand" })
	return model, lower
end

--[[
	Pierre runique : bloc de pierre portant une rune (Neon) sur sa face avant (-Z).
	Éteinte par défaut (cyan sombre), allumée avec `lit`. Retourne le Model et la pierre (à viser).
]]
function PropsSacred.runeStone(parent: Instance, base: CFrame, size: Vector3, options: RuneStoneOptions?): (Model, Part)
	local opts: RuneStoneOptions = options or {}
	local model = Kit.model(parent, "RuneStone", base)
	local stone = Kit.part(model, base * CFrame.new(0, size.Y / 2, 0), size, opts.look or Palette.stoneDark, { name = "Stone" })
	local glyph = opts.glyph or (if opts.lit then Palette.temporalCyan else Palette.temporalCyanDim)
	local face = base * CFrame.new(0, size.Y * 0.55, -size.Z / 2 - 0.03)
	local stem = size.Y * 0.55
	local glyphOptions: Kit.PartOptions = { decor = true, transparency = 0.1, name = "Rune" }
	Kit.part(model, face, Vector3.new(0.16, stem, 0.06), glyph, glyphOptions)
	for _, side in { -1, 1 } do
		Kit.part(model, face * CFrame.new(side * size.X * 0.14, stem * 0.18, 0) * CFrame.Angles(0, 0, math.rad(-side * 38)), Vector3.new(0.14, stem * 0.45, 0.06), glyph, glyphOptions)
	end
	Kit.part(model, face * CFrame.new(0, -stem * 0.38, 0), Vector3.new(size.X * 0.4, 0.14, 0.06), glyph, glyphOptions)
	return model, stone
end

--------------------------------------------------------------------------------
-- Mobilier sacré
--------------------------------------------------------------------------------

--[[
	Sarcophage de pierre, long axe le long du Z local (tête du gisant vers +Z).
	`open` : couvercle repoussé de travers, intérieur noir et crâne visible.
]]
function PropsSacred.sarcophagus(parent: Instance, base: CFrame, random: Random, options: SarcophagusOptions?): Model
	local opts: SarcophagusOptions = options or {}
	local L = opts.length or 7
	local W, H = 3.2, 2.4
	local stone = opts.look or Palette.darken(Palette.stone, random:NextNumber(0.8, 1))
	local model = Kit.model(parent, "Sarcophagus", base)
	Kit.part(model, base * CFrame.new(0, 0.2, 0), Vector3.new(W + 0.6, 0.4, L + 0.6), Palette.darken(stone, 0.8))
	Kit.part(model, base * CFrame.new(0, 0.4 + (H - 0.4) / 2, 0), Vector3.new(W, H - 0.4, L), stone, { name = "Body" })
	if opts.open then
		Kit.part(model, base * CFrame.new(0, H - 0.05, 0), Vector3.new(W - 0.6, 0.12, L - 0.6), Palette.void, DECOR)
		Kit.ball(model, (base * CFrame.new(0.3, H, L / 2 - 1.2)).Position, 0.8, Palette.bone, DECOR)
		local lid = base * CFrame.new(W * 0.6, H + 0.4, -0.4) * CFrame.Angles(0, math.rad(random:NextNumber(8, 18)), math.rad(-8))
		Kit.part(model, lid, Vector3.new(W + 0.3, 0.45, L + 0.3), stone, { name = "Lid" })
		return model
	end
	Kit.part(model, base * CFrame.new(0, H + 0.22, 0), Vector3.new(W + 0.3, 0.45, L + 0.3), stone, { name = "Lid" })
	if opts.effigy ~= false then
		local top = H + 0.45
		Kit.part(model, base * CFrame.new(0, top + 0.3, 0.3), Vector3.new(1.4, 0.6, L * 0.45), stone, DECOR)
		Kit.ball(model, (base * CFrame.new(0, top + 0.45, L / 2 - 1)).Position, 0.95, stone, DECOR)
		Kit.part(model, base * CFrame.new(0, top + 0.7, 0.6), Vector3.new(0.5, 0.35, 0.7), stone, DECOR) -- mains jointes
		Kit.wedge(model, base * CFrame.new(0, top + 0.35, -L / 2 + 1.2), Vector3.new(1.2, 0.7, 1.4), stone, DECOR)
	end
	return model
end

-- Autel de pierre. Retourne le Model et la dalle supérieure (dessus à base.Y + ALTAR_HEIGHT).
function PropsSacred.altar(parent: Instance, base: CFrame, width: number, depth: number, look: Look?): (Model, Part)
	local stone = look or Palette.stone
	local model = Kit.model(parent, "Altar", base)
	Kit.part(model, base * CFrame.new(0, 0.25, 0), Vector3.new(width + 0.8, 0.5, depth + 0.8), Palette.darken(stone, 0.8))
	Kit.part(model, base * CFrame.new(0, 1.75, 0), Vector3.new(width, 2.5, depth), stone, { name = "Body" })
	local top = Kit.part(model, base * CFrame.new(0, 3.25, 0), Vector3.new(width + 0.6, 0.5, depth + 0.6), Palette.darken(stone, 1.1), { name = "AltarTop" })
	Kit.part(model, base * CFrame.new(0, 1.8, -depth / 2 - 0.05), Vector3.new(width * 0.6, 1.5, 0.1), Palette.darken(stone, 0.7), DECOR)
	return model, top
end

--[[
	Lutrin. Droit : le livre se pose sur le plateau incliné. `overturned` : couché au sol, le livre
	est tombé devant. Retourne le Model et le CFrame (LOCAL) où poser le livre.
]]
function PropsSacred.lectern(parent: Instance, base: CFrame, overturned: boolean?): (Model, CFrame)
	local model = Kit.model(parent, "Lectern", base)
	local u = if overturned then base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-86)) else base
	Kit.part(model, u * CFrame.new(0, 0.15, 0), Vector3.new(1.6, 0.3, 1.6), Palette.timber, DECOR)
	Kit.part(model, u * CFrame.new(0, 1.75, 0), Vector3.new(0.45, 3.2, 0.45), Palette.oldWood, { decor = overturned == true, name = "Post" })
	local board = u * CFrame.new(0, 3.5, 0) * CFrame.Angles(math.rad(25), 0, 0)
	Kit.part(model, board, Vector3.new(2.2, 0.2, 1.6), Palette.oldWood, DECOR)
	if overturned then
		return model, base * CFrame.new(1.4, 0.12, -2.3) * CFrame.Angles(0, math.rad(18), 0)
	end
	return model, board * CFrame.new(0, 0.16, 0)
end

-- Livre (ouvert : deux pages en V sur une couverture). Retourne la couverture (Part à viser).
function PropsSacred.book(parent: Instance, cframe: CFrame, open: boolean?): Part
	if not open then
		return Kit.part(parent, cframe * CFrame.new(0, 0.18, 0), Vector3.new(1.3, 0.35, 1.7), Palette.banner, { decor = true, name = "Book" })
	end
	local cover = Kit.part(parent, cframe * CFrame.new(0, 0.04, 0), Vector3.new(2, 0.08, 1.35), Palette.darken(Palette.banner, 0.7), { decor = true, name = "Book" })
	for _, side in { -1, 1 } do
		Kit.part(parent, cframe * CFrame.new(side * 0.47, 0.14, 0) * CFrame.Angles(0, 0, math.rad(side * 7)), Vector3.new(0.9, 0.12, 1.2), Palette.paper, DECOR)
	end
	return cover
end

-- Banc d'église ; `broken` : renversé ou dossier arraché.
function PropsSacred.pew(parent: Instance, base: CFrame, length: number, random: Random, broken: boolean?): Model
	local model = Kit.model(parent, "Pew", base)
	local frame = base
	if broken then
		frame = base * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(random:NextNumber(-70, -20)), math.rad(random:NextNumber(-15, 15)), 0)
	end
	local wood = Palette.burntWood
	Kit.part(model, frame * CFrame.new(0, 1.4, 0), Vector3.new(length, 0.3, 1.4), wood, { decor = broken == true, name = "Seat" })
	if not broken or random:NextNumber() < 0.5 then
		Kit.part(model, frame * CFrame.new(0, 2.4, 0.6), Vector3.new(length, 1.8, 0.25), wood, DECOR)
	end
	for _, x in { -length / 2 + 0.15, length / 2 - 0.15 } do
		Kit.part(model, frame * CFrame.new(x, 1.2, 0.1), Vector3.new(0.3, 2.4, 1.6), Palette.charredWood, DECOR)
	end
	return model
end

--[[
	Cloche de bronze suspendue. `hang` = point d'accroche (sommet), la cloche pend sous lui.
	`height` = hauteur de la cloche ; diamètre de la lèvre ~ 1,05 x height.
	Retourne le Model et le corps de la cloche.
]]
function PropsSacred.bell(parent: Instance, hang: CFrame, height: number, options: BellOptions?): (Model, Part)
	local opts: BellOptions = options or {}
	local h = height
	local d = h * 1.05
	local bronze = opts.look or Palette.bronze
	local model = Kit.model(parent, "Bell", hang)
	Kit.part(model, hang * CFrame.new(0, -0.25, 0), Vector3.new(0.5, 0.9, 0.35), Palette.iron, DECOR)
	Kit.ball(model, (hang * CFrame.new(0, -0.32 * h, 0)).Position, 0.64 * d, bronze, DECOR)
	local body = Kit.column(model, hang * CFrame.new(0, -0.86 * h, 0), 0.55 * h, 0.64 * d, bronze, { name = "BellBody" })
	Kit.column(model, hang * CFrame.new(0, -0.95 * h, 0), 0.14 * h, 0.84 * d, bronze, DECOR)
	Kit.column(model, hang * CFrame.new(0, -1.0 * h, 0), 0.08 * h, d, Palette.darken(bronze, 0.85), DECOR)
	if opts.cracked then
		-- Fissure de haut en bas sur la face avant (-Z), qui se prolonge sur la lèvre.
		local crack: Kit.PartOptions = { decor = true, name = "Crack" }
		Kit.part(model, hang * CFrame.new(0.04 * d, -0.6 * h, -0.32 * d - 0.04) * CFrame.Angles(0, 0, math.rad(5)), Vector3.new(0.14, 0.55 * h, 0.08), Palette.soot, crack)
		Kit.part(model, hang * CFrame.new(0.07 * d, -0.92 * h, -0.42 * d - 0.04) * CFrame.Angles(0, 0, math.rad(-8)), Vector3.new(0.14, 0.14 * h, 0.08), Palette.soot, crack)
		Kit.part(model, hang * CFrame.new(0.09 * d, -0.99 * h, -0.5 * d - 0.03), Vector3.new(0.18, 0.1 * h, 0.08), Palette.soot, crack)
	end
	return model, body
end

-- Échelle de fer contre un mur (le mur est du côté +Z de `foot`). Retourne le Model et un montant.
function PropsSacred.ladder(parent: Instance, foot: CFrame, height: number, width: number?): (Model, Part)
	local w = width or 2.2
	local model = Kit.model(parent, "Ladder", foot)
	local rail = Kit.part(model, foot * CFrame.new(-w / 2, height / 2, 0), Vector3.new(0.25, height, 0.25), Palette.rust, { name = "Rail" })
	Kit.part(model, foot * CFrame.new(w / 2, height / 2, 0), Vector3.new(0.25, height, 0.25), Palette.rust, { decor = true, name = "Rail" })
	local rungs = math.floor(height / 1.1)
	for i = 1, rungs do
		Kit.part(model, foot * CFrame.new(0, i * 1.1 - 0.4, 0), Vector3.new(w, 0.16, 0.16), Palette.iron, DECOR)
	end
	for _, y in { 1.5, height - 1.5 } do
		Kit.part(model, foot * CFrame.new(0, y, 0.45), Vector3.new(w + 0.6, 0.2, 0.7), Palette.iron, DECOR) -- pattes de scellement
	end
	return model, rail
end

-- Bibliothèque garnie (le dos est du côté +Z).
function PropsSacred.bookshelf(parent: Instance, base: CFrame, width: number, height: number, random: Random): Model
	local model = Kit.model(parent, "Bookshelf", base)
	local wood = Palette.oldWood
	for _, x in { -width / 2 + 0.15, width / 2 - 0.15 } do
		Kit.part(model, base * CFrame.new(x, height / 2, 0), Vector3.new(0.3, height, 1.4), wood)
	end
	Kit.part(model, base * CFrame.new(0, height - 0.15, 0), Vector3.new(width, 0.3, 1.4), wood, DECOR)
	Kit.part(model, base * CFrame.new(0, height / 2, 0.62), Vector3.new(width, height, 0.15), Palette.timber, DECOR)
	local bookLooks = { Palette.banner, Palette.bannerBlue, Palette.oldWood, Palette.clothDark, Palette.burntWood }
	local shelves = math.max(2, math.floor(height / 2.2))
	for s = 0, shelves - 1 do
		local y = 0.3 + s * (height - 0.6) / shelves
		Kit.part(model, base * CFrame.new(0, y, 0), Vector3.new(width - 0.6, 0.2, 1.3), wood, DECOR)
		local cursor = -width / 2 + 0.4
		while cursor < width / 2 - 1 do
			local w = random:NextNumber(0.8, 1.8)
			local hBooks = random:NextNumber(1, 1.6)
			if random:NextNumber() < 0.8 then
				local tilt = if random:NextNumber() < 0.15 then math.rad(20) else 0
				local cf = base * CFrame.new(cursor + w / 2, y + 0.1 + hBooks / 2, -0.05) * CFrame.Angles(0, 0, tilt)
				Kit.part(model, cf, Vector3.new(w, hBooks, 1), bookLooks[random:NextInteger(1, #bookLooks)], DECOR)
			end
			cursor += w + random:NextNumber(0.05, 0.5)
		end
	end
	return model
end

-- Candélabre de fer à trois bougies.
function PropsSacred.candelabrum(parent: Instance, base: CFrame, height: number, options: CandelabrumOptions?): Model
	local opts: CandelabrumOptions = options or {}
	local model = Kit.model(parent, "Candelabrum", base)
	Kit.part(model, base * CFrame.new(0, 0.1, 0), Vector3.new(1.2, 0.2, 1.2), Palette.iron, DECOR)
	Kit.rod(model, (base * CFrame.new(0, 0.2, 0)).Position, (base * CFrame.new(0, height, 0)).Position, 0.18, Palette.iron, DECOR)
	Kit.part(model, base * CFrame.new(0, height, 0), Vector3.new(2.2, 0.14, 0.14), Palette.iron, DECOR)
	local flame = if opts.cold then Palette.coldFlame else Palette.candleFlame
	for _, x in { -1, 0, 1 } do
		local cupY = height + (if x == 0 then 0.35 else 0)
		Kit.column(model, base * CFrame.new(x, cupY, 0), 0.8, 0.28, Palette.wax, DECOR)
		Kit.part(model, base * CFrame.new(x, cupY + 0.98, 0), Vector3.new(0.12, 0.3, 0.12), flame, { decor = true, name = "Flame" })
	end
	if opts.light then
		local holder = Kit.part(model, base * CFrame.new(0, height + 1.2, 0), Vector3.new(0.2, 0.2, 0.2), flame, { decor = true, transparency = 1, name = "LightHolder" })
		Kit.light(holder, {
			color = if opts.cold then Palette.colors.coldLight else Palette.colors.candleLight,
			brightness = if opts.cold then 1.3 else 1,
			range = 16,
		})
	end
	return model
end

-- Applique murale (torche en coupe). `mount` = point sur le mur, LookVector vers la pièce.
function PropsSacred.wallSconce(parent: Instance, mount: CFrame, options: SconceOptions?): Model
	local opts: SconceOptions = options or {}
	local model = Kit.model(parent, "Sconce", mount)
	Kit.part(model, mount * CFrame.new(0, 0, 0.05), Vector3.new(0.7, 1.2, 0.15), Palette.iron, DECOR)
	local cup = mount * CFrame.new(0, 0.35, -0.85)
	Kit.beam(model, (mount * CFrame.new(0, -0.3, 0)).Position, cup.Position, 0.18, 0.18, Palette.iron, DECOR)
	Kit.column(model, cup * CFrame.new(0, -0.2, 0), 0.4, 0.7, Palette.iron, DECOR)
	if opts.lit ~= false then
		local flame = Kit.part(model, cup * CFrame.new(0, 0.45, 0), Vector3.new(0.35, 0.6, 0.35), if opts.cold then Palette.coldFlame else Palette.ember, { decor = true, name = "Flame" })
		if opts.light then
			Kit.light(flame, {
				color = if opts.cold then Palette.colors.coldLight else Palette.colors.emberLight,
				brightness = if opts.cold then 1.4 else 1.2,
				range = opts.range or 18,
			})
		end
	end
	return model
end

--[[
	Vitrail gothique dans une ouverture de mur. `frame` = milieu du BAS de l'ouverture (dans le plan
	du mur), la face visible regarde vers -Z. `height` inclut l'arc brisé (hauteur = largeur / 2).
]]
function PropsSacred.gothicWindow(parent: Instance, frame: CFrame, width: number, height: number, glass: Look, options: WindowOptions?): Model
	local opts: WindowOptions = options or {}
	local model = Kit.model(parent, "GothicWindow", frame)
	local arch = width / 2
	local rect = math.max(0.5, height - arch)
	local glassOptions: Kit.PartOptions = { decor = true, transparency = 0.25 }
	local broken = opts.broken == true and opts.random ~= nil
	local keep = if broken and opts.random then opts.random:NextNumber(0.25, 0.6) else 1
	Kit.part(model, frame * CFrame.new(0, rect * keep / 2, 0), Vector3.new(width, rect * keep, 0.15), glass, glassOptions)
	if not broken then
		for _, side in { -1, 1 } do
			local size = Vector3.new(0.15, arch, width / 2)
			Kit.wedge(model, frame * CFrame.new(side * width / 4, rect + arch / 2, 0) * CFrame.Angles(0, math.rad(-side * 90), 0), size, glass, glassOptions)
		end
	elseif opts.random then
		-- Éclats restés pris dans le plomb.
		for _ = 1, 2 do
			local x = opts.random:NextNumber(-width / 3, width / 3)
			local y = rect * keep + opts.random:NextNumber(0.2, 1)
			Kit.wedge(model, frame * CFrame.new(x, y, 0) * CFrame.Angles(0, math.rad(90), math.rad(opts.random:NextNumber(-20, 20))), Vector3.new(0.12, 0.9, 0.6), glass, glassOptions)
		end
	end
	Kit.part(model, frame * CFrame.new(0, height / 2, 0), Vector3.new(0.3, height, 0.3), Palette.stoneLight, DECOR)
	Kit.part(model, frame * CFrame.new(0, rect, 0), Vector3.new(width, 0.25, 0.3), Palette.stoneLight, DECOR)
	return model
end

--------------------------------------------------------------------------------
-- Mausolée
--------------------------------------------------------------------------------

--[[
	Mausolée de pierre à porche : socle, deux colonnes, fronton, toit plat, porte ouverte
	(l'ouverture se ferme par un voile ou une porte construits par la zone, voir `doorway`).
	~35 Parts.
]]
function PropsSacred.mausoleum(parent: Instance, base: CFrame, random: Random, options: MausoleumOptions?): MausoleumResult
	local opts: MausoleumOptions = options or {}
	local W = opts.width or 12
	local D = opts.depth or 14
	local H = opts.height or 9
	local stone = opts.look or Palette.stone
	local t = 1.2
	local P = 1
	local porch = 3.4
	local model = Kit.model(parent, "Mausoleum", base)

	-- Socle (enfoncé), porche et marche (0,5 stud chacune).
	Kit.part(model, base * CFrame.new(0, (P - 1.5) / 2, -porch / 2), Vector3.new(W + 1, P + 1.5, D + porch + 1), Palette.darken(stone, 0.8), { name = "Plinth" })
	Kit.part(model, base * CFrame.new(0, 0, -D / 2 - porch - 1.2), Vector3.new(6, 1, 1.6), Palette.stoneLight, { name = "Step" })

	-- Murs (pierre, sans ossature) ; porte à l'avant.
	local floor = base * CFrame.new(0, P, 0)
	local door = { x0 = -2.2, x1 = 2.2, y0 = 0, y1 = 7, kind = "door" :: "door" }
	PropsBuildings.panelWall(model, floor * CFrame.new(0, 0, -D / 2 + t / 2), W, H, { door }, stone, nil, { thickness = t })
	PropsBuildings.panelWall(model, floor * CFrame.new(0, 0, D / 2 - t / 2) * CFrame.Angles(0, math.pi, 0), W, H, {}, stone, nil, { thickness = t })
	for _, side in { -1, 1 } do
		local slit = { x0 = -0.35, x1 = 0.35, y0 = 4, y1 = 6.6, kind = "window" :: "window" }
		PropsBuildings.panelWall(model, floor * CFrame.new(side * (W / 2 - t / 2), 0, 0) * CFrame.Angles(0, math.rad(-side * 90), 0), D - 2 * t, H, { slit }, stone, nil, { thickness = t })
	end
	Kit.part(model, floor * CFrame.new(0, 0.1, 0), Vector3.new(W - 2 * t, 0.2, D - 2 * t), Palette.marble, DECOR)

	-- Encadrement de la porte et inscription.
	local doorFrame = floor * CFrame.new(0, 0, -D / 2 - 0.15)
	for _, x in { -2.6, 2.6 } do
		Kit.part(model, doorFrame * CFrame.new(x, 3.6, 0), Vector3.new(0.8, 7.2, 0.4), Palette.darken(stone, 0.75), DECOR)
	end
	local lintel = Kit.part(model, doorFrame * CFrame.new(0, 7.5, 0), Vector3.new(6, 1, 0.45), Palette.darken(stone, 0.75), { name = "Lintel" })
	if opts.inscription then
		Kit.surfaceText(lintel, Enum.NormalId.Front, opts.inscription, { color = Palette.colors.chalk, pixelsPerStud = 30 })
	end

	-- Toit plat débordant (couvre le porche), corniche et frontons.
	local roofY = P + H + 0.4
	Kit.part(model, base * CFrame.new(0, roofY, -porch / 2), Vector3.new(W + 1.2, 0.8, D + porch + 1.2), Palette.darken(stone, 0.85), { name = "Roof" })
	Kit.part(model, base * CFrame.new(0, roofY - 0.6, -porch / 2), Vector3.new(W + 0.6, 0.4, D + porch + 0.6), Palette.darken(stone, 0.7), DECOR)
	PropsBuildings.gable(model, base * CFrame.new(0, roofY + 0.4, -D / 2 - porch - 0.1), W + 1.2, 3, 1, stone)
	PropsBuildings.gable(model, base * CFrame.new(0, roofY + 0.4, D / 2 + 0.1) * CFrame.Angles(0, math.pi, 0), W + 1.2, 3, 1, stone)
	Kit.part(model, base * CFrame.new(0, roofY + 1.9, -porch / 2), Vector3.new(0.8, 0.6, D + porch + 1.2), Palette.darken(stone, 0.7), DECOR)

	-- Colonnes du porche, urnes de part et d'autre de la marche.
	for _, side in { -1, 1 } do
		PropsBuildings.pillar(model, base * CFrame.new(side * (W / 2 - 0.8), P, -D / 2 - porch + 0.9), H, 1.4, stone)
		local urn = base * CFrame.new(side * 3.6, 0, -D / 2 - porch - 1.6)
		Kit.column(model, urn, 0.9, 1.1, Palette.darken(stone, 0.7), DECOR)
		Kit.ball(model, (urn * CFrame.new(0, 1.4, 0)).Position, 1.1, Palette.bronzeDark, DECOR)
	end
	local _ = random
	return {
		model = model,
		floorY = P,
		doorway = floor * CFrame.new(0, 0, -D / 2),
		doorSize = Vector3.new(4.4, 7, t),
		interior = floor * CFrame.new(0, 0, 0.5),
		approach = base * CFrame.new(0, 0, -D / 2 - porch - 3.5),
	}
end

-- Tas d'ossements : crâne et os épars (décor pur).
function PropsSacred.boneHeap(parent: Instance, base: CFrame, size: number, random: Random): Model
	local model = Kit.model(parent, "BoneHeap", base)
	Kit.wedge(model, base * CFrame.new(0, size * 0.15, 0) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), Vector3.new(size, size * 0.3, size * 0.8), Palette.ashDark, DECOR)
	Kit.ball(model, (base * CFrame.new(random:NextNumber(-0.3, 0.3) * size, size * 0.32, 0)).Position, 0.75, Palette.bone, DECOR)
	for _ = 1, 4 do
		local a = base * CFrame.new(random:NextNumber(-0.5, 0.5) * size, 0.2, random:NextNumber(-0.5, 0.5) * size)
		local b = a * CFrame.Angles(0, random:NextNumber(0, 6.28), 0) * CFrame.new(0, random:NextNumber(0, 0.4), random:NextNumber(1, 1.8))
		Kit.rod(model, a.Position, b.Position, 0.22, Palette.bone, DECOR)
	end
	return model
end

return table.freeze(PropsSacred)
