--!strict
--[[
	AvatarCreatorCatalog
	Décrit les étapes du créateur de personnage à partir des catalogues partagés (AvatarConfig,
	MagicConfig) : ce qu'affiche chaque onglet, quel champ du Selection il modifie, quel plan de
	caméra il demande et comment dessiner la vignette de chaque option.

	Tout est DÉRIVÉ des listes d'AvatarConfig : ajouter une coiffure (une ligne dans HAIR_OPTIONS)
	l'ajoute au créateur, vignette comprise, sans rien toucher ici. Aucun ID d'asset n'est écrit dans
	ce fichier : les vignettes réutilisent uniquement les ID déjà présents dans AvatarConfig.
		- coiffures et tenues : vignette officielle Roblox de l'asset (rbxthumb://type=Asset...) ;
		- visages et marques : l'image déjà référencée par l'option, posée sur une pastille couleur peau ;
		- corps : médaillon dessiné (initiale), faute d'image dédiée dans la configuration.

	Ajouter une catégorie (c'est ainsi qu'ont été ajoutés le peuple et le teint) :
		1. la liste dans AvatarConfig + le champ dans Selection (côté serveur : AvatarSerializer et
		   AvatarAppearance) ;
		2. une entrée dans STEPS ci-dessous (kind = "list", avec get / set et une vignette).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Avatar"):WaitForChild("AvatarConfig"))
local RaceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Avatar"):WaitForChild("RaceConfig"))

type Selection = AvatarConfig.Selection

-- Plan de caméra demandé par une étape (voir AvatarCreatorCamera).
export type Shot = "body" | "face" | "destiny" | "summary"

export type StepKind = "list" | "proportions" | "destiny" | "summary"

-- Vignette d'une option :
--   "image"     : image complète (vignette d'asset), `inset` = petite image en coin (cape d'une tenue)
--   "face"      : image transparente posée sur une pastille couleur peau (visage, marque)
--   "medallion" : médaillon dessiné portant `text` (une initiale)
--   "none"      : pastille vide (option "aucune")
--   "swatch"    : pastille de couleur `color` (teint) ; sans couleur, médaillon portant `text`
export type ThumbnailKind = "image" | "face" | "medallion" | "none" | "swatch"

export type Thumbnail = {
	kind: ThumbnailKind,
	image: string?,
	inset: string?,
	text: string?,
	color: Color3?,
}

export type OptionEntry = {
	name: string,
	thumbnail: Thumbnail,
	description: string?, -- texte riche affiché sous le nom (peuples : récit, avantage, inconvénient)
}

-- Étape "liste" : une option à choisir parmi `options`, rangée dans un champ du Selection.
export type ListSpec = {
	options: { OptionEntry },
	get: (selection: Selection) -> number,
	set: (selection: Selection, index: number) -> (),
}

export type Step = {
	id: string,
	kind: StepKind,
	numeral: string, -- chiffre romain de l'onglet
	label: string, -- nom court (onglet, récapitulatif)
	title: string, -- titre du panneau
	subtitle: string,
	shot: Shot,
	list: ListSpec?, -- seulement pour kind == "list"
}

local AvatarCreatorCatalog = {}

--------------------------------------------------------------------------------
-- Vignettes
--------------------------------------------------------------------------------

local THUMBNAIL_SIZE = 150 -- taille officielle prise en charge par rbxthumb pour type=Asset

-- Vignette officielle d'un asset du catalogue dont l'ID figure DÉJÀ dans AvatarConfig.
local function assetThumbnail(assetId: number): string
	return `rbxthumb://type=Asset&id={assetId}&w={THUMBNAIL_SIZE}&h={THUMBNAIL_SIZE}`
end

-- Première lettre d'un nom (UTF-8 : "Écuyer" donne "É").
local function initial(name: string): string
	local isValid, codepoint = pcall(utf8.codepoint, name, 1)
	if isValid and type(codepoint) == "number" then
		return utf8.char(codepoint)
	end
	return string.sub(name, 1, 1)
end

-- Texte riche d'un peuple : épithète, récit, avantage (vert), inconvénient (rouge), origine.
local function describeRace(race: RaceConfig.Race): string
	local origin = if race.originAvailable
		then `Origine : {race.originName}.`
		else `Origine : {race.originName} — terres pas encore accessibles : vous commencerez au Belvédère.`
	return table.concat({
		`<i>{race.epithet}</i>`,
		race.lore,
		`<font color="#92CE78">✦ {race.advantage}</font>`,
		`<font color="#DE584C">✧ {race.drawback}</font>`,
		`<font color="#B0A89C">{origin}</font>`,
	}, "\n")
end

local function buildRaceOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, race in RaceConfig.RACES do
		entries[index] = {
			name = race.name,
			thumbnail = { kind = "medallion", text = initial(race.name) },
			description = describeRace(race),
		}
	end
	return entries
end

local function buildSkinOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, tone in AvatarConfig.SKIN_TONES do
		entries[index] = { name = tone.name, thumbnail = { kind = "swatch", color = tone.color, text = "★" } }
	end
	return entries
end

local function buildBaseOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, option in AvatarConfig.BASE_OPTIONS do
		entries[index] = { name = option.name, thumbnail = { kind = "medallion", text = initial(option.name) } }
	end
	return entries
end

local function buildFaceOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, option in AvatarConfig.FACE_OPTIONS do
		entries[index] = { name = option.name, thumbnail = { kind = "face", image = option.texture } }
	end
	return entries
end

local function buildMarkOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, option in AvatarConfig.MARK_OPTIONS do
		local thumbnail: Thumbnail = if option.texture == ""
			then { kind = "none" }
			else { kind = "face", image = option.texture }
		entries[index] = { name = option.name, thumbnail = thumbnail }
	end
	return entries
end

local function buildHairOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, option in AvatarConfig.HAIR_OPTIONS do
		entries[index] = { name = option.name, thumbnail = { kind = "image", image = assetThumbnail(option.assetId) } }
	end
	return entries
end

local function buildOutfitOptions(): { OptionEntry }
	local entries: { OptionEntry } = {}
	for index, option in AvatarConfig.OUTFIT_OPTIONS do
		entries[index] = {
			name = option.name,
			thumbnail = {
				kind = "image",
				image = assetThumbnail(option.shirtId),
				inset = if option.backAccessoryId > 0 then assetThumbnail(option.backAccessoryId) else nil,
			},
		}
	end
	return entries
end

--------------------------------------------------------------------------------
-- Étapes, dans l'ordre du parcours
--------------------------------------------------------------------------------

local STEPS: { Step } = {
	{
		id = "race",
		kind = "list",
		numeral = "",
		label = "Origine",
		title = "Peuple et origine",
		subtitle = "D'où venez-vous, avant que le temps ne s'arrête ?",
		shot = "body",
		list = {
			options = buildRaceOptions(),
			get = function(selection: Selection): number
				return selection.raceIndex
			end,
			set = function(selection: Selection, index: number)
				selection.raceIndex = index
			end,
		},
	},
	{
		id = "base",
		kind = "list",
		numeral = "",
		label = "Corps",
		title = "Corps",
		subtitle = "L'enveloppe qui vous fut rendue.",
		shot = "body",
		list = {
			options = buildBaseOptions(),
			get = function(selection: Selection): number
				return selection.baseIndex
			end,
			set = function(selection: Selection, index: number)
				selection.baseIndex = index
			end,
		},
	},
	{
		id = "skin",
		kind = "list",
		numeral = "",
		label = "Teint",
		title = "Teint",
		subtitle = "La couleur de votre peau, du visage aux mains.",
		shot = "face",
		list = {
			options = buildSkinOptions(),
			get = function(selection: Selection): number
				return selection.skinIndex
			end,
			set = function(selection: Selection, index: number)
				selection.skinIndex = index
			end,
		},
	},
	{
		id = "face",
		kind = "list",
		numeral = "",
		label = "Visage",
		title = "Visage",
		subtitle = "Le dernier visage dont vous vous souvenez.",
		shot = "face",
		list = {
			options = buildFaceOptions(),
			get = function(selection: Selection): number
				return selection.faceIndex
			end,
			set = function(selection: Selection, index: number)
				selection.faceIndex = index
			end,
		},
	},
	{
		id = "mark",
		kind = "list",
		numeral = "",
		label = "Marques",
		title = "Cicatrices et tatouages",
		subtitle = "Ce que la vie, ou la mort, a gravé sur vous.",
		shot = "face",
		list = {
			options = buildMarkOptions(),
			get = function(selection: Selection): number
				return selection.markIndex
			end,
			set = function(selection: Selection, index: number)
				selection.markIndex = index
			end,
		},
	},
	{
		id = "hair",
		kind = "list",
		numeral = "",
		label = "Chevelure",
		title = "Chevelure",
		subtitle = "Ce que le vent n'a pas emporté.",
		shot = "face",
		list = {
			options = buildHairOptions(),
			get = function(selection: Selection): number
				return selection.hairIndex
			end,
			set = function(selection: Selection, index: number)
				selection.hairIndex = index
			end,
		},
	},
	{
		id = "outfit",
		kind = "list",
		numeral = "",
		label = "Tenue",
		title = "Tenue",
		subtitle = "Les habits de votre dernier voyage.",
		shot = "body",
		list = {
			options = buildOutfitOptions(),
			get = function(selection: Selection): number
				return selection.outfitIndex
			end,
			set = function(selection: Selection, index: number)
				selection.outfitIndex = index
			end,
		},
	},
	{
		id = "proportions",
		kind = "proportions",
		numeral = "",
		label = "Proportions",
		title = "Proportions",
		subtitle = "Votre stature, telle que le monde s'en souvient.",
		shot = "body",
	},
	{
		id = "destiny",
		kind = "destiny",
		numeral = "",
		label = "Destin",
		title = "Le Choix du Destin",
		subtitle = "Une seule magie coule dans vos veines.",
		shot = "destiny",
	},
	{
		id = "summary",
		kind = "summary",
		numeral = "",
		label = "Récapitulatif",
		title = "Récapitulatif",
		subtitle = "Relisez-vous avant de rouvrir les yeux.",
		shot = "summary",
	},
}

-- Chiffres romains des onglets, calculés dans l'ordre (ajouter une étape ne demande rien d'autre).
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
for index, step in STEPS do
	step.numeral = ROMAN[index] or tostring(index)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

AvatarCreatorCatalog.STEPS = STEPS

-- Index de la première étape d'un type donné (nil si absente).
function AvatarCreatorCatalog.findStep(kind: StepKind): number?
	for index, step in STEPS do
		if step.kind == kind then
			return index
		end
	end
	return nil
end

-- Nombre d'étapes d'apparence (avant le Destin) : pour "II / VI".
function AvatarCreatorCatalog.countAppearanceSteps(): number
	local count = 0
	for _, step in STEPS do
		if step.kind == "list" or step.kind == "proportions" then
			count += 1
		end
	end
	return count
end

-- Échelle affichée en pourcentage : 1.05 -> "105 %".
function AvatarCreatorCatalog.formatScale(value: number): string
	return `{math.round(value * 100)} %`
end

-- Valeur lisible d'une étape pour le récapitulatif.
function AvatarCreatorCatalog.describe(step: Step, selection: Selection): string
	local list = step.list
	if list then
		local entry = list.options[list.get(selection)]
		return if entry then entry.name else "?"
	end
	if step.kind == "proportions" then
		local height = AvatarCreatorCatalog.formatScale(selection.heightScale)
		local width = AvatarCreatorCatalog.formatScale(selection.widthScale)
		return `Taille {height} · Carrure {width}`
	end
	return ""
end

-- Choix de départ : la première option de chaque liste et les échelles par défaut.
function AvatarCreatorCatalog.defaultSelection(): Selection
	return {
		baseIndex = 1,
		faceIndex = 1,
		markIndex = 1,
		hairIndex = 1,
		outfitIndex = 1,
		heightScale = AvatarConfig.HEIGHT_SCALE.default,
		widthScale = AvatarConfig.WIDTH_SCALE.default,
		magicIndex = 1,
		raceIndex = RaceConfig.indexOf(RaceConfig.DEFAULT_RACE_ID),
		skinIndex = 1,
	}
end

return AvatarCreatorCatalog
